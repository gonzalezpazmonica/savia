#!/usr/bin/env bash
# gate-unknown-check.sh — contador de gates en «unknown» frente al baseline (SE-453 D3).
# Cuenta los gates distintos con una línea de hoy en output/unmeasured-gates.jsonl y los compara con
# config/gate-unknown-baseline.txt (solo puede bajar). Primer ciclo: aviso (WARN, exit 0).
# GATE_UNKNOWN_ENFORCE=1 lo convierte en fallo (exit 1). Salida: una línea PASS/WARN/FAIL.
# Doc: docs/rules/domain/gate-result-contract.md
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${GATE_UNMEASURED_LOG:-$ROOT/output/unmeasured-gates.jsonl}"
BASELINE_FILE="${GATE_UNKNOWN_BASELINE:-$ROOT/config/gate-unknown-baseline.txt}"
DAY="$(date +%Y-%m-%d)"

if [[ ! -f "$BASELINE_FILE" ]] || ! [[ "$(tr -d '[:space:]' < "$BASELINE_FILE")" =~ ^[0-9]+$ ]]; then
  echo "FAIL gate-unknown: baseline ausente o no numérico ($BASELINE_FILE)"
  exit 1
fi
BASELINE="$(tr -d '[:space:]' < "$BASELINE_FILE")"

HOOKS=""
if [[ -f "$LOG" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "WARN gate-unknown: python3 ausente, no se puede leer $LOG (no medido)"
    exit 0
  fi
  HOOKS="$(python3 - "$LOG" "$DAY" <<'PYEOF'
import json, sys
seen = set()
for n, line in enumerate(open(sys.argv[1]), 1):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        print("INVALID:%d" % n)
        sys.exit(0)
    if d.get("day") == sys.argv[2] and d.get("hook"):
        seen.add(d["hook"])
print(",".join(sorted(seen)))
PYEOF
)"
fi
if [[ "$HOOKS" == INVALID:* ]]; then
  echo "FAIL gate-unknown: línea ${HOOKS#INVALID:} de $LOG no es JSON"
  exit 1
fi

COUNT=0
[[ -n "$HOOKS" ]] && COUNT="$(printf '%s\n' "$HOOKS" | tr ',' '\n' | wc -l)"
if [[ "$COUNT" -le "$BASELINE" ]]; then
  echo "PASS gate-unknown: $COUNT gates en unknown (baseline $BASELINE)"
  exit 0
fi
if [[ "${GATE_UNKNOWN_ENFORCE:-0}" == "1" ]]; then
  echo "FAIL gate-unknown: $COUNT gates en unknown (baseline $BASELINE): $HOOKS"
  exit 1
fi
echo "WARN gate-unknown: $COUNT gates en unknown (baseline $BASELINE): $HOOKS (ciclo de aviso, D3)"
exit 0
