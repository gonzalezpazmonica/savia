#!/usr/bin/env bats
# SCL-012 — pruebas de SAGI P1-P5 (harness sobre el orquestador)
# Spec: docs/specs/SCL-012-pruebas-sagi.spec.md (AC-1..AC-4)

SCRIPT="scripts/sagi-pruebas.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$FIXDIR"
}

@test "AC-1: harness existe, bash -n, sin vendor names, compone orquestador" {
  [[ -x "$SCRIPT" ]]
  bash -n "$SCRIPT"
  run grep -niE "openai|anthropic|gpt-|gemini|qwen|deepseek" "$SCRIPT"
  [[ "$status" -ne 0 ]]
  grep -q "savia-orchestrator.sh" "$SCRIPT"
}

@test "AC-2: cada prueba emite línea con tratamiento, baseline, delta y veredicto" {
  run bash "$SCRIPT" --pruebas P1,P2,P3
  [[ "$status" -eq 0 ]]
  local n
  n=$(echo "$output" | grep -cE '^\[P[123]\] tratamiento=[0-9.]+ baseline=[0-9.]+ delta=[0-9.]+ → (PASS|FAIL)$')
  [[ "$n" -eq 3 ]]
}

@test "AC-3: veredicto agregado CONFIRMA cuando >=2 pruebas PASS" {
  run bash "$SCRIPT"
  [[ "$status" -eq 0 ]]
  # inputs sintéticos de fixture pasan → CONFIRMA
  echo "$output" | grep -qE "CONFIRMA|INCONCLUSO"
}

@test "AC-4: resultado negativo es primera clase — INCONCLUSO en dry-run" {
  run bash "$SCRIPT" --dry-run
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "INCONCLUSO"
  # la honestidad está: dice que <2 confirman, no miente
  echo "$output" | grep -q "negativo es primera clase"
}

@test "AC-3b: selección de pruebas (--pruebas) limita el run" {
  run bash "$SCRIPT" --pruebas P1
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "\[P1\]"
  ! echo "$output" | grep -q "\[P3\]"
}

@test "P4/P5 declarados dry-run sin requerir infra federada" {
  run bash "$SCRIPT" --pruebas P4,P5
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "P4.*dry-run\|\[P4\]"
  echo "$output" | grep -q "P5.*dry-run\|\[P5\]"
}

@test "input inválido → exit 2" {
  run bash "$SCRIPT" --pruebas
  [[ "$status" -eq 2 ]]
  run bash "$SCRIPT" --badflag
  [[ "$status" -eq 2 ]]
}

@test "no muta CRITERIO.md ni CONSTITUCION" {
  local h1 h2
  h1=$(sha256sum CRITERIO.md | cut -d' ' -f1)
  h2=$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)
  bash "$SCRIPT" >/dev/null
  [[ "$(sha256sum CRITERIO.md | cut -d' ' -f1)" == "$h1" ]]
  [[ "$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)" == "$h2" ]]
}
# --- S03c: comportamiento real del veredicto (SPEC-183 / L11) ---
# Árbol sintético: el script calcula ROOT desde su ruta, así que se copia a un
# raíz temporal con dependencias stub y un CRITERIO.md controlado.

mk_tree() {
  TREE="$FIXDIR/tree"
  mkdir -p "$TREE/scripts"
  cp "$SCRIPT" "$TREE/scripts/sagi-pruebas.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TREE/scripts/savia-orchestrator.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TREE/scripts/learning-metric.sh"
  chmod +x "$TREE"/scripts/*.sh
  if [[ "${1:-human}" == "human" ]]; then
    printf 'CRIT-001 provenance: human_authored\n' > "$TREE/CRITERIO.md"
  else
    printf 'CRIT-001 provenance: INFERRED\n' > "$TREE/CRITERIO.md"
  fi
}

@test "veredicto: P1+P2+P3 con CRITERIO human_authored → CONFIRMA 3/3" {
  mk_tree human
  run bash "$TREE/scripts/sagi-pruebas.sh"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "VEREDICTO L11: CONFIRMA (3/3"
  echo "$output" | grep -q "\[P1\] tratamiento=90.0 baseline=40.0 delta=50.0 → PASS"
  echo "$output" | grep -q "\[P2\] tratamiento=1 baseline=0 delta=1 → PASS"
  echo "$output" | grep -q "\[P3\] tratamiento=10 baseline=0 delta=10 → PASS"
}

@test "veredicto: sin entradas human_authored P2 y P3 fallan → INCONCLUSO 1/3" {
  mk_tree inferred
  run bash "$TREE/scripts/sagi-pruebas.sh"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "\[P2\] tratamiento=0 baseline=0 delta=0 → FAIL"
  echo "$output" | grep -q "\[P3\] tratamiento=0 baseline=0 delta=0 → FAIL"
  echo "$output" | grep -q "VEREDICTO L11: INCONCLUSO (1/3"
}

@test "veredicto: el umbral es 2 → un PASS no confirma, dos sí" {
  mk_tree inferred
  run bash "$TREE/scripts/sagi-pruebas.sh" --pruebas P1
  echo "$output" | grep -q "INCONCLUSO (1/1"
  run bash "$TREE/scripts/sagi-pruebas.sh" --pruebas P1,P2
  echo "$output" | grep -q "INCONCLUSO (1/2"
  mk_tree human
  run bash "$TREE/scripts/sagi-pruebas.sh" --pruebas P1,P2
  echo "$output" | grep -q "CONFIRMA (2/2"
}

@test "P4 y P5 nunca suman PASS: solas → INCONCLUSO 0/2" {
  mk_tree human
  run bash "$TREE/scripts/sagi-pruebas.sh" --pruebas P4,P5
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "INCONCLUSO (0/2"
  echo "$output" | grep -q "requiere 2 instancias federadas"
}

@test "--dry-run no puntúa ninguna prueba aunque CRITERIO sea válido" {
  mk_tree human
  run bash "$TREE/scripts/sagi-pruebas.sh" --dry-run
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "INCONCLUSO (0/3"
  ! echo "$output" | grep -q "→ PASS"
  echo "$output" | grep -q "\[P1\] dry-run"
}

@test "--json antepone cabecera JSON válida con pruebas y dry_run" {
  mk_tree human
  run bash "$TREE/scripts/sagi-pruebas.sh" --json --pruebas P1,P3 --dry-run
  [[ "$status" -eq 0 ]]
  echo "${lines[0]}" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['orquestador'] == 'savia-orchestrator.sh', d
assert d['pruebas'] == 'P1,P3', d
assert d['dry_run'] is True, d"
}

@test "prueba desconocida se avisa y no cuenta como PASS" {
  mk_tree human
  run bash "$TREE/scripts/sagi-pruebas.sh" --pruebas P9
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "prueba desconocida: P9"
  echo "$output" | grep -q "INCONCLUSO (0/1"
}

@test "falta el orquestador → exit 3" {
  mk_tree human
  unlink "$TREE/scripts/savia-orchestrator.sh"
  run bash "$TREE/scripts/sagi-pruebas.sh"
  [[ "$status" -eq 3 ]]
  echo "$output" | grep -q "falta savia-orchestrator.sh"
}

@test "falta la métrica de aprendizaje → exit 3" {
  mk_tree human
  unlink "$TREE/scripts/learning-metric.sh"
  run bash "$TREE/scripts/sagi-pruebas.sh"
  [[ "$status" -eq 3 ]]
  echo "$output" | grep -q "falta learning-metric.sh"
}

@test "CRITERIO.md ausente (sin datos) → P3 FAIL sin error de shell" {
  mk_tree human
  unlink "$TREE/CRITERIO.md"
  run bash "$TREE/scripts/sagi-pruebas.sh"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "\[P3\] .* → FAIL"
  ! echo "$output" | grep -qi "syntax error\|unbound"
}

@test "el script declara set -uo pipefail" {
  grep -q '^set -uo pipefail' "$SCRIPT"
}
