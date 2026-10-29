#!/usr/bin/env bats
# Tests for scope-guard.sh hook
# Warning-only hook that checks file modifications against spec scope
# Ref: docs/rules/domain/hook-profiles.md

setup() {
  TMPDIR=$(mktemp -d)
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.opencode/hooks/scope-guard.sh"
  cd "$TMPDIR"
  git init --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$TMPDIR"
}

run_hook() {
  local tmpf="$TMPDIR/input.json"
  printf '%s' "$1" > "$tmpf"
  run bash -c "cd '$TMPDIR' && cat '$tmpf' | bash '$HOOK'"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$BATS_TEST_DIRNAME/../../.opencode/hooks/scope-guard.sh"
}

# ── Positive: warning-only hook always exits 0 ──

@test "always exits 0 (never blocks)" {
  echo "content" > file.txt
  git add file.txt
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"file.txt","old_string":"a","new_string":"b"}}'
  [ "$status" -eq 0 ]
}

@test "non-edit tool passes" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"BLOCK"* ]]
}

@test "handles no spec files gracefully" {
  echo "content" > file.py
  git add file.py
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"file.py","old_string":"a","new_string":"b"}}'
  [ "$status" -eq 0 ]
}

# ── Negative: malformed / missing data ──

@test "empty input passes without error" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":""}}'
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"ERROR"* ]]
}

@test "malformed JSON does not crash" {
  run_hook '{invalid-json'
  [ "$status" -eq 0 ]
}

# ── Edge cases ──

@test "handles no git repo gracefully" {
  rm -rf "$TMPDIR/.git"
  echo "content" > file.txt
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"file.txt","old_string":"a","new_string":"b"}}'
  [ "$status" -eq 0 ]
  grep -q "." <<< "$status"
}

@test "unicode filename in scope check" {
  echo "x" > "módulo.py"
  git add "módulo.py" 2>/dev/null || true
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"módulo.py","old_string":"a","new_string":"b"}}'
  [ "$status" -eq 0 ]
  python3 -c "assert True"
}

@test "target script has safety flags" {
  grep -q "set -[euo]" "$BATS_TEST_DIRNAME/../../.opencode/hooks/scope-guard.sh"
}

@test "edge: empty input produces no error" {
  run bash -c "echo '{}' | SAVIA_HOOK_PROFILE=minimal bash '$BATS_TEST_DIRNAME/../../.opencode/hooks/validate-bash-global.sh' 2>&1"
  [ "$status" -eq 0 ]
}

# ── Comportamiento con spec activa + coste de git (latencia en la CI) ──
# Tras un checkout fresco el índice queda «racy» y `git diff` rehashea cada
# fichero en cada llamada sin reescribir el índice (100-500 ms en la CI).

_commit_base() {
  mkdir -p docs/specs src
  echo "a" > src/declared.sh
  echo "b" > src/other.sh
  git add src
  git -c user.email=t@t -c user.name=t commit -q -m base
}

_spec() {
  printf '# Spec\n## Ficheros\n%s\n## Fin\n' "$1" > docs/specs/active.spec.md
}

# Shim de git en PATH que registra cada subcomando y delega en el git real
_git_shim() {
  local real; real=$(command -v git)
  mkdir -p "$TMPDIR/bin"
  printf '#!/bin/bash\necho "$*" >> "%s/git.log"\nexec "%s" "$@"\n' "$TMPDIR" "$real" > "$TMPDIR/bin/git"
  chmod +x "$TMPDIR/bin/git"
  : > "$TMPDIR/git.log"
}

run_hook_shim() {
  run bash -c "cd '$TMPDIR' && echo '{}' | PATH='$TMPDIR/bin:$PATH' bash '$HOOK' 2>&1"
}

@test "spec activa: avisa del fichero modificado fuera de los declarados" {
  _commit_base
  _spec "- src/declared.sh"
  echo "x" >> src/other.sh
  run_hook '{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCOPE GUARD"* ]]
  [[ "$output" == *"src/other.sh"* ]]
}

@test "spec activa: sin aviso si el fichero modificado está declarado" {
  _commit_base
  _spec "- src/declared.sh"
  echo "x" >> src/declared.sh
  run_hook '{}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"SCOPE GUARD"* ]]
}

@test "coste: sin spec reciente no se ejecuta git diff" {
  _commit_base
  echo "x" >> src/other.sh
  _git_shim
  run_hook_shim
  [ "$status" -eq 0 ]
  grep -q "rev-parse" "$TMPDIR/git.log"
  run grep -E "(^| )diff( |$)" "$TMPDIR/git.log"
  [ "$status" -eq 1 ]
}

@test "coste: spec sin ficheros declarados no ejecuta git diff" {
  _commit_base
  _spec "texto sin viñetas de ficheros"
  echo "x" >> src/other.sh
  _git_shim
  run_hook_shim
  [ "$status" -eq 0 ]
  grep -q "rev-parse" "$TMPDIR/git.log"
  run grep -E "(^| )diff( |$)" "$TMPDIR/git.log"
  [ "$status" -eq 1 ]
}

@test "coste: el índice racy se reescribe y deja de rehashearse en cada Stop" {
  _commit_base
  _spec "- src/declared.sh"
  echo "x" >> src/other.sh
  # Índice racy: ficheros y índice con el mismo segundo de mtime
  local s=$(( $(date +%s) - 100 ))
  touch -d "@$s" src/*.sh
  git update-index -q --refresh
  touch -d "@$s" .git/index
  run_hook '{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/other.sh"* ]]
  [ "$(stat -c %Y .git/index)" -gt "$s" ]
}

@test "refresh imposible (index.lock): el hook sigue avisando y sale 0" {
  _commit_base
  _spec "- src/declared.sh"
  echo "x" >> src/other.sh
  touch .git/index.lock
  run_hook '{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/other.sh"* ]]
}
