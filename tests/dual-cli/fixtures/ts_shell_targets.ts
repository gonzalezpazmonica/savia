// Runs the shell-target corpus through the OpenCode port (lib/shell-targets.ts), so the Python test can
// compare it with scripts/dual-cli/shell_targets.py case by case.
import { protectedTarget } from "../../../scripts/opencode-plugin/savia-gates/lib/shell-targets"
import { PROTECTED_GATE_PATHS, shellWritesGate } from "../../../scripts/opencode-plugin/savia-gates/lib/hook-vocabulary"

const input: { cases: { command: string }[]; cwd: string; root: string } = JSON.parse(await Bun.stdin.text())
const out = input.cases.map((c) => {
  const view = { tool_name: "Bash", tool_input: { command: c.command }, decomposed: false, aliases: [] }
  const gate = shellWritesGate(view, input.cwd, input.root)
  try {
    return { hit: protectedTarget(c.command, input.cwd, input.root, PROTECTED_GATE_PATHS), invalid: false, gate }
  } catch (e) {
    if (e instanceof Error && e.message === "INVALID_EVENT") return { hit: null, invalid: true, gate }
    throw e
  }
})
console.log(JSON.stringify(out))
