#!/usr/bin/env bats
# BATS tests for .opencode/hooks/block-branch-switch-dirty.sh
# PreToolUse on Bash — intercepts git checkout/switch with uncommitted changes.
# Tier: security (minimal profile — always active).
# Ref: batch 48 hook coverage — SPEC-safety branch switch data loss prevention

HOOK=".opencode/hooks/block-branch-switch-dirty.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  export SAVIA_HOOK_PROFILE="${SAVIA_HOOK_PROFILE:-standard}"
  TEST_REPO=$(mktemp -d "$TMPDIR/bbsd-XXXXXX")
  HOOK_ABS="$(pwd)/$HOOK"
}
teardown() {
  rm -rf "$TEST_REPO" 2>/dev/null || true
  cd /
}

setup_clean_repo() {
  cd "$TEST_REPO"
  git init -q -b main 2>/dev/null || git init -q
  git config user.email "t@t" && git config user.name "t"
  echo "a" > a.txt
  git add a.txt && git commit -qm "init"
  # Create feature branch but stay on the initial branch
  local initial
  initial=$(git branch --show-current)
  git branch feature
  # ensure we're on initial branch (main or master)
  git checkout -q "$initial"
}

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }
@test "security tier correctly declared" {
  # After SE-071 fix: hook uses profile_gate "security" (valid tier).
  # Active in all profiles: minimal/standard/strict/ci.
  run grep -c 'profile_gate "security"' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "SE-071 regression: no invalid tier 'minimal' remains" {
  # Regression test — ensures bug SE-071 doesn't silently reappear.
  # "minimal" is a PROFILE value, not a TIER (tiers: security/standard/strict).
  # If this test fails, the safety hook is silent-disabled under default profile.
  run grep -c 'profile_gate "minimal"' "$HOOK"
  [[ "$output" -eq 0 ]]
}

# ── Pass-through ────────────────────────────────────────

@test "pass-through: empty stdin exits 0" {
  run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "pass-through: non-git command exits 0" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"ls -la"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "pass-through: git status not affected" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "pass-through: git log not affected" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git log --oneline -5"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "pass-through: git commit not affected" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git commit -m test"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Clean tree → allow ──────────────────────────────────

@test "clean: git checkout with clean tree exits 0" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "clean: git switch with clean tree exits 0" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git switch feature"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "clean: git checkout -b new-branch with clean tree exits 0" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout -b new-branch"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

# ── File restore exempt ─────────────────────────────────

@test "exempt: git checkout -- file.txt allowed with dirty tree" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout -- a.txt"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "exempt: git checkout -- . allowed with dirty tree" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout -- ."}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "exempt: git checkout --merge -- <ficheros> is a restore, allowed with dirty tree" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout --merge -- a.txt"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "exempt: git checkout <tree-ish> -- <ruta> restores, allowed with dirty tree" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout HEAD -- a.txt"}}'
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: git checkout --merge <rama> (no paths) still blocks with dirty tree" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout --merge feature"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO"* ]]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: git checkout <rama> -- without paths still blocks with dirty tree" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature --"}}'
  [ "$status" -eq 2 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: a restore earlier in the command does not excuse a later branch switch" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout -- b.txt; git checkout feature"}}'
  [ "$status" -eq 2 ]
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Dirty tree → block ──────────────────────────────────

@test "block: git checkout with modified file exits 2" {
  setup_clean_repo
  echo "modified content" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [ "$status" -eq 2 ]
  [[ "${output}${stderr:-}" == *"BLOQUEADO"* ]]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: git switch with modified file exits 2" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git switch feature"}}'
  [ "$status" -eq 2 ]
  [[ "${output}${stderr:-}" == *"BLOQUEADO"* ]]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: git checkout with untracked files exits 2" {
  setup_clean_repo
  echo "new file" > newfile.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [ "$status" -eq 2 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: git checkout -b with dirty tree exits 2" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout -b new-feature"}}'
  [ "$status" -eq 2 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: warning message includes git stash suggestion" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [[ "${output}${stderr:-}" == *"git stash"* ]]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: warning mentions git add + commit option" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [[ "${output}${stderr:-}" == *"git add"* ]]
  [[ "${output}${stderr:-}" == *"git commit"* ]]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "block: lists count of modified and untracked files" {
  setup_clean_repo
  echo "mod" > a.txt
  echo "new" > b.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [[ "${output}${stderr:-}" == *"modificados"* ]]
  [[ "${output}${stderr:-}" == *"rastrear"* ]]
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Command extraction ─────────────────────────────────

@test "extract: python3 json parse used" {
  run grep -c 'python3 -c' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "extract: no command in JSON exits 0" {
  run bash "$HOOK" <<< '{"other":"field"}'
  [ "$status" -eq 0 ]
}

# ── Negative cases ─────────────────────────────────────

# Revisión #1483: entrada inesperada → fail-closed (antes salía 0 sin mirar).
@test "negative: malformed JSON blocks (fail-closed)" {
  run bash "$HOOK" <<< "not valid JSON"
  [ "$status" -eq 2 ]
  [[ "$output" == *"entrada de hook inválida"* ]]
}

@test "negative: a non-string command is unexpected input and blocks" {
  run bash "$HOOK" <<< '{"tool_input":{"command":["git","checkout","feature"]}}'
  [ "$status" -eq 2 ]
}

@test "negative: command 'git-checkout' with dash not matched" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git-checkout feature"}}'
  # Pattern requires space: "git checkout" not "git-checkout"
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "negative: git checkout as substring of longer word not matched" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"echo git checkouter"}}'
  # Pattern requires "git checkout" followed by space — "checkouter" matches with \s optional? Actually regex \s requires space after.
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Target resolution edge cases (follow-up to PR #1066) ──────────
# (a) unexpandable cd target ($VAR) must fall back to the session cwd, never pass through;
# (b) only the -C of the checkout/switch invocation counts, not a foreign `git -C X status`;
# (c) `git -C dir checkout -- file` is a restore and is exempt;
# (d) the last cd before the git invocation wins; (e) no stray "0" line in the block message.

@test "resolution: cd \$UNSET && git switch — session cwd dirty → exits 2 (no pass-through)" {
  setup_clean_repo
  echo "dirty A" > a.txt
  run bash "$HOOK_ABS" <<< "{\"cwd\":\"$TEST_REPO\",\"tool_input\":{\"command\":\"cd \$B && git switch feature\"}}"
  [ "$status" -eq 2 ]
  cd "$BATS_TEST_DIRNAME/.."
}

# Revisión #1483: un destino que no se puede resolver bloquea aunque el cwd de
# la sesión esté limpio (fail-closed, misma decisión que el guard TS).
@test "resolution: cd \$UNSET && git switch — session cwd clean → exits 2 (uncertain target)" {
  setup_clean_repo
  run bash "$HOOK_ABS" <<< "{\"cwd\":\"$TEST_REPO\",\"tool_input\":{\"command\":\"cd \$B && git switch feature\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"destino de cambio de rama desconocido"* ]]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "resolution: cd to non-existent dir && git switch — session cwd dirty → exits 2" {
  setup_clean_repo
  echo "dirty A" > a.txt
  run bash "$HOOK_ABS" <<< "{\"cwd\":\"$TEST_REPO\",\"tool_input\":{\"command\":\"cd /nonexistent/dir/xyz && git switch feature\"}}"
  [ "$status" -eq 2 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "resolution: foreign git -C A status before cd B && git switch — A dirty, B clean → exits 0" {
  setup_clean_repo
  echo "dirty A" > a.txt
  setup_second_repo
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"echo \$(git -C $TEST_REPO status --short); cd $OTHER_REPO && git switch feature\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "resolution: cd B && git switch; git -C A status after — A dirty, B clean → exits 0" {
  setup_clean_repo
  echo "dirty A" > a.txt
  setup_second_repo
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $OTHER_REPO && git switch feature && git -C $TEST_REPO status\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "resolution: git -C B checkout -- file is a restore → exits 0 even with B dirty" {
  setup_clean_repo
  setup_second_repo
  echo "dirty B" > "$OTHER_REPO/b.txt"
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"git -C $OTHER_REPO checkout -- b.txt\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "resolution: cd A && cd B && git switch — last cd wins (A dirty, B clean) → exits 0" {
  setup_clean_repo
  echo "dirty A" > a.txt
  setup_second_repo
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $TEST_REPO && cd $OTHER_REPO && git switch feature\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "resolution: cd A && cd B && git switch — last cd wins (A clean, B dirty) → exits 2" {
  setup_clean_repo
  setup_second_repo
  echo "dirty B" > "$OTHER_REPO/b.txt"
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $TEST_REPO && cd $OTHER_REPO && git switch feature\"}}"
  [ "$status" -eq 2 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "resolution: block message has no stray '0' line (grep -c double count)" {
  setup_clean_repo
  echo "modified" > a.txt
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [ "$status" -eq 2 ]
  # `! cmd` is exempt from errexit — count explicitly so the assertion really fails
  [ "$(echo "${output}${stderr:-}" | grep -cx '0')" -eq 0 ]
  echo "${output}${stderr:-}" | grep -q "Ficheros modificados: 1"
  echo "${output}${stderr:-}" | grep -q "Ficheros sin rastrear: 0"
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Target repo resolution (bug: hook cwd != command cwd) ──────────
# The hook runs with cwd = workspace (repo A). When the command targets another
# repo (cd B && git switch / git -C B switch / session cwd = B), the dirty check
# MUST run against B, not A.
# NOTE: assertions use [ ] / grep (not [[ ]]) so they also fail under bash 3.2 (macOS).

setup_second_repo() {
  OTHER_REPO=$(mktemp -d "$TMPDIR/bbsd-other-XXXXXX")
  ( cd "$OTHER_REPO" && git init -q -b main 2>/dev/null || git init -q
    git config user.email "t@t" && git config user.name "t"
    echo "b" > b.txt && git add b.txt && git commit -qm "init" && git branch feature )
}

@test "target: cd B && git switch — A dirty, B clean → exits 0" {
  setup_clean_repo
  echo "dirty A" > a.txt
  setup_second_repo
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $OTHER_REPO && git switch -c nueva\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: cd B && git switch — A clean, B dirty → exits 2" {
  setup_clean_repo
  setup_second_repo
  echo "dirty B" > "$OTHER_REPO/b.txt"
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $OTHER_REPO && git switch feature\"}}"
  [ "$status" -eq 2 ]
  echo "${output}${stderr:-}" | grep -q "BLOQUEADO"
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: git -C B switch — A dirty, B clean → exits 0" {
  setup_clean_repo
  echo "dirty A" > a.txt
  setup_second_repo
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"git -C $OTHER_REPO switch feature\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: git -C B switch — B dirty → exits 2 (git -C is intercepted)" {
  setup_clean_repo
  setup_second_repo
  echo "dirty B" > "$OTHER_REPO/b.txt"
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"git -C $OTHER_REPO switch feature\"}}"
  [ "$status" -eq 2 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: session cwd = B (hook JSON cwd) — A dirty, B clean → exits 0" {
  setup_clean_repo
  echo "dirty A" > a.txt
  setup_second_repo
  run bash "$HOOK_ABS" <<< "{\"cwd\":\"$OTHER_REPO\",\"tool_input\":{\"command\":\"git switch feature\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: session cwd = B dirty → exits 2 even if hook cwd A is clean" {
  setup_clean_repo
  setup_second_repo
  echo "dirty B" > "$OTHER_REPO/b.txt"
  run bash "$HOOK_ABS" <<< "{\"cwd\":\"$OTHER_REPO\",\"tool_input\":{\"command\":\"git switch feature\"}}"
  [ "$status" -eq 2 ]
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: cd to non-git dir && git switch → exits 0 (nothing to protect)" {
  setup_clean_repo
  echo "dirty A" > a.txt
  NOGIT=$(mktemp -d "$TMPDIR/bbsd-nogit-XXXXXX")
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $NOGIT && git switch feature\"}}"
  [ "$status" -eq 0 ]
  rm -rf "$NOGIT"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: block message names the repo that is dirty" {
  setup_clean_repo
  setup_second_repo
  echo "dirty B" > "$OTHER_REPO/b.txt"
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $OTHER_REPO && git switch feature\"}}"
  [ "$status" -eq 2 ]
  echo "${output}${stderr:-}" | grep -q "Repo:"
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

@test "target: SE-300 .pr-summary.md NOT deleted when switching in another repo" {
  setup_clean_repo
  setup_second_repo
  # workspace = dir containing the hook's ../.. (the test checkout)
  WS="$(cd "$(dirname "$HOOK_ABS")/../.." && pwd -P)"
  local had=0; [[ -f "$WS/.pr-summary.md" ]] && had=1
  [[ $had -eq 0 ]] && echo "sentinel" > "$WS/.pr-summary.md"
  run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"cd $OTHER_REPO && git switch feature\"}}"
  [ "$status" -eq 0 ]
  [ -f "$WS/.pr-summary.md" ]
  [[ $had -eq 0 ]] && rm -f "$WS/.pr-summary.md"
  rm -rf "$OTHER_REPO"
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Edge cases ─────────────────────────────────────────

@test "regresión: redirecciones y comentarios tras -- no son rutas de checkout" {
  setup_clean_repo
  echo dirty > a.txt
  for cmd in 'git checkout feature -- >/dev/null' 'git checkout feature -- 2>&1' 'git checkout feature -- # comentario'; do
    payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$cmd" "$TEST_REPO")
    run bash "$HOOK_ABS" <<< "$payload"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOQUEADO"* ]]
  done
  cd "$BATS_TEST_DIRNAME/.."
}

@test "regresión: restaurar en una línea no oculta el cambio de rama de la siguiente" {
  setup_clean_repo
  echo dirty > a.txt
  for cmd in $'git checkout -- a.txt\ngit checkout feature' $'git checkout feature\ngrep -- x f'; do
    payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$cmd" "$TEST_REPO")
    run bash "$HOOK_ABS" <<< "$payload"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOQUEADO"* ]]
  done
  cd "$BATS_TEST_DIRNAME/.."
}

@test "regresión: -- seguido solo de expansiones (\$X, \$(…)) no es restauración" {
  # Revisión de seguridad #1483 P1-1: si se expanden a nada, bash ejecuta
  # `git checkout feature --`, que cambia de rama con el árbol sucio.
  setup_clean_repo
  echo dirty > a.txt
  for cmd in 'git checkout feature -- $FILES' 'git checkout feature -- $(true)'; do
    payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$cmd" "$TEST_REPO")
    run bash "$HOOK_ABS" <<< "$payload"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOQUEADO"* ]]
  done
  # con una ruta conocida junto a la expansión sigue siendo restauración
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' 'git checkout feature -- a.txt $FILES' "$TEST_REPO")
  run bash "$HOOK_ABS" <<< "$payload"
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "edge: very large dirty tree (>20 files) listed truncated" {
  setup_clean_repo
  for i in $(seq 1 30); do echo "new" > "file-$i.txt"; done
  run bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}'
  [ "$status" -eq 2 ]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "edge: empty command field exits 0" {
  run bash "$HOOK" <<< '{"tool_input":{"command":""}}'
  [ "$status" -eq 0 ]
}

@test "edge: null command field exits 0" {
  run bash "$HOOK" <<< '{"tool_input":{"command":null}}'
  [ "$status" -eq 0 ]
}

# ── Coverage ───────────────────────────────────────────

@test "coverage: timeout guard on cat" {
  run grep -c 'timeout.*cat\|timeout 3' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: Spanish warning messages" {
  run grep -c 'BLOQUEADO.*rama\|modificados\|rastrear' "$HOOK"
  [[ "$output" -ge 2 ]]
}

@test "coverage: escape for file-restore pattern" {
  run grep -c 'git checkout.*--' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ──────────────────────────────────────────

@test "isolation: exit codes limited to {0, 2}" {
  setup_clean_repo
  for cmd in "ls" "git status" "git checkout feature"; do
    run bash "$HOOK_ABS" <<< "{\"tool_input\":{\"command\":\"$cmd\"}}"
    [[ "$status" -eq 0 || "$status" -eq 2 ]]
  done
  cd "$BATS_TEST_DIRNAME/.."
}

@test "isolation: hook does not modify repo files" {
  setup_clean_repo
  echo "modified" > a.txt
  local before_hash after_hash
  before_hash=$(sha256sum a.txt | cut -d' ' -f1)
  # Hook exits 2 when blocking — capture exit code but still verify no modification
  bash "$HOOK_ABS" <<< '{"tool_input":{"command":"git checkout feature"}}' >/dev/null 2>&1 || true
  after_hash=$(sha256sum a.txt | cut -d' ' -f1)
  [[ "$before_hash" == "$after_hash" ]]
  cd "$BATS_TEST_DIRNAME/.."
}
