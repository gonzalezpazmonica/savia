import { afterEach, expect, test } from "bun:test"
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises"
import { existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// Hook context (UserPromptSubmit additionalContext) carries no confidentiality level unless the hook
// declares one (hookSpecificOutput.saviaLevel), so it counts as N3. It is attached only when the turn is
// local by BOTH signals: the lane Space exports (SAVIA_GATES_ENGINE_LANE, unset outside Space) and every
// provider the turn can reach (model, small_model, agent model, message model) declared local in
// SAVIA_GATES_LOCAL_PROVIDERS. Otherwise only context declared N1 goes. Same input across all cases.

const roots: string[] = []
const savedEnv = { ...process.env }
const auditDir = await mkdtemp(join(tmpdir(), "savia-lane-audit-"))
process.env.SAVIA_AUDIT_DIR = auditDir
const { SaviaGates } = await import("../index")

afterEach(async () => {
  process.env = { ...savedEnv, SAVIA_AUDIT_DIR: auditDir }
  for (const r of roots.splice(0)) await rm(r, { recursive: true, force: true })
})

const PRIVATE = "MARKER_HOOK_CONTEXT_N3"
const PUBLIC = "MARKER_HOOK_CONTEXT_N1"
const hook = (ctx: string, level?: string) =>
  [
    "#!/usr/bin/env bash",
    "cat >/dev/null",
    `echo '${JSON.stringify({
      hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: ctx, ...(level ? { saviaLevel: level } : {}) },
    })}'`,
    "",
  ].join("\n")

async function workspace(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "savia-lane-test-"))
  roots.push(root)
  await mkdir(join(root, ".claude/hooks"), { recursive: true })
  await mkdir(join(root, ".opencode"), { recursive: true })
  await symlink("../.claude/hooks", join(root, ".opencode/hooks"))
  await writeFile(join(root, ".claude/hooks/private.sh"), hook(PRIVATE), { mode: 0o755 })
  await writeFile(join(root, ".claude/hooks/public.sh"), hook(PUBLIC, "N1"), { mode: 0o755 })
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({
    hooks: { UserPromptSubmit: [{ hooks: [
      { type: "command", command: '"$CLAUDE_PROJECT_DIR"/.opencode/hooks/private.sh' },
      { type: "command", command: '"$CLAUDE_PROJECT_DIR"/.opencode/hooks/public.sh' },
    ] }] },
  }))
  return root
}

type Case = {
  lane?: string
  local?: string
  config?: Record<string, unknown> | "throws" | "hangs"
  messageProvider?: string
}

const LOCAL_CFG = { model: "ollama/qwen", small_model: "ollama/qwen" }

async function send(c: Case): Promise<string> {
  const root = await workspace()
  delete process.env.SAVIA_GATES_PIN
  for (const [k, v] of [["SAVIA_GATES_ENGINE_LANE", c.lane], ["SAVIA_GATES_LOCAL_PROVIDERS", c.local]] as const) {
    if (v === undefined) delete process.env[k]
    else process.env[k] = v
  }
  process.env.SAVIA_PLUGIN_DIR = join(root, ".manifest-test")
  const client = {
    config: {
      get: async () => {
        if (c.config === "throws") throw new Error("sin servidor")
        if (c.config === "hangs") return new Promise(() => {})
        return { data: c.config ?? LOCAL_CFG }
      },
    },
  }
  const hooks: any = await SaviaGates({ $: Bun.$, directory: root, client } as any)
  const output: any = { message: { id: "msg_1" }, parts: [{ type: "text", text: "hola" }] }
  const model = c.messageProvider ? { providerID: c.messageProvider, modelID: "m" } : undefined
  await hooks["chat.message"]({ sessionID: "ses_1", agent: "build", model }, output)
  expect(output.parts[0]).toEqual({ type: "text", text: "hola" })
  expect(output.parts.length).toBeLessThanOrEqual(2)
  return output.parts.slice(1).map((p: any) => (expect(p.synthetic).toBe(true), p.text)).join("\n")
}

async function withheldCount(): Promise<number> {
  const f = join(auditDir, "savia-gates.jsonl")
  return existsSync(f) ? (await readFile(f, "utf8")).split("prompt-context-withheld").length - 1 : 0
}

test("local by both signals: every hook context is attached", async () => {
  for (const lane of ["local", undefined]) {
    const shipped = await send({ lane, local: "ollama" })
    expect(shipped).toContain(PRIVATE)
    expect(shipped).toContain(PUBLIC)
  }
})

test("cloud by either signal: only context declared N1 is attached, the rest is withheld and audited", async () => {
  const cases: Case[] = [
    { lane: "cloud", local: "ollama" }, // Space says cloud, providers say local
    { lane: "local" }, // Space says local, no provider declared local
    { lane: undefined }, // plain OpenCode CLI, nothing declared
    { lane: "", local: "ollama" },
    { lane: "LOCAL", local: "ollama" },
    { lane: " local", local: "ollama" },
    { lane: "local", local: "ollama", config: { model: "ollama/qwen", small_model: "anthropic/haiku" } }, // title model
    { lane: "local", local: "ollama", config: { model: "ollama/qwen", agent: { build: { model: "openai/x" } } } },
    { lane: "local", local: "ollama", config: { ...LOCAL_CFG, agent: { title: { model: "anthropic/haiku" } } } },
    { lane: "local", local: "ollama", config: { ...LOCAL_CFG, agent: { summary: { model: "anthropic/haiku" } } } },
    { lane: "local", local: "ollama", config: { ...LOCAL_CFG, agent: { compaction: { model: "anthropic/haiku" } } } },
    { lane: "local", local: "ollama", config: { ...LOCAL_CFG, agent: { title: { model: "desconocido" } } } }, // internal agent, unknown model
    { lane: "local", local: "ollama", config: "hangs" }, // config.get never answers
    { lane: "local", local: "ollama", messageProvider: "anthropic" },
    { lane: "local", local: "ollama", config: { model: "qwen" } }, // provider cannot be resolved
    { lane: "local", local: "ollama", config: {} },
    { lane: "local", local: "ollama", config: "throws" },
  ]
  for (const c of cases) {
    const before = await withheldCount()
    const shipped = await send(c)
    expect(shipped, JSON.stringify(c)).not.toContain(PRIVATE)
    expect(shipped, JSON.stringify(c)).toBe(PUBLIC)
    expect(await withheldCount(), JSON.stringify(c)).toBe(before + 1)
  }
  const log = await readFile(join(auditDir, "savia-gates.jsonl"), "utf8")
  expect(log).not.toContain(PRIVATE)
})

test("internal agents on a local provider keep the turn local", async () => {
  const config = { ...LOCAL_CFG, agent: { title: { model: "ollama/a" }, summary: { model: "ollama/b" }, compaction: { model: "ollama/c" } } }
  expect(await send({ lane: "local", local: "ollama", config })).toContain(PRIVATE)
})

test("a hook declaring N2, N3 or N4 is withheld from the cloud, N1 goes", async () => {
  for (const level of ["N2", "N3", "N4"]) {
    const root = await workspace()
    await writeFile(join(root, ".claude/hooks/private.sh"), hook(PRIVATE, level), { mode: 0o755 })
    delete process.env.SAVIA_GATES_PIN
    process.env.SAVIA_GATES_ENGINE_LANE = "cloud"
    process.env.SAVIA_PLUGIN_DIR = join(root, ".manifest-test")
    const client = { config: { get: async () => ({ data: LOCAL_CFG }) } }
    const hooks: any = await SaviaGates({ $: Bun.$, directory: root, client } as any)
    const output: any = { message: { id: "msg_1" }, parts: [{ type: "text", text: "hola" }] }
    await hooks["chat.message"]({ sessionID: "ses_1", agent: "build" }, output)
    const shipped = output.parts.slice(1).map((p: any) => p.text).join("\n")
    expect(shipped, level).not.toContain(PRIVATE)
    expect(shipped, level).toBe(PUBLIC)
  }
})
