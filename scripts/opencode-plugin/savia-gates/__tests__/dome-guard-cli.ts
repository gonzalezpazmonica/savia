// CLI de la regla de cúpulas de savia-gates para la prueba de paridad con el hook bash
// (tests/hooks/test-dome-guard-parity.bats). Misma entrada que el hook: el payload PreToolUse por
// stdin y `--root`; imprime {"decision", "reason"}. Corre con bun o con node --experimental-strip-types.
import { readFileSync } from "node:fs"
import { decidePayload } from "../lib/dome-guard.ts"

const argv = process.argv.slice(2)
const root = argv.includes("--root") ? argv[argv.indexOf("--root") + 1] : process.cwd()
let raw = ""
try {
  raw = readFileSync(0, "utf-8")
} catch {
  raw = ""
}
process.stdout.write(JSON.stringify(decidePayload(raw, root, process.env)) + "\n")
