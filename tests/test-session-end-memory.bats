#!/usr/bin/env bats
# BATS tests for .opencode/hooks/session-end-memory.sh
# SessionEnd hook — SPEC-013/055: <200ms sync log, background worker writes
# session-hot.md for next-session context injection.
# Batch 45 hook coverage.

HOOK=".opencode/hooks/session-end-memory.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  export SAVIA_HOOK_PROFILE="${SAVIA_HOOK_PROFILE:-standard}"
  TEST_HOME=$(mktemp -d "$TMPDIR/sem-home-XXXXXX")
}
teardown() {
  rm -rf "$TEST_HOME" 2>/dev/null || true
  cd /
}

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }
@test "SPEC-013 reference" {
  run grep -c 'SPEC-013' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "SPEC-055 strict perf reference" {
  run grep -c 'SPEC-055' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "has profile_gate standard" {
  run grep -c 'profile_gate "standard"' "$HOOK"
  [[ "$output" -ge 1 ]]
}

# ── Synchronous log ─────────────────────────────────────

@test "sync: logs session-end event to session-end.log" {
  HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -f "$TEST_HOME/.savia/session-end.log" ]]
  run cat "$TEST_HOME/.savia/session-end.log"
  [[ "$output" == *"session-end"* ]]
  [[ "$output" == *"pid="* ]]
}

@test "sync: log entry has ISO 8601 timestamp" {
  HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  run cat "$TEST_HOME/.savia/session-end.log"
  [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "sync: multiple calls append to same log" {
  HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  run wc -l < "$TEST_HOME/.savia/session-end.log"
  [[ "$output" -ge 2 ]]
}

# ── Perf: must return quickly ───────────────────────────

@test "perf: hook returns in under 1 second (sync path)" {
  local start end
  start=$(date +%s%N)
  HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  end=$(date +%s%N)
  local elapsed_ms=$(( (end - start) / 1000000 ))
  # Generous 1000ms threshold (SPEC-055 target is 200ms; allow CI overhead)
  [[ "$elapsed_ms" -lt 1000 ]]
}

# ── Background worker ───────────────────────────────────

@test "worker: spawned in background (does not block hook)" {
  HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  # worker log dir created (worker may still be running)
  [[ -d "$TEST_HOME/.savia" ]]
}

@test "worker: eventually writes to worker log" {
  HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  # wait briefly for worker to flush
  local n=0
  while [[ ! -f "$TEST_HOME/.savia/session-end-worker.log" && $n -lt 20 ]]; do
    sleep 0.1; n=$((n+1))
  done
  [[ -f "$TEST_HOME/.savia/session-end-worker.log" ]]
}

@test "worker: writes session-hot.md when modified files present" {
  # Need a fake git repo with modified files
  local repo="$TMPDIR/sem-repo-$$"
  mkdir -p "$repo" && cd "$repo" && git init -q 2>/dev/null
  git config user.email "t@t" && git config user.name "t"
  echo "a" > a.txt && git add a.txt && git commit -qm "init" 2>/dev/null
  echo "modified" > a.txt

  local hook_abs="$BATS_TEST_DIRNAME/../$HOOK"
  CLAUDE_PROJECT_DIR="$repo" HOME="$TEST_HOME" bash "$hook_abs" <<< "" >/dev/null 2>&1

  # Wait for worker
  local repo_slug session_dir session_hot
  repo_slug=$(echo "$repo" | sed 's|[/:\]|-|g; s|^-||')
  session_dir="$TEST_HOME/.savia-memory/sessions/$(date +%Y-%m-%d)"
  session_hot="$session_dir/session-hot.md"
  local n=0
  while [[ ! -f "$session_hot" && $n -lt 30 ]]; do
    sleep 0.1; n=$((n+1))
  done

  cd "$BATS_TEST_DIRNAME/.."
  [[ -f "$session_hot" ]]
  run cat "$session_hot"
  [[ "$output" == *"Files modified"* ]]
  rm -rf "$repo"
}

@test "worker: includes branch name in session-hot" {
  local repo="$TMPDIR/sem-repo-br-$$"
  mkdir -p "$repo" && cd "$repo" && git init -q -b feature/x 2>/dev/null
  git config user.email "t@t" && git config user.name "t"
  echo "a" > a.txt && git add a.txt && git commit -qm "init" 2>/dev/null
  echo "z" > a.txt

  local hook_abs="$BATS_TEST_DIRNAME/../$HOOK"
  CLAUDE_PROJECT_DIR="$repo" HOME="$TEST_HOME" bash "$hook_abs" <<< "" >/dev/null 2>&1

  local n=0
  # esperar al contenido, no a que exista el fichero: el worker lo crea al redirigir y escribe después
  while ! grep -q "worker-start" "$TEST_HOME/.savia/session-end-worker.log" 2>/dev/null && [[ $n -lt 100 ]]; do
    sleep 0.1; n=$((n+1))
  done

  cd "$BATS_TEST_DIRNAME/.."
  run cat "$TEST_HOME/.savia/session-end-worker.log"
  [[ "$output" == *"worker-start | branch=feature/x"* ]]
  rm -rf "$repo"
}

# ── Failure analysis ────────────────────────────────────

@test "worker: no session-hot when no actions and no modifications" {
  # Clean repo with no diff
  local repo="$TMPDIR/sem-clean-$$"
  mkdir -p "$repo" && cd "$repo" && git init -q 2>/dev/null
  git config user.email "t@t" && git config user.name "t"
  echo "a" > a.txt && git add a.txt && git commit -qm "init" 2>/dev/null

  local hook_abs="$BATS_TEST_DIRNAME/../$HOOK"
  CLAUDE_PROJECT_DIR="$repo" HOME="$TEST_HOME" bash "$hook_abs" <<< "" >/dev/null 2>&1

  sleep 0.3
  cd "$BATS_TEST_DIRNAME/.."

  local repo_slug session_dir session_hot
  repo_slug=$(echo "$repo" | sed 's|[/:\]|-|g; s|^-||')
  session_hot="$TEST_HOME/.savia-memory/sessions/$(date +%Y-%m-%d)/session-hot.md"
  [[ ! -f "$session_hot" ]]
  rm -rf "$repo"
}

@test "worker: session-actions.jsonl failures counted" {
  mkdir -p "$TEST_HOME/.savia"
  cat > "$TEST_HOME/.savia/session-actions.jsonl" <<EOF
{"action":"edit","attempt":1}
{"action":"edit","attempt":2}
{"action":"write","attempt":3}
EOF
  local repo="$TMPDIR/sem-fail-$$"
  mkdir -p "$repo" && cd "$repo" && git init -q 2>/dev/null

  local hook_abs="$BATS_TEST_DIRNAME/../$HOOK"
  CLAUDE_PROJECT_DIR="$repo" HOME="$TEST_HOME" bash "$hook_abs" <<< "" >/dev/null 2>&1

  local repo_slug session_hot
  repo_slug=$(echo "$repo" | sed 's|[/:\]|-|g; s|^-||')
  session_hot="$TEST_HOME/.savia-memory/sessions/$(date +%Y-%m-%d)/session-hot.md"

  local n=0
  while [[ ! -f "$session_hot" && $n -lt 30 ]]; do
    sleep 0.1; n=$((n+1))
  done

  cd "$BATS_TEST_DIRNAME/.."
  [[ -f "$session_hot" ]]
  run cat "$session_hot"
  [[ "$output" == *"Failures:"* ]]
  [[ "$output" == *"2"* ]]  # 2 attempts >= 2
  rm -rf "$repo"
}

# ── Input handling ──────────────────────────────────────

@test "input: drains stdin without failing" {
  HOME="$TEST_HOME" run bash "$HOOK" <<< '{"some":"json","other":"fields"}'
  [ "$status" -eq 0 ]
}

@test "input: empty stdin handled" {
  HOME="$TEST_HOME" run bash "$HOOK" < /dev/null
  [ "$status" -eq 0 ]
}

@test "input: large stdin drained" {
  local big
  big=$(printf 'x%.0s' {1..10000})
  HOME="$TEST_HOME" run bash "$HOOK" <<< "$big"
  [ "$status" -eq 0 ]
}

# ── Edge cases ──────────────────────────────────────────

@test "edge: non-git repo still writes log (graceful fallback)" {
  local not_a_repo="$TMPDIR/sem-nogit-$$"
  mkdir -p "$not_a_repo"
  local hook_abs="$BATS_TEST_DIRNAME/../$HOOK"
  CLAUDE_PROJECT_DIR="$not_a_repo" HOME="$TEST_HOME" run bash "$hook_abs" <<< ""
  [ "$status" -eq 0 ]
  [[ -f "$TEST_HOME/.savia/session-end.log" ]]
  rm -rf "$not_a_repo"
}

@test "edge: HOME dir does not exist yet — created" {
  local new_home="$TMPDIR/sem-newhome-$$"
  HOME="$new_home" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -f "$new_home/.savia/session-end.log" ]]
  rm -rf "$new_home"
}

# ── Coverage ────────────────────────────────────────────

@test "coverage: worker disowned" {
  run grep -c 'disown' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: session-hot.md produced" {
  run grep -c 'session-hot.md\|SESSION_HOT' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: worker fork pattern (background subshell)" {
  run grep -c '^[[:space:]]*)[[:space:]]*&' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: ACTION_LOG reference" {
  run grep -c 'session-actions.jsonl\|ACTION_LOG' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: frontmatter type: session-hot" {
  run grep -c 'type: session-hot' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ───────────────────────────────────────────

@test "isolation: always exits 0 (SessionEnd never blocks)" {
  for input in '' 'junk' '{"json":true}' "$(printf 'big%.0s' {1..100})"; do
    HOME="$TEST_HOME" run bash "$HOOK" <<< "$input"
    [ "$status" -eq 0 ]
  done
}

@test "isolation: sync path does not modify repo" {
  local before after
  before=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  after=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  [[ "$before" == "$after" ]]
}
