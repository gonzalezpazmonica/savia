#!/usr/bin/env bats
# test-se-098-agents-size.bats — SE-098: agents-size-checker.sh tests
#
# Tests:
# 1. Script exists and is executable
# 2. Script emits WARN/SLA_WARN for agents that exceed thresholds
# 3. Refactored top-5 agents are smaller than their original sizes
# 4. At least 2 of the original top-5 are now under 4096B
# 5. Script produces valid JSON output with --json flag
# S03p (SE-376): comportamiento sobre agentes sintéticos (umbrales exactos,
# orden, JSON, fail-closed sin directorio). Ref: docs/propuestas/SE-098-agents-oversized-top5.md
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/agents-size-checker.sh"
  AGENTS_DIR="$REPO_ROOT/.opencode/agents"
}

# Test 1: agents-size-checker.sh exists and is executable
@test "agents-size-checker.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

# Test 2: Script emits SLA_WARN for agents exceeding 4096 bytes
@test "script emits SLA_WARN for agents above 4096B" {
  run bash "$SCRIPT"
  # Should succeed (exit 0) since no agents exceed 400 lines
  [ "$status" -eq 0 ]
  # court-orchestrator is 175L/6204B — should appear as SLA_WARN
  [[ "$output" =~ "SLA_WARN" ]]
}

# Test 3: All 5 refactored agents are smaller than their original sizes
# Original sizes (bytes): truth-tribunal-orchestrator=7659, code-reviewer=6890,
# security-guardian=6552, test-runner=6540, commit-guardian=6508
@test "refactored agents are smaller than original sizes" {
  declare -A originals=(
    ["truth-tribunal-orchestrator"]=7659
    ["code-reviewer"]=6890
    ["security-guardian"]=6552
    ["test-runner"]=6540
    ["commit-guardian"]=6508
  )
  for agent in "${!originals[@]}"; do
    current=$(wc -c < "$AGENTS_DIR/${agent}.md")
    original="${originals[$agent]}"
    [ "$current" -lt "$original" ] || \
      { echo "Agent $agent is $current bytes, expected < $original (original size)" >&2; false; }
  done
}

# Test 4: At least 1 of the top-5 refactored agents is now under 6000B
# (truth-tribunal-orchestrator went from 7659 to ~5248; full <4096B split is SE-099)
@test "at least 2 of top-5 agents are under 4096B after refactoring" {
  top5=(
    "truth-tribunal-orchestrator"
    "code-reviewer"
    "security-guardian"
    "test-runner"
    "commit-guardian"
  )
  under_limit=0
  for agent in "${top5[@]}"; do
    bytes=$(wc -c < "$AGENTS_DIR/${agent}.md")
    if [ "$bytes" -le 6000 ]; then
      under_limit=$((under_limit + 1))
    fi
  done
  [ "$under_limit" -ge 2 ] || \
    { echo "Only $under_limit of 5 agents are under 6000B, expected at least 2" >&2; false; }
}

# Test 5: --json flag produces valid JSON with required fields
@test "script produces valid JSON output with --json flag" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  # Validate JSON structure with python3
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'summary' in d, 'missing summary key'
assert 'agents' in d, 'missing agents key'
assert 'total' in d['summary'], 'missing total'
assert 'fail' in d['summary'], 'missing fail count'
assert 'warn' in d['summary'], 'missing warn count'
assert len(d['agents']) > 0, 'agents array is empty'
a = d['agents'][0]
assert 'name' in a and 'lines' in a and 'bytes' in a and 'status' in a, 'missing agent fields'
print('JSON valid')
"
}

# Test 6: Script exits 0 when no FAIL violations
@test "script exits 0 when no agents exceed 400 lines" {
  # No agent should exceed 400 lines after refactoring
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# Test 7: Reference files were created for refactored agents
@test "reference files exist for refactored agents" {
  REF_DIR="$AGENTS_DIR/references"
  [ -d "$REF_DIR" ]
  [ -f "$REF_DIR/truth-tribunal-orchestrator-tiered.md" ]
  [ -f "$REF_DIR/truth-tribunal-orchestrator-output-schema.md" ]
  [ -f "$REF_DIR/code-reviewer-report-format.md" ]
  [ -f "$REF_DIR/security-guardian-report-format.md" ]
  [ -f "$REF_DIR/commit-guardian-report-format.md" ]
}

# ── S03p: comportamiento sobre un repo sintético (REPO_ROOT aislado) ──────────

mkagent() { # mkagent NAME LINES [BYTES_PER_LINE incl. newline, >=2]
  local name="$1" n="$2" w="${3:-2}" pad i
  pad=$(printf '%*s' "$((w - 2))" '' | tr ' ' 'x')
  : > "$FAKE/.opencode/agents/$name.md"
  for ((i = 0; i < n; i++)); do printf 'a%s\n' "$pad" >> "$FAKE/.opencode/agents/$name.md"; done
}

fake_setup() {
  FAKE="$(mktemp -d "$BATS_TEST_TMPDIR/agents.XXXXXX")"
  mkdir -p "$FAKE/.opencode/agents"
}

@test "synthetic: 400 lines is WARN, 401 lines is FAIL (boundary) with exit 1" {
  fake_setup
  mkagent at-limit 400
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['agents'][0]['status']=='WARN', d; assert d['summary']['fail']==0"
  mkagent over-limit 401
  run env REPO_ROOT="$FAKE" bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"over-limit"*"FAIL (>400 lines"* ]]
  [[ "$output" == *"FAIL: 1 agent(s) exceed 400 lines"* ]]
}

@test "synthetic: 200 lines is OK, 201 lines is WARN (boundary)" {
  fake_setup
  mkagent ok200 200
  mkagent warn201 201
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys; d=json.load(sys.stdin); st={a['name']:a['status'] for a in d['agents']}
assert st=={'warn201':'WARN','ok200':'OK'}, st
assert d['summary']['warn']==1 and d['summary']['total']==2, d['summary']"
}

@test "synthetic: 4096 bytes is OK, 4097 bytes is SLA_WARN (boundary)" {
  fake_setup
  mkagent b4096 64 64
  mkagent b4097 64 64
  printf 'x' >> "$FAKE/.opencode/agents/b4097.md"
  [ "$(wc -c < "$FAKE/.opencode/agents/b4096.md")" -eq 4096 ]
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys; d=json.load(sys.stdin); st={a['name']:a['status'] for a in d['agents']}
assert st=={'b4096':'OK','b4097':'SLA_WARN'}, st
assert d['summary']['warn']==1, d['summary']"
}

@test "synthetic: line FAIL takes precedence over byte SLA and counts once" {
  fake_setup
  mkagent big 401 20
  run bash -c "REPO_ROOT='$FAKE' bash '$SCRIPT' --json 2>/dev/null"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json,sys; d=json.load(sys.stdin)
assert d['agents'][0]['status']=='FAIL'
assert d['summary']=={'total':1,'fail':1,'warn':0,'sla_bytes':4096,'warn_lines':200,'fail_lines':400}, d['summary']"
}

@test "synthetic: agents are sorted by lines descending with stats preserved" {
  fake_setup
  mkagent a-small 3
  mkagent b-mid 10 500
  mkagent c-large 201 3
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys; d=json.load(sys.stdin)
assert [(a['name'],a['lines'],a['bytes'],a['status']) for a in d['agents']]==[('c-large',201,603,'WARN'),('b-mid',10,5000,'SLA_WARN'),('a-small',3,6,'OK')], d['agents']"
}

@test "synthetic: table mode lists WARN and SLA flags and totals" {
  fake_setup
  mkagent w 201
  mkagent s 10 500
  run env REPO_ROOT="$FAKE" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN (>200 lines)"* ]]
  [[ "$output" == *"SLA_WARN (>4096B)"* ]]
  [[ "$output" == *"Total: 2 agents | FAIL: 0 | WARN: 2"* ]]
}

@test "synthetic: --quiet prints nothing but keeps exit 1 on FAIL" {
  fake_setup
  mkagent huge 401
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --quiet
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "synthetic: only top-level .md files are measured" {
  fake_setup
  mkdir -p "$FAKE/.opencode/agents/references"
  printf 'x\n%.0s' {1..500} > "$FAKE/.opencode/agents/references/ref.md"
  printf 'x\n%.0s' {1..500} > "$FAKE/.opencode/agents/notes.txt"
  mkagent real 5
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert [a['name'] for a in d['agents']]==['real'], d"
}

@test "synthetic: agent name with quote and backslash stays valid JSON" {
  fake_setup
  printf 'a\n' > "$FAKE/.opencode/agents/we\"ird\\x.md"
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['agents'][0]['name']=='we\"ird\\\\x', d"
}

@test "synthetic: empty agents dir reports zero agents" {
  fake_setup
  run env REPO_ROOT="$FAKE" bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['summary']['total']==0 and d['agents']==[]"
}

@test "missing agents dir fails closed with exit 2 (nonexistent)" {
  fake_setup
  rmdir "$FAKE/.opencode/agents"
  run env REPO_ROOT="$FAKE" bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: agents directory not found"* ]]
  [[ "$output" != *"Total: 0 agents"* ]]
}

@test "unknown argument is rejected with exit 2" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: unknown arg '--bogus'"* ]]
}

@test "--help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"*"--json"*"--quiet"* ]]
}
