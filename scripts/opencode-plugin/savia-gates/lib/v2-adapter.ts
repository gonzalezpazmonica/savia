// v2-adapter.ts — OpenCode 2 binding for savia-gates.
//
// V2 loads a plugin through `setup(ctx)` and registers hooks per domain; every hook receives ONE mutable
// event. A V1 plugin does not load in V2, so without this adapter the guards were lost silently on upgrade.
// Blocking is fail closed: a throw in `tool.execute.before` rejects that tool call, a throw in the
// `prompt` hook means the prompt is never admitted. The core lives in gates.ts (shared with V1).
//
// Vocabulary: the guards (hooks in .claude/settings.json, dome-guard, guard-pin) speak V1 (`bash`, `task`,
// `filePath`). V2 renamed tools (`shell`, `subagent`) and uses `path`, so tool and args are normalised
// here, in one place, before any decision. No Bun-only API is used (`$` has no V2 counterpart).

import { createGates } from "./gates"
import type { Gates, HookContext } from "./gates"
import { patchPaths } from "./guard-pin"

/** V2 tool name -> the name the guards and the settings.json matchers use. */
export function normalizeToolName(tool: unknown): string {
  const t = String(tool ?? "").toLowerCase()
  if (t === "shell") return "bash"
  if (t === "subagent") return "task"
  return t
}

/**
 * The tool input as the guards expect it: `path` also visible as `filePath` (V1 key). A non-object input
 * is wrapped so the guards still see it instead of an empty object.
 */
export function guardView(raw: unknown): Record<string, unknown> {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return { value: raw }
  const view: Record<string, unknown> = { ...(raw as Record<string, unknown>) }
  if (typeof view.path === "string" && view.filePath === undefined) view.filePath = view.path
  return view
}

/** Carries a guard's rewrite (e.g. credential redaction) from the guard view back to the V2 input. */
export function applyMutation(raw: unknown, view: Record<string, unknown>, mutated: Record<string, unknown>): unknown {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return raw
  const next: Record<string, unknown> = { ...(raw as Record<string, unknown>) }
  for (const [k, v] of Object.entries(mutated)) {
    if (JSON.stringify(v) !== JSON.stringify(view[k])) next[k] = v
  }
  for (const k of Object.keys(view)) {
    if (!(k in mutated) && k in next) delete next[k]
  }
  // `filePath` is only the guards' name for V2's `path`: a rewrite of it is a rewrite of `path`.
  const rawObj = raw as Record<string, unknown>
  if (rawObj.filePath === undefined && "filePath" in next) {
    if (typeof rawObj.path === "string" && next.path === rawObj.path) next.path = next.filePath
    delete next.filePath
  }
  return next
}

function resultText(event: any): string {
  if (event?.status === "error") return String(event?.error?.message ?? "")
  const r = event?.result
  if (typeof r === "string") return r
  const c = r?.content ?? r?.output
  if (typeof c === "string") return c
  if (Array.isArray(c)) return c.map((p: any) => (typeof p === "string" ? p : p?.text ?? "")).join("\n")
  return r === undefined ? "" : JSON.stringify(r)
}

/** Event stream types -> Claude Code lifecycle categories. */
const FILE_TOOLS = new Set(["edit", "write", "patch", "multiedit"])

/** Files a successful edit/write/patch touched (V2 emits no `file.edited` event for tool writes). */
function touchedFiles(tool: string, input: Record<string, unknown>): string[] {
  if (!FILE_TOOLS.has(tool)) return []
  const out: string[] = []
  for (const k of ["path", "filePath", "file_path"]) if (typeof input[k] === "string") out.push(input[k] as string)
  if (typeof input.patchText === "string") out.push(...patchPaths(input.patchText))
  return [...new Set(out)]
}

const EVENT_MAP: Record<string, Array<{ cc: string; augment?: (e: any) => Record<string, unknown> }>> = {
  "session.created": [
    { cc: "SessionStart" },
    { cc: "InstructionsLoaded", augment: () => ({ file_path: "AGENTS.md", memory_type: "instructions", load_reason: "session.created" }) },
  ],
  "session.deleted": [{ cc: "SessionEnd" }],
  // A V2 execution (one agent turn) ends in one of these three; `session.idle` is not emitted for it.
  "session.execution.succeeded": [{ cc: "Stop" }],
  "session.execution.failed": [{ cc: "Stop" }],
  "session.execution.interrupted": [{ cc: "Stop" }],
  "file.edited": [{ cc: "FileChanged", augment: (e) => ({ file_path: eventField(e, "file", "path") }) }],
}

function eventField(e: any, ...keys: string[]): string {
  for (const bag of [e?.data, e?.properties, e]) {
    for (const k of keys) if (typeof bag?.[k] === "string") return bag[k]
  }
  return ""
}

async function optional(what: string, register: () => Promise<unknown>): Promise<void> {
  try {
    await register()
  } catch (e) {
    // A runtime without this non-authority hook must not break the load; the authority hooks do not use this.
    process.stderr.write(`savia-gates: optional hook ${what} unavailable: ${e instanceof Error ? e.message : String(e)}\n`)
  }
}

/**
 * OpenCode 1.19 also calls `setup()` on an object that has `id` + `setup`, with a reduced context
 * (agent, catalog, command, integration, plugin, reference, skill: no `location`, `tool`, `session` or
 * `permission`). V1 takes its hooks from `server()`; a `setup()` there must do nothing. A real V2 context
 * always has `location`, so a context with `location` but without the hook domains is a runtime change
 * we do not know and fails loudly instead of loading without guards.
 */
function isReducedHostContext(ctx: any): boolean {
  return ctx?.location === undefined && ctx?.tool === undefined && ctx?.session === undefined
}

export async function setupV2(ctx: any): Promise<void | (() => void)> {
  if (isReducedHostContext(ctx)) return
  for (const [domain, fn] of [["tool", "hook"], ["session", "hook"], ["permission", "hook"]] as const) {
    if (typeof ctx?.[domain]?.[fn] !== "function") {
      throw new Error(`savia-gates: this OpenCode 2 has no ctx.${domain}.${fn}(); the guards cannot be installed`)
    }
  }
  let gates: Gates
  try {
    gates = await createGates({ directory: ctx.location?.directory, worktree: ctx.location?.project?.directory }, "v2")
  } catch (e) {
    // The guards could not start. Loading without them is the silent loss this plugin exists to prevent,
    // so every tool call and every prompt is refused until the engine is restarted with a working install.
    const why = e instanceof Error ? e.message : String(e)
    const deny = (what: string) => () => {
      throw new Error(`savia-gates: ${what} blocked — GUARDS_UNAVAILABLE: ${why}`)
    }
    await ctx.tool.hook("execute.before", deny("tool call"))
    await ctx.session.hook("prompt", deny("prompt"))
    return
  }

  // Authority hooks: their registration errors propagate on purpose (a plugin that fails to load is visible).
  await ctx.tool.hook("execute.before", async (event: any) => {
    const tool = normalizeToolName(event.tool)
    const view = guardView(event.input)
    const mutated = await gates.beforeTool({ tool, args: view, sessionID: event.sessionID, callID: event.id })
    if (mutated) event.input = applyMutation(event.input, view, mutated)
    if (tool === "task") await gates.fire("SubagentStart", { session_id: event.sessionID, tool_input: view })
  })

  await ctx.tool.hook("execute.after", async (event: any) => {
    const tool = normalizeToolName(event.tool)
    const view = guardView(event.input)
    await gates.afterTool({ tool, args: view, output: resultText(event), sessionID: event.sessionID, callID: event.id })
    if (event.status === "completed") {
      for (const file of touchedFiles(tool, view)) await gates.fire("FileChanged", { file_path: file })
    }
    if (tool === "task") await gates.fire("SubagentStop", { session_id: event.sessionID })
  })

  // Context produced by the prompt hooks for the current turn, per session. The provider is only known when
  // the model request is built, so it is shipped from the `context` hook, which sees that request's model.
  const turnContext = new Map<string, HookContext[]>()

  await ctx.session.hook("prompt", async (event: any) => {
    const contexts = await gates.promptSubmit({ sessionID: event.sessionID, text: String(event.prompt?.text ?? "") })
    if (contexts.length > 0) turnContext.set(event.sessionID, contexts)
    else turnContext.delete(event.sessionID)
  })

  await ctx.session.hook("context", async (event: any) => {
    const contexts = turnContext.get(event.sessionID)
    if (!contexts) return
    const shipped = await gates.shippableContext(contexts, [String(event.model?.providerID ?? "")])
    if (shipped) event.system.push({ type: "text", text: shipped })
  })

  await ctx.permission.hook("evaluate", async (event: any) => {
    const resources: string[] = Array.isArray(event.resources) ? [...event.resources] : []
    // Only a shell action carries a command: for the others, matching destructive command patterns against
    // file contents in the metadata would deny a legitimate edit.
    if (event.action === "shell" && typeof event.metadata?.command === "string") resources.push(event.metadata.command)
    const decision = await gates.permission({ tool: event.action, command: event.action === "shell" ? resources.join("\n") : "" })
    if (decision === "deny") {
      event.effect = "deny"
      event.message = "savia-gates: acción destructiva denegada en rama agent/* (AUTONOMOUS_REVIEWER)"
    }
  })

  // Non-authority hooks.
  await optional("shell.create.before", () =>
    ctx.shell.hook("create.before", async (event: any) => {
      await gates.cwdChanged(event.cwd)
    }))

  const controller = new AbortController()
  void (async () => {
    try {
      for await (const ev of ctx.event.subscribe({ signal: controller.signal })) {
        const type = ev?.type
        if (typeof type !== "string") continue
        if (type === "session.compacted") await gates.compacted(eventField(ev, "sessionID"))
        else if (type === "session.compaction.started") await gates.compacting(eventField(ev, "sessionID"))
        else if (type === "config.updated") await gates.configChanged()
        else {
          if (type === "session.deleted") turnContext.delete(eventField(ev, "sessionID"))
          for (const t of EVENT_MAP[type] ?? []) await gates.fire(t.cc, { event: ev, ...(t.augment?.(ev) ?? {}) })
        }
      }
    } catch {
      // Aborted on unload, or the stream ended: lifecycle events are best effort.
    }
  })()
  return () => controller.abort()
}
