// permission.ts — AUTONOMOUS_REVIEWER policy enforcement
//
// Default Claude Code policy: never auto-merge / push --force / approve PR
// from agent/* branches. OpenCode v1 exposes `permission.ask` and v2
// `permission.hook("evaluate")`; both return "deny" deterministically before
// the human is even prompted, instead of trusting the runtime to ask every
// time. No runtime-specific shell helper: `git` runs through node:child_process
// so the same code serves both frontends.

import { execFile } from "node:child_process"

const DESTRUCTIVE_PATTERNS: RegExp[] = [
  /\bgit\s+push\s+--force/i,
  /\bgit\s+push\s+--force-with-lease/i,
  /\bgit\s+reset\s+--hard\b/i,
  /\bgit\s+branch\s+-D\b/i,
  /\bgit\s+rebase\s+-i\b/i,
  /\bgh\s+pr\s+merge\b/i,
  /\bgh\s+pr\s+(approve|review\s+--approve)\b/i,
  /\brm\s+-rf\s+\//i,
]

function detectAgentBranch(projectRoot: string): Promise<boolean> {
  return new Promise((resolve) => {
    execFile("git", ["-C", projectRoot, "symbolic-ref", "--short", "HEAD"], { timeout: 3000 }, (err, stdout) => {
      if (err) return resolve(false)
      const branch = String(stdout ?? "").trim()
      resolve(branch.startsWith("agent/") || branch.startsWith("spec-"))
    })
  })
}

function isDestructive(input: any): boolean {
  // Inputs we get vary across hook signatures; coerce to a single string.
  const candidate =
    typeof input?.command === "string" ? input.command :
    typeof input?.args?.command === "string" ? input.args.command :
    JSON.stringify(input ?? {})
  return DESTRUCTIVE_PATTERNS.some((re) => re.test(candidate))
}

function reviewerConfigured(): boolean {
  // Mirrors pm-config.local.md: AUTONOMOUS_REVIEWER must be set for autonomous mode.
  const v = process.env.AUTONOMOUS_REVIEWER ?? ""
  return v.startsWith("@") && v.length > 1
}

export async function decidePermission(
  projectRoot: string,
  input: any,
): Promise<"allow" | "deny" | "ask"> {
  // Cheap regex first: most permission checks are not destructive and never need the git call.
  if (!isDestructive(input)) return "ask"
  if (!(await detectAgentBranch(projectRoot))) return "ask"
  if (!reviewerConfigured()) return "deny"
  return "deny"  // even with reviewer configured, agent/* never auto-allows destructive ops
}
