// Replays non-tool hook events through the OpenCode savia-gates bridge (lib/shell-bridge.ts), the
// path gates.fire / promptSubmit use. Prints, per event, whether it blocked and the context texts.
import { loadHookMap, runHooksForEvent } from "../../../scripts/opencode-plugin/savia-gates/lib/shell-bridge"

const root = process.env.CLAUDE_PROJECT_DIR!
const corpus: { event: string; payload: Record<string, unknown> }[] = JSON.parse(await Bun.stdin.text())
const map = await loadHookMap(root)
const out: { blocked: boolean; contexts: string[] }[] = []
for (const c of corpus) {
  const r = await runHooksForEvent(root, map, c.event, null, JSON.stringify({ hook_event_name: c.event, ...c.payload }))
  out.push({ blocked: r.blocked, contexts: (r.contexts ?? []).map((x) => x.text) })
}
console.log(JSON.stringify(out))
