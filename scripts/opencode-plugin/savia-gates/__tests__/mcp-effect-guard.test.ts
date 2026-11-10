import { afterEach, expect, test } from "bun:test"
import { copyFile, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { execFileSync } from "node:child_process"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { MCP_NATIVE_TWIN_HOOKS, catalogName, mcpEffectVerdict, mcpServers, runCore } from "../lib/mcp-effect-guard"

// SE-508 S1 DUAL_BINDING: la regla de savia-gates llama al mismo núcleo que el hook mcp-effect-guard.sh.
// Aquí se prueba lo que solo existe en OpenCode: el nombre de las tools MCP de OpenCode (`<servidor>_<tool>`),
// la delegación con pin fijado (AC-8) y el fallo cerrado del puente. La paridad de decisiones la comprueba
// tests/hooks/test-se508-mcp-guard-parity.bats.

const REPO = join(import.meta.dir, "../../../..")
// SE508_CORE_SRC: núcleo de origen para los fixtures (por defecto, el del repo). Sirve para ejecutar la suite
// contra un mutante del núcleo (AC-10).
const CORE = process.env.SE508_CORE_SRC ?? join(REPO, ".claude/hooks/lib/mcp_effect_guard.py")
const dirs: string[] = []
const savedEnv = { ...process.env }

afterEach(async () => {
  process.env = { ...savedEnv }
  await Promise.all(dirs.splice(0).map((d) => rm(d, { recursive: true, force: true })))
})

const CATALOG = "mcp__claude_ai_Gmail__send_message: write\nmcp__github__merge_pull_request: merge\nmcp__savia-vaults__vault_read: read_only\n"

/** Árbol con el núcleo real copiado y un remoto bare de fixture con el mismo catálogo. */
async function workspace(): Promise<{ root: string; env: Record<string, string> }> {
  const root = await mkdtemp(join(tmpdir(), "se508-ts-"))
  dirs.push(root)
  await mkdir(join(root, "config"), { recursive: true })
  await mkdir(join(root, ".claude/hooks/lib"), { recursive: true })
  await writeFile(join(root, "config/mcp-effect-catalog.yaml"), CATALOG)
  await writeFile(join(root, "config/webfetch-allow-hosts"), "docs.ejemplo.org\n")
  await copyFile(CORE, join(root, ".claude/hooks/lib/mcp_effect_guard.py"))
  const src = join(root, "src")
  const bare = join(root, "remote.git")
  const git = (...a: string[]) => execFileSync("git", a, { env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" } })
  git("init", "-q", "-b", "main", src)
  await mkdir(join(src, "config"), { recursive: true })
  await mkdir(join(src, ".claude/hooks/lib"), { recursive: true })
  await writeFile(join(src, "config/mcp-effect-catalog.yaml"), CATALOG)
  await writeFile(join(src, "config/webfetch-allow-hosts"), "docs.ejemplo.org\n")
  await copyFile(CORE, join(src, ".claude/hooks/lib/mcp_effect_guard.py"))
  git("-C", src, "add", "-A")
  git("-C", src, "-c", "user.name=t", "-c", "user.email=t@t.test", "commit", "-q", "-m", "fixture")
  git("clone", "-q", "--bare", src, bare)
  git("-C", bare, "config", "uploadpack.allowFilter", "true")
  git("-C", bare, "config", "uploadpack.allowAnySHA1InWant", "true")
  const env = {
    PATH: process.env.PATH ?? "", SAVIA_MCP_GUARD_TEST: "1", BATS_TEST_FILENAME: "mcp-effect-guard.test.ts",
    SAVIA_MCP_GUARD_TEST_REMOTE: `file://${bare}`, SAVIA_MCP_GUARD_TEST_TODAY: "2026-11-10",
    SAVIA_MCP_GUARD_LOG: join(root, "decisions.jsonl"),
  }
  return { root, env }
}

test("catalogName: nombres de OpenCode al vocabulario del catálogo", () => {
  const servers = ["github", "savia-vaults", "savia"]
  expect(catalogName("mcp__github__merge_pull_request", servers)).toBe("mcp__github__merge_pull_request")
  expect(catalogName("github_merge_pull_request", servers)).toBe("mcp__github__merge_pull_request")
  expect(catalogName("savia-vaults_vault_read", servers)).toBe("mcp__savia-vaults__vault_read")
  expect(catalogName("webfetch", servers)).toBe("WebFetch")
  expect(catalogName("websearch", servers)).toBe("WebSearch")
  // negativo: herramientas propias del motor y nombres sin servidor no son MCP
  expect(catalogName("bash", servers)).toBeNull()
  expect(catalogName("edit", servers)).toBeNull()
  expect(catalogName("githubx_merge", servers)).toBeNull()
})

test("mcpServers lee los servidores de opencode.json; ilegible → lista vacía", async () => {
  const root = await mkdtemp(join(tmpdir(), "se508-srv-"))
  dirs.push(root)
  await writeFile(join(root, "opencode.json"), JSON.stringify({ mcp: { github: {}, "savia-vaults": {} } }))
  expect(mcpServers(root).sort()).toEqual(["github", "savia-vaults"])
  await writeFile(join(root, "opencode.json"), "{roto")
  expect(mcpServers(root)).toEqual([])
})

test("el gemelo bash no lo ejecuta el puente (misma decisión dos veces)", () => {
  expect(MCP_NATIVE_TWIN_HOOKS).toContain("mcp-effect-guard.sh")
})

test("sin núcleo: ask; en un run sin persona: deny (falla cerrado)", async () => {
  const root = await mkdtemp(join(tmpdir(), "se508-nocore-"))
  dirs.push(root)
  const raw = JSON.stringify({ tool_name: "mcp__claude_ai_Gmail__send_message", tool_input: {} })
  expect((await runCore(raw, { root, env: { PATH: process.env.PATH ?? "" }, pinFixed: false })).decision).toBe("ask")
  expect((await runCore(raw, { root, env: { PATH: process.env.PATH ?? "", SAVIA_AUTONOMOUS_RUN: "1" }, pinFixed: false })).decision).toBe("deny")
})

test("AC-8: con SAVIA_GATES_PIN=1 y pin fijado no decide para write y deja línea delegated", async () => {
  const { root, env } = await workspace()
  const v = await mcpEffectVerdict({ root, tool: "mcp__claude_ai_Gmail__send_message", args: {}, env: { ...env, SAVIA_GATES_PIN: "1" }, pinFixed: true, servers: [] })
  expect(v.decision).toBe("pass")
  const log = (await readFile(env.SAVIA_MCP_GUARD_LOG, "utf-8")).trim().split("\n").map((l) => JSON.parse(l))
  expect(log.at(-1).decision).toBe("delegated")
})

test("AC-8 negativo: SAVIA_MCP_GUARD=space sin pin fijado → ask", async () => {
  const { root, env } = await workspace()
  const v = await mcpEffectVerdict({ root, tool: "mcp__claude_ai_Gmail__send_message", args: {}, env: { ...env, SAVIA_MCP_GUARD: "space" }, pinFixed: false, servers: [] })
  expect(v.decision).toBe("ask")
})

test("AC-8 negativo: merge con pin fijado y cualquier variable → deny", async () => {
  const { root, env } = await workspace()
  const v = await mcpEffectVerdict({ root, tool: "github_merge_pull_request", args: {}, env: { ...env, SAVIA_GATES_PIN: "1", SAVIA_MCP_GUARD: "space" }, pinFixed: true, servers: ["github"] })
  expect(v.decision).toBe("deny")
  expect(v.reason).toContain("SE-343")
})

test("AC-8b: un run sin persona no delega aunque el pin esté fijado", async () => {
  const { root, env } = await workspace()
  const v = await mcpEffectVerdict({ root, tool: "mcp__claude_ai_Gmail__send_message", args: {}, env: { ...env, SAVIA_GATES_PIN: "1", SAVIA_AUTONOMOUS_RUN: "1" }, pinFixed: true, servers: [] })
  expect(v.decision).toBe("deny")
})

test("tool que no es MCP ni web: no decide (sin lanzar el núcleo)", async () => {
  const v = await mcpEffectVerdict({ root: "/nonexistent", tool: "bash", args: { command: "ls" }, env: {}, pinFixed: false, servers: [] })
  expect(v.decision).toBe("pass")
})
