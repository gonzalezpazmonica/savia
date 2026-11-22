// guard-blocks.ts — SE-510 D2: registro local de bloqueos de los guards TS.
//
// Delega en scripts/guard_blocks.py (la misma línea, clave HMAC y redacción que los
// hooks bash): un solo formato para output/guard-blocks.jsonl. Solo se llama cuando
// un guard ya ha bloqueado, así que no añade coste al camino que pasa. Nunca lanza:
// un fallo al registrar no puede convertir un bloqueo en un permiso ni al revés.
// Solo cuenta como bloqueo un error que EMPIEZA por la marca BLOCKED/BLOQUEADO: un TypeError o un
// fallo interno de un guard no es un bloqueo e inflaría la tasa de falsos positivos.

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { extractCommand, extractToolName } from "./hook-input.ts";

const RECORDER = fileURLToPath(new URL("../../../scripts/guard_blocks.py", import.meta.url));

/** Nombre del guard según la etiqueta del mensaje: «BLOCKED [branch-switch-dirty]: …». */
export function guardNameOf(message: string): string {
  const m = /\b(?:BLOCKED|BLOQUEADO)\s*\[([\w./-]+)\]/i.exec(message);
  return m ? m[1] : "ts-before-guards";
}

export function recordGuardBlock(err: unknown, input: any, output: any): boolean {
  try {
    const message = err instanceof Error ? err.message : String(err);
    if (!/^\s*(?:BLOCKED|BLOQUEADO)\b/.test(message)) return false; // la marca abre el mensaje
    const command = extractCommand(input, output) ?? "";
    const tool = extractToolName(input) || "unknown";
    const res = spawnSync("python3", [RECORDER, "record", "--engine", "ts", "--event", "PreToolUse",
      "--tool", tool, "--guard", guardNameOf(message)], {
      input: JSON.stringify({ tool_input: { command } }), encoding: "utf8", timeout: 3000,
      // El motivo puede citar lo detectado: por el entorno (solo la dueña), no por argv (/proc).
      env: { ...process.env, SAVIA_GUARD_BLOCK_REASON: message.split("\n")[0] },
    });
    return res.status === 0 && !res.error;
  } catch {
    return false;
  }
}
