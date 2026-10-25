// Replays PreToolUse events through the OpenCode savia-gates production path (lib/hook-vocabulary.ts),
// with the tool names and argument keys OpenCode really passes (`bash`, `write`, `filePath`, `patchText`).
import { loadHookMap } from "../../../scripts/opencode-plugin/savia-gates/lib/shell-bridge"
import { runPreToolUse } from "../../../scripts/opencode-plugin/savia-gates/lib/hook-vocabulary"

const root = process.env.CLAUDE_PROJECT_DIR!
const corpus: { tool: string; input: Record<string, unknown> }[] = JSON.parse(await Bun.stdin.text())
const map = await loadHookMap(root)
// `--reasons`: [blocked, reason] per call, so a test can tell which gate blocked.
const withReasons = process.argv.includes("--reasons")
const out: unknown[] = []
for (const c of corpus) {
  const r = await runPreToolUse(root, map, c.tool, c.input, { cwd: root })
  out.push(withReasons ? [r.blocked, r.reason] : r.blocked)
}
console.log(JSON.stringify(out))
