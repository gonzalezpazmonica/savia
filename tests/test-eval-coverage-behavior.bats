#!/usr/bin/env bats
# Ref: SE-381 / SE-387 D — la cobertura L4 solo cuenta evals de comportamiento;
# las de definicion (grep sobre el prompt del agente) se reportan aparte.
# Cubre scripts/eval-coverage-matrix.py y el gate eval-coverage-L4 de
# scripts/coherence-gates.sh.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  set -o pipefail
  TMP=$(mktemp -d)
  R="$TMP/root"
  mkdir -p "$R/scripts" "$R/.scm" "$R/tests/bats" "$R/tests/evals" "$R/output"
  cp "$REPO_ROOT/scripts/eval-coverage-matrix.py" "$REPO_ROOT/scripts/derived_canon.py" "$R/scripts/"
  # derived.sh de mentira: el registry ya existe en la raiz de prueba.
  printf '#!/bin/bash\nexit 0\n' > "$R/scripts/derived.sh"
  python3 - "$R/.scm/registry.json" <<'PYEOF'
import json, sys
caps = [{"id": "agent:.claude/agents/%s" % n, "kind": "agent", "risk_level": "L4"}
        for n in ("grep-only", "behavioral", "mixed")]
json.dump({"capabilities": caps}, open(sys.argv[1], "w"))
PYEOF
  mkdir -p "$R/contracts/capabilities"
  for n in grep-only behavioral mixed; do
    touch "$R/tests/bats/$n-l4.bats"
    printf 'id: agent.%s\nlaws:\n  - LAW-X-001\nenforcement:\n  - j\nnegative_tests:\n  - t\n' "$n" > "$R/contracts/capabilities/agent.$n.yaml"
  done
}

teardown() {
  rm -rf "$TMP"
}

# fixture <agente> <escenario> <tipo: definition|behavior|declarative>
fixture() {
  mkdir -p "$R/tests/evals/$1"
  case "$3" in
    definition) printf '{"scenario":"%s","agent":"%s","cases":[{"id":"c","checks":[{"id":"x","target":"agent","must_match":"veto"}]}]}' "$2" "$1" ;;
    behavior)   printf '{"scenario":"%s","agent":"%s","cases":[{"id":"c","checks":[],"aggregate":{"judges":[],"expect":{"exit":0}}}]}' "$2" "$1" ;;
    declarative) printf '{"scenario":"%s","agent":"%s","cases":[{"input":"vacia","expected":"fail suave"}]}' "$2" "$1" ;;
  esac > "$R/tests/evals/$1/$2.json"
}

all_fixtures() { # <agente> <tipo>
  for s in golden edge adversarial bypass; do fixture "$1" "$s" "$2"; done
}

run_matrix() {
  python3 "$R/scripts/eval-coverage-matrix.py" --root "$R" >/dev/null
}

row() { # <agente> <campo>
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps([r for r in d['rows'] if r['id'].endswith('/'+sys.argv[2])][0][sys.argv[3]]))" \
    "$R/output/eval-coverage-matrix.json" "$1" "$2"
}

@test "agente cuyas pruebas son solo grep no cuenta como cubierto: missing de comportamiento" {
  all_fixtures grep-only definition
  run_matrix
  [ "$(row grep-only covered)" = "false" ]
}

@test "la cobertura de definicion se reporta aparte y sigue completa" {
  all_fixtures grep-only definition
  run_matrix
  [ "$(row grep-only covered_definition)" = "true" ]
  [ "$(row grep-only definition_checks)" -ge 1 ]
}

@test "fixtures declarativos empty de checks y agregador no cuentan como comportamiento" {
  all_fixtures grep-only declarative
  run_matrix
  [ "$(row grep-only covered)" = "false" ]
}

@test "agente con evals de comportamiento ejecutadas cuenta como cubierto" {
  all_fixtures behavioral behavior
  run_matrix
  [ "$(row behavioral covered)" = "true" ]
  [ "$(row behavioral behavior_cases)" -ge 4 ]
}

@test "boundary: solo golden de comportamiento y el resto grep deja el agente descubierto, missing edge" {
  fixture mixed golden behavior
  for s in edge adversarial bypass; do fixture mixed "$s" definition; done
  run_matrix
  [ "$(row mixed covered)" = "false" ]
  [ "$(row mixed covered_definition)" = "true" ]
  [[ "$(row mixed missing)" == *"edge"* ]]
}

@test "resumen por riesgo cuenta solo comportamiento y expone el de definicion" {
  all_fixtures grep-only definition
  all_fixtures behavioral behavior
  run_matrix
  run python3 -c "import json,sys; d=json.load(open(sys.argv[1]))['summary_by_risk']['L4']; print(d['total'], d['covered'], d['covered_definition'])" "$R/output/eval-coverage-matrix.json"
  [ "$output" = "3 1 2" ]
}

@test "el informe markdown separa evals de definicion y de comportamiento" {
  all_fixtures grep-only definition
  run_matrix
  grep -qi "definici" "$R/output/eval-coverage-matrix.md"
  grep -qi "comportamiento" "$R/output/eval-coverage-matrix.md"
}

@test "zero fixtures: agente sin carpeta queda descubierto, no null ni error" {
  run_matrix
  [ "$(row grep-only covered)" = "false" ]
  [ "$(row grep-only behavior_cases)" = "0" ]
}

@test "nonexistent json valido: fixture corrupto con aggregate en el texto no cuenta" {
  mkdir -p "$R/tests/evals/grep-only"
  for s in golden edge adversarial bypass; do
    printf '{"aggregate": no es json' > "$R/tests/evals/grep-only/$s.json"
  done
  run_matrix
  [ "$(row grep-only covered)" = "false" ]
  [ "$(row grep-only behavior_cases)" = "0" ]
}

# ── gate en coherence-gates.sh ─────────────────────────────────────────

gate_root() { # $1 = contenido del JSON de la matriz
  G="$TMP/gate"
  mkdir -p "$G/scripts" "$G/output" "$G/tests/chaos"
  cp "$REPO_ROOT/scripts/coherence-gates.sh" "$G/scripts/"
  for s in guardrail-negative-tests.sh debt-budget-check.sh contract-check.sh law-check.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$G/scripts/$s"
  done
  printf '#!/bin/bash\nexit 0\n' > "$G/tests/chaos/run-chaos-suite.sh"
  printf 'import sys\nsys.exit(0)\n' > "$G/scripts/capability-entropy.py"
  printf 'import sys\nsys.exit(0)\n' > "$G/scripts/constitutional-coverage.py"
  printf 'import sys, os\nopen(os.path.join(sys.argv[2], "output", "eval-coverage-matrix.json"), "w").write(%s)\n' \
    "$(python3 -c 'import sys; print(repr(sys.argv[1]))' "$1")" > "$G/scripts/eval-coverage-matrix.py"
  : > "$G/scripts/coherence-gate-policy.yaml"
}

@test "gate: cobertura solo de definicion no da PASS (fail honesto) e informa el numero real" {
  gate_root '{"rows":[{"risk":"L4","covered":false,"covered_definition":true},{"risk":"L4","covered":false,"covered_definition":true}]}'
  run bash "$G/scripts/coherence-gates.sh"
  [[ "$output" != *"PASS coherence/eval-coverage-L4"* ]]
  [[ "$output" == *"coherence/eval-coverage-L4"*"comportamiento 0/2"* ]]
  [[ "$output" == *"definicion 2/2"* ]]
}

@test "gate: perder cobertura de definicion sigue en block (sin bajar umbrales)" {
  gate_root '{"rows":[{"risk":"L4","covered":false,"covered_definition":false}]}'
  run bash "$G/scripts/coherence-gates.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK coherence/eval-coverage-L4"* ]]
}

@test "gate: comportamiento completo da PASS con el recuento real" {
  gate_root '{"rows":[{"risk":"L4","covered":true,"covered_definition":true},{"risk":"L4","covered":true,"covered_definition":true}]}'
  run bash "$G/scripts/coherence-gates.sh"
  [[ "$output" == *"PASS coherence/eval-coverage-L4: comportamiento 2/2"* ]]
}
