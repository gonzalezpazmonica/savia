// Replays the AC6 prompt corpus through the OpenCode savia-gates production path: one settings.json
// per case with a `prompt` handler on `Bash(git commit*)`, evaluator from SAVIA_PROMPT_HOOK_CMD.
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { loadHookMap } from "../../../scripts/opencode-plugin/savia-gates/lib/shell-bridge"
import { runPreToolUse } from "../../../scripts/opencode-plugin/savia-gates/lib/hook-vocabulary"

type Case = { command: string; evaluator: string; timeout?: number; model?: string }
const corpus: Case[] = JSON.parse(await Bun.stdin.text())
const out: { action: string; reason: string }[] = []
for (const c of corpus) {
  const root = await mkdtemp(join(tmpdir(), "savia-prompt-replay-"))
  const handler: Record<string, unknown> = { type: "prompt", prompt: "Valida: $ARGUMENTS", timeout: c.timeout ?? 5 }
  if (c.model) handler.model = c.model
  await writeFile(join(root, "settings.json"), JSON.stringify({ hooks: { PreToolUse: [{ matcher: "Bash(git commit*)", hooks: [handler] }] } }))
  process.env.SAVIA_PROMPT_HOOK_CMD = c.evaluator
  const map = await loadHookMap(root, join(root, "settings.json"))
  const r = await runPreToolUse(root, map, "bash", { command: c.command }, { cwd: root })
  out.push({ action: r.blocked ? "deny" : "allow", reason: r.reason })
  await rm(root, { recursive: true, force: true })
}
console.log(JSON.stringify(out))
