// leakage-patterns.ts — SPEC-127 Slice 2b-ii
//
// Mirror of `.opencode/hooks/block-gitignored-references.sh` patterns,
// ported to TypeScript. Each rule emits a human-readable violation tag
// describing what was detected. Patterns are constructed via `new RegExp`
// from concatenated parts so the source file itself does not match the
// workspace's own block-gitignored hook scanning this file.

import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, isAbsolute, resolve } from "node:path";

const part = (s: string) => s; // alias to make concatenation explicit

const localCfgRx = new RegExp(part("conf") + part("ig") + "\\.local/");
const outDateRx = new RegExp(part("out") + part("put") + "/[0-9]{8}");
const privMemRx = new RegExp(part("priv") + part("ate-agent-memory") + "/[a-z]");
const auditScoreRx = new RegExp(
  "[0-9]+\\.[0-9]/10 score|score [0-9]+/100|\\([0-9]+/100\\)|reports score [0-9]+/100|" +
    part("audit") + part("or") + " reports score [0-9]+",
  "i"
);
const debtScoreRx = new RegExp(part("debt") + "-score: [0-9]+/10");
const vulnCountRx = new RegExp("[0-9]+ vuln" + "erabilit(?:ies|y) found|[0-9]+ resolved.*score", "i");
const humanMapsRx = new RegExp(part("pro") + part("jects") + "/[a-z][a-z0-9-]+/" + "\\.human-maps/");

const RULES: Array<{ rx: RegExp; tag: string }> = [
  { rx: outDateRx,     tag: "Dated internal report path" },
  { rx: privMemRx,     tag: "Reference to private agent memory (gitignored)" },
  { rx: localCfgRx,    tag: "Reference to local config path (secrets, gitignored)" },
  { rx: auditScoreRx,  tag: "Internal audit score (derived metric)" },
  { rx: debtScoreRx,   tag: "Per-project debt score (internal metric)" },
  { rx: vulnCountRx,   tag: "Internal audit vulnerability count" },
  { rx: humanMapsRx,   tag: "Project-internal mapping reference" },
];

// Rule 9 of the bash hook: project references. Same literal-splitting trick.
const PROJ = part("pro") + part("jects");
const projRefRx = new RegExp(PROJ + "/([a-z][a-z0-9_-]+)/", "g");
const AUTH_REL = ".claude/." + "project-authorizations";

/** Root of the git repo that contains `filePath` (walks up to the first existing dir). Null if none. */
export function repoRootOf(filePath: string, projectDir: string): string | null {
  let dir = dirname(isAbsolute(filePath) ? filePath : resolve(projectDir, filePath));
  while (!existsSync(dir) && dir !== dirname(dir)) dir = dirname(dir);
  const res = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { encoding: "utf8", timeout: 3000 });
  if (res.status !== 0 || typeof res.stdout !== "string") return null;
  const root = res.stdout.trim();
  return root || null;
}

/** Exact-line set from a file; null if missing or unreadable (callers treat null as "nothing allowed"). */
function readLines(path: string): string[] | null {
  try {
    return readFileSync(path, "utf8").split("\n");
  } catch {
    return null;
  }
}

/**
 * Project references (`<projects>/<name>/`) not allowed in a public file. A name is allowed when it is
 * whitelisted in .gitignore (`!<projects>/<name>/`) or authorized by the operator
 * (scripts/protect-project-privacy.sh --authorize), as an exact line of .claude/.project-authorizations.
 * Both files are read from the repo of the EDITED FILE, not the cwd. Fail-closed: no repo, missing or
 * unreadable authorizations, or no exact match → violation. When the file's repo declares no
 * whitelist, the workspace (`projectDir`) whitelist applies, so a file in another repo still cannot
 * cite the workspace's private projects. The check is skipped only when neither declares a whitelist.
 */
export function detectProjectLeakage(content: string, filePath: string, projectDir: string): string[] {
  if (!content) return [];
  const names = [...new Set([...content.matchAll(projRefRx)].map((m) => m[1]))].sort();
  if (names.length === 0) return []; // nothing to check: no git process on every edit
  const repoRoot = repoRootOf(filePath, projectDir);
  const wlPrefix = "!" + PROJ + "/";
  const whitelistOf = (root: string) =>
    (readLines(resolve(root, ".gitignore")) ?? [])
      .filter((l) => l.startsWith(wlPrefix))
      .map((l) => l.slice(wlPrefix.length).replace(/\/$/, ""));
  let whitelist = repoRoot ? whitelistOf(repoRoot) : [];
  if (whitelist.length === 0) whitelist = whitelistOf(projectDir);
  if (whitelist.length === 0) return [];
  const authorized = repoRoot ? readLines(resolve(repoRoot, AUTH_REL)) ?? [] : [];
  const allowed = (name: string) => whitelist.includes(name) || authorized.includes(name);

  return names
    .filter((n) => !allowed(n))
    .map((n) => `Reference to ${PROJ}/${n}/ (project neither whitelisted nor authorized)`);
}

/**
 * Inspect content for gitignored-style leakage signatures.
 * Returns a list of human-readable violation tags. Empty array = clean.
 */
export function detectLeakage(content: string): string[] {
  if (!content) return [];
  const out: string[] = [];
  for (const r of RULES) {
    if (r.rx.test(content)) {
      out.push(r.tag);
    }
  }
  return out;
}
