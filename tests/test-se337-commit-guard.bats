#!/usr/bin/env bats
# SE-337 — guard de commit en ramas humanas (main/master)
# Ref: docs/specs/SE-337-commit-guard-main.spec.md (AC-01..AC-05)

HOOK=".claude/hooks/block-commit-to-main.sh"
LOG="output/turn-sdlc/commit-guard.jsonl"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
  export SAVIA_TURN_SDLC_LOG_DIR="$FIXDIR"   # log temporal de test
  # repo temp con rama main
  git -C "$FIXDIR" init -q -b main
  git -C "$FIXDIR" config user.email t@t
  git -C "$FIXDIR" config user.name t
  git -C "$FIXDIR" commit --allow-empty -q -m init
}

teardown() {
  rm -rf "$FIXDIR"
  unset SAVIA_TURN_SDLC_LOG_DIR
}

@test "AC-01: en rama main, git commit → JSON block" {
  cd "$FIXDIR" || return 1
  run bash "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/$HOOK"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"decision": "block"'
  echo "$output" | grep -qi "main"
}

@test "AC-02: en rama agent/foo, git commit → pass sin JSON" {
  cd "$FIXDIR" || return 1
  git checkout -q -b agent/foo 2>/dev/null
  run bash "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/$HOOK"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "AC-03: SAVIA_ALLOW_MAIN_COMMIT=1 en main → permite (sin JSON)" {
  cd "$FIXDIR" || return 1
  run env SAVIA_ALLOW_MAIN_COMMIT=1 bash "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/$HOOK"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "AC-04: bloqueo y bypass registrados en commit-guard.jsonl" {
  cd "$FIXDIR" || return 1
  local h=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/$HOOK
  bash "$h" >/dev/null 2>&1
  SAVIA_ALLOW_MAIN_COMMIT=1 bash "$h" >/dev/null 2>&1
  [[ -f "$FIXDIR/commit-guard.jsonl" ]]
  grep -q "verdict\":\"block\"" "$FIXDIR/commit-guard.jsonl"
  grep -q "verdict\":\"bypass\"" "$FIXDIR/commit-guard.jsonl"
}

@test "AC-05a: hashes CRITERIO/CONSTITUCION invariantes tras bloqueos" {
  local h1 h2
  h1=$(sha256sum CRITERIO.md | cut -d' ' -f1)
  h2=$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)
  cd "$FIXDIR" || return 1
  bash "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/$HOOK" >/dev/null 2>&1
  # verificación real desde la raíz del repo
  cd "$(dirname "$BATS_TEST_FILENAME")/.."
  [[ "$(sha256sum CRITERIO.md | cut -d' ' -f1)" == "$h1" ]]
  [[ "$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)" == "$h2" ]]
}

@test "AC-05b: bash -n, sin vendor names, PURE_BASH" {
  local h=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/$HOOK
  bash -n "$h"
  grep -q 'set -uo pipefail' "$h"
  run grep -niE "openai|anthropic|gpt-|gemini|qwen|deepseek" "$h"
  [[ "$status" -ne 0 ]]
}

@test "regression: broad Bash registration allows reads and worktree creation on main" {
  local h="$PWD/$HOOK" command payload
  cd "$FIXDIR" || return 1
  for command in 'pwd' 'cat CLAUDE.md' 'git status --short --branch' \
    'git fetch origin' 'git worktree add -b agent/fix /tmp/worktree main' \
    'git merge --no-commit --no-ff origin/main' 'git log --format=%h'; do
    payload=$(jq -nc --arg command "$command" '{tool_input:{command:$command}}')
    run bash "$h" <<< "$payload"
    [[ "$status" -eq 0 && -z "$output" ]]
  done
  [[ ! -e "$FIXDIR/commit-guard.jsonl" ]]
}

@test "regression: actual command payloads still block commits on main and master" {
  local h="$PWD/$HOOK" branch command payload
  cd "$FIXDIR" || return 1
  for branch in main master; do
    git branch -m "$branch"
    for command in 'git commit -m test' 'git -c user.name=test commit --amend' \
      'git -C . commit -m test' 'pwd && git commit -m test' \
      '/usr/bin/git commit -m test' $'git status\ngit commit -m test'; do
      payload=$(jq -nc --arg command "$command" '{tool_input:{command:$command}}')
      run bash "$h" <<< "$payload"
      [[ "$status" -eq 0 ]]
      [[ "$(jq -r .decision <<< "$output")" == block ]]
    done
  done
}

@test "regression: cmd payload supports reads and still blocks commits" {
  local h="$PWD/$HOOK"
  cd "$FIXDIR" || return 1
  run bash "$h" <<< '{"tool_input":{"cmd":"git status"}}'
  [[ "$status" -eq 0 && -z "$output" ]]
  run bash "$h" <<< '{"tool_input":{"cmd":"git commit -m test"}}'
  [[ "$status" -eq 0 ]]
  [[ "$(jq -r .decision <<< "$output")" == block ]]
}

@test "regression: malformed, null and empty command payloads remain conservative" {
  local h="$PWD/$HOOK" payload
  cd "$FIXDIR" || return 1
  for payload in '{' '{}' '{"tool_input":{"command":null}}' \
    '{"tool_input":{"command":42}}' '{"tool_input":{"command":""}}'; do
    run bash "$h" <<< "$payload"
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r .decision <<< "$output")" == block ]]
  done
}

@test "regression: commit payload is allowed on an agent branch" {
  local h="$PWD/$HOOK"
  cd "$FIXDIR" || return 1
  git checkout -q -b agent/regression
  run bash "$h" <<< '{"tool_input":{"command":"git commit -m test"}}'
  [[ "$status" -eq 0 && -z "$output" ]]
}

@test "regression: workdir selects the repository whose command will run" {
  local h="$PWD/$HOOK" payload
  git -C "$FIXDIR" worktree add -q -b agent/workdir "$FIXDIR/agent"
  cd "$FIXDIR" || return 1
  payload=$(jq -nc --arg dir "$FIXDIR/agent" \
    '{cwd:env.PWD,tool_input:{command:"git commit -m test",workdir:$dir}}')
  run bash "$h" <<< "$payload"
  [[ "$status" -eq 0 && -z "$output" ]]
  cd "$FIXDIR/agent" || return 1
  payload=$(jq -nc --arg dir "$FIXDIR" \
    '{tool_input:{command:"git commit -m test",workdir:$dir}}')
  run bash "$h" <<< "$payload"
  [[ "$status" -eq 0 ]]
  [[ "$(jq -r .decision <<< "$output")" == block ]]
}

@test "regression: explicit guarded cd selects an isolated worktree" {
  local h="$PWD/$HOOK" payload command
  git -C "$FIXDIR" worktree add -q -b agent/explicit "$FIXDIR/agent"
  cd "$FIXDIR" || return 1
  command="cd \"$FIXDIR/agent\" && git commit -m test"
  payload=$(jq -nc --arg command "$command" '{tool_input:{command:$command}}')
  run bash "$h" <<< "$payload"
  [[ "$status" -eq 0 && -z "$output" ]]
  cd "$FIXDIR/agent" || return 1
  command="cd \"$FIXDIR\" && git commit -m test"
  payload=$(jq -nc --arg command "$command" '{tool_input:{command:$command}}')
  run bash "$h" <<< "$payload"
  [[ "$status" -eq 0 ]]
  [[ "$(jq -r .decision <<< "$output")" == block ]]
}

@test "edge: empty workdir falls back to the current directory" {
  local h="$PWD/$HOOK"
  cd "$FIXDIR" || return 1
  run bash "$h" <<< '{"tool_input":{"command":"git commit -m test","workdir":""}}'
  [[ "$status" -eq 0 ]]
  [[ "$(jq -r .decision <<< "$output")" == block ]]
}

@test "edge: guarded cd to a nonexistent directory cannot reach the commit" {
  local h="$PWD/$HOOK" payload
  cd "$FIXDIR" || return 1
  # cd falla antes de git commit, así que no hay commit que bloquear.
  payload=$(jq -nc '{tool_input:{command:"cd \"/nonexistent-se337\" && git commit -m test"}}')
  run bash "$h" <<< "$payload"
  [[ "$status" -eq 0 && -z "$output" ]]
  run bash -c 'cd "/nonexistent-se337" 2>/dev/null && echo reached'
  [[ "$output" != *reached* ]]
}

@test "RN-01: detached HEAD / no repo → pass (sin rama humana)" {
  run bash "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/$HOOK"
  [[ "$status" -eq 0 ]]
  # en el workspace principal (rama actual) no bloquea si no es main
  local br
  br=$(git branch --show-current 2>/dev/null || echo "")
  if [[ "$br" != main && "$br" != master ]]; then
    [[ -z "$output" ]]
  fi
}
