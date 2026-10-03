// savia-gates — OpenCode v1.14 plugin
// Spec: SE-077 (docs/propuestas/SE-077-opencode-replatform-v114.md)
// Doc:  docs/rules/domain/opencode-savia-bridge.md
//
// Strategy: this plugin does NOT re-implement Claude Code hooks. It reads the
// SAME `.claude/settings.json` Claude Code already uses, builds an event→hooks
// map, and delegates to the existing bash files via Bun's `$` shell API.
// Exit code 2 from a hook == block; 0 == pass; JSON on stdout == arg mutation.
// AUTONOMOUS_REVIEWER policy is enforced via `permission.ask` returning
// "deny" for destructive ops on agent/* branches when no human reviewer is on
// the line.

import type { Plugin, PluginInput } from "@opencode-ai/plugin"
import { randomUUID } from "node:crypto"
import { loadHookMap, runHooksForEvent, sweepOrphanedHooks } from "./lib/shell-bridge"
import { decidePermission } from "./lib/permission"
import { auditLog } from "./lib/audit"
import { guardVariants } from "./lib/sandbox"
import { writeManifest } from "./lib/manifest"
import { patchPaths, pinFor, protectsPath, verifyPin } from "./lib/guard-pin"

function resolveProjectRoot(directory: string | undefined): string {
  if (directory) return directory
  return process.env.PROJECT_ROOT || `${process.env.HOME}/claude`
}

export const SaviaGates: Plugin = async (ctx: PluginInput) => {
  const { $, directory } = ctx
  const root = resolveProjectRoot(directory)
  const hookMap = await loadHookMap(root)
  let lastCwd: string | null = null
  // T1: con SAVIA_GATES_PIN=1 (Space en modo mediado) los guards se fijan la primera vez que se
  // carga este directorio y se verifican antes de cada decisión (lib/guard-pin.ts).
  const pin = process.env.SAVIA_GATES_PIN === "1" ? await pinFor(root, hookMap) : null

  async function pinViolation(tool: string | null, args: Record<string, unknown> | undefined): Promise<string | null> {
    if (!pin) return null
    const changed = await verifyPin(pin)
    if (changed.length > 0) {
      await auditLog({ event: "guards-modified", root, changed: changed.slice(0, 20) })
      return `GUARDS_MODIFIED: ${changed.slice(0, 5).join(", ")}${changed.length > 5 ? ` (+${changed.length - 5})` : ""} — reinicia el motor desde una copia de confianza`
    }
    const targets: string[] = []
    for (const k of ["filePath", "file_path", "path"]) {
      if (typeof args?.[k] === "string") targets.push(args[k] as string)
    }
    if (typeof args?.patchText === "string") targets.push(...patchPaths(args.patchText as string))
    const hit = tool && tool !== "bash" ? targets.find((t) => protectsPath(pin, root, t)) : undefined
    if (hit) {
      await auditLog({ event: "guard-protected", tool, path: hit })
      return `GUARD_PROTECTED: ${hit}`
    }
    return null
  }

  await writeManifest(hookMap)
  await auditLog({ event: "plugin-loaded", root, events: Object.keys(hookMap).length })

  // Self-heal: kill hook processes left behind by dead opencode instances
  // and remove their stale payload files (see SE-077 process-leak fix).
  void sweepOrphanedHooks()
      .then((r) => {
        if (r.killed > 0 || r.removed > 0) {
          return auditLog({ event: "heal-sweep-done", killed: r.killed, removed: r.removed })
        }
      })
      .catch(() => {})

  return {
    "tool.execute.before": async (input, output) => {
      const pinned = await pinViolation(input.tool, output.args)
      if (pinned) throw new Error(`savia-gates: ${pinned}`)
      // A sandbox plugin may already have wrapped the command: hooks see the
      // original and the unwrapped form, and any block wins (lib/sandbox.ts).
      const variants = guardVariants(input.tool, output.args)
      let mutated: Record<string, unknown> | undefined
      for (const [n, toolInput] of variants.entries()) {
        const payload = JSON.stringify({
          hook_event_name: "PreToolUse",
          tool_name: input.tool,
          tool_input: toolInput,
          session_id: input.sessionID,
          call_id: input.callID,
        })
        const result = await runHooksForEvent(root, hookMap, "PreToolUse", input.tool, payload)
        if (result.blocked) {
          await auditLog({ event: "tool-blocked", tool: input.tool, reason: result.stderr, unwrapped: n > 0 })
          throw new Error(`savia-gates: ${result.stderr || "PreToolUse blocked"}`)
        }
        // Mutations only apply to the args OpenCode will actually run.
        if (n === 0 && result.mutatedArgs) mutated = result.mutatedArgs
      }
      if (mutated) output.args = mutated
    },

    "tool.execute.after": async (input, output) => {
      const payload = JSON.stringify({
        hook_event_name: "PostToolUse",
        tool_name: input.tool,
        tool_input: input.args,
        tool_output: output.output,
        session_id: input.sessionID,
        call_id: input.callID,
      })
      const result = await runHooksForEvent(root, hookMap, "PostToolUse", input.tool, payload)
      if (result.blocked) {
        await auditLog({ event: "post-hook-warning", tool: input.tool, reason: result.stderr })
      }
    },

    "chat.message": async (input, output) => {
      const pinned = await pinViolation(null, undefined)
      if (pinned) throw new Error(`savia-gates: prompt blocked — ${pinned}`)
      const payload = JSON.stringify({
        hook_event_name: "UserPromptSubmit",
        session_id: input.sessionID,
        agent: input.agent,
        prompt_text: typeof output.message === "string" ? output.message : JSON.stringify(output.message),
      })
      const result = await runHooksForEvent(root, hookMap, "UserPromptSubmit", null, payload)
      if (result.blocked) {
        await auditLog({ event: "prompt-blocked", reason: result.stderr })
        throw new Error(`savia-gates: prompt blocked — ${result.stderr}`)
      }
      if (result.injectedContext) {
        // OpenCode v1.18 Part schema: id must start with "prt_", and the
        // part's messageID MUST reference an existing message row (FK). Only
        // inject when the real message id is available; otherwise skip to
        // avoid a FOREIGN KEY crash on the session.
        const messageID = (output.message as any)?.id ?? input.messageID
        if (typeof messageID === "string" && messageID.startsWith("msg_")) {
          output.parts = output.parts ?? []
          output.parts.push({
            id: `prt_${randomUUID()}`,
            sessionID: input.sessionID,
            messageID,
            type: "text",
            text: result.injectedContext,
            synthetic: true,
          })
        }
      }
    },

    "permission.ask": async (input, output) => {
      if (await pinViolation(null, undefined)) {
        output.status = "deny"
        return
      }
      const decision = await decidePermission($, root, input)
      if (decision !== "ask") {
        output.status = decision
        await auditLog({ event: "permission-decision", decision, tool: (input as any).tool ?? "unknown" })
      }
    },

    "command.execute.before": async (input, output) => {
      const pinned = await pinViolation(null, undefined)
      if (pinned) throw new Error(`savia-gates: command ${input.command} blocked — ${pinned}`)
      // Slash commands are gated through the same PreToolUse pipeline so
      // credential-leak / branch-safety checks apply uniformly.
      const payload = JSON.stringify({
        hook_event_name: "CommandExecuteBefore",
        command: input.command,
        session_id: input.sessionID,
        arguments: input.arguments,
      })
      const result = await runHooksForEvent(root, hookMap, "PreToolUse", null, payload)
      if (result.blocked) {
        throw new Error(`savia-gates: command ${input.command} blocked — ${result.stderr}`)
      }
    },

    "event": async (input) => {
      // Map OpenCode generic events onto Claude Code categories.
      const ev = (input as any).event
      if (!ev || typeof ev.type !== "string") return
      const map: Record<string, Array<{ cc: string; augment?: (e: any) => Record<string, unknown> }>> = {
        "session.created": [{ cc: "SessionStart" }, { cc: "InstructionsLoaded", augment: () => ({
          file_path: "AGENTS.md",
          memory_type: "instructions",
          load_reason: "session.created",
        }) }],
        "session.deleted": [{ cc: "SessionEnd" }],
        "session.stopped": [{ cc: "Stop" }],
        "session.compacted": [{ cc: "PostCompact" }],
        "subagent.completed": [{ cc: "SubagentStop" }],
        "subagent.started": [{ cc: "SubagentStart" }],
        "task.created": [{ cc: "TaskCreated" }],
        "task.completed": [{ cc: "TaskCompleted" }],
        "file.edited": [{ cc: "FileChanged", augment: (e: any) => ({ file_path: e?.properties?.file ?? "" }) }],
        "file.watcher.updated": [{ cc: "FileChanged", augment: (e: any) => ({ file_path: e?.properties?.file ?? "", watcher_event: e?.properties?.event ?? "" }) }],
      }
      const targets = map[ev.type]
      if (!targets) return
      for (const t of targets) {
        const payload = JSON.stringify({ hook_event_name: t.cc, event: ev, ...(t.augment?.(ev) ?? {}) })
        await runHooksForEvent(root, hookMap, t.cc, null, payload).catch(() => {})
      }
    },

    "experimental.compaction.autocontinue": async (input, _output) => {
      // Called AFTER compaction succeeds — the PostCompact hook point.
      const payload = JSON.stringify({ hook_event_name: "PostCompact", session_id: input.sessionID })
      await auditLog({ event: "session-compacted", session_id: input.sessionID }).catch(() => {})
      await runHooksForEvent(root, hookMap, "PostCompact", null, payload).catch(() => {})
    },

    "experimental.session.compacting": async (input, _output) => {
      const payload = JSON.stringify({ hook_event_name: "PreCompact", session_id: input.sessionID })
      await auditLog({ event: "session-compacting", session_id: input.sessionID }).catch(() => {})
      await runHooksForEvent(root, hookMap, "PreCompact", null, payload).catch(() => {})
    },

    "config": async (input) => {
      // Config reloaded — the ConfigChange hook point.
      const payload = JSON.stringify({
        hook_event_name: "ConfigChange",
        source: "opencode-config",
        file_path: `${root}/opencode.json`,
      })
      await runHooksForEvent(root, hookMap, "ConfigChange", null, payload).catch(() => {})
    },

    "shell.env": async (input, _output) => {
      // CwdChanged hook point: fire when the shell's working directory changes.
      const cwd = (input as any).cwd
      if (typeof cwd === "string" && cwd !== lastCwd) {
        lastCwd = cwd
        const payload = JSON.stringify({ hook_event_name: "CwdChanged", cwd })
        await runHooksForEvent(root, hookMap, "CwdChanged", null, payload).catch(() => {})
      }
    },
  }
}

export default SaviaGates
