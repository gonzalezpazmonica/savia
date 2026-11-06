#!/usr/bin/env bats

setup() {
  ADVS="$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh"
}

@test "adversarial: script is executable" {
  [ -x "$ADVS" ]
}

@test "adversarial: script has set -uo pipefail" {
  head -2 "$ADVS" | grep -q "set -euo pipefail"
}

@test "adversarial: 6 tests present" {
  # Cuenta las 6 líneas TAP emitidas, no las apariciones de run_test en el código.
  run bash "$ADVS" --ci
  [ "$(grep -cE '^(not )?ok - ' <<< "$output")" -eq 6 ]
}

@test "adversarial: credential leak test exists" {
  grep -q "credential_leak" "$ADVS"
}

@test "adversarial: write outside work dir test exists" {
  grep -q "write_outside" "$ADVS"
}

@test "adversarial: cross-encargo test exists" {
  grep -q "cross_encargo" "$ADVS"
}

@test "adversarial: privilege escalation test exists" {
  grep -q "privilege_escalation" "$ADVS"
}

@test "adversarial: host fallback test exists" {
  grep -q "host_fallback" "$ADVS"
}

@test "adversarial: autonomy evidence test exists" {
  grep -q "autonomy_without_evidence" "$ADVS"
}

@test "adversarial: exits non-zero on failure mode" {
  run bash "$ADVS"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ── S03q (SE-376): comportamiento con un docker simulado ────────────────────
# Ref: projects/savia-vaults/specs/SE-292-contencion-ejecucion.spec.md (S7)
# El stub responde a info / image inspect / run según variables y registra
# cada llamada en $DOCKER_LOG. Así se prueba la suite sin motor real.

mkstub() {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"; : > "$DOCKER_LOG"
  cat > "$STUB/docker" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
case "$1" in
  info) exit "${STUB_INFO_RC:-0}" ;;
  image) [[ "$3" == "savia-contained:latest" ]] && exit "${STUB_IMAGE_RC:-0}"; exit 1 ;;
  run) exit "${STUB_RUN_RC:-1}" ;;
esac
exit 0
SH
  chmod +x "$STUB/docker"
  export DOCKER_LOG
}

suite() { PATH="$STUB:$PATH" run bash "$ADVS" --ci; }

@test "contenedor que filtra: los 4 ataques salen not ok (sin falso verde)" {
  mkstub; STUB_RUN_RC=0 suite
  [ "$status" -eq 1 ]
  for t in credential_leak write_outside cross_encargo privilege_escalation; do
    [[ "$output" == *"not ok - $t"* ]]
  done
}

@test "contenedor estanco: los 4 ataques fallan y salen ok" {
  mkstub; STUB_RUN_RC=1 suite
  for t in credential_leak write_outside cross_encargo privilege_escalation; do
    grep -qE "^ok - $t " <<< "$output"
  done
  [[ "$output" == *"Results: 5 PASS | 1 FAIL"* ]]
}

@test "los ataques pasan por containment-run (cap-drop, sin red, imagen)" {
  mkstub; STUB_RUN_RC=1 suite
  [ "$(grep -c '^run ' "$DOCKER_LOG")" -eq 4 ]
  run grep -c -- '--cap-drop=ALL --security-opt=no-new-privileges --network=none' "$DOCKER_LOG"
  [ "$output" -eq 4 ]
  grep -qE 'bash -c cat .*\.savia/confidentiality-key' "$DOCKER_LOG"
  grep -q 'sudo -n whoami' "$DOCKER_LOG"
}

@test "imagen missing: ataques no ejecutados y fail-closed con motivo" {
  mkstub; STUB_IMAGE_RC=1 STUB_RUN_RC=1 suite
  [ "$status" -eq 1 ]
  [ "$(grep -c 'not ok - .* # contención no disponible: imagen savia-contained:latest no construida' <<< "$output")" -eq 4 ]
  [ "$(grep -c '^run ' "$DOCKER_LOG")" -eq 0 ]
}

@test "daemon sin respuesta: error de precondición, sin docker run" {
  mkstub; STUB_INFO_RC=1 STUB_RUN_RC=1 suite
  [ "$(grep -c '# contención no disponible: daemon de docker sin respuesta' <<< "$output")" -eq 4 ]
  [ "$(grep -c '^run ' "$DOCKER_LOG")" -eq 0 ]
}

@test "host_fallback: imagen ausente bloquea N-contenido y sale ok" {
  mkstub; STUB_RUN_RC=0 suite
  grep -qE '^ok - host_fallback ' <<< "$output"
  [ "$(grep -c 'savia-adversarial-missing:probe' "$DOCKER_LOG")" -ge 1 ]
}

@test "autonomy_without_evidence nunca certifica sin gate (fail-closed)" {
  mkstub; STUB_RUN_RC=1 suite
  [ "$status" -eq 1 ]
  [[ "$output" == *"not ok - autonomy_without_evidence # gate de ampliación de autonomía no implementado"* ]]
}
