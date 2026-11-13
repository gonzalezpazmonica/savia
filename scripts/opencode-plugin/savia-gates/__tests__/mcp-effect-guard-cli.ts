// CLI del binding OpenCode del guard de efectos (SE-508) para la prueba de paridad con el hook bash
// (tests/hooks/test-se508-mcp-guard-parity.bats). Misma entrada que el hook: el payload PreToolUse por stdin
// tal cual (también si es ilegible) y `--root`; `--pin-fixed` simula el pin fijado en el plugin.
// Imprime {"decision", "reason"}. Corre con bun o con node --experimental-strip-types.
import { readFileSync } from "node:fs"
import { runCore } from "../lib/mcp-effect-guard.ts"

const argv = process.argv.slice(2)
const root = argv.includes("--root") ? argv[argv.indexOf("--root") + 1] : process.cwd()
const coreRoot = argv.includes("--core-root") ? argv[argv.indexOf("--core-root") + 1] : undefined
const raw = readFileSync(0) // bytes tal cual: un payload ilegible llega ilegible al núcleo
const v = await runCore(raw, { root, coreRoot, env: process.env, pinFixed: argv.includes("--pin-fixed") })
process.stdout.write(JSON.stringify(v) + "\n")
