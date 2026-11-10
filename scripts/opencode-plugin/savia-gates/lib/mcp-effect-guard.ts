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
// OpenCode nombra las tools MCP `<servidor>_<tool>` (con el nombre del servidor saneado). Solo se
// reconocen los servidores declarados en opencode.json del proyecto o del usuario; una tool de un
// servidor declarado en otro sitio no se ve (límite declarado en el PR de S1).

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

const WEB: Record<string, string> = { webfetch: "WebFetch", websearch: "WebSearch" }

function sanitize(server: string): string {
  return server.replace(/[^a-zA-Z0-9_-]/g, "_")
}

/** Nombre de la tool en el vocabulario del catálogo (`mcp__<servidor>__<tool>`, WebFetch, WebSearch) o null. */
export function catalogName(tool: string, servers: string[]): string | null {
  if (tool.startsWith("mcp__")) return tool
  if (tool === "WebFetch" || tool === "WebSearch") return tool
  const web = WEB[tool.toLowerCase()]
  if (web) return web
  // El servidor más largo primero: `savia-vaults_x` no debe leerse como servidor `savia`.
  for (const server of [...servers].sort((a, b) => b.length - a.length)) {
    const prefix = `${sanitize(server)}_`
    if (tool.startsWith(prefix) && tool.length > prefix.length) return `mcp__${server}__${tool.slice(prefix.length)}`
  }
  return null
}

function serversIn(file: string): string[] {
  if (!existsSync(file)) return []
  try {
    const mcp = JSON.parse(readFileSync(file, "utf-8"))?.mcp
    return mcp && typeof mcp === "object" && !Array.isArray(mcp) ? Object.keys(mcp) : []
  } catch {
    return []
  }
}

/** Servidores MCP declarados para este proyecto (opencode.json del proyecto, de .opencode/ y del usuario). */
export function mcpServers(root: string): string[] {
  const files = [join(root, "opencode.json"), join(root, ".opencode/opencode.json"),
    join(homedir(), ".config/opencode/opencode.json")]
  return [...new Set(files.flatMap(serversIn))]
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
  const name = catalogName(a.tool, a.servers ?? mcpServers(a.root))
  if (!name) return { decision: "pass", reason: "" }
  const raw = JSON.stringify({ hook_event_name: "PreToolUse", tool_name: name, tool_input: a.args ?? {} })
  return runCore(raw, { root: a.root, coreRoot: a.coreRoot, env: a.env, pinFixed: a.pinFixed })
}
