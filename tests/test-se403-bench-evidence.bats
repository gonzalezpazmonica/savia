#!/usr/bin/env bats
# Ref: docs/specs/SE-403-benchmark-evidence-frontier.spec.md (AC1-AC7)
# Repo, dataset, resultados y frontera temporales: nunca toca ~/.savia ni el repo real.

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  RUNNER="$BATS_TEST_DIRNAME/self-evolution/run-benchmark.sh"
  export SAVIA_BENCH_ROOT="$TMPDIR/repo" SAVIA_BENCH_DIR="$TMPDIR/bench"
  export SAVIA_BENCH_DATASET="$TMPDIR/dataset" SAVIA_BENCH_RESULTS="$TMPDIR/results"
  export SAVIA_BENCH_VERIF_FILE="$TMPDIR/verif.txt"
  mkdir -p "$SAVIA_BENCH_ROOT" "$SAVIA_BENCH_DATASET"
  git -C "$SAVIA_BENCH_ROOT" init -q -b main
  git -C "$SAVIA_BENCH_ROOT" config user.email t@t; git -C "$SAVIA_BENCH_ROOT" config user.name t
  echo x > "$SAVIA_BENCH_ROOT/f"; git -C "$SAVIA_BENCH_ROOT" add -A; git -C "$SAVIA_BENCH_ROOT" commit -qm init
  printf 'id: task-a\n' > "$SAVIA_BENCH_DATASET/task-a.yaml"
  printf 'id: task-b\n' > "$SAVIA_BENCH_DATASET/task-b.yaml"
  printf 'task-a|echo alpha-out; echo alpha-err >&2; true\ntask-b|echo beta-out; false\n' > "$SAVIA_BENCH_VERIF_FILE"
}

teardown() { cd /; }

latest_run() { ls -1t "$SAVIA_BENCH_DIR/runs" | head -1; }

@test "safety: runner declares set -uo pipefail" {
  head -6 "$RUNNER" | grep -q 'set -uo pipefail'
}

@test "AC1: same dataset and commands give the same selection_hash" {
  bash "$RUNNER" --execute >/dev/null
  h1=$(jq -r .selection_hash "$SAVIA_BENCH_DIR/runs/$(latest_run)/manifest.json")
  sleep 1
  bash "$RUNNER" --execute >/dev/null
  h2=$(jq -r .selection_hash "$SAVIA_BENCH_DIR/runs/$(latest_run)/manifest.json")
  [ "$h1" = "$h2" ]
  [ "${#h1}" -eq 64 ]
}

@test "AC1: changing a command or a task YAML changes the selection_hash" {
  bash "$RUNNER" --execute >/dev/null
  h1=$(jq -r .selection_hash "$SAVIA_BENCH_DIR/runs/$(latest_run)/manifest.json")
  printf 'id: task-a\nchanged: yes\n' > "$SAVIA_BENCH_DATASET/task-a.yaml"
  sleep 1
  bash "$RUNNER" --execute >/dev/null
  h2=$(jq -r .selection_hash "$SAVIA_BENCH_DIR/runs/$(latest_run)/manifest.json")
  [ "$h1" != "$h2" ]
}

@test "AC2: each run archives stdout/stderr per task and a provenance manifest" {
  bash "$RUNNER" --execute >/dev/null
  d="$SAVIA_BENCH_DIR/runs/$(latest_run)"
  grep -q alpha-out "$d/task-a.stdout"
  grep -q alpha-err "$d/task-a.stderr"
  [ "$(jq -r .status "$d/task-b.json")" = "CHECK_FAIL" ]
  run jq -r '[(.harness_commit|length), .dirty, .runner_version] | @tsv' "$d/manifest.json"
  [ "$output" = "$(printf '40\tfalse\t2')" ]
}

@test "AC3: --compare reports INCOMPARABLE when the selection differs" {
  bash "$RUNNER" --execute >/dev/null
  printf 'task-a|true\ntask-c|true\n' > "$SAVIA_BENCH_VERIF_FILE"
  echo dirt > "$SAVIA_BENCH_ROOT/wip"
  sleep 1
  bash "$RUNNER" --execute >/dev/null
  run bash "$RUNNER" --compare
  [ "$status" -eq 0 ]
  [[ "$output" == *"INCOMPARABLE"* ]]
}

@test "AC3: --compare against the frontier of the same selection reports a verdict" {
  bash "$RUNNER" --execute >/dev/null
  echo dirt > "$SAVIA_BENCH_ROOT/wip"
  sleep 1
  bash "$RUNNER" --execute >/dev/null
  run bash "$RUNNER" --compare
  [[ "$output" == EQUAL* ]]
}

@test "AC4: frontier updates only on improvement and never from a dirty tree" {
  bash "$RUNNER" --execute >/dev/null
  first=$(jq -r '.[] .run_id' "$SAVIA_BENCH_DIR/frontier.json")
  echo dirt > "$SAVIA_BENCH_ROOT/untracked-change"
  printf 'task-a|true\ntask-b|true\n' > "$SAVIA_BENCH_VERIF_FILE"
  sleep 1
  bash "$RUNNER" --execute >/dev/null
  [ "$(jq -r '.[] .run_id' "$SAVIA_BENCH_DIR/frontier.json" | grep -c .)" -eq 1 ]
  [ "$(jq -r "to_entries[] | select(.value.run_id==\"$first\") | .key" "$SAVIA_BENCH_DIR/frontier.json" | grep -c .)" -eq 1 ]
}

@test "AC4: a clean improving run replaces the frontier entry for its selection" {
  printf 'task-a|true\ntask-b|false\n' > "$SAVIA_BENCH_VERIF_FILE"
  bash "$RUNNER" --execute >/dev/null
  sel=$(jq -r 'keys[0]' "$SAVIA_BENCH_DIR/frontier.json")
  [ "$(jq -r ".\"$sel\".pass" "$SAVIA_BENCH_DIR/frontier.json")" -eq 1 ]
}

@test "AC4: concurrent runs do not corrupt the frontier" {
  bash "$RUNNER" --execute >/dev/null & bash "$RUNNER" --execute >/dev/null & wait
  jq -e . "$SAVIA_BENCH_DIR/frontier.json" >/dev/null
}

@test "AC5: results/aggregate.json keeps its format" {
  bash "$RUNNER" --execute >/dev/null
  run jq -r 'keys | join(",")' "$SAVIA_BENCH_RESULTS/aggregate.json"
  [ "$output" = "aggregate,tasks,total" ]
}

@test "AC6: nothing is written to the benchmarked repo" {
  bash "$RUNNER" --execute >/dev/null
  [ -z "$(git -C "$SAVIA_BENCH_ROOT" status --porcelain)" ]
}

@test "empty: --compare without any run exits 1 with a message" {
  run bash "$RUNNER" --compare
  [ "$status" -eq 1 ]
  [[ "$output" == *"no runs"* ]]
}

@test "missing: nonexistent verif file exits 2" {
  export SAVIA_BENCH_VERIF_FILE="$TMPDIR/nope.txt"
  run bash "$RUNNER" --execute
  [ "$status" -eq 2 ]
}

@test "boundary: a clean run with zero passing tasks is archived and seeds the frontier" {
  printf 'task-a|false\ntask-b|false\n' > "$SAVIA_BENCH_VERIF_FILE"
  bash "$RUNNER" --execute >/dev/null
  [ "$(jq -r '.[] .pass' "$SAVIA_BENCH_DIR/frontier.json")" -eq 0 ]
  [ "$(jq -r .pass "$SAVIA_BENCH_DIR/runs/$(latest_run)/manifest.json")" -eq 0 ]
}

@test "nonexistent: --compare with an unknown run_id exits 1" {
  bash "$RUNNER" --execute >/dev/null
  run bash "$RUNNER" --compare 19990101T000000Z-deadbeef
  [ "$status" -eq 1 ]
  [[ "$output" == *"run not found"* ]]
}

@test "regression: rewriting the tracked results/ dir does not make the next run dirty" {
  export SAVIA_BENCH_RESULTS="$SAVIA_BENCH_ROOT/results"
  bash "$RUNNER" --execute >/dev/null
  git -C "$SAVIA_BENCH_ROOT" add -A; git -C "$SAVIA_BENCH_ROOT" commit -qm results
  sleep 1
  bash "$RUNNER" --execute >/dev/null   # reescribe results/ (duraciones distintas)
  [ -n "$(git -C "$SAVIA_BENCH_ROOT" status --porcelain)" ]
  sleep 1
  bash "$RUNNER" --execute >/dev/null
  [ "$(jq -r .dirty "$SAVIA_BENCH_DIR/runs/$(latest_run)/manifest.json")" = "false" ]
}

@test "regression: a real change outside results/ still marks the run dirty" {
  export SAVIA_BENCH_RESULTS="$SAVIA_BENCH_ROOT/results"
  echo y >> "$SAVIA_BENCH_ROOT/f"
  bash "$RUNNER" --execute >/dev/null
  [ "$(jq -r .dirty "$SAVIA_BENCH_DIR/runs/$(latest_run)/manifest.json")" = "true" ]
}
