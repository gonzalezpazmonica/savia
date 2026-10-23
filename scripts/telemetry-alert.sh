#!/usr/bin/env bash
# telemetry-alert.sh — SE-334 S2: emite alert cuando un issue cruza el umbral,
# y opcionalmente alimenta el hook de captura SCL (cierra el círculo: el
# bucle aprende del incidente).
#
# Política: config/telemetry-policies.yaml  (alert_on: count >= N)
# El modo demo/--dry-run no toca nada. REGLA: nunca modifica CRITERIO.md,
# nunca escribe fuera de sustrato markdown/JSONL, sin red, sin LLM (CRIT-001).
#
# Usage: telemetry-alert.sh [--issues FILE] [--policy FILE] [--capture]
#   --capture   además, llama a learning-proposal.sh con el issue como origen
# Exit: 0 siempre · 2 input inválido
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISSUES="${TEL_FP_ISSUES:-$ROOT/output/telemetry-issues.jsonl}"
POLICY="${TEL_FP_POLICY:-$ROOT/config/telemetry-policies.yaml}"
ALERT_LOG="${TEL_FP_ALERT_LOG:-$ROOT/output/telemetry-alerts.jsonl}"
CAPTURE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues) ISSUES="$2"; shift 2 ;;
    --policy) POLICY="$2"; shift 2 ;;
    --capture) CAPTURE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "usage: $0 [--issues F] [--policy F] [--capture]" >&2; exit 2 ;;
  esac
done

[[ -f "$ISSUES" ]] || { echo "no issues file: $ISSUES" >&2; exit 0; }

# umbral por defecto si no hay policy
THRESHOLD=5
if [[ -f "$POLICY" ]]; then
  P=$(grep -oP 'count\s*>=\s*\K[0-9]+' "$POLICY" 2>/dev/null | head -1)
  [[ -n "$P" ]] && THRESHOLD="$P"
fi

$DRY_RUN || mkdir -p "$(dirname "$ALERT_LOG")"
ALERTS=0
while IFS= read -r issue; do
  [[ -z "$issue" ]] && continue
  COUNT_JSON=$(echo "$issue" | python3 -c "import sys,json;print(json.loads(sys.stdin.read()).get('count',0))" 2>/dev/null || echo 0)
  HASH=$(echo "$issue" | python3 -c "import sys,json;print(json.loads(sys.stdin.read()).get('hash',''))" 2>/dev/null || echo "")
  [[ -z "$HASH" ]] && continue
  if (( COUNT_JSON >= THRESHOLD )); then
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ALERT="{\"ts\":\"$TS\",\"kind\":\"telemetry-alert\",\"hash\":\"$HASH\",\"count\":$COUNT_JSON,\"threshold\":$THRESHOLD,\"status\":\"open\"}"
    $DRY_RUN || echo "$ALERT" >> "$ALERT_LOG"
    ALERTS=$((ALERTS + 1))
    if $CAPTURE && ! $DRY_RUN; then
      bash "$ROOT/scripts/learning-proposal.sh" \
        --origin "telemetry alert: issue $HASH ($COUNT_JSON eventos)" \
        --evidence "$ISSUES" \
        --diagnosis "incidente recurrente detectado por telemetria (count=$COUNT_JSON >= umbral $THRESHOLD); el bucle aprende del incidente" \
        --change "revisar el error agrupado y proponer correccion de criterio/memoria/skill/spec" \
        --target skill --trigger recurrence >/dev/null 2>&1 || true
    fi
  fi
done < "$ISSUES"

echo "alerts=$ALERTS threshold=$THRESHOLD capture=$CAPTURE"