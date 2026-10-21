// Replays a corpus of PreToolUse events through the OpenCode savia-gates shell bridge.
import { loadHookMap, runHooksForEvent } from "../../../scripts/opencode-plugin/savia-gates/lib/shell-bridge"

const root = process.env.CLAUDE_PROJECT_DIR!
const corpus: { tool: string; input: Record<string, unknown> }[] = JSON.parse(await Bun.stdin.text())
const map = await loadHookMap(root)
const out: boolean[] = []
for (const c of corpus) {
  const payload = JSON.stringify({ tool_name: c.tool, tool_input: c.input, cwd: root })
  const r = await runHooksForEvent(root, map, "PreToolUse", c.tool, payload)
  out.push(r.blocked)
}
console.log(JSON.stringify(out))
