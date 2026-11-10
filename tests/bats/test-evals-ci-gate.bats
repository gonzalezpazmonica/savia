#!/usr/bin/env bats
# tests/bats/test-evals-ci-gate.bats — SPEC-151 BATS tests
# Validates runner, workflow, scripts, and datasets existence.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

@test "evals-runner.sh exists and is executable" {
  local runner="$REPO_ROOT/scripts/evals-runner.sh"
  [ -f "$runner" ]
  [ -x "$runner" ]
}

@test "evals-runner.sh --mock produces valid JSON array" {
  local runner="$REPO_ROOT/scripts/evals-runner.sh"
  run bash "$runner" --mock
  [ "$status" -eq 0 ]
  # Validate it's a JSON array
  echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, list), 'Expected JSON array'
assert len(data) > 0, 'Expected non-empty array'
"
  [ "$?" -eq 0 ]
}

@test "evals-ci.yaml workflow exists" {
  local workflow="$REPO_ROOT/.github/workflows/evals-ci.yaml"
  [ -f "$workflow" ]
}

@test "evals-paired-delta.py exists" {
  local script="$REPO_ROOT/scripts/evals-paired-delta.py"
  [ -f "$script" ]
}

@test "tests/evals/datasets directory has jsonl files" {
  local datasets_dir="$REPO_ROOT/tests/evals/datasets"
  [ -d "$datasets_dir" ]
  # At least one .jsonl file must exist
  local count
  count=$(find "$datasets_dir" -name "*.jsonl" | wc -l)
  [ "$count" -ge 1 ]
}

@test "evals-paired-delta.py passes for equal baseline and current" {
  local script="$REPO_ROOT/scripts/evals-paired-delta.py"
  local tmp_scores
  tmp_scores=$(mktemp /tmp/scores-XXXXXX.json)
  echo '[{"id":"t1","score":0.8},{"id":"t2","score":0.9}]' > "$tmp_scores"
  run python3 "$script" --baseline "$tmp_scores" --current "$tmp_scores"
  rm -f "$tmp_scores"
  [ "$status" -eq 0 ]
  # threshold_pass must be true
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['threshold_pass'] is True, f'Expected pass, got {d}'
"
  [ "$?" -eq 0 ]
}

# ── Behaviour of the paired-delta gate and of the runner CLI (S03s) ──
# Ref: SPEC-151; result contract SE-453 (docs/rules/domain/gate-result-contract.md)
DELTA="$REPO_ROOT/scripts/evals-paired-delta.py"
RUNNER="$REPO_ROOT/scripts/evals-runner.sh"

setup() {
  T="$BATS_TEST_TMPDIR"
  unset SAVIA_EVAL_DELTA_THRESHOLD SAVIA_EVAL_EXECUTOR
}

scores() { # scores <file> <json>
  printf '%s\n' "$2" > "$T/$1"
}

field() { # field <python expr over d>: evaluates over the JSON in $output
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$output" "$1"
}

@test "delta: mean degradation beyond the threshold fails with exit 1" {
  scores b.json '[{"id":"t1","score":1.0},{"id":"t2","score":1.0}]'
  scores c.json '[{"id":"t1","score":0.5},{"id":"t2","score":1.0}]'
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
  [ "$status" -eq 1 ]
  [ "$(field 'd["threshold_pass"], d["degradation_count"], d["mean_delta"]')" = "(False, 1, -0.25)" ]
}

@test "delta: degradation exactly at the threshold passes, just beyond fails (boundary)" {
  scores b.json '[{"id":"t1","score":1.0}]'
  scores c.json '[{"id":"t1","score":0.75}]'
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json" --threshold 0.25
  [ "$status" -eq 0 ]
  [ "$(field 'd["threshold_pass"]')" = "True" ]
  scores c.json '[{"id":"t1","score":0.5}]'
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json" --threshold 0.25
  [ "$status" -eq 1 ]
}

@test "delta: --threshold wins over SAVIA_EVAL_DELTA_THRESHOLD, which wins over the 0.05 default" {
  scores b.json '[{"id":"t1","score":1.0}]'
  scores c.json '[{"id":"t1","score":0.75}]'
  SAVIA_EVAL_DELTA_THRESHOLD=0.5 run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
  [ "$status" -eq 0 ]
  [ "$(field 'd["threshold_used"]')" = "0.5" ]
  SAVIA_EVAL_DELTA_THRESHOLD=0.5 run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json" --threshold 0.1
  [ "$status" -eq 1 ]
  [ "$(field 'd["threshold_used"]')" = "0.1" ]
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
  [ "$status" -eq 1 ]
  [ "$(field 'd["threshold_used"]')" = "0.05" ]
}

@test "delta: dict formats are accepted and only ids present in both are paired" {
  scores b.json '{"t1":{"score":0.5},"t2":0.5,"solo-base":0.1}'
  scores c.json '{"t1":0.7,"t2":{"score":0.3},"solo-current":0.9}'
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
  [ "$status" -eq 0 ]
  [ "$(field 'd["pairs_evaluated"], abs(d["mean_delta"]), d["std_delta"], d["improvement_count"], d["degradation_count"]')" = "(2, 0.0, 0.2, 1, 1)" ]
}

@test "delta: no common ids is not a pass (exit 2, fail-closed)" {
  scores b.json '[{"id":"t1","score":0.9}]'
  scores c.json '[{"id":"otro","score":0.1}]'
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"sin IDs comunes"* ]]
}

@test "delta: empty current results are not a pass (exit 2)" {
  scores b.json '[{"id":"t1","score":0.9}]'
  scores c.json '[]'
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
  [ "$status" -eq 2 ]
}

@test "delta: malformed scores file fails with exit 1 and an error, not a traceback" {
  scores b.json '[{"id":"t1","score":0.9}]'
  for bad in 'no json' '[{"id":"t1"}]' '[{"id":"t1","score":"alto"}]' '"string"'; do
    scores c.json "$bad"
    run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"error"'* ]]
    [[ "$output" != *Traceback* ]]
  done
}

@test "delta: missing --current is a usage error" {
  scores b.json '[{"id":"t1","score":0.9}]'
  run python3 "$DELTA" --baseline "$T/b.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--baseline and --current are required"* ]]
}

@test "runner: --mock --output writes a report where every dataset is unknown/not_executed" {
  run bash "$RUNNER" --mock --output "$T/report.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Report written to $T/report.json"* ]]
  run python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert len(r)>=2 and all(x["result"]=="unknown" and x["threshold_pass"] is None and any(g["reason"]=="not_executed" for g in x["gaps"]) for x in r), r' "$T/report.json"
  [ "$status" -eq 0 ]
}

@test "runner: --dataset limits the report to that dataset" {
  run bash "$RUNNER" --mock --dataset pbi-decomposition
  [ "$status" -eq 0 ]
  [ "$(field '",".join(x["dataset"] for x in d)')" = "pbi-decomposition" ]
}

@test "runner: unknown dataset fails with exit 1" {
  run bash "$RUNNER" --mock --dataset no-existe
  [ "$status" -eq 1 ]
  [[ "$output" == *"dataset 'no-existe' not found"* ]]
}

@test "runner: option without a value is a usage error, not an unbound variable" {
  for opt in --dataset --output --threshold; do
    run bash "$RUNNER" --mock "$opt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: $opt needs a value"* ]]
  done
}

@test "runner: unknown option is rejected" {
  run bash "$RUNNER" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "delta: a small drop within the threshold is not a degradation and an unchanged id is not an improvement" {
  scores b.json '[{"id":"t1","score":1.0},{"id":"t2","score":1.0}]'
  scores c.json '[{"id":"t1","score":0.99},{"id":"t2","score":1.0}]'
  run python3 "$DELTA" --baseline "$T/b.json" --current "$T/c.json"
  [ "$status" -eq 0 ]
  [ "$(field 'd["degradation_count"], d["improvement_count"]')" = "(0, 0)" ]
}

@test "runner: live mode without SAVIA_EVAL_EXECUTOR fails closed with exit 2" {
  run bash "$RUNNER" --dataset pbi-decomposition
  [ "$status" -eq 2 ]
  [[ "$output" == *"SAVIA_EVAL_EXECUTOR"* ]]
}
