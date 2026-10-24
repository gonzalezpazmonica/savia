#!/usr/bin/env bats
# test-sealed-contracts.bats — SPEC-188 Fase 2 validation
# Verifica la estructura y coherencia del sistema de contract tests

ALLOWLIST=".claude/contracts/allowlist.txt"
CONTRACTS_DIR="tests/contracts"
HOOK=".opencode/hooks/contract-test-guard.sh"

setup() {
  export CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

# --- Estructura del sistema ---

@test "allowlist exists and is non-empty" {
  [[ -s "$ALLOWLIST" ]]
}

@test "allowlist has at least 5 sealed paths" {
  count=$(grep -v '^#' "$ALLOWLIST" | grep -v '^$' | wc -l)
  [[ "$count" -ge 5 ]]
}

@test "contracts/ directory exists" {
  [[ -d "$CONTRACTS_DIR" ]]
}

@test "contracts/README.md exists" {
  [[ -f "$CONTRACTS_DIR/README.md" ]]
}

@test "contract-test-guard hook exists and is executable" {
  [[ -x "$HOOK" ]]
}

@test "sealed-contract-tests.md doc exists" {
  [[ -f "docs/rules/domain/sealed-contract-tests.md" ]]
}

# --- Coherencia allowlist <-> contracts/ ---

@test "each allowlist path exists on disk" {
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "#"* ]] && continue
    [[ -f "$line" ]] || { echo "MISSING: $line"; false; }
  done < "$ALLOWLIST"
}

@test "each allowlist path has a symlink in contracts/" {
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "#"* ]] && continue
    fname=$(basename "$line")
    [[ -e "$CONTRACTS_DIR/$fname" ]] || { echo "NO SYMLINK: $fname in $CONTRACTS_DIR"; false; }
  done < "$ALLOWLIST"
}

@test "all symlinks in contracts/ resolve to existing files" {
  for link in "$CONTRACTS_DIR"/*.bats; do
    [[ -e "$link" ]] || { echo "BROKEN SYMLINK: $link"; false; }
  done
}

# --- Tests sellados pasan ---

@test "sealed test: block-force-push passes" {
  bats "$CONTRACTS_DIR/test-block-force-push.bats" >/dev/null 2>&1
}

@test "sealed test: confidentiality-sign passes" {
  bats "$CONTRACTS_DIR/test-confidentiality-sign.bats" >/dev/null 2>&1
}

@test "sealed test: hook-pii-gate passes" {
  bats "$CONTRACTS_DIR/test-hook-pii-gate.bats" >/dev/null 2>&1
}

@test "sealed test: permissions-wildcard-audit passes" {
  ( cd "$CLAUDE_PROJECT_DIR" && bats "tests/test-permissions-wildcard-audit.bats" ) >/dev/null 2>&1
}

@test "sealed test: validate-agent-permissions passes" {
  ( cd "$CLAUDE_PROJECT_DIR" && bats "tests/test-validate-agent-permissions.bats" ) >/dev/null 2>&1
}

# --- Guard hook funciona sobre contracts/ ---

@test "guard blocks edit to allowlisted path from agent branch" {
  local path
  path=$(grep -v '^#' "$ALLOWLIST" | grep -v '^$' | head -1)
  export _SAVIA_INTERNAL_TEST_BRANCH="agent/test-branch"
  export SAVIA_TEST_MODE=1
  run bash -c "printf '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"%s\"}}' '$path' | bash '$HOOK'"
  unset _SAVIA_INTERNAL_TEST_BRANCH SAVIA_TEST_MODE
  [[ "$status" -eq 2 ]]
}

@test "guard allows edit from main branch" {
  local path
  path=$(grep -v '^#' "$ALLOWLIST" | grep -v '^$' | head -1)
  export _SAVIA_INTERNAL_TEST_BRANCH="main"
  export SAVIA_TEST_MODE=1
  run bash -c "printf '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"%s\"}}' '$path' | bash '$HOOK'"
  unset _SAVIA_INTERNAL_TEST_BRANCH SAVIA_TEST_MODE
  [[ "$status" -eq 0 ]]
}

@test "guard allows non-contract path from agent branch" {
  export _SAVIA_INTERNAL_TEST_BRANCH="agent/test-branch"
  export SAVIA_TEST_MODE=1
  run bash -c "printf '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"docs/README.md\"}}' | bash '$HOOK'"
  unset _SAVIA_INTERNAL_TEST_BRANCH SAVIA_TEST_MODE
  [[ "$status" -eq 0 ]]
}

# --- Doc quality ---

@test "sealed-contract-tests.md mentions allowlist" {
  grep -q "allowlist" docs/rules/domain/sealed-contract-tests.md
}

@test "sealed-contract-tests.md mentions contract-test-guard" {
  grep -q "contract-test-guard" docs/rules/domain/sealed-contract-tests.md
}

@test "sealed-contract-tests.md mentions bypass keyword" {
  grep -q "contract-change\|contract-add\|contract-remove" docs/rules/domain/sealed-contract-tests.md
}

# --- Comportamiento del guard con allowlist y repo aislados ---

guard_env() {
  GREPO="$BATS_TEST_TMPDIR/grepo"
  mkdir -p "$GREPO"
  git init -q -b main "$GREPO"
  git -C "$GREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  printf '# sellados\n\ntests/hooks/test-sealed.bats\nscripts/core.sh\n' > "$BATS_TEST_TMPDIR/allow.txt"
  export CLAUDE_PROJECT_DIR="$GREPO" SAVIA_CONTRACT_ALLOWLIST="$BATS_TEST_TMPDIR/allow.txt"
  export SAVIA_TEST_MODE=1 _SAVIA_INTERNAL_TEST_BRANCH="${1:-agent/x}"
}
call() {  # $1 = tool, $2 = ruta
  run bash -c 'jq -n --arg t "$1" --arg p "$2" "{tool_name:\$t,tool_input:{file_path:\$p}}" | bash "$0"' "$HOOK" "$1" "$2"
}
commit_msg() { git -C "$GREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$1"; }

@test "guard: Edit de ruta sellada desde agent/* sale 2 y nombra la ruta" {
  guard_env
  call Edit tests/hooks/test-sealed.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED [contract-test-guard]: tests/hooks/test-sealed.bats is a SEALED"* ]]
}

@test "guard: Write tambien se bloquea; Read y Bash no" {
  guard_env
  call Write scripts/core.sh
  [ "$status" -eq 2 ]
  call Read scripts/core.sh
  [ "$status" -eq 0 ]
  call Bash scripts/core.sh
  [ "$status" -eq 0 ]
}

@test "guard: ruta absoluta dentro del repo se normaliza y se bloquea" {
  guard_env
  call Edit "$GREPO/scripts/core.sh"
  [ "$status" -eq 2 ]
}

@test "guard: coincidencia por sufijo de directorio, no por subcadena" {
  guard_env
  call Edit worktree/scripts/core.sh
  [ "$status" -eq 2 ]
  call Edit scripts/core.sh.bak
  [ "$status" -eq 0 ]
  call Edit scripts/xcore.sh
  [ "$status" -eq 0 ]
}

@test "guard: la linea comentada de la allowlist no sella nada" {
  guard_env
  printf '#scripts/free.sh\nscripts/other.sh\n' > "$SAVIA_CONTRACT_ALLOWLIST"
  call Edit scripts/free.sh
  [ "$status" -eq 0 ]
  call Edit scripts/other.sh
  [ "$status" -eq 2 ]
}

@test "guard: ramas no agent/* (main, feature/agent/x) pasan" {
  guard_env main
  call Edit scripts/core.sh
  [ "$status" -eq 0 ]
  export _SAVIA_INTERNAL_TEST_BRANCH="feature/agent/x"
  call Edit scripts/core.sh
  [ "$status" -eq 0 ]
}

@test "guard: commit [contract-change] en HEAD permite la edicion" {
  guard_env
  commit_msg "[contract-change] actualizar sellado"
  call Edit scripts/core.sh
  [ "$status" -eq 0 ]
}

@test "guard: marcas [contract-add] y [contract-remove] tambien permiten; otra marca no" {
  guard_env
  commit_msg "[contract-add] x"
  call Edit scripts/core.sh; [ "$status" -eq 0 ]
  commit_msg "[contract-remove] x"
  call Edit scripts/core.sh; [ "$status" -eq 0 ]
  commit_msg "[contract-nope] x"
  call Edit scripts/core.sh; [ "$status" -eq 2 ]
}

@test "guard: allowlist vacia o inexistente deja pasar todo" {
  guard_env
  : > "$SAVIA_CONTRACT_ALLOWLIST"
  call Edit scripts/core.sh
  [ "$status" -eq 0 ]
  export SAVIA_CONTRACT_ALLOWLIST="$BATS_TEST_TMPDIR/no-existe.txt"
  call Edit scripts/core.sh
  [ "$status" -eq 0 ]
}

@test "guard: entrada vacia, sin file_path o JSON sin tool_name pasan" {
  guard_env
  run bash -c 'printf "" | bash "$0"' "$HOOK"
  [ "$status" -eq 0 ]
  run bash -c 'echo "{\"tool_name\":\"Edit\",\"tool_input\":{}}" | bash "$0"' "$HOOK"
  [ "$status" -eq 0 ]
  run bash -c 'echo "{}" | bash "$0"' "$HOOK"
  [ "$status" -eq 0 ]
}

@test "guard: --self-test pasa con sus tres casos" {
  run bash "$HOOK" --self-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-test OK"* ]]
}

@test "guard: sin modo test usa la rama real de git (humana pasa, agent/* bloquea)" {
  guard_env
  run env -u BATS_TEST_FILENAME -u CI -u SAVIA_TEST_MODE bash -c 'git -C "$CLAUDE_PROJECT_DIR" branch -f feature/humana main; git -C "$CLAUDE_PROJECT_DIR" symbolic-ref HEAD refs/heads/feature/humana; jq -n "{tool_name:\"Edit\",tool_input:{file_path:\"scripts/core.sh\"}}" | bash "$0"' "$HOOK"
  [ "$status" -eq 0 ]
  run env -u BATS_TEST_FILENAME -u CI -u SAVIA_TEST_MODE bash -c 'git -C "$CLAUDE_PROJECT_DIR" branch -f agent/real main; git -C "$CLAUDE_PROJECT_DIR" symbolic-ref HEAD refs/heads/agent/real; jq -n "{tool_name:\"Edit\",tool_input:{file_path:\"scripts/core.sh\"}}" | bash "$0"' "$HOOK"
  [ "$status" -eq 2 ]
}
