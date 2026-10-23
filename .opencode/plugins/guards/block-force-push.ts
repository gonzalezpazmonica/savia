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
// SE-453 (review #1355): --amend has to be an argument of its own of that git commit. A shell
// tokenizer (quotes, escapes, $(…), <(…), `…`, redirections like 2>&1, comments) splits the
// command into simple commands; a regex over words cut the chain at $( or & and let --amend pass.
// Mirror of amend_scan in the bash hook: same rules, same results (tests/test-gate-result-dual-binding.bats).
// git accepts unique prefixes of long options, so --am, --ame and --amen are --amend too.
const AMEND = /^--am(?:e(?:nd?)?)?$/i;
const ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/;
const PREFIXES = new Set(["env", "command", "sudo", "nohup", "time", "exec", "if", "then", "do", "else", "elif", "while", "until", "!", "{"]);
const GIT_OPTS_WITH_VALUE = new Set(["-c", "--git-dir", "--work-tree"]);
// Fail closed: if the command cannot be tokenized (an open quote or substitution), a coarse match blocks.
const AMEND_COARSE = /(?:^|[^A-Za-z0-9_-])git[^A-Za-z0-9_-](?:[\s\S]*[^A-Za-z0-9_-])?commit[\s\S]*[^A-Za-z0-9_-]--am(?:e(?:nd?)?)?(?:[^A-Za-z0-9_=-]|$)/i;

// Options of the previous prefix (sudo -u x, env -i, time -p); sudo and env options with a value skip it too.
const PREFIX_OPT_WITH_VALUE = /^(?:sudo:-[ugpChDrtUT]|env:-[uCS])$/;
const PREFIX_WITH_OPTS = new Set(["env", "command", "sudo", "nohup", "time", "exec"]);

function isAmendCommit(w: string[]): boolean {
  let k = 0;
  let p = "";
  while (k < w.length) {
    if (ASSIGN.test(w[k])) { k++; continue; }
    if (p && w[k].startsWith("-")) {
      if (PREFIX_OPT_WITH_VALUE.test(`${p}:${w[k]}`)) k++;
      k++; continue;
    }
    const low = w[k].toLowerCase();
    if (!PREFIXES.has(low)) break;
    p = PREFIX_WITH_OPTS.has(low) ? low : "";
    k++;
  }
  if (k >= w.length) return false;
  const g = w[k].toLowerCase();
  if (g !== "git" && !g.endsWith("/git")) return false;
  k++;
  while (k < w.length && w[k].startsWith("-")) {
    if (GIT_OPTS_WITH_VALUE.has(w[k].toLowerCase())) k++;
    k++;
  }
  if (k >= w.length || w[k].toLowerCase() !== "commit") return false;
  return w.slice(k + 1).some((x) => AMEND.test(x));
}

// Review #1355 (P1): every $(…) level is walked again when its inside is tokenized, so the cost is
// O(n·depth). Same caps and same counting points as the bash hook: every loop spends from a step
// budget and recursion stops at AMEND_MAX_NEST; when exhausted the scan returns -1 / 2 and the coarse
// match fails closed.
const AMEND_MAX_CHARS = 16384;
const AMEND_MAX_STEPS = 2 * AMEND_MAX_CHARS;
const AMEND_MAX_NEST = 32;
const st = { steps: 0, nest: 0 };
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
  const flush = () => { if (inWord) { words.push(word); word = ""; inWord = false; redir = false; } };
  const endCmd = () => { flush(); const hit = isAmendCommit(words); words = []; return hit; };
  // Substitutions are scanned as commands of their own and kept as part of the current word.
  const nested = (start: number, inner: string, end: number): number => {
    const r = amendScan(inner);
    if (r !== 0) return r;
    tick(end - start);
    word += s.slice(start, end); inWord = true; redir = false;
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
    if (c === '"') {
      let k = i + 1;
      inWord = true; redir = false;
      while (k < s.length && s[k] !== '"') {
        if (tick()) return 2;
        if (s[k] === "\\" && k + 1 < s.length && '"\\$`'.includes(s[k + 1])) { word += s[k + 1]; k += 2; continue; }
        if (s[k] === "$" && s[k + 1] === "(") {
          const j = closeSubst(s, k + 2); if (j < 0) return 2;
          const r = nested(k, s.slice(k + 2, j - 1), j); if (r !== 0) return r;
          k = j; continue;
        }
        if (s[k] === "`") {
          const j = closeBq(s, k + 1); if (j < 0) return 2;
          const r = nested(k, s.slice(k + 1, j - 1), j); if (r !== 0) return r;
          k = j; continue;
        }
        word += s[k]; k++;
      }
      if (k >= s.length) return 2;
      i = k + 1; continue;
    }
    if ((c === "$" || c === "<" || c === ">") && s[i + 1] === "(") {
      const j = closeSubst(s, i + 2); if (j < 0) return 2;
      const r = nested(i, s.slice(i + 2, j - 1), j); if (r !== 0) return r;
      i = j; continue;
    }
    if (c === "`") {
      const j = closeBq(s, i + 1); if (j < 0) return 2;
      const r = nested(i, s.slice(i + 1, j - 1), j); if (r !== 0) return r;
      i = j; continue;
    }
    if (c === " " || c === "\t") { flush(); i++; continue; }
    if (c === "#" && !inWord) { const j = s.indexOf("\n", i); i = j < 0 ? s.length : j; continue; }
    // Redirections (2>&1, >&2, &>f, >|f) belong to the word, not a separator.
    if ((c === "&" && (s[i + 1] === ">" || redir)) || (c === "|" && redir)) {
      word += c; inWord = true; redir = false; i++; continue;
    }
    if (";&|()\n".includes(c)) { if (endCmd()) return 1; i++; continue; }
    word += c; inWord = true; i++;
    redir = c === "<" || c === ">";
  }
  if (st.steps > AMEND_MAX_STEPS) return 2; // a word copy ran out of budget
  return endCmd() ? 1 : 0;
}

// Same cap as the bash hook (its tokenizer has to finish within the 5 s hook timeout), measured in UTF-8
// bytes like bash does under LC_ALL=C: longer → fail closed.
const utf8 = new TextEncoder();

function amendBlocked(command: string): boolean {
  // Without \, ' and " because git co\mmit --"am"end is --amend too (review #1355).
  if (!/commit[\s\S]*--am/i.test(command.replace(/[\\'"]/g, ""))) return false;
  st.steps = 0; st.nest = 0;
  const r = utf8.encode(command).length > AMEND_MAX_CHARS ? 2 : amendScan(command);
  return r === 1 || (r === 2 && AMEND_COARSE.test(command));
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
  // (\s and [^;&|] would otherwise cross a newline that separates two commands).
  const joined = command.replace(/\\\n/g, " ");
  const lines = joined.split("\n");
  const anyLine = (r: RegExp) => lines.some((l) => r.test(l));
  const lease = anyLine(FORCE_WITH_LEASE);
  if (anyLine(BARE_FORCE) && !lease) {
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
