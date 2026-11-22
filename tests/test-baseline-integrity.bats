#!/usr/bin/env bats
# nightly: serial (mide la latencia real de los hooks; la carga paralela del runner la falsea)
# BATS integrity guard for .ci-baseline/ files (SE-046 closure).
#
# Rule: baseline must NEVER exceed current measurement + margin.
# Prevents drift where baselines accumulate slack, rendering the ratchet
# inert (SE-046 original motivation: hook-critical baseline=10 vs real=4).
#
# Ref: docs/propuestas/SE-046-baseline-re-levelling-ratchet-integrity-.md

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  BASELINE_DIR=".ci-baseline"
}
teardown() { cd /; }

@test "baseline dir exists" { [[ -d "$BASELINE_DIR" ]]; }

@test "baseline file: agent-size-violations.count present" {
  [[ -f "$BASELINE_DIR/agent-size-violations.count" ]]
}

@test "baseline file: hook-critical-violations.count present" {
  [[ -f "$BASELINE_DIR/hook-critical-violations.count" ]]
}

@test "baseline file: bats-compliance-min.pct present" {
  [[ -f "$BASELINE_DIR/bats-compliance-min.pct" ]]
}

@test "baseline agent-size: content is non-negative integer" {
  val=$(cat "$BASELINE_DIR/agent-size-violations.count" | tr -d '[:space:]')
  [[ "$val" =~ ^[0-9]+$ ]]
}

@test "baseline hook-critical: content is non-negative integer" {
  val=$(cat "$BASELINE_DIR/hook-critical-violations.count" | tr -d '[:space:]')
  [[ "$val" =~ ^[0-9]+$ ]]
}

# ── Integrity: baselines are tight vs current measurement ─────────────

@test "integrity: agent-size baseline not inflated vs measured" {
  baseline=$(cat "$BASELINE_DIR/agent-size-violations.count" | tr -d '[:space:]')
  measured=$(bash scripts/agent-size-audit.sh 2>&1 | grep -oE 'violations=[0-9]+' | head -1 | cut -d= -f2)
  [[ -n "$measured" ]]
  # Baseline must be >= measured (ratchet rule) AND not too loose (tight = within 3 units of measured)
  [[ "$baseline" -ge "$measured" ]]
  diff=$((baseline - measured))
  [[ "$diff" -le 3 ]] || {
    echo "Agent size baseline stale: baseline=$baseline, measured=$measured, diff=$diff > 3"
    echo "Run: bash scripts/baseline-tighten.sh --baseline $BASELINE_DIR/agent-size-violations.count --current $measured"
    return 1
  }
}

@test "integrity: hook-critical baseline not inflated vs measured" {
  baseline=$(cat "$BASELINE_DIR/hook-critical-violations.count" | tr -d '[:space:]')
  # Run bench to get fresh measurement (quiet mode, 5 runs)
  bash scripts/hook-bench-all.sh --runs 5 --quiet >/dev/null 2>&1 || true
  report=$(ls -t output/hook-bench-report-*.md 2>/dev/null | head -1)
  [[ -n "$report" ]]
  measured=$(grep -oP 'Critical hooks: [0-9]+ \(violations: \K\d+' "$report" | head -1)
  measured="${measured:-999}"
  [[ "$baseline" -ge "$measured" ]]
  diff=$((baseline - measured))
  [[ "$diff" -le 3 ]] || {
    echo "Hook-critical baseline stale: baseline=$baseline, measured=$measured, diff=$diff > 3"
    echo "Run: bash scripts/baseline-tighten.sh --baseline $BASELINE_DIR/hook-critical-violations.count --current $measured"
    return 1
  }
}

@test "integrity: baseline never loosens (ratchet direction enforced)" {
  # Simulate: if we invoke baseline-tighten with --current > previous, it must NOT tighten
  local tmp; tmp="$BATS_TEST_TMPDIR/baseline-test"
  echo "5" > "$tmp"
  run bash scripts/baseline-tighten.sh --baseline "$tmp" --current 10
  [ "$status" -eq 1 ]  # regression detected
  # File unchanged — baseline did NOT loosen
  [[ "$(cat "$tmp")" == "5" ]]
}

# ── Negative cases ──────────────────────────────────────

@test "negative: missing baseline file fails script gracefully" {
  run bash scripts/baseline-tighten.sh --baseline /nonexistent/baseline --current 0
  # Treats missing as 0, so current 0 == previous 0 -> noop
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "negative: non-integer current rejected" {
  run bash scripts/baseline-tighten.sh --baseline /tmp/foo --current abc
  [ "$status" -eq 2 ]
}

@test "negative: missing --baseline arg rejected" {
  run bash scripts/baseline-tighten.sh --current 5
  [ "$status" -eq 2 ]
}

@test "negative: missing --current arg rejected" {
  run bash scripts/baseline-tighten.sh --baseline /tmp/foo
  [ "$status" -eq 2 ]
}

# ── Edge cases ──────────────────────────────────────────

@test "edge: zero baseline with zero current is noop" {
  local tmp; tmp="$BATS_TEST_TMPDIR/zero"
  echo "0" > "$tmp"
  run bash scripts/baseline-tighten.sh --baseline "$tmp" --current 0
  [ "$status" -eq 0 ]
  [[ "$(cat "$tmp")" == "0" ]]
}

@test "edge: large number baseline tightens correctly" {
  local tmp; tmp="$BATS_TEST_TMPDIR/large"
  echo "999999" > "$tmp"
  run bash scripts/baseline-tighten.sh --baseline "$tmp" --current 1000
  [ "$status" -eq 0 ]
  [[ "$(cat "$tmp")" == "1000" ]]
}

@test "edge: empty baseline file treated as zero" {
  local tmp; tmp="$BATS_TEST_TMPDIR/empty"
  : > "$tmp"
  run bash scripts/baseline-tighten.sh --baseline "$tmp" --current 5
  [ "$status" -eq 1 ]  # 5 > 0 = regression
}

# ── Coverage ───────────────────────────────────────────

@test "coverage: baseline-tighten script exists and executable" {
  [[ -x "scripts/baseline-tighten.sh" ]]
}

@test "coverage: set -uo pipefail in baseline-tighten" {
  run grep -c 'set -uo pipefail' scripts/baseline-tighten.sh
  [[ "$output" -ge 1 ]]
}

@test "coverage: SE-046 reference in script" {
  run grep -c 'SE-046' scripts/baseline-tighten.sh
  [[ "$output" -ge 1 ]]
}

# ── Isolation ──────────────────────────────────────────

@test "isolation: script does not modify real baselines during test" {
  local h_before
  h_before=$(md5sum "$BASELINE_DIR"/*.count 2>/dev/null | sort | md5sum | awk '{print $1}')
  bash scripts/baseline-tighten.sh --help >/dev/null 2>&1
  local h_after
  h_after=$(md5sum "$BASELINE_DIR"/*.count 2>/dev/null | sort | md5sum | awk '{print $1}')
  [[ "$h_before" == "$h_after" ]]
}
