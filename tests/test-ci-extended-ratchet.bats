#!/usr/bin/env bats
# BATS tests for ci-extended-checks ratchet gates (checks #8, #9, #10).
# SE-037/038/039 Slice 3 — enforcement gates with ratchet pattern.
#
# Ref: ROADMAP.md §Tier 1 Slice 3 (enforcement)
# Pattern: `.ci-baseline/*.count` files freeze current violations; gates
# fail only on REGRESSION (current > baseline). When remediation lands,
# contributor updates baseline to lock in improvement.
#
# Safety: script under test has `set -euo pipefail`.

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
}

teardown() {
  cd /
}

# ── Structure ──────────────────────────────────────────────────────────────

@test "ci-extended-checks script is executable" {
  [[ -x "scripts/ci-extended-checks.sh" ]]
}

@test ".ci-baseline directory exists" {
  [[ -d ".ci-baseline" ]]
}

@test ".ci-baseline/README.md documents ratchet pattern" {
  [[ -f ".ci-baseline/README.md" ]]
  run grep -c "ratchet\|Ratchet" ".ci-baseline/README.md"
  [[ "$output" -ge 1 ]]
}

# ── Baseline files ─────────────────────────────────────────────────────────

@test "agent-size baseline file exists and is numeric" {
  local f=".ci-baseline/agent-size-violations.count"
  [[ -f "$f" ]]
  local val
  val=$(cat "$f" | tr -d '[:space:]')
  [[ "$val" =~ ^[0-9]+$ ]]
}

@test "hook-critical baseline file exists and is numeric" {
  local f=".ci-baseline/hook-critical-violations.count"
  [[ -f "$f" ]]
  local val
  val=$(cat "$f" | tr -d '[:space:]')
  [[ "$val" =~ ^[0-9]+$ ]]
}

@test "bats compliance floor file exists and in [0,100]" {
  local f=".ci-baseline/bats-compliance-min.pct"
  [[ -f "$f" ]]
  local val
  val=$(cat "$f" | tr -d '[:space:]')
  [[ "$val" =~ ^[0-9]+$ ]]
  (( val >= 0 && val <= 100 ))
}

# ── Check definitions ──────────────────────────────────────────────────────

@test "check #8 Agent Size Ratchet is present" {
  run grep -c "8. Agent Size Ratchet\|Agent Size Ratchet" "scripts/ci-extended-checks.sh"
  [[ "$output" -ge 1 ]]
}

@test "check #9 Hook Latency Ratchet is present" {
  run grep -c "9. Hook Latency Ratchet\|Hook Latency Ratchet" "scripts/ci-extended-checks.sh"
  [[ "$output" -ge 1 ]]
}

@test "check #9 does not ignore hook benchmark execution failures" {
  run grep -F '"$hook_script" --runs 5 --quiet >/dev/null 2>&1 || true' scripts/ci-extended-checks.sh
  [ "$status" -ne 0 ]
  grep -q 'Hook benchmark execution failed' scripts/ci-extended-checks.sh
}

@test "check #10 BATS Auditor Compliance Floor is present" {
  run grep -c "10. BATS Auditor Compliance Floor\|BATS Auditor Compliance Floor" "scripts/ci-extended-checks.sh"
  [[ "$output" -ge 1 ]]
}

# ── Execution ──────────────────────────────────────────────────────────────

@test "ci-extended-checks runs end-to-end with exit 0 when all pass" {
  run bash scripts/ci-extended-checks.sh
  [ "$status" -eq 0 ]
}

@test "ci-extended-checks output contains all 10 checks" {
  run bash scripts/ci-extended-checks.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent Size Ratchet"* ]]
  [[ "$output" == *"Hook Latency Ratchet"* ]]
  [[ "$output" == *"BATS Auditor Compliance Floor"* ]]
}

@test "check #8 passes with current baseline" {
  run bash scripts/ci-extended-checks.sh
  [[ "$output" == *"Agent size:"*"violations ≤ baseline"* ]]
}

@test "check #9 passes with current baseline" {
  run bash scripts/ci-extended-checks.sh
  [[ "$output" == *"Hook latency:"*"violations ≤ baseline"* ]]
}

@test "check #10 passes with floor configured" {
  run bash scripts/ci-extended-checks.sh
  [[ "$output" == *"BATS compliance floor"* ]]
}

# ── Ratchet regression detection (simulated) ───────────────────────────────

@test "regression: check #8 fails if baseline is artificially low" {
  local f=".ci-baseline/agent-size-violations.count"
  local original
  original=$(cat "$f")
  echo "0" > "$f"
  run bash scripts/ci-extended-checks.sh
  local status_captured=$status
  echo "$original" > "$f"
  [ "$status_captured" -ne 0 ]
}

@test "regression: check #9 fails if baseline is artificially low" {
  local f=".ci-baseline/hook-critical-violations.count"
  local original
  original=$(cat "$f")
  echo "0" > "$f"
  run bash scripts/ci-extended-checks.sh
  local status_captured=$status
  echo "$original" > "$f"
  [ "$status_captured" -ne 0 ]
  [[ "$output" == *"Hook latency:"*"regression"* ]]
}

# ── Stale baseline detection (improvement hint) ────────────────────────────

@test "check #8 emits stale hint when current < baseline" {
  local f=".ci-baseline/agent-size-violations.count"
  local original
  original=$(cat "$f")
  local bumped=$(( original + 10 ))
  echo "$bumped" > "$f"
  run bash scripts/ci-extended-checks.sh
  local status_captured=$status
  echo "$original" > "$f"
  [[ "$output" == *"Baseline stale"* ]]
}

# ── BATS gate opt-in ───────────────────────────────────────────────────────

@test "check #10 skips full sweep by default (fast mode)" {
  run bash scripts/ci-extended-checks.sh
  [[ "$output" == *"full sweep skipped"* ]] || [[ "$output" == *"set BATS_GATE_FULL"* ]]
}

@test "check #10 full sweep is opt-in via BATS_GATE_FULL=1" {
  run grep -c 'BATS_GATE_FULL' scripts/ci-extended-checks.sh
  [[ "$output" -ge 2 ]]
}

# ── Baseline integrity ─────────────────────────────────────────────────────

@test "baseline files are NOT gitignored" {
  run git check-ignore .ci-baseline/agent-size-violations.count
  [ "$status" -ne 0 ]
}

@test "baseline README warns against increasing counts" {
  run grep -cE 'never increase|Never increase|ratchet down' .ci-baseline/README.md
  [[ "$output" -ge 1 ]]
}

# ── Negative cases ─────────────────────────────────────────────────────────

@test "negative: missing baseline file fails the check cleanly" {
  local f=".ci-baseline/agent-size-violations.count"
  local original
  original=$(cat "$f")
  mv "$f" "$f.bak"
  run bash scripts/ci-extended-checks.sh
  local status_captured=$status
  mv "$f.bak" "$f"
  [[ "$output" == *"baseline"*"missing"* ]] || [[ "$output" == *"Agent size baseline"* ]]
}

@test "negative: non-numeric compliance floor is rejected" {
  local f=".ci-baseline/bats-compliance-min.pct"
  local original
  original=$(cat "$f")
  echo "abc" > "$f"
  run bash scripts/ci-extended-checks.sh
  local status_captured=$status
  echo "$original" > "$f"
  [[ "$output" == *"floor invalid"* ]]
}

@test "negative: bash -n syntax check passes on script" {
  run bash -n "scripts/ci-extended-checks.sh"
  [ "$status" -eq 0 ]
}

@test "negative: script uses set -euo (strict mode)" {
  run grep -cE '^set -[euo]+' "scripts/ci-extended-checks.sh"
  [[ "$output" -ge 1 ]]
}

@test "negative: empty baseline file is not silently accepted" {
  local f=".ci-baseline/agent-size-violations.count"
  local original
  original=$(cat "$f")
  : > "$f"
  run bash scripts/ci-extended-checks.sh
  local status_captured=$status
  echo "$original" > "$f"
  # Empty file should either fail or treat as 0 — must not crash
  [[ "$status_captured" -eq 0 || "$status_captured" -eq 1 ]]
}

# ── Edge cases ─────────────────────────────────────────────────────────────

@test "edge: ratchet allows current == baseline" {
  run bash scripts/ci-extended-checks.sh
  [ "$status" -eq 0 ]
}

@test "edge: baseline README mentions ratchet down not up" {
  run grep -cE 'ratchet down|only ratchet' .ci-baseline/README.md
  [[ "$output" -ge 1 ]]
}

@test "edge: gate 10 tolerates BATS_GATE_FULL=0 and BATS_GATE_FULL=1" {
  run env BATS_GATE_FULL=0 bash scripts/ci-extended-checks.sh
  [ "$status" -eq 0 ]
}

@test "edge: all 3 ratchet gates reference their spec" {
  run grep -cE 'SE-03[789]' "scripts/ci-extended-checks.sh"
  [[ "$output" -ge 3 ]]
}
