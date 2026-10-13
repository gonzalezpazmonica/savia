import { afterEach, expect, test } from "bun:test"
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises"
import { realpathSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { decideDome, domeGuardVerdict, localRegistryPath, parseShell, bashReadsOnly } from "../lib/dome-guard"
import { SaviaGates } from "../index"

// SE-436 S5 DUAL_BINDING: la regla de savia-gates decide igual que el hook dome-guard.sh. Esta suite
// ejecuta la misma tabla que tests/python/test_dome_guard.py; la paridad entre las dos la comprueba
// tests/hooks/test-dome-guard-parity.bats.

const CASES = join(import.meta.dir, "../../../../tests/hooks/fixtures/dome-guard-cases.json")
const dirs: string[] = []
const savedEnv = { ...process.env }

afterEach(async () => {
  process.env = { ...savedEnv }
  await Promise.all(dirs.splice(0).map((d) => rm(d, { recursive: true, force: true })))
})

function sub(v: any, ws: string): any {
  if (typeof v === "string") return v.replaceAll("@WS@", ws)
  if (Array.isArray(v)) return v.map((x) => sub(x, ws))
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, sub(x, ws)]))
  return v
}

async function workspace(table: any, c: any): Promise<string> {
  const ws = realpathSync(await mkdtemp(join(tmpdir(), "dome-guard-ts-")))
  dirs.push(ws)
  for (const d of table.dirs) await mkdir(join(ws, d), { recursive: true })
  for (const f of table.files) await writeFile(join(ws, f), "x")
  for (const [link, target] of c.links ?? []) await symlink(sub(target, ws), join(ws, link))
  const reg = table.registries[c.registry]
  const base = join(ws, "projects/savia-vaults/savia-vaults.domes.json")
  for (const [key, path] of [["base", base], ["local", localRegistryPath(base)]]) {
    if (key in reg) await writeFile(path, typeof reg[key] === "string" ? reg[key] : JSON.stringify(sub(reg[key], ws)))
  }
  return ws
}

async function runCase(table: any, c: any): Promise<{ decision: string; reason: string }> {
  const ws = await workspace(table, c)
  const env = sub(c.env ?? {}, ws) as Record<string, string>
  return decideDome({
    root: ws,
    project: ws,
    tool: c.tool,
    input: sub(c.input, ws),
    context: "ctx" in c ? c.ctx : undefined,
    env: { SAVIA_SPACE_DOMES_FILE: env.SAVIA_SPACE_DOMES_FILE },
  })
}

test("every shared case gives the expected decision and reason", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  expect(table.cases.length).toBeGreaterThanOrEqual(100)
  const notices: Record<string, string> = Object.fromEntries(Object.entries(table.notices).map(([k, v]) => [`@${k}@`, v as string]))
  const failures: string[] = []
  for (const c of table.cases) {
    const got = await runCase(table, c)
    if (got.decision !== c.expect) failures.push(`${c.name}: ${got.decision} != ${c.expect} (${got.reason})`)
    if ("reason" in c && got.reason !== (notices[c.reason] ?? c.reason)) failures.push(`${c.name}: motivo ${got.reason}`)
    if ("reason_has" in c && !got.reason.includes(c.reason_has)) failures.push(`${c.name}: sin ${c.reason_has}: ${got.reason}`)
    if ("reason_lacks" in c && got.reason.includes(c.reason_lacks)) failures.push(`${c.name}: con ${c.reason_lacks}`)
  }
  expect(failures).toEqual([])
})

test("read-only bash detection is conservative", () => {
  const ro = (cmd: string) => {
    try {
      return bashReadsOnly(parseShell(cmd))
    } catch {
      return false
    }
  }
  for (const cmd of ["cat a.md", "ls -la /x | head -5", "/usr/bin/grep -r foo .", "cat a | grep x | wc -l", "ls; cat a"]) {
    expect(ro(cmd)).toBe(true)
  }
  for (const cmd of ["cat a > b", "cat a; rm b", "cat a && touch b", "cat <(echo x)", "cat $(echo a)", "python3 -c 1", "cat a\nrm b", "", "cat a | tee b", "tree x"]) {
    expect(ro(cmd)).toBe(false)
  }
  for (const cmd of ["echo 'x", 'echo "x', "echo $(x", "echo `x", "echo ${x", "cat <(x"]) {
    expect(() => parseShell(cmd)).toThrow()
  }
})

test("delegation to Space and mediated mode decide nothing", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  const c = table.cases[0]
  const ws = await workspace(table, c)
  const base = { root: ws, project: ws, tool: "edit", input: { filePath: "vaults/gallinero/a.md" } }
  expect(domeGuardVerdict({ ...base, env: {} }).decision).toBe("ask")
  expect(domeGuardVerdict({ ...base, env: { SAVIA_DOME_GUARD: "space" } }).decision).toBe("pass")
  expect(domeGuardVerdict({ ...base, env: { SAVIA_GATES_PIN: "1" } }).decision).toBe("pass")
})

async function gatedPlugin(ws: string): Promise<any> {
  await mkdir(join(ws, ".claude"), { recursive: true })
  await writeFile(join(ws, ".claude/settings.json"), JSON.stringify({ hooks: {} }))
  process.env.SAVIA_AUDIT_DIR = join(ws, ".audit-test")
  process.env.SAVIA_PLUGIN_DIR = join(ws, ".manifest-test")
  delete process.env.SAVIA_DOME_GUARD
  delete process.env.SAVIA_GATES_PIN
  delete process.env.SAVIA_SPACE_DOMES_FILE
  return SaviaGates({ $: Bun.$, directory: ws, worktree: ws } as any)
}

async function before(hooks: any, tool: string, args: Record<string, unknown>): Promise<string> {
  try {
    await hooks["tool.execute.before"]({ tool, sessionID: "s", callID: "c" }, { args })
    return "PASS"
  } catch (e) {
    return String(e)
  }
}

test("savia-gates enforces the rule in tool.execute.before, also on the sandbox-wrapped command", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  const ws = await workspace(table, table.cases[0])
  const hooks = await gatedPlugin(ws)
  const write = await before(hooks, "edit", { filePath: join(ws, "vaults/gallinero/a.md") })
  expect(write).toContain("DOME_ASK")
  expect(write).toContain("Guardar como nota")
  expect(await before(hooks, "read", { filePath: join(ws, "vaults/secreta/a.md") })).toContain("DOME_DENY")
  expect(await before(hooks, "edit", { filePath: join(ws, "src/a.rs") })).toBe("PASS")
  expect(await before(hooks, "bash", { command: "cargo test" })).toBe("PASS")
  const wrapped = `bwrap --ro-bind / / -- bash -c 'echo x > vaults/gallinero/a.md'`
  expect(await before(hooks, "bash", { command: wrapped })).toContain("DOME_ASK")
})
