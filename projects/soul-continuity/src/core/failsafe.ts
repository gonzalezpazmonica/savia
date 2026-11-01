/**
 * Fail-safe durable (portado de Soul F1): un STOP del operador sobrevive a reinicios.
 *
 * - `stop` deja el fichero STOP con escritura atómica; mientras exista, el núcleo no lee
 *   ninguna fuente y la API responde 503.
 * - Fail-closed: un STOP ilegible, vacío o corrupto cuenta como STOP. Solo `resume`, orden
 *   explícita del operador, lo levanta; nada lo levanta solo (ni el tiempo ni un reinicio).
 * - Cada STOP y cada reanudación quedan en `failsafe.jsonl`.
 */

import { existsSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { appendJsonl, writeJson } from "./store.ts";

export const STOP_FILE = "STOP";
const LOG = "failsafe.jsonl";

export interface StopState {
  stopped: boolean;
  reason?: string;
  at?: string;
  /** El fichero existe pero no se pudo leer: se trata como STOP. */
  corrupt?: boolean;
}

export class StoppedError extends Error {
  readonly code = "STOPPED";
  constructor(state: StopState) {
    super(`Soul está detenido${state.reason ? `: ${state.reason}` : ""}. Reanuda con «soul resume».`);
  }
}

export function stopState(dataDir: string): StopState {
  const p = join(dataDir, STOP_FILE);
  if (!existsSync(p)) return { stopped: false };
  try {
    const v = JSON.parse(readFileSync(p, "utf8")) as { reason?: unknown; at?: unknown };
    return { stopped: true, reason: typeof v.reason === "string" ? v.reason : undefined, at: typeof v.at === "string" ? v.at : undefined };
  } catch {
    return { stopped: true, corrupt: true, reason: "fichero STOP ilegible" };
  }
}

export function stop(dataDir: string, reason: string, now: string): StopState {
  writeJson(join(dataDir, STOP_FILE), { reason, at: now });
  appendJsonl(join(dataDir, LOG), { action: "stop", reason, at: now });
  return stopState(dataDir);
}

export function resume(dataDir: string, now: string): StopState {
  const before = stopState(dataDir);
  rmSync(join(dataDir, STOP_FILE), { force: true });
  if (before.stopped) appendJsonl(join(dataDir, LOG), { action: "resume", at: now });
  return stopState(dataDir);
}

export function assertRunning(dataDir: string): void {
  const s = stopState(dataDir);
  if (s.stopped) throw new StoppedError(s);
}
