#!/usr/bin/env bats
# BATS tests for .opencode/hooks/post-edit-lint.sh
# PostToolUse async — auto-lint tras edición según extensión del fichero.
# Invoca linter disponible (dotnet/ruff/eslint/gofmt/rustfmt/rubocop/php-cs-fixer/terraform).
# Ref: batch 47 hook coverage — SPEC-lint multi-lang auto-check

HOOK=".opencode/hooks/post-edit-lint.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  TEST_DIR=$(mktemp -d "$TMPDIR/pel-XXXXXX")
  # Linters falsos delante en el PATH: el resultado no depende de lo que traiga la
  # máquina (en el runner `dotnet format` sin proyecto no terminaba) y cada test de
  # extensión comprueba que el hook llama al linter correcto con el fichero.
  STUBS="$TEST_DIR/stubs"
  CALLS="$TEST_DIR/calls.log"
  mkdir -p "$STUBS"
  for tool in dotnet ruff gofmt rustfmt rubocop php-cs-fixer terraform; do
    printf '#!/bin/bash\necho "%s $*" >> "%s"\nexit 0\n' "$tool" "$CALLS" > "$STUBS/$tool"
    chmod +x "$STUBS/$tool"
  done
  export PATH="$STUBS:$PATH"
}

# Aserción: el linter `$1` se invocó con el fichero `$2`; si `$2` va vacío, no se invocó ninguno.
# Línea completa: nombre del linter y ruta en la misma invocación.
assert_linter_called() {
  [[ -f "$CALLS" ]] && grep -E "^$1 .*" "$CALLS" | grep -qF "$2"
}
assert_no_linter() { [[ ! -s "$CALLS" ]]; }
teardown() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
  cd /
}

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }

# ── Pass-through ────────────────────────────────────────

@test "pass-through: empty file_path exits 0" {
  run bash "$HOOK" <<< '{"tool_input":{}}'
  [ "$status" -eq 0 ]
}

@test "pass-through: no tool_input exits 0" {
  run bash "$HOOK" <<< '{}'
  [ "$status" -eq 0 ]
}

@test "pass-through: empty JSON exits 0" {
  run bash "$HOOK" <<< ''
  # jq returns empty for empty input, FILE_PATH empty → exit 0
  [ "$status" -eq 0 ]
}

@test "pass-through: unknown extension exits 0" {
  echo "data" > "$TEST_DIR/file.xyz"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/file.xyz\"}}"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
  assert_no_linter
}

@test "pass-through: no extension exits 0" {
  echo "data" > "$TEST_DIR/Makefile"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/Makefile\"}}"
  [ "$status" -eq 0 ]
}

@test "pass-through: binary-looking extensions exit 0" {
  run bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/file.png"}}'
  [ "$status" -eq 0 ]
}

# ── Known extensions ────────────────────────────────────

@test "ext: .cs file triggers dotnet format" {
  echo 'class X {}' > "$TEST_DIR/code.cs"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/code.cs\"}}"
  [ "$status" -eq 0 ]
  assert_linter_called dotnet "$TEST_DIR/code.cs"
}

@test "ext: .py file triggers ruff check" {
  echo 'def foo(): pass' > "$TEST_DIR/script.py"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/script.py\"}}"
  [ "$status" -eq 0 ]
  assert_linter_called ruff "$TEST_DIR/script.py"
}

@test "ext: .ts extension matches TS case" {
  echo 'const x: number = 1' > "$TEST_DIR/file.ts"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/file.ts\"}}"
  [ "$status" -eq 0 ]
}

@test "ext: .tsx extension matches TS case" {
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/comp.tsx\"}}"
  [ "$status" -eq 0 ]
}

@test "ext: .js extension matches JS case" {
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/script.js\"}}"
  [ "$status" -eq 0 ]
}

@test "ext: .jsx extension matches JS case" {
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/comp.jsx\"}}"
  [ "$status" -eq 0 ]
}

@test "ext: .go file triggers gofmt" {
  echo 'package main' > "$TEST_DIR/main.go"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/main.go\"}}"
  [ "$status" -eq 0 ]
  assert_linter_called gofmt "$TEST_DIR/main.go"
}

@test "ext: .rs file triggers rustfmt" {
  echo 'fn main() {}' > "$TEST_DIR/lib.rs"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/lib.rs\"}}"
  [ "$status" -eq 0 ]
  assert_linter_called rustfmt "$TEST_DIR/lib.rs"
}

@test "ext: .rb file triggers rubocop" {
  echo 'def foo; end' > "$TEST_DIR/code.rb"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/code.rb\"}}"
  [ "$status" -eq 0 ]
  assert_linter_called rubocop "$TEST_DIR/code.rb"
}

@test "ext: .php file triggers php-cs-fixer" {
  echo '<?php function foo() {}' > "$TEST_DIR/code.php"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/code.php\"}}"
  [ "$status" -eq 0 ]
  assert_linter_called php-cs-fixer "$TEST_DIR/code.php"
}

@test "ext: .tf file triggers terraform fmt" {
  echo 'resource "x" "y" {}' > "$TEST_DIR/main.tf"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/main.tf\"}}"
  [ "$status" -eq 0 ]
  assert_linter_called terraform "$TEST_DIR/main.tf"
}

# ── Missing linter tool ─────────────────────────────────

@test "missing: linter ausente se omite sin error (solo jq en el PATH)" {
  echo 'def x(): pass' > "$TEST_DIR/x.py"
  mkdir -p "$TEST_DIR/onlyjq"
  for t in jq cat; do ln -s "$(command -v "$t")" "$TEST_DIR/onlyjq/$t"; done
  # Un linter de otro lenguaje sí está en el PATH: el stub prueba que la ausencia de ruff
  # no hace que el hook invoque otro linter (y que assert_no_linter puede fallar).
  ln -s "$STUBS/gofmt" "$TEST_DIR/onlyjq/gofmt"
  local bash_bin; bash_bin="$(command -v bash)"
  PATH="$TEST_DIR/onlyjq" run "$bash_bin" "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/x.py\"}}"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
  assert_no_linter
}

# ── ESLint local-only check ─────────────────────────────

@test "eslint: TS without local node_modules/.bin/eslint skipped" {
  # No eslint in fixture dir → should skip
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/x.ts\"}}"
  [ "$status" -eq 0 ]
}

# ── JSON parsing ────────────────────────────────────────

@test "jq: malformed JSON handled (no FILE_PATH)" {
  run bash "$HOOK" <<< "not valid JSON"
  # jq fails silently, FILE_PATH empty, exit 0
  [ "$status" -eq 0 ]
}

@test "jq: nested tool_input.file_path extracted" {
  echo 'x' > "$TEST_DIR/test.py"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/test.py\",\"other\":\"field\"}}"
  [ "$status" -eq 0 ]
}

# ── Negative cases ──────────────────────────────────────

@test "negative: null file_path exits 0" {
  run bash "$HOOK" <<< '{"tool_input":{"file_path":null}}'
  [ "$status" -eq 0 ]
}

@test "negative: file_path pointing to nonexistent file" {
  # Hook does not check existence — delegates to linter
  run bash "$HOOK" <<< '{"tool_input":{"file_path":"/absolute/nonexistent/foo.py"}}'
  [ "$status" -eq 0 ]
}

# ── Edge cases ──────────────────────────────────────────

@test "edge: file_path with spaces" {
  mkdir -p "$TEST_DIR/with spaces"
  echo 'x' > "$TEST_DIR/with spaces/code.py"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/with spaces/code.py\"}}"
  [ "$status" -eq 0 ]
}

@test "edge: uppercase .PY extension not matched (case-sensitive)" {
  echo 'x' > "$TEST_DIR/code.PY"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/code.PY\"}}"
  [ "$status" -eq 0 ]
  assert_no_linter
}

@test "edge: large empty-content file handled" {
  touch "$TEST_DIR/empty.py"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/empty.py\"}}"
  [ "$status" -eq 0 ]
}

@test "edge: zero-byte file with extension" {
  : > "$TEST_DIR/zero.rs"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/zero.rs\"}}"
  [ "$status" -eq 0 ]
}

# ── Coverage ────────────────────────────────────────────

@test "coverage: 8 language extensions in case" {
  for ext in cs py ts tsx js jsx go rs rb php tf; do
    grep -qE "^[[:space:]]*$ext\)" "$HOOK" || \
      grep -qE "[|[:space:]]$ext[\\)|]" "$HOOK" || \
      fail "missing ext case: $ext"
  done
}

@test "coverage: command -v checks before invoking linter" {
  run grep -c 'command -v' "$HOOK"
  [[ "$output" -ge 5 ]]
}

@test "coverage: error suppression via || true" {
  run grep -c '|| true' "$HOOK"
  [[ "$output" -ge 5 ]]
}

@test "coverage: jq used for JSON parsing" {
  run grep -c 'jq -r' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ───────────────────────────────────────────

@test "isolation: hook always exits 0 (never blocks)" {
  for payload in '' '{}' '{"tool_input":{"file_path":"/x.py"}}' 'bad json' '{"tool_input":{"file_path":""}}'; do
    run bash "$HOOK" <<< "$payload"
    [ "$status" -eq 0 ]
  done
}

@test "isolation: hook does not modify the lint target file" {
  echo 'original content' > "$TEST_DIR/keep.py"
  local before_hash after_hash
  before_hash=$(sha256sum "$TEST_DIR/keep.py" | cut -d' ' -f1)
  bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TEST_DIR/keep.py\"}}" >/dev/null 2>&1
  after_hash=$(sha256sum "$TEST_DIR/keep.py" | cut -d' ' -f1)
  [[ "$before_hash" == "$after_hash" ]]
}
