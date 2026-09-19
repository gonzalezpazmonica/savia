#!/usr/bin/env bats
# SE-397 F5A characterization, safety and benchmark contract.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/se397-f5-hot-path-bench.sh"
  export HOOK="$REPO_ROOT/.opencode/hooks/validate-bash-global.sh"
  export FIXTURES="$REPO_ROOT/tests/fixtures/se397-f5"
  export SAVIA_HOOK_PROFILE="standard"
  export CLAUDE_PROJECT_DIR="$REPO_ROOT"
}

@test "runner and fixture corpus are present" {
  [[ -x "$SCRIPT" ]]
  jq -e '.safe | length == 10' "$FIXTURES/cases.json"
  jq -e '.parity | length == 13' "$FIXTURES/cases.json"
}

@test "pre-change oracle covers every parity case without raw commands" {
  run python3 - "$FIXTURES/cases.json" "$FIXTURES/oracle.json" <<'PY'
import json, sys
cases = json.load(open(sys.argv[1], encoding="utf-8"))["parity"]
oracle = json.load(open(sys.argv[2], encoding="utf-8"))
assert {c["id"] for c in cases} == {c["id"] for c in oracle["cases"]}
assert all(set(c) == {"id", "exit", "stderr_sha256"} for c in oracle["cases"])
assert all(len(c["stderr_sha256"]) == 64 for c in oracle["cases"])
PY
  [[ "$status" -eq 0 ]]
}

@test "runner rejects arbitrary hook and invalid run counts" {
  run "$SCRIPT" --hook /tmp/other --runs 3 --output output/se397-f5/rejected.json
  [[ "$status" -eq 2 ]]
  run "$SCRIPT" --runs 2 --output output/se397-f5/rejected.json
  [[ "$status" -eq 2 ]]
  run "$SCRIPT" --runs nope --output output/se397-f5/rejected.json
  [[ "$status" -eq 2 ]]
}

@test "runner rejects output escape and symlink" {
  run "$SCRIPT" --runs 3 --output ../escape.json
  [[ "$status" -eq 2 ]]
  local link="$REPO_ROOT/output/se397-f5-link"
  ln -s "$BATS_TEST_TMPDIR" "$link"
  run "$SCRIPT" --runs 3 --output output/se397-f5-link/report.json
  rm -f "$link"
  [[ "$status" -eq 2 ]]
}

@test "nearest-rank percentile contract is explicit" {
  run python3 - <<'PY'
import math
xs = [1, 2, 3, 4, 100]
def p(r): return sorted(xs)[math.ceil(len(xs) * r) - 1]
assert [p(.50), p(.95), p(.99)] == [3, 100, 100]
PY
  [[ "$status" -eq 0 ]]
}

@test "runner emits canonical parity report" {
  local report="output/se397-f5/test-${BATS_TEST_NUMBER}.json"
  run "$SCRIPT" --runs 3 --output "$report"
  [[ "$status" -eq 0 ]]
  run jq -e '
    .schema_version == 1 and
    .report == "se397-f5-hot-path" and
    .target == ".opencode/hooks/validate-bash-global.sh" and
    .runs == 3 and
    .safe.samples == 30 and
    .parity == {"cases":13,"matched":13,"status":"MATCH"} and
    (.limitations | length == 4)
  ' "$REPO_ROOT/$report"
  [[ "$status" -eq 0 ]]
}

@test "irrelevant input can be proven to avoid environment sources" {
  local trace="$BATS_TEST_TMPDIR/trace"
  exec 19>"$trace"
  run env BASH_XTRACEFD=19 bash -x "$HOOK" <<< '{"tool_input":{"command":"printf ok"}}'
  exec 19>&-
  [[ "$status" -eq 0 ]]
  ! grep -qE 'savia-env\.sh|profile-gate\.sh' "$trace"
}

@test "mixed-case and punctuated relevance tokens select full path" {
  local command
  for command in '/usr/bin/GIT status' 'x;Rm -rf /tmp/x' 'CHMOD 755 x' \
    'CURL --version' 'GH --version' 'SUDO -n true' 'git-lfs version'; do
    local trace="$BATS_TEST_TMPDIR/trace-${RANDOM}"
    exec 19>"$trace"
    run env BASH_XTRACEFD=19 bash -x "$HOOK" <<< "{\"tool_input\":{\"command\":\"$command\"}}"
    exec 19>&-
    grep -q 'savia-env\.sh' "$trace"
  done
}

@test "malformed empty and non-string commands preserve full path" {
  local payload
  for payload in '' 'broken json' '{"tool_input":{}}' '{"tool_input":{"command":["printf","ok"]}}'; do
    local trace="$BATS_TEST_TMPDIR/trace-${RANDOM}"
    exec 19>"$trace"
    run env BASH_XTRACEFD=19 bash -x "$HOOK" <<< "$payload"
    exec 19>&-
    [[ "$status" -eq 0 ]]
    grep -q 'savia-env\.sh' "$trace"
  done
}
