// block-branch-switch-dirty.ts — SPEC-OC-04 Slice 2
//
// Prevents `git checkout <branch>` / `git switch <branch>` when the working
// tree has uncommitted changes. Avoids silent data loss when the agent (or
// human) tries to jump branches mid-edit. Port of
// `.opencode/hooks/block-branch-switch-dirty.sh` (Tier: security, always active).
//
// Reference: docs/rules/domain/critical-rules-extended.md (Rule 13)

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
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
 * True if, after a standalone `--`, there is at least one path that is not a
 * `$VAR`, `$(…)` or backtick expansion: those can expand to nothing and leave
 * `git checkout <rama> --`, which changes branch.
 */
function knownPathAfterDashDash(args: string): boolean {
  const m = args.match(/(?:^|\s)--\s+(.*)$/);
  if (!m) return false;
  const rest = m[1].replace(/\$\([^)]*\)?|`[^`]*`?/g, " ");
  return rest.split(/\s+/).some((t) => t !== "" && !/^["']?\$/.test(t));
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
    if (m[1].toLowerCase() === "checkout" && knownPathAfterDashDash(pathArgs(m[2]))) continue;
    return true;
  }
  return false;
}

const RESOLVER = fileURLToPath(new URL("../../../scripts/lib/git_op_targets.py", import.meta.url));
const ADMITTED = "Forma admitida: git -C <ruta> checkout|switch … (o cd <ruta> && git checkout …).";
// Prefiltro: `git` y `checkout|switch` como palabras (sin comillas ni barras).
const GIT_RX = /(^|[^\w])git([^\w]|$)/i;
const SWITCH_RX = /(^|[^\w-])(checkout|switch)([^\w-]|$)/i;

/**
 * Directorio destino de cada `git checkout|switch` que puede mover HEAD,
 * resuelto por `scripts/lib/git_op_targets.py --switch`: el mismo resolvedor
 * que el hook bash y que los guards de commit en main (#1467). "" = forma
 * incierta → BLOQUEAR. null = resolvedor no disponible.
 */
export function switchTargets(command: string, base: string): string[] | null {
  const res = spawnSync("python3", [RESOLVER, "--switch", base], { encoding: "utf8", timeout: 5000, input: command });
  if (res.status !== 0 || res.error) return null;
  return (res.stdout || "").split("\n").filter((l) => l.startsWith("switch\t")).map((l) => l.slice(7));
}

/**
 * Cambios sin guardar en `dir`. "" = limpio o no es un repo (nada que perder).
 * null = git falló por otra causa (timeout, `dubious ownership`…): no se sabe,
 * así que el llamador bloquea (fail-closed).
 */
export function dirtyOf(dir: string): string | null {
  const res = spawnSync("git", ["-C", dir, "status", "--porcelain"], {
    encoding: "utf8", timeout: 3000, stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, LC_ALL: "C" }, // el mensaje de «no es un repo» se compara en inglés
  });
  if (!res.error && res.status === 0) return (res.stdout || "").trim();
  if (!res.error && /not a git repository/i.test(res.stderr || "")) return "";
  return null;
}

export async function blockBranchSwitchDirty(
  input: ToolInput, output: ToolOutput,
): Promise<void> {
  if (extractToolName(input) !== "bash") return;
  const command = extractCommand(input, output);
  if (!command) return;
  const plain = command.replace(/["'\\]/g, "");
  if (!GIT_RX.test(plain) || !SWITCH_RX.test(plain)) return;
  const args = (output?.args ?? input?.args ?? {}) as Record<string, unknown>;
  const base = typeof args.workdir === "string" && args.workdir ? args.workdir : process.cwd();

  // El repo que importa es el DESTINO de la orden (`git -C <clon> checkout <sha>`),
  // no el checkout de la sesión. Sin resolvedor: detector por regex y cwd de la orden.
  let targets = switchTargets(command, base);
  if (targets === null) targets = hasBranchChange(command) ? [base] : [];
  if (targets.includes("")) {
    throw new Error(`BLOCKED [branch-switch-dirty]: destino del cambio de rama no reconocido con certeza (fail-closed). ${ADMITTED}`);
  }
  let dirty = "";
  let repo = "";
  for (const dir of targets) {
    if (!existsSync(dir)) continue; // aún no existe (clon creado en la misma orden): nada que perder
    const state = dirtyOf(dir);
    if (state === null) {
      throw new Error(`BLOCKED [branch-switch-dirty]: no se pudo leer el estado de ${dir} con git status (fail-closed).`);
    }
    dirty = state;
    if (dirty) { repo = dir; break; }
  }
  if (!dirty) return;

  const lines = dirty.split("\n");
  const tracked = lines.filter((l) => /^( M|M |MM|A |D )/.test(l)).length;
  const untracked = lines.filter((l) => l.startsWith("??")).length;

  throw new Error(
    [
      "BLOCKED [branch-switch-dirty]: cannot switch branch with uncommitted changes.",
      `  Repo: ${repo}`,
      `  Modified files:  ${tracked}`,
      `  Untracked files: ${untracked}`,
      "  Options: 1) git add + git commit  2) git stash -u (temporary)",
      "  Never switch branches without saving changes.",
    ].join("\n"),
  );
}
