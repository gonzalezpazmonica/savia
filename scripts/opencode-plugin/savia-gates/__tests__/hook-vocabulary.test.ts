import { afterEach, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { SaviaGates } from "../index"
import { applyPatchOperations, fromHookInput, hookViews } from "../lib/hook-vocabulary"

// SE-392 S3: the hooks are written for Claude Code (`Edit`, `file_path`). OpenCode passes `edit` and
// `filePath`, and `apply_patch` with every file in one body. Without the translation a guard written the
// Claude Code way let the OpenCode call through. The parity of the patch parser with the Codex core
// (scripts/dual-cli/gates.py) is checked from Python: tests/dual-cli/test_edit_replay.py.

const roots: string[] = []
const savedEnv = { ...process.env }

afterEach(async () => {
  process.env = { ...savedEnv }
  await Promise.all(roots.splice(0).map((r) => rm(r, { recursive: true, force: true })))
})

// Written the Claude Code way: exact tool name and `.tool_input.file_path`, like tdd-gate.sh.
const CLAUDE_STYLE_GUARD = `#!/usr/bin/env bash
in=$(cat)
tool=$(printf '%s' "$in" | jq -r '.tool_name // empty')
path=$(printf '%s' "$in" | jq -r '.tool_input.file_path // empty')
if [ "$tool" = "Edit" ] || [ "$tool" = "Write" ]; then
  case "$path" in *prohibido*) echo "RUTA PROHIBIDA $tool $path" >&2; exit 2;; esac
fi
exit 0
`
const PATH_REWRITE_GUARD = `#!/usr/bin/env bash
in=$(cat)
printf '%s' "$in" | jq -c '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input + {file_path:"/tmp/seguro.txt"})}}'
`

async function gatesWith(guard: string, matcher = "Edit|Write", extra: Record<string, unknown>[] = []) {
  const root = await mkdtemp(join(tmpdir(), "savia-vocab-test-"))
  roots.push(root)
  await mkdir(join(root, ".claude/hooks"), { recursive: true })
  await writeFile(join(root, ".claude/hooks/guard.sh"), guard, { mode: 0o755 })
  const hooks = { PreToolUse: [{ matcher, hooks: [{ type: "command", command: `"$CLAUDE_PROJECT_DIR"/.claude/hooks/guard.sh` }, ...extra] }] }
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({ hooks }))
  process.env.SAVIA_AUDIT_DIR = join(root, ".audit-test")
  process.env.SAVIA_PLUGIN_DIR = join(root, ".manifest-test")
  delete process.env.SAVIA_GATES_PIN
  delete process.env.SAVIA_DOME_GUARD
  const plugin: any = await SaviaGates({ directory: root, worktree: root } as any)
  const before = async (tool: string, args: Record<string, unknown>) => {
    const output = { args }
    try {
      await plugin["tool.execute.before"]({ tool, sessionID: "s", callID: "c" }, output)
      return { verdict: "PASS", args: output.args }
    } catch (e) {
      return { verdict: String(e), args: output.args }
    }
  }
  return { root, before }
}

test("OpenCode edit/write reach a guard written for Claude Code names and keys", async () => {
  const { root, before } = await gatesWith(CLAUDE_STYLE_GUARD)
  expect((await before("write", { filePath: join(root, "prohibido.txt"), content: "x" })).verdict).toContain("RUTA PROHIBIDA Write")
  expect((await before("edit", { filePath: join(root, "prohibido.txt"), oldString: "a", newString: "b" })).verdict).toContain("RUTA PROHIBIDA Edit")
  expect((await before("write", { filePath: join(root, "libre.txt"), content: "x" })).verdict).toBe("PASS")
})

test("apply_patch is gated file by file: one forbidden file blocks the whole patch", async () => {
  const { before } = await gatesWith(CLAUDE_STYLE_GUARD)
  const patch = "*** Begin Patch\n*** Add File: libre.txt\n+a\n*** Update File: prohibido.py\n@@\n-x\n+y\n*** End Patch\n"
  expect((await before("apply_patch", { patchText: patch })).verdict).toContain("RUTA PROHIBIDA Edit")
  const moved = "*** Begin Patch\n*** Update File: libre.txt\n*** Move to: prohibido.txt\n@@\n-x\n+y\n*** End Patch\n"
  expect((await before("apply_patch", { patchText: moved })).verdict).toContain("RUTA PROHIBIDA Write")
  expect((await before("apply_patch", { patchText: "*** Begin Patch\n*** Add File: libre.txt\n+a\n*** End Patch\n" })).verdict).toBe("PASS")
})

test("a patch that cannot be parsed blocks instead of matching no hook", async () => {
  const { before } = await gatesWith(CLAUDE_STYLE_GUARD)
  expect((await before("apply_patch", { patchText: "*** Begin Patch\n*** Frobnicate File: a\n*** End Patch\n" })).verdict).toContain("INVALID_EVENT")
  expect((await before("apply_patch", { patchText: 42 })).verdict).toContain("INVALID_EVENT")
})

test("a guard rewrite in Claude Code keys is carried back to the OpenCode key", async () => {
  const { root, before } = await gatesWith(PATH_REWRITE_GUARD)
  const r = await before("write", { filePath: join(root, "a.txt"), content: "x" })
  expect(r.verdict).toBe("PASS")
  expect(r.args).toEqual({ filePath: "/tmp/seguro.txt", content: "x" })
})

test("a rewrite of one file of a patch cannot be applied, so the patch is blocked", async () => {
  const { before } = await gatesWith(PATH_REWRITE_GUARD)
  const r = await before("apply_patch", { patchText: "*** Begin Patch\n*** Add File: a.txt\n+a\n*** End Patch\n" })
  expect(r.verdict).toContain("UPDATED_INPUT_UNSUPPORTED")
})

test("hookViews keeps the OpenCode keys and adds the Claude Code ones", () => {
  const [v] = hookViews("edit", { filePath: "/r/a", oldString: "a", newString: "b", replaceAll: true }, "/r")
  expect(v.tool_name).toBe("Edit")
  expect(v.tool_input).toEqual({ filePath: "/r/a", oldString: "a", newString: "b", replaceAll: true,
    file_path: "/r/a", old_string: "a", new_string: "b", replace_all: true })
  expect(hookViews("bash", { command: "ls" }, "/r")[0].tool_name).toBe("Bash")
  expect(hookViews("mcp_vault_write", { x: 1 }, "/r")[0].tool_name).toBe("mcp_vault_write")
})

test("fromHookInput drops untouched aliases and maps changed ones back", () => {
  const [v] = hookViews("write", { filePath: "/r/a", content: "x" }, "/r")
  expect(fromHookInput({ ...v.tool_input }, v)).toEqual({ filePath: "/r/a", content: "x" })
  expect(fromHookInput({ ...v.tool_input, content: "y" }, v)).toEqual({ filePath: "/r/a", content: "y" })
})

test("applyPatchOperations resolves paths against the session directory", () => {
  expect(applyPatchOperations("*** Begin Patch\n*** Delete File: ../b/c.txt\n*** End Patch", "/r/s"))
    .toEqual([["Write", "/r/b/c.txt", "delete", "", ""]])
})

// SE-392 AC6. Read as a regex, `Bash(git commit*)` was a group that never matched: block-commit-to-main and the
// other commit gates did not run in OpenCode. Matcher parity with the Codex core: tests/dual-cli/test_prompt_transport.py.
test("a command-scoped matcher selects the command in OpenCode", async () => {
  const { before } = await gatesWith(`#!/usr/bin/env bash\necho COMMIT_GATE >&2; exit 2\n`, "Bash(git commit*)")
  expect((await before("bash", { command: "git commit -m 'feat: x'" })).verdict).toContain("COMMIT_GATE")
  const heredoc = "git commit -m \"$(cat <<'EOF'\nfeat: x\n\ncuerpo\nEOF\n)\""
  expect((await before("bash", { command: heredoc })).verdict).toContain("COMMIT_GATE")
  expect((await before("bash", { command: "git status" })).verdict).toBe("PASS")
})

test("a prompt handler goes to the declared evaluator and every failure blocks", async () => {
  const prompt = { type: "prompt", prompt: "Valida: $ARGUMENTS", timeout: 2 }
  const { before } = await gatesWith(`#!/usr/bin/env bash\nexit 0\n`, "Bash(git commit*)", [prompt])
  const commit = { command: "git commit -m 'feat: x'" }
  delete process.env.SAVIA_PROMPT_HOOK_CMD
  expect((await before("bash", commit)).verdict).toContain("PROMPT_HOOK_UNAVAILABLE")
  expect((await before("bash", { command: "ls" })).verdict).toBe("PASS")
  process.env.SAVIA_PROMPT_HOOK_CMD = `grep -q "git commit -m 'feat: x'" && echo '{"ok": true}'`
  expect((await before("bash", commit)).verdict).toBe("PASS")
  process.env.SAVIA_PROMPT_HOOK_CMD = `cat >/dev/null; echo '{"ok": false, "reason": "vago"}'`
  expect((await before("bash", commit)).verdict).toContain("PROMPT_HOOK_BLOCK: vago")
  process.env.SAVIA_PROMPT_HOOK_CMD = `cat >/dev/null; echo 'vale'`
  expect((await before("bash", commit)).verdict).toContain("INVALID_HOOK_OUTPUT")
})

test("the gate files cannot be rewritten from OpenCode, also without SAVIA_GATES_PIN", async () => {
  const { root, before } = await gatesWith(`#!/usr/bin/env bash\nexit 0\n`)
  expect((await before("write", { filePath: join(root, ".claude/settings.json"), content: "{}" })).verdict).toContain("PROTECTED_GATE_PATH")
  expect((await before("edit", { filePath: join(root, ".claude/hooks/guard.sh"), oldString: "exit 0", newString: "exit 0" })).verdict).toContain("PROTECTED_GATE_PATH")
  const patch = "*** Begin Patch\n*** Add File: libre.txt\n+a\n*** Add File: scripts/opencode-plugin/x.ts\n+b\n*** End Patch\n"
  expect((await before("apply_patch", { patchText: patch })).verdict).toContain("PROTECTED_GATE_PATH")
  expect((await before("write", { filePath: join(root, "libre.txt"), content: "x" })).verdict).toBe("PASS")
})
