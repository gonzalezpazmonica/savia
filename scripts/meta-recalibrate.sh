#!/usr/bin/env bash
# meta-recalibrate.sh — L13 F1: recalibración del juicio metacognitivo.
#
# Registra el resultado real (success/failure) de una propuesta predicha con
# cierta confianza y actualiza la curva de calibración del agente (por tarea).
# La siguiente vez, meta-monitor.sh consulta la curva y ajusta el juicio.
#
# Almacén: output/meta/calibration.json  — CRIT-001: todo local, sin cloud.
#
# Usage:
#   meta-recalibrate.sh --task <id> --predicted <0-100> --outcome <success|fail|partial>
#     [--calibration-file <path>]
# Exit: 0 ok · 2 input inválido
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CAL_FILE="$ROOT/output/meta/calibration.json"

TASK=""
PRED=""
OUTCOME=""
CAL_FILE="$DEFAULT_CAL_FILE"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="${2:-}"; shift 2 ;;
    --predicted) PRED="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    --calibration-file) CAL_FILE="${2:-}"; shift 2 ;;
    *) echo "usage: $0 --task T --predicted P --outcome success|fail|partial" >&2; exit 2 ;;
  esac
done
[[ -z "$TASK" || -z "$PRED" || -z "$OUTCOME" ]] && { echo "ERROR: --task/--predicted/--outcome requeridos" >&2; exit 2; }
[[ "$PRED" =~ ^([0-9]{1,2}([.][0-9]+)?|100([.]0+)?)$ ]] || { echo "ERROR: --predicted numerico 0-100" >&2; exit 2; }
case "$OUTCOME" in success|fail|partial) ;; *) echo "ERROR: outcome ∈ success|fail|partial" >&2; exit 2 ;; esac

L_DIR="$(dirname "$CAL_FILE")"
mkdir -p "$L_DIR"

python3 - "$CAL_FILE" "$TASK" "$PRED" "$OUTCOME" <<'PY'
import json, sys, os, time
cal_file, task, pred, outcome = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]

data = {"runs": [], "by_task": {}}
if os.path.exists(cal_file):
    try:
        data = json.load(open(cal_file))
        if not isinstance(data, dict):
            data = {"runs": [], "by_task": {}}
    except Exception:
        data = {"runs": [], "by_task": {}}

data.setdefault("runs", [])
data.setdefault("by_task", {})

data["runs"].append({
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "task": task,
    "predicted": pred,
    "outcome": outcome,
})

bt = data["by_task"].setdefault(task, {"n": 0, "correct": 0})
bt["n"] += 1
if outcome == "success":
    bt["correct"] += 1
elif outcome == "partial":
    bt["correct"] += 0.5

json.dump(data, open(cal_file, "w"), indent=2)
# reporte
correct = sum(1 for r in data["runs"] if r.get("outcome") == "success")
partial = sum(0.5 for r in data["runs"] if r.get("outcome") == "partial")
n = len(data["runs"])
acc = round((correct + partial) / n, 3) if n else 0.5
print(f"recorded task={task} predicted={pred} outcome={outcome}")
print(f"calibration: runs={n} accuracy={acc}")
PY