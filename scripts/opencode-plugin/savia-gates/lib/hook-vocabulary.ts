// hook-vocabulary.ts — OpenCode tool calls as the Claude Code hooks expect them (SE-392 S3).
//
// The hooks in .claude/settings.json are written for Claude Code: `tool_name` is `Bash`/`Edit`/`Write`
// and the input carries `file_path`, `old_string`, `new_string`. OpenCode passes `bash`/`edit`/`write`
// and `filePath`, `oldString`, `newString`, so a hook that compares `tool_name == "Edit"` or reads only
// `.tool_input.file_path` let an OpenCode edit through that Claude Code and Codex block (tdd-gate,
// permission-mode-gate, …). `apply_patch` carries every file in one body and matched no Edit|Write
// hook at all. Here each call becomes the same per-effect events the Codex adapter produces
// (scripts/dual-cli/gates.py: normalize_codex_pretool / apply_patch_operations), so both frontends
// replay to the same decisions. Original keys stay in the input: hooks that already read
// `filePath` keep working. A patch that cannot be parsed is an error, never "no files".

import { realpathSync } from "node:fs"
import { basename, dirname, isAbsolute, join, normalize, sep } from "node:path"
import { runHooksForEvent } from "./shell-bridge"
import type { HookMap, RunOptions } from "./shell-bridge"

const TOOL_NAMES: Record<string, string> = {
  bash: "Bash", edit: "Edit", write: "Write", read: "Read", glob: "Glob", grep: "Grep",
  list: "LS", ls: "LS", task: "Task", multiedit: "MultiEdit", notebookedit: "NotebookEdit",
  webfetch: "WebFetch", websearch: "WebSearch", todowrite: "TodoWrite", todoread: "TodoRead",
}

/** OpenCode key -> Claude Code key. */
const KEY_ALIASES: [string, string][] = [
  ["filePath", "file_path"], ["oldString", "old_string"], ["newString", "new_string"], ["replaceAll", "replace_all"],
]

const PATCH_TOOLS = new Set(["apply_patch", "patch"])

/**
 * The agent being gated must not rewrite the gate. Same list as PROTECTED_PATHS in
 * scripts/dual-cli/gates.py (parity checked by tests/dual-cli/test_prompt_transport.py), relative to the root.
 * Before this, OpenCode only protected them through guard-pin with SAVIA_GATES_PIN=1.
 */
export const PROTECTED_GATE_PATHS = [".claude/settings.json", ".claude/settings.local.json", ".claude/hooks",
  ".opencode/hooks", ".opencode/plugins", ".opencode/plugin", "scripts/dual-cli", "scripts/opencode-plugin", ".codex",
  "opencode.json", "opencode.jsonc", ".opencode/opencode.json", ".opencode/opencode.jsonc", ".opencode/package.json"]

/** Tools whose view carries a file the call writes. */
const FILE_EFFECT_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"])

/** os.path.realpath: resolves the symlinks of the part that exists, keeps the rest as written. */
function realPath(p: string): string {
  try {
    return realpathSync(p)
  } catch {
    const parent = dirname(p)
    return parent === p ? p : join(realPath(parent), basename(p))
  }
}

/** Port of gates.is_protected: the path (lexically and through symlinks) is gate configuration or code. */
export function isProtectedPath(path: string, root: string): boolean {
  for (const candidate of [normalize(path), realPath(path)]) {
    for (const rel of PROTECTED_GATE_PATHS) {
      for (const base of [normalize(join(root, rel)), realPath(join(root, rel))]) {
        if (candidate === base || candidate.startsWith(base + sep)) return true
      }
    }
  }
  return false
}

export interface HookView {
  tool_name: string
  tool_input: Record<string, unknown>
  /** One file of a multi-file patch: a hook rewrite cannot be mapped back onto the patch. */
  decomposed: boolean
  /** Claude Code keys this view added on top of the OpenCode input. */
  aliases: [string, string][]
}

const HEADERS: [string, string][] = [["*** Add File: ", "add"], ["*** Update File: ", "update"], ["*** Delete File: ", "delete"]]
const OTHER_HEADERS = new Set(["*** Begin Patch", "*** End Patch", "*** End of File"])
const MOVE = "*** Move to: "

/** Python's str.splitlines() boundaries, so both cores see the same lines. */
const LINE_BREAK = /\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]/

/** os.path.normpath(os.path.join(cwd, p)) */
function joinPath(cwd: string, p: string): string {
  const out = normalize(isAbsolute(p) ? p : join(cwd, p))
  return out.length > 1 && out.endsWith("/") ? out.slice(0, -1) : out
}

/** Port of gates.apply_patch_operations: per-file [tool, path, op, content, old]. Throws INVALID_EVENT. */
export function applyPatchOperations(patch: unknown, cwd: string): [string, string, string, string, string][] {
  if (typeof patch !== "string" || !patch.includes("*** Begin Patch")) throw new Error("INVALID_EVENT")
  type Op = { op: string; path: string; added: string[]; removed: string[]; moveTo?: string }
  const ops: Op[] = []
  let current: Op | null = null
  const lines = patch.split(LINE_BREAK)
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
  for (const line of lines) {
    const head = line.trim()
    if (head.startsWith("+") || head.startsWith("-") || !head.startsWith("***")) {
      if (current) {
        if (line.startsWith("+")) current.added.push(line.slice(1))
        else if (line.startsWith("-")) current.removed.push(line.slice(1))
      }
      continue
    }
    const header = HEADERS.find(([prefix]) => head.startsWith(prefix))
    if (header) {
      current = { op: header[1], path: head.slice(header[0].length).trim(), added: [], removed: [] }
      ops.push(current)
    } else if (head.startsWith(MOVE) && current?.op === "update") {
      current.moveTo = head.slice(MOVE.length).trim()
    } else if (!OTHER_HEADERS.has(head) && !head.startsWith(MOVE)) {
      throw new Error("INVALID_EVENT")
    }
  }
  if (ops.length === 0 || ops.some((o) => !o.path)) throw new Error("INVALID_EVENT")
  const result: [string, string, string, string, string][] = []
  for (const o of ops) {
    result.push([o.op === "update" ? "Edit" : "Write", joinPath(cwd, o.path), o.op, o.added.join("\n"), o.removed.join("\n")])
    if (o.moveTo !== undefined) result.push(["Write", joinPath(cwd, o.moveTo), "move", o.added.join("\n"), ""])
  }
  return result
}

/** The hook events one OpenCode tool call stands for (one per file for a patch). */
export function hookViews(tool: string, input: Record<string, unknown>, cwd: string): HookView[] {
  const lower = String(tool ?? "").toLowerCase()
  if (PATCH_TOOLS.has(lower)) {
    const body = typeof input?.patchText === "string" ? input.patchText : input?.patch ?? input?.command
    return applyPatchOperations(body, cwd).map(([name, path, op, content, old]) => ({
      tool_name: name,
      tool_input: name === "Write"
        ? { file_path: path, operation: op, content }
        : { file_path: path, operation: op, new_string: content, old_string: old },
      decomposed: true,
      aliases: [],
    }))
  }
  const view: Record<string, unknown> = { ...input }
  const aliases: [string, string][] = []
  for (const [from, to] of KEY_ALIASES) {
    if (from in view && !(to in view)) {
      view[to] = view[from]
      aliases.push([from, to])
    }
  }
  return [{ tool_name: TOOL_NAMES[lower] ?? tool, tool_input: view, decomposed: false, aliases }]
}

/** A hook rewrite expressed in Claude Code keys, carried back to the OpenCode keys the tool runs with. */
export function fromHookInput(mutated: Record<string, unknown>, view: HookView): Record<string, unknown> {
  const next: Record<string, unknown> = { ...mutated }
  for (const [from, to] of view.aliases) {
    if (to in next && JSON.stringify(next[to]) !== JSON.stringify(view.tool_input[to])) next[from] = next[to]
    delete next[to]
  }
  return next
}

export interface PreToolUseOutcome {
  blocked: boolean
  reason: string
  mutated?: Record<string, unknown>
}

/** Runs PreToolUse for every view of one call; the first block wins. Shared by gates.ts and the replay. */
export async function runPreToolUse(
  root: string,
  hookMap: HookMap,
  tool: string,
  input: Record<string, unknown>,
  base: { session_id?: string; call_id?: string; cwd: string },
  opts: RunOptions = {},
): Promise<PreToolUseOutcome> {
  let views: HookView[]
  try {
    views = hookViews(tool, input, base.cwd)
  } catch {
    return { blocked: true, reason: "INVALID_EVENT" }
  }
  for (const view of views) {
    const target = view.tool_input.file_path ?? view.tool_input.notebook_path
    if (FILE_EFFECT_TOOLS.has(view.tool_name) && typeof target === "string" &&
        isProtectedPath(joinPath(base.cwd, target), root)) {
      return { blocked: true, reason: "PROTECTED_GATE_PATH" }
    }
  }
  let mutated: Record<string, unknown> | undefined
  for (const view of views) {
    const payload = JSON.stringify({
      hook_event_name: "PreToolUse",
      tool_name: view.tool_name,
      tool_input: view.tool_input,
      session_id: base.session_id,
      call_id: base.call_id,
      cwd: base.cwd,
    })
    const result = await runHooksForEvent(root, hookMap, "PreToolUse", view.tool_name, payload, opts)
    if (result.blocked) return { blocked: true, reason: result.stderr || "PreToolUse blocked" }
    if (result.mutatedArgs && typeof result.mutatedArgs === "object") {
      // Same rule as the Codex adapter: a rewrite that cannot be applied must not let the original run.
      if (view.decomposed) return { blocked: true, reason: "UPDATED_INPUT_UNSUPPORTED" }
      mutated = fromHookInput(result.mutatedArgs, view)
    }
  }
  return { blocked: false, reason: "HOOK_OK", mutated }
}
