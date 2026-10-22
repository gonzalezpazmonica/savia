#!/usr/bin/env bash
# meta-monitor.sh — L13 F1: juicio metacognitivo de monitoreo.
#
# Datada una confianza declarada (0-100) por el orquestador/orquestador SAGI,
# emite una confianza CALIBRADA ajustada por:
#   - calibración histórica del agente (SE-255 S4; fichero de curva o default)
#   - divergencia grafo-modelo (L1; predictor de error CONFIRMADO)
#   - evidencia externa (gap entre confianza y evidencia disponible)
#
# Salida JSON:
#   {task, confidence_declared, calibration, divergence, evidence_gap,
#    confidence_adjusted, action_hint}
#
# PURE_BASH+python, sin red, sin LLM (CRIT-001). El juicio es del sistema sobre
# sí mismo (metacognición propia, no teoría de la mente ni consciencia — L13).
#
# Usage:
#   meta-monitor.sh --task <id> --confidence <0-100>
#     [--divergence <0-1>] [--calibration-file <path>] [--evidence <0-1>]
# Exit: 0 ok · 2 input inválido
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CAL_FILE="$ROOT/output/meta/calibration.json"

TASK=""
CONF=""
DIV="0.3"
EVIDENCE="0.5"
CAL_FILE="$DEFAULT_CAL_FILE"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="${2:-}"; shift 2 ;;
    --confidence) CONF="${2:-}"; shift 2 ;;
    --divergence) DIV="${2:-}"; shift 2 ;;
    --calibration-file) CAL_FILE="${2:-}"; shift 2 ;;
    --evidence) EVIDENCE="${2:-}"; shift 2 ;;
    *) echo "usage: $0 --task T --confidence C [--divergence D] [--calibration-file F] [--evidence E]" >&2; exit 2 ;;
  esac
done
[[ -z "$TASK" || -z "$CONF" ]] && { echo "ERROR: --task y --confidence requeridos" >&2; exit 2; }
[[ "$CONF" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --confidence numerico 0-100" >&2; exit 2; }
[[ "$DIV" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --divergence numerico 0-1" >&2; exit 2; }
[[ "$EVIDENCE" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --evidence numerico 0-1" >&2; exit 2; }

# calibración histórica: si existe curva, cal por tarea (más preciso) con fallback global
CAL_ACC="0.5"
if [[ -f "$CAL_FILE" ]]; then
  CAL_ACC=$(python3 - "$CAL_FILE" "$TASK" <<'PY'
import json, sys, os
cal_file, task = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(cal_file))
    if not isinstance(d, dict):
        print('0.5'); sys.exit(0)
    # por tarea primero
    bt = d.get('by_task', {}).get(task)
    if bt and bt.get('n'):
        print(round(bt['correct'] / bt['n'], 3)); sys.exit(0)
    # fallback global
    runs = d.get('runs') or []
    if runs:
        corr = sum(1 for r in runs if r.get('outcome') == 'success')
        part = sum(0.5 for r in runs if r.get('outcome') == 'partial')
        print(round((corr + part) / len(runs), 3)); sys.exit(0)
    print('0.5')
except Exception:
    print('0.5')
PY
  )
fi

# Compute adjusted confidence (python): fusiona confianza, calibración, divergencia, evidencia
python3 - "$CONF" "$CAL_ACC" "$DIV" "$EVIDENCE" "$TASK" <<'PY'
import sys, json
conf, cal, div, ev, task = (float(sys.argv[1]), float(sys.argv[2]),
                             float(sys.argv[3]), float(sys.argv[4]), sys.argv[5])
# f1: penalizar por calibración histórica débil (si el agente suele errar, su confianza vale menos)
calib_penalty = (conf * (1.0 - cal))
# f2: divergencia es predictor de error (L1) — por encima de 0.6, bajada fuerte
div_penalty = conf * div if div > 0.6 else conf * div * 0.5
# f3: evidencia disponible (0=ninguna, 1=total) — poca evidencia reduce confianza
ev_penalty = conf * (1.0 - ev) * 0.3
adjusted = conf - calib_penalty - div_penalty - ev_penalty
adjusted = max(0.0, min(100.0, round(adjusted, 1)))

if adjusted < 60:
    action = "POSTPONE (pedir evidencia / re-planificar)"
elif adjusted < 75:
    action = "CAUTIOUS (persistir con advertencia)"
else:
    action = "EMIT (confianza suficiente)"

print(json.dumps({
    "task": task,
    "confidence_declared": conf,
    "calibration": cal,
    "divergence": div,
    "evidence": ev,
    "confidence_adjusted": adjusted,
    "action_hint": action,
}, ensure_ascii=False))
PY