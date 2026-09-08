// manifest.ts — emits a sibling JSON manifest of registered bindings.
//
// The parity-audit script (SE-077 Slice 2) reads this file to compare against
// .claude/settings.json instead of parsing the TS source. Idempotent.

import type { HookMap } from "./shell-bridge"
import { mkdir, writeFile } from "node:fs/promises"

const MANIFEST_DIR =
  process.env.SAVIA_PLUGIN_DIR ??
  `${process.env.HOME ?? ""}/.savia/opencode/plugins/savia-gates`
const MANIFEST_FILE = `${MANIFEST_DIR}/manifest.json`

export async function writeManifest(hookMap: HookMap): Promise<void> {
  const bindings: Array<{
    claudeHook: string
    event: string
    matcher: string | null
    handler: string
  }> = []
  // Map Claude Code event names → OpenCode plugin handler names. Mirrors the
  // dispatch table in index.ts. A single Claude Code event may map to several
  // OpenCode hook points (e.g. PostCompact fires on `session.compacted` and on
  // `experimental.compaction.autocontinue`; SessionStart/InstructionsLoaded
  // both fire on `session.created`).
  const HANDLERS: Record<string, string[]> = {
    PreToolUse: ["tool.execute.before"],
    PostToolUse: ["tool.execute.after"],
    UserPromptSubmit: ["chat.message"],
    SessionStart: ["event:session.created"],
    InstructionsLoaded: ["event:session.created"],
    SessionEnd: ["event:session.deleted"],
    Stop: ["event:session.stopped"],
    PostCompact: ["event:session.compacted", "experimental.compaction.autocontinue"],
    SubagentStart: ["event:subagent.started"],
    SubagentStop: ["event:subagent.completed"],
    TaskCreated: ["event:task.created"],
    TaskCompleted: ["event:task.completed"],
    PreCompact: ["experimental.session.compacting"],
    FileChanged: ["event:file.edited", "event:file.watcher.updated"],
    CwdChanged: ["shell.env"],
    ConfigChange: ["config"],
    // PostToolUseFailure has no native OpenCode hook point — the hook bash
    // declares its own # opencode-binding: NOT_EXPOSED justification.
  }
  for (const [event, entries] of Object.entries(hookMap)) {
    const eventHandlers = HANDLERS[event]
    if (!eventHandlers) continue
    for (const e of entries) {
      // The parity inventory compares command hook basenames. HTTP Shield
      // hooks have no command basename and are exercised by runtime tests.
      if (e.type !== "command") continue
      // Extract the .sh basename the same way opencode-parity-audit.sh does
      // (regex over the command path), so manifest claudeHook matches the CC
      // binding even when the command carries args like "$CLAUDE_JSON_INPUT".
      const m = /([^/"\s]+\.sh)/.exec(e.command)
      const file = m?.[1] ?? e.command.split("/").pop() ?? e.command
      for (const handler of eventHandlers) {
        bindings.push({
          claudeHook: file,
          event,
          matcher: e.matcher ?? null,
          handler,
        })
      }
    }
  }
  const manifest = {
    spec: "SE-077",
    plugin: "savia-gates",
    generated_at: new Date().toISOString(),
    bindings,
  }
  await mkdir(MANIFEST_DIR, { recursive: true }).catch(() => {})
  await writeFile(MANIFEST_FILE, JSON.stringify(manifest, null, 2)).catch(() => {})
}
