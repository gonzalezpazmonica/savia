#!/usr/bin/env bats
# tests/test-se-217-surface-guard.bats — SE-217 Slice 3: Surface Guard
# Ref: docs/propuestas/SE-217-autoresearch-patterns.md

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/agent-surface-guard.sh"

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------
setup() {
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
  export SAVIA_EVO_DIR="${TMP_DIR}/.evo"
  # Point the script at a temp workspace so git ops are isolated
  export SAVIA_WORKSPACE_DIR="${TMP_DIR}"
  # Initialise a bare git repo in TMP_DIR so git commands succeed
  git -C "$TMP_DIR" init -q
  git -C "$TMP_DIR" config user.email "test@test.com"
  git -C "$TMP_DIR" config user.name "Test"
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

# ---------------------------------------------------------------------------
# Helper: stage a file in TMP_DIR
# ---------------------------------------------------------------------------
_stage_file() {
  local rel_path="$1"
  local full_path="${TMP_DIR}/${rel_path}"
  mkdir -p "$(dirname "$full_path")"
  echo "content" > "$full_path"
  git -C "$TMP_DIR" add "$rel_path"
}

# ---------------------------------------------------------------------------
# 1. Infrastructure
# ---------------------------------------------------------------------------

@test "script exists at expected path" {
  [[ -f "$SCRIPT" ]]
}

@test "script is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "script uses set -uo pipefail" {
  run grep -E "^set -uo pipefail" "$SCRIPT"
  [[ "$status" -eq 0 ]]
}

@test "script header references SE-217 spec" {
  run grep "SE-217" "$SCRIPT"
  [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# 2. declare subcommand
# ---------------------------------------------------------------------------

@test "declare creates surface.json with correct fields" {
  run bash "$SCRIPT" declare \
    --run-id "test-run-01" \
    --editable "src/ tests/" \
    --readonly "CLAUDE.md scripts/" \
    --forbidden ".git/"
  [[ "$status" -eq 0 ]]
  local sf="${SAVIA_EVO_DIR}/test-run-01/surface.json"
  [[ -f "$sf" ]]
  run python3 -c "
import json, sys
d = json.load(open('${sf}'))
assert d['run_id'] == 'test-run-01', f'run_id mismatch: {d}'
assert 'src/' in d['editable'], f'editable: {d}'
assert 'tests/' in d['editable'], f'editable: {d}'
assert 'CLAUDE.md' in d['readonly'], f'readonly: {d}'
assert '.git/' in d['forbidden'], f'forbidden: {d}'
print('OK')
"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "OK" ]]
}

@test "surface.json is valid JSON" {
  bash "$SCRIPT" declare \
    --run-id "test-json-valid" \
    --editable "output/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  local sf="${SAVIA_EVO_DIR}/test-json-valid/surface.json"
  run python3 -c "import json; json.load(open('${sf}')); print('valid')"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valid" ]]
}

@test "declare without --run-id exits with error" {
  run bash "$SCRIPT" declare --editable "src/"
  [[ "$status" -ne 0 ]]
  [[ "$output" =~ "run-id" || "${lines[0]}" =~ "run-id" ]] || \
    echo "$output" | grep -qi "run.id"
}

@test "declare creates .evo directory automatically if missing" {
  rm -rf "${SAVIA_EVO_DIR}"
  run bash "$SCRIPT" declare \
    --run-id "auto-evo" \
    --editable "output/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  [[ "$status" -eq 0 ]]
  [[ -d "${SAVIA_EVO_DIR}" ]]
}

# ---------------------------------------------------------------------------
# 3. verify subcommand
# ---------------------------------------------------------------------------

@test "verify with staged file in editable exits 0" {
  bash "$SCRIPT" declare \
    --run-id "vtest-editable" \
    --editable "src/ tests/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  _stage_file "src/foo.py"
  run bash "$SCRIPT" verify --run-id "vtest-editable"
  [[ "$status" -eq 0 ]]
}

@test "verify with staged file in readonly exits 1 and mentions file" {
  bash "$SCRIPT" declare \
    --run-id "vtest-readonly" \
    --editable "src/" \
    --readonly "CLAUDE.md scripts/" \
    --forbidden ".git/"
  _stage_file "CLAUDE.md"
  run bash "$SCRIPT" verify --run-id "vtest-readonly"
  [[ "$status" -eq 1 ]]
  [[ "${output}" =~ "CLAUDE.md" ]]
}

@test "verify with staged file in forbidden exits 1 with FORBIDDEN message" {
  bash "$SCRIPT" declare \
    --run-id "vtest-forbidden" \
    --editable "src/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/ danger/"
  _stage_file "danger/secret.txt"
  run bash "$SCRIPT" verify --run-id "vtest-forbidden"
  [[ "$status" -eq 1 ]]
  [[ "${output}" =~ "FORBIDDEN" ]]
}

@test "verify on clean repo (no staged files) exits 0" {
  bash "$SCRIPT" declare \
    --run-id "vtest-clean" \
    --editable "src/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  # Ensure no staged files
  run bash "$SCRIPT" verify --run-id "vtest-clean"
  [[ "$status" -eq 0 ]]
}

@test "verify without --run-id uses defaults and does not fail on clean repo" {
  run bash "$SCRIPT" verify
  [[ "$status" -eq 0 ]]
}

@test "READONLY has precedence over EDITABLE for same file" {
  bash "$SCRIPT" declare \
    --run-id "vtest-precedence" \
    --editable "src/ CLAUDE.md" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  _stage_file "CLAUDE.md"
  run bash "$SCRIPT" verify --run-id "vtest-precedence"
  # READONLY wins: exit 1
  [[ "$status" -eq 1 ]]
  [[ "${output}" =~ "READONLY" ]]
}

# ---------------------------------------------------------------------------
# 4. context subcommand
# ---------------------------------------------------------------------------

@test "context generates block with EDITABLE READ-ONLY FORBIDDEN sections" {
  bash "$SCRIPT" declare \
    --run-id "ctx-test" \
    --editable "src/ tests/" \
    --readonly "CLAUDE.md scripts/" \
    --forbidden ".git/"
  run bash "$SCRIPT" context --run-id "ctx-test"
  [[ "$status" -eq 0 ]]
  [[ "${output}" =~ "EDITABLE" ]]
  [[ "${output}" =~ "READ-ONLY" ]]
  [[ "${output}" =~ "FORBIDDEN" ]]
}

@test "context without --run-id exits with error" {
  run bash "$SCRIPT" context
  [[ "$status" -ne 0 ]]
  [[ "${output}" =~ "run-id" ]] || echo "$output" | grep -qi "run.id"
}

# ---------------------------------------------------------------------------
# 5. list subcommand
# ---------------------------------------------------------------------------

@test "list shows declared run_id" {
  bash "$SCRIPT" declare \
    --run-id "list-run-01" \
    --editable "src/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  run bash "$SCRIPT" list
  [[ "$status" -eq 0 ]]
  [[ "${output}" =~ "list-run-01" ]]
}

# ---------------------------------------------------------------------------
# 6. Edge cases
# ---------------------------------------------------------------------------

@test "editable directory with no files does not produce error" {
  bash "$SCRIPT" declare \
    --run-id "empty-editable" \
    --editable "empty-dir/ tests/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  # Stage a file in tests/ (known editable); empty-dir/ doesn't exist — no error
  _stage_file "tests/some_test.sh"
  run bash "$SCRIPT" verify --run-id "empty-editable"
  [[ "$status" -eq 0 ]]
}

@test "verify staged file NOT in any surface category exits 1" {
  bash "$SCRIPT" declare \
    --run-id "vtest-outside" \
    --editable "src/" \
    --readonly "CLAUDE.md" \
    --forbidden ".git/"
  _stage_file "random/outside.txt"
  run bash "$SCRIPT" verify --run-id "vtest-outside"
  [[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Barrido Python 2026-11-27: los nombres de run no entran como código Python
# ---------------------------------------------------------------------------
@test "list: un run_id con comillas no ejecuta código en python3 -c" {
  local rid="x'+str(__import__('pathlib').Path('pwned-list').touch())+'"
  mkdir -p "${SAVIA_EVO_DIR}/${rid}"
  printf '{"run_id":"r","declared_at":"t","editable":[],"readonly":[],"forbidden":[]}\n' \
    > "${SAVIA_EVO_DIR}/${rid}/surface.json"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SCRIPT" list
  [ ! -e "$BATS_TEST_TMPDIR/pwned-list" ]
  [[ "$output" == *"r  t"* ]]
}
