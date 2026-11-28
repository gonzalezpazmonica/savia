#!/usr/bin/env bash
# corporate-adopt.sh — SE-271 S2
# Presents a corporate body entry by entry. Runs monotonicity gate.
# Shows conflicts with personal criterion. Requires human signature per entry.
# Records declinations with reason. Writes to append-only hash-chained ledger.
# Command: /corporate-adopt <body>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GATE_SCRIPT="${GATE_SCRIPT:-$SCRIPT_DIR/corporate-monotonicity-gate.sh}"
CRITERIO="${CRITERIO:-$REPO_ROOT/CRITERIO.md}"
LEDGER_DIR="${LEDGER_DIR:-$REPO_ROOT/data/corporate}"
LEDGER="${LEDGER:-$LEDGER_DIR/adoption-ledger.jsonl}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <body.card.json>

Presents a corporate criterion body entry by entry for adoption.
Runs monotonicity gate before presenting. Shows conflicts with
existing personal criterion. Requires human signature per entry.

Arguments:
  body.card.json   Path to the corporate body card.

Exit codes:
  0   Adoption complete (all presented entries processed).
  1   Body failed monotonicity gate (cannot be presented).
  2   Usage error.
EOF
  exit 2
}

# ── helpers ──────────────────────────────────────────────────────────────

write_ledger_entry() {
  local entry_id="$1"
  local action="$2"
  local reason="$3"
  local signature="$4"
  local body_id="$5"
  local body_version="$6"

  mkdir -p "$LEDGER_DIR"

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local prev_hash="genesis"
  if [[ -f "$LEDGER" && -s "$LEDGER" ]]; then
    prev_hash=$(sha256sum "$LEDGER" | awk '{print $1}')
  fi

  # Los valores (id y body_id vienen de la tarjeta externa) van por argv.
  python3 -c '
import json, sys
keys = ("entry_id", "action", "reason", "signature", "body_id",
        "body_version", "prev_ledger_hash", "timestamp")
print(json.dumps(dict(zip(keys, sys.argv[1:9])), ensure_ascii=False))
' "$entry_id" "$action" "$reason" "$signature" "$body_id" "$body_version" "$prev_hash" "$ts" \
    >> "$LEDGER" 2>/dev/null || true
}

detect_conflicts() {
  local entry_json="$1"

  local entry_id ambito principio
  entry_id=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  ambito=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ambito',''))" 2>/dev/null || echo "")
  principio=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('principio',''))" 2>/dev/null || echo "")

  local conflicts=""

  # Check against personal criterion entries in same ambito
  if [[ -f "$CRITERIO" ]]; then
    # Find existing entries in same ambito
    local same_scope
    # ambito viene de la tarjeta externa: por argv y escapado como literal.
    # Antes {ambito} era una variable de Python inexistente y nunca había conflictos.
    same_scope=$(python3 -c '
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
ambito = sys.argv[2]
if not ambito:
    sys.exit()
# Find all CRIT entries in same ambito
pattern = r"(CRIT-\d+)\s*—.*\n.*ambito.*" + re.escape(ambito)
matches = re.findall(pattern, content, re.IGNORECASE)
if matches:
    print(",".join(matches))
' "$CRITERIO" "$ambito" 2>/dev/null)

    if [[ -n "$same_scope" ]]; then
      conflicts="Personal criterion in same ambito ($ambito): $same_scope"
    fi
  fi

  echo "$conflicts"
}

prompt_entry() {
  local entry_json="$1"
  local body_id="$2"
  local body_version="$3"

  local entry_id dureza ambito principio ej contraej enforcement
  entry_id=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  dureza=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('dureza',''))" 2>/dev/null || echo "")
  ambito=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ambito',''))" 2>/dev/null || echo "")
  principio=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('principio',''))" 2>/dev/null || echo "")
  ej=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ejemplo',''))" 2>/dev/null || echo "")
  contraej=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('contraejemplo',''))" 2>/dev/null || echo "")
  enforcement=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('enforcement',''))" 2>/dev/null || echo "")

  echo ""
  echo "────────────────────────────────────────────────────"
  echo "  Entry: $entry_id"
  echo "  Ambito: $ambito  |  Dureza: $dureza"
  echo "  Principio: $principio"
  [[ -n "$ej" ]] && echo "  Ejemplo: $ej"
  [[ -n "$contraej" ]] && echo "  Contraejemplo: $contraej"
  [[ -n "$enforcement" ]] && echo "  Enforcement: $enforcement"

  # Show conflicts
  local conflicts
  conflicts=$(detect_conflicts "$entry_json")
  if [[ -n "$conflicts" ]]; then
    echo ""
    echo "  CONFLICT: $conflicts"
  else
    echo "  No conflicts with personal criterion."
  fi

  echo "────────────────────────────────────────────────────"
  echo -n "  Adopt this entry? [y/N/d(decline)]: "
}

# ── main ──────────────────────────────────────────────────────────────────

main() {
  if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing body.card.json argument." >&2
    usage
  fi

  CANDIDATE="$1"

  if [[ ! -f "$CANDIDATE" ]]; then
    echo "ERROR: Body card not found: $CANDIDATE" >&2
    exit 2
  fi

  if ! python3 -c 'import json,sys; json.load(open(sys.argv[1])); print("OK")' "$CANDIDATE" 2>/dev/null | grep -q OK; then
    echo "ERROR: Body card is not valid JSON: $CANDIDATE" >&2
    exit 2
  fi

  # Step 1: Run monotonicity gate
  echo "=== Corporate Adoption Protocol ==="
  echo ""
  echo "Step 1: Monotonicity gate..."

  local gate_output gate_rc
  # El código de salida se captura en la misma orden: con «|| true» detrás,
  # $? era siempre 0 y un gate en FAIL no paraba la adopción.
  gate_rc=0
  gate_output=$(bash "$GATE_SCRIPT" "$CANDIDATE" 2>&1) || gate_rc=$?

  echo "$gate_output"

  if [[ "$gate_rc" -ne 0 ]]; then
    echo ""
    echo "FATAL: Body failed monotonicity gate. Cannot proceed with adoption."
    echo "The body attempts to relax invariants protected by the constitution"
    echo "or the ethical floor. Resolution: the issuer must amend the body"
    echo "to comply, or the entry must be removed."
    exit 1
  fi

  echo ""
  echo "Step 2: Entry-by-entry adoption"

  local body_id body_version entry_count
  body_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("body_id","UNKNOWN"))' "$CANDIDATE" 2>/dev/null || echo "UNKNOWN")
  body_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","0"))' "$CANDIDATE" 2>/dev/null || echo "0")
  entry_count=$(python3 -c '
import json, sys
card=json.load(open(sys.argv[1]))
entries=card.get("entries",card.get("criterios",[]))
print(len(entries))
' "$CANDIDATE" 2>/dev/null || echo "0")

  echo "Body: $body_id v$body_version"
  echo "Entries to process: $entry_count"
  echo ""

  if [[ "$entry_count" -eq 0 ]]; then
    echo "Body has no entries. Nothing to adopt."
    exit 0
  fi

  local adopted=0
  local declined=0

  for i in $(seq 0 $((entry_count - 1))); do
    local entry_json
    entry_json=$(python3 -c '
import json, sys
card=json.load(open(sys.argv[1]))
i=int(sys.argv[2])
entries=card.get("entries",card.get("criterios",[]))
if i < len(entries):
    print(json.dumps(entries[i],ensure_ascii=False))
' "$CANDIDATE" "$i" 2>/dev/null)

    if [[ -z "$entry_json" ]]; then
      continue
    fi

    local entry_id
    entry_id=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

    prompt_entry "$entry_json" "$body_id" "$body_version"

    local answer
    read -r answer

    case "${answer,,}" in
      y|yes)
        echo ""
        echo -n "  Enter adoption signature (identifies you): "
        read -r sig
        write_ledger_entry "$entry_id" "adopted" "" "${sig:-unsigned}" "$body_id" "$body_version"
        echo "  ADOPTED ($entry_id)"
        adopted=$((adopted + 1))
        ;;
      d|decline)
        echo -n "  Reason for declination: "
        read -r reason
        echo -n "  Enter declination signature: "
        read -r sig
        write_ledger_entry "$entry_id" "declined" "${reason:-no reason given}" "${sig:-unsigned}" "$body_id" "$body_version"
        echo "  DECLINED ($entry_id): ${reason:-no reason given}"
        declined=$((declined + 1))
        ;;
      *)
        # Default: skip (no action, not recorded — explicit skip not needed)
        echo "  SKIPPED ($entry_id)"
        ;;
    esac
  done

  echo ""
  echo "=== Adoption Summary ==="
  echo "Body: $body_id v$body_version"
  echo "Total entries: $entry_count"
  echo "Adopted: $adopted"
  echo "Declined: $declined"
  echo "Skipped: $((entry_count - adopted - declined))"
  echo "Ledger: $LEDGER"
  exit 0
}

main "$@"
