/**
 * Piezas comunes de los adaptadores de API de Soul Continuidad v1 (SE-490).
 *
 * - `Stop`: fallo con estado del contrato; el adaptador no aporta nada (fail-closed).
 * - `claim`: afirmación con título limpio, marcada como texto no fiable y con TTL.
 * - `token`: credencial del almacén; traduce sus errores a estados del contrato.
 * - `check` / `getJson` / `odataAll`: lectura con tope de páginas, sin seguir enlaces ajenos.
 *
 * Nunca guarda ni devuelve cuerpos: los adaptadores piden solo metadatos y copian
 * campos escalares concretos, nunca respuestas enteras.
 */

import { type Claim, type ClaimType, type Route, claimKey, cleanText, iso, parseTs } from "../contract/claims.ts";
import type { AdapterContext, AdapterResult, AdapterStatus, SourceAdapter, TransportResponse } from "../contract/adapter.ts";
import { type ApiAdapterName, DESCRIPTORS } from "./descriptors.ts";

/** Respuesta JSON de una fuente: se lee campo a campo; su forma no es nuestra. */
// biome-ignore lint/suspicious/noExplicitAny: JSON externo validado campo a campo
export type J = any;

export const DAY = 86_400_000;

/** Tope de páginas por colección y lectura (riesgo R3 de la viabilidad). */
export const DEFAULT_MAX_PAGES = 20;

export class Stop extends Error {
  readonly status: Exclude<AdapterStatus, "ok">;
  readonly fallback: Route | "manual" | null;
  constructor(status: Exclude<AdapterStatus, "ok">, message: string, fallback: Route | "manual" | null = null) {
    super(message);
    this.status = status;
    this.fallback = fallback;
  }
}

export function nowMs(ctx: AdapterContext): number {
  const t = parseTs(ctx.now);
  if (t === null) throw new Stop("error", "Instante de lectura inválido.");
  return t;
}

/** Afirmación con los valores por defecto del contrato y el TTL del adaptador. */
export function claim(ctx: AdapterContext, adapter: ApiAdapterName, type: ClaimType, ref: string, over: Partial<Claim>): Claim {
  const title = cleanText(over.title);
  const c: Claim = {
    key: claimKey(adapter, type, ref),
    claim_type: type,
    state: "OBSERVED",
    source_refs: [{ adapter, route: ctx.route, ref }],
    sensitivity: ctx.sensitivity,
    observed_at: ctx.now,
    valid_until: iso(nowMs(ctx) + DESCRIPTORS[adapter].ttl_s * 1000),
    event_at: null,
    due_at: null,
    open: true,
    awaiting_operator: false,
    attrs: {},
    ...over,
    title,
  };
  if (title !== null) c.untrusted_text = true;
  else delete c.untrusted_text;
  return c;
}

/** Un `ref` nativo no puede llevar `:` (la clave se parte por ahí) ni espacios. */
export function safeRef(v: unknown): string | null {
  if (typeof v !== "string" && typeof v !== "number") return null;
  const s = String(v);
  return s && !/[:\s]/.test(s) ? s : null;
}

/** Fecha de una fuente a ISO UTC. Sin zona solo se acepta si la fuente declara UTC. */
export function toIso(v: unknown, assumeUtc = false): string | null {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}/.test(v)) return null;
  const zoned = /(Z|[+-]\d{2}:?\d{2})$/.test(v);
  if (!zoned && !assumeUtc && v.includes("T")) return null;
  const ms = Date.parse(zoned || !v.includes("T") ? v : `${v}Z`);
  return Number.isFinite(ms) ? iso(ms) : null;
}

/** Código de un error de credencial, sin depender de la identidad de la clase. */
function credCode(e: unknown): string | null {
  if (typeof e !== "object" || e === null) return null;
  const code = (e as { code?: unknown }).code;
  return typeof code === "string" ? code : null;
}

export async function token(ctx: AdapterContext, service: string, scopes: string[]): Promise<string> {
  let t: unknown;
  try {
    t = await ctx.credentials.acquire(service, scopes);
  } catch (e) {
    const code = credCode(e);
    if (code === "admin_consent_required") {
      throw new Stop("admin_consent_required",
        "El inquilino exige consentimiento de administración para estos permisos. No se activa la ruta por API; puedes activar la ruta web.",
        ctx.route === "graph" ? "web" : "manual");
    }
    if (code === "session_expired") throw new Stop("session_expired", "Vuelve a iniciar sesión en el perfil de Soul.");
    throw new Stop("token_expired", "No hay credencial vigente: vuelve a iniciar sesión.");
  }
  if (typeof t !== "string" || !t) throw new Stop("token_expired", "No hay credencial: vuelve a iniciar sesión.");
  return t;
}

/** Traduce el estado HTTP a un estado del contrato. Solo 200 con JSON sigue adelante. */
export function check(r: TransportResponse, label: string, opts: { forbiddenIsConsent?: boolean } = {}): J {
  if (r.status === 401 || r.status === 203) throw new Stop("token_expired", `La credencial de ${label} caducó: vuelve a iniciar sesión.`);
  if (r.status === 403 && opts.forbiddenIsConsent) {
    throw new Stop("admin_consent_required",
      `${label} deniega el permiso delegado: probablemente exige consentimiento de administración. Puedes activar la ruta web.`, "web");
  }
  if (r.status === 429 || r.status === 503) throw new Stop("unavailable", `${label} limita las peticiones; se reintentará en la próxima lectura.`);
  if (r.status !== 200) throw new Stop("error", `${label} respondió ${r.status}.`);
  if (typeof r.body !== "object" || r.body === null) throw new Stop("error", `${label} devolvió una respuesta inesperada.`);
  return r.body;
}

export interface GetOpts {
  headers?: Record<string, string>;
  forbiddenIsConsent?: boolean;
  /** Esquema de autorización: `Bearer` (por defecto) o `Basic` con el valor ya codificado. */
  scheme?: "Bearer" | "Basic";
}

export function authHeader(tok: string, scheme: GetOpts["scheme"] = "Bearer"): string {
  return `${scheme} ${tok}`;
}

export async function getJson(ctx: AdapterContext, service: string, tok: string, url: string, label: string, opts: GetOpts = {}): Promise<J> {
  const r = await ctx.transport.request({ service, method: "GET", url, headers: { ...opts.headers, Authorization: authHeader(tok, opts.scheme) } });
  return check(r, label, opts);
}

/**
 * Un enlace de paginación o delta se sigue solo si apunta al mismo servicio: una
 * respuesta manipulada no puede llevarse el token a otro host.
 */
export function sameOrigin(link: string, first: string, label: string): string {
  if (link.startsWith("/")) return localPath(link, label);
  let u: URL;
  try {
    u = new URL(link);
  } catch {
    throw new Stop("error", `${label}: enlace de paginación inválido.`);
  }
  // Petición relativa: el transporte pone la base del servicio; del enlace solo vale la ruta.
  if (first.startsWith("/")) return localPath(`${u.pathname}${u.search}`, label);
  if (new URL(first).origin !== u.origin) throw new Stop("error", `${label}: enlace de paginación hacia otro origen; se descarta.`);
  return link;
}

/**
 * Una ruta relativa empieza por una sola `/` y no lleva `\`: `//host/x` o `/\host/x`
 * se resolverían como URL de otro host y el token saldría con ellas.
 */
function localPath(p: string, label: string): string {
  if (!/^\/(?![/\\])/.test(p) || p.includes("\\")) throw new Stop("error", `${label}: enlace de paginación hacia otro origen; se descarta.`);
  return p;
}

/**
 * Sigue `@odata.nextLink` hasta `maxPages`. Si quedan páginas al llegar al tope,
 * falla cerrado: una colección incompleta daría hechos falsos (p. ej. un hilo
 * «esperando» cuya respuesta estaba en la página que no se leyó).
 */
export async function odataAll(ctx: AdapterContext, service: string, tok: string, url: string, label: string,
  opts: GetOpts & { maxPages?: number } = {}): Promise<J[]> {
  const out: J[] = [];
  const max = opts.maxPages ?? DEFAULT_MAX_PAGES;
  let next: string | undefined = url;
  for (let i = 0; next; i++) {
    if (i >= max) throw new Stop("unavailable", `${label}: la colección supera el tope de ${max} páginas; no se dan datos incompletos.`);
    const b = await getJson(ctx, service, tok, i === 0 ? next : sameOrigin(next, url, label), label, opts);
    if (Array.isArray(b.value)) out.push(...b.value);
    next = typeof b["@odata.nextLink"] === "string" ? b["@odata.nextLink"] : undefined;
  }
  return out;
}

/** Envuelve la lectura: cualquier excepción ajena al contrato es `error`, sin claims. */
export function adapter(name: ApiAdapterName, fn: (ctx: AdapterContext) => Promise<Claim[]>): SourceAdapter {
  const d = DESCRIPTORS[name];
  return {
    name,
    routes: [...d.routes],
    purpose: d.purpose,
    async read(ctx): Promise<AdapterResult> {
      if (!d.routes.includes(ctx.route)) {
        return { status: "error", route: ctx.route, message: `Ruta ${ctx.route} no admitida por ${name}.`, fallback: null };
      }
      try {
        return { status: "ok", route: ctx.route, claims: await fn(ctx) };
      } catch (e) {
        if (e instanceof Stop) return { status: e.status, route: ctx.route, message: e.message, fallback: e.fallback };
        return { status: "error", route: ctx.route, message: `Error interno del adaptador ${name}.`, fallback: null };
      }
    },
  };
}

export function emailsOf(ctx: AdapterContext): Set<string> {
  return new Set(ctx.operator.identities.emails.map((x) => x.toLowerCase()));
}

export function domainOf(addr: string): string {
  return addr.split("@")[1]?.toLowerCase() ?? "";
}
