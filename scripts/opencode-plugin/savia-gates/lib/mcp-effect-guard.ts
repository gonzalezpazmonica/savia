// mcp-effect-guard.ts — guard previo de efectos MCP, WebFetch y WebSearch en OpenCode (SE-508 S1).
//
// DUAL_BINDING con el hook de Claude Code `.claude/hooks/mcp-effect-guard.sh`: los dos llaman al mismo
// núcleo, `.claude/hooks/lib/mcp_effect_guard.py`, con el mismo payload PreToolUse. Aquí no se decide
// nada: se traduce el nombre de la tool al vocabulario del catálogo y se lanza el núcleo con
// `--frontend opencode`. Paridad: tests/hooks/test-se508-mcp-guard-parity.bats.
//
// Lo único propio de OpenCode es la delegación en Savia Space (spec, punto 5): el núcleo la aplica si
// recibe `--pin-fixed` (el pin de guards está fijado en ESTE proceso del plugin, guard-pin.ts) y
// SAVIA_GATES_PIN=1 está en el entorno. Nunca para merge ni en un run sin persona.
//
// Falla cerrado: sin python3, sin núcleo, tiempo agotado o salida ilegible → ask (deny sin persona).
// OpenCode nombra las tools MCP `<servidor>_<tool>` (con el nombre del servidor saneado). Los servidores se
// leen de opencode.json y opencode.jsonc (raíz, .opencode/, ~/.config/opencode/) y de OPENCODE_CONFIG. Una tool
// que no es nativa del motor (lista cerrada NATIVE_TOOLS) y no se puede traducir no pasa: llega al núcleo como
// `mcp__opencode-unresolved__<tool>`, sin clasificar → ask (deny sin persona). Fallo cerrado, no fallo abierto.

import { spawn } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

export const MCP_NATIVE_TWIN_HOOKS = ["mcp-effect-guard.sh"]
export const CORE_REL = ".claude/hooks/lib/mcp_effect_guard.py"
/** Más que el máximo del núcleo (3 s ls-remote + 2×6 s fetch) y lo mismo que el `timeout 20` del hook. */
export const CORE_TIMEOUT_MS = 20_000

export interface McpVerdict {
  decision: "pass" | "ask" | "deny"
  reason: string
}

/** Tools del motor que sacan datos fuera: `codesearch` manda la consulta a un servicio externo, como WebSearch. */
const WEB: Record<string, string> = { webfetch: "WebFetch", websearch: "WebSearch", codesearch: "WebSearch" }

/** Tools propias del motor de OpenCode (vocabulario v1, en minúsculas). Fuera de esta lista, todo es candidato a MCP. */
export const NATIVE_TOOLS = new Set(["bash", "edit", "write", "read", "glob", "grep", "list", "ls", "task", "multiedit",
  "notebookedit", "todowrite", "todoread", "patch", "apply_patch", "skill", "question", "lsp", "invalid",
  "batch", "plan_enter", "plan_exit"])
/** Servidor ficticio para tools no nativas que no se pueden atribuir a ningún servidor declarado. */
export const UNRESOLVED_SERVER = "opencode-unresolved"

function sanitize(server: string): string {
  return server.replace(/[^a-zA-Z0-9_-]/g, "_")
}

/**
 * Nombre de la tool en el vocabulario del catálogo (`mcp__<servidor>__<tool>`, WebFetch, WebSearch), o null si es
 * nativa del motor. Una tool no nativa sin servidor reconocible → `mcp__opencode-unresolved__<tool>` (sin clasificar).
 */
export function catalogName(tool: string, servers: string[]): string | null {
  if (tool.startsWith("mcp__")) return tool
  if (tool === "WebFetch" || tool === "WebSearch") return tool
  const lower = tool.toLowerCase()
  if (Object.hasOwn(WEB, lower)) return WEB[lower]
  // Los servidores declarados van antes que la lista nativa: un servidor `apply` con tool `patch` da
  // `apply_patch`, que no debe pasar como nativa. El servidor más largo primero: `savia-vaults_x` no es `savia`.
  for (const server of [...servers].sort((a, b) => b.length - a.length)) {
    const prefix = `${sanitize(server)}_`
    if (tool.startsWith(prefix) && tool.length > prefix.length) return `mcp__${server}__${tool.slice(prefix.length)}`
  }
  if (NATIVE_TOOLS.has(lower)) return null
  return `mcp__${UNRESOLVED_SERVER}__${tool}`
}

/** Índice del primer carácter significativo desde `i` (salta espacios y comentarios). */
function skipBlank(text: string, i: number): number {
  while (i < text.length) {
    if (/\s/.test(text[i])) i++
    else if (text.startsWith("//", i)) {
      while (i < text.length && text[i] !== "\n") i++
    } else if (text.startsWith("/*", i)) {
      const end = text.indexOf("*/", i + 2)
      i = end < 0 ? text.length : end + 2
    } else break
  }
  return i
}

/**
 * JSONC → JSON en un solo recorrido: quita comentarios `//` y `/* *\/` y comas finales antes de `}` o `]`, siempre
 * fuera de cadenas (una cadena con `, ]` o `//` dentro queda intacta).
 */
export function stripJsonc(text: string): string {
  let out = ""
  let i = 0
  while (i < text.length) {
    const c = text[i]
    if (c === '"') {
      let j = i + 1
      while (j < text.length && text[j] !== '"') j += text[j] === "\\" ? 2 : 1
      out += text.slice(i, j + 1)
      i = j + 1
    } else if (text.startsWith("//", i) || text.startsWith("/*", i)) {
      i = skipBlank(text, i)
    } else if (c === "," && (text[skipBlank(text, i + 1)] === "}" || text[skipBlank(text, i + 1)] === "]")) {
      i++
    } else {
      out += c
      i++
    }
  }
  return out
}

function serversIn(file: string): string[] {
  if (!existsSync(file)) return []
  try {
    const mcp = JSON.parse(stripJsonc(readFileSync(file, "utf-8")))?.mcp
    return mcp && typeof mcp === "object" && !Array.isArray(mcp) ? Object.keys(mcp) : []
  } catch {
    return []
  }
}

/**
 * Servidores MCP declarados: opencode.json[c] del proyecto, de .opencode/, del usuario, de OPENCODE_CONFIG_DIR y el
 * de OPENCODE_CONFIG. Un servidor con `enabled: false` cuenta igual: sobra una pregunta, no falta ninguna.
 */
export function mcpServers(root: string, env: Record<string, string | undefined> = process.env): string[] {
  const dirs = [root, join(root, ".opencode"), join(env.HOME || homedir(), ".config/opencode")]
  if (env.OPENCODE_CONFIG_DIR) dirs.push(env.OPENCODE_CONFIG_DIR)
  const files = dirs.flatMap((d) => [join(d, "opencode.json"), join(d, "opencode.jsonc")])
  if (env.OPENCODE_CONFIG) files.push(env.OPENCODE_CONFIG)
  return [...new Set(files.flatMap(serversIn))]
}

/**
 * Entorno para el núcleo en producción: sin las variables de inyección de tests. El motor puede heredar un `.env`
 * del workspace (Bun lo carga), y un agente que lo escriba no debe poder cambiar remoto ni reloj del guard.
 */
export function productionEnv(env: Record<string, string | undefined>): Record<string, string | undefined> {
  const out: Record<string, string | undefined> = {}
  for (const [k, v] of Object.entries(env)) {
    if (k.startsWith("SAVIA_MCP_GUARD_TEST") || k === "BATS_TEST_FILENAME") continue
    out[k] = v
  }
  return out
}

function autonomous(env: Record<string, string | undefined>): boolean {
  return Boolean(env.SAVIA_RUN_ID) || env.SAVIA_AUTONOMOUS_RUN === "1"
}

function failClosed(env: Record<string, string | undefined>, why: string): McpVerdict {
  return { decision: autonomous(env) ? "deny" : "ask", reason: `Guard de efectos: ${why}; no se puede comprobar qué hace la llamada` }
}

/** Lanza el núcleo con el payload tal cual (bytes ilegibles incluidos) y devuelve su decisión. */
export function runCore(raw: string | Uint8Array, o: { root: string; coreRoot?: string; env: Record<string, string | undefined>; pinFixed: boolean }): Promise<McpVerdict> {
  const core = join(o.coreRoot ?? o.root, CORE_REL)
  if (!existsSync(core)) return Promise.resolve(failClosed(o.env, "falta el núcleo del guard"))
  const args = [core, "--root", o.root, "--frontend", "opencode", "--json"]
  if (o.pinFixed) args.push("--pin-fixed")
  return new Promise((resolve) => {
    let out = ""
    let done = false
    const finish = (v: McpVerdict) => {
      if (!done) {
        done = true
        resolve(v)
      }
    }
    let child: ReturnType<typeof spawn>
    try {
      child = spawn("python3", args, { env: o.env as NodeJS.ProcessEnv, stdio: ["pipe", "pipe", "ignore"] })
    } catch {
      return finish(failClosed(o.env, "python3 no disponible"))
    }
    const timer = setTimeout(() => {
      child.kill("SIGKILL")
      finish(failClosed(o.env, "el guard tardó demasiado"))
    }, CORE_TIMEOUT_MS)
    child.on("error", () => {
      clearTimeout(timer)
      finish(failClosed(o.env, "python3 no disponible"))
    })
    child.stdout?.on("data", (d) => (out += d))
    child.on("close", (code) => {
      clearTimeout(timer)
      if (code !== 0) return finish(failClosed(o.env, "el guard falló"))
      try {
        const v = JSON.parse(out)
        if (v && ["pass", "ask", "deny"].includes(v.decision) && typeof v.reason === "string") return finish(v)
      } catch {
        // cae al fallo cerrado
      }
      finish(failClosed(o.env, "el guard devolvió una salida ilegible"))
    })
    child.stdin?.on("error", () => {})
    child.stdin?.end(raw)
  })
}

/** Decisión para una llamada de OpenCode. `tool` en vocabulario v1 (lo normalizan los adaptadores). */
export async function mcpEffectVerdict(a: {
  root: string
  coreRoot?: string
  tool: string
  args: Record<string, unknown> | undefined
  env: Record<string, string | undefined>
  pinFixed: boolean
  servers?: string[]
}): Promise<McpVerdict> {
  const name = catalogName(a.tool, a.servers ?? mcpServers(a.root, a.env))
  if (!name) return { decision: "pass", reason: "" }
  const raw = JSON.stringify({ hook_event_name: "PreToolUse", tool_name: name, tool_input: a.args ?? {} })
  return runCore(raw, { root: a.root, coreRoot: a.coreRoot, env: a.env, pinFixed: a.pinFixed })
}
