// gates.ts — frontend-agnostic core of savia-gates.
//
// OpenCode v1 and v2 expose different plugin APIs (v1: hooks by string key with
// (input, output); v2: hooks per domain with one mutable event). The decisions
// are the same, so they live here and index.ts holds the two thin adapters.
// Nothing in this file touches a frontend object: callers pass plain values and
// a throw means "block" (fail closed).

import { randomUUID } from "node:crypto"
import { loadHookMap, runHooksForEvent, sweepOrphanedHooks } from "./shell-bridge"
import type { HookMap } from "./shell-bridge"
import { runPreToolUse } from "./hook-vocabulary"
import { decidePermission } from "./permission"
import { auditLog } from "./audit"
import { guardVariants } from "./sandbox"
import { patchPaths, pinFor, protectsPath, verifyPin } from "./guard-pin"
import { REGISTRY, trustedFor, verifyTrusted, wrapCommand } from "./trusted-guards"
import type { TrustedGuards } from "./trusted-guards"
import { resolveProjectRoot } from "./root"
import { domeGuardVerdict, NATIVE_TWIN_HOOKS, strictest } from "./dome-guard"

/** Providers the operator declared local (comma-separated). Anything else counts as cloud. */
function localProviders(): Set<string> {
  return new Set((process.env.SAVIA_GATES_LOCAL_PROVIDERS ?? "").split(",").map((p) => p.trim()).filter(Boolean))
}

export interface HookContext {
  text: string
  level?: string
}

export interface GatesInit {
  directory?: string | null
  worktree?: string | null
}

export type Flavor = "v1" | "v2"

export async function createGates(init: GatesInit, flavor: Flavor) {
  const root = resolveProjectRoot(init.directory, init.worktree)
  // Las rutas relativas de las herramientas son relativas a la sesión, no a la raíz.
  const cwd = init.directory || root
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
  const hookMap: HookMap = await loadHookMap(root, trusted ? `${trusted.copy}/${REGISTRY}` : undefined)
  // El gemelo bash de una regla nativa (lib/dome-guard.ts) daría la misma decisión otra vez y costaría un
  // proceso por llamada: el puente no lo ejecuta.
  hookMap.PreToolUse = (hookMap.PreToolUse ?? []).filter((h) =>
    !(h.type === "command" && NATIVE_TWIN_HOOKS.some((n) => h.command.endsWith(`/${n}`))))
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
  await auditLog({ event: "plugin-loaded", root, flavor, events: Object.keys(hookMap).length })

  // Self-heal: kill hook processes left behind by dead opencode instances
  // and remove their stale payload files (see SE-077 process-leak fix).
  void sweepOrphanedHooks()
    .then((r) => {
      if (r.killed > 0 || r.removed > 0) {
        return auditLog({ event: "heal-sweep-done", killed: r.killed, removed: r.removed })
      }
    })
    .catch(() => {})

  const fire = (cc: string, payload: Record<string, unknown>) =>
    runHooksForEvent(root, hookMap, cc, null, JSON.stringify({ hook_event_name: cc, ...payload }), runOpts).catch(() => {})

  return {
    root,
    cwd,

    /** PreToolUse. `tool` and `args` use the v1 vocabulary (adapters normalise). Throws to block; returns mutated args. */
    async beforeTool(a: { tool: string; args: Record<string, unknown>; sessionID?: string; callID?: string }) {
      const { tool, args } = a
      const violated = await pinViolation(tool, args)
      if (violated) throw new Error(`savia-gates: ${violated}`)
      // A sandbox plugin may already have wrapped the command: hooks see the
      // original and the unwrapped form, and any block wins (lib/sandbox.ts).
      const variants = guardVariants(tool, args)
      // SE-436 S5: guard de cúpulas nativo, gemelo del hook dome-guard.sh (misma decisión). El motor no
      // pasa `permission.ask` a los plugins, así que `ask` se aplica como bloqueo con el aviso de propuesta.
      const dome = strictest(variants.map((v) =>
        domeGuardVerdict({ root, project: cwd, tool, input: v, env: process.env })))
      if (dome.decision !== "pass") {
        await auditLog({ event: "dome-guard", tool, decision: dome.decision, reason: dome.reason })
        throw new Error(`savia-gates: DOME_${dome.decision.toUpperCase()}: ${dome.reason}`)
      }
      let mutated: Record<string, unknown> | undefined
      for (const [n, toolInput] of variants.entries()) {
        // SE-392: the hooks see the call in Claude Code vocabulary, one event per patched file (lib/hook-vocabulary.ts).
        const result = await runPreToolUse(root, hookMap, tool, toolInput,
          { session_id: a.sessionID, call_id: a.callID, cwd }, runOpts)
        if (result.blocked) {
          await auditLog({ event: "tool-blocked", tool, reason: result.reason, unwrapped: n > 0 })
          throw new Error(`savia-gates: ${result.reason}`)
        }
        // Mutations only apply to the args the frontend will actually run.
        if (n === 0 && result.mutated) mutated = result.mutated
      }
      const after = await pinViolationAfterHooks()
      if (after) throw new Error(`savia-gates: ${after}`)
      return mutated
    },

    /** PostToolUse: audit only, never blocks. */
    async afterTool(a: { tool: string; args: unknown; output: unknown; sessionID?: string; callID?: string }) {
      const payload = JSON.stringify({
        hook_event_name: "PostToolUse",
        tool_name: a.tool,
        tool_input: a.args,
        tool_output: a.output,
        session_id: a.sessionID,
        call_id: a.callID,
      })
      const result = await runHooksForEvent(root, hookMap, "PostToolUse", a.tool, payload, runOpts)
      if (result.blocked) {
        await auditLog({ event: "post-hook-warning", tool: a.tool, reason: result.stderr })
      }
    },

    /** UserPromptSubmit. Throws to block; returns the context the hooks produced (not yet filtered by provider). */
    async promptSubmit(a: { sessionID?: string; agent?: string; text: string }): Promise<HookContext[]> {
      const violated = await pinViolation(null, undefined)
      if (violated) throw new Error(`savia-gates: prompt blocked — ${violated}`)
      const payload = JSON.stringify({
        hook_event_name: "UserPromptSubmit",
        session_id: a.sessionID,
        agent: a.agent,
        prompt_text: a.text,
      })
      const result = await runHooksForEvent(root, hookMap, "UserPromptSubmit", null, payload, runOpts)
      if (result.blocked) {
        await auditLog({ event: "prompt-blocked", reason: result.stderr })
        throw new Error(`savia-gates: prompt blocked — ${result.stderr}`)
      }
      const after = await pinViolationAfterHooks()
      if (after) throw new Error(`savia-gates: prompt blocked — ${after}`)
      return result.contexts ?? []
    },

    /**
     * Hook context has no confidentiality level unless the hook declares one. It only goes to a
     * provider the operator declared local (SAVIA_GATES_LOCAL_PROVIDERS); to any other provider,
     * or when the provider is unknown, only context declared N1 goes (fail-closed).
     * `providers` are every provider the request can reach; one unknown or cloud provider is enough.
     */
    async shippableContext(contexts: HookContext[], providers: string[]): Promise<string> {
      if (contexts.length === 0) return ""
      const provider = providers.join(",") || "unknown"
      const allowedLocal = localProviders()
      // Two independent signals; either one saying cloud makes it cloud. Space exports the lane of its
      // engine (SAVIA_GATES_ENGINE_LANE=cloud|local); without Space (plain OpenCode CLI) it is unset and
      // only the declared-local providers can open the local path.
      const lane = process.env.SAVIA_GATES_ENGINE_LANE
      const laneLocal = lane === undefined || lane === "local"
      const local = laneLocal && providers.length > 0 && providers.every((p) => p !== "" && allowedLocal.has(p))
      const allowed = contexts.filter((c) => local || c.level === "N1")
      if (allowed.length < contexts.length) {
        await auditLog({
          event: "prompt-context-withheld",
          provider,
          lane: lane ?? "unset",
          withheld: contexts.length - allowed.length,
        })
      }
      return allowed.map((c) => c.text).join("\n")
    },

    /** AUTONOMOUS_REVIEWER policy. A pin violation denies everything. */
    async permission(input: unknown): Promise<"allow" | "deny" | "ask"> {
      if (await pinViolation(null, undefined)) return "deny"
      const decision = await decidePermission(root, input)
      if (decision !== "ask") {
        await auditLog({ event: "permission-decision", decision, tool: (input as any)?.tool ?? "unknown", flavor })
      }
      return decision
    },

    /** v1 `command.execute.before`: slash commands go through the same PreToolUse pipeline. */
    async commandBefore(a: { command: string; sessionID?: string; arguments?: unknown }) {
      const violated = await pinViolation(null, undefined)
      if (violated) throw new Error(`savia-gates: command ${a.command} blocked — ${violated}`)
      const payload = JSON.stringify({
        hook_event_name: "CommandExecuteBefore",
        command: a.command,
        session_id: a.sessionID,
        arguments: a.arguments,
      })
      const result = await runHooksForEvent(root, hookMap, "PreToolUse", null, payload, runOpts)
      if (result.blocked) {
        throw new Error(`savia-gates: command ${a.command} blocked — ${result.stderr}`)
      }
      const after = await pinViolationAfterHooks()
      if (after) throw new Error(`savia-gates: command ${a.command} blocked — ${after}`)
    },

    /** Lifecycle categories (Claude Code names) fired by frontend events. Never blocks. */
    fire,

    async compacted(sessionID: string | undefined) {
      await auditLog({ event: "session-compacted", session_id: sessionID }).catch(() => {})
      await fire("PostCompact", { session_id: sessionID })
    },

    async compacting(sessionID: string | undefined) {
      await auditLog({ event: "session-compacting", session_id: sessionID }).catch(() => {})
      await fire("PreCompact", { session_id: sessionID })
    },

    async configChanged() {
      await fire("ConfigChange", { source: "opencode-config", file_path: `${root}/opencode.json` })
    },

    async cwdChanged(next: unknown) {
      if (typeof next === "string" && next !== lastCwd) {
        lastCwd = next
        await fire("CwdChanged", { cwd: next })
      }
    },

    /** Part for the v1 schema: id `prt_…`, FK to an existing message. */
    syntheticPart(sessionID: string, messageID: string, text: string) {
      return { id: `prt_${randomUUID()}`, sessionID, messageID, type: "text", text, synthetic: true }
    },
  }
}

export type Gates = Awaited<ReturnType<typeof createGates>>
