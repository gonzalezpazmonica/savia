#!/usr/bin/env bats
# Ref: SE-292 (contención de ejecución, S2/S3/S7) — docs/rules/domain/execution-containment.md
# Fail-closed of containment-run.sh and the status report of containment-check.sh.
# Docker is replaced by a fake binary on PATH: no real container is started.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/containment-run.sh"
  CHECK="$BATS_TEST_DIRNAME/../scripts/containment-check.sh"
}

teardown() {
  unset RUNLOG_PATH
}

@test "fail-closed: N-contenido without Docker exits 2" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-contenido "echo should-fail"
  [ "$status" -eq 2 ]
}

@test "fail-closed: N-hostil without Docker exits 2" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-hostil "echo should-fail"
  [ "$status" -eq 2 ]
}

@test "fail-closed: message explains what failed" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-contenido "echo test"
  [[ "$output" =~ "BLOCKED" || "$output" =~ "not installed" || "$output" =~ "not available" ]]
}

@test "containment-check reports status even without Docker" {
  _fake_docker
  FAKE_INFO=1 PATH="$FAKEBIN:$PATH" run bash "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Docker daemon:    UNAVAILABLE"* ]]
  [[ "$output" == *"Status: UNAVAILABLE"* ]]
}

@test "containment-check --json produces valid JSON" {
  _fake_docker
  FAKE_INFO=1 PATH="$FAKEBIN:$PATH" run bash "$CHECK" --json
  [ "$status" -eq 0 ]
  run python3 -c 'import sys,json; d=json.loads(sys.argv[1]); assert d["docker_available"] is False and d["base_image"] is False and d["containers_running"] == 0, d' "$output"
  [ "$status" -eq 0 ]
}

# ── Fake docker: deterministic daemon/image/run states (SE-292 S2/S3/S7) ──
# FAKE_INFO / FAKE_IMAGE: exit code of `docker info` / `docker image inspect`.
# FAKE_PS: number of running containers. Every `docker run` argv is logged.
_fake_docker() {
  FAKEBIN="$BATS_TEST_TMPDIR/fakebin"
  RUNLOG="$BATS_TEST_TMPDIR/docker-run.log"
  mkdir -p "$FAKEBIN"
  cat > "$FAKEBIN/docker" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  info) exit "${FAKE_INFO:-0}" ;;
  image)
    [ "${FAKE_IMAGE:-0}" -eq 0 ] || exit 1
    [[ "$*" == *--format* ]] && echo "2026-10-01T10:20:30.123456789Z"
    exit 0 ;;
  ps) for ((i=0; i<${FAKE_PS:-0}; i++)); do echo "c$i"; done; exit "${FAKE_PS_RC:-0}" ;;
  run) shift; printf '%s\n' "$@" > "$RUNLOG_PATH"; echo "container-ran"; exit "${FAKE_RUN_RC:-0}" ;;
esac
exit 99
FAKE
  chmod +x "$FAKEBIN/docker"
  export RUNLOG_PATH="$RUNLOG"
}

@test "run: N-anfitrion executes on the host and keeps the exit code" {
  run bash "$SCRIPT" N-anfitrion "echo host-side; (exit 7)"
  [ "$status" -eq 7 ]
  [ "$output" = "host-side" ]
}

@test "run: missing level or command is a usage error (exit 2)" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: containment-run.sh"* ]]
  run bash "$SCRIPT" N-contenido
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: containment-run.sh"* ]]
}

@test "run: unknown level is rejected without running the command" {
  marker="$BATS_TEST_TMPDIR/ran"
  run bash "$SCRIPT" n-contenido "touch $marker"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: Unknown level 'n-contenido'"* ]]
  [ ! -e "$marker" ]
}

@test "run: no silent fallback to the host when Docker is unusable" {
  _fake_docker
  marker="$BATS_TEST_TMPDIR/ran-on-host"
  FAKE_INFO=1 PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-contenido "touch $marker"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED [containment-fail-closed]: Docker daemon not responding"* ]]
  [[ "$output" == *"Level: N-contenido"* ]]
  [ ! -e "$marker" ]
  [ ! -e "$RUNLOG" ]
}

@test "run: Docker not installed blocks with its own reason" {
  # PATH without any docker binary: only the tools bash needs.
  mkdir -p "$BATS_TEST_TMPDIR/nodocker"
  for t in timeout env; do ln -s "$(command -v $t)" "$BATS_TEST_TMPDIR/nodocker/$t"; done
  PATH="$BATS_TEST_TMPDIR/nodocker" run "$(command -v bash)" "$SCRIPT" N-hostil "echo x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED [containment-fail-closed]: Docker not installed"* ]]
}

@test "run: missing image blocks N-hostil (fail-closed)" {
  _fake_docker
  FAKE_IMAGE=1 PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-hostil "echo x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED [containment-fail-closed]: Image not built"* ]]
  [ ! -e "$RUNLOG" ]
}

@test "run: N-contenido runs isolated (no network, no caps, limits) without read-only rootfs" {
  _fake_docker
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-contenido "echo inside"
  [ "$status" -eq 0 ]
  [ "$output" = "container-ran" ]
  for opt in --rm --network=none --cap-drop=ALL --security-opt=no-new-privileges \
             --cpus=1 --memory=512m --pids-limit=50 SAVIA_CONTAINER_MODE=1 savia-contained:latest; do
    grep -qxF -- "$opt" "$RUNLOG"
  done
  [ "$(tail -1 "$RUNLOG")" = "echo inside" ]
  [ "$(grep -cxF -- --read-only "$RUNLOG")" -eq 0 ]
}

@test "run: N-hostil adds read-only rootfs and a noexec tmpfs" {
  _fake_docker
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-hostil "echo inside"
  [ "$status" -eq 0 ]
  grep -qxF -- --read-only "$RUNLOG"
  grep -qxF -- /tmp:noexec,nosuid,size=100M "$RUNLOG"
  grep -qxF -- --network=none "$RUNLOG"
}

@test "run: host environment and volumes never reach the container (credential isolation)" {
  _fake_docker
  AWS_SECRET_ACCESS_KEY=s3cr3t PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-contenido "env"
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^(-v|--volume|--mount|--env-file|--privileged|--network=host)' "$RUNLOG")" -eq 0 ]
  [ "$(grep -cx -- -e "$RUNLOG")" -eq 1 ]
  [ "$(grep -c s3cr3t "$RUNLOG")" -eq 0 ]
}

@test "run: container failure propagates its exit code" {
  _fake_docker
  FAKE_RUN_RC=5 PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-contenido "false"
  [ "$status" -eq 5 ]
}

@test "run: empty command string is a usage error, nothing is started" {
  _fake_docker
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-contenido ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: containment-run.sh"* ]]
  [ ! -e "$RUNLOG" ]
}

@test "run: docker info hanging past the timeout counts as daemon not responding" {
  _fake_docker
  printf '#!/usr/bin/env bash\n[ "$1" = info ] && exec sleep 30\nexit 0\n' > "$FAKEBIN/docker"
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" N-hostil "echo x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Docker daemon not responding"* ]]
}

@test "check: zero running containers is reported as 0 with READY" {
  _fake_docker
  FAKE_PS=0 PATH="$FAKEBIN:$PATH" run bash "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Containers:       0 running"* ]]
}

@test "safety: containment-run and containment-check run with set -euo pipefail" {
  grep -qx 'set -euo pipefail' "$SCRIPT"
  grep -qx 'set -euo pipefail' "$CHECK"
}

@test "check: daemon and image present is READY with exit 0" {
  _fake_docker
  FAKE_PS=3 PATH="$FAKEBIN:$PATH" run bash "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker daemon:    AVAILABLE"* ]]
  [[ "$output" == *"Base image:       BUILT (2026-10-01T10:20:30)"* ]]
  [[ "$output" == *"Containers:       3 running"* ]]
  [[ "$output" == *"Status: READY"* ]]
}

@test "check: daemon without image is PARTIAL with exit 1" {
  _fake_docker
  FAKE_IMAGE=1 PATH="$FAKEBIN:$PATH" run bash "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Base image:       MISSING"* ]]
  [[ "$output" == *"Status: PARTIAL"* ]]
}

@test "check --json: ready state reports true/true, count and build date" {
  _fake_docker
  FAKE_PS=2 PATH="$FAKEBIN:$PATH" run bash "$CHECK" --json
  [ "$status" -eq 0 ]
  run python3 -c 'import sys,json; d=json.loads(sys.argv[1]); assert d=={"docker_available":True,"base_image":True,"containers_running":2,"last_build":"2026-10-01T10:20:30"}, d' "$output"
  [ "$status" -eq 0 ]
}

@test "check: a failing 'docker ps' still yields a report, not a silent abort" {
  _fake_docker
  FAKE_PS=0 FAKE_PS_RC=1 PATH="$FAKEBIN:$PATH" run bash "$CHECK" --json
  [ "$status" -eq 0 ]
  run python3 -c 'import sys,json; d=json.loads(sys.argv[1]); assert d["containers_running"]==0 and d["docker_available"] is True, d' "$output"
  [ "$status" -eq 0 ]
}

@test "session container start without Docker fails gracefully" {
  SESSION="$BATS_TEST_DIRNAME/../containment/session-container.sh"
  # Deterministic "Docker unusable": a docker stub that always fails, first on PATH.
  mkdir -p "$BATS_TEST_TMPDIR/nodocker"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/nodocker/docker"
  chmod +x "$BATS_TEST_TMPDIR/nodocker/docker"
  PATH="$BATS_TEST_TMPDIR/nodocker:$PATH" run bash "$SESSION" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"Starting session container"* ]]
}

@test "adversarial suite reports test count" {
  run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh"
  [[ "$output" =~ Results:\ [0-9]+\ PASS\ \|\ [0-9]+\ FAIL ]]
  # exit status must agree with the reported failure count
  fails="${BASH_REMATCH[0]##*| }"; fails="${fails% FAIL}"
  if [ "$fails" -eq 0 ]; then [ "$status" -eq 0 ]; else [ "$status" -eq 1 ]; fi
}

@test "adversarial suite --ci produces TAP output" {
  run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh" --ci
  [[ "$output" == *"TAP version 13"* ]]
  [[ "$output" == *"1..6"* ]]
  [ "$(grep -cE '^(not )?ok - ' <<< "$output")" -eq 6 ]
}
