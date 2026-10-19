import { afterEach, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import plugin, { SaviaGates } from "../index"
import { applyMutation, guardView, normalizeToolName } from "../lib/v2-adapter"

// OpenCode 2 does not load a V1 plugin: before the dual export the guards disappeared without any error.
// These tests drive the V2 entry (`setup(ctx)`) with a fake context that records the hooks the way the
// real runtime registers them (verified against the v2.0.32 binary by scripts/opencode-gates-v2-real.sh).

const roots: string[] = []
const savedEnv = { ...process.env }

afterEach(async () => {
  process.env = { ...savedEnv }
  await Promise.all(roots.splice(0).map((r) => rm(r, { recursive: true, force: true })))
})

const BLOCKING_GUARD = '#!/usr/bin/env bash\nin=$(cat)\ncase "$in" in *PROHIBIDO*) echo "PROHIBIDO bloqueado" >&2; exit 2;; esac\nexit 0\n'
const REWRITE_GUARD = '#!/usr/bin/env bash\ncat >/dev/null\necho \'{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"echo limpio","timeout":5}}}\'\n'
const CONTEXT_GUARD = (level: string) =>
  `#!/usr/bin/env bash\ncat >/dev/null\necho '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"CTX_${level}","saviaLevel":"${level}"}}'\n`

async function workspace(hooks: Record<string, unknown>, files: Record<string, string> = {}): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "savia-v2-test-"))
  roots.push(root)
  await mkdir(join(root, ".claude/hooks"), { recursive: true })
  await writeFile(join(root, ".claude/hooks/guard.sh"), BLOCKING_GUARD, { mode: 0o755 })
  for (const [name, body] of Object.entries(files)) await writeFile(join(root, ".claude/hooks", name), body, { mode: 0o755 })
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({ hooks }))
  process.env.SAVIA_AUDIT_DIR = join(root, ".audit-test")
  process.env.SAVIA_PLUGIN_DIR = join(root, ".manifest-test")
  delete process.env.SAVIA_GATES_PIN
  delete process.env.SAVIA_DOME_GUARD
  return root
}

const cmd = (name: string) => ({ type: "command", command: `"$CLAUDE_PROJECT_DIR"/.claude/hooks/${name}` })

function fakeCtx(directory: string) {
  const hooks: Record<string, Array<(event: any) => Promise<void> | void>> = {}
  const mk = (domain: string) => ({
    hook: async (name: string, cb: (event: any) => Promise<void> | void) => {
      ;(hooks[`${domain}.${name}`] ??= []).push(cb)
      return { dispose: async () => {} }
    },
  })
  const ctx = {
    location: { directory, project: { id: "p", directory, canonical: directory } },
    tool: mk("tool"), session: mk("session"), permission: mk("permission"), shell: mk("shell"),
    event: { subscribe: () => ({ async *[Symbol.asyncIterator]() {} }) },
  }
  return { ctx, hooks }
}

async function fire(hooks: Record<string, Array<(e: any) => any>>, key: string, event: any): Promise<string> {
  try {
    for (const cb of hooks[key] ?? []) await cb(event)
    return "PASS"
  } catch (e) {
    return String(e)
  }
}

test("one default export serves V1 (server) and V2 (id + setup)", () => {
  expect(plugin.id).toBe("savia-gates")
  expect(typeof plugin.setup).toBe("function")
  expect(typeof plugin.server).toBe("function")
})

test("setup registers every authority hook", async () => {
  const root = await workspace({})
  const { ctx, hooks } = fakeCtx(root)
  await plugin.setup(ctx as any)
  for (const key of ["tool.execute.before", "tool.execute.after", "session.prompt", "session.context", "permission.evaluate"]) {
    expect(hooks[key]?.length, key).toBe(1)
  }
})

test("V2 names are normalised and the guard blocks: shell is bash, subagent is task, path is also filePath", () => {
  expect(normalizeToolName("shell")).toBe("bash")
  expect(normalizeToolName("subagent")).toBe("task")
  expect(normalizeToolName("Read")).toBe("read")
  expect(guardView({ path: "a.md" })).toEqual({ path: "a.md", filePath: "a.md" })
  expect(guardView("raw")).toEqual({ value: "raw" })
})

test("a PreToolUse hook blocks a shell call, a read by path and a subagent call (matchers use V1 names)", async () => {
  const root = await workspace({ PreToolUse: [{ matcher: "Bash|Read|Task", hooks: [cmd("guard.sh")] }] })
  const { ctx, hooks } = fakeCtx(root)
  await plugin.setup(ctx as any)
  const run = (tool: string, input: unknown) => fire(hooks, "tool.execute.before", { tool, input, sessionID: "ses_1", id: "call_1" })
  expect(await run("shell", { command: "echo PROHIBIDO" })).toContain("PROHIBIDO bloqueado")
  expect(await run("read", { path: "PROHIBIDO.md" })).toContain("PROHIBIDO bloqueado")
  expect(await run("subagent", { prompt: "PROHIBIDO" })).toContain("PROHIBIDO bloqueado")
  expect(await run("shell", { command: "echo hola" })).toBe("PASS")
  // A tool the matcher does not name is not blocked.
  expect(await run("grep", { pattern: "PROHIBIDO" })).toBe("PASS")
})

test("a guard rewrite (it replaces the whole input, as in V1) reaches the V2 input", async () => {
  const root = await workspace({ PreToolUse: [{ matcher: "Bash", hooks: [cmd("rewrite.sh")] }] }, { "rewrite.sh": REWRITE_GUARD })
  const { ctx, hooks } = fakeCtx(root)
  await plugin.setup(ctx as any)
  const event: any = { tool: "shell", input: { command: "echo secreto", timeout: 5 }, sessionID: "s", id: "c" }
  expect(await fire(hooks, "tool.execute.before", event)).toBe("PASS")
  expect(event.input.command).toBe("echo limpio")
  expect(event.input.timeout).toBe(5)
  // The alias the adapter adds for the guards never leaks into the V2 input.
  expect(applyMutation({ path: "a" }, { path: "a", filePath: "a" }, { path: "a", filePath: "a" })).toEqual({ path: "a" })
  expect(applyMutation({ path: "a", x: 1 }, { path: "a", filePath: "a", x: 1 }, { path: "b", filePath: "b", x: 1 })).toEqual({ path: "b", x: 1 })
})

test("a prompt hook blocks the prompt (fail closed) and a clean prompt passes", async () => {
  const root = await workspace({ UserPromptSubmit: [{ hooks: [cmd("guard.sh")] }] })
  const { ctx, hooks } = fakeCtx(root)
  await plugin.setup(ctx as any)
  expect(await fire(hooks, "session.prompt", { sessionID: "s", prompt: { text: "esto es PROHIBIDO" } })).toContain("prompt blocked")
  expect(await fire(hooks, "session.prompt", { sessionID: "s", prompt: { text: "hola" } })).toBe("PASS")
})

test("prompt context goes to the model by this request's provider: cloud keeps only N1, a declared local one gets all", async () => {
  const root = await workspace({ UserPromptSubmit: [{ hooks: [cmd("n3.sh"), cmd("n1.sh")] }] }, {
    "n3.sh": CONTEXT_GUARD("N3"), "n1.sh": CONTEXT_GUARD("N1"),
  })
  process.env.SAVIA_GATES_LOCAL_PROVIDERS = "ollama"
  delete process.env.SAVIA_GATES_ENGINE_LANE
  const { ctx, hooks } = fakeCtx(root)
  await plugin.setup(ctx as any)
  await fire(hooks, "session.prompt", { sessionID: "s", prompt: { text: "hola" } })
  const system = async (providerID: string) => {
    const event: any = { sessionID: "s", model: { providerID, id: "m" }, system: [] }
    await fire(hooks, "session.context", event)
    return event.system.map((p: any) => p.text).join("\n")
  }
  expect(await system("anthropic")).toBe("CTX_N1")
  expect(await system("")).toBe("CTX_N1")
  expect(await system("ollama")).toContain("CTX_N3")
  process.env.SAVIA_GATES_ENGINE_LANE = "cloud"
  expect(await system("ollama")).toBe("CTX_N1")
  // A new prompt without context clears the previous one.
  const empty = await workspace({})
  const again = fakeCtx(empty)
  await plugin.setup(again.ctx as any)
  await fire(again.hooks, "session.prompt", { sessionID: "s", prompt: { text: "hola" } })
  const ev: any = { sessionID: "s", model: { providerID: "ollama", id: "m" }, system: [] }
  await fire(again.hooks, "session.context", ev)
  expect(ev.system).toEqual([])
})

test("AUTONOMOUS_REVIEWER: destructive shell action on an agent/* branch is denied, other branches and actions are untouched", async () => {
  const root = await workspace({})
  const git = (...a: string[]) => Bun.spawnSync(["git", "-C", root, ...a])
  git("init", "-q", "-b", "agent/x")
  const { ctx, hooks } = fakeCtx(root)
  await plugin.setup(ctx as any)
  const evalPerm = async (action: string, resources: string[], metadata?: Record<string, unknown>) => {
    const event: any = { sessionID: "s", action, resources, metadata, effect: "ask" }
    await fire(hooks, "permission.evaluate", event)
    return event
  }
  const reset = await evalPerm("shell", ["git reset --hard HEAD~1"], { command: "git reset --hard HEAD~1" })
  expect(reset.effect).toBe("deny")
  expect(reset.message).toContain("AUTONOMOUS_REVIEWER")
  expect((await evalPerm("shell", ["git status"], { command: "git status" })).effect).toBe("ask")
  expect((await evalPerm("edit", ["notes.md"], { diff: "git reset --hard" })).effect).toBe("ask")
  git("checkout", "-q", "-b", "feature/humana")
  expect((await evalPerm("shell", ["git reset --hard HEAD~1"], { command: "git reset --hard HEAD~1" })).effect).toBe("ask")
})

test("if the guards cannot start, every tool call and prompt is refused instead of loading without guards", async () => {
  const { ctx, hooks } = fakeCtx("/nonexistent")
  const broken = { ...ctx, location: { get directory(): string { throw new Error("boom") }, project: {} } }
  await plugin.setup(broken as any)
  expect(await fire(hooks, "tool.execute.before", { tool: "shell", input: { command: "ls" } })).toContain("GUARDS_UNAVAILABLE")
  expect(await fire(hooks, "session.prompt", { sessionID: "s", prompt: { text: "hola" } })).toContain("GUARDS_UNAVAILABLE")
})

test("the registry missing blocks everything (fail closed, same as V1)", async () => {
  const root = await mkdtemp(join(tmpdir(), "savia-v2-noreg-"))
  roots.push(root)
  process.env.SAVIA_AUDIT_DIR = join(root, ".audit-test")
  const { ctx, hooks } = fakeCtx(root)
  await plugin.setup(ctx as any)
  expect(await fire(hooks, "tool.execute.before", { tool: "shell", input: { command: "ls" } })).toContain("INVALID_HOOK_CONFIGURATION")
})

test("OpenCode 1.19 calls setup() with a reduced context: it does nothing there (V1 uses server())", async () => {
  const reduced = { options: {}, agent: {}, catalog: {}, command: {}, integration: {}, plugin: {}, reference: {}, skill: {} }
  expect(await plugin.setup(reduced as any)).toBeUndefined()
  // A context that looks like V2 (has `location`) but lacks the hook domains is a loud failure, not a silent load.
  await expect(plugin.setup({ location: { directory: "/x" }, tool: {} } as any)).rejects.toThrow("ctx.tool.hook")
})

test("V1 chat.message sees the typed text from the parts (the message record has none), synthetic parts excluded", async () => {
  const root = await workspace({ UserPromptSubmit: [{ hooks: [cmd("guard.sh")] }] })
  const hooks: any = await SaviaGates({ directory: root, worktree: root } as any)
  const send = async (parts: unknown[]) => {
    try {
      await hooks["chat.message"]({ sessionID: "s", agent: "build" }, { message: { id: "msg_1", role: "user" }, parts })
      return "PASS"
    } catch (e) {
      return String(e)
    }
  }
  expect(await send([{ type: "text", text: "esto es PROHIBIDO" }])).toContain("prompt blocked")
  expect(await send([{ type: "text", text: "hola" }])).toBe("PASS")
  expect(await send([{ type: "text", text: "PROHIBIDO", synthetic: true }, { type: "text", text: "hola" }])).toBe("PASS")
})
