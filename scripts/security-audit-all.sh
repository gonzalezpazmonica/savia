#!/usr/bin/env bash
# security-audit-all.sh — Unified runner for all security scanners.
#
# Ejecuta en secuencia:
#   - prompt-security-scan.sh (PS-01..PS-14) sobre agents/skills
#   - mcp-security-audit.sh (MCP-01..MCP-11) SE-058
#   - permissions-wildcard-audit.sh (PERM-01..PERM-08) SE-059
#   - hook-injection-audit.sh (HOOK-01..HOOK-09) SE-060
#
# Agrega findings en un solo report JSON o human.
#
# Usage:
#   security-audit-all.sh              # run all + human report
#   security-audit-all.sh --json       # aggregated JSON
#   security-audit-all.sh --fail-on LEVEL   # exit 1 if findings >= LEVEL (default HIGH)
#
# Exit codes:
#   0 — findings below fail-on threshold
#   1 — findings at or above fail-on threshold
#   2 — usage error
#
# SE-453: resultado clean|findings|unknown. En texto, la última línea de stdout es
# `gate-result: {...}`; con --json, los campos `result` y `gaps`. Un sub-escáner que sale ≥ 2,
# no deja JSON legible o informa `result: unknown` es un hueco, nunca cero hallazgos.
# Con hueco y sin hallazgos el exit sigue en 0 (D3: ciclo de aviso, registrado en
# output/unmeasured-gates.jsonl); SAVIA_GATE_UNKNOWN=block lo convierte en 1.
#
# Ref: docs/rules/domain/security-scanners.md
# Safety: read-only, invokes read-only scanners. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"
GAPS=()
add_gap() { [[ " ${GAPS[*]} " == *" $1 "* ]] || GAPS+=("$1"); }

JSON=0
FAIL_ON="HIGH"

usage() {
  cat <<EOF
Usage:
  $0 [--json] [--fail-on LOW|MEDIUM|HIGH|CRITICAL]

Runs all security scanners and aggregates findings.

Options:
  --json              JSON aggregated output
  --fail-on LEVEL     Exit 1 if any finding at LEVEL or higher (default HIGH)

Ref: docs/rules/domain/security-scanners.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --fail-on) FAIL_ON="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

case "$FAIL_ON" in
  LOW|MEDIUM|HIGH|CRITICAL) ;;
  *) echo "ERROR: invalid --fail-on level" >&2; exit 2 ;;
esac

sev_rank() {
  case "$1" in
    LOW) echo 1 ;;
    MEDIUM) echo 2 ;;
    HIGH) echo 3 ;;
    CRITICAL) echo 4 ;;
    *) echo 0 ;;
  esac
}
FAIL_RANK=$(sev_rank "$FAIL_ON")

TOTAL_CRIT=0
TOTAL_HIGH=0
TOTAL_MED=0
TOTAL_LOW=0
SCANNER_RESULTS=()

# run_scanner <nombre> <orden...> — ejecuta un sub-escáner en modo JSON y suma sus severidades.
# El exit code 1 (hallazgos) no invalida el JSON: se lee igual. Exit ≥ 2, JSON ilegible o
# `result: unknown` ⇒ hueco (con los huecos propios del sub-escáner si los declara). Las cuentas
# critical/high/medium son obligatorias y enteras, y exit 1 o findings_count > 0 sin ninguna cuenta
# es ilegible (SE-453 parte 2, #1348).
run_scanner() {
  local name="$1"; shift
  local output rc=0 parsed c=0 h=0 m=0 l=0 g
  output=$("$@" 2>/dev/null) || rc=$?
  parsed=$(printf '%s' "$output" | GATE_REASONS="$_GATE_REASONS" python3 -c '
import json, os, re, sys
REASONS = os.environ["GATE_REASONS"].split()
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(3)
# critical/high/medium son obligatorias: una clave ausente (esquema cambiado) es ilegible, no un 0.
# low es opcional porque permissions-wildcard-audit y hook-injection-audit no la emiten.
if not isinstance(d, dict) or any(k not in d for k in ("critical", "high", "medium")):
    sys.exit(3)
counts = [d.get(k, 0) for k in ("critical", "high", "medium", "low")]
# type() y no isinstance(): True es un int para Python; "2" o 2.7 tampoco son una cuenta.
fc = d.get("findings_count", sum(c for c in counts if type(c) is int))
if not all(type(v) is int and v >= 0 for v in counts + [fc]):
    sys.exit(3)
# Hallazgos declarados sin ninguna cuenta (p.ej. severidades anidadas en otra clave) no es un limpio.
if fc > 0 and sum(counts) == 0:
    sys.exit(3)
print(*counts)
if d.get("result") == "unknown":
    gaps = [g for g in d.get("gaps") or [] if isinstance(g, dict)]
    for g in gaps or [{"check": "result", "reason": "unreadable"}]:
        # Vocabulario cerrado (gate-result.sh): un motivo ajeno o un check con «:», espacios o saltos
        # de línea haría que gate_result_emit fallara sin salida y el JSON agregado quedara roto.
        check = re.sub(r"[^A-Za-z0-9_./-]", "_", str(g.get("check") or "result")) or "result"
        reason = g.get("reason")
        print("%s:%s" % (check, reason if reason in REASONS else "unreadable"))
' 2>/dev/null) || parsed=""
  if [[ $rc -ge 2 || -z "$parsed" ]]; then
    add_gap "$name:unreadable"
  else
    read -r c h m l <<< "$(head -1 <<< "$parsed")"
    # Un sub-escáner que dice FAIL (exit 1) sin ninguna cuenta no puede leerse como limpio.
    if [[ $rc -eq 1 && $((c + h + m + l)) -eq 0 ]]; then
      add_gap "$name:unreadable"
    fi
    while IFS= read -r g; do
      [[ -n "$g" ]] && add_gap "$name/$g"
    done < <(tail -n +2 <<< "$parsed")
  fi
  TOTAL_CRIT=$((TOTAL_CRIT + c))
  TOTAL_HIGH=$((TOTAL_HIGH + h))
  TOTAL_MED=$((TOTAL_MED + m))
  TOTAL_LOW=$((TOTAL_LOW + l))
  SCANNER_RESULTS+=("$name|$c|$h|$m|$l")
}

# Sin python3 ningún JSON de escáner es legible: cada uno queda `unreadable` y este hueco dice por qué.
# Se prueba que arranque, no solo que exista: un shim de pyenv sin versión o un venv roto pasan `command -v`.
python3 -c '' >/dev/null 2>&1 || add_gap "python3:missing_tool"

# Run each scanner in JSON mode
run_scanner "mcp-security-audit" bash "$PROJECT_ROOT/scripts/mcp-security-audit.sh" --json
run_scanner "permissions-wildcard-audit" bash "$PROJECT_ROOT/scripts/permissions-wildcard-audit.sh" --json
run_scanner "hook-injection-audit" bash "$PROJECT_ROOT/scripts/hook-injection-audit.sh" --json

# Prompt security scan: count findings manually (it has different output format)
PS_FINDINGS=0
if [[ -f "$PROJECT_ROOT/scripts/prompt-security-scan.sh" ]]; then
  PS_RC=0
  PS_OUT=$(bash "$PROJECT_ROOT/scripts/prompt-security-scan.sh" "$PROJECT_ROOT/.claude/agents" 2>&1) || PS_RC=$?
  PS_FINDINGS=$(echo "$PS_OUT" | grep -oE 'Findings: [0-9]+' | head -1 | awk '{print $2}')
  PS_GATE=$(echo "$PS_OUT" | grep '^gate-result: ' | tail -1)
  # Exit 1 con «Findings: 0» es un FAIL sin cuenta: hueco, no limpio.
  if [[ $PS_RC -ge 2 || -z "$PS_FINDINGS" || ( $PS_RC -eq 1 && "$PS_FINDINGS" -eq 0 ) ]]; then
    add_gap "prompt-security-scan:unreadable"
  elif [[ "$PS_GATE" == *'"result":"unknown"'* ]]; then
    add_gap "prompt-security-scan:unreadable"
  fi
  PS_FINDINGS="${PS_FINDINGS:-0}"
  # Assume HIGH severity for PS findings (simplification)
  TOTAL_HIGH=$((TOTAL_HIGH + PS_FINDINGS))
  SCANNER_RESULTS+=("prompt-security-scan|0|$PS_FINDINGS|0|0")
else
  # Antes un prompt-security-scan ausente (o sin bit de ejecución) se omitía sin decirlo: clean sin medir.
  add_gap "prompt-security-scan:missing_tool"
fi

# Determine exit
EXIT_CODE=0
for sev_thresh in CRITICAL HIGH MEDIUM LOW; do
  rank=$(sev_rank "$sev_thresh")
  if [[ "$rank" -ge "$FAIL_RANK" ]]; then
    case "$sev_thresh" in
      CRITICAL) [[ "$TOTAL_CRIT" -gt 0 ]] && EXIT_CODE=1 ;;
      HIGH) [[ "$TOTAL_HIGH" -gt 0 ]] && EXIT_CODE=1 ;;
      MEDIUM) [[ "$TOTAL_MED" -gt 0 ]] && EXIT_CODE=1 ;;
      LOW) [[ "$TOTAL_LOW" -gt 0 ]] && EXIT_CODE=1 ;;
    esac
  fi
done

RESULT="clean"
if [[ $((TOTAL_CRIT + TOTAL_HIGH + TOTAL_MED + TOTAL_LOW)) -gt 0 ]]; then
  RESULT="findings"
elif [[ ${#GAPS[@]} -gt 0 ]]; then
  RESULT="unknown"
  GATE_UNMEASURED_ROOT="$PROJECT_ROOT" gate_unmeasured_record "security-audit-all" unreadable
fi
# block mira los huecos, no RESULT: un hallazgo LOW bajo --fail-on no puede tapar un sub-escáner
# ilegible que quizá escondía un CRITICAL.
[[ ${#GAPS[@]} -gt 0 && "${SAVIA_GATE_UNKNOWN:-warn}" == "block" ]] && EXIT_CODE=1
VERDICT="$([ $EXIT_CODE -eq 0 ] && echo PASS || echo FAIL)"

if [[ "$JSON" -eq 1 ]]; then
  scanners_json=""
  for r in "${SCANNER_RESULTS[@]}"; do
    IFS='|' read -r name c h m l <<< "$r"
    scanners_json+="{\"scanner\":\"$name\",\"critical\":$c,\"high\":$h,\"medium\":$m,\"low\":$l},"
  done
  scanners_json="[${scanners_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","fail_on":"$FAIL_ON","total_critical":$TOTAL_CRIT,"total_high":$TOTAL_HIGH,"total_medium":$TOTAL_MED,"total_low":$TOTAL_LOW,"scanners":$scanners_json,$(gate_result_emit "$RESULT" "${GAPS[@]}" | sed 's/^gate-result: {//; s/}$//')}
JSON
else
  echo "=== Savia Security Audit (all scanners) ==="
  echo ""
  echo "Fail threshold:  $FAIL_ON"
  echo ""
  printf "  %-35s %-8s %-6s %-6s %-5s\n" "SCANNER" "CRIT" "HIGH" "MED" "LOW"
  for r in "${SCANNER_RESULTS[@]}"; do
    IFS='|' read -r name c h m l <<< "$r"
    printf "  %-35s %-8s %-6s %-6s %-5s\n" "$name" "$c" "$h" "$m" "$l"
  done
  echo ""
  echo "Totals:          crit=$TOTAL_CRIT  high=$TOTAL_HIGH  med=$TOTAL_MED  low=$TOTAL_LOW"
  echo ""
  echo "VERDICT: $VERDICT"
  [[ "$RESULT" == "unknown" ]] && echo "WARN: auditoría incompleta (resultado desconocido): ${GAPS[*]}"
  gate_result_emit "$RESULT" "${GAPS[@]}"
fi

exit $EXIT_CODE
