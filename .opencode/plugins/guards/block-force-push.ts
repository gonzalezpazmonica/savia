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
  String.raw`(?:(?:\s+(?:-C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source|--super-prefix)\s+(?:"[^"]*"|'[^']*'|\S+))|(?:\s+--?[A-Za-z][A-Za-z-]*(?:=\S+)?))*\s+`;
const rx = (body: string) => new RegExp(GIT_AT + body, "i");
// SE-453 (review #1355): --amend has to be an argument of its own of that git commit. A shell
// tokenizer (quotes, escapes, $(…), <(…), `…`, redirections like 2>&1, comments) splits the
// command into simple commands; a regex over words cut the chain at $( or & and let --amend pass.
// Mirror of amend_scan in the bash hook: same rules, same results (tests/test-gate-result-dual-binding.bats).
// git accepts unique prefixes of long options, so --am, --ame and --amen are --amend too.
const AMEND = /^--am(?:e(?:nd?)?)?$/i;
const GIT_OPTS_WITH_VALUE = new Set(["-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--attr-source", "--super-prefix"]);

// Review #1355 (3rd): the tokenizer does not expand, so an "opaque" word (unquoted or quoted substitution,
// ${…}, $'…' with escapes, braces with , or ..) carries the \x01 mark and matches by substring: if it holds
// --am after commit (and is not the value of -m, -F…) it blocks, like the old regex did. git may follow any
// prefix (sudo -u x, timeout 5, xargs, ssh host…), and the text given to bash -c, sh -c, eval or ssh is
// tokenized again as a command of its own, with the same budget and the same nesting cap.
const OPAQUE = "\x01";
const SHELLS = /^(?:bash|sh|zsh|dash|ksh|ash|mksh|fish|eval|ssh|su|watch)$/;
// $var, $1, $@…: the value is not visible, so the word is opaque (--amend$x, 4th review).
const PARAM_START = /[A-Za-z0-9_@*#?$!-]/;
// An opaque word is compared without { } $ ,: -{-,}amend and co${x}mmit match too.
const bare = (x: string) => x.replace(/[{}$,]/g, "");
const COMMIT_OPTS_WITH_VALUE = /^(?:-m|-f|-c|-t|--message|--file|--reuse-message|--reedit-message|--fixup|--squash|--author|--date|--template|--cleanup|--trailer)$/;

function gitCommitAmend(w: string[], k: number): boolean {
  while (k < w.length && w[k].startsWith("-")) {
    if (GIT_OPTS_WITH_VALUE.has(w[k].toLowerCase())) k++;
    k++;
  }
  if (k >= w.length) return false;
  const sub = w[k].toLowerCase();
  if (sub !== "commit" && !(sub.startsWith(OPAQUE) && bare(sub).includes("commit"))) return false;
  let prev = "";
  for (k++; k < w.length; k++) {
    const s = w[k].toLowerCase();
    if (AMEND.test(s)) return true;
    if (s.startsWith(OPAQUE) && bare(s).includes("--am") && !COMMIT_OPTS_WITH_VALUE.test(prev)) return true;
    prev = s;
  }
  return false;
}

// Words of a simple command → 1 is git … commit … --amend, 0 no, 2 cannot be tokenized.
function isAmendCommit(w: string[]): number {
  for (let m = 0; m < w.length; m++) {
    const b = w[m].replace(/^\x01/, "").toLowerCase().replace(/^[\s\S]*\//, "");
    if (b === "git" || (w[m].startsWith(OPAQUE) && b.includes("git"))) {
      if (gitCommitAmend(w, m + 1)) return 1;
    } else if (SHELLS.test(b) && m + 1 < w.length) {
      const r = amendScan(w.slice(m + 1).join(" ").replaceAll(OPAQUE, ""));
      if (r !== 0) return r;
    }
  }
  return 0;
}

// Review #1355 (P1): every $(…) level is walked again when its inside is tokenized, so the cost is
// O(n·depth). Same caps and same counting points as the bash hook: every loop spends from a step
// budget and recursion stops at AMEND_MAX_NEST; when exhausted the scan returns -1 / 2 and the coarse
// match fails closed.
const AMEND_MAX_CHARS = 16384;
const AMEND_MAX_STEPS = 2 * AMEND_MAX_CHARS;
const AMEND_MAX_NEST = 32;
const st = { steps: 0, nest: 0, esc: false };
const tick = (n = 1) => (st.steps += n) > AMEND_MAX_STEPS;

// Index just past the `)` closing a $( / <( / >( opened before i, or -1.
function closeSubst(s: string, i: number): number {
  if (st.nest >= AMEND_MAX_NEST) return -1;
  st.nest++;
  try { return closeSubstIn(s, i); } finally { st.nest--; }
}

function closeSubstIn(s: string, i: number): number {
  let depth = 1;
  while (i < s.length) {
    if (tick()) return -1;
    const c = s[i];
    if (c === "\\") { i += 2; continue; }
    if (c === "$" && s[i + 1] === "'") { const j = closeAnsi(s, i + 2); if (j < 0) return -1; i = j; continue; }
    if (c === "'") { const j = closeSq(s, i + 1); if (j < 0) return -1; i = j; continue; }
    if (c === '"') { const j = closeDq(s, i + 1); if (j < 0) return -1; i = j; continue; }
    if (c === "`") { const j = closeBq(s, i + 1); if (j < 0) return -1; i = j; continue; }
    if (c === "(") depth++;
    else if (c === ")" && --depth === 0) return i + 1;
    i++;
  }
  return -1;
}

// Index just past the closing ', or -1 (the bash hook walks it char by char: same step count).
function closeSq(s: string, i: number): number {
  const j = s.indexOf("'", i);
  if (j < 0 || tick(j - i + 1)) return -1;
  return j + 1;
}

// Index just past the ' closing $'…' (\' does not close it), or -1; st.esc tells whether it held a backslash.
function closeAnsi(s: string, i: number): number {
  st.esc = false;
  while (i < s.length) {
    if (tick()) return -1;
    if (s[i] === "\\") { st.esc = true; i += 2; continue; }
    if (s[i] === "'") return i + 1;
    i++;
  }
  return -1;
}

// Index just past the } closing a ${ opened before i, or -1.
function closeBrace(s: string, i: number): number {
  let depth = 1;
  while (i < s.length) {
    if (tick()) return -1;
    const c = s[i];
    if (c === "\\") { i += 2; continue; }
    if (c === "'") { const j = closeSq(s, i + 1); if (j < 0) return -1; i = j; continue; }
    if (c === '"') { const j = closeDq(s, i + 1); if (j < 0) return -1; i = j; continue; }
    if (c === "`") { const j = closeBq(s, i + 1); if (j < 0) return -1; i = j; continue; }
    if (c === "$" && s[i + 1] === "(") { const j = closeSubst(s, i + 2); if (j < 0) return -1; i = j; continue; }
    if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return i + 1;
    i++;
  }
  return -1;
}

function closeBq(s: string, i: number): number {
  while (i < s.length) {
    if (tick()) return -1;
    if (s[i] === "\\") { i += 2; continue; }
    if (s[i] === "`") return i + 1;
    i++;
  }
  return -1;
}

function closeDq(s: string, i: number): number {
  while (i < s.length) {
    if (tick()) return -1;
    const c = s[i];
    if (c === "\\") { i += 2; continue; }
    if (c === '"') return i + 1;
    if (c === "$" && s[i + 1] === "(") { const j = closeSubst(s, i + 2); if (j < 0) return -1; i = j; continue; }
    if (c === "`") { const j = closeBq(s, i + 1); if (j < 0) return -1; i = j; continue; }
    i++;
  }
  return -1;
}

// 1 = some simple command is `git … commit … --amend`, 0 = none, 2 = cannot be tokenized.
function amendScan(s: string): number {
  if (st.nest >= AMEND_MAX_NEST) return 2;
  st.nest++;
  try { return amendScanIn(s); } finally { st.nest--; }
}

function amendScanIn(s: string): number {
  let words: string[] = [];
  let word = "";
  let inWord = false;
  // redir: the word ends in an unquoted < or > (echo ">"|git … is not a >| redirection).
  let redir = false;
  // opaque: the word holds something the shell expands and the scan cannot see (\x01 mark); ubrace: unquoted {.
  let opaque = false;
  let ubrace = false;
  const flush = () => {
    if (inWord) { words.push(opaque ? OPAQUE + word : word); word = ""; inWord = false; redir = false; }
    opaque = false; ubrace = false;
  };
  const endCmd = () => { flush(); const r = words.length ? isAmendCommit(words) : 0; words = []; return r; };
  // Substitutions are scanned as commands of their own and kept as part of the current word.
  const nested = (start: number, inner: string, end: number, opq: boolean): number => {
    const r = amendScan(inner);
    if (r !== 0) return r;
    tick(end - start);
    word += s.slice(start, end); inWord = true; redir = false;
    if (opq) opaque = true;
    return 0;
  };
  let i = 0;
  while (i < s.length) {
    if (tick()) return 2;
    const c = s[i];
    if (c === "\\") {
      if (s[i + 1] !== "\n" && i + 1 < s.length) { word += s[i + 1]; inWord = true; redir = false; }
      i += 2; continue;
    }
    if (c === "'") {
      const j = closeSq(s, i + 1); if (j < 0) return 2;
      tick(j - 1 - (i + 1));
      word += s.slice(i + 1, j - 1); inWord = true; redir = false; i = j; continue;
    }
    if (c === "$" && s[i + 1] === "'") { // $'…': ANSI-C quotes; with a backslash the word is opaque
      const j = closeAnsi(s, i + 2); if (j < 0) return 2;
      tick(j - 1 - (i + 2));
      word += s.slice(i + 2, j - 1); inWord = true; redir = false;
      if (st.esc) opaque = true;
      i = j; continue;
    }
    if (c === "$" && s[i + 1] === '"') { i++; continue; } // $"…" is "…"
    if (c === '"') {
      let k = i + 1;
      inWord = true; redir = false;
      while (k < s.length && s[k] !== '"') {
        if (tick()) return 2;
        if (s[k] === "\\" && k + 1 < s.length && '"\\$`'.includes(s[k + 1])) { word += s[k + 1]; k += 2; continue; }
        if (s[k] === "$" && s[k + 1] === "{") {
          const j = closeBrace(s, k + 2); if (j < 0) return 2;
          const r = nested(k, s.slice(k + 2, j - 1), j, true); if (r !== 0) return r;
          k = j; continue;
        }
        if (s[k] === "$" && s[k + 1] === "(") {
          const j = closeSubst(s, k + 2); if (j < 0) return 2;
          const r = nested(k, s.slice(k + 2, j - 1), j, true); if (r !== 0) return r;
          k = j; continue;
        }
        if (s[k] === "`") {
          const j = closeBq(s, k + 1); if (j < 0) return 2;
          const r = nested(k, s.slice(k + 1, j - 1), j, true); if (r !== 0) return r;
          k = j; continue;
        }
        if (s[k] === "$" && PARAM_START.test(s[k + 1] ?? "")) opaque = true;
        word += s[k]; k++;
      }
      if (k >= s.length) return 2;
      i = k + 1; continue;
    }
    if ((c === "$" || c === "<" || c === ">") && s[i + 1] === "(") {
      const j = closeSubst(s, i + 2); if (j < 0) return 2;
      const r = nested(i, s.slice(i + 2, j - 1), j, c === "$"); if (r !== 0) return r;
      i = j; continue;
    }
    if (c === "$" && s[i + 1] === "{") { // ${…}: the text inside is scanned as a command
      const j = closeBrace(s, i + 2); if (j < 0) return 2;
      const r = nested(i, s.slice(i + 2, j - 1), j, true); if (r !== 0) return r;
      i = j; continue;
    }
    if (c === "`") {
      const j = closeBq(s, i + 1); if (j < 0) return 2;
      const r = nested(i, s.slice(i + 1, j - 1), j, true); if (r !== 0) return r;
      i = j; continue;
    }
    if (c === " " || c === "\t") { flush(); i++; continue; }
    if (c === "#" && !inWord) {
      const j = s.indexOf("\n", i);
      const e = j < 0 ? s.length : j;
      if (tick(e - i)) return 2;
      i = e; continue;
    }
    // Redirections (2>&1, >&2, &>f, >|f) belong to the word, not a separator.
    if ((c === "&" && (s[i + 1] === ">" || redir)) || (c === "|" && redir)) {
      word += c; inWord = true; redir = false; i++; continue;
    }
    if (";&|()\n".includes(c)) { const r = endCmd(); if (r !== 0) return r; i++; continue; }
    if (c === "$" && PARAM_START.test(s[i + 1] ?? "")) opaque = true;
    // Unquoted brace expansion ({a,b}, {1..3}): the shell expands it, the word is opaque.
    if (c === "{") ubrace = true;
    if (ubrace && (c === "," || (c === "." && s[i + 1] === "."))) opaque = true;
    word += c; inWord = true; i++;
    redir = c === "<" || c === ">";
  }
  if (st.steps > AMEND_MAX_STEPS) return 2; // a word copy ran out of budget
  return endCmd();
}

// Same cap as the bash hook (its tokenizer has to finish within the 5 s hook timeout), measured in UTF-8
// bytes like bash does under LC_ALL=C: longer → fail closed.
const utf8 = new TextEncoder();

function amendBlocked(command: string): boolean {
  // Without \ ' " $ { } , because git co\mmit --"am"end, -$'-amend' and -{-,}amend are --amend too.
  // indexOf instead of a regex: linear on commands of any length.
  const fast = command.replace(/[\\'"${},]/g, "").toLowerCase();
  const at = fast.indexOf("commit");
  if (at < 0 || fast.indexOf("--am", at + 6) < 0) return false;
  st.steps = 0; st.nest = 0;
  // Fail closed: if the fast path matched and the command cannot be tokenized (caps, open quote or
  // substitution), block without a regex. The coarse match on the raw command was dodged by --"amend" and
  // co\mmit, and its backtracking had no bound (4th review #1355).
  const r = utf8.encode(command).length > AMEND_MAX_CHARS ? 2 : amendScan(command);
  return r !== 0;
}

const FORCE_WITH_LEASE = rx(String.raw`push\s+.*--force-with-lease`);
const BARE_FORCE = rx(String.raw`push\s+(?:[^;&|]*\s)?(?:--force|-f)(?:\s|$)`);
const PUSH_MENTIONS_MAIN = /git\s+push\s+.*\b(?:main|master)\b/i;

const BLOCK_RULES: Array<{ rx: RegExp; msg: string }> = [
  {
    rx: rx(String.raw`push\s+(?:origin\s+)?(?:main|master)(?:\s|$|[;&|)])`),
    msg: "Cannot push directly to main/master. Use a feature branch and PR.",
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

  // Same as the bash hook: join «\⏎» continuations, then match line by line like grep does
  // (\s and [^;&|] would otherwise cross a newline that separates two commands). Only an odd backslash
  // continues: in «\\⏎» the backslash is literal and the newline separates commands (4th review #1355).
  // «\⏎» vanishes without leaving a space (git comm\⏎it), so both joins are checked: with and without space.
  const withSpace = command.replace(/\\\\|\\\n/g, (m) => (m === "\\\n" ? " " : m));
  const noSpace = command.replace(/\\\\|\\\n/g, (m) => (m === "\\\n" ? "" : m));
  checkJoined(withSpace);
  if (noSpace !== withSpace) checkJoined(noSpace);
}

function checkJoined(joined: string): void {
  const lines = joined.split("\n");
  const anyLine = (r: RegExp) => lines.some((l) => r.test(l));
  const lease = anyLine(FORCE_WITH_LEASE);
  // --force or -f always blocks: a --force-with-lease in another command or line does not excuse it, and in
  // the same command --force overrides the lease (review #1355); BARE_FORCE never matches --force-with-lease.
  if (anyLine(BARE_FORCE)) {
    throw new Error("BLOCKED [force-push]: git push --force blocked. Use --force-with-lease instead.");
  }
  if (lease && anyLine(PUSH_MENTIONS_MAIN)) {
    throw new Error("BLOCKED [force-push]: Cannot force-push to main/master. Create a branch.");
  }
  if (amendBlocked(joined)) {
    throw new Error("BLOCKED [force-push]: git commit --amend can destroy previous commits. Create a new commit.");
  }
  for (const r of BLOCK_RULES) {
    if (anyLine(r.rx)) {
      throw new Error(`BLOCKED [force-push]: ${r.msg}`);
    }
  }
}
