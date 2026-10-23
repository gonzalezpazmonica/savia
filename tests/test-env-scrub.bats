#!/usr/bin/env bats
# tests/test-env-scrub.bats — SE-326 S5: env-scrub (AC-S5).
# Ref: docs/propuestas/SE-326-harness-loop-hygiene.md

SCRUB="scripts/env-scrub.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# ── AC-S5 ─────────────────────────────────────────────────────────────────

@test "S5.1: con SAVIA_SCRUB_ENV=1, run drena *TOKEN*/*SECRET* (AC-S5.1)" {
  export SAVIA_SCRUB_ENV=1
  run env MY_SECRET_TOKEN="leaked" bash "$SCRUB" run env
  [[ ! "$output" == *"MY_SECRET_TOKEN"* ]]
}

@test "S5.2: con SAVIA_SCRUB_ENV unset, no hace nada (AC-S5.2)" {
  unset SAVIA_SCRUB_ENV
  run bash "$SCRUB" check "echo hola"
  [[ $status -eq 0 ]]
}

@test "S5.3: check detecta comando que introduce secret por env (AC-S5.3 warning)" {
  export SAVIA_SCRUB_ENV=1
  run bash "$SCRUB" check 'export API_TOKEN=abc; curl https://x'
  [[ $status -eq 2 ]]
  [[ "$output" == *"WARN [env-scrub]"* ]]
}

@test "S5.4: allowlist PATH/HOME se conserva (AC-S5.1)" {
  export SAVIA_SCRUB_ENV=1
  run bash "$SCRUB" run env
  [[ "$output" == *"PATH="* ]]
  [[ "$output" == *"HOME="* ]]
}

@test "S5.5: --list-dropped lista vars que matchean el patrón (AC-S5.4 telemetría)" {
  export SAVIA_SCRUB_ENV=1
  export MY_GH_TOKEN="x"
  export MY_ORDINARY_VAR="y"
  run bash "$SCRUB" --list-dropped
  [[ "$output" == *"MY_GH_TOKEN"* ]]
  [[ ! "$output" == *"MY_ORDINARY_VAR"* ]]
}

# --- S03c: semántica real de allowlist y detección (SE-326 S5) ---

scrub() { env SAVIA_SCRUB_ENV=1 "$@"; }

@test "run: solo sobrevive la allowlist; una variable ordinaria ajena también se elimina" {
  run env SAVIA_SCRUB_ENV=1 MY_ORDINARY_VAR=hola OTRA=1 bash "$SCRUB" run env
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "MY_ORDINARY_VAR\|^OTRA="; then false; fi
  names=$(echo "$output" | cut -d= -f1 | sort | tr '\n' ' ')
  for k in HOME PATH SAVIA_SCRUB_ENV SHELL LANG TERM; do
    [[ " $names" == *" $k "* ]]
  done
}

@test "run: PYTHONPATH, GH_TOKEN, API_KEY, DB_PASSWORD, GH_PAT y CLIENT_SECRET no llegan al hijo" {
  run env SAVIA_SCRUB_ENV=1 PYTHONPATH=/x GH_TOKEN=a API_KEY=b DB_PASSWORD=c GH_PAT=d CLIENT_SECRET=e bash "$SCRUB" run env
  [ "$status" -eq 0 ]
  if echo "$output" | grep -qE "^(PYTHONPATH|GH_TOKEN|API_KEY|DB_PASSWORD|GH_PAT|CLIENT_SECRET)="; then false; fi
}

@test "run: conserva CLAUDE_PROJECT_DIR y SAVIA_WORKSPACE_DIR y fuerza SAVIA_SCRUB_ENV=1" {
  run env SAVIA_SCRUB_ENV=1 CLAUDE_PROJECT_DIR=/p SAVIA_WORKSPACE_DIR=/w bash "$SCRUB" run env
  echo "$output" | grep -q "^CLAUDE_PROJECT_DIR=/p$"
  echo "$output" | grep -q "^SAVIA_WORKSPACE_DIR=/w$"
  echo "$output" | grep -q "^SAVIA_SCRUB_ENV=1$"
}

@test "run: propaga el exit code del comando (fallo = 7)" {
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" run bash -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "run: argumentos con espacios llegan intactos al comando" {
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" run printf '[%s]' "uno dos" tres
  [ "$output" = "[uno dos][tres]" ]
}

@test "OFF por defecto: ni run ni subcomando desconocido hacen nada (exit 0, sin salida)" {
  run env -u SAVIA_SCRUB_ENV bash "$SCRUB" run echo visible
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run env SAVIA_SCRUB_ENV=0 bash "$SCRUB" bogus
  [ "$status" -eq 0 ]
}

@test "ON: subcomando desconocido o vacío → exit 2 con uso" {
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "uso: env-scrub.sh"
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB"
  [ "$status" -eq 2 ]
}

@test "check: TOKEN= a secas (sin prefijo) también se detecta" {
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" check 'TOKEN=abc curl x'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "TOKEN="
}

@test "check: cubre KEY, SECRET, PASSWORD y PAT como palabra" {
  for v in AWS_ACCESS_KEY CLIENT_SECRET DB_PASSWORD GH_PAT; do
    run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" check "$v=x cmd"
    [ "$status" -eq 2 ]
  done
}

@test "check: PAT pegado (GHPAT, AZDOPAT) sigue marcándose" {
  for v in GHPAT AZDOPAT; do
    run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" check "$v=x cmd"
    [ "$status" -eq 2 ]
  done
}

@test "check: PATH, PYTHONPATH y MYPATH no son credenciales (sin falsos positivos)" {
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" check 'PATH=$PATH:/x PYTHONPATH=. MYPATH=1 ls'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check: comando sin asignaciones → exit 0; vacío también (borde)" {
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" check 'ls -la /tmp'
  [ "$status" -eq 0 ]
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" check
  [ "$status" -eq 0 ]
}

@test "check: el aviso indica cómo pasar credenciales (Rule #1)" {
  run env SAVIA_SCRUB_ENV=1 bash "$SCRUB" check 'API_TOKEN=x run'
  echo "$output" | grep -q 'cat \$PAT_FILE'
}

@test "--list-dropped: no lista PATH ni otras variables de la allowlist" {
  run env SAVIA_SCRUB_ENV=1 GH_TOKEN=x PYTHONPATH=/y bash "$SCRUB" --list-dropped
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "GH_TOKEN"
  if echo "$output" | grep -qx "PATH"; then false; fi
}

@test "--list-dropped: PYTHONPATH no cuenta como credencial" {
  run env SAVIA_SCRUB_ENV=1 PYTHONPATH=/y bash "$SCRUB" --list-dropped
  if echo "$output" | grep -qx "PYTHONPATH"; then false; fi
}

@test "--list-dropped: sin variables sensibles la salida está vacía (vacío)" {
  run env -i PATH="$PATH" HOME="$HOME" SAVIA_SCRUB_ENV=1 bash "$SCRUB" --list-dropped
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "el script declara set -uo pipefail" {
  grep -q '^set -uo pipefail' "$SCRUB"
}
