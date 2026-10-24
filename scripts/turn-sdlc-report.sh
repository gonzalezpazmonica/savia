#!/usr/bin/env bash
# turn-sdlc-report.sh — SE-336 S4: reporte Turn-SDLC por ventana
# Consolida discovery-order.jsonl + dod-gate.jsonl en un reporte con
# contadores y top violaciones. Contraparte de ventana del learning-report:
# si order_ok no sube tras SE-335, la regla no funciona — dato, no opinión.
#
# Usage: turn-sdlc-report.sh --window W## [--json]
# Exit: 0 reporte generado · 2 input inválido
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISCOVERY_LOG="${SAVIA_TURN_SDLC_DISCOVERY_LOG:-$ROOT/output/learning-loop/discovery-order.jsonl}"
DOD_LOG="${SAVIA_TURN_SDLC_DOD_LOG:-$ROOT/output/turn-sdlc/dod-gate.jsonl}"
OUT_DIR="${SAVIA_TURN_SDLC_OUT_DIR:-$ROOT/output}"

WINDOW="W?"
JSON_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --window) WINDOW="$2"; shift 2 ;;
    --json) JSON_MODE=true; shift ;;
    *) echo "Usage: $0 --window W## [--json]" >&2; exit 2 ;;
  esac
done

# ── Consolidación discovery-order ────────────────────────────────────────────
TOTAL_TURNS=0
OK_TURNS=0
FALSE_TURNS=0
NA_TURNS=0
declare -A FS_TOP=()

if [[ -f "$DISCOVERY_LOG" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ORDER_OK=$(echo "$line" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get('order_ok','na'))
except Exception:
    print('parse-error')" 2>/dev/null)
    FIRST_TOOLS=$(echo "$line" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get('first_tools',''))
except Exception:
    print('')" 2>/dev/null)
    TOTAL_TURNS=$((TOTAL_TURNS + 1))
    case "$ORDER_OK" in
      true)  OK_TURNS=$((OK_TURNS + 1)) ;;
      false)
        FALSE_TURNS=$((FALSE_TURNS + 1))
        # primera tool de la secuencia como "top violación"
        FIRST="${FIRST_TOOLS%%,*}"
        [[ -n "$FIRST" ]] && FS_TOP["$FIRST"]=$(( ${FS_TOP["$FIRST"]:-0} + 1 ))
        ;;
      *)      NA_TURNS=$((NA_TURNS + 1)) ;;
    esac
  done < "$DISCOVERY_LOG"
fi

# ── Consolidación dod-gate ───────────────────────────────────────────────────
DOD_BLOCK=0
DOD_WARN=0
declare -A DOD_RULES=()

if [[ -f "$DOD_LOG" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    RULE=$(echo "$line" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get('rule',''))
except Exception:
    print('')" 2>/dev/null)
    SEV=$(echo "$line" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get('severity',''))
except Exception:
    print('')" 2>/dev/null)
    case "$SEV" in
      block) DOD_BLOCK=$((DOD_BLOCK + 1)) ;;
      warn)  DOD_WARN=$((DOD_WARN + 1)) ;;
    esac
    [[ -n "$RULE" ]] && DOD_RULES["$RULE"]=$(( ${DOD_RULES["$RULE"]:-0} + 1 ))
  done < "$DOD_LOG"
fi

PCT_OK=0
if (( TOTAL_TURNS - NA_TURNS > 0 )); then
  PCT_OK=$(( OK_TURNS * 100 / (TOTAL_TURNS - NA_TURNS) ))
fi

# ── Output ───────────────────────────────────────────────────────────────────
if $JSON_MODE; then
  printf '{"window":"%s","turns":%d,"order_ok":%d,"order_false":%d,"order_na":%d,"pct_order_ok":%d,"dod_blocked":%d,"dod_warn":%d' \
    "$WINDOW" "$TOTAL_TURNS" "$OK_TURNS" "$FALSE_TURNS" "$NA_TURNS" "$PCT_OK" "$DOD_BLOCK" "$DOD_WARN"
  printf ',"top_violations":{'
  first=true
  for k in "${!FS_TOP[@]}"; do
    $first || printf ','
    first=false
    printf '"%s":%d' "$k" "${FS_TOP[$k]}"
  done
  printf '},"dod_rules":{'
  first=true
  for k in "${!DOD_RULES[@]}"; do
    $first || printf ','
    first=false
    printf '"%s":%d' "$k" "${DOD_RULES[$k]}"
  done
  printf '}}\n'
  exit 0
fi

OUT_MD="$OUT_DIR/turn-sdlc-report-$WINDOW.md"
mkdir -p "$OUT_DIR"
{
  echo "# Turn-SDLC Report — $WINDOW ($(date +%Y-%m-%d))"
  echo
  echo "> SE-336 S4 · Generado por \`scripts/turn-sdlc-report.sh\` — no editar a mano."
  echo "> Alimenta la métrica L del bucle SCL (divergencia regla-comportamiento)."
  echo
  echo "## Resumen"
  echo
  echo "| Métrica | Valor |"
  echo "|---|---|"
  echo "| Turnos observados | $TOTAL_TURNS |"
  echo "| order_ok=true | $OK_TURNS |"
  echo "| order_ok=false | $FALSE_TURNS |"
  echo "| order_ok=na (no-cognitivo) | $NA_TURNS |"
  echo "| **% order_ok (excl. na)** | **$PCT_OK%** |"
  echo "| DOD bloqueos | $DOD_BLOCK |"
  echo "| DOD warnings | $DOD_WARN |"
  echo
  echo "## Top violaciones de orden (primera tool del turno)"
  echo
  echo "| Primera tool | Turnos |"
  echo "|---|---|"
  if (( ${#FS_TOP[@]} == 0 )); then
    echo "| — | 0 |"
  else
    for k in "${!FS_TOP[@]}"; do
      echo "| \`$k\` | ${FS_TOP[$k]} |"
    done
  fi
  echo
  echo "## Reglas DOD disparadas"
  echo
  echo "| Regla | Eventos |"
  echo "|---|---|"
  if (( ${#DOD_RULES[@]} == 0 )); then
    echo "| — | 0 |"
  else
    for k in "${!DOD_RULES[@]}"; do
      echo "| $k | ${DOD_RULES[$k]} |"
    done
  fi
} > "$OUT_MD"

echo "Generated $OUT_MD"
echo "turnos=$TOTAL_TURNS · order_ok=$PCT_OK% · dod_blocked=$DOD_BLOCK · dod_warn=$DOD_WARN"
