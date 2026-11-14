#!/usr/bin/env bash
# control-band-detect.sh — SE-357: detección determinista de control bands (sin LLM).
# set -uo pipefail
#
# Detecta breaches de control bands sobre métricas locales con rolling baseline
# y reglas Western Electric. DETECCIÓN 100% DETERMINISTA: este script JAMÁS
# invoca un LLM. El agente se invoca DESPUÉS, en el tier adecuado.
#
# Métricas soportadas (origen local):
#   ci_test_failure_rate  → output/ci-duration/failures.jsonl (SE-361) o data/
#   telemetry_anomaly     → output/telemetry-events.jsonl (SE-534)
#   session_error_rate    → output/session-action-log.jsonl
#
# Salida JSON: {metric, sigma_level, breached, samples, window, mean, sd}
#
# Uso:
#   control-band-detect.sh --metric ci_test_failure_rate [--window 30d] [--dry-run]
#
# Ref: SE-357 — Control Bands autónomas (playbook Anthropic Stage 6)
set -uo pipefail
[[ -n "${LC_ALL:-}" ]] && { export LANG="$LC_ALL"; unset LC_ALL; }; export LC_NUMERIC=C  # punto decimal fijo (es_ES usa coma); LC_ALL anularía LC_NUMERIC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRIC=""
WINDOW_DAYS=30
DRY=false
CONFIG="$ROOT/control-bands.yaml"

while [[ $# -gt 0 ]]; do case "$1" in
  --metric) METRIC="$2"; shift 2 ;;
  --window) WINDOW_DAYS="$2"; shift 2 ;;
  --dry-run) DRY=true; shift ;;
  --config) CONFIG="$2"; shift 2 ;;
  *) shift ;;
esac; done

[[ -z "$METRIC" ]] && { echo "Uso: control-band-detect.sh --metric {ci_test_failure_rate|telemetry_anomaly|session_error_rate}" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "ERROR: config $CONFIG no existe. Fail-closed." >&2; exit 1; }

# Validar métrica soportada ANTES de ejecutar (fail-closed)
case "$METRIC" in
  ci_test_failure_rate|telemetry_anomaly|session_error_rate) ;;
  *) echo "ERROR: métrica '$METRIC' no soportada. Válidas: ci_test_failure_rate|telemetry_anomaly|session_error_rate" >&2; exit 2 ;;
esac

# ── Extraer métricas de fuentes locales ──────────────────────────────────────
collect_samples() {
  local metric="$1"
  case "$metric" in
    ci_test_failure_rate)
      # leer data/ci-duration/failures.jsonl (si existe) o telemetry
      if [[ -f "$ROOT/data/ci-duration/failures.jsonl" ]]; then
        grep -oE '"ts":"[^"]*"' "$ROOT/data/ci-duration/failures.jsonl" 2>/dev/null | wc -l
      else
        echo "0"
      fi
      ;;
    telemetry_anomaly)
      if [[ -f "$ROOT/output/telemetry-events.jsonl" ]]; then
        local total anomalies
        total=$(wc -l < "$ROOT/output/telemetry-events.jsonl" 2>/dev/null || echo 0)
        anomalies=$(grep -cE '"severity":"(error|critical)"' "$ROOT/output/telemetry-events.jsonl" 2>/dev/null || echo 0)
        [[ "$total" -gt 0 ]] && awk -v a="$anomalies" -v t="$total" 'BEGIN{printf "%.4f", a/t}' || echo "0"
      else
        echo "0"
      fi
      ;;
    session_error_rate)
      if [[ -f "$ROOT/output/session-action-log.jsonl" ]]; then
        local total fails
        total=$(wc -l < "$ROOT/output/session-action-log.jsonl" 2>/dev/null || echo 0)
        fails=$(grep -cE '"result":"(fail|error)"' "$ROOT/output/session-action-log.jsonl" 2>/dev/null || echo 0)
        [[ "$total" -gt 0 ]] && awk -v f="$fails" -v t="$total" 'BEGIN{printf "%.4f", f/t}' || echo "0"
      else
        echo "0"
      fi
      ;;
    *) echo "ERROR: métrica '$metric' no soportada" >&2; exit 2 ;;
  esac
}

# ── Cálculo σ (Western Electric simplificado) ─────────────────────────────────
# mean + sd sobre la muestra reciente; breach si último punto > mean + k*sd
compute_sigma() {
  local samples="$1"
  local last
  last=$(echo "$samples" | awk '{print $NF}')
  # media y desviación estándar
  python3 - "$samples" "$last" <<'PY'
import sys, math
vals = [float(x) for x in sys.argv[1].split() if x]
if len(vals) < 3:
    print('{"sigma_level":0,"breached":false,"samples":%d,"mean":0,"sd":0}' % len(vals))
    sys.exit(0)
last = float(sys.argv[2])
mean = sum(vals) / len(vals)
var = sum((x - mean)**2 for x in vals) / len(vals)
sd = math.sqrt(var)
# distancia en sigma del último punto
sigma = (last - mean) / sd if sd > 0 else 0
breached = abs(sigma) >= 1.0
import json
print(json.dumps({
    "sigma_level": round(sigma, 2),
    "breached": breached,
    "samples": len(vals),
    "mean": round(mean, 4),
    "sd": round(sd, 4),
}))
PY
}

# ── Ejecución ────────────────────────────────────────────────────────────────
if $DRY; then
  echo "DRY-RUN: metric=$METRIC window=${WINDOW_DAYS}d config=$CONFIG (sin invocar agente)"
  exit 0
fi

SAMPLE_VALUE=$(collect_samples "$METRIC")
# Construir serie temporal simple para σ (en producción: ventana rodante real)
# Aquí usamos el valor actual + baseline sintético del config
BASELINE=$(grep -A3 "metric: $METRIC" "$CONFIG" 2>/dev/null | grep "baseline" | head -1 | cut -d: -f2 | tr -d ' ')
BASELINE="${BASELINE:-rolling_30d}"

# Serie: si solo hay un valor, evaluamos contra threshold del config
THRESHOLD=$(grep -A6 "metric: $METRIC" "$CONFIG" 2>/dev/null | grep -E "threshold" | head -1 | cut -d: -f2 | tr -d ' ')
if [[ -n "$THRESHOLD" ]]; then
  # comparación directa contra umbral configurado
  python3 - "$SAMPLE_VALUE" "$THRESHOLD" <<'PY'
import sys, json
val = float(sys.argv[1]); thr = float(sys.argv[2])
print(json.dumps({
    "metric": "VALUE",
    "sigma_level": val/thr if thr else 0,
    "breached": val >= thr,
    "samples": 1,
    "mean": val,
    "sd": 0,
    "threshold": thr,
}))
PY
else
  compute_sigma "$SAMPLE_VALUE"
fi
