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
import { patchPaths, pinFor, protectsPath, verifyPin } from "./lib/guard-pin"
import { REGISTRY, trustedFor, verifyTrusted, wrapCommand } from "./lib/trusted-guards"
import type { TrustedGuards } from "./lib/trusted-guards"
import { resolveProjectRoot } from "./lib/root"

/** Providers the operator declared local (comma-separated). Anything else counts as cloud. */
function localProviders(): Set<string> {
  return new Set((process.env.SAVIA_GATES_LOCAL_PROVIDERS ?? "").split(",").map((p) => p.trim()).filter(Boolean))
}

/** Providers of the message's model, the default model, small_model and the agent's model. A model
 *  that cannot be resolved counts as "" (unknown, so cloud). */
async function turnProviders(ctx: PluginInput, agent: string | undefined, messageProvider: string | undefined): Promise<string[]> {
  const of = (m: unknown) => (typeof m === "string" && m.includes("/") ? m.split("/")[0] : "")
  try {
    const cfg: any = (await ctx.client.config.get())?.data ?? {}
    const agentModel = agent ? cfg.agent?.[agent]?.model : undefined
    const out = [of(agentModel ?? cfg.model), of(cfg.small_model ?? cfg.model)]
    if (messageProvider !== undefined) out.push(messageProvider)
    return out
  } catch {
    return [""]
  }
}

export const SaviaGates: Plugin = async (ctx: PluginInput) => {
  const { $, directory, worktree } = ctx
  const root = resolveProjectRoot(directory, worktree)
  // Las rutas relativas de las herramientas son relativas a la sesión, no a la raíz.
  const cwd = directory || root
  const pinned = process.env.SAVIA_GATES_PIN === "1"
  // T1b: con SAVIA_GATES_PIN=1 (Space en modo mediado) los hooks se ejecutan bajo bwrap desde una
  // copia de confianza de .claude/hooks y scripts/, y el registro se lee de esa copia
  // (lib/trusted-guards.ts). Sin bwrap no hay aislamiento: todo se bloquea.
  let trusted: TrustedGuards | null = null
  let isolationError: string | null = null
  if (pinned) {
    try {
      trusted = await trustedFor(root)
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      isolationError = msg.startsWith("GUARDS_ISOLATION_UNAVAILABLE") ? msg : `GUARDS_ISOLATION_UNAVAILABLE: ${msg}`
      await auditLog({ event: "guards-isolation-unavailable", root, reason: isolationError })
    }
  }
  const hookMap = await loadHookMap(root, trusted ? `${trusted.copy}/${REGISTRY}` : undefined)
  const runOpts = trusted ? { wrap: (command: string) => wrapCommand(trusted as TrustedGuards, command) } : {}
  let lastCwd: string | null = null
  // T1: además los guards se fijan por hash la primera vez que se carga este directorio y se
  // verifican antes de cada decisión (lib/guard-pin.ts); la primera violación se queda.
  const pin = pinned ? await pinFor(root, hookMap) : null

  async function pinViolation(tool: string | null, args: Record<string, unknown> | undefined): Promise<string | null> {
    if (!pin) return null
    if (isolationError) return isolationError
    const already = pin.tripped !== undefined
    let changed = await verifyPin(pin)
    if (changed.length === 0 && trusted) {
      const copyChanged = await verifyTrusted(trusted)
      if (copyChanged.length > 0) changed = pin.tripped = copyChanged
    }
    if (changed.length > 0) {
      // Una sola línea de auditoría por pin: el bloqueo es permanente hasta reiniciar.
      if (!already) await auditLog({ event: "guards-modified", root, changed: changed.slice(0, 20) })
      return `GUARDS_MODIFIED: ${changed.slice(0, 5).join(", ")}${changed.length > 5 ? ` (+${changed.length - 5})` : ""} — reinicia el motor desde una copia de confianza`
    }
    const targets: string[] = []
    for (const k of ["filePath", "file_path", "path"]) {
      if (typeof args?.[k] === "string") targets.push(args[k] as string)
    }
    if (typeof args?.patchText === "string") targets.push(...patchPaths(args.patchText as string))
    const hit = tool && tool !== "bash" ? targets.find((t) => protectsPath(pin, cwd, t)) : undefined
    if (hit) {
      await auditLog({ event: "guard-protected", tool, path: hit })
      return `GUARD_PROTECTED: ${hit}`
    }
    return null
  }

  // La copia solo se verificaba antes del pipeline: una escritura en ella mientras corren los hooks
  // (cientos de ms) llegaba al guard sin detectarse en esa decisión. Cualquier escritura que un hook
  // pudo leer cambia el ctime antes de esta segunda verificación, así que cierra la carrera (#1264).
  async function pinViolationAfterHooks(): Promise<string | null> {
    return pinViolation(null, undefined)
  }

  // manifest.json lo genera la instalación (lib/manifest.ts): cargar no escribe en el directorio
  // del plugin, que forma parte de la huella del motor (pluginSetHash de Savia Space).
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
        const result = await runHooksForEvent(root, hookMap, "PreToolUse", input.tool, payload, runOpts)
        if (result.blocked) {
          await auditLog({ event: "tool-blocked", tool: input.tool, reason: result.stderr, unwrapped: n > 0 })
          throw new Error(`savia-gates: ${result.stderr || "PreToolUse blocked"}`)
        }
        // Mutations only apply to the args OpenCode will actually run.
        if (n === 0 && result.mutatedArgs) mutated = result.mutatedArgs
      }
      const after = await pinViolationAfterHooks()
      if (after) throw new Error(`savia-gates: ${after}`)
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
      const result = await runHooksForEvent(root, hookMap, "PostToolUse", input.tool, payload, runOpts)
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
      const result = await runHooksForEvent(root, hookMap, "UserPromptSubmit", null, payload, runOpts)
      if (result.blocked) {
        await auditLog({ event: "prompt-blocked", reason: result.stderr })
        throw new Error(`savia-gates: prompt blocked — ${result.stderr}`)
      }
      const after = await pinViolationAfterHooks()
      if (after) throw new Error(`savia-gates: prompt blocked — ${after}`)
      // Hook context has no confidentiality level unless the hook declares one. It only goes to a
      // provider the operator declared local (SAVIA_GATES_LOCAL_PROVIDERS); to any other provider,
      // or when the provider is unknown, only context declared N1 goes (fail-closed).
      // Every provider the turn can reach: the message's model and the configured ones (the title
      // and summary go to small_model with the same parts). One unknown or cloud provider is enough.
      const providers = await turnProviders(ctx, input.agent, input.model?.providerID)
      const provider = providers.join(",") || "unknown"
      const allowedLocal = localProviders()
      // Two independent signals; either one saying cloud makes it cloud. Space exports the lane of its
      // engine (SAVIA_GATES_ENGINE_LANE=cloud|local); without Space (plain OpenCode CLI) it is unset and
      // only the declared-local providers can open the local path.
      const lane = process.env.SAVIA_GATES_ENGINE_LANE
      const laneLocal = lane === undefined || lane === "local"
      const local =
        laneLocal && providers.length > 0 && providers.every((p) => p !== "" && allowedLocal.has(p))
      const contexts = result.contexts ?? []
      const allowed = contexts.filter((c) => local || c.level === "N1")
      if (allowed.length < contexts.length) {
        await auditLog({
          event: "prompt-context-withheld",
          provider,
          lane: lane ?? "unset",
          withheld: contexts.length - allowed.length,
        })
      }
      const shipped = allowed.map((c) => c.text).join("\n")
      if (shipped) {
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
            text: shipped,
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
      const result = await runHooksForEvent(root, hookMap, "PreToolUse", null, payload, runOpts)
      if (result.blocked) {
        throw new Error(`savia-gates: command ${input.command} blocked — ${result.stderr}`)
      }
      const after = await pinViolationAfterHooks()
      if (after) throw new Error(`savia-gates: command ${input.command} blocked — ${after}`)
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
        await runHooksForEvent(root, hookMap, t.cc, null, payload, runOpts).catch(() => {})
      }
    },

    "experimental.compaction.autocontinue": async (input, _output) => {
      // Called AFTER compaction succeeds — the PostCompact hook point.
      const payload = JSON.stringify({ hook_event_name: "PostCompact", session_id: input.sessionID })
      await auditLog({ event: "session-compacted", session_id: input.sessionID }).catch(() => {})
      await runHooksForEvent(root, hookMap, "PostCompact", null, payload, runOpts).catch(() => {})
    },

    "experimental.session.compacting": async (input, _output) => {
      const payload = JSON.stringify({ hook_event_name: "PreCompact", session_id: input.sessionID })
      await auditLog({ event: "session-compacting", session_id: input.sessionID }).catch(() => {})
      await runHooksForEvent(root, hookMap, "PreCompact", null, payload, runOpts).catch(() => {})
    },

    "config": async (input) => {
      // Config reloaded — the ConfigChange hook point.
      const payload = JSON.stringify({
        hook_event_name: "ConfigChange",
        source: "opencode-config",
        file_path: `${root}/opencode.json`,
      })
      await runHooksForEvent(root, hookMap, "ConfigChange", null, payload, runOpts).catch(() => {})
    },

    "shell.env": async (input, _output) => {
      // CwdChanged hook point: fire when the shell's working directory changes.
      const cwd = (input as any).cwd
      if (typeof cwd === "string" && cwd !== lastCwd) {
        lastCwd = cwd
        const payload = JSON.stringify({ hook_event_name: "CwdChanged", cwd })
        await runHooksForEvent(root, hookMap, "CwdChanged", null, payload, runOpts).catch(() => {})
      }
    },
  }
}

export default SaviaGates
