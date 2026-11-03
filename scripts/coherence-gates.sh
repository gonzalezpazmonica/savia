#!/usr/bin/env bash
# coherence-gates.sh — SE-377/380/381/383: gates de coherencia (advisory por defecto).
# Uso: coherence-gates.sh [--strict]
set -uo pipefail
ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
POLICY="$ROOT/scripts/coherence-gate-policy.yaml"
STRICT="false"
[[ "${1:-}" == "--strict" ]] && STRICT="true"
FAILED=0
# SE-387 Slice A: un gate declarado BLOCK con calibration complete bloquea
gate_status() { # $1=id → imprime BLOCK|WARN|OBSERVE|WARN (default)
  local id="$1" st
  st=$(awk "/- id: $id\$/{f=1} f&&/status:/{print \$2; exit}" "$POLICY" 2>/dev/null)
  echo "${st:-WARN}"
}
is_calibrated() { # $1=id
  awk "/- id: $1\$/{f=1} f&&/calibration:/{print \$2; exit}" "$POLICY" 2>/dev/null
}
echo "--- Coherence gates (SE-377/380/381/383/386) ---"
BLOCKED_FATAL=0
run_gate() { # $1 nombre $2 comando...
  local name="$1"; shift
  local st; st=$(gate_status "$name")
  local out
  if out=$( "$@" 2>&1 ); then
    echo "PASS coherence/$name"
  else
    local cal; cal=$(is_calibrated "$name")
    echo "${st} coherence/$name (calibration=${cal:-unknown})"
    if [[ "$st" == "BLOCK" && "$cal" == "complete" ]]; then
      echo "BLOCK coherence/$name: gate calibrado y graduado a bloqueante (SE-387 A1)"
      BLOCKED_FATAL=1
    else
      FAILED=1
    fi
  fi
}
run_gate negative-safety bash "$ROOT/scripts/guardrail-negative-tests.sh"
run_gate chaos-suite bash "$ROOT/tests/chaos/run-chaos-suite.sh"
run_gate entropy python3 "$ROOT/scripts/capability-entropy.py" --root "$ROOT" --check
run_gate debt-budget bash "$ROOT/scripts/debt-budget-check.sh" "$ROOT"
run_gate constitutional-contracts bash "$ROOT/scripts/contract-check.sh"
run_gate constitutional-contracts bash "$ROOT/scripts/law-check.sh"
run_gate constitutional-coverage python3 "$ROOT/scripts/constitutional-coverage.py" --root "$ROOT"
# Cierre del harness (C F2-F5 + E + F + H). Hueco G3: estar presente y ser
# ejecutable no es estar aplicado. PASS solo si el script está en el camino del
# efecto (hook de .claude/settings.json, fichero de hook registrado o workflow de
# CI; evaluador único: frontend-probe.sh --wired). Si no, DECLARED (WARN).
CLOSURE_DECLARED=0
for t in grounding-verify.sh validate-handoff.sh validate-handoff-integrity.sh checkpoint.sh effect-reservation.sh debt-burn-down.sh planning-transition.sh report-benchmark.sh; do
  if [[ ! -x "$ROOT/scripts/$t" && ! -x "$ROOT/tests/self-evolution/$t" ]]; then
    echo "WARN coherence/closure-$t: ausente o no ejecutable"; FAILED=1; CLOSURE_DECLARED=1; continue
  fi
  bash "$ROOT/scripts/frontend-probe.sh" --wired "$t" >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "PASS coherence/closure-$t: en el camino del efecto"
  elif [[ $rc -eq 1 ]]; then
    echo "WARN coherence/closure-$t: DECLARED (presente, sin hook ni CI que lo aplique)"; FAILED=1; CLOSURE_DECLARED=1
  else
    echo "WARN coherence/closure-$t: DECLARED (no se pudo evaluar el cableado, exit $rc)"; FAILED=1; CLOSURE_DECLARED=1
  fi
done
if [[ $CLOSURE_DECLARED -eq 0 ]]; then
  echo "PASS coherence/harness-closure: C F2-F5 + E + F + H aplicados por hook o CI"
else
  echo "WARN coherence/harness-closure: DECLARED (tooling presente, no todo en el camino del efecto)"
fi
# Eval coverage L4 (SE-387 D): sin matriz legible no hay PASS (fail-closed).
EVAL_OUT=""
if python3 "$ROOT/scripts/eval-coverage-matrix.py" --root "$ROOT" >/dev/null 2>&1; then
  EVAL_OUT=$(python3 - "$ROOT/output/eval-coverage-matrix.json" <<'PYEOF' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
l4 = [r for r in d["rows"] if r["risk"] == "L4"]
bad = [r for r in l4 if not r["covered"]]
print(("FAIL" if bad or not l4 else "OK"), len(l4) - len(bad), len(l4))
PYEOF
)
fi
read -r EVAL_V EVAL_C EVAL_T <<< "${EVAL_OUT:-ERROR 0 0}"
if [[ "$EVAL_V" == "OK" ]]; then
  echo "PASS coherence/eval-coverage-L4: $EVAL_C/$EVAL_T cubiertas"
elif [[ "$EVAL_V" == "FAIL" ]]; then
  echo "BLOCK coherence/eval-coverage-L4: capability L4 perdió cobertura ($EVAL_C/$EVAL_T) (SE-387 D)"
  BLOCKED_FATAL=1
else
  echo "BLOCK coherence/eval-coverage-L4: matriz de cobertura no evaluable (fail-closed, SE-387 D)"
  BLOCKED_FATAL=1
fi
if [[ $BLOCKED_FATAL -eq 1 ]]; then
  echo "-- coherence gates: BLOCK (L4 graduado, SE-387 A1)"
  exit 1
fi
echo "-- coherence gates: sin bloqueo L4 (advisory/WARN restante)"
exit 0
