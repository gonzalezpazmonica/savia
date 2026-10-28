// block-force-push.ts — SPEC-OC-01, SE-453 S2 (paridad con el hook bash)
//
// Blocks destructive git operations: force-push, push to main/master,
// amend, hard reset. Port of `.opencode/hooks/block-force-push.sh`.
// SE-453: the git-command anchor (GIT_AT) is the same as in the bash hook, so
// `git -C dir push --force` and `git commit --amend` block in both bindings.
// Checked against the bash hook with the same inputs in tests/test-gate-result-dual-binding.bats.
//
// Reference: docs/rules/domain/autonomous-safety.md
// Reference: docs/rules/domain/critical-rules-extended.md (Rule 13)

import { extractToolName, extractCommand, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";

// Start of a real git command: at the beginning of a line, after a separator, inside a subshell or
// inside `bash -c "…"`/`bash -lc`/`sh -c '…'`/`fish`/`tcsh`/`csh -c`/`script -qc`/`eval`/`su -c`/`ssh host`/`find -exec`, with what may precede it (VAR=value, wrappers such as
// env/command/sudo/doas/pkexec/runuser/nohup/time/exec/xargs/nice/ionice/stdbuf/setsid/timeout/strace/ltrace/unbuffer/watch with their options,
// chroot/flock with their positional argument —
// `sudo -u x`, `env -i`, `timeout -s KILL 30` —, then, do, if, !, {), a path or a backslash before git
// (`/usr/bin/git`, `\git`) and git global options (-C dir, -c key=value, --no-pager…).
// A mention inside a message or an echo does not match. Same grammar as the bash hook's GIT_AT.
// Flag m: `^` matches at every line start, like the bash hook's grep (one line at a time); S is the
// whitespace that does not cross a newline, so no rule spans two lines (grep cannot either).
// No word can be read two ways (a wrapper option argument is never a prefix word, the value of -c/-C
// never starts with `-`): an ambiguous grammar backtracks exponentially in V8 (`nice -n 5 -n 5 …`,
// `git -c -a -c -a …`), which would hang the guard; grep has no such problem.
const S = String.raw`[^\S\n]`;
const NUM = String.raw`[0-9][0-9.]*[smhd]?`;
const WRAPPERS = String.raw`env|command|sudo|doas|pkexec|runuser|nohup|time|exec|xargs|nice|ionice|stdbuf|setsid|timeout|strace|ltrace|unbuffer|watch`;
// Wrappers whose first non-option word is not the command (`chroot /`, `flock file`); their options take no argument,
// so each word has one reading (`flock -w 5 f git` is a known limit).
const POSITIONAL = String.raw`flock|chroot`;
const PREFIX_WORD = String.raw`(?:[A-Za-z_][A-Za-z0-9_]*=|(?:${WRAPPERS}|${POSITIONAL}|then|do|else|if|elif|while|until|${NUM}|!|\{)(?:${S}|$))`;
const WRAPPER = String.raw`(?:${WRAPPERS})(?:${S}+-\S+(?:${S}+(?!${PREFIX_WORD})[^-\s]\S*)?)*`;
// `su [-l|-|user]… -c '…'` and `ssh [-opt [arg]]… host '…'` run a command like `sh -c` does; `-exec`/`-execdir`
// of find start one too. Each option word starts with `-` and each other word does not, so these stay unambiguous.
const SU = String.raw`su(?:${S}+(?:-[A-Za-z-]*|[^-\s"']\S*))*${S}+(?:-[A-Za-z]*c|--command)`;
const SSH = String.raw`ssh(?:${S}+-\S+(?:${S}+[^-\s]\S*)?)*${S}+[^-\s"']\S*`;
const GIT_AT =
  String.raw`(?:^|[;&|(\x60]|\$\(|${S}-exec(?:dir)?${S}|\b(?:(?:(?:ba|z|da|k|t?c|fi)?sh|script)(?:${S}+-[A-Za-z]+)*${S}+-[A-Za-z]*c|eval|${SU}|${SSH})${S}+["']?)${S}*` +
  String.raw`(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|${WRAPPER}|timeout${S}+(?!${NUM}(?:${S}|$))[^-\s]\S*|(?:${POSITIONAL})(?:${S}+-\S+)*${S}+(?!${PREFIX_WORD})[^-\s]\S*|${NUM}|then|do|else|if|elif|while|until|!|\{)${S}+)*` +
  String.raw`(?:\\|\S*/)?git` +
  String.raw`(?:(?:${S}+(?:-C|-c|--git-dir|--work-tree)${S}+(?:"[^"\n]*"|'[^'\n]*'|[^-\s]\S*))|(?:${S}+--?[A-Za-z][A-Za-z-]*(?:=\S+)?))*${S}+`;
// End of an option or a branch name: whitespace, end of line, separator or closing quote.
const END = String.raw`(?:${S}|$|[;&|)"'\x60])`;
// Whitespace inside a character class, without the newline.
const WS = String.raw`\t\v\f\r `;
const rx = (body: string) => new RegExp(GIT_AT + body, "im");

const FORCE_WITH_LEASE = rx(String.raw`push${S}+.*--force-with-lease`);
// Never matches --force-with-lease, so a hit is a real --force/-f even if another push in the command
// uses the lease (SE-453: the lease no longer exempts the whole command). A `+branch` refspec forces too.
// Short flags may be combined (`-fu`, `-uf`): any single-dash cluster of letters with an `f` forces.
// `--mirror` forces too (it force-updates and deletes remote refs).
const BARE_FORCE = rx(String.raw`push${S}+(?:[^;&|\n]*[${WS}])?(?:(?:--force|--mirror|-[A-Za-z]*f[A-Za-z]*)${END}|["']?\+\S)`);
// main/master as a destination: a bare word, after `:`, `+` or a quote, or after refs/heads/, heads/
// (git resolves it to refs/heads/) or refs/remotes/<remote>/; `main-fix` and `feature/main` do not match.
// `--all` updates main without naming it, so with the lease it counts as a push to main.
// Unanchored on purpose (same as IS_PUSH_TO_MAIN in the bash hook): it only counts together with the anchored
// FORCE_WITH_LEASE, so the lease and the mention of main may sit in different commands of one line (safe side).
const PUSH_MENTIONS_MAIN = new RegExp(
  String.raw`git${S}+push${S}+.*(?:^|[${WS}:+"']|(?:refs/|[${WS}:+"'])heads/|refs/remotes/[^/\s]+/)(?:main|master)(?:[${WS}:;&|)"'\x60]|$)` +
    String.raw`|git${S}+push${S}+(?:[^;&|\n]*[${WS}])?--all${END}`,
  "im",
);
// main/master as the destination of a push in this same command (without crossing ;, & or |):
// `origin main`, `HEAD:main`, `+main`, `refs/heads/main`, `heads/main`, `main:main`, `'main'`.
const PUSH_MAIN = String.raw`push${S}+(?:[^;&|\n]*(?:[${WS}:+"']|(?:refs/|[${WS}:+"'])heads/|refs/remotes/[^/\s]+/))?(?:main|master)(?:[${WS}:]|$|[;&|)"'\x60])`;

const BLOCK_RULES: Array<{ rx: RegExp; msg: string }> = [
  {
    rx: rx(PUSH_MAIN),
    msg: "Cannot push directly to main/master. Use a feature branch and PR.",
  },
  {
    rx: rx(String.raw`commit${S}+.*--amend`),
    msg: "git commit --amend can destroy previous commits. Create a new commit.",
  },
  {
    rx: rx(String.raw`reset${S}+--hard`),
    msg: "git reset --hard blocked. It destroys working directory changes.",
  },
  // OpenCode-only rules (stricter than the bash hook; kept from SPEC-OC-01).
  // Floor: the unanchored rules of the TS port in main, so a prefix missing from WRAPPERS (`watch '…'`,
  // `firejail`, `proxychains`…) never blocks less than before SE-453 (security review #1348, round 3, P1-1).
  // Like main, a flag followed by a quote (`echo 'git push --force'`) does not match; unlike main, no rule
  // crosses a newline and `main-fix` does not count as main.
  {
    rx: new RegExp(String.raw`git${S}+push${S}+(?:.*${S})?(?:--force(?!-with-lease)|-f)(?:${S}|$)`, "im"),
    msg: "git push --force blocked. Use --force-with-lease instead.",
  },
  {
    rx: new RegExp(String.raw`git${S}+push${S}+(?:.*${S})?origin${S}+(?:main|master)(?![\w./-])`, "im"),
    msg: "Cannot push directly to origin/main or origin/master. Use a feature branch and PR.",
  },
  {
    rx: new RegExp(String.raw`git${S}+reset${S}+--hard`, "im"),
    msg: "git reset --hard blocked. It destroys working directory changes.",
  },
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
  const raw = extractCommand(input, output);
  if (!raw) return;
  // Line continuations: an odd backslash at the end of a line joins the next one (`git push origin \⏎main`
  // pushes to main). Rules run line by line (flag m), so check the raw lines and also the command with the
  // continuations joined (backslash and newline removed, as the shell does). Same as the bash hook.
  const joined = raw.replace(/(?<!\\)((?:\\\\)*)\\\n/g, "$1");
  const command = joined === raw ? raw : `${raw}\n${joined}`;

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
