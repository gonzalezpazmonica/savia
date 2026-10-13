// CLI de la regla de cúpulas de savia-gates para la prueba de paridad con el hook bash
// (tests/hooks/test-dome-guard-parity.bats). Misma entrada que el hook: el payload PreToolUse por
// stdin y `--root`; imprime {"decision", "reason"}. Corre con bun o con node --experimental-strip-types.
import { readFileSync } from "node:fs"
import { domeGuardVerdict } from "../lib/dome-guard.ts"

/** posixpath.abspath del núcleo Python: el proyecto es el `cwd` del payload, normalizado. */
function abspath(p: string): string {
  const full = p.startsWith("/") ? p : `${process.cwd()}/${p}`
  const initial = full.startsWith("//") && !full.startsWith("///") ? 2 : 1
  const out: string[] = []
  for (const c of full.split("/")) {
    if (c === "" || c === ".") continue
    if (c !== "..") out.push(c)
    else if (out.length > 0) out.pop()
  }
  return "/".repeat(initial) + out.join("/")
}

const argv = process.argv.slice(2)
const root = argv.includes("--root") ? argv[argv.indexOf("--root") + 1] : process.cwd()
let payload: any = {}
try {
  payload = JSON.parse(readFileSync(0, "utf-8") || "{}")
} catch {
  payload = {}
}
if (!payload || typeof payload !== "object" || Array.isArray(payload)) payload = {}
const cwd = typeof payload.cwd === "string" && payload.cwd ? payload.cwd : root
const verdict = domeGuardVerdict({
  root,
  project: abspath(cwd),
  tool: String(payload.tool_name ?? ""),
  input: payload.tool_input,
  context: payload.dome_context,
  env: process.env,
})
process.stdout.write(JSON.stringify(verdict) + "\n")
