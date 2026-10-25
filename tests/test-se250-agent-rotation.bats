#!/usr/bin/env bats
# test-se250-agent-rotation.bats — SE-250: token exhaustion detector tests
#
# Acceptance criteria from SE-250:
# 1. --log /dev/null exits 1 (log not found)
# 2. Log with "context_length_exceeded" -> exit 0, CAUSE=token_exhaustion
# 3. Logic error log -> exit 0, CAUSE=logic_error
# 4. No escalation above mid without ALLOW_HEAVY_ESCALATION=true
# 5. BATS suite >= 10 tests, quality >= 80
# 6. Script is pure bash, no LLM calls

SCRIPT="scripts/detect-token-exhaustion.sh"
TMP="${BATS_TEST_TMPDIR:-/tmp}/se250-test-$$"

setup() {
  cd "${BATS_TEST_DIRNAME}/.."
  mkdir -p "$TMP"
}

teardown() {
  rm -rf "$TMP"
}

# ── Structure tests ──────────────────────────────────────────────────────────

@test "SE-250-T01: detect-token-exhaustion.sh exists and is executable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

@test "SE-250-T02: script declares set -uo pipefail" {
  grep -q "set -uo pipefail" "$SCRIPT"
}

@test "SE-250-T03: script references SE-250" {
  grep -q "SE-250" "$SCRIPT"
}

@test "SE-250-T04: --help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--log"* ]]
}

@test "SE-250-T05: no LLM calls in script (no curl/ollama/anthropic)" {
  # Script must be deterministic bash only
  grep -qvE "(curl|wget|ollama|anthropic|openai)" "$SCRIPT"
}

# ── Input validation ─────────────────────────────────────────────────────────

@test "SE-250-T06: --log with nonexistent file exits 1" {
  run bash "$SCRIPT" --log /nonexistent/path.log
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAUSE=unknown"* ]]
}

@test "SE-250-T07: missing --log flag exits 1 with usage" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# ── Token exhaustion detection ────────────────────────────────────────────────

@test "SE-250-T08: log with context_length_exceeded -> CAUSE=token_exhaustion" {
  echo "Error: context_length_exceeded in API call" > "$TMP/token.log"
  run bash "$SCRIPT" --log "$TMP/token.log"
  [ "$status" -eq 0 ]
  [[ "$output" == "CAUSE=token_exhaustion" ]]
}

@test "SE-250-T09: log with max_tokens exceeded -> CAUSE=token_exhaustion" {
  echo "Request failed: max_tokens exceeded (16384 > 12000)" > "$TMP/token2.log"
  run bash "$SCRIPT" --log "$TMP/token2.log"
  [ "$status" -eq 0 ]
  [[ "$output" == "CAUSE=token_exhaustion" ]]
}

@test "SE-250-T10: log with prompt too long -> CAUSE=token_exhaustion" {
  echo "The prompt is too long. Reduce the size of your input." > "$TMP/token3.log"
  run bash "$SCRIPT" --log "$TMP/token3.log"
  [ "$status" -eq 0 ]
  [[ "$output" == "CAUSE=token_exhaustion" ]]
}

# ── Logic error detection ────────────────────────────────────────────────────

@test "SE-250-T11: log with bash syntax error -> CAUSE=logic_error" {
  echo "bash: syntax error near unexpected token" > "$TMP/logic.log"
  run bash "$SCRIPT" --log "$TMP/logic.log"
  [ "$status" -eq 0 ]
  [[ "$output" == "CAUSE=logic_error" ]]
}

@test "SE-250-T12: log with SyntaxError -> CAUSE=logic_error" {
  echo "SyntaxError: invalid syntax in line 42" > "$TMP/logic2.log"
  run bash "$SCRIPT" --log "$TMP/logic2.log"
  [ "$status" -eq 0 ]
  [[ "$output" == "CAUSE=logic_error" ]]
}

@test "SE-250-T13: unknown log content -> CAUSE=unknown, exit 2" {
  echo "Something unexpected happened in the pipeline" > "$TMP/unknown.log"
  run bash "$SCRIPT" --log "$TMP/unknown.log"
  [ "$status" -eq 2 ]
  [[ "$output" == "CAUSE=unknown" ]]
}

@test "SE-250-T14: verbose flag produces extra output about signal matched" {
  echo "Error: context_length_exceeded" > "$TMP/verbose.log"
  run bash "$SCRIPT" --log "$TMP/verbose.log" --verbose
  [ "$status" -eq 0 ]
  # output contains CAUSE line
  [[ "$output" == *"CAUSE=token_exhaustion"* ]]
  # verbose produces SIGNAL: matched line
  [[ "$output" == *"SIGNAL:"* ]]
}

# ── Comportamiento: cada patrón, precedencia, mensajes y salidas ─────────────

detect() { printf '%s\n' "$1" > "$TMP/l.log"; run bash "$SCRIPT" --log "$TMP/l.log"; }

@test "cada señal de agotamiento de tokens se clasifica como token_exhaustion (exit 0)" {
  local s
  while IFS= read -r s; do
    detect "$s"
    [ "$status" -eq 0 ] || { echo "status=$status para: $s"; return 1; }
    [ "$output" = "CAUSE=token_exhaustion" ] || { echo "salida=$output para: $s"; return 1; }
  done <<'EOF'
error: context_length_exceeded
max_tokens limit was exceeded here
the prompt is far too long
input is too long for the model
input length 300000 exceeds the model limit
prompt exceeds the maximum allowed
reached the tokens per minute limit
context window is full
OutputBlockedError raised
ContextWindowExceeded: x
Maximum context length is 200000
Too many tokens in request
the prompt is way too long today
EOF
}

@test "cada señal de fallo lógico se clasifica como logic_error (exit 0)" {
  local s
  while IFS= read -r s; do
    detect "$s"
    [ "$status" -eq 0 ] || { echo "status=$status para: $s"; return 1; }
    [ "$output" = "CAUSE=logic_error" ] || { echo "salida=$output para: $s"; return 1; }
  done <<'EOF'
SyntaxError: invalid syntax
NameError: name x is not defined
TypeError: bad operand
ImportError: no module
ModuleNotFoundError: yaml
FileNotFoundError: x
PermissionError: denied
ConnectionError: reset
TimeoutError: slow
subprocess call failed
foo: command not found
process finished with exit code 3
assertion x failed
test_login failed
BATS run: not ok 3
Error: something at line 42
bash: -c: syntax error near token
unexpected end token found
EOF
}

@test "las señales no distinguen mayúsculas de minúsculas" {
  detect "CONTEXT_LENGTH_EXCEEDED"
  [ "$output" = "CAUSE=token_exhaustion" ]
  detect "syntaxerror: x"
  [ "$output" = "CAUSE=logic_error" ]
}

@test "si el log tiene ambas señales gana token_exhaustion" {
  printf 'SyntaxError: algo\ncontext_length_exceeded\nNameError: x\n' > "$TMP/l.log"
  run bash "$SCRIPT" --log "$TMP/l.log"
  [ "$status" -eq 0 ]
  [ "$output" = "CAUSE=token_exhaustion" ]
}

@test "exit code 0 no es fallo lógico (solo 1-9)" {
  detect "all done, exit code 0"
  [ "$status" -eq 2 ]
  [ "$output" = "CAUSE=unknown" ]
  detect "exit code 9"
  [ "$output" = "CAUSE=logic_error" ]
}

@test "log desconocido: solo CAUSE=unknown por stdout y exit 2" {
  detect "todo normal sin errores"
  [ "$status" -eq 2 ]
  [ "$output" = "CAUSE=unknown" ]
}

@test "log inexistente: error por stderr, CAUSE=unknown por stdout y exit 1" {
  run bash -c "bash '$SCRIPT' --log '$TMP/nada.log' 2>'$TMP/err'"
  [ "$status" -eq 1 ]
  [ "$output" = "CAUSE=unknown" ]
  grep -q "ERROR: log not found: $TMP/nada.log" "$TMP/err"
}

@test "log vacío: exit 1 con mensaje de vacío" {
  : > "$TMP/vacio.log"
  run bash -c "bash '$SCRIPT' --log '$TMP/vacio.log' 2>'$TMP/err'"
  [ "$status" -eq 1 ]
  [ "$output" = "CAUSE=unknown" ]
  grep -q "ERROR: log is empty" "$TMP/err"
}

@test "--verbose escribe SIGNAL por stderr con el patrón y no ensucia stdout" {
  printf 'ContextWindowExceeded\n' > "$TMP/l.log"
  run bash -c "bash '$SCRIPT' --log '$TMP/l.log' --verbose 2>'$TMP/err'"
  [ "$output" = "CAUSE=token_exhaustion" ]
  grep -q "SIGNAL: matched 'ContextWindowExceeded'" "$TMP/err"
}

@test "sin --verbose no hay SIGNAL" {
  printf 'ContextWindowExceeded\n' > "$TMP/l.log"
  run bash -c "bash '$SCRIPT' --log '$TMP/l.log' 2>&1"
  [[ "$output" != *SIGNAL* ]]
}

@test "--help imprime el uso por stdout y sale 0 también tras otras opciones" {
  run bash "$SCRIPT" --verbose -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: detect-token-exhaustion.sh --log <path> [--verbose]"* ]]
  [[ "$output" == *"CAUSE=token_exhaustion|logic_error|unknown"* ]]
}

@test "argumento desconocido: exit 1 con el argumento y el uso por stderr" {
  run bash "$SCRIPT" --nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown arg: --nope"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "sin --log: exit 1 con ERROR: --log is required y uso" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: --log is required"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "regresión: --log sin valor termina con error en vez de girar para siempre" {
  run timeout 5 bash "$SCRIPT" --log
  [ "$status" -eq 1 ]
  [[ "$output" == *"--log requires a value"* ]]
}
