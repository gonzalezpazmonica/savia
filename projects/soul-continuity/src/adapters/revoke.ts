/**
 * Revocación de un adaptador de API (SE-490, AC-5).
 *
 * Borra la caché local del adaptador para ese operador (sincronización delta y
 * metadatos), primero, y después sus tokens del almacén del sistema, en todas las variantes de
 * permisos que declara. No toca otros adaptadores ni otros operadores. Si el
 * almacén falla, la revocación falla y no informa de un borrado que no ocurrió.
 * El libro de correcciones y el consentimiento los gestiona el núcleo.
 */

import { existsSync, rmSync } from "node:fs";
import { adapterCacheDir } from "./delta-cache.ts";
import { DESCRIPTORS, isApiAdapter } from "./descriptors.ts";

export interface TokenRevoker {
  revoke(service: string, scopes: string[]): Promise<boolean>;
}

export interface RevokeResult {
  adapter: string;
  cache_removed: boolean;
  tokens_removed: number;
}

export async function revokeAdapter(o: { adapter: string; operatorRef: string; stateDir: string; store: TokenRevoker }): Promise<RevokeResult> {
  if (!isApiAdapter(o.adapter)) throw new Error(`Adaptador sin revocación de API: ${o.adapter.slice(0, 40)}`);
  const d = DESCRIPTORS[o.adapter];
  // Primero la caché (datos personales): si después falla el almacén, la revocación
  // falla igualmente, pero no deja asuntos y direcciones en disco.
  const dir = adapterCacheDir(o.stateDir, o.operatorRef, o.adapter);
  const had = existsSync(dir);
  rmSync(dir, { recursive: true, force: true });
  if (existsSync(dir)) throw new Error("No se pudo borrar la caché del adaptador.");
  let tokens = 0;
  for (const scopes of d.scopes) if (await o.store.revoke(d.service, scopes)) tokens++;
  return { adapter: o.adapter, cache_removed: had, tokens_removed: tokens };
}
