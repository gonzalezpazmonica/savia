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

@test "ronda 3 P1-1: evaluate deniega vida > 7 días (7 d exactos vale) e irreversible o sin reversibility declarada sin max_uses 1; controles ALLOW" {
  run $F contract-invariants
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 3 P2: params con tipo distinto del declarado -> OUT_OF_SCOPE; solo savia-worker:<id> hereda nivel, yema:x o codex:x -> UNKNOWN_STATE" {
  run $F params-types-level
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 4 codex P1-2: PR de otra rama con target.branch dentro del ámbito -> OUT_OF_SCOPE; sin headRefName -> UNKNOWN_STATE; controles ALLOW" {
  run $F pr-branch
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 4 codex P1-1: con PR en el objetivo, avanzar la rama local entre evaluate y recheck -> STATE_CHANGED; quieta -> ALLOW" {
  run $F pr-branch-sha
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 4 codex P2: hecho ausente no cumple '!=' (UNKNOWN_STATE) e isDraft 0 no es false; controles" {
  run $F absent-typed-facts
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 4 seg. P1-1: fuera de test_mode el home sale de la base de usuarios, no de \$HOME (también el HOME de git/gh)" {
  run $F home-real
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 4 seg. P2-4: un contrato firmado que revienta la evaluación sale con exit 2 y deja línea ERROR en el audit" {
  run $F error-audited
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 5 codex P1-1: PR sin headRefOid, vacío, no hexadecimal o no textual -> UNKNOWN_STATE; con sha -> ALLOW" {
  run $F pr-head-sha
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 5 codex P1-2: en pr.merge, Branch.head_sha es la cabeza real del PR; un pin al commit local con otra cabeza -> PRECONDITION_FAILED" {
  run $F pr-branch-facts
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 5 codex P2-3: un JSON sin firma con authority.level no textual no tumba otro contrato válido; check-contract da FAIL" {
  run $F broken-catalog
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "ronda 5 codex P2-4: ninguna batería ejecuta el kernel sin overrides fuera de la sonda hermética (home y raíz temporales)" {
  # el kernel real o el envoltorio sin SAVIA_AUTHORITY_TEST resuelven el HOME real: solo vía run_without_overrides
  run grep -nE '"-I", REAL_KERNEL|(del |pop\()env\[?\(?"SAVIA_AUTHORITY_TEST"' tests/fixtures/se496/review_fixes.py tests/fixtures/se496/ledger_digest_audit.py tests/fixtures/se496/denegaciones.py
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run grep -c 'run_without_overrides(' tests/fixtures/se496/review_fixes.py tests/fixtures/se496/ledger_digest_audit.py
  [[ "$output" == *"review_fixes.py:1"* ]]
  [[ "$output" == *"ledger_digest_audit.py:1"* ]]
}
