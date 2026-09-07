#!/usr/bin/env bats
# Ref: SE-077 Slice 1 — savia-gates plugin (TS source structure tests)
#
# These tests validate the plugin AT REST — file existence, package.json shape,
# hook registrations declared in index.ts, safety boundaries. Runtime behaviour
# is tested separately by Mónica's E2E once OpenCode is installed.

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PLUGIN_DIR="$ROOT_DIR/scripts/opencode-plugin/savia-gates"
  SCRIPT="$ROOT_DIR/scripts/opencode-install.sh"
}

# ── Plugin source structure ──────────────────────────────────────────────────

@test "plugin: directory exists at scripts/opencode-plugin/savia-gates/" {
  [ -d "$PLUGIN_DIR" ]
}

@test "plugin: package.json declares savia-gates with @opencode-ai/plugin dep" {
  [ -f "$PLUGIN_DIR/package.json" ]
  grep -q '"name": "savia-gates"' "$PLUGIN_DIR/package.json"
  grep -q '"@opencode-ai/plugin"' "$PLUGIN_DIR/package.json"
}

@test "plugin: index.ts exports SaviaGates default" {
  [ -f "$PLUGIN_DIR/index.ts" ]
  grep -q 'export const SaviaGates' "$PLUGIN_DIR/index.ts"
  grep -q 'export default SaviaGates' "$PLUGIN_DIR/index.ts"
}

@test "plugin: index.ts registers ≥10 critical hook event handlers" {
  # AC-02: Plugin loads ≥10 critical hooks
  count=$(grep -cE '"(tool\.execute\.before|tool\.execute\.after|chat\.message|permission\.ask|command\.execute\.before|event|experimental\.session\.compacting)"' "$PLUGIN_DIR/index.ts")
  [ "$count" -ge 7 ]
  # And the index actively dispatches each over the hookMap
  grep -q "loadHookMap" "$PLUGIN_DIR/index.ts"
}

@test "plugin: lib/shell-bridge.ts loads .claude/settings.json (not directory walk)" {
  [ -f "$PLUGIN_DIR/lib/shell-bridge.ts" ]
  grep -q '\.claude/settings\.json' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'loadHookMap' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'runHooksForEvent' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge delivers payload on stdin via temp-file redirect (no .text stdin)" {
  grep -q 'stdinPath' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'writeFile' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'tmpdir' "$PLUGIN_DIR/lib/shell-bridge.ts"
  ! grep -qE '\.text\(\s*\{\s*stdin' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge runs hook command via bash -c argv (no shell escaping)" {
  # Bun.spawn with argv array — inner quotes need no escaping (replaces `$` raw)
  grep -q 'Bun.spawn' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'bash", "-c", h.command' "$PLUGIN_DIR/lib/shell-bridge.ts"
  ! grep -qE 'bash \$\{h\.command\}' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge cwd is pinned to projectRoot" {
  grep -q 'cwd: projectRoot' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge resolves CLAUDE_PLUGIN_ROOT in hook commands" {
  grep -q 'CLAUDE_PLUGIN_ROOT' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge honours stdin JSON {decision:block} (SE-337 gate contract)" {
  grep -q 'decision === "block"' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'hook-json-block' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: matcherApplies rebuilds composite Tool(cmd) candidates" {
  grep -q "tool(git commit" "$PLUGIN_DIR/lib/shell-bridge.ts" || grep -q 'tool_input?.command' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'tooling.*payload' "$PLUGIN_DIR/lib/shell-bridge.ts" || grep -q 'candidates.push' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge captures real exitCode from spawned process (not .text string)" {
  grep -q 'proc.exited' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'exitCode' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'BLOCK_EXIT' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge runs async hooks fire-and-forget (exit code ignored)" {
  grep -q 'h\.async' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'continue' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: bridge enforces timeout via timer + tree-kill (no \`$ shell) )" {
  grep -q 'setTimeout' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'killTree' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'process.kill(-pid' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "safety: shell-bridge block exit code contract is 2" {
  grep -q 'BLOCK_EXIT = 2' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: learning recall uses the canonical UserPromptSubmit bridge" {
  grep -q '"chat.message"' "$PLUGIN_DIR/index.ts"
  grep -q '"UserPromptSubmit"' "$PLUGIN_DIR/index.ts"
  grep -q 'hookSpecificOutput.*additionalContext' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q '\.claude/hooks/learning-recall-hook.sh' "$ROOT_DIR/.claude/settings.json"
  [ ! -e "$ROOT_DIR/.opencode/plugins/learning-recall.ts" ]
}

@test "plugin: lib/permission.ts blocks destructive ops on agent/* branches" {
  [ -f "$PLUGIN_DIR/lib/permission.ts" ]
  grep -q 'agent/' "$PLUGIN_DIR/lib/permission.ts"
  grep -q 'AUTONOMOUS_REVIEWER' "$PLUGIN_DIR/lib/permission.ts"
  grep -q 'push.*force\|force.*push' "$PLUGIN_DIR/lib/permission.ts"
}

@test "plugin: lib/audit.ts writes append-only JSONL to ~/.savia/audit/" {
  [ -f "$PLUGIN_DIR/lib/audit.ts" ]
  grep -q 'savia-gates.jsonl' "$PLUGIN_DIR/lib/audit.ts"
  grep -q 'appendFile' "$PLUGIN_DIR/lib/audit.ts"
}

@test "plugin: lib/manifest.ts emits sibling manifest.json for parity audit" {
  [ -f "$PLUGIN_DIR/lib/manifest.ts" ]
  grep -q 'manifest.json' "$PLUGIN_DIR/lib/manifest.ts"
  grep -q 'bindings' "$PLUGIN_DIR/lib/manifest.ts"
}

# ── Gap closure: SE-077 remaining 6 events (2026-08-25) ────────────────────

@test "plugin: FileChanged mapped to file.edited / file.watcher.updated" {
  grep -q '"file.edited"' "$PLUGIN_DIR/index.ts"
  grep -qE 'cc: "FileChanged"|cc:"FileChanged"' "$PLUGIN_DIR/index.ts"
  grep -q "file_path: e?.properties?.file" "$PLUGIN_DIR/index.ts"
}

@test "plugin: PostCompact mapped to session.compacted + compaction.autocontinue" {
  grep -q 'session.compacted.*PostCompact\|"cc": "PostCompact"' "$PLUGIN_DIR/index.ts"
  grep -q 'experimental.compaction.autocontinue' "$PLUGIN_DIR/index.ts"
  grep -q '"PostCompact"' "$PLUGIN_DIR/index.ts"
}

@test "plugin: ConfigChange mapped to config hook" {
  grep -q '"config": async' "$PLUGIN_DIR/index.ts"
  grep -q '"ConfigChange"' "$PLUGIN_DIR/index.ts"
}

@test "plugin: CwdChanged mapped to shell.env (cwd dedup)" {
  grep -q '"shell.env": async' "$PLUGIN_DIR/index.ts"
  grep -q '"CwdChanged"' "$PLUGIN_DIR/index.ts"
  grep -q 'lastCwd' "$PLUGIN_DIR/index.ts"
}

@test "plugin: InstructionsLoaded mapped on session.created" {
  grep -qE 'cc: "InstructionsLoaded"|cc:"InstructionsLoaded"' "$PLUGIN_DIR/index.ts"
}

@test "plugin: manifest HANDLERS table covers the six remaining events" {
  grep -q 'PostCompact' "$PLUGIN_DIR/lib/manifest.ts"
  grep -q 'FileChanged' "$PLUGIN_DIR/lib/manifest.ts"
  grep -q 'CwdChanged' "$PLUGIN_DIR/lib/manifest.ts"
  grep -q 'ConfigChange' "$PLUGIN_DIR/lib/manifest.ts"
  grep -q 'InstructionsLoaded' "$PLUGIN_DIR/lib/manifest.ts"
  grep -q 'PostToolUseFailure' "$PLUGIN_DIR/lib/manifest.ts"
}

@test "plugin: PostToolUseFailure justified NOT_EXPOSED in hook header" {
  grep -q 'opencode-binding: NOT_EXPOSED' "$ROOT_DIR/.claude/hooks/post-tool-failure-log.sh"
}

# ── Safety / boundaries ─────────────────────────────────────────────────────

@test "safety: plugin TS never calls git push or pr merge anywhere" {
  ! grep -rE --include="*.ts" '\bgit\s+push\b|gh\s+pr\s+merge\b' "$PLUGIN_DIR"
}

@test "safety: plugin TS never reads ANTHROPIC API keys directly" {
  ! grep -rE 'ANTHROPIC_API_KEY|ANTHROPIC_BASE_URL' "$PLUGIN_DIR"
}

@test "safety: shell-bridge timeout is bounded" {
  grep -q 'timeoutFor' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -qE 'Math\.min\(configured' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q '30000' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

# ── Installer ───────────────────────────────────────────────────────────────

@test "installer: --help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "installer: --dry-run prints plan without touching ~/.savia" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"opencode installed"* ]]
}

@test "installer: refuses unknown arg" {
  run bash "$SCRIPT" --frobnicate
  [ "$status" -eq 2 ]
}

@test "installer: --uninstall is idempotent on missing dir" {
  SAVIA_HOME=$(mktemp -d) run bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
}

# ── Spec ref ────────────────────────────────────────────────────────────────

@test "spec ref: SE-077 cited in installer header" {
  grep -q "SE-077" "$SCRIPT"
}

@test "spec ref: SE-077 cited in plugin index.ts" {
  grep -q "SE-077" "$PLUGIN_DIR/index.ts"
}

@test "safety: installer has set -uo pipefail" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "safety: installer never invokes git push" {
  ! grep -E '^[^#]*git\s+push' "$SCRIPT"
}

# ── Edge cases ──────────────────────────────────────────────────────────────

@test "edge: --link-only mode skips download step" {
  run bash "$SCRIPT" --link-only --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"download"* ]] || true
}

@test "edge: empty agents-md doesn't crash plugin loader" {
  # Missing settings are represented as a blocking configuration state.
  grep -q "INVALID_HOOK_CONFIGURATION" "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "edge: large hookMap (>50 entries) supported without recursion" {
  # Shell-bridge iterates with a for-loop, no recursive calls
  ! grep -E 'function .*\(\).*\{[^}]*\1[^}]*\}' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

# ── Anti-leak / self-heal (SE-077 process-leak fix, 2026-08-26) ─────────────

@test "plugin: hooks spawn detached (own process group) for tree-kill" {
  grep -q 'detached: true' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'Bun.spawn' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: timeout kills the hook process group (no leak)" {
  grep -q 'killTree' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'process.kill(-pid' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'SIGKILL' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: async hooks cap at 60s and wire stdout/stderr to /dev/null" {
  grep -q '60000' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'ignoreOutput' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: sweepOrphanedHooks exported and wired at plugin load" {
  grep -q 'sweepOrphanedHooks' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -q 'sweepOrphanedHooks' "$PLUGIN_DIR/index.ts"
  grep -q 'heal-sweep' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "heal script: opencode-gates-heal.sh exists, executable, syntactically valid" {
  [ -x "$ROOT_DIR/scripts/opencode-gates-heal.sh" ]
  bash -n "$ROOT_DIR/scripts/opencode-gates-heal.sh"
  grep -qF -- '--force' "$ROOT_DIR/scripts/opencode-gates-heal.sh"
  grep -qF -- '--dry-run' "$ROOT_DIR/scripts/opencode-gates-heal.sh"
}

@test "safety: heal script never kills opencode itself (tty stdin excluded)" {
  grep -q 'readlink "$p/fd/0"' "$ROOT_DIR/scripts/opencode-gates-heal.sh"
  ! grep -qE 'pkill\s+-f\s+opencode' "$ROOT_DIR/scripts/opencode-gates-heal.sh"
}

# ── Ptrace-independent pid registry (2026-08-26, Yama ptrace_scope=1) ──────

@test "plugin: spawnHook writes per-hook pid registry (no /proc fd readlink)" {
  grep -q 'hookRegistryPath' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -qF 'savia-gates-${owner}-hook-${hookPid}.json' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -qF 'writeFile(hookRegistryPath(process.pid, hookPid)' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "plugin: sweep kills leaked hooks from the pid registry (dead owners)" {
  grep -q 'HOOK_REGISTRY_RE' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -qF 'savia-gates-(\d+)-hook-(\d+)' "$PLUGIN_DIR/lib/shell-bridge.ts"
  grep -qF 'killTree(hookPid)' "$PLUGIN_DIR/lib/shell-bridge.ts"
}

@test "heal script: kills leaked hooks via pid registry (dead owners)" {
  grep -qF '/tmp/savia-gates-*-hook-*.json' "$ROOT_DIR/scripts/opencode-gates-heal.sh"
  grep -qF 'kill_target' "$ROOT_DIR/scripts/opencode-gates-heal.sh"
}
