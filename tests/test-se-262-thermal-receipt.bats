#!/usr/bin/env bats
# tests/test-se-262-thermal-receipt.bats — Tests for pr-thermal-receipt.sh (SE-262)
# Cada caso trabaja sobre un repo git temporal (--project), nunca sobre el real.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pr-thermal-receipt.sh"

setup() {
  [[ -x "$SCRIPT" ]] || skip "pr-thermal-receipt.sh missing"
  R="$(mktemp -d)"
  git -C "$R" init -q -b main
  git -C "$R" config user.name "Receipt Tester"
  git -C "$R" config user.email "t@example.invalid"
  mkdir -p "$R/scripts"
  printf 'echo uno\necho dos\n' > "$R/scripts/a.sh"
  printf 'function viejo() {\n}\n' > "$R/old.js"
  git -C "$R" add -A
  git -C "$R" commit -qm base
}

teardown() {
  rm -rf "$R"
}

# segunda confirmación: añade script, borra script, añade/borra funciones
second_commit() {
  printf 'echo uno\necho dos\necho tres\n' > "$R/scripts/a.sh"
  printf 'echo nuevo\n' > "$R/scripts/b.sh"
  printf 'def nueva():\n    pass\nexport function otra() {}\n' > "$R/new.py"
  git -C "$R" rm -q old.js
  git -C "$R" add -A
  git -C "$R" commit -qm second
}

field() { echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['delta']['$1'])"; }

@test "T01: refuses to run outside git repo" {
  d="$(mktemp -d)"
  run bash "$SCRIPT" --staged --project "$d"
  rm -rf "$d"
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "not a git repository" ]]
}

@test "T02: requires --staged or --branch" {
  run bash "$SCRIPT" --project "$R"
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "must specify --staged or --branch" ]]
}

@test "T03: staged mode without changes warns and reports zeros" {
  run bash "$SCRIPT" --staged --project "$R" --format json
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "WARN: no staged changes" ]]
  run bash -c "bash '$SCRIPT' --staged --project '$R' --format json 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(field files_changed)" = "0" ]
  [ "$(field loc_added)" = "0" ]
}

@test "T04: markdown output has receipt marker and sticky comment structure" {
  run bash -c "bash '$SCRIPT' --staged --project '$R' 2>/dev/null"
  [[ "${lines[0]}" == "<!-- codeflow-card:receipt -->" ]]
  [[ "$output" =~ '```text' ]]
  [[ "$output" =~ "thank you for your code" ]]
}

@test "T05: markdown receipt shows header, actor and branch" {
  run bash "$SCRIPT" --staged --project "$R"
  [[ "$output" =~ "--- THERMAL RECEIPT ---" ]]
  [[ "$output" =~ "actor: Receipt Tester" ]]
  [[ "$output" =~ "branch: main" ]]
  [[ "$output" =~ "PR · $(date +%Y-%m-%d)" ]]
}

@test "T06: json format outputs valid JSON with timestamp, actor, branch and delta" {
  run bash "$SCRIPT" --staged --project "$R" --format json
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -v '^WARN' | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['actor'] == 'Receipt Tester' and d['branch'] == 'main'
assert 'T' in d['timestamp']
assert set(d['delta']) >= {'files_changed','files_added','files_deleted','loc_added','loc_removed','functions_added','functions_removed','scripts_added','scripts_removed'}
"
}

@test "T07: staged counts files, LOC, new files and function lines" {
  printf 'echo uno\necho dos\necho tres\n' > "$R/scripts/a.sh"
  printf 'def nueva():\n    pass\n' > "$R/new.py"
  git -C "$R" add -A
  run bash "$SCRIPT" --staged --project "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(field files_changed)" = "2" ]
  [ "$(field files_added)" = "1" ]
  [ "$(field files_deleted)" = "0" ]
  [ "$(field loc_added)" = "3" ]
  [ "$(field loc_removed)" = "0" ]
  [ "$(field functions_added)" = "1" ]
  [ "$(field functions_removed)" = "0" ]
  [ "$(field scripts_added)" = "1" ]
  [ "$(field scripts_removed)" = "0" ]
}

@test "T08: staged counts removals: deleted files, removed LOC, removed functions and scripts" {
  git -C "$R" rm -q old.js scripts/a.sh
  run bash "$SCRIPT" --staged --project "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(field files_changed)" = "2" ]
  [ "$(field files_deleted)" = "2" ]
  [ "$(field files_added)" = "0" ]
  [ "$(field loc_removed)" = "4" ]
  [ "$(field functions_removed)" = "1" ]
  [ "$(field scripts_removed)" = "1" ]
}

@test "T09: branch mode with an invalid ref fails with exit 1 and names the ref" {
  run bash "$SCRIPT" --branch "nonexistent..alsofake" --project "$R"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "invalid refspec: nonexistent..alsofake" ]]
}

@test "T10: branch mode counts the whole range" {
  second_commit
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" --project "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(field files_changed)" = "4" ]
  [ "$(field files_added)" = "2" ]
  [ "$(field files_deleted)" = "1" ]
  [ "$(field loc_added)" = "5" ]
  [ "$(field loc_removed)" = "2" ]
  [ "$(field functions_added)" = "2" ]
  [ "$(field functions_removed)" = "1" ]
}

@test "T11: branch mode counts scripts touched and scripts removed" {
  second_commit
  git -C "$R" rm -q scripts/a.sh
  git -C "$R" commit -qm third
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" --project "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(field scripts_removed)" = "1" ]
  [ "$(field scripts_added)" = "1" ]
}

@test "T12: branch mode with an empty range reports zeros and exits 0" {
  run bash "$SCRIPT" --branch "HEAD..HEAD" --project "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(field files_changed)" = "0" ]
  [ "$(field loc_added)" = "0" ]
}

@test "T13: markdown receipt prints the same numbers as the json" {
  second_commit
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" --project "$R"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "files          4 (+2 new, -1 removed)" ]]
  [[ "$output" =~ "LOC           +5 / -2" ]]
  [[ "$output" =~ "functions      +2 / -1" ]]
  [[ "$output" =~ "scripts        +2 / -0" ]]
}

@test "T14: --health without workspace-health script yields valid JSON with null score" {
  second_commit
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" --project "$R" --format json --health
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)['delta']
assert d['health_after'] == {'score': None, 'grade': '?'}, d
"
}

@test "T15: --health parses score and grade from workspace-health output" {
  second_commit
  mkdir -p "$R/scripts"
  cat > "$R/scripts/workspace-health.sh" <<'EOS'
#!/usr/bin/env bash
echo '{"score": 87, "grade": "B+"}'
EOS
  chmod +x "$R/scripts/workspace-health.sh"
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" --project "$R" --format json --health
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)['delta']
assert d['health_after'] == {'score': 87, 'grade': 'B+'}, d
"
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" --project "$R" --health
  [[ "$output" =~ "health        B+" ]]
}

@test "T16: without --health the receipt has no health line" {
  run bash "$SCRIPT" --branch "HEAD..HEAD" --project "$R"
  [[ "$output" != *"health"* ]]
}

@test "T17: help flag works and exits 0 without needing a repo" {
  run bash "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Usage" ]]
  [[ "$output" =~ "--branch REFSPEC" ]]
}

@test "T18: unknown option exits 1 and prints usage on stderr" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" =~ "unknown option: --bogus" ]]
}

@test "T19: unknown format is rejected" {
  run bash "$SCRIPT" --staged --project "$R" --format xml
  [ "$status" -eq 1 ]
  [[ "$output" =~ "unknown format: xml" ]]
}

@test "T20: options that need a value fail cleanly when it is missing" {
  run bash "$SCRIPT" --branch
  [ "$status" -eq 1 ]
  [[ "$output" =~ "--branch requires a value" ]]
}

@test "T21: default project is the current directory" {
  second_commit
  cd "$R"
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" --format json
  [ "$status" -eq 0 ]
  [ "$(field files_changed)" = "4" ]
}
