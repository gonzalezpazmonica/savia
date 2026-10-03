import { afterEach, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { loadHookMap } from "../lib/shell-bridge"
import { capturePin, patchPaths, pinFor, protectsPath, verifyPin } from "../lib/guard-pin"
import { SaviaGates } from "../index"

// T1: en modo mediado el motor carga los guards del directorio del agente. Con SAVIA_GATES_PIN=1
// quien arranca fija registro y scripts; un cambio posterior bloquea (fail-closed).

const roots: string[] = []
const savedEnv = { ...process.env }

afterEach(async () => {
  process.env = { ...savedEnv }
  await Promise.all(roots.splice(0).map((r) => rm(r, { recursive: true, force: true })))
})

const BLOCKING_GUARD =
  '#!/usr/bin/env bash\nsource "$(dirname "$0")/lib/common.sh"\nin=$(cat)\ncase "$in" in *PROHIBIDO*) echo "PROHIBIDO bloqueado" >&2; exit 2;; esac\nexit 0\n'

async function workspace(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "savia-guard-pin-test-"))
  roots.push(root)
  await mkdir(join(root, ".claude/hooks/lib"), { recursive: true })
  await mkdir(join(root, ".opencode"), { recursive: true })
  await symlink("../.claude/hooks", join(root, ".opencode/hooks"))
  await writeFile(join(root, ".claude/hooks/guard.sh"), BLOCKING_GUARD, { mode: 0o755 })
  await writeFile(join(root, ".claude/hooks/lib/common.sh"), "true\n")
  await writeFile(join(root, "README.md"), "no es un guard\n")
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({
    hooks: { PreToolUse: [{ matcher: "Bash", hooks: [
      { type: "command", command: '"$CLAUDE_PROJECT_DIR"/.opencode/hooks/guard.sh' },
      { type: "command", command: 'bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/falta.sh || true' },
    ] }] },
  }))
  return root
}

async function bash(hooks: any, command: string): Promise<string> {
  try {
    await hooks["tool.execute.before"]({ tool: "bash", sessionID: "s", callID: "c" }, { args: { command } })
    return "PASS"
  } catch (e) {
    return String(e)
  }
}

async function plugin(root: string): Promise<any> {
  process.env.SAVIA_AUDIT_DIR = join(root, ".audit-test")
  process.env.SAVIA_PLUGIN_DIR = join(root, ".manifest-test")
  return SaviaGates({ $: Bun.$, directory: root } as any)
}

test("capturePin + verifyPin: unchanged guards verify clean", async () => {
  const root = await workspace()
  const pin = await capturePin(root, await loadHookMap(root))
  expect(pin.files.size).toBeGreaterThanOrEqual(4)
  expect(await verifyPin(pin)).toEqual([])
})

test("verifyPin detects edited, sourced, added, deleted and newly created registered scripts", async () => {
  const cases: Array<[string, (r: string) => Promise<unknown>]> = [
    ["guard edited", (r) => writeFile(join(r, ".claude/hooks/guard.sh"), "exit 0\n")],
    ["edited through the symlinked dir", (r) => writeFile(join(r, ".opencode/hooks/guard.sh"), "exit 0\n")],
    ["sourced library edited", (r) => writeFile(join(r, ".claude/hooks/lib/common.sh"), "exit 0\n")],
    ["registry edited", (r) => writeFile(join(r, ".claude/settings.json"), "{}")],
    ["file added to a hook dir", (r) => writeFile(join(r, ".claude/hooks/lib/extra.sh"), "true\n")],
    ["guard deleted", (r) => rm(join(r, ".claude/hooks/guard.sh"))],
    ["missing registered script created", (r) => writeFile(join(r, ".claude/hooks/falta.sh"), "exit 0\n")],
  ]
  for (const [label, mutate] of cases) {
    const root = await workspace()
    const pin = await capturePin(root, await loadHookMap(root))
    await mutate(root)
    expect({ label, changed: (await verifyPin(pin)).length > 0 }).toEqual({ label, changed: true })
  }
})

test("verifyPin ignores files outside the guard set (no false block)", async () => {
  const root = await workspace()
  const pin = await capturePin(root, await loadHookMap(root))
  await writeFile(join(root, "README.md"), "cambiado\n")
  await writeFile(join(root, "nuevo.ts"), "export {}\n")
  expect(await verifyPin(pin)).toEqual([])
})

test("protectsPath covers guard files and dirs, relative, absolute and via symlink; rejects others", async () => {
  const root = await workspace()
  const pin = await capturePin(root, await loadHookMap(root))
  for (const p of [".claude/settings.json", ".claude/hooks/guard.sh", ".opencode/hooks/guard.sh",
    ".opencode/hooks/nuevo.sh", ".claude/hooks/../hooks/lib/common.sh", join(root, ".claude/hooks/guard.sh")]) {
    expect({ p, protected: protectsPath(pin, root, p) }).toEqual({ p, protected: true })
  }
  for (const p of ["README.md", "src/x.ts", ".claude/otra.json", ""]) {
    expect({ p, protected: protectsPath(pin, root, p) }).toEqual({ p, protected: false })
  }
})

test("patchPaths extracts every file an apply_patch touches", () => {
  const text = "*** Begin Patch\n*** Update File: a/b.ts\n@@\n-x\n+y\n*** Add File: .claude/hooks/x.sh\n+exit 0\n*** Delete File: c.md\n*** Update File: d.ts\n*** Move to: .claude/settings.json\n*** End Patch"
  expect(patchPaths(text)).toEqual(["a/b.ts", ".claude/hooks/x.sh", "c.md", "d.ts", ".claude/settings.json"])
  expect(patchPaths("")).toEqual([])
})

test("pinFor keeps the first pin for a root across plugin reloads (boundary: instance dispose)", async () => {
  const root = await workspace()
  const first = await pinFor(root, await loadHookMap(root))
  await writeFile(join(root, ".claude/settings.json"), "{}")
  const second = await pinFor(root, await loadHookMap(root))
  expect(second).toBe(first)
  expect((await verifyPin(second)).some((p) => p.endsWith(".claude/settings.json"))).toBe(true)
})

test("pinned plugin: editing the guard in the workspace does not unblock (fail-closed)", async () => {
  const root = await workspace()
  process.env.SAVIA_GATES_PIN = "1"
  const hooks = await plugin(root)
  expect(await bash(hooks, "echo PROHIBIDO")).toContain("PROHIBIDO bloqueado")
  expect(await bash(hooks, "ls")).toBe("PASS")
  await writeFile(join(root, ".claude/hooks/guard.sh"), "#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n")
  expect(await bash(hooks, "echo PROHIBIDO")).toContain("GUARDS_MODIFIED")
  expect(await bash(hooks, "ls")).toContain("GUARDS_MODIFIED")
})

test("pinned plugin: a reload after editing the registry stays blocked", async () => {
  const root = await workspace()
  process.env.SAVIA_GATES_PIN = "1"
  await plugin(root)
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({ hooks: { PreToolUse: [] } }))
  const reloaded = await plugin(root)
  expect(await bash(reloaded, "echo PROHIBIDO")).toContain("GUARDS_MODIFIED")
})

test("pinned plugin: edit, write and apply_patch on a guard are blocked; other files pass", async () => {
  const root = await workspace()
  process.env.SAVIA_GATES_PIN = "1"
  const hooks = await plugin(root)
  const run = async (tool: string, args: Record<string, unknown>) => {
    try {
      await hooks["tool.execute.before"]({ tool, sessionID: "s", callID: "c" }, { args })
      return "PASS"
    } catch (e) {
      return String(e)
    }
  }
  expect(await run("edit", { filePath: join(root, ".claude/hooks/guard.sh") })).toContain("GUARD_PROTECTED")
  expect(await run("write", { filePath: ".claude/settings.json" })).toContain("GUARD_PROTECTED")
  expect(await run("apply_patch", { patchText: "*** Begin Patch\n*** Add File: .opencode/hooks/n.sh\n+x\n*** End Patch" }))
    .toContain("GUARD_PROTECTED")
  expect(await run("edit", { filePath: join(root, "README.md") })).toBe("PASS")
})

test("without SAVIA_GATES_PIN the interactive behaviour is unchanged (empty env: no pin)", async () => {
  const root = await workspace()
  delete process.env.SAVIA_GATES_PIN
  const hooks = await plugin(root)
  await writeFile(join(root, ".claude/hooks/guard.sh"), "#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n")
  expect(await bash(hooks, "echo PROHIBIDO")).toBe("PASS")
})

test("a hook at the project root does not pin the whole root", async () => {
  const root = await mkdtemp(join(tmpdir(), "savia-guard-pin-test-"))
  roots.push(root)
  await mkdir(join(root, ".claude"))
  await writeFile(join(root, "guard.sh"), "exit 0\n")
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({
    hooks: { PreToolUse: [{ hooks: [{ type: "command", command: 'bash "$CLAUDE_PROJECT_DIR"/guard.sh' }] }] },
  }))
  const pin = await capturePin(root, await loadHookMap(root))
  await writeFile(join(root, "trabajo.ts"), "export {}\n")
  expect(await verifyPin(pin)).toEqual([])
  await writeFile(join(root, "guard.sh"), "exit 1\n")
  expect((await verifyPin(pin)).length).toBe(1)
})
