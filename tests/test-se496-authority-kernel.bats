#!/usr/bin/env bats

# Ref: docs/specs/SE-496-governed-operational-ontology-authority.spec.md (F0: AC-1..AC-9, AC-5b, AC-5c, AC-6b, AC-12, AC-13)
# Cada caso de R5 corre con su gemelo positivo (difiere en un solo dato). Mundo hermético por caso:
# repo git propio con origin/main, dos operadores ficticios, `gh` falso y HOME temporal (AC-9).
# Cobertura de pasos: D01 p1, D07 p2, D06 p3, D08 p4, D02/D03 p5, D05 p6, D09 p7, D14 p8, D15 p9,
# D10 p10, T-uses p11, D13 p12, D12 p13, D11 p14, T-level p15, T-tier p16, T-action p17, T-state p18.

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  X="python3 tests/fixtures/se496/extras.py"
  TMP=$(mktemp -d -p "$BATS_TEST_TMPDIR")  # bats borra BATS_TEST_TMPDIR al terminar cada test
}

teardown() {
  unset TMP
}

@test "AC-1/AC-2: ontología válida; inferred en precondición, estado sin dueño y acción sin efectos fallan; contratos inválidos con su código" {
  run $X extra validators
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "AC-1: la ontología real declara los 8 tipos y las 4 acciones y check-ontology da PASS" {
  run python3 -I scripts/lib/authority_kernel.py check-ontology
  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]]
  for t in Principal Delegate Repo Branch PullRequest Project VaultNote ExternalSystem; do
    grep -q "^  $t:" contracts/ontology/savia-operational.yaml
  done
  for a in pr.create-draft pr.merge project.publish vault.note-write; do
    grep -q "^  $a:" contracts/ontology/savia-operational.yaml
  done
}

@test "AC-3 D01: missing contract is rejected -> NO_CONTRACT" { run $X check D01; [ "$output" = "OK" ]; }
@test "AC-3 D02: revocado en origin/main -> REVOKED" { run $X check D02; [ "$output" = "OK" ]; }
@test "AC-3 D03: revocado solo en local -> REVOKED" { run $X check D03; [ "$output" = "OK" ]; }
@test "AC-3 D04/AC-7: revocado entre evaluar y ejecutar -> REVOKED en recheck" { run $X check D04; [ "$output" = "OK" ]; }
@test "AC-3 D05: expired, boundary now==expires_at and before not_before are rejected" { run $X check D05 D05b D05c; [ "$output" = "OK" ]; }
@test "AC-3 D06: firma alterada, firmante solo en la rama y namespace ajeno -> BAD_SIGNATURE" { run $X check D06 D06b D06c; [ "$output" = "OK" ]; }
@test "AC-3 D07: unsigned, invalid principal, principal self y principal agente -> SELF_ISSUED (precedencia sobre BAD_SIGNATURE)" { run $X check D07 D07b D07c; [ "$output" = "OK" ]; }
@test "AC-3 D08: otro operador y perfil editado -> PRINCIPAL_MISMATCH" { run $X check D08 D08b; [ "$output" = "OK" ]; }
@test "AC-3 D09: versión distinta y descriptor cambiado tras firmar -> CAPABILITY_MISMATCH" { run $X check D09 D09b; [ "$output" = "OK" ]; }
@test "AC-3/AC-13 D10: bad prefix, agent/x/y, .., nonexistent scope, other repo -> OUT_OF_SCOPE" { run $X check D10 D10b D10c D10d D10e; [ "$output" = "OK" ]; }
@test "AC-3 D11: efecto no declarado en el contrato o aportado por la orden -> UNDECLARED_EFFECT" { run $X check D11 D11b; [ "$output" = "OK" ]; }
@test "AC-3 D12: CI roja, pendiente, cancelada, rama humana y PR cerrado -> PRECONDITION_FAILED:<id>" { run $X check D12 D12b D12c D12d D12e; [ "$output" = "OK" ]; }
@test "AC-3/AC-6 D13: fail-closed when gh, origin/main, ssh-keygen or git are missing -> UNKNOWN_STATE (exit 1, never 0)" { run $X check D13 D13b D13c D13d; [ "$output" = "OK" ]; }
@test "AC-3/AC-13 D14: NFD, homoglifo, ramas por mayúsculas, alias y 2 candidatos -> AMBIGUOUS" { run $X check D14 D14b D14c D14d D14e; [ "$output" = "OK" ]; }
@test "AC-3 precedencia: homoglifo de un proyecto del ámbito -> AMBIGUOUS, no OUT_OF_SCOPE" { run $X check P2; [ "$output" = "OK" ]; }
@test "AC-3/AC-8 D15: autoridad inferida -> INFERRED_NOT_AUTHORITY con sugerencia; con contrato firmado ALLOW y la misma sugerencia" {
  run $X check D15
  [ "$output" = "OK" ]
  run python3 tests/fixtures/se496/battery.py run D15 neg
  [[ "$output" == "RC=1 REASON=INFERRED_NOT_AUTHORITY SUGG=1" ]]
  run python3 tests/fixtures/se496/battery.py run D15 twin
  [[ "$output" == "RC=0 REASON=OK SUGG=1" ]]
}
@test "AC-3 técnico: contrato por encima del nivel del agente -> LEVEL_EXCEEDED" { run $X check T-level; [ "$output" = "OK" ]; }
@test "AC-3 técnico: orden distinta de la evaluada -> ACTION_MISMATCH" { run $X check T-action; [ "$output" = "OK" ]; }
@test "AC-3 técnico: head_sha nuevo sin romper precondición -> STATE_CHANGED" { run $X check T-state; [ "$output" = "OK" ]; }
@test "AC-3 técnico: tier 3/4 sin revisión humana -> REQUIRES_APPROVAL REVIEW_REQUIRED (exit 4), con revisión ALLOW" { run $X check T-tier; [ "$output" = "OK" ]; }
@test "AC-3/AC-6b técnico: bad input (malformed, null field) -> exit 2 without decision" { run $X check T-malformed T-malformed-field; [ "$output" = "OK" ]; }
@test "AC-3 técnico: zero uses left (max_uses spent) -> evaluate is rejected with MAX_USES_EXHAUSTED" { run $X check T-uses; [ "$output" = "OK" ]; }

@test "AC-5 (D04, arnés F0, fail-closed): revocar entre evaluate y recheck deja el marcador sin crear; sin revocar se crea; kernel ausente no ejecuta" {
  run $X extra harness
  [ "$output" = "OK" ]
}

@test "AC-5b: evaluate no consume; recheck consume; segundo recheck MAX_USES_EXHAUSTED; carrera de dos recheck = un solo ALLOW (x5)" {
  run $X extra ledger
  [ "$output" = "OK" ]
}

@test "AC-5c: el digest ignora lo no referenciado, cambia con lo referenciado; con max_uses 2 dos órdenes dan dos ALLOW" {
  run $X extra digest
  [ "$output" = "OK" ]
}

@test "AC-6b: cada fila de la tabla de códigos de salida (0, 1, 2) y fallo interno -> exit 2" {
  run $X extra exit
  [ "$output" = "OK" ]
}

@test "AC-7: sin caché, ALLOW y luego DENY con una revocación en medio" {
  run $X extra nocache
  [ "$output" = "OK" ]
}

@test "AC-9: empty signers file blocks every delegation (DENY)" {
  run $X extra signers-empty
  [ "$output" = "OK" ]
}

@test "AC-9: ningún caso lee ni escribe el HOME real" {
  export HOME="$TMP/home-real"
  mkdir -p "$HOME"
  run python3 tests/fixtures/se496/battery.py run D01 twin
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$HOME")" ]
}

@test "AC-12: el audit registra permitidos y denegados, hashea lo no declarado en audit_plain y verify-audit detecta edición, borrado y reordenación" {
  run $X extra audit
  [ "$output" = "OK" ]
}

@test "kernel sin modo de pruebas ignora los overrides de entorno (un agente no lo redirige)" {
  run $X extra noenv
  [ "$output" = "OK" ]
}
