#!/usr/bin/env bash
set -uo pipefail
# coherence-court.sh — SE-350: Coherence Court (jueces transversales de consistencia entre etapas)
# Extrae el patrón "jueces paralelos + scoring + gate" de Code Review Court a un
# componente transversal, desacoplado del dominio de código. Audita la coherencia
# relativa entre la salida de la etapa actual y las premisas/decisiones fijadas en
# etapas anteriores del mismo flujo.
#
# Ref: docs/specs/SE-350-coherence-court.spec.md
# Espejo de: scripts/court-review.sh (Code Review Court) y court-score-aggregator.sh.
#
# Subcomandos:
#   check     [--flow F] [--stage-output FILE]   → gate de flujo multi-etapa
#   premises  <flow> init|add|list|show|clear    → registro de premisas (JSONL)
#   skeleton  <flow> <stage_output>              → genera .coherence.crc skeleton
#   score     C H M L                            → score 0-100
#   gate      <score> [--threshold N] [--conditional N] → puerta humana
#   hash      FILE                               → SHA-256

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}}}"

COHERENCE_SCORE_PASS="${COHERENCE_SCORE_PASS:-90}"
COHERENCE_SCORE_CONDITIONAL="${COHERENCE_SCORE_CONDITIONAL:-70}"
COHERENCE_PREMISES_DIR="${COHERENCE_PREMISES_DIR:-$WORKSPACE_DIR/data}"

die() { echo "ERROR: $*" >&2; exit 1; }

_py3() { command -v python3 &>/dev/null; }

# Enteros no negativos validados ANTES de cualquier contexto aritmético:
# $(( )) y [[ -ge ]] evalúan subíndices, así que "HOME[$(cmd)]" ejecutaría cmd.
_require_uint() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be a non-negative integer: '$value'"
}

# El flujo forma parte del nombre de fichero: sin "/" no puede salir del directorio.
_require_flow() {
  local flow="$1"
  [[ -n "$flow" ]] || die "flow name is required"
  [[ "$flow" != */* && "$flow" != *$'\n'* ]] || die "invalid flow name '$flow' (no '/' or newlines)"
}

# Valor obligatorio de una opción: evita el aborto opaco de set -u con "$2".
_need_value() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value"
}

_premises_file() {
  local flow="$1"
  echo "$COHERENCE_PREMISES_DIR/coherence-premises-${flow}.jsonl"
}

_ensure_premises() {
  local flow="$1"
  local file
  file="$(_premises_file "$flow")"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  [[ -f "$file" ]] || touch "$file"
}

_count_premises() {
  local flow="$1" file
  file="$(_premises_file "$flow")"
  [[ -f "$file" ]] || { echo 0; return; }
  python3 - "$file" <<'PY'
import sys, json
n = 0
try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            try: json.loads(line); n += 1
            except Exception: pass
except Exception: pass
print(n)
PY
}

cmd_check() {
  local flow="" stage_output=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --flow)        _need_value "$@"; flow="$2"; shift 2 ;;
      --stage-output) _need_value "$@"; stage_output="$2"; shift 2 ;;
      --help|-h)     usage; exit 0 ;;
      *)             die "Unknown arg: $1" ;;
    esac
  done
  [[ -z "$flow" ]] && die "check requires --flow"
  [[ -z "$stage_output" ]] && die "check requires --stage-output"
  [[ -f "$stage_output" ]] || die "stage_output not found: $stage_output"
  _require_flow "$flow"

  local n
  n="$(_count_premises "$flow")"
  if [[ "$n" -lt 1 ]]; then
    echo "FAIL: flow '$flow' has $n premises — no prior stage to compare against (single-stage flow)."
    echo "Register premises with: coherence-court.sh premises $flow add <kind> <content>"
    exit 1
  fi
  echo "PASS: flow '$flow' has $n premise(s); stage output present ($stage_output)"
}

cmd_premises() {
  local flow="${1:-}" sub="${2:-}"
  [[ -z "$flow" ]] && die "Usage: coherence-court.sh premises <flow> init|add|list|show|clear"
  _require_flow "$flow"
  local file
  file="$(_premises_file "$flow")"

  case "$sub" in
    init)
      _ensure_premises "$flow"
      echo "initialized: $file"
      ;;
    add)
      local kind="${3:-}" content="${4:-}" stage="stage-1" source="" premise_id=""
      shift 4 || shift "$#"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --stage) _need_value "$@"; stage="$2"; shift 2 ;;
          --source) _need_value "$@"; source="$2"; shift 2 ;;
          --id) _need_value "$@"; premise_id="$2"; shift 2 ;;
          *) die "Unknown arg: $1" ;;
        esac
      done
      [[ -z "$kind" ]] && die "premises add requires <kind> (fact|constraint|objective|decision)"
      case "$kind" in
        fact|constraint|objective|decision) ;;
        *) die "Invalid kind '$kind' (allowed: fact|constraint|objective|decision)" ;;
      esac
      [[ -z "$content" ]] && die "premises add requires <content>"
      _ensure_premises "$flow"
      _py3 || die "python3 required for premises add"
      python3 - "$file" "$flow" "$stage" "$kind" "$content" "$source" "$premise_id" <<'PY'
import sys, json, uuid
file, flow, stage, kind, content, source, premise_id = sys.argv[1:8]
rec = {
    "schema_version": "1",
    "premise_id": premise_id or uuid.uuid4().hex[:12],
    "flow": flow,
    "stage": stage,
    "kind": kind,
    "content": content,
    "source": source or None,
    "added_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec) + "\n")
print(rec["premise_id"])
PY
      ;;
    list)
      local as_json=0
      shift 2 || shift "$#"
      [[ "${1:-}" == "--json" ]] && as_json=1
      [[ -f "$file" ]] || die "No premises registry for flow '$flow' (run init)"
      python3 - "$file" "$as_json" <<'PY'
import sys, json
file, as_json = sys.argv[1], int(sys.argv[2])
rows = []
try:
    with open(file, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            try: rows.append(json.loads(line))
            except Exception: pass
except Exception: pass
if as_json:
    print(json.dumps(rows, indent=2))
else:
    for r in rows:
        print(f"{r['premise_id']}  [{r['kind']}] stage={r.get('stage','')}  {r['content']}")
PY
      ;;
    show)
      local pid="${3:-}"
      [[ -z "$pid" ]] && die "premises show requires <premise_id>"
      [[ -f "$file" ]] || die "No premises registry for flow '$flow'"
      python3 - "$file" "$pid" <<'PY'
import sys, json
file, pid = sys.argv[1], sys.argv[2]
found = None
try:
    with open(file, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            try:
                r = json.loads(line)
                if r.get("premise_id") == pid: found = r
            except Exception: pass
except Exception: pass
if found is None:
    print(f"ERROR: premise {pid} not found", file=sys.stderr)
    sys.exit(1)
print(json.dumps(found, indent=2, ensure_ascii=False))
PY
      ;;
    clear)
      _ensure_premises "$flow"
      : > "$file"
      echo "cleared: $file"
      ;;
    *)
      echo "Usage: coherence-court.sh premises <flow> {init|add|list|show|clear}" >&2
      exit 2
      ;;
  esac
}

# Cadena YAML segura: JSON es un subconjunto de YAML y escapa comillas y saltos.
_yaml_str() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

cmd_skeleton() {
  local flow="${1:-}" stage_output="${2:-}"
  [[ -z "$flow" ]] && die "skeleton requires <flow>"
  [[ -z "$stage_output" ]] && die "skeleton requires <stage_output>"
  [[ -f "$stage_output" ]] || die "stage_output not found: $stage_output"
  _require_flow "$flow"

  local sha
  sha=$(sha256sum "$stage_output" 2>/dev/null | awk '{print $1}') || sha="unknown"
  local n
  n="$(_count_premises "$flow")"

  cat <<EOF
---
court_id: "COH-$(date +%Y-%m%d)-001"
flow_ref: $(_yaml_str "$flow")
stage_ref: "current"
premises_count: $n
checked_at: "$(date -Iseconds)"
court_round: 1
stage_output:
  - path: $(_yaml_str "$stage_output")
    sha256: "$sha"
    findings: []
    status: "pending"
judges:
  coherence-factual: { verdict: "pending", findings_count: 0 }
  coherence-scope: { verdict: "pending", findings_count: 0 }
  coherence-objectives: { verdict: "pending", findings_count: 0 }
  coherence-premise-drift: { verdict: "pending", findings_count: 0 }
consolidated:
  verdict: "pending"
  total_findings: 0
  blocking: 0
  advisory: 0
  score: 0
premises:
$(python3 - "$(_premises_file "$flow")" "$n" <<'PY'
import sys, json
file, n = sys.argv[1], int(sys.argv[2])
out = []
try:
    with open(file, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            try:
                r = json.loads(line)
                q = lambda v: json.dumps(str(v), ensure_ascii=False)
                out.append(f"  - id: {q(r.get('premise_id',''))}\n    kind: {q(r.get('kind',''))}\n    content: {q(r.get('content',''))}")
            except Exception: pass
except Exception: pass
print("\n".join(out) if out else "  []")
PY
)
rounds: []
signature:
  hash: ""
  reviewed_by: "coherence-court-v1"
---
EOF
}

cmd_score() {
  local c="${1:-0}" h="${2:-0}" m="${3:-0}" l="${4:-0}"
  _require_uint C "$c"; _require_uint H "$h"; _require_uint M "$m"; _require_uint L "$l"
  _require_uint COHERENCE_SCORE_PASS "$COHERENCE_SCORE_PASS"
  _require_uint COHERENCE_SCORE_CONDITIONAL "$COHERENCE_SCORE_CONDITIONAL"
  local score=$((100 - c * 25 - h * 10 - m * 3 - l * 1))
  [[ "$score" -lt 0 ]] && score=0

  local verdict
  if [[ "$score" -ge "$COHERENCE_SCORE_PASS" ]]; then
    verdict="pass"
  elif [[ "$score" -ge "$COHERENCE_SCORE_CONDITIONAL" ]]; then
    verdict="conditional"
  else
    verdict="fail"
  fi

  echo "score=$score verdict=$verdict (C=$c H=$h M=$m L=$l)"
}

cmd_gate() {
  local score="${1:-}" threshold="$COHERENCE_SCORE_PASS" conditional="$COHERENCE_SCORE_CONDITIONAL"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold)   _need_value "$@"; threshold="$2"; shift 2 ;;
      --conditional) _need_value "$@"; conditional="$2"; shift 2 ;;
      --help|-h)     echo "Usage: coherence-court.sh gate <score> [--threshold N] [--conditional N]"; exit 0 ;;
      *) score="$1"; shift ;;
    esac
  done
  [[ -z "$score" ]] && die "gate requires <score>"
  [[ "$score" =~ ^[0-9]+$ ]] || die "score must be an integer: '$score'"
  _require_uint threshold "$threshold"
  _require_uint conditional "$conditional"
  [[ "$conditional" -le "$threshold" ]] || die "conditional threshold ($conditional) must be <= pass threshold ($threshold)"

  if [[ "$score" -ge "$threshold" ]]; then
    echo "PASS: score=$score >= $threshold — coherent. Continuar el flujo (revisión humana ligera)."
    exit 0
  elif [[ "$score" -ge "$conditional" ]]; then
    echo "CONDITIONAL: score=$score >= $conditional < $threshold — revisar discrepancias antes de continuar."
    exit 2
  else
    echo "FAIL: score=$score < $conditional — puerta humana: NO continuar el flujo hasta resolver discrepancias."
    exit 1
  fi
}

cmd_hash() {
  local file="${1:-}"
  [[ -z "$file" ]] && die "Usage: coherence-court.sh hash FILE"
  [[ -f "$file" ]] || die "File not found: $file"
  sha256sum "$file" | awk '{print $1}'
}

usage() {
  cat <<EOF
coherence-court.sh — SE-350 Coherence Court

Usage:
  coherence-court.sh check [--flow F] [--stage-output FILE]
  coherence-court.sh premises <flow> {init|add|list|show|clear}
  coherence-court.sh skeleton <flow> <stage_output>
  coherence-court.sh score C H M L
  coherence-court.sh gate <score> [--threshold N] [--conditional N]
  coherence-court.sh hash FILE

Environment:
  COHERENCE_SCORE_PASS          global pass threshold (default 90)
  COHERENCE_SCORE_CONDITIONAL   global conditional threshold (default 70)
  COHERENCE_PREMISES_DIR        premises dir (default <workspace>/data)
EOF
}

case "${1:-}" in
  check)    shift; cmd_check "$@" ;;
  premises) shift; cmd_premises "$@" ;;
  skeleton) shift; cmd_skeleton "$@" ;;
  score)    shift; cmd_score "$@" ;;
  gate)     shift; cmd_gate "$@" ;;
  hash)     shift; cmd_hash "$@" ;;
  --help|-h) usage ;;
  *)        echo "Usage: coherence-court.sh {check|premises|skeleton|score|gate|hash}" >&2; exit 2 ;;
esac
