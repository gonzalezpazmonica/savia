#!/usr/bin/env bats

# Ref: docs/specs/SE-400-model-agnostic-ablation-minimal-kernel.spec.md (F4)
# Ref: docs/specs/SE-400-f4-unit-ablation.md
setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  python3 scripts/ablation_units.py run --out "$BATS_FILE_TMPDIR/report" \
    --unit block-infra-destructive.sh --unit block-branch-switch-dirty.sh \
    >"$BATS_FILE_TMPDIR/run.log" 2>&1
  echo $? >"$BATS_FILE_TMPDIR/run.status"
}

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  R="$BATS_FILE_TMPDIR/report/f4-unit-receipts.json"
}

jqr() { python3 -c "import json,sys; r=json.load(open('$R')); print($1)"; }

@test "SE-400 F4 script, preregistro y corpus existen" {
  [ -x scripts/ablation_units.py ]
  [ -f config/ablation-preregistrations.json ]
  [ -f config/ablation-f4-corpus.json ]
}

@test "SE-400 F4 tests de fixtures pasan" {
  run python3 -m unittest tests/test_ablation_units.py
  [ "$status" -eq 0 ]
}

@test "SE-400 F4 check: el preregistro cubre exactamente el grupo PreToolUse/Bash de F2" {
  run python3 scripts/ablation_units.py check
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREREG_OK f4-pretooluse-bash@"*"units=13"* ]]
}

@test "SE-400 F4 run sobre el repo: control válido y cero invocaciones de modelo" {
  [ "$(cat "$BATS_FILE_TMPDIR/run.status")" -eq 0 ]
  [ "$(jqr "len(r['control']['invalid'])")" -eq 0 ]
  [ "$(jqr "r['model_invocations']")" -eq 0 ]
}

@test "SE-400 F4 block-infra-destructive atrapa en exclusiva terraform destroy (A0 y A2)" {
  run jqr "sorted({u['decision'] for u in r['units'] if u['unit_id']=='u-block-infra-destructive'})"
  [ "$output" = "['ABORT_FALSE_ALLOW']" ]
  run jqr "all('block-terraform-destroy' in u['unique_failures_caught'] for u in r['units'] if u['unit_id']=='u-block-infra-destructive')"
  [ "$output" = "True" ]
}

@test "SE-400 F4 block-branch-switch-dirty no atrapa nada en el corpus y no se declara redundante" {
  run jqr "sorted({u['decision'] for u in r['units'] if u['unit_id']=='u-block-branch-switch-dirty'})"
  [ "$output" = "['NO_UNIQUE_CATCH_ON_CORPUS']" ]
  run jqr "'NO_ESSENTIALITY_CLASSIFICATION_FROM_THIS_RECEIPT' in r['limitations']"
  [ "$output" = "True" ]
}

@test "SE-400 F4 sin exclusiones caducadas: f4-adb-root vuelve al corpus" {
  # La exclusión de 0.2.0 caducó cuando el hook pasó a leer stdin (#1398). Si reaparece una
  # exclusión y su control ya no es ALLOW, hay que retirarla del preregistro, no tolerarla.
  run jqr "[e['id'] for e in r['control']['excluded'] if e['stale']]"
  [ "$output" = "[]" ]
  run jqr "r['control']['excluded']"
  [ "$output" = "[]" ]
  # f4-adb-root ahora cuenta como caso del control (no excluido): 32 casos y ninguno inválido.
  [ "$(jqr "r['control']['cases']")" -ge 32 ]
}

@test "SE-400 F4 el repositorio no cambia tras correr la ablación" {
  run git -C "$PWD" status --porcelain -- .claude/settings.json .claude/hooks
  [ -z "$output" ]
}

@test "SE-400 F4 un filtro de unidad inexistente se rechaza" {
  run python3 scripts/ablation_units.py run --out "$BATS_TEST_TMPDIR" --unit no-existe.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNIT_FILTER_EMPTY"* ]]
}
