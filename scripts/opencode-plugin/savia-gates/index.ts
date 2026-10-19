// savia-gates — OpenCode plugin, dual V1/V2
// Spec: SE-077 (docs/propuestas/SE-077-opencode-replatform-v114.md)
// Doc:  docs/rules/domain/opencode-savia-bridge.md
//
// Strategy: this plugin does NOT re-implement Claude Code hooks. It reads the
// SAME `.claude/settings.json` Claude Code already uses, builds an event→hooks
// map, and delegates to the existing bash files (lib/shell-bridge.ts).
// Exit code 2 from a hook == block; 0 == pass; JSON on stdout == arg mutation.
// AUTONOMOUS_REVIEWER policy is enforced via `permission.ask` (V1) and
// `permission.hook("evaluate")` (V2), denying destructive ops on agent/* branches.
//
// One object serves both frontends (OpenCode >= 1.18.29 for V1): V1 calls
// `server()`, V2 reads `id` and calls `setup()`. A V1-only export does not load in V2
// and its guards would be lost without any error, so V2 is first-class here:
//   lib/gates.ts       frontend-agnostic core (decisions)
//   lib/v1-adapter.ts  hooks by key  ("tool.execute.before", "chat.message", …)
//   lib/v2-adapter.ts  hooks per domain (ctx.tool.hook("execute.before"), …)
// The two APIs stay separate on purpose: sharing the export does not translate hooks.

import { SaviaGates } from "./lib/v1-adapter"
import { setupV2 } from "./lib/v2-adapter"

export { SaviaGates }

export const SaviaGatesPlugin = {
  id: "savia-gates",
  setup: setupV2,
  server: (input: any, _options?: unknown) => SaviaGates(input),
}

export default SaviaGatesPlugin
