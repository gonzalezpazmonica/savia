// block-commit-to-main.ts — SE-337 (guarda TS del runtime OpenCode)
//
// Bloquea `git commit` cuando la rama del repo DESTINO es main/master,
// mecanizando la regla autonomous-safety "NUNCA commit en ramas de humanos".
// Contraparte TS del hook shell `.opencode/hooks/block-commit-to-main.sh`.
//
// El destino de cada `git commit` real lo resuelve `scripts/lib/git_op_targets.py`
// (el mismo resolvedor que usan los hooks bash, para que no diverjan):
// `git -C <ruta>`, `cd <ruta>` encadenado, variables literales de la misma
// orden y el cwd de la orden. El texto de heredocs y cadenas no es una orden.
// Destino no resoluble, fuera de un repo o sin Python → criterio conservador:
// se mira la rama del cwd de la orden (comportamiento anterior).
//
// Bypass consciente de la operadora: SAVIA_ALLOW_MAIN_COMMIT=1 (queda
// registrado en el log, no es silencioso).
//
// Sin red (CRIT-001). Coste ~30-60ms solo cuando la orden menciona git commit.

import { extractToolName, extractCommand, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";

// Fallback sin resolvedor (sin Python, timeout, fallo): `git` y `commit` como
// palabras en la orden, igual que el prefiltro del hook bash (fail-closed;
// cubre `git -C <ruta> commit`).
const FALLBACK_GIT_RX = /(^|[^\w-])git([^\w-]|$)/;
const FALLBACK_COMMIT_RX = /(^|[^\w-])commit([^\w-]|$)/;
const RESOLVER = new URL("../../../scripts/lib/git_op_targets.py", import.meta.url).pathname;

async function spawn(cmd: string, args: string[], input?: string): Promise<{ ok: boolean; out: string }> {
  try {
    const { spawnSync } = await import("node:child_process");
    const res = spawnSync(cmd, args, { encoding: "utf8", timeout: 3000, input });
    // Sin trim(): la línea `commit\t` (destino vacío = no resoluble) termina en tabulador.
    return { ok: res.status === 0 && !res.error, out: res.stdout || "" };
  } catch {
    return { ok: false, out: "" };
  }
}

async function branchOf(dir: string): Promise<string | null> {
  // TEST_BRANCH simula la rama en los tests; fuera de `bun test` (NODE_ENV=test)
  // se ignora para que una variable de entorno no desactive el guard.
  if (process.env.NODE_ENV === "test" && process.env.TEST_BRANCH) return process.env.TEST_BRANCH;
  const inside = await spawn("git", ["-C", dir, "rev-parse", "--is-inside-work-tree"]);
  if (!inside.ok || inside.out.trim() !== "true") return null; // no es un repo
  const res = await spawn("git", ["-C", dir, "branch", "--show-current"]);
  return res.out.trim();
}

/** Directorios destino de cada `git commit` real; "" = no resoluble. null = resolvedor no disponible. */
async function commitTargets(command: string, base: string): Promise<string[] | null> {
  const res = await spawn("python3", [RESOLVER, base], command);
  if (!res.ok) return null;
  return res.out
    .split("\n")
    .filter((l) => l.startsWith("commit\t"))
    .map((l) => l.slice("commit\t".length));
}

const isHuman = (b: string | null) => b === "main" || b === "master";

export async function blockCommitToMain(input: ToolInput, output: ToolOutput): Promise<void> {
  if (extractToolName(input) !== "bash") return;
  const command = extractCommand(input, output);
  if (!command || !/\bcommit\b/.test(command)) return;

  const args = (output?.args ?? input?.args ?? {}) as Record<string, unknown>;
  const base = typeof args.workdir === "string" && args.workdir ? args.workdir : process.cwd();

  let targets = await commitTargets(command, base);
  if (targets === null) {
    // Sin resolvedor: conservador (texto + cwd de la orden).
    targets = FALLBACK_GIT_RX.test(command) && FALLBACK_COMMIT_RX.test(command) ? [""] : [];
  }
  if (targets.length === 0) return;

  let branch = "";
  for (const dir of targets) {
    let b = dir ? await branchOf(dir) : null;
    if (b === null) b = await branchOf(base); // conservador: cwd de la orden
    if (isHuman(b)) {
      branch = b as string;
      break;
    }
  }
  if (!branch) return; // rama segura (agent/*, feature/*) o fuera de repo

  // Bypass consciente de la operadora: se registra, no es silencioso.
  const verdict = process.env.SAVIA_ALLOW_MAIN_COMMIT === "1" ? "bypass" : "block";
  try {
    const fs = await import("node:fs");
    const path = await import("node:path");
    const log = path.join(process.cwd(), "output", "turn-sdlc", "commit-guard.jsonl");
    const entry: Record<string, string> = { ts: new Date().toISOString(), branch, action: "commit", verdict };
    if (verdict === "bypass") entry.env = "SAVIA_ALLOW_MAIN_COMMIT=1";
    fs.appendFileSync(log, JSON.stringify(entry) + "\n");
  } catch { /* best-effort */ }
  if (verdict === "bypass") return;

  const reason = `Commit en rama humana (${branch}) bloqueado por autonomous-safety (NUNCA commit en main/master). Crea una rama agent/* y commitea ahí: git checkout -b agent/<tarea>. Si es intencional de la operadora, repítelo con SAVIA_ALLOW_MAIN_COMMIT=1 (queda registrado).`;
  throw new Error(`BLOCKED [commit-to-main]: ${reason}`);
}
