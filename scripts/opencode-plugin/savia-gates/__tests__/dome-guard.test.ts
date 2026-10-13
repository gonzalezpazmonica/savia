import { afterEach, expect, test } from "bun:test"
import { chmod, mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises"
import { realpathSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { UNKNOWN_CWD_NOTICE, UNKNOWN_TOOL_NOTICE, decidePayload, domeGuardVerdict, localRegistryPath, parseShell, bashReadsOnly } from "../lib/dome-guard"
import { SaviaGates } from "../index"

// SE-436 S5 DUAL_BINDING: la regla de savia-gates decide igual que el hook dome-guard.sh. Esta suite
// ejecuta la misma tabla que tests/python/test_dome_guard.py; la paridad entre las dos la comprueba
// tests/hooks/test-dome-guard-parity.bats.

const CASES = join(import.meta.dir, "../../../../tests/hooks/fixtures/dome-guard-cases.json")
const dirs: string[] = []
const savedEnv = { ...process.env }

const locked: string[] = []

afterEach(async () => {
  process.env = { ...savedEnv }
  await Promise.all(locked.splice(0).map((p) => chmod(p, 0o755)))
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
  for (const d of c.mkdirs ?? []) await mkdir(join(ws, d), { recursive: true })
  for (const [link, target] of c.links ?? []) await symlink(sub(target, ws), join(ws, link))
  const reg = table.registries[c.registry]
  const base = join(ws, "projects/savia-vaults/savia-vaults.domes.json")
  for (const [key, path] of [["base", base], ["local", localRegistryPath(base)]]) {
    if (key in reg) await writeFile(path, typeof reg[key] === "string" ? reg[key] : JSON.stringify(sub(reg[key], ws)))
  }
  for (const [rel, mode] of c.chmod ?? []) {
    await chmod(join(ws, rel), parseInt(mode, 8))
    locked.push(join(ws, rel))
  }
  return ws
}

function payloadText(c: any, ws: string): string {
  if ("raw" in c) return c.raw
  const payload: Record<string, unknown> = {
    hook_event_name: "PreToolUse", tool_name: c.tool, tool_input: sub(c.input, ws), session_id: "s1",
    cwd: "cwd" in c ? join(ws, c.cwd) : ws,
  }
  if ("ctx" in c) payload.dome_context = c.ctx
  return JSON.stringify(payload)
}

async function runCase(table: any, c: any): Promise<{ decision: string; reason: string }> {
  const ws = await workspace(table, c)
  const env = sub(c.env ?? {}, ws) as Record<string, string>
  return decidePayload(payloadText(c, ws), ws, { SAVIA_SPACE_DOMES_FILE: env.SAVIA_SPACE_DOMES_FILE })
}

test("every shared case gives the expected decision and reason", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  expect(table.cases.length).toBeGreaterThanOrEqual(240)
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

test("review P1s: inline scripts, key=value paths, workdir, session cwd in a dome and the registry itself", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  const ws = await workspace(table, table.cases[0])
  const run = (tool: string, input: unknown, cwd = ws) =>
    decidePayload(JSON.stringify({ tool_name: tool, tool_input: input, cwd }), ws, {}).decision
  expect(run("bash", { command: "bash -c 'echo x > vaults/gallinero/a.md'" })).toBe("ask")
  expect(run("bash", { command: `python3 -c "print(open('vaults/secreta/a').read())"` })).toBe("ask")
  expect(run("bash", { command: "dd if=/dev/zero of=vaults/gallinero/a count=1" })).toBe("ask")
  expect(run("bash", { command: "echo x > a.md", workdir: join(ws, "vaults/gallinero") })).toBe("ask")
  expect(run("bash", { command: "cat x.md", workdir: "vaults/secreta" })).toBe("deny")
  expect(run("bash", { command: "cat a.md" }, join(ws, "vaults/secreta"))).toBe("deny")
  expect(run("bash", { command: "ls" }, join(ws, "src"))).toBe("pass")
  expect(run("write", { filePath: join(ws, "projects/savia-vaults/savia-vaults.domes.local.json") })).toBe("ask")
  expect(run("bash", { command: "echo x | tee -a projects/savia-vaults/savia-vaults.domes.local.json" })).toBe("ask")
  expect(decidePayload("no json", ws, {}).decision).toBe("ask")
})

test("the bridge does not run the bash twin of a native rule again, but runs any other hook", async () => {
  const ws = realpathSync(await mkdtemp(join(tmpdir(), "dome-guard-twin-")))
  dirs.push(ws)
  await mkdir(join(ws, ".claude/hooks"), { recursive: true })
  const blocker = "#!/usr/bin/env bash\ncat >/dev/null\necho BLOQUEADO >&2\nexit 2\n"
  for (const name of ["dome-guard.sh", "x-dome-guard.sh"]) await writeFile(join(ws, ".claude/hooks", name), blocker, { mode: 0o755 })
  const settings = (name: string) => JSON.stringify({ hooks: { PreToolUse: [{ matcher: "Edit", hooks: [
    { type: "command", command: `"$CLAUDE_PROJECT_DIR"/.claude/hooks/${name}` }] }] } })
  process.env.SAVIA_AUDIT_DIR = join(ws, ".audit-test")
  process.env.SAVIA_PLUGIN_DIR = join(ws, ".manifest-test")
  delete process.env.SAVIA_GATES_PIN
  await writeFile(join(ws, ".claude/settings.json"), settings("dome-guard.sh"))
  let hooks: any = await SaviaGates({ $: Bun.$, directory: ws, worktree: ws } as any)
  expect(await before(hooks, "edit", { filePath: join(ws, "a.md") })).toBe("PASS")
  await writeFile(join(ws, ".claude/settings.json"), settings("x-dome-guard.sh"))
  hooks = await SaviaGates({ $: Bun.$, directory: ws, worktree: ws } as any)
  expect(await before(hooks, "edit", { filePath: join(ws, "a.md") })).toContain("BLOQUEADO")
})

test("review P1-S6: moving or deleting an ancestor of a dome or of the registry asks", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  const ws = await workspace(table, table.cases[0])
  const RM = "r" + "m"
  const run = (command: string) =>
    decidePayload(JSON.stringify({ tool_name: "bash", tool_input: { command }, cwd: ws }), ws, {})
  for (const cmd of ["mv vaults /tmp/v", `${RM} -r projects/savia-vaults`, "cd projects && mv savia-vaults old", `git ${RM} -r vaults`]) {
    expect(run(cmd).decision).toBe("ask")
  }
  expect(run("mv projects/savia-vaults /tmp/sv").reason).toContain("registro de cúpulas no lo cambia el motor")
  expect(run("find vaults -delete").decision).toBe("deny")
  for (const cmd of ["mv src/a src/b", `${RM} -r vaults2`, `cd src && ${RM} -r tmp`]) expect(run(cmd).decision).toBe("pass")
})

test("review r3: registry errors other than ENOENT fail closed, and any writer reaching an ancestor asks", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  const ws = await workspace(table, table.cases[0])
  const run = (tool: string, input: unknown) =>
    decidePayload(JSON.stringify({ tool_name: tool, tool_input: input, cwd: ws }), ws, {})
  await chmod(join(ws, "projects/savia-vaults"), 0o000)
  locked.push(join(ws, "projects/savia-vaults"))
  expect(run("read", { filePath: "vaults/secreta/a" })).toEqual(expect.objectContaining({ decision: "ask" }))
  expect(run("read", { filePath: "src/a" }).reason).toContain("ilegible")
  await chmod(join(ws, "projects/savia-vaults"), 0o755)
  await symlink(join(ws, "nada.json"), join(ws, "projects/savia-vaults/savia-vaults.domes.local.json"))
  expect(run("read", { filePath: "src/a" }).reason).toContain("enlace roto")
  await rm(join(ws, "projects/savia-vaults/savia-vaults.domes.local.json"))
  for (const command of ["env mv vaults /tmp/v", "timeout 5 mv projects/savia-vaults /tmp/sv", "bash -c 'mv vaults /tmp/v'",
    "mv v* /tmp/v", "d=vaults; mv $d /tmp/v", "echo vaults | xargs mv -t /tmp", "git clean -fdX", "chmod 000 projects/savia-vaults"]) {
    expect([command, run("bash", { command }).decision]).toEqual([command, "ask"])
  }
  for (const command of ["git add .", "timeout 30 cargo test", 'git commit -m "$msg"']) {
    expect([command, run("bash", { command }).decision]).toEqual([command, "pass"])
  }
  expect(run("mcp__fs__write_file", { file_path: join(ws, "vaults/secreta/a") }).reason).toBe(UNKNOWN_TOOL_NOTICE)
})

test("review r4 P1-C2: a bash call whose directory is unknown always asks, before parsing the command", async () => {
  const table = JSON.parse(await readFile(CASES, "utf-8"))
  const ws = await workspace(table, table.cases[0])
  const run = (payload: unknown) => decidePayload(JSON.stringify(payload), ws, {})
  for (const input of [{ command: "ls", x: 1 }, { command: "cat a.md", chdir: "vaults/secreta" }, { command: "cargo test", workdir: "" },
    { command: "ls", workdir: ["a"] }, { command: "ls", workdir: 7 }, "ls", null]) {
    expect([input, run({ tool_name: "bash", tool_input: input, cwd: ws })]).toEqual([input, { decision: "ask", reason: UNKNOWN_CWD_NOTICE }])
  }
  expect(run({ tool_name: "Bash", tool_input: { command: "ls" } }).reason).toBe(UNKNOWN_CWD_NOTICE)
  expect(run({ tool_name: "Bash", tool_input: { command: "ls" }, cwd: 42 }).reason).toBe(UNKNOWN_CWD_NOTICE)
  expect(run({ tool_name: "Bash", cwd: ws, tool_input: { command: "ls", description: "x", timeout: 5, run_in_background: true,
    dangerouslyDisableSandbox: false } }).decision).toBe("pass")
  expect(run({ tool_name: "Read", tool_input: { file_path: "src/a" } }).decision).toBe("pass")
  // El plugin conoce el directorio de la sesión: sin cwdKnown explícito, una orden normal se analiza.
  expect(domeGuardVerdict({ root: ws, project: ws, tool: "bash", input: { command: "ls" }, env: {} }).decision).toBe("pass")
  expect(domeGuardVerdict({ root: ws, project: ws, tool: "bash", input: { command: "ls", cwd: "src" }, env: {} }).reason).toBe(UNKNOWN_CWD_NOTICE)
})
