// block-branch-switch-dirty.ts — SPEC-OC-04 Slice 2
//
// Prevents `git checkout <branch>` / `git switch <branch>` when the working
// tree has uncommitted changes. Avoids silent data loss when the agent (or
// human) tries to jump branches mid-edit. Port of
// `.opencode/hooks/block-branch-switch-dirty.sh` (Tier: security, always active).
//
// Reference: docs/rules/domain/critical-rules-extended.md (Rule 13)

import { execSync } from "node:child_process";
import { extractToolName, extractCommand, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";

// Every `git [-C <dir>] checkout|switch` invocation, with its own arguments
// (up to the next ; & | or newline).
const INVOCATION_RX = /(?:^|[^\w./-])git\s+(?:-C\s+[^\s;&|]+\s+)?(checkout|switch)(?![\w-])([^;&|\n]*)/gi;

/**
 * Arguments without redirections (`>/dev/null`, `2> f`) or a trailing comment
 * (`# -- x`): neither is a pathspec, so `git checkout feature -- >/dev/null`
 * still changes branch.
 */
function pathArgs(args: string): string {
  return (" " + args).replace(/\s#.*$/, "").replace(/(^|\s)\d*[<>]+\s*\S*/g, " ");
}

/**
 * True if the command contains an invocation that can move HEAD. A file
 * restore is `git checkout [<opciones>] [<tree-ish>] -- <rutas>`: a standalone
 * `--` followed by at least one path among that invocation's own arguments
 * (`--merge`, `--ours` or a tree-ish before it included) never changes
 * branch; `git checkout main --` without paths does. `git switch` has no
 * pathspec mode. A restore earlier in the command does not excuse a later
 * `git checkout <rama>`.
 */
export function hasBranchChange(command: string): boolean {
  // Line continuations join words (same normalisation as the bash hook).
  for (const m of command.replace(/\\\n/g, " ").matchAll(INVOCATION_RX)) {
    if (m[1].toLowerCase() === "checkout" && /(^|\s)--\s+\S/.test(pathArgs(m[2]))) continue;
    return true;
  }
  return false;
}

export async function blockBranchSwitchDirty(
  input: ToolInput, output: ToolOutput,
): Promise<void> {
  if (extractToolName(input) !== "bash") return;
  const command = extractCommand(input, output);
  if (!command) return;

  if (!hasBranchChange(command)) return;

  let dirty = "";
  try {
    dirty = execSync("git status --porcelain", {
      encoding: "utf8",
      timeout: 3000,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    // Not a git repo or git failed — let the original command run and fail naturally.
    return;
  }

  if (!dirty) return;

  const lines = dirty.split("\n");
  const tracked = lines.filter((l) => /^( M|M |MM|A |D )/.test(l)).length;
  const untracked = lines.filter((l) => l.startsWith("??")).length;

  throw new Error(
    [
      "BLOCKED [branch-switch-dirty]: cannot switch branch with uncommitted changes.",
      `  Modified files:  ${tracked}`,
      `  Untracked files: ${untracked}`,
      "  Options: 1) git add + git commit  2) git stash -u (temporary)",
      "  Never switch branches without saving changes.",
    ].join("\n"),
  );
}
