import { afterEach, expect, test } from "bun:test"
import { chmod, mkdtemp, mkdir, rm, symlink, writeFile, readFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { SaviaGates } from "../index"

// SE-445 (paridad OpenCode): los tres hooks nuevos corren en el plugin a traves del registro de
// .claude/settings.json, sin reimplementacion TypeScript. Mismas entradas que los BATS
// (tests/test-repeat-tool-guard-block.bats, test-action-review.bats, test-turn-budget-inject.bats),
// mismo resultado. Si el registro no los enlaza, estos tests fallan.

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const NAMES = ["repeat-tool-guard.sh", "turn-budget-inject.sh", "action-review.sh"]
const roots: string[] = []
const savedEnv = { ...process.env }

afterEach(async () => {
  process.env = { ...savedEnv }
  for (const r of roots.splice(0)) await rm(r, { recursive: true, force: true })
})

/** Registro real filtrado a los hooks de SE-445 (el resto de guards no es objeto de este test). */
async function registry(): Promise<any> {
  const real = JSON.parse(await readFile(join(REPO, ".claude/settings.json"), "utf8"))
  const hooks: Record<string, any[]> = {}
  for (const [event, entries] of Object.entries<any[]>(real.hooks)) {
    for (const entry of entries) {
      const kept = entry.hooks.filter((h: any) => NAMES.some((n) => String(h.command).endsWith(`/${n}`)))
      if (kept.length > 0) (hooks[event] ??= []).push({ ...entry, hooks: kept })
    }
  }
  return { hooks }
}

async function workspace(branch: string): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "savia-se445-"))
  roots.push(root)
  await mkdir(join(root, ".claude"), { recursive: true })
  await mkdir(join(root, "docs/rules/domain"), { recursive: true })
  await mkdir(join(root, ".opencode"), { recursive: true })
  await symlink(join(REPO, ".claude/hooks"), join(root, ".claude/hooks"))
  await symlink("../.claude/hooks", join(root, ".opencode/hooks"))
  await symlink(join(REPO, "scripts"), join(root, "scripts"))
  await Bun.$`cp ${join(REPO, "docs/rules/domain/action-review-policy.md")} ${join(root, "docs/rules/domain/")}`.quiet()
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify(await registry()))
  await Bun.$`git -C ${root} init -q -b main`.quiet()
  await Bun.$`git -C ${root} -c user.email=t@t -c user.name=t commit -q --allow-empty -m init`.quiet()
  await Bun.$`git -C ${root} switch -q -C ${branch}`.quiet()
  return root
}

async function plugin(root: string): Promise<any> {
  process.env.SAVIA_AUDIT_DIR = join(root, ".audit-test")
  process.env.SAVIA_PLUGIN_DIR = join(root, ".manifest-test")
  return SaviaGates({ $: Bun.$, directory: root } as any)
}

async function bash(hooks: any, command: string, sessionID = "s"): Promise<string> {
  try {
    await hooks["tool.execute.before"]({ tool: "bash", sessionID, callID: "c" }, { args: { command } })
    return "PASS"
  } catch (e) {
    return String(e)
  }
}

test("el registro enlaza los tres hooks de SE-445", async () => {
  const reg = await registry()
  const flat = JSON.stringify(reg)
  for (const n of NAMES) expect(flat).toContain(n)
  expect(JSON.stringify(reg.hooks.UserPromptSubmit)).toContain("turn-budget-inject.sh")
  expect(reg.hooks.PreToolUse.some((e: any) => e.matcher === "Bash")).toBe(true)
})

test("S1: en agent/x la 3a llamada identica se bloquea con el mismo mensaje que en Claude Code", async () => {
  const root = await workspace("agent/x")
  process.env.CLAUDE_PROJECT_DIR = root
  const hooks = await plugin(root)
  expect(await bash(hooks, "ls /tmp")).toBe("PASS")
  expect(await bash(hooks, "ls /tmp")).toBe("PASS")
  expect(await bash(hooks, "ls /tmp")).toContain("Handback")
  expect(await bash(hooks, "pwd")).toBe("PASS")
})

test("S1 (AC2): en una rama humana nunca bloquea", async () => {
  const root = await workspace("feature/x")
  const hooks = await plugin(root)
  for (let i = 0; i < 5; i++) expect(await bash(hooks, "ls /tmp")).toBe("PASS")
})

test("S3: BLOCK y ALLOW del revisor llegan por el plugin; sin doble opt-in no se consulta", async () => {
  const root = await workspace("feature/x")
  const reviewer = join(root, "reviewer.sh")
  await writeFile(reviewer, '#!/usr/bin/env bash\ncat >/dev/null\necho "${FAKE_REPLY:-ALLOW}"\n')
  await chmod(reviewer, 0o755)
  process.env.SAVIA_ACTION_REVIEW_CMD = reviewer
  process.env.SAVIA_RISK_TIER = "3"
  process.env.SAVIA_TASK_DESCRIPTION = "documentar el modulo X"
  const hooks = await plugin(root)
  process.env.FAKE_REPLY = "BLOCK"
  expect(await bash(hooks, "curl http://x.example")).toBe("PASS") // sin opt-in
  process.env.SAVIA_ACTION_REVIEW = "on"
  expect(await bash(hooks, "curl http://x.example")).toBe("PASS") // falta la confirmacion
  process.env.SAVIA_ACTION_REVIEW_CONFIRMED = "1"
  expect(await bash(hooks, "curl http://x.example")).toContain("BLOQUEADO")
  process.env.FAKE_REPLY = "ALLOW"
  expect(await bash(hooks, "python3 build_docs.py")).toBe("PASS")
})

test("S3 (AC5): revisor caido, tier 3 rechaza y tier 1 permite", async () => {
  const root = await workspace("feature/x")
  process.env.SAVIA_ACTION_REVIEW_CMD = "sleep 10"
  process.env.SAVIA_ACTION_REVIEW_TIMEOUT = "1"
  process.env.SAVIA_ACTION_REVIEW = "on"
  process.env.SAVIA_ACTION_REVIEW_CONFIRMED = "1"
  const hooks = await plugin(root)
  process.env.SAVIA_RISK_TIER = "3"
  expect(await bash(hooks, "python3 build_docs.py")).toContain("fail-closed")
  process.env.SAVIA_RISK_TIER = "1"
  expect(await bash(hooks, "python3 build_docs.py again")).toBe("PASS")
})

test("S2: el presupuesto llega al prompt como parte sintetica N1", async () => {
  const root = await workspace("agent/x")
  process.env.SAVIA_TURN_BUDGET = "on"
  process.env.SAVIA_TURN_BUDGET_MAX = "40"
  const hooks = await plugin(root)
  expect(await bash(hooks, "ls", "sb")).toBe("PASS") // cuenta un turno
  const output: any = { message: { id: "msg_1" }, parts: [{ type: "text", text: "hola" }] }
  await hooks["chat.message"]({ sessionID: "sb", agent: "a" }, output)
  const shipped = JSON.stringify(output.parts)
  expect(shipped).toContain("turnos 1/40")
})
