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

// Qué es restauración (`git checkout [<opciones>] [<tree-ish>] -- <rutas>`) y
// qué cambia de rama lo decide solo el resolvedor; sin él, se bloquea.
const RESOLVER = fileURLToPath(new URL("../../../scripts/lib/git_op_targets.py", import.meta.url));
const ADMITTED = "Forma admitida: git -C <ruta> checkout|switch … (o cd <ruta> && git checkout …).";
// Prefiltro: `git` o `checkout|switch` como palabras (sin comillas ni barras).
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
  return parseSwitchTargets(res.stdout || "");
}

/**
 * Salida del resolvedor → destinos. Una línea que no sea `switch\t<dir>` (p. ej.
 * un destino con salto de línea partido en dos) cuenta como "" → BLOQUEAR, igual
 * que el hook bash (revisión de seguridad #1483, 3.ª, P2-4).
 */
export function parseSwitchTargets(stdout: string): string[] {
  return stdout.split("\n").filter((l) => l !== "")
    .map((l) => (l.startsWith("switch\t") ? l.slice(7) : ""));
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
  // `git` O `checkout|switch`: `git co feature` (alias) no dice `checkout` y
  // `$g checkout` no dice `git`; el resolvedor decide en los dos casos.
  if (!GIT_RX.test(plain) && !SWITCH_RX.test(plain)) return;
  const args = (output?.args ?? input?.args ?? {}) as Record<string, unknown>;
  const base = typeof args.workdir === "string" && args.workdir ? args.workdir : process.cwd();

  // El repo que importa es el DESTINO de la orden (`git -C <clon> checkout <sha>`),
  // no el checkout de la sesión. Sin resolvedor (python3 ausente, timeout) no se
  // sabe si la orden cambia de rama ni dónde (`-c k=v`, `-C "/a b"`, alias,
  // `$(…)` anidadas): BLOQUEAR, como el hook bash (revisión #1483, 3.ª, P2-5).
  const targets = switchTargets(command, base);
  if (targets === null) {
    throw new Error("BLOCKED [branch-switch-dirty]: resolvedor de destinos no disponible (python3 scripts/lib/git_op_targets.py); no se puede comprobar el cambio de rama (fail-closed).");
  }
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
