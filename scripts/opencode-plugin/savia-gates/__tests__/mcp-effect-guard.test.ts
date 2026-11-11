import { afterEach, expect, test } from "bun:test"
import { copyFile, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { execFileSync } from "node:child_process"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { MCP_NATIVE_TWIN_HOOKS, catalogName, mcpEffectVerdict, mcpServers, productionEnv, runCore, stripJsonc } from "../lib/mcp-effect-guard"

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
    SAVIA_MCP_GUARD_TEST_LOG: join(root, "decisions.jsonl"),
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
  // negativo: herramientas propias del motor no son MCP
  expect(catalogName("bash", servers)).toBeNull()
  expect(catalogName("edit", servers)).toBeNull()
  // revisión #1525 P1: una tool no nativa sin servidor reconocible no se ignora; queda sin clasificar
  expect(catalogName("githubx_merge", servers)).toBe("mcp__opencode-unresolved__githubx_merge")
  expect(catalogName("github_merge_pull_request", [])).toBe("mcp__opencode-unresolved__github_merge_pull_request")
  // un nombre que coincide con una propiedad de Object no se toma por tool web
  expect(catalogName("constructor", servers)).toBe("mcp__opencode-unresolved__constructor")
})

test("revisión #1525 P1: servidor no declarado en opencode.json → ask, y deny sin persona (antes pasaba)", async () => {
  const { root, env } = await workspace()
  const v = await mcpEffectVerdict({ root, tool: "github_merge_pull_request", args: {}, env, pinFixed: false, servers: [] })
  expect(v.decision).toBe("ask")
  expect(v.reason).toContain("sin clasificar")
  const auto = await mcpEffectVerdict({ root, tool: "github_merge_pull_request", args: {}, env: { ...env, SAVIA_AUTONOMOUS_RUN: "1" }, pinFixed: false, servers: [] })
  expect(auto.decision).toBe("deny")
})

test("revisión #1525 P1: mcpServers lee opencode.jsonc (comentarios, URLs, comas finales) y OPENCODE_CONFIG", async () => {
  const root = await mkdtemp(join(tmpdir(), "se508-jsonc-"))
  dirs.push(root)
  await writeFile(join(root, "opencode.jsonc"), `{
  // servidores activados desde .opencode/mcp-templates
  "mcp": {
    "github": { "url": "https://api.ejemplo.test/mcp", /* remoto */ "type": "remote", },
  },
}`)
  const extra = join(root, "otro.json")
  await writeFile(extra, JSON.stringify({ mcp: { "savia-vaults": {} } }))
  expect(mcpServers(root, { HOME: root }).sort()).toEqual(["github"])
  expect(mcpServers(root, { HOME: root, OPENCODE_CONFIG: extra }).sort()).toEqual(["github", "savia-vaults"])
  // negativo: sin el fichero de OPENCODE_CONFIG no aparece el servidor
  expect(mcpServers(root, { HOME: root, OPENCODE_CONFIG: join(root, "no-existe.json") })).toEqual(["github"])
})

test("stripJsonc respeta // dentro de cadenas", () => {
  expect(JSON.parse(stripJsonc('{"a": "https://x.test//y", // c\n"b": [1,],}'))).toEqual({ a: "https://x.test//y", b: [1] })
})

test("revisión #1525 P2: stripJsonc no toca comas seguidas de cierre dentro de cadenas", () => {
  expect(JSON.parse(stripJsonc('{"a": "x, ]", "b": "y,}", "c": [1, /* c */ ], }'))).toEqual({ a: "x, ]", b: "y,}", c: [1] })
  // negativo: una coma que no es final se conserva
  expect(JSON.parse(stripJsonc('{"a": [1, 2]}'))).toEqual({ a: [1, 2] })
})

test("revisión #1525 P2: un servidor declarado gana a la lista nativa (apply + patch ≠ apply_patch nativa)", () => {
  expect(catalogName("apply_patch", ["apply"])).toBe("mcp__apply__patch")
  expect(catalogName("plan_enter", ["plan"])).toBe("mcp__plan__enter")
  // negativo: sin ese servidor declarado, la tool nativa sigue sin decisión
  expect(catalogName("apply_patch", ["github"])).toBeNull()
})

test("revisión #1525 P2: codesearch de OpenCode saca la consulta fuera → se trata como WebSearch", () => {
  expect(catalogName("codesearch", [])).toBe("WebSearch")
  expect(catalogName("codesearch", ["github"])).toBe("WebSearch")
})

test("revisión #1525 P2: mcpServers lee OPENCODE_CONFIG_DIR", async () => {
  const root = await mkdtemp(join(tmpdir(), "se508-cfgdir-"))
  dirs.push(root)
  const cfg = join(root, "cfg")
  await mkdir(cfg)
  await writeFile(join(cfg, "opencode.json"), JSON.stringify({ mcp: { gitlab: {} } }))
  expect(mcpServers(root, { HOME: root, OPENCODE_CONFIG_DIR: cfg })).toEqual(["gitlab"])
  // negativo: sin la variable, el directorio no se lee
  expect(mcpServers(root, { HOME: root })).toEqual([])
})

test("revisión #1525 P2: productionEnv quita la inyección de tests y conserva lo demás", () => {
  const e = productionEnv({ PATH: "/bin", SAVIA_MCP_GUARD_TEST: "1", SAVIA_MCP_GUARD_TEST_REMOTE: "file:///x",
    SAVIA_MCP_GUARD_TEST_TODAY: "2026-01-01", BATS_TEST_FILENAME: "x.bats", SAVIA_RUN_ID: "r" })
  expect(e).toEqual({ PATH: "/bin", SAVIA_RUN_ID: "r" })
})

test("mcpServers lee los servidores de opencode.json; ilegible → lista vacía", async () => {
  const root = await mkdtemp(join(tmpdir(), "se508-srv-"))
  dirs.push(root)
  await writeFile(join(root, "opencode.json"), JSON.stringify({ mcp: { github: {}, "savia-vaults": {} } }))
  expect(mcpServers(root, { HOME: root }).sort()).toEqual(["github", "savia-vaults"])
  await writeFile(join(root, "opencode.json"), "{roto")
  expect(mcpServers(root, { HOME: root })).toEqual([])
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
  const log = (await readFile(env.SAVIA_MCP_GUARD_TEST_LOG, "utf-8")).trim().split("\n").map((l) => JSON.parse(l))
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

// Revisión #1525 de seguridad, P1-1: con SAVIA_GATES_PIN=1 el núcleo corría desde el workspace, fuera de bwrap y
// leído de disco después de verificar el pin (el TOCTOU que T1b cierra). Para hacer la carrera determinista, el
// registro no nombra hooks: el pin no fija `.claude/hooks/lib`, igual que el agente que gana la carrera. El núcleo
// de la copia de confianza dice ask; el del workspace, reescrito tras cargar, diría pass.
const STUB = (decision: string) =>
  `import json, sys\nsys.stdin.read()\nprint(json.dumps({"decision": "${decision}", "reason": "núcleo ${decision}"}))\n`

// bwrap de prueba: CI no tiene bwrap (los tests de trusted-guards usan el real). Emula `--ro-bind ORIG DEST`
// sustituyendo DEST por ORIG en la orden; así se comprueba el cableado (orden envuelta + copia montada) sin depender
// del runner. Si gates.ts no envuelve el núcleo, este bwrap no se llama y corre el núcleo del workspace.
const FAKE_BWRAP = [
  "#!/usr/bin/env bash",
  "binds=()",
  "while [ $# -gt 0 ]; do case \"$1\" in",
  "  --dev-bind) shift 3;; --ro-bind) binds+=(\"$2\" \"$3\"); shift 3;; --chdir) shift 2;; --die-with-parent) shift;;",
  "  --) shift; break;; *) exit 99;; esac; done",
  "[ \"$1\" = true ] && exit 0",
  "[ \"$1 $2\" = \"bash -c\" ] || exit 98",
  "cmd=\"$3\"",
  "for ((i=0; i<${#binds[@]}; i+=2)); do cmd=\"${cmd//${binds[i+1]}/${binds[i]}}\"; done",
  "exec bash -c \"$cmd\"",
  "",
].join("\n")

async function pinnedPlugin(): Promise<{ root: string; hooks: any }> {
  const root = await mkdtemp(join(tmpdir(), "se508-pinned-"))
  dirs.push(root)
  await writeFile(join(root, "fake-bwrap"), FAKE_BWRAP, { mode: 0o755 })
  process.env.SAVIA_GATES_BWRAP = join(root, "fake-bwrap")
  await mkdir(join(root, ".claude/hooks/lib"), { recursive: true })
  await mkdir(join(root, "scripts"), { recursive: true })
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({ hooks: {} }))
  await writeFile(join(root, ".claude/hooks/lib/mcp_effect_guard.py"), STUB("ask"))
  process.env.SAVIA_AUDIT_DIR = join(root, ".audit-test")
  process.env.SAVIA_PLUGIN_DIR = join(root, ".manifest-test")
  process.env.SAVIA_GATES_PIN = "1"
  const { SaviaGates } = await import("../index")
  return { root, hooks: await SaviaGates({ $: Bun.$, directory: root } as any) }
}

async function webfetch(hooks: any): Promise<string> {
  try {
    await hooks["tool.execute.before"]({ tool: "webfetch", sessionID: "s", callID: "c" }, { args: { url: "https://x.test/" } })
    return "PASS"
  } catch (e) {
    return String(e)
  }
}

test("revisión #1525 P1-1: con el pin, el núcleo del workspace reescrito tras cargar no se ejecuta (corre la copia)", async () => {
  const { root, hooks } = await pinnedPlugin()
  // control: antes de tocar nada decide el núcleo (ask), no un fallo cerrado
  expect(await webfetch(hooks)).toContain("MCP_ASK: núcleo ask")
  await writeFile(join(root, ".claude/hooks/lib/mcp_effect_guard.py"), STUB("pass"))
  // Sin el arreglo, el plugin lanzaba el núcleo del workspace y la llamada pasaba.
  expect(await webfetch(hooks)).toContain("MCP_ASK: núcleo ask")
})

test("revisión #1525 P1-1 negativo: sin pin, el núcleo es el del workspace (no hay copia que usar)", async () => {
  const { root, hooks } = await pinnedPlugin().then(async (p) => {
    delete process.env.SAVIA_GATES_PIN
    const { SaviaGates } = await import("../index")
    return { root: p.root, hooks: await SaviaGates({ $: Bun.$, directory: p.root } as any) }
  })
  await writeFile(join(root, ".claude/hooks/lib/mcp_effect_guard.py"), STUB("pass"))
  expect(await webfetch(hooks)).toBe("PASS")
})

test("runCore con wrap: lanza el núcleo de <root> a través del envoltorio, con python3 -I y rutas entrecomilladas", async () => {
  const root = await mkdtemp(join(tmpdir(), "se508-wrap 'q-"))
  dirs.push(root)
  await mkdir(join(root, ".claude/hooks/lib"), { recursive: true })
  await writeFile(join(root, ".claude/hooks/lib/mcp_effect_guard.py"), STUB("ask"))
  const seen: string[] = []
  const wrap = (c: string) => (seen.push(c), ["bash", "-c", c])
  const v = await runCore("{}", { root, env: { PATH: process.env.PATH ?? "" }, pinFixed: false, wrap })
  expect(v.reason).toBe("núcleo ask")
  expect(seen).toHaveLength(1)
  expect(seen[0].startsWith("exec python3 -I ")).toBe(true)
})

test("revisión #1525 P2-1: productionEnv quita también el desvío del registro (SAVIA_MCP_GUARD_TEST_LOG)", () => {
  expect(productionEnv({ PATH: "/bin", SAVIA_MCP_GUARD_TEST_LOG: "/tmp/x" })).toEqual({ PATH: "/bin" })
})
