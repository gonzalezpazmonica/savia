# Fixture común de SE-508 (guard de efectos MCP/WebFetch/WebSearch) para los bats del hook y de paridad.
#
# Monta un árbol de trabajo ($WS, repositorio git) con catálogo, lista de hosts y copia del núcleo, y un
# remoto bare ($BARE) cuyo `main` tiene los mismos ficheros. El núcleo lee el remoto por la URL inyectada
# con SAVIA_MCP_GUARD_TEST=1 (solo vale con BATS_TEST_FILENAME, que bats exporta).
#
# SE508_HOOK y SE508_CORE_SRC permiten ejecutar la suite contra otro hook o un mutante del núcleo (AC-10).

SE508_CATALOG='mcp__claude_ai_Gmail__send_message: write
mcp__claude_ai_Gmail__get_message: read_only
mcp__github__merge_pull_request: merge
mcp__github__create_pull_request: write
mcp__savia-vaults__vault_read: read_only'
SE508_HOSTS='docs.ejemplo.org'

se508_git() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=t -c user.email=t@t.test "$@"; }

# se508_publish DIR CATALOG HOSTS CORE_FILE → crea DIR.git (bare) con esos ficheros en main
se508_publish() {
  local src="$1.src" catalog="$2" hosts="$3" core="$4"
  se508_git init -q -b main "$src"
  mkdir -p "$src/config" "$src/.claude/hooks/lib"
  printf '%s\n' "$catalog" > "$src/config/mcp-effect-catalog.yaml"
  printf '%s\n' "$hosts" > "$src/config/webfetch-allow-hosts"
  [[ -n "$core" ]] && cp "$core" "$src/.claude/hooks/lib/mcp_effect_guard.py"
  se508_git -C "$src" add -A
  se508_git -C "$src" commit -q -m fixture
  se508_git clone -q --bare "$src" "$1.git"
  se508_git -C "$1.git" config uploadpack.allowFilter true
  se508_git -C "$1.git" config uploadpack.allowAnySHA1InWant true
}

se508_setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="${SE508_HOOK:-$REPO_ROOT/.claude/hooks/mcp-effect-guard.sh}"
  CORE_SRC="${SE508_CORE_SRC:-$REPO_ROOT/.claude/hooks/lib/mcp_effect_guard.py}"
  unset SAVIA_GATES_PIN SAVIA_MCP_GUARD SAVIA_RUN_ID SAVIA_AUTONOMOUS_RUN SAVIA_HOOK_PROFILE
  TMPD="$(cd "$(mktemp -d)" && pwd -P)"
  WS="$TMPD/ws"
  se508_git init -q -b main "$WS"
  mkdir -p "$WS/config" "$WS/.claude/hooks/lib"
  printf '%s\n' "$SE508_CATALOG" > "$WS/config/mcp-effect-catalog.yaml"
  printf '%s\n' "$SE508_HOSTS" > "$WS/config/webfetch-allow-hosts"
  cp "$CORE_SRC" "$WS/.claude/hooks/lib/mcp_effect_guard.py"
  se508_publish "$TMPD/remote" "$SE508_CATALOG" "$SE508_HOSTS" "$CORE_SRC"
  BARE="$TMPD/remote.git"
  export SAVIA_MCP_GUARD_TEST=1 SAVIA_MCP_GUARD_TEST_REMOTE="file://$BARE" SAVIA_MCP_GUARD_TEST_TODAY=2026-11-10
  export SAVIA_MCP_GUARD_TEST_LOG="$TMPD/decisions.jsonl" CLAUDE_PROJECT_DIR="$WS"
}

se508_teardown() {
  [[ -n "${TMPD:-}" && -d "$TMPD" ]] && find "$TMPD" -mindepth 1 -delete 2>/dev/null
  [[ -n "${TMPD:-}" ]] && rmdir "$TMPD" 2>/dev/null
  return 0
}

# se508_payload TOOL [TOOL_INPUT_JSON]
se508_payload() {
  local input="${2:-}"
  [[ -n "$input" ]] || input='{}'
  printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$input"
}

# hook_decision PAYLOAD → imprime ask|deny|pass (pass = salida vacía y exit 0); exit 1 si el hook falla
hook_decision() {
  local out rc
  out=$(printf '%s' "$1" | bash "$HOOK"); rc=$?
  [[ $rc -eq 0 ]] || { echo "hook-exit-$rc"; return 1; }
  if [[ -z "$out" ]]; then echo pass; return 0; fi
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'
}

hook_reason() { printf '%s' "$1" | bash "$HOOK" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
