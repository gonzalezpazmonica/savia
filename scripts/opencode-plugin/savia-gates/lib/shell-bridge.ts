// shell-bridge.ts — runs Claude Code bash hooks from OpenCode plugin
//
// Reads .claude/settings.json once, builds an event → hook[] map keyed by
// the same matcher Claude Code uses (tool name regex / glob), then on each
// event invokes the matching hook scripts via Bun.spawn (own process group,
// killable on timeout). This way the EXISTING .sh hooks run unchanged in
// OpenCode.

import { readFile, readdir, readlink, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { auditLog } from "./audit"

export interface HookEntry {
  command: string         // resolved absolute path of the .sh
  matcher?: string         // optional matcher (tool name regex)
  timeout?: number
  async?: boolean
  declared_event: string  // SessionStart / PreToolUse / etc.
  unsupported?: boolean   // a declared hook we cannot safely translate
}

export type HookMap = Record<string, HookEntry[]>

export interface HookResult {
  blocked: boolean
  stderr: string
  stdout: string
  mutatedArgs?: any
  injectedContext?: string
}

export async function loadHookMap(projectRoot: string): Promise<HookMap> {
  const settingsPath = `${projectRoot}/.claude/settings.json`
  const raw = await readFile(settingsPath, "utf-8").catch(() => "")
  if (!raw) return { __configuration__: [{ command: "", declared_event: "configuration", unsupported: true }] }
  let parsed: any = {}
  try {
    parsed = JSON.parse(raw)
  } catch {
    return { __configuration__: [{ command: "", declared_event: "configuration", unsupported: true }] }
  }
  const out: HookMap = {}
  const events = parsed.hooks || {}
  for (const [eventName, entries] of Object.entries(events)) {
    if (!Array.isArray(entries)) continue
    out[eventName] = []
    for (const entry of entries as any[]) {
      const matcher = entry.matcher
      const hooks = entry.hooks || []
      for (const h of hooks) {
        // A configured synchronous gate must never disappear merely because
        // this adapter cannot execute its hook type.  Async hooks are
        // telemetry by contract and remain non-blocking.
        if (h.type !== "command" || typeof h.command !== "string") {
          if (!h.async) out[eventName].push({ command: "", matcher, async: false,
            declared_event: eventName, unsupported: true })
          continue
        }
        const cmd = h.command
          .replace(/"\$CLAUDE_PROJECT_DIR"/g, projectRoot)
          .replace(/\$CLAUDE_PROJECT_DIR/g, projectRoot)
          .replace(/"\$CLAUDE_PLUGIN_ROOT"/g, projectRoot)
          .replace(/\$CLAUDE_PLUGIN_ROOT/g, projectRoot)
          .replace(/"\$\{CLAUDE_PLUGIN_ROOT\}"/g, projectRoot)
          .replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, projectRoot)
          // Only unwrap a command that is ENTIRELY one quoted path (legacy `""/…`
          // form). Never strip quotes that are shell syntax (e.g. a trailing
          // `echo "…"`), or `bash -c` breaks on unbalanced quotes.
          .replace(/^"([^"]*)"$/, "$1")
        out[eventName].push({
          command: cmd,
          matcher,
          timeout: h.timeout,
          async: h.async,
          declared_event: eventName,
        })
      }
    }
  }
  return out
}

function toMatcherRegex(matcher: string): RegExp {
  // Claude Code matchers are simple regex / `*` globs / pipe-separated
  // alternatives. Convert `*` to `.*` and match case-insensitively.
  return new RegExp(matcher.replace(/\*/g, ".*"), "i")
}

function matcherApplies(
  matcher: string | undefined,
  tool: string | null,
  payload?: string,
): boolean {
  if (!matcher) return true
  if (!tool && !payload) return true  // event hooks (UserPromptSubmit, etc.) — no tool axis
  // Prefer a relaxed regex match against the tool name (Claude Code semantics).
  // When the tool name does not match, also try the serialized payload so
  // content-sensitive matchers (`Bash:gh pr create*`, `Bash(gh pr create*)`)
  // can fire — OpenCode passes the tool name lowercased (`bash` vs `Bash`).
  let re: RegExp
  try {
    re = toMatcherRegex(matcher)
  } catch {
    if (tool && matcher === tool) return true
    if (payload && payload.includes(matcher)) return true
    return false
  }
  if (tool && re.test(tool)) return true
  const candidates: string[] = []
  if (payload) candidates.push(payload)
  // Claude Code matchers of the form `Tool(command*)` are matched against a
  // composite "tool name" like `Bash(git commit -m x)` or `Bash:gh pr create`.
  // OpenCode passes the lowercased tool name and the args. Rebuild the
  // composite forms so command-scoped matchers fire.
  let cmd: string | undefined
  try {
    const parsed = JSON.parse(payload ?? "")
    cmd = parsed?.tool_input?.command ?? parsed?.command ?? parsed?.tool_input?.input
    if (typeof cmd !== "string") cmd = undefined
  } catch {
    cmd = undefined
  }
  if (tool && cmd) {
    candidates.push(`${tool}(${cmd})`)
    candidates.push(`${tool}:${cmd}`)
    candidates.push(`${tool} ${cmd}`)
  }
  for (const c of candidates) {
    try {
      if (re.test(c)) return true
    } catch {
      /* already handled */
    }
  }
  return false
}

/** Path for a per-call stdin payload file (local, ephemeral, CRIT-001 safe). */
function stdinPayloadPath(): { path: string; cleanup: () => Promise<void> } {
  const path = `${tmpdir()}/savia-gates-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}.json`
  return { path, cleanup: () => rm(path, { force: true }).catch(() => {}) }
}

/**
 * Spawn a hook via Bun.spawn in its OWN process group (`detached: true`) and
 * feed the payload on stdin from a temporary file.
 *
 * Why not Bun's `$` shell? The bundled `$`/BunShell runtime does not expose a
 * killable subprocess handle, so a hook that hangs (e.g. a `curl` to a down
 * Shield daemon, an `ollama` classify) leaked a `bash` process (plus children)
 * and its pipes/FDs into the opencode process. Over hours that accumulated
 * hundreds of processes + thousands of FDs and practically blocked the session.
 *
 * `detached: true` makes the spawned `bash` a session/process-group leader, so
 * the whole tree can be killed with `process.kill(-pid, SIGKILL)` on timeout
 * (children like `ollama` stay in the group and die too).
 */
/**
 * Per-hook pid registry file. Written next to the payload so the self-heal
 * sweep can kill leaked hooks WITHOUT ptrace: sending a SIGKILL to a same-uid
 * pid is always allowed, but reading another process's `/proc/<pid>/fd/0` is
 * blocked by Yama `ptrace_scope=1`. The registry carries the hook pid itself,
 * so the sweep only needs `process.kill(pid, 0)` (allowed) to test the owner.
 */
function hookRegistryPath(owner: number, hookPid: number): string {
  return `${tmpdir()}/savia-gates-${owner}-hook-${hookPid}.json`
}

async function spawnHook(
  projectRoot: string,
  h: HookEntry,
  payload: string,
  ignoreOutput: boolean,
): Promise<{ proc: any; pid: number; cleanup: () => Promise<void> }> {
  const { path: stdinPath, cleanup } = stdinPayloadPath()
  await writeFile(stdinPath, payload, "utf8")
  // best-effort registry: a failed write must never fail the hook spawn.
  const writeRegistry = (hookPid: number) =>
    writeFile(hookRegistryPath(process.pid, hookPid), JSON.stringify({ hookPid, owner: process.pid }), "utf8")
  try {
    // `bash -c "<command>"` runs the hook command string as shell syntax:
    // handles plain paths (shebang), `bash "..."` prefixes, redirections and
    // `||` chains that appear in settings.json.
    const proc = Bun.spawn({
      cmd: ["bash", "-c", h.command],
      cwd: projectRoot,
      env: { ...process.env, CLAUDE_PROJECT_DIR: projectRoot, CLAUDE_JSON_INPUT: payload },
      stdin: Bun.file(stdinPath),
      stdout: ignoreOutput ? "ignore" : "pipe",
      stderr: ignoreOutput ? "ignore" : "pipe",
      detached: true,
    })
    await writeRegistry(proc.pid).catch(() => {})
    const cleanupAll = async () => {
      await cleanup()
      await rm(hookRegistryPath(process.pid, proc.pid), { force: true }).catch(() => {})
    }
    return { proc, pid: proc.pid, cleanup: cleanupAll }
  } catch (err) {
    await cleanup()
    throw err
  }
}

/** Honours the configured timeout (Claude Code default 5s, cap 30s). */
function timeoutFor(h: HookEntry): number {
  const configured = h.timeout ?? 5000
  return Math.min(configured < 1000 ? configured * 1000 : configured, 30000)
}

/**
 * Kill a hook's whole process group (spawned detached, so pid == pgid). Falls
 * back to killing the single process if the group is already gone.
 */
function killTree(pid: number): void {
  try {
    process.kill(-pid, "SIGKILL")
  } catch {
    try {
      process.kill(pid, "SIGKILL")
    } catch {
      /* already dead */
    }
  }
}

const readStreamText = (s: any): Promise<string> =>
  s ? new Response(s).text().catch(() => "") : Promise.resolve("")

/**
 * Await one hook with a hard timeout. On timeout the process GROUP is killed
 * (SIGKILL) so no `bash`/child leaks into the opencode process.
 *
 * `fireAndForget` (async hooks) spawn with stdout/stderr wired to /dev/null
 * (their output is ignored by contract) and get a generous hard cap so they
 * cannot block the caller nor accumulate FDs in opencode.
 */
async function runHookOnce(
  projectRoot: string,
  h: HookEntry,
  payload: string,
  fireAndForget = false,
): Promise<{ exit: number; stdout: string; stderr: string }> {
  const { proc, pid, cleanup } = await spawnHook(projectRoot, h, payload, fireAndForget)
  const cap = fireAndForget ? 60000 : timeoutFor(h) + 1000
  let timedOut = false
  const killTimer = setTimeout(() => {
    timedOut = true
    killTree(pid)
  }, cap)
  try {
    const [stdout, stderr, exitCode] = await Promise.all([
      readStreamText(proc.stdout),
      readStreamText(proc.stderr),
      proc.exited,
    ])
    if (timedOut) {
      return { exit: BLOCK_EXIT, stdout: "", stderr: `${h.command} timed out after ${cap}ms` }
    }
    return { exit: typeof exitCode === "number" ? exitCode : 0, stdout, stderr }
  } finally {
    clearTimeout(killTimer)
    void cleanup()
  }
}

/**
 * Self-heal sweep (CRIT-001 safe, local only). Removes stale payload files and
 * kills hook processes whose savia-gates stdin payload is owned by a DEAD
 * opencode pid. Run at plugin load so every fresh opencode start cleans the
 * leftovers of crashed/hung previous instances.
 *
 * Processes owned by the CURRENT pid (or any live pid) are never touched.
 */
const PAYLOAD_TMP_RE = /savia-gates-(\d+)-\d+-[a-z0-9]+\.json/

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

const HOOK_REGISTRY_RE = /^savia-gates-(\d+)-hook-(\d+)\.json$/

export async function sweepOrphanedHooks(): Promise<{ killed: number; removed: number }> {
  const dir = tmpdir()
  let removed = 0
  let killed = 0

  await auditLog({ event: "heal-sweep-start" }).catch(() => {})

  let files: string[] = []
  try {
    files = await readdir(dir)
  } catch {
    files = []
  }

  // 1) stale payload files owned by dead pids
  for (const f of files) {
    const m = PAYLOAD_TMP_RE.exec(f)
    if (!m) continue
    const owner = Number(m[1])
    if (owner !== process.pid && !pidAlive(owner)) {
      await rm(`${dir}/${f}`, { force: true }).catch(() => {})
      removed++
    }
  }

  // 2) pid-registry files (ptrace-independent): the hook pid is recorded by
  // spawnHook, so killing a dead owner's leaked hook only needs same-uid
  // signals — no /proc/<pid>/fd readlink (blocked by Yama ptrace_scope=1).
  for (const f of files) {
    const m = HOOK_REGISTRY_RE.exec(f)
    if (!m) continue
    const owner = Number(m[1])
    const hookPid = Number(m[2])
    if (owner === process.pid || pidAlive(owner)) continue
    await rm(`${dir}/${f}`, { force: true }).catch(() => {})
    killTree(hookPid)
    killed++
  }

  // 3) hook processes whose stdin is a savia-gates payload of a dead owner.
  //    Best-effort only: readlink of a foreign /proc/<pid>/fd requires ptrace
  //    (Yama ptrace_scope=1), so this only fires for descendant processes.
  let procs: string[] = []
  try {
    procs = await readdir("/proc")
  } catch {
    procs = []
  }
  for (const p of procs) {
    if (!/^\d+$/.test(p)) continue
    const pid = Number(p)
    if (pid === process.pid) continue
    let fd0 = ""
    try {
      fd0 = await readlink(`/proc/${p}/fd/0`)
    } catch {
      continue
    }
    const m = PAYLOAD_TMP_RE.exec(fd0)
    if (!m) continue
    const owner = Number(m[1])
    if (owner === process.pid || pidAlive(owner)) continue
    killTree(pid)
    killed++
  }

  if (killed > 0 || removed > 0) {
    await auditLog({ event: "heal-sweep", killed, removed }).catch(() => {})
  }
  return { killed, removed }
}

// Exit code 2 == hard block (Claude Code contract). Anything else (including
// hook crashes / timeouts) passes through — logging the cause when present.
const BLOCK_EXIT = 2

export async function runHooksForEvent(
  projectRoot: string,
  hookMap: HookMap,
  event: string,
  tool: string | null,
  payload: string,
): Promise<HookResult> {
  const result: HookResult = { blocked: false, stderr: "", stdout: "" }
  if (hookMap.__configuration__?.length) {
    result.blocked = true
    result.stderr = "INVALID_HOOK_CONFIGURATION"
    return result
  }
  const hooks = hookMap[event] || []
  for (const h of hooks) {
    if (!matcherApplies(h.matcher, tool, payload)) continue
    if (h.unsupported) {
      result.blocked = true
      result.stderr = "UNSUPPORTED_CRITICAL_HOOK"
      return result
    }
    try {
      // `async: true` hooks are fire-and-forget (Claude Code semantics):
      // their exit code and output are ignored, and the caller never waits.
      if (h.async) {
        void runHookOnce(projectRoot, h, payload, true).catch(() => {})
        continue
      }
      const { exit, stdout, stderr } = await runHookOnce(projectRoot, h, payload, false)
      if (exit === BLOCK_EXIT) {
        result.blocked = true
        result.stderr = stderr.trim() || `${h.command} exited ${BLOCK_EXIT}`
        return result
      }
      // Claude Code block contract #2: exit 0 + stdout JSON `{"decision":"block"}`
      // (used by SE-337 commit guard and the Stop gates). Parse BEFORE mutation
      // so a block is not swallowed by the mutatedArgs/injectedContext handling.
      let parsed: any = null
      try {
        parsed = JSON.parse(stdout)
      } catch {
        /* not JSON — ignore stdout */
      }
      if (parsed?.decision === "block") {
        result.blocked = true
        result.stderr = String(parsed.reason ?? "") || `${h.command} blocked via {decision:block}`
        await auditLog({ event: "hook-json-block", command: h.command, reason: result.stderr })
        return result
      }
      // If a hook prints structured JSON on stdout, treat it as arg/context mutation.
      if (parsed) {
        if (parsed.mutatedArgs) result.mutatedArgs = parsed.mutatedArgs
        if (parsed.injectedContext) result.injectedContext = parsed.injectedContext
        if (parsed?.hookSpecificOutput?.additionalContext) {
          result.injectedContext = parsed.hookSpecificOutput.additionalContext
        }
      }
    } catch (err) {
      // Synchronous hook failures are policy uncertainty, not permission.
      result.blocked = true
      result.stderr = String(err) || "HOOK_EXECUTION_FAILED"
      return result
    }
  }
  return result
}
