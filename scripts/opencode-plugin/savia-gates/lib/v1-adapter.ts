// v1-adapter.ts — OpenCode 1.x (>= 1.18.29 as object, any 1.x as function) binding for savia-gates.
//
// Hooks are returned by string key and receive (input, output). The core lives in gates.ts.

import type { Plugin, PluginInput } from "@opencode-ai/plugin"
import { createGates } from "./gates"

const CONFIG_TIMEOUT_MS = 3000
const INTERNAL_AGENTS = ["title", "summary", "compaction"]

/** Providers of the message's model, the default model, small_model, the agent's model and the models of
 *  the internal agents (title, summary, compaction), which receive the session history. A model that
 *  cannot be resolved, or a config that does not answer in time, counts as "" (unknown, so cloud). */
async function turnProviders(ctx: PluginInput, agent: string | undefined, messageProvider: string | undefined): Promise<string[]> {
  const of = (m: unknown) => (typeof m === "string" && m.includes("/") ? m.split("/")[0] : "")
  try {
    let timer: ReturnType<typeof setTimeout> | undefined
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error("config.get timeout")), CONFIG_TIMEOUT_MS)
    })
    const cfg: any = (await Promise.race([ctx.client.config.get(), timeout]).finally(() => clearTimeout(timer)))?.data ?? {}
    const agentModel = agent ? cfg.agent?.[agent]?.model : undefined
    const out = [of(agentModel ?? cfg.model), of(cfg.small_model ?? cfg.model)]
    for (const a of INTERNAL_AGENTS) {
      const m = cfg.agent?.[a]?.model
      if (m !== undefined) out.push(of(m))
    }
    if (messageProvider !== undefined) out.push(messageProvider)
    return out
  } catch {
    return [""]
  }
}

/**
 * What the user typed. In OpenCode 1.x `output.message` is the message record (no text) and the text is in
 * the `text` parts; serialising the record alone showed the prompt hooks nothing to match against.
 */
export function promptText(output: { message?: unknown; parts?: unknown[] }): string {
  if (typeof output.message === "string") return output.message
  const texts = (output.parts ?? [])
    .filter((p: any) => p?.type === "text" && !p.synthetic && typeof p.text === "string")
    .map((p: any) => p.text as string)
  return texts.length > 0 ? texts.join("\n") : JSON.stringify(output.message)
}

export const SaviaGates: Plugin = async (ctx: PluginInput) => {
  const gates = await createGates({ directory: ctx.directory, worktree: ctx.worktree }, "v1")

  return {
    "tool.execute.before": async (input, output) => {
      const mutated = await gates.beforeTool({
        tool: input.tool,
        args: output.args,
        sessionID: input.sessionID,
        callID: input.callID,
      })
      if (mutated) output.args = mutated
    },

    "tool.execute.after": async (input, output) => {
      await gates.afterTool({
        tool: input.tool,
        args: input.args,
        output: output.output,
        sessionID: input.sessionID,
        callID: input.callID,
      })
    },

    "chat.message": async (input, output) => {
      const contexts = await gates.promptSubmit({
        sessionID: input.sessionID,
        agent: input.agent,
        text: promptText(output),
      })
      if (contexts.length === 0) return
      // Every provider the turn can reach: the message's model and the configured ones (the title
      // and summary go to small_model with the same parts). One unknown or cloud provider is enough.
      const providers = await turnProviders(ctx, input.agent, input.model?.providerID)
      const shipped = await gates.shippableContext(contexts, providers)
      if (shipped) {
        // OpenCode v1.18 Part schema: id must start with "prt_", and the
        // part's messageID MUST reference an existing message row (FK). Only
        // inject when the real message id is available; otherwise skip to
        // avoid a FOREIGN KEY crash on the session.
        const messageID = (output.message as any)?.id ?? (input as any).messageID
        if (typeof messageID === "string" && messageID.startsWith("msg_")) {
          output.parts = output.parts ?? []
          output.parts.push(gates.syntheticPart(input.sessionID, messageID, shipped) as any)
        }
      }
    },

    "permission.ask": async (input, output) => {
      const decision = await gates.permission(input)
      if (decision !== "ask") output.status = decision
    },

    "command.execute.before": async (input) => {
      await gates.commandBefore({ command: input.command, sessionID: input.sessionID, arguments: input.arguments })
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
      for (const t of targets) await gates.fire(t.cc, { event: ev, ...(t.augment?.(ev) ?? {}) })
    },

    "experimental.compaction.autocontinue": async (input) => {
      // Called AFTER compaction succeeds — the PostCompact hook point.
      await gates.compacted(input.sessionID)
    },

    "experimental.session.compacting": async (input) => {
      await gates.compacting(input.sessionID)
    },

    "config": async () => {
      // Config reloaded — the ConfigChange hook point.
      await gates.configChanged()
    },

    "shell.env": async (input) => {
      // CwdChanged hook point: fire when the shell's working directory changes.
      await gates.cwdChanged((input as any).cwd)
    },
  }
}
