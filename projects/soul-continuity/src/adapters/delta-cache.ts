/**
 * Caché de sincronización de los adaptadores (delta queries de Graph).
 *
 * Guarda, por operador y adaptador, el enlace delta o de continuación y los
 * metadatos mínimos de cada elemento (id, hilo, remitente, destinatarios, asunto,
 * fecha, marca). Nunca cuerpos ni tokens: `save` rechaza campos de cuerpo.
 *
 * El directorio del operador usa el mismo hash que el núcleo de referencia
 * (`op-<sha256(ref)[:16]>`), así que la caché vive junto a su libro y se borra
 * con él. Ficheros con permisos 0600.
 */

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, rmSync, writeFileSync, renameSync } from "node:fs";
import { join } from "node:path";

export type Meta = Record<string, string | number | boolean | null | string[]>;

export interface DeltaState {
  /** Enlace a seguir en la próxima lectura: `@odata.deltaLink` o, si la ronda quedó a medias, `@odata.nextLink`. */
  link: string | null;
  /** La ronda en curso terminó con un `deltaLink`: los elementos son la foto completa. */
  complete: boolean;
  items: Record<string, Meta>;
}

export interface DeltaCache {
  load(operatorRef: string, adapter: string, key: string): Promise<DeltaState | null>;
  save(operatorRef: string, adapter: string, key: string, state: DeltaState): Promise<void>;
  clear(operatorRef: string, adapter: string): Promise<void>;
}

const BODY_FIELD = /^(body|bodyPreview|content|snippet|text|uniqueBody|description)$/i;

function assertNoBodies(state: DeltaState): void {
  for (const [id, m] of Object.entries(state.items)) {
    for (const k of Object.keys(m)) if (BODY_FIELD.test(k)) throw new Error(`campo de cuerpo en la caché (${id}): ${k}`);
  }
}

const h16 = (s: string) => createHash("sha256").update(s).digest("hex").slice(0, 16);

export function operatorDir(stateDir: string, operatorRef: string): string {
  return join(stateDir, `op-${h16(operatorRef)}`);
}

export function adapterCacheDir(stateDir: string, operatorRef: string, adapter: string): string {
  if (!/^[a-z0-9-]+$/.test(adapter)) throw new Error("nombre de adaptador inválido");
  return join(operatorDir(stateDir, operatorRef), "adapters", adapter);
}

export class FileDeltaCache implements DeltaCache {
  private readonly stateDir: string;
  constructor(stateDir: string) {
    this.stateDir = stateDir;
  }

  async load(op: string, adapter: string, key: string): Promise<DeltaState | null> {
    try {
      const v = JSON.parse(readFileSync(join(adapterCacheDir(this.stateDir, op, adapter), `${h16(key)}.json`), "utf8"));
      if (typeof v !== "object" || v === null || typeof v.items !== "object" || v.items === null) return null;
      if (v.link !== null && typeof v.link !== "string") return null;
      return { link: v.link, complete: v.complete === true, items: v.items };
    } catch {
      return null;
    }
  }

  async save(op: string, adapter: string, key: string, state: DeltaState): Promise<void> {
    assertNoBodies(state);
    const dir = adapterCacheDir(this.stateDir, op, adapter);
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    const f = join(dir, `${h16(key)}.json`);
    const tmp = `${f}.tmp`;
    writeFileSync(tmp, JSON.stringify(state), { mode: 0o600 });
    renameSync(tmp, f);
  }

  async clear(op: string, adapter: string): Promise<void> {
    rmSync(adapterCacheDir(this.stateDir, op, adapter), { recursive: true, force: true });
  }
}

export class MemoryDeltaCache implements DeltaCache {
  private readonly m = new Map<string, string>();
  private k(op: string, adapter: string, key: string) {
    return JSON.stringify([op, adapter, key]);
  }
  async load(op: string, adapter: string, key: string): Promise<DeltaState | null> {
    const v = this.m.get(this.k(op, adapter, key));
    return v ? JSON.parse(v) : null;
  }
  async save(op: string, adapter: string, key: string, state: DeltaState): Promise<void> {
    assertNoBodies(state);
    this.m.set(this.k(op, adapter, key), JSON.stringify(state));
  }
  async clear(op: string, adapter: string): Promise<void> {
    for (const k of [...this.m.keys()]) {
      const [o, a] = JSON.parse(k);
      if (o === op && a === adapter) this.m.delete(k);
    }
  }
}
