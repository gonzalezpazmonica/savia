#!/usr/bin/env bats
# test-se237-coarse-to-fine.bats
#
# Tests SE-237: Patrón Coarse-to-Fine en DAG Scheduling
# Ref: docs/propuestas/SE-237-coarse-to-fine-dag-pattern.md

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
NIDO="$REPO_ROOT"
SCRIPT="${NIDO}/scripts/dag-gate-cost-checker.sh"

# ── Fixture helpers ──────────────────────────────────────────────────────────
create_dag_correct() {
  cat > "$1" <<'YAML'
stages:
  - name: spec-validator
    gate_type: CHEAP
  - name: test-runner
    gate_type: MEDIUM
  - name: court-orchestrator
    gate_type: EXPENSIVE
YAML
}

create_dag_incorrect() {
  cat > "$1" <<'YAML'
stages:
  - name: court-orchestrator
    gate_type: EXPENSIVE
  - name: spec-validator
    gate_type: CHEAP
  - name: test-runner
    gate_type: MEDIUM
YAML
}

create_dag_only_cheap() {
  cat > "$1" <<'YAML'
stages:
  - name: validate-spec
    gate_type: CHEAP
  - name: hashline-guard
    gate_type: CHEAP
  - name: bash-syntax-check
    gate_type: CHEAP
YAML
}

# ── Test 1: SE-237 spec existe ────────────────────────────────────────────────
@test "SE-237 spec existe en docs/propuestas/" {
  [ -f "${NIDO}/docs/propuestas/SE-237-coarse-to-fine-dag-pattern.md" ]
}

# ── Test 2: coarse-to-fine-gates.md existe y ≤150 líneas ─────────────────────
@test "coarse-to-fine-gates.md existe y tiene ≤150 líneas" {
  [ -f "${NIDO}/docs/rules/domain/coarse-to-fine-gates.md" ]
  line_count=$(wc -l < "${NIDO}/docs/rules/domain/coarse-to-fine-gates.md")
  [ "$line_count" -le 150 ]
}

# ── Test 3: dag-gate-cost-checker.sh existe y pasa bash -n ───────────────────
@test "dag-gate-cost-checker.sh existe y pasa bash -n syntax check" {
  [ -f "$SCRIPT" ]
  bash -n "$SCRIPT"
}

# ── Test 4: DAG correcto (cheap→medium→expensive) → exit 0 ───────────────────
@test "DAG correcto cheap→medium→expensive → exit 0" {
  tmp=$(mktemp /tmp/dag-correct-XXXXXX.yaml)
  create_dag_correct "$tmp"
  run bash "$SCRIPT" "$tmp"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}

# ── Test 5: DAG incorrecto → exit 1 con mensaje ──────────────────────────────
@test "DAG incorrecto (expensive antes de cheap) → exit 1 con mensaje de error" {
  tmp=$(mktemp /tmp/dag-incorrect-XXXXXX.yaml)
  create_dag_incorrect "$tmp"
  run bash "$SCRIPT" "$tmp"
  rm -f "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "VIOLATION" ]] || [[ "$output" =~ "violaci" ]]
}

# ── Test 6: DAG con solo cheap → exit 0 ──────────────────────────────────────
@test "DAG con solo gates CHEAP → exit 0" {
  tmp=$(mktemp /tmp/dag-cheap-XXXXXX.yaml)
  create_dag_only_cheap "$tmp"
  run bash "$SCRIPT" "$tmp"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}

# ── Test 7: DAG vacío → exit 0 ───────────────────────────────────────────────
@test "DAG vacío → exit 0 (nada que verificar)" {
  tmp=$(mktemp /tmp/dag-empty-XXXXXX.yaml)
  echo "" > "$tmp"
  run bash "$SCRIPT" "$tmp"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}

# ── Test 8: coarse-to-fine-gates.md menciona CHEAP, MEDIUM, EXPENSIVE ────────
@test "coarse-to-fine-gates.md menciona 'CHEAP', 'MEDIUM', 'EXPENSIVE'" {
  grep -q "CHEAP" "${NIDO}/docs/rules/domain/coarse-to-fine-gates.md"
  grep -q "MEDIUM" "${NIDO}/docs/rules/domain/coarse-to-fine-gates.md"
  grep -q "EXPENSIVE" "${NIDO}/docs/rules/domain/coarse-to-fine-gates.md"
}

# ── Test 9: docs menciona feasibility-probe como gate CHEAP/MEDIUM ───────────
@test "docs menciona feasibility-probe como ejemplo de gate" {
  grep -qi "feasibility-probe" "${NIDO}/docs/rules/domain/coarse-to-fine-gates.md"
}

# ── Test 10: docs menciona court-orchestrator como gate EXPENSIVE ─────────────
@test "docs menciona court-orchestrator como ejemplo de gate EXPENSIVE" {
  grep -qi "court-orchestrator" "${NIDO}/docs/rules/domain/coarse-to-fine-gates.md"
}

# ── S03o: comportamiento discriminante del checker (stdin, YAML multilínea, errores) ──

setup() {
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/dag.XXXXXX")"
}

# yaml_pair <fichero> <tipo1> <tipo2>: dos pasos con nombres sin clasificar; solo cuenta gate_type.
yaml_pair() {
  printf 'stages:\n  - name: paso-uno\n    gate_type: %s\n  - name: paso-dos\n    gate_type: %s\n' "$2" "$3" > "$1"
}

@test "checker: declara set -euo pipefail" {
  head -40 "$SCRIPT" | grep -q "set -euo pipefail"
}

@test "YAML multilínea: el gate_type de la línea siguiente se respeta (EXPENSIVE antes de CHEAP → exit 1)" {
  yaml_pair "$T/v.yaml" EXPENSIVE CHEAP
  run bash "$SCRIPT" "$T/v.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'paso-dos' (CHEAP, cost=1) aparece después de 'paso-uno' (EXPENSIVE, cost=3)"* ]]
}

@test "YAML multilínea: CHEAP antes de EXPENSIVE con nombres sin clasificar → exit 0" {
  yaml_pair "$T/ok.yaml" CHEAP EXPENSIVE
  run bash "$SCRIPT" "$T/ok.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"orden coarse-to-fine correcto"* ]]
}

@test "stdin: un DAG con violación da exit 1 (antes leía vacío y daba PASS)" {
  yaml_pair "$T/v.yaml" EXPENSIVE CHEAP
  run bash -c 'bash "$1" < "$2"' _ "$SCRIPT" "$T/v.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 violación(es)"* ]]
}

@test "stdin: DAG correcto da exit 0 y no lo trata como vacío" {
  create_dag_correct "$T/c.yaml"
  run bash -c 'bash "$1" < "$2"' _ "$SCRIPT" "$T/c.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"orden coarse-to-fine correcto"* ]]
}

@test "stdin vacío (empty): exit 0, DAG vacío" {
  run bash -c 'bash "$1" < /dev/null' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DAG vacío"* ]]
}

@test "JSON inválido: exit 2 (antes exit 0)" {
  printf '{"stages": [' > "$T/bad.json"
  run bash "$SCRIPT" "$T/bad.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"JSON inválido"* ]]
}

@test "JSON con lista en la raíz: exit 2 (invalid)" {
  printf '["court-orchestrator","lint"]' > "$T/list.json"
  run bash "$SCRIPT" "$T/list.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"debe ser un objeto"* ]]
}

@test "JSON con stages que no es lista o elemento numérico: exit 2 (invalid)" {
  printf '{"stages": "lint"}' > "$T/s.json"
  run bash "$SCRIPT" "$T/s.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"'stages' debe ser una lista"* ]]
  printf '{"stages": ["lint", 7]}' > "$T/n.json"
  run bash "$SCRIPT" "$T/n.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"elemento no válido"* ]]
}

@test "fichero inexistente (nonexistent): exit 2 con la ruta" {
  run bash "$SCRIPT" "$T/no-existe.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"fichero no encontrado: $T/no-existe.yaml"* ]]
}

@test "JSON con id y type en lugar de name y gate_type" {
  printf '{"gates":[{"id":"g1","type":"medium"},{"id":"g2","type":"cheap"}]}' > "$T/g.json"
  run bash "$SCRIPT" "$T/g.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'g2' (CHEAP, cost=1) aparece después de 'g1' (MEDIUM, cost=2)"* ]]
}

@test "steps planos: tipo inferido por la tabla de agentes en los dos sentidos" {
  printf 'steps:\n  - feasibility-probe\n  - test-runner\n  - court-orchestrator\n' > "$T/ok.yaml"
  run bash "$SCRIPT" "$T/ok.yaml"
  [ "$status" -eq 0 ]
  printf 'steps:\n  - court-orchestrator\n  - spec-validator\n' > "$T/bad.yaml"
  run bash "$SCRIPT" "$T/bad.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'spec-validator' (CHEAP"* ]]
}

@test "inferencia por patrón de nombre y MEDIUM por defecto" {
  printf 'pipeline:\n  - x-audit\n  - nombre-raro\n  - my-lint-step\n' > "$T/p.yaml"
  run bash "$SCRIPT" "$T/p.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'nombre-raro' (MEDIUM, cost=2)"* ]]
  [[ "$output" == *"'my-lint-step' (CHEAP, cost=1)"* ]]
  [[ "$output" == *"'x-audit' (EXPENSIVE, cost=3)"* ]]
  [[ "$output" == *"2 violación(es)"* ]]
}

@test "mismo coste consecutivo es correcto (límite)" {
  yaml_pair "$T/eq.yaml" MEDIUM MEDIUM
  run bash "$SCRIPT" "$T/eq.yaml"
  [ "$status" -eq 0 ]
}

@test "la violación se mide contra el máximo visto, no solo contra el paso anterior" {
  printf '{"stages":[{"name":"a","gate_type":"CHEAP"},{"name":"b","gate_type":"EXPENSIVE"},{"name":"c","gate_type":"CHEAP"},{"name":"d","gate_type":"MEDIUM"}]}' > "$T/m.json"
  run bash "$SCRIPT" "$T/m.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 violación(es)"* ]]
  [[ "$output" == *"'d' (MEDIUM, cost=2) aparece después de 'c' (CHEAP, cost=1)"* ]]
}

@test "YAML con comentarios y otra sección raíz: solo cuenta la lista del DAG" {
  printf '# plan\nnombre: demo\nsteps:\n  # primero lo barato\n  - lint\n  - court-orchestrator\notros:\n  - spec-validator\n' > "$T/c.yaml"
  run bash "$SCRIPT" "$T/c.yaml"
  [ "$status" -eq 0 ]
}

@test "stages tiene prioridad sobre steps cuando hay los dos" {
  printf '{"stages":[{"name":"a","gate_type":"CHEAP"}],"steps":["court-orchestrator","lint"]}' > "$T/both.json"
  run bash "$SCRIPT" "$T/both.json"
  [ "$status" -eq 0 ]
}

@test "nombre con barra vertical no desplaza el tipo" {
  printf '{"stages":[{"name":"a|EXPENSIVE","gate_type":"CHEAP"},{"name":"b","gate_type":"CHEAP"}]}' > "$T/pipe.json"
  run bash "$SCRIPT" "$T/pipe.json"
  [ "$status" -eq 0 ]
}

@test "stdin con JSON inválido: exit 2, no PASS" {
  run bash -c 'printf "{\"stages\": [" | bash "$1"' _ "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"JSON inválido"* ]]
}

@test "una clave raíz con valor cierra la lista anterior" {
  printf 'steps:\n  - lint\nversion: 2\n  - court-orchestrator\n  - spec-validator\n' > "$T/close.yaml"
  run bash "$SCRIPT" "$T/close.yaml"
  [ "$status" -eq 0 ]
}
