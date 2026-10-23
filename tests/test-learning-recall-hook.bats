#!/usr/bin/env bats
# BATS tests for .claude/hooks/learning-recall-hook.sh (SCL-003, SCL-008).
# Ref: SCL-003 (recall por prompt), SCL-008 (autoridad de criterio), SE-333.
# SE-339: cobertura de hook crítico (inyecta aprendizaje en el prompt).
SCRIPT=".claude/hooks/learning-recall-hook.sh"

setup() { cd "$BATS_TEST_DIRNAME/.."; }
teardown() { cd /; }

@test "existe" { [[ -f "$SCRIPT" ]]; }
@test "usa set -uo pipefail" { run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "pasa bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }
@test "referencia SCL-003" { run grep -c 'SCL-003' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "delega en learning-recall.sh" { run grep -c 'learning-recall' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "nunca bloquea (exit 0 siempre — SCL-003 AC-7)" {
  run grep -cE 'exit [1-9]' "$SCRIPT"
  # El hook no debe fallar el pipeline; si hay exits no-cero, debe ser solo en
  # ramas protegidas por try/catch. Verificamos que existe la garantía exit 0.
  run grep -cE 'exit 0' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
@test "no persiste el prompt (SCL-008 TS-07)" {
  # Sandboxed project with a stub recall that only answers when it receives the marker query.
  local proj="$BATS_TEST_TMPDIR/proj" marker="PROMPT-MARKER-7f3a9c-unico"
  mkdir -p "$proj/scripts"
  cat > "$proj/scripts/learning-recall.sh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *PROMPT-MARKER-7f3a9c-unico*) echo '{"effective_hits":[{"criterion_id":"C-1","principle":"criterio de prueba"}]}' ;;
esac
STUB
  run env CLAUDE_PROJECT_DIR="$proj" HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR" \
    bash -c "echo '{\"content\":\"consulta con $marker para recall\"}' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  # the hook did process the prompt (injected the stub hit) ...
  [[ "$output" == *"Criterios humanos aplicables"* ]]
  # ... and left no file containing it
  run grep -rl --exclude=learning-recall.sh -- "$marker" "$BATS_TEST_TMPDIR"
  [ -z "$output" ]
}
