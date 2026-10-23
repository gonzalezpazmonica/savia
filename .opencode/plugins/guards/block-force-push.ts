// block-force-push.ts — SPEC-OC-01, SE-453 S2 (paridad con el hook bash)
//
// Blocks destructive git operations: force-push, push to main/master,
// amend, hard reset. Port of `.opencode/hooks/block-force-push.sh`.
// SE-453: the git-command anchor (GIT_AT) is the same as in the bash hook, so
// `git -C dir push --force` and `git commit --amend` block in both bindings.
// Checked against the bash hook with the same inputs in tests/test-gate-result-contract.bats.
//
// Reference: docs/rules/domain/autonomous-safety.md
// Reference: docs/rules/domain/critical-rules-extended.md (Rule 13)

import { extractToolName, extractCommand, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";

// Start of a real git command: at the beginning, after a separator or inside a subshell, with what may
// precede it (VAR=value, env, command, sudo, nohup, time, exec) and git global options
// (-C dir, -c key=value, --no-pager…). A mention inside a message or an echo does not match.
const GIT_AT =
  String.raw`(?:^|[;&|(\x60]|\$\()\s*(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|env|command|sudo|nohup|time|exec)\s+)*git` +
  String.raw`(?:(?:\s+(?:-C|-c|--git-dir|--work-tree)\s+(?:"[^"]*"|'[^']*'|\S+))|(?:\s+--?[A-Za-z][A-Za-z-]*(?:=\S+)?))*\s+`;
const rx = (body: string) => new RegExp(GIT_AT + body, "i");
// One shell word, possibly with quoted runs: an --amend inside -m "…" or after a separator does not match.
// git accepts unique prefixes of long options, so --am, --ame and --amen are --amend too.
const ARG = String.raw`(?:"[^"]*"|'[^']*'|[^\s;&|()"'])+`;

const FORCE_WITH_LEASE = rx(String.raw`push\s+.*--force-with-lease`);
const BARE_FORCE = rx(String.raw`push\s+(?:[^;&|]*\s)?(?:--force|-f)(?:\s|$)`);
const PUSH_MENTIONS_MAIN = /git\s+push\s+.*\b(?:main|master)\b/i;

const BLOCK_RULES: Array<{ rx: RegExp; msg: string }> = [
  {
    rx: rx(String.raw`push\s+(?:origin\s+)?(?:main|master)(?:\s|$|[;&|)])`),
    msg: "Cannot push directly to main/master. Use a feature branch and PR.",
  },
  {
    rx: rx(String.raw`commit(?:\s+${ARG})*\s+(?:--am(?:e(?:nd?)?)?|"--amend"|'--amend')(?:\s|$|[;&|)])`),
    msg: "git commit --amend can destroy previous commits. Create a new commit.",
  },
  {
    rx: rx(String.raw`reset\s+--hard`),
    msg: "git reset --hard blocked. It destroys working directory changes.",
  },
  // OpenCode-only rules (stricter than the bash hook; kept from SPEC-OC-01).
  {
    rx: /git\s+push\s+.*--delete\s+origin\s+main/i,
    msg: "Cannot delete origin/main branch.",
  },
  {
    rx: /git\s+checkout\s+--force/i,
    msg: "git checkout --force blocked. It destroys working directory changes.",
  },
  {
    rx: /git\s+rebase\s+origin\/(main|master)/i,
    msg: "Cannot rebase onto origin/main or origin/master. Use merge instead.",
  },
];

export async function blockForcePush(input: ToolInput, output: ToolOutput): Promise<void> {
  if (extractToolName(input) !== "bash") return;
  const command = extractCommand(input, output);
  if (!command) return;

  const lease = FORCE_WITH_LEASE.test(command);
  if (BARE_FORCE.test(command) && !lease) {
    throw new Error("BLOCKED [force-push]: git push --force blocked. Use --force-with-lease instead.");
  }
  if (lease && PUSH_MENTIONS_MAIN.test(command)) {
    throw new Error("BLOCKED [force-push]: Cannot force-push to main/master. Create a branch.");
  }
  for (const r of BLOCK_RULES) {
    if (r.rx.test(command)) {
      throw new Error(`BLOCKED [force-push]: ${r.msg}`);
    }
  }
}
