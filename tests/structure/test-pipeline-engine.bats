#!/usr/bin/env bats
# Tests for Era 110 — Autonomous Pipeline Engine
# Ref: .claude/templates/pipeline/ci-template.yaml

setup() {
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  ROOT="$PWD"
  TMPDIR_PE=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_PE"
}

@test "pipeline-engine.sh exists and is executable" {
  [ -x "$ROOT/scripts/pipeline-engine.sh" ]
}

@test "pipeline-stage-runner.sh exists and is executable" {
  [ -x "$ROOT/scripts/pipeline-stage-runner.sh" ]
}

@test "CI template exists" {
  [ -f "$ROOT/.claude/templates/pipeline/ci-template.yaml" ]
}

@test "pipeline-local-run command exists" {
  [ -f "$ROOT/.opencode/commands/pipeline-local-run.md" ]
}

@test "pipeline engine dry-run parses template" {
  run bash -c "echo '' | $ROOT/scripts/pipeline-engine.sh $ROOT/.claude/templates/pipeline/ci-template.yaml --dry-run"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dry-run"
  echo "$output" | grep -q "build"
}

@test "stage runner outputs valid JSON result" {
  local tmp; tmp=$(mktemp -d)
  run bash -c "echo '' | $ROOT/scripts/pipeline-stage-runner.sh --name test-stage --command 'echo ok' --output-dir $tmp"
  [ "$status" -eq 0 ]
  [ -f "$tmp/stage-test-stage.json" ]
  python3 -c "import json; json.load(open('$tmp/stage-test-stage.json'))"
  rm -rf "$tmp"
}

@test "stage runner handles failing command" {
  run bash -c "echo '' | $ROOT/scripts/pipeline-stage-runner.sh --name fail-stage --command 'exit 1' --output-dir $TMPDIR_PE"
  [ "$status" -ne 0 ]
  grep -q '"status": "failed"' "$TMPDIR_PE/stage-fail-stage.json"
}

# ── Negative cases ──

@test "pipeline engine fails on missing template" {
  run bash -c "echo '' | $ROOT/scripts/pipeline-engine.sh /nonexistent/template.yaml --dry-run"
  [ "$status" -ne 0 ]
}

@test "pipeline engine handles invalid YAML without crash" {
  echo "{{invalid yaml" > "$TMPDIR_PE/bad.yaml"
  run bash -c "echo '' | $ROOT/scripts/pipeline-engine.sh $TMPDIR_PE/bad.yaml --dry-run 2>&1"
  # Current contract: no stage is parseable, so nothing runs and nothing crashes.
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pipeline: bad.yaml"* ]]
  [[ "$output" == *"All 0 stages passed"* ]]
  [[ "$output" != *"command not found"* ]]
}

@test "stage runner fails without required args" {
  run bash -c "echo '' | $ROOT/scripts/pipeline-stage-runner.sh 2>&1"
  [ "$status" -ne 0 ]
}

# ── Edge cases ──

@test "stage runner JSON result has status field" {
  run bash -c "echo '' | $ROOT/scripts/pipeline-stage-runner.sh --name edge-stage --command 'echo ok' --output-dir $TMPDIR_PE"
  [ "$status" -eq 0 ]
  python3 -c "import json; d=json.load(open('$TMPDIR_PE/stage-edge-stage.json')); assert 'status' in d"
}

@test "CI template has build stage defined" {
  grep -q "build" "$ROOT/.claude/templates/pipeline/ci-template.yaml"
}

@test "pipeline-engine.sh has safety headers" {
  grep -q "set -[euo]" "$ROOT/scripts/pipeline-engine.sh" || grep -q "set -[euo]*o pipefail" "$ROOT/scripts/pipeline-engine.sh"
}

@test "dry-run output contains expected structure" {
  # Ref: docs/rules/domain/parallel-execution.md
  run bash -c "echo '' | $ROOT/scripts/pipeline-engine.sh $ROOT/.claude/templates/pipeline/ci-template.yaml --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"build"* ]]
}

@test "stage runner handles empty command gracefully" {
  run bash -c "echo '' | $ROOT/scripts/pipeline-stage-runner.sh --name empty-cmd --command '' --output-dir $TMPDIR_PE 2>&1"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
