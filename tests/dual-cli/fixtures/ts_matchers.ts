// Evaluates hook matchers with the OpenCode savia-gates matcher (lib/shell-bridge.ts) and prints the
// protected gate paths, so the Python test can compare both cores.
import { matcherApplies } from "../../../scripts/opencode-plugin/savia-gates/lib/shell-bridge"
import { isProtectedPath, PROTECTED_GATE_PATHS } from "../../../scripts/opencode-plugin/savia-gates/lib/hook-vocabulary"

const input: { matchers: { matcher: string; tool: string; command?: string }[]; paths: { path: string; root: string }[] } =
  JSON.parse(await Bun.stdin.text())
const matches = input.matchers.map((c) => {
  const payload = JSON.stringify({ tool_name: c.tool, tool_input: c.command === undefined ? {} : { command: c.command } })
  return matcherApplies(c.matcher, c.tool, payload)
})
const protectedPaths = input.paths.map((p) => isProtectedPath(p.path, p.root))
console.log(JSON.stringify({ matches, protected: protectedPaths, list: PROTECTED_GATE_PATHS }))
