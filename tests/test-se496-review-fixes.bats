#!/usr/bin/env bats

# Ref: docs/specs/SE-496-governed-operational-ontology-authority.spec.md (F0)
# Regresiones de la revisión independiente de la PR #1528 (correctness + security).
# Cada caso lleva su control positivo en el mismo mundo hermético (tests/fixtures/se496/review_fixes.py).

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  F="python3 tests/fixtures/se496/review_fixes.py"
  TMP=$(mktemp -d -p "$BATS_TEST_TMPDIR")  # bats borra BATS_TEST_TMPDIR al terminar cada test
}

teardown() {
  unset TMP
}

@test "P1-1: el kernel real ignora SAVIA_AUTHORITY_* aunque venga TEST=1 y ssh-keygen=/bin/true; el envoltorio de tests da ALLOW" {
  run $F env-bypass
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "P1-1: el kernel no lee el entorno para redirigirse (environ/getenv solo dentro de test_mode)" {
  # cualquier forma: os.environ[...], .get, getenv, environb; la unica excepcion es heredar el entorno en modo test
  run bash -c "grep -nE 'environ|getenv' scripts/lib/authority_kernel.py | grep -v 'if test_mode()'"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run grep -c 'environ' scripts/lib/authority_kernel.py
  [ "$output" -ge 1 ]
  run grep -c 'SAVIA_AUTHORITY_TEST' tests/helpers/se496_kernel_entry.py
  [ "$output" -ge 1 ]
}

@test "P1-2: PR de 101 ficheros con workflow en el 101 -> REVIEW_REQUIRED; lista incompleta, sin changedFiles o ruta con espacios -> UNKNOWN_STATE" {
  run $F tier-files
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "P2-1: subir el nivel del agente en el árbol de trabajo no cuenta; en origin/main sí" {
  run $F level-main
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "P2-1: la propiedad de los hechos sale de la ontología de origin/main, no del árbol de trabajo" {
  run $F ontology-main
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "P2-3: Branch.ci_status consulta todas las ejecuciones del head exacto; un workflow en rojo no cumple" {
  run $F ci-head
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "corr. 4: hechos de Branch con target.repo distinto del remoto local -> UNKNOWN_STATE" {
  run $F branch-repo
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "P2-4 boundary: recibo previo de 10 min vale; 10 min 1 s, futuro o sin fecha -> STATE_CHANGED" {
  run $F prior-age
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "corr. 3: pr.merge en borrador o con CI no verde -> PRECONDITION_FAILED; listo pasa a la puerta de nivel" {
  run $F merge-pre
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "P2-5: una mutación que revienta cuenta como CRASHED, no como KILLED" {
  run $F mutation-crash
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 2 P1-1: params atados al objetivo; params.branch=main, params.project=otro, ruta fuera de paths, parámetro no declarado o action.name ajeno -> DENY; controles ALLOW" {
  run $F params-scope
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 2 P2-2: checks solo saltados o neutros no son CI verde para pr.merge; con un SUCCESS real sí" {
  run $F ci-skipped
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 2 corr.: 200 ejecuciones del head (límite de gh run list) -> UNKNOWN_STATE; 199 -> ALLOW" {
  run $F runs-limit
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "review_fixes.py rechaza un caso desconocido con exit 2" {
  run $F no-existe
  [ "$status" -eq 2 ]
}
