#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# PATH sin docker: enlaces a todo el PATH del host salvo docker, de modo que los
# casos "sin Docker" sean deterministas también en máquinas y runners con Docker.
setup_file() {
  NODOCKER_BIN="$BATS_FILE_TMPDIR/nodocker-bin"
  mkdir -p "$NODOCKER_BIN"
  local d f
  IFS=: read -ra _dirs <<< "$PATH"
  for d in "${_dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      if [ -x "$f" ] && [ "${f##*/}" != "docker" ]; then
        ln -sf "$f" "$NODOCKER_BIN/${f##*/}" 2>/dev/null || true
      fi
    done
  done
  export NODOCKER_BIN
}

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/containment-run.sh"
  CHECK="$BATS_TEST_DIRNAME/../scripts/containment-check.sh"
}

@test "fail-closed: N-contenido without Docker exits 2" {
  PATH="$NODOCKER_BIN" run bash "$SCRIPT" N-contenido "echo should-fail"
  [ "$status" -eq 2 ]
}

@test "fail-closed: N-hostil without Docker exits 2" {
  PATH="$NODOCKER_BIN" run bash "$SCRIPT" N-hostil "echo should-fail"
  [ "$status" -eq 2 ]
}

@test "fail-closed: message explains what failed" {
  PATH="$NODOCKER_BIN" run bash "$SCRIPT" N-contenido "echo test"
  [[ "$output" =~ "BLOCKED" || "$output" =~ "not installed" || "$output" =~ "not available" ]]
}

@test "containment-check reports status even without Docker" {
  PATH="$NODOCKER_BIN" run bash "$CHECK"
  [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
}

@test "containment-check --json produces valid JSON" {
  PATH="$NODOCKER_BIN" run bash "$CHECK" --json
  [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['docker_available'] is False"
}

@test "session container start without Docker fails gracefully" {
  SESSION="$BATS_TEST_DIRNAME/../containment/session-container.sh"
  PATH="$NODOCKER_BIN" run -127 bash "$SESSION" start
  [[ "$output" == *"docker"* ]]
}

@test "adversarial suite reports test count" {
  PATH="$NODOCKER_BIN" run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh"
  [[ "$output" =~ "Results: "[0-9]+" PASS | "[0-9]+" FAIL" ]]
}

@test "adversarial suite --ci produces TAP output" {
  PATH="$NODOCKER_BIN" run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh" --ci
  [[ "$output" =~ "TAP version 13" ]]
  [[ "$output" =~ "1..6" ]]
}
