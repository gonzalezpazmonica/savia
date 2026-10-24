#!/usr/bin/env bats
# test-se-022-bench.bats — SE-022 Resource Bench Management
# Ref: docs/propuestas/savia-enterprise/SPEC-SE-022-resource-bench.md

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BENCH_REGISTER="${REPO_ROOT}/scripts/enterprise/bench-register.sh"
  BENCH_MATCH="${REPO_ROOT}/scripts/enterprise/bench-match.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR REPO_ROOT
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

_register() {
  local tenant="$1" user="$2" skills="$3" from="$4"
  bash -c "REPO_ROOT='${TEST_TMPDIR}' bash '${BENCH_REGISTER}' \
    --user '${user}' --tenant '${tenant}' \
    --skills '${skills}' --available-from '${from}'" >/dev/null 2>&1
}

# ── bench-register.sh ────────────────────────────────────────────────────────

@test "SE-022: bench-register.sh exists and is executable" {
  [[ -f "$BENCH_REGISTER" ]]
  [[ -x "$BENCH_REGISTER" ]]
}

@test "SE-022: bench-register.sh fails without required args" {
  run bash "$BENCH_REGISTER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"required"* ]]
}

@test "SE-022: bench-register.sh creates yaml with correct fields" {
  local tenant="bench-$$"
  local user="dev-alice"
  local skills="python,terraform,azure"
  local from="2026-07-01"

  run bash -c "REPO_ROOT='${TEST_TMPDIR}' bash '${BENCH_REGISTER}' \
    --user '${user}' \
    --tenant '${tenant}' \
    --skills '${skills}' \
    --available-from '${from}' \
    --until '2026-12-31'"
  [ "$status" -eq 0 ]

  local bench_file="${TEST_TMPDIR}/tenants/${tenant}/bench/${user}.yaml"
  [[ -f "$bench_file" ]]
  grep -q "user: \"${user}\"" "$bench_file"
  grep -q "tenant: \"${tenant}\"" "$bench_file"
  grep -q "available_from: \"${from}\"" "$bench_file"
  grep -q "status: available" "$bench_file"
  grep -q "python" "$bench_file"
  grep -q "terraform" "$bench_file"
  grep -q "azure" "$bench_file"
}

@test "SE-022: bench-register.sh stores all required yaml keys" {
  local tenant="struct-$$"
  local user="dev-bob"

  bash -c "REPO_ROOT='${TEST_TMPDIR}' bash '${BENCH_REGISTER}' \
    --user '${user}' --tenant '${tenant}' \
    --skills 'java,spring' --available-from '2026-07-01'" >/dev/null

  local bench_file="${TEST_TMPDIR}/tenants/${tenant}/bench/${user}.yaml"
  grep -q "^user:" "$bench_file"
  grep -q "^tenant:" "$bench_file"
  grep -q "^registered_at:" "$bench_file"
  grep -q "^available_from:" "$bench_file"
  grep -q "^skills:" "$bench_file"
  grep -q "^status:" "$bench_file"
}

@test "SE-022: bench-register.sh rejects invalid date format" {
  run bash "$BENCH_REGISTER" \
    --user dev --tenant t --skills "go" --available-from "01/07/2026"
  [ "$status" -eq 2 ]
}

# ── bench-match.sh ───────────────────────────────────────────────────────────

@test "SE-022: bench-match.sh exists and is executable" {
  [[ -f "$BENCH_MATCH" ]]
  [[ -x "$BENCH_MATCH" ]]
}

@test "SE-022: bench-match.sh fails without required args" {
  run bash "$BENCH_MATCH"
  [ "$status" -eq 2 ]
}

@test "SE-022: bench-match.sh returns candidates for matching skills" {
  local tenant="match-$$"
  _register "$tenant" "alice" "python,azure,terraform" "2026-07-01"
  _register "$tenant" "bob"   "java,spring"            "2026-07-15"

  run bash -c "REPO_ROOT='${TEST_TMPDIR}' bash '${BENCH_MATCH}' \
    --skills 'python,azure' --from '2026-07-01' --tenant '${tenant}' --json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  # bob shouldn't appear (no python/azure)
  [[ "$output" != *'"user":"bob"'* ]]
}

@test "SE-022: bench-match.sh calculates skills_match_pct correctly" {
  local tenant="pct-$$"
  # alice has 3/4 required skills → 75%
  _register "$tenant" "alice" "python,azure,terraform" "2026-07-01"

  run bash -c "REPO_ROOT='${TEST_TMPDIR}' bash '${BENCH_MATCH}' \
    --skills 'python,azure,terraform,kubernetes' \
    --from '2026-07-01' --tenant '${tenant}' --json"
  [ "$status" -eq 0 ]

  pct=$(echo "$output" | grep -o '"skills_match_pct":[0-9]*' | head -1 | cut -d: -f2)
  [[ "$pct" -eq 75 ]]
}

@test "SE-022: bench-match.sh resource with 0% match excluded by threshold" {
  local tenant="thresh-$$"
  _register "$tenant" "carol" "ruby,rails" "2026-07-01"

  run bash -c "REPO_ROOT='${TEST_TMPDIR}' bash '${BENCH_MATCH}' \
    --skills 'python,go' --from '2026-07-01' \
    --tenant '${tenant}' --threshold 50 --json"
  # No match above 50% → exit 1
  [ "$status" -eq 1 ]
}

@test "SE-022: bench-match.sh returns JSON with matches field" {
  local tenant="jsonkeys-$$"
  _register "$tenant" "dave" "dotnet,azure,sql" "2026-07-01"

  run bash -c "REPO_ROOT='${TEST_TMPDIR}' bash '${BENCH_MATCH}' \
    --skills 'dotnet' --from '2026-07-01' --tenant '${tenant}' --json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"matches\""* ]]
  [[ "$output" == *"\"tenant\""* ]]
  [[ "$output" == *"\"required_skills\""* ]]
}
