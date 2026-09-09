#!/usr/bin/env bats
# Tests for spec-quality-auditor.sh — deterministic spec quality scorer
# Ref: eval-criteria.md, SPEC-055

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/spec-quality-auditor.sh"

setup() {
  export TMPDIR_TEST=$(mktemp -d)
  mkdir -p "$TMPDIR_TEST/specs"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ── Structure ──

@test "spec-auditor: script is valid bash" {
  bash -n "$SCRIPT"
}

@test "spec-auditor: uses set -uo pipefail" {
  grep -q "set -uo pipefail" "$SCRIPT"
}

@test "spec-auditor: --help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
}

# ── Positive cases ──

@test "spec-auditor: high-quality spec scores 80+" {
  cat > "$TMPDIR_TEST/specs/SPEC-999-good.md" << 'MD'
# SPEC-999: Test Feature

**Status**: Approved | **Date**: 2026-04-03 | **Era**: 177

## Problem

Users cannot validate spec quality before implementation.

## Solution

A deterministic scorer that checks 9 criteria without LLM.

## Acceptance Criteria

- AC-1: Score output is JSON with total field
- AC-2: Specs with all sections score >= 80
- AC-3: Missing sections reduce score proportionally

## Effort

Estimated: 4h implementation + 2h tests.

## Dependencies

Depends on SPEC-055 (test auditor pattern).

## Verification

Run: bash scripts/spec-quality-auditor.sh spec.md
Verify JSON output with jq. Run BATS tests.
MD
  run bash "$SCRIPT" "$TMPDIR_TEST/specs/SPEC-999-good.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"total":'* ]]
  score=$(echo "$output" | grep -oP '"total":\K[0-9]+')
  [ "$score" -ge 80 ]
}

@test "spec-auditor: low-quality spec scores below 80" {
  cat > "$TMPDIR_TEST/specs/SPEC-998-bad.md" << 'MD'
# Some feature

We should probably do something about this thing.
It would be nice to have.
MD
  run bash "$SCRIPT" "$TMPDIR_TEST/specs/SPEC-998-bad.md"
  [ "$status" -eq 0 ]
  score=$(echo "$output" | grep -oP '"total":\K[0-9]+')
  [ "$score" -lt 80 ]
}

@test "spec-auditor: outputs valid JSON" {
  cat > "$TMPDIR_TEST/specs/SPEC-997.md" << 'MD'
# SPEC-997: JSON test
**Status**: Draft | **Date**: 2026-04-03
## Problem
Test.
## Solution
Test.
MD
  run bash "$SCRIPT" "$TMPDIR_TEST/specs/SPEC-997.md"
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null
}

# ── Negative cases ──

@test "spec-auditor: no args exits 1" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "spec-auditor: nonexistent file reports error" {
  run bash "$SCRIPT" "/nonexistent/spec.md"
  [[ "$output" == *"error"* ]] || [[ "$output" == *"not found"* ]]
}

# ── Edge cases ──

@test "spec-auditor: empty spec scores low" {
  touch "$TMPDIR_TEST/specs/SPEC-000-empty.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/specs/SPEC-000-empty.md"
  [ "$status" -eq 0 ]
  score=$(echo "$output" | grep -oP '"total":\K[0-9]+')
  [ "$score" -lt 30 ]
}

@test "spec-auditor: batch mode scans directory" {
  cat > "$TMPDIR_TEST/specs/SPEC-001-a.md" << 'MD'
# SPEC-001: A
## Problem
X.
MD
  run bash "$SCRIPT" --batch "$TMPDIR_TEST/specs"
  [[ "$output" == *'"batch":true'* ]]
  [[ "$output" == *'"total":1'* ]]
}

@test "spec-auditor: batch with min-score filters" {
  cat > "$TMPDIR_TEST/specs/SPEC-002-low.md" << 'MD'
# Bad spec
Nothing here.
MD
  run bash "$SCRIPT" --batch "$TMPDIR_TEST/specs" --min-score 50
  [[ "$output" == *'"failed":1'* ]]
}

# ── Coverage breadth ──

@test "spec-auditor: score_spec function exists" {
  grep -q 'score_spec' "$SCRIPT"
}

@test "spec-auditor: checks 9 criteria (C1-C9)" {
  grep -q '# C1:' "$SCRIPT"
  grep -q '# C5:' "$SCRIPT"
  grep -q '# C9:' "$SCRIPT"
}

@test "spec-auditor: certified field in output" {
  cat > "$TMPDIR_TEST/specs/SPEC-100.md" << 'MD'
# SPEC-100: Test
MD
  run bash "$SCRIPT" "$TMPDIR_TEST/specs/SPEC-100.md"
  [[ "$output" == *'"certified":'* ]]
}

@test "spec-auditor: real specs produce valid scores" {
  run bash "$SCRIPT" "$BATS_TEST_DIRNAME/../../docs/propuestas/SPEC-055-test-auditor.md"
  [ "$status" -eq 0 ]
  score=$(echo "$output" | grep -oP '"total":\K[0-9]+')
  [ "$score" -ge 50 ]
}

@test "spec-auditor: long spec does not lose matched criteria to broken pipe" {
  local spec="$TMPDIR_TEST/specs/SE-999-long.spec.md"
  {
    echo '# SE-999: Long specification'
    echo 'status: APPROVED'
    echo 'date: 2026-09-09'
    echo 'author: operator'
    echo '## Problem'
    echo 'A reproducible problem.'
    echo '## Solution'
    echo 'A deterministic solution.'
    echo '## Acceptance Criteria'
    echo '- AC-1: verified with tests'
    echo '## Effort'
    echo 'Estimated: 2h'
    echo '## Dependencies'
    echo 'Requires SE-051'
    seq 1 3000 | sed 's/^/filler line /'
  } > "$spec"

  run bash "$SCRIPT" "$spec"

  [ "$status" -eq 0 ]
  [[ "$output" != *"Broken pipe"* ]]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["criteria"]["header"] == 5, d
assert d["criteria"]["problem"] == 15, d
assert d["criteria"]["dependencies"] == 5, d
'
}

@test "spec-auditor: detects acceptance criteria" {
  grep -q 'acceptance\|criterio\|AC-' "$SCRIPT"
}

@test "spec-auditor: detects effort estimation" {
  grep -q 'effort\|esfuerzo\|hours\|horas' "$SCRIPT"
}
