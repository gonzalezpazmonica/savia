#!/usr/bin/env bash
# meta-control.sh — L13 F2: control metacognitivo sobre el orquestador SAGI.
#
# Dado el juicio metacognitivo (confidence_adjusted de meta-monitor.sh), decide
# la ACCION de control para el orquestador:
#   EMIT     → confianza suficiente; se permite emitir/persistir la propuesta
#   POSTPONE → confianza baja; pedir +evidencia o re-planificar (no emitir ya)
#   REPLAN   → divergencia alta; re-planificar el enfoque antes de decidir
#   REDUCE   → calibración histórica mala; bajar nivel de autonomía (SCL-006)
#
# CRIT-031/ART-11: esta capa PROPONE la acción; nunca la ejecuta sin humano.
# Todo en local, sin LLM, sin red (CRIT-001).
#
# Usage:
#   meta-control.sh --adjusted <0-100> --divergence <0-1>
#     [--calibration <0-1>] [--requested <emit|persist|decide>] [--dry-run]
# Exit: 0 ok · 2 input inválido
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ADJUSTED=""
DIVERGENCE="0.3"
CALIBRATION="0.5"
REQUESTED="decide"
DRY_RUN=false
THRESHOLD_POSTPONE="${SAGI_META_POSTPONE:-60}"
THRESHOLD_DIVERGENCE="${SAGI_META_DIVERGENCE:-0.7}"
THRESHOLD_CALIBRATION="${SAGI_META_CALIBRATION:-0.5}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adjusted) ADJUSTED="${2:-}"; shift 2 ;;
    --divergence) DIVERGENCE="${2:-}"; shift 2 ;;
    --calibration) CALIBRATION="${2:-}"; shift 2 ;;
    --requested) REQUESTED="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "usage: $0 --adjusted A [--divergence D] [--calibration C] [--requested R] [--dry-run]" >&2; exit 2 ;;
  esac
done
[[ -z "$ADJUSTED" ]] && { echo "ERROR: --adjusted requerido" >&2; exit 2; }
[[ "$ADJUSTED" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --adjusted numerico 0-100" >&2; exit 2; }
[[ "$DIVERGENCE" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --divergence numerico 0-1" >&2; exit 2; }
[[ "$CALIBRATION" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --calibration numerico 0-1" >&2; exit 2; }

# Decisión de control (determinista, umbrales configurables)
python3 - "$ADJUSTED" "$DIVERGENCE" "$CALIBRATION" "$REQUESTED" \
        "$THRESHOLD_POSTPONE" "$THRESHOLD_DIVERGENCE" "$THRESHOLD_CALIBRATION" "$DRY_RUN" <<'PY'
import sys, json
adjusted, div, cal, requested = (float(sys.argv[1]), float(sys.argv[2]),
                                 float(sys.argv[3]), sys.argv[4])
t_postpone, t_div, t_cal = (float(sys.argv[5]), float(sys.argv[6]), float(sys.argv[7]))
dry = sys.argv[8] == 'true'

action = "EMIT"
reason = "confianza suficiente"
proposal = "emitir y persistir la propuesta como INFERRED"

# 1. divergencia alta → replan (incluso si confianza alta: señal L1 de error previsto)
if div > t_div:
    action = "REPLAN"
    reason = f"divergencia {div:.2f} > {t_div:.2f} (L1 predice error)"
    proposal = "re-planificar el enfoque antes de decidir; no persistir aun"
# 2. calibración histórica mala → reducir autonomía
elif cal < t_cal:
    action = "REDUCE"
    reason = f"calibración histórica {cal:.2f} < {t_cal:.2f} (sobreconfianza habitual)"
    proposal = "bajar nivel de autonomía (SCL-006) y reportar, no ejecutar en L2+"
# 3. confianza ajustada baja → postergar si la acción es emitir/persistir/decidir
elif adjusted < t_postpone and requested in ("decide", "persist", "emit"):
    action = "POSTPONE"
    reason = f"confianza ajustada {adjusted:.1f} < {t_postpone:.0f}"
    proposal = "pedir evidencia adicional o reformular; no entregar propuesta ya"

out = {
    "action": action,
    "reason": reason,
    "proposal": proposal,
    "confidence_adjusted": adjusted,
    "divergence": div,
    "calibration": cal,
    "requested": requested,
}
if dry:
    out["dry_run"] = True
    out["executed"] = False
print(json.dumps(out, ensure_ascii=False))
PY
exit 0