// CLI de la regla de cúpulas de savia-gates para la prueba de paridad con el hook bash
// (tests/hooks/test-dome-guard-parity.bats). Misma entrada que el hook: el payload PreToolUse por
// stdin y `--root`; imprime {"decision", "reason"}. Corre con bun o con node --experimental-strip-types.
import { readFileSync } from "node:fs"
import { decidePayload } from "../lib/dome-guard.ts"

const argv = process.argv.slice(2)
const root = argv.includes("--root") ? argv[argv.indexOf("--root") + 1] : process.cwd()
// Bytes que no son UTF-8: payload ilegible, como en el núcleo Python.
let raw = ""
try {
  raw = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(readFileSync(0))
} catch {
  raw = ""
}
process.stdout.write(JSON.stringify(decidePayload(raw, root, process.env)) + "\n")
