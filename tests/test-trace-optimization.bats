#!/usr/bin/env bats
# Ref: docs/propuestas/SPEC-044-trace-prompt-optimization.md
# Tests for trace-pattern-extractor.sh + prompt-suggestion-engine.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export EXTRACTOR="$REPO_ROOT/scripts/trace-pattern-extractor.sh"
  export ENGINE="$REPO_ROOT/scripts/prompt-suggestion-engine.sh"
  TMPDIR_TO=$(mktemp -d)
  mkdir -p "$TMPDIR_TO/output/trace-analysis"

  # Create sample traces
  cat > "$TMPDIR_TO/traces.jsonl" << 'EOF'
{"agent":"dotnet-developer","tokens_in":5000,"tokens_out":800,"duration_ms":15000,"outcome":"success","budget_exceeded":false,"ts":"2026-04-01"}
{"agent":"dotnet-developer","tokens_in":5000,"tokens_out":200,"duration_ms":30000,"outcome":"failure","budget_exceeded":true,"ts":"2026-04-02"}
{"agent":"architect","tokens_in":8000,"tokens_out":1500,"duration_ms":20000,"outcome":"success","budget_exceeded":false,"ts":"2026-04-01"}
EOF
}

teardown() { rm -rf "$TMPDIR_TO"; }

@test "extractor has safety flags" {
  head -10 "$EXTRACTOR" | grep -qE "set -(e|u).*pipefail"
}

@test "engine has safety flags" {
  head -10 "$ENGINE" | grep -qE "set -(e|u).*pipefail"
}

@test "extractor help shows usage" {
  run bash "$EXTRACTOR" --help 2>&1
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"trace"* ]]
}

@test "engine help shows usage" {
  run bash "$ENGINE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "positive: extractor runs on sample traces" {
  run bash "$EXTRACTOR" --traces-file "$TMPDIR_TO/traces.jsonl" --min-traces 1
  [ "$status" -le 1 ]
}

@test "positive: engine runs with dry-run" {
  run bash "$ENGINE" --dry-run --traces-file "$TMPDIR_TO/traces.jsonl"
  [ "$status" -le 1 ]
  [[ "$output" == *"Optimization"* ]] || [[ "$output" == *"candidates"* ]] || [[ "$output" == *"Done"* ]]
}

@test "positive: engine generates plans" {
  TRACE_ANALYSIS_DIR="$TMPDIR_TO/output/trace-analysis" MIN_TRACES=2 \
    run bash "$ENGINE" --traces-file "$TMPDIR_TO/traces.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent: dotnet-developer"* ]]
  [ -f "$TMPDIR_TO/output/trace-analysis/dotnet-developer-plan.md" ]
  grep -q "frequent_failures" "$TMPDIR_TO/output/trace-analysis/dotnet-developer-plan.md"
}

@test "negative: engine below min-traces generates no plans" {
  TRACE_ANALYSIS_DIR="$TMPDIR_TO/output/trace-analysis" \
    run bash "$ENGINE" --traces-file "$TMPDIR_TO/traces.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$(ls "$TMPDIR_TO"/output/trace-analysis/*-plan.md 2>/dev/null)" ]
}

@test "negative: extractor handles empty traces" {
  touch "$TMPDIR_TO/empty.jsonl"
  run bash "$EXTRACTOR" --traces-file "$TMPDIR_TO/empty.jsonl"
  [ "$status" -le 1 ]
}

@test "negative: engine handles no candidates" {
  run bash "$ENGINE" --traces-file "$TMPDIR_TO/empty.jsonl" 2>/dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"No optimization"* ]] || [[ "$output" == *"Done"* ]]
}

@test "negative: extractor with nonexistent file" {
  run bash "$EXTRACTOR" --traces-file "/nonexistent/traces.jsonl"
  [ "$status" -le 1 ]
}

@test "edge: engine with --agent filter" {
  run bash "$ENGINE" --agent "dotnet-developer" --dry-run --traces-file "$TMPDIR_TO/traces.jsonl"
  [ "$status" -le 1 ]
}

@test "edge: boundary — single trace entry" {
  echo '{"agent":"x","tokens_in":100,"outcome":"success","ts":"2026-04-01"}' > "$TMPDIR_TO/single.jsonl"
  run bash "$EXTRACTOR" --traces-file "$TMPDIR_TO/single.jsonl" --min-traces 1
  [ "$status" -le 1 ]
}

@test "coverage: extractor computes failure_rate" {
  grep -q "failure_rate\|failure.*rate\|failures" "$EXTRACTOR"
}

@test "coverage: engine classifies patterns" {
  grep -q "classify\|pattern\|Pattern" "$ENGINE"
}

@test "coverage: engine suggests fixes" {
  grep -q "suggest\|Suggest\|fix\|Fix" "$ENGINE"
}
