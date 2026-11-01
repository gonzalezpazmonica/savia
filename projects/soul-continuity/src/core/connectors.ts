/**
 * Registro de los adaptadores reales del producto (SE-490, H-1) y su composición con el sistema.
 *
 * - Ningún adaptador está activo por defecto: el operador los nombra en `connectors.enabled`
 *   de `config.json`. Además, cada fuente necesita su entrada en el perfil con propósito y
 *   consentimiento (lo comprueba el núcleo). Un adaptador no activado responde «no instalado».
 * - `web` (navegador en el perfil dedicado) solo se registra si el operador lo nombra. Se carga
 *   bajo demanda desde `src/web/` (necesita `playwright-core` allí); si falta, la fuente queda
 *   `unavailable`. Sus ficheros viven en `<datos>/web/`, que `soul uninstall` borra (H-4).
 * - Transporte de API: `HttpTransport` de solo lectura con bases HTTPS por servicio. Las de Jira
 *   y Azure DevOps son del sitio u organización del operador y no tienen valor por defecto.
 * - Revocar (AC-5, H-3): caché delta y tokens de todas las variantes de permisos de un adaptador
 *   de API; para `web`, todo `<datos>/web/` (perfil con sus sesiones, huellas, recibos).
 */

import { existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { ADAPTERS, type AdapterContext, type AdapterResult, type SourceAdapter, type Transport } from "../contract/adapter.ts";
import { isApiAdapter } from "../adapters/descriptors.ts";
import { FileDeltaCache } from "../adapters/delta-cache.ts";
import { HttpTransport } from "../adapters/http-transport.ts";
import { makeApiAdapters } from "../adapters/index.ts";
import { revokeAdapter, type TokenRevoker } from "../adapters/revoke.ts";
import type { AdapterRegistry } from "./engine.ts";

export interface ConnectorsConfig {
  /** Adaptadores que el operador activa en esta instalación. Vacío por defecto. */
  enabled: string[];
  /** Bases HTTPS por servicio lógico (graph, google, github, jira, ado). */
  bases?: Record<string, string>;
  /** Aplicación OAuth propia del operador o de su organización (sin secretos salvo el de app instalada de Google). */
  oauth?: {
    microsoft?: { client_id: string; tenant: string; owner: "operator" | "organization" };
    google?: { client_id: string; client_secret?: string; owner: "operator" | "organization" };
  };
}

export const DEFAULT_BASES: Readonly<Record<string, string>> = {
  graph: "https://graph.microsoft.com",
  google: "https://www.googleapis.com",
  github: "https://api.github.com",
};
const SERVICES = new Set(["graph", "google", "github", "jira", "ado"]);
const LOOPBACK = new Set(["127.0.0.1", "[::1]"]);

function isSafeBase(b: string): boolean {
  let u: URL;
  try { u = new URL(b); } catch { return false; }
  if (u.username || u.password || u.search || u.hash) return false;
  return u.protocol === "https:" || (u.protocol === "http:" && LOOPBACK.has(u.hostname));
}

/** Problemas de `connectors` (vacío si es válido o no está). */
export function validateConnectors(c: unknown): string[] {
  if (c === undefined) return [];
  if (typeof c !== "object" || c === null) return ["connectors debe ser un objeto"];
  const v = c as Record<string, unknown>;
  const p: string[] = [];
  if (!Array.isArray(v.enabled)) p.push("connectors.enabled debe ser una lista de adaptadores");
  else {
    for (const a of v.enabled) if (!(ADAPTERS as readonly unknown[]).includes(a)) p.push(`connectors.enabled: adaptador desconocido ${String(JSON.stringify(a)).slice(0, 40)}`);
  }
  if (v.bases !== undefined) {
    if (typeof v.bases !== "object" || v.bases === null) p.push("connectors.bases debe ser un objeto");
    else {
      for (const [k, b] of Object.entries(v.bases)) {
        if (!SERVICES.has(k)) { p.push(`connectors.bases: servicio desconocido ${k.slice(0, 20)}`); continue; }
        if (typeof b !== "string" || !isSafeBase(b)) p.push(`connectors.bases.${k}: solo https (o http a 127.0.0.1/[::1]), sin usuario, consulta ni fragmento`);
      }
    }
  }
  if (v.oauth !== undefined) {
    const o = v.oauth as Record<string, Record<string, unknown>> | null;
    if (typeof o !== "object" || o === null) p.push("connectors.oauth debe ser un objeto");
    else {
      for (const [k, c] of Object.entries(o)) {
        if (k !== "microsoft" && k !== "google") { p.push(`connectors.oauth: proveedor desconocido ${k.slice(0, 20)}`); continue; }
        if (typeof c?.client_id !== "string" || !/^[A-Za-z0-9._-]{1,200}$/.test(c.client_id)) p.push(`connectors.oauth.${k}.client_id inválido`);
        if (c?.owner !== "operator" && c?.owner !== "organization") p.push(`connectors.oauth.${k}.owner: operator | organization`);
        if (k === "microsoft" && (typeof c?.tenant !== "string" || !/^[A-Za-z0-9.-]{1,100}$/.test(c.tenant))) p.push("connectors.oauth.microsoft.tenant inválido");
      }
    }
  }
  return p;
}

export function enabledAdapters(c: ConnectorsConfig | undefined): Set<string> {
  return new Set((c?.enabled ?? []).filter((a) => (ADAPTERS as readonly string[]).includes(a)));
}

/** Transporte de los adaptadores de API: solo lectura y solo hacia las bases declaradas. */
export function apiTransport(c: ConnectorsConfig | undefined, o: { fetch?: typeof fetch } = {}): Transport {
  const bases: Record<string, string> = { ...DEFAULT_BASES };
  for (const [k, b] of Object.entries(c?.bases ?? {})) if (SERVICES.has(k) && isSafeBase(b)) bases[k] = b;
  return new HttpTransport({ bases, fetch: o.fetch });
}

/** Lo mínimo del adaptador web que usa el núcleo (se carga sin acoplar sus tipos ni `playwright-core`). */
export interface WebModule {
  crearAdaptadorWeb(): SourceAdapter;
  prepararPerfilSoul(datos: string): string;
  buscarNavegador(): { ruta: string };
}

const WEB_MODULES = ["../web/adaptador/contrato.ts", "../web/cortafuegos/perfil.ts"];

async function loadWebModule(): Promise<WebModule> {
  // Especificadores no literales: el adaptador web es opcional y no entra en el typecheck del núcleo.
  const [a, b] = await Promise.all(WEB_MODULES.map((m) => import(new URL(m, import.meta.url).href)));
  return { crearAdaptadorWeb: a.crearAdaptadorWeb, prepararPerfilSoul: b.prepararPerfilSoul, buscarNavegador: b.buscarNavegador };
}

export function webDir(dataDir: string): string {
  return join(dataDir, "web");
}

/**
 * Adaptador `web` del producto. Perfil, huellas, recetas desactivadas y recibos van siempre al
 * directorio de datos de Soul: la configuración no puede llevarlos a otro sitio (H-4).
 */
export function productionWebAdapter(dataDir: string, load: () => Promise<WebModule> = loadWebModule): SourceAdapter {
  return {
    name: "web", routes: ["web"], purpose: "Webs sin API, solo lectura con recetas y cortafuegos",
    async read(ctx: AdapterContext): Promise<AdapterResult> {
      let m: WebModule;
      try { m = await load(); } catch {
        return { status: "unavailable", route: "web", fallback: "manual", message: "el adaptador web no está instalado (falta playwright-core en src/web)" };
      }
      const dir = webDir(dataDir);
      try {
        // El navegador sale de SOUL_NAVEGADOR o de las rutas conocidas, nunca de config.json: quien
        // pueda escribir la configuración no elige qué binario arranca Soul.
        const ejecutable = m.buscarNavegador().ruta;
        const perfil = m.prepararPerfilSoul(dataDir);
        const params = {
          ...ctx.params, ejecutable, perfil,
          huellas: join(dir, "huellas.json"), desactivadas: join(dir, "desactivadas.json"), validaciones: join(dir, "validaciones"),
        };
        return await m.crearAdaptadorWeb().read({ ...ctx, params });
      } catch (e) {
        return { status: "error", route: "web", fallback: "manual", message: `el adaptador web no arrancó (${String((e as Error).message).split("\n")[0].slice(0, 160)})` };
      }
    },
  };
}

/** Registro de producción: solo lo que el operador activó. */
export function productionAdapters(o: { connectors?: ConnectorsConfig; dataDir: string; loadWeb?: () => Promise<WebModule> }): AdapterRegistry {
  const on = enabledAdapters(o.connectors);
  const api: Record<string, SourceAdapter> = makeApiAdapters({ cache: new FileDeltaCache(o.dataDir) });
  const reg: AdapterRegistry = {};
  for (const name of on) {
    if (name === "web") reg.web = productionWebAdapter(o.dataDir, o.loadWeb);
    else if (isApiAdapter(name)) reg[name] = api[name];
  }
  return reg;
}

export interface SourceRevocation {
  adapter: string;
  cache_removed: boolean;
  tokens_removed: number;
}

/** AC-5: lo que guarda un adaptador fuera del libro y la instantánea (que purga el núcleo). */
export async function revokeSource(o: { adapter: string; operatorRef: string; dataDir: string; tokens: TokenRevoker }): Promise<SourceRevocation> {
  if (o.adapter === "web") {
    const dir = webDir(o.dataDir);
    const had = existsSync(dir);
    rmSync(dir, { recursive: true, force: true });
    if (existsSync(dir)) throw new Error("No se pudo borrar el perfil web de Soul.");
    return { adapter: "web", cache_removed: had, tokens_removed: 0 };
  }
  if (!isApiAdapter(o.adapter)) throw new Error(`adaptador desconocido: ${o.adapter.slice(0, 40)}`);
  return revokeAdapter({ adapter: o.adapter, operatorRef: o.operatorRef, stateDir: o.dataDir, store: o.tokens });
}
