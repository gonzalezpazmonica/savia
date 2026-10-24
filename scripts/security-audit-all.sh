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
#   2 — usage error, or UNKNOWN: a scanner did not run or gave unreadable output (SE-453)
#
# Contrato SE-453: --json lleva `result` y `gaps`; en texto la última línea es `gate-result: {...}`.
#
# Ref: docs/rules/domain/security-scanners.md
# Safety: read-only, invokes read-only scanners. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$PROJECT_ROOT/.claude/hooks/lib/gate-result.sh"
GAPS=()
# Sin python3 ningún JSON de escáner es legible: cada uno queda `unreadable` y este hueco dice por qué.
# Se prueba que arranque, no solo que exista: un shim de pyenv sin versión o un venv roto pasan `command -v`.
python3 -c '' >/dev/null 2>&1 || GAPS+=("python3:missing_tool")

# SE-453: un escáner que no corre, sale con un código fuera de su contrato o da una salida que no es
# JSON queda como hueco (unknown), nunca como cero hallazgos. Antes `$(cmd || echo '{}')` pegaba `{}`
# detrás del JSON cuando el escáner salía 1 (hallazgos) y el parseo fallaba a 0: un FAIL se leía PASS.
run_scanner() {
  local name="$1" script="$2"; shift 2
  local output rc counts c h m l
  if [[ ! -f "$script" ]]; then
    GAPS+=("$name:missing_tool"); SCANNER_RESULTS+=("$name|-|-|-|-"); return 0
  fi
  output=$(bash "$script" "$@" 2>/dev/null); rc=$?
  counts=""
  if [[ "$rc" -eq 0 || "$rc" -eq 1 ]]; then
    counts=$(printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
# critical/high/medium son obligatorias: una clave ausente (esquema cambiado) es ilegible, no un 0.
# low es opcional porque permissions-wildcard-audit y hook-injection-audit no la emiten.
if not isinstance(d, dict) or any(k not in d for k in ("critical", "high", "medium")):
    sys.exit(1)
vals = [d.get(k, 0) for k in ("critical", "high", "medium", "low")]
# type() y no isinstance(): True es un int para Python y en $((…)) valdría 0.
if not all(type(v) is int and v >= 0 for v in vals):
    sys.exit(1)
fc = d.get("findings_count", sum(vals))
if type(fc) is not int:
    sys.exit(1)
# Hallazgos declarados sin ninguna cuenta (p.ej. severidades anidadas en otra clave) no es un limpio.
if fc > 0 and sum(vals) == 0:
    sys.exit(1)
print(" ".join(map(str, vals)))
' 2>/dev/null) || counts=""
  fi
  if [[ -z "$counts" ]]; then
    GAPS+=("$name:unreadable"); SCANNER_RESULTS+=("$name|-|-|-|-"); return 0
  fi
  read -r c h m l <<< "$counts"
  # Un escáner que dice FAIL (rc 1) sin ninguna cuenta no puede leerse como limpio.
  if [[ "$rc" -eq 1 && $((c + h + m + l)) -eq 0 ]]; then
    GAPS+=("$name:unreadable"); SCANNER_RESULTS+=("$name|-|-|-|-"); return 0
  fi
  TOTAL_CRIT=$((TOTAL_CRIT + c))
  TOTAL_HIGH=$((TOTAL_HIGH + h))
  TOTAL_MED=$((TOTAL_MED + m))
  TOTAL_LOW=$((TOTAL_LOW + l))
  SCANNER_RESULTS+=("$name|$c|$h|$m|$l")
}

# Run each scanner in JSON mode
run_scanner "mcp-security-audit" "$PROJECT_ROOT/scripts/mcp-security-audit.sh" --json
run_scanner "permissions-wildcard-audit" "$PROJECT_ROOT/scripts/permissions-wildcard-audit.sh" --json
run_scanner "hook-injection-audit" "$PROJECT_ROOT/scripts/hook-injection-audit.sh" --json

# Prompt security scan: count findings manually (it has different output format)
PS_FINDINGS=0
if [[ -f "$PROJECT_ROOT/scripts/prompt-security-scan.sh" ]]; then
  PS_OUT=$(bash "$PROJECT_ROOT/scripts/prompt-security-scan.sh" "$PROJECT_ROOT/.claude/agents" 2>&1); PS_RC=$?
  PS_FINDINGS=$(echo "$PS_OUT" | grep -oE 'Findings: [0-9]+' | head -1 | awk '{print $2}')
  if [[ ( "$PS_RC" -eq 0 || "$PS_RC" -eq 1 ) && -n "$PS_FINDINGS" ]] && ! [[ "$PS_RC" -eq 1 && "$PS_FINDINGS" -eq 0 ]]; then
    # Assume HIGH severity for PS findings (simplification)
    TOTAL_HIGH=$((TOTAL_HIGH + PS_FINDINGS))
    SCANNER_RESULTS+=("prompt-security-scan|0|$PS_FINDINGS|0|0")
  else
    GAPS+=("prompt-security-scan:unreadable"); SCANNER_RESULTS+=("prompt-security-scan|-|-|-|-")
  fi
else
  GAPS+=("prompt-security-scan:missing_tool"); SCANNER_RESULTS+=("prompt-security-scan|-|-|-|-")
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

# SE-453: resultado del contrato, derivado del mismo criterio que el exit para que `result`, `verdict` y
# el código digan lo mismo: sobre el umbral ⇒ findings/FAIL/1 (aunque haya huecos, que van en `gaps`);
# si no, un hueco ⇒ unknown/UNKNOWN/2; si no, clean/PASS/0. Los hallazgos bajo el umbral siguen en los totales.
if [[ "$EXIT_CODE" -eq 1 ]]; then RESULT="findings"; VERDICT="FAIL"
elif [[ ${#GAPS[@]} -gt 0 ]]; then RESULT="unknown"; VERDICT="UNKNOWN"; EXIT_CODE=2
else RESULT="clean"; VERDICT="PASS"; fi
# ${GAPS[@]+…}: con set -u, un array vacío aborta en bash < 4.4 (macOS trae 3.2).
GATE_LINE="$(gate_result_emit "$RESULT" ${GAPS[@]+"${GAPS[@]}"})"

if [[ "$JSON" -eq 1 ]]; then
  scanners_json=""
  for r in "${SCANNER_RESULTS[@]}"; do
    IFS='|' read -r name c h m l <<< "$r"
    [[ "$c" == "-" ]] && { scanners_json+="{\"scanner\":\"$name\",\"critical\":null,\"high\":null,\"medium\":null,\"low\":null},"; continue; }
    scanners_json+="{\"scanner\":\"$name\",\"critical\":$c,\"high\":$h,\"medium\":$m,\"low\":$l},"
  done
  scanners_json="[${scanners_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","fail_on":"$FAIL_ON","total_critical":$TOTAL_CRIT,"total_high":$TOTAL_HIGH,"total_medium":$TOTAL_MED,"total_low":$TOTAL_LOW,"scanners":$scanners_json,${GATE_LINE#gate-result: \{}
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
  echo "$GATE_LINE"
fi

exit $EXIT_CODE
