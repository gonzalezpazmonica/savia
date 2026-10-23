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

// Start of a real git command: at the beginning of a line, after a separator, inside a subshell or
// inside `bash -c "…"`/`sh -c '…'`/`eval`, with what may precede it (VAR=value, env, command, sudo, nohup,
// time, exec, then, do, if, xargs, timeout N, nice, !, {) and git global options (-C dir, -c key=value,
// --no-pager…). A mention inside a message or an echo does not match.
// Flag m: `^` matches at every line start, like the bash hook's grep (one line at a time).
const GIT_AT =
  String.raw`(?:^|[;&|(\x60]|\$\(|\b(?:(?:ba|z|da|k)?sh\s+-c|eval)\s+["']?)\s*` +
  String.raw`(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|env|command|sudo|nohup|time|exec|then|do|else|if|elif|while|until|xargs|nice|timeout\s+\S+|!|\{)\s+)*git` +
  String.raw`(?:(?:\s+(?:-C|-c|--git-dir|--work-tree)\s+(?:"[^"]*"|'[^']*'|\S+))|(?:\s+--?[A-Za-z][A-Za-z-]*(?:=\S+)?))*\s+`;
// End of an option or a branch name: whitespace, end of line, separator or closing quote.
const END = String.raw`(?:\s|$|[;&|)"'\x60])`;
const rx = (body: string) => new RegExp(GIT_AT + body, "im");

const FORCE_WITH_LEASE = rx(String.raw`push\s+.*--force-with-lease`);
// Never matches --force-with-lease, so a hit is a real --force/-f even if another push in the command
// uses the lease (SE-453: the lease no longer exempts the whole command).
const BARE_FORCE = rx(String.raw`push\s+(?:[^;&|\n]*\s)?(?:--force|-f)` + END);
// main/master as a destination: a bare word or after `:`, `+` or `/` of a refspec; `main-fix` does not match.
const PUSH_MENTIONS_MAIN = /git\s+push\s+.*(?:^|[\s:+/])(?:main|master)(?:[\s:;&|)"'\x60]|$)/im;

const BLOCK_RULES: Array<{ rx: RegExp; msg: string }> = [
  {
    rx: rx(String.raw`push\s+(?:origin\s+)?(?:main|master)` + END),
    msg: "Cannot push directly to main/master. Use a feature branch and PR.",
  },
  {
    rx: rx(String.raw`commit\s+.*--amend`),
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

  if (BARE_FORCE.test(command)) {
    throw new Error("BLOCKED [force-push]: git push --force blocked. Use --force-with-lease instead.");
  }
  if (FORCE_WITH_LEASE.test(command) && PUSH_MENTIONS_MAIN.test(command)) {
    throw new Error("BLOCKED [force-push]: Cannot force-push to main/master. Create a branch.");
  }
  for (const r of BLOCK_RULES) {
    if (r.rx.test(command)) {
      throw new Error(`BLOCKED [force-push]: ${r.msg}`);
    }
  }
}
