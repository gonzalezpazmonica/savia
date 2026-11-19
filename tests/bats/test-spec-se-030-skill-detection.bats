#!/usr/bin/env bats
# tests/bats/test-spec-se-030-skill-detection.bats — SPEC-SE-030 Skill Self-Improvement Phase 1
#
# Tests for scripts/skill-usage-tracker.py
# Ref: docs/propuestas/savia-enterprise/SPEC-SE-030-skill-self-improvement.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TRACKER="$REPO_ROOT/scripts/skill-usage-tracker.py"
  TMPDIR_TEST="$(mktemp -d)"
  export DATA_DIR="$TMPDIR_TEST/data"
  export OUTPUT_DIR="$TMPDIR_TEST/output"
  export INVOCATIONS_LOG="$TMPDIR_TEST/data/skill-invocations.jsonl"
  mkdir -p "$DATA_DIR" "$OUTPUT_DIR"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ── Test 1: skill-pattern-detector.sh exists and is executable ───────────────

# ── Test 2: --json produces JSON with patterns_found ─────────────────────────

# ── Test 3: skill-usage-tracker.py exists ────────────────────────────────────

@test "skill-usage-tracker.py exists in scripts/" {
  [ -f "$TRACKER" ]
}

# ── Test 4: script does not fail with empty data/ ────────────────────────────

# ── Test 5: no data returns patterns_found=0 ─────────────────────────────────

# ── Test 6: usage-tracker appends entry to JSONL ─────────────────────────────

@test "skill-usage-tracker.py appends entry to JSONL file" {
  run python3 "$TRACKER" \
    --skill "test-skill" \
    --command "/test-cmd" \
    --session "bats-session-001" \
    --invocations-file "$INVOCATIONS_LOG"
  [ "$status" -eq 0 ]
  [ -f "$INVOCATIONS_LOG" ]
  count=$(wc -l < "$INVOCATIONS_LOG")
  [ "$count" -ge 1 ]
}

# ── Test 7: usage-tracker entry has required fields ───────────────────────────

@test "skill-usage-tracker.py entry has ts, skill, command, session_id" {
  python3 "$TRACKER" \
    --skill "my-skill" \
    --command "/my-cmd" \
    --session "sess-42" \
    --invocations-file "$INVOCATIONS_LOG"

  has_all=$(python3 -c "
import json
r = json.loads(open('$INVOCATIONS_LOG').read().strip())
required = {'ts','skill','command','session_id'}
missing = required - set(r.keys())
print('ok' if not missing else 'MISSING:'+str(missing))
" 2>/dev/null)
  [ "$has_all" = "ok" ]
}

# ── Test 8: pattern detection with sufficient synthetic sessions ──────────────

# ── Test 9: patterns have sequence, count, suggestion ────────────────────────

# ── Test 10: suggestion not empty ────────────────────────────────────────────
