/**
 * Transporte HTTP de producción para los adaptadores de API (SE-490).
 *
 * - Base por servicio (`graph`, `google`, `jira`, `ado`, `github`); una URL
 *   absoluta solo se acepta si es del mismo origen que su base.
 * - Solo lectura: GET y HEAD; POST solo para las lecturas de una lista cerrada
 *   (WIQL de Azure DevOps). Cualquier otro método se rechaza antes de salir.
 * - 429 y 503: respeta `Retry-After` hasta `maxRetries` y `maxWaitMs`; si la
 *   espera pedida supera el tope, devuelve la respuesta y el adaptador queda
 *   `unavailable` hasta la siguiente lectura.
 * - No sigue redirecciones (el token no viaja a otro host) y nunca pone
 *   cabeceras ni URLs con token en los mensajes de error.
 * Usa el `fetch` de Node.js: sin dependencias.
 */

import type { Transport, TransportRequest, TransportResponse } from "../contract/adapter.ts";

/** Lecturas que la API solo admite por POST: servicio y ruta exactos. */
export const READ_POSTS: { service: string; path: RegExp }[] = [
  { service: "ado", path: /^(\/[^/?#]+){0,2}\/_apis\/wit\/wiql$/ },
];

export class TransportRefused extends Error {}

export interface HttpTransportOptions {
  bases: Record<string, string>;
  fetch?: typeof fetch;
  maxRetries?: number;
  maxWaitMs?: number;
  timeoutMs?: number;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
}

/** `Retry-After` en milisegundos: segundos o fecha HTTP. Inválido → null. */
export function parseRetryAfter(v: string | null | undefined, nowMs: number): number | null {
  if (v == null || v === "") return null;
  if (/^\d+$/.test(v.trim())) return Number(v.trim()) * 1000;
  const t = Date.parse(v);
  if (!Number.isFinite(t) || !/[a-z]/i.test(v)) return null;
  return Math.max(0, t - nowMs);
}

export class HttpTransport implements Transport {
  private readonly bases: Record<string, URL>;
  private readonly fetchFn: typeof fetch;
  private readonly maxRetries: number;
  private readonly maxWaitMs: number;
  private readonly timeoutMs: number;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly now: () => number;

  constructor(o: HttpTransportOptions) {
    this.bases = Object.fromEntries(Object.entries(o.bases).map(([k, v]) => [k, new URL(v.endsWith("/") ? v.slice(0, -1) : v)]));
    this.fetchFn = o.fetch ?? fetch;
    this.maxRetries = o.maxRetries ?? 3;
    this.maxWaitMs = o.maxWaitMs ?? 60_000;
    this.timeoutMs = o.timeoutMs ?? 30_000;
    this.sleep = o.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
    this.now = o.now ?? Date.now;
  }

  private resolve(req: TransportRequest): URL {
    const base = Object.prototype.hasOwnProperty.call(this.bases, req.service) ? this.bases[req.service] : undefined;
    if (!base) throw new TransportRefused(`servicio sin base configurada: ${req.service}`);
    if (req.url.startsWith("/")) return new URL(`${base.pathname.replace(/\/$/, "")}${req.url}`, base.origin);
    let u: URL;
    try {
      u = new URL(req.url);
    } catch {
      throw new TransportRefused("URL inválida");
    }
    if (u.origin !== base.origin) throw new TransportRefused(`origen no permitido para ${req.service}`);
    return u;
  }

  private allowed(req: TransportRequest, u: URL): boolean {
    const m = req.method.toUpperCase();
    if (m === "GET" || m === "HEAD") return true;
    if (m !== "POST") return false;
    const base = this.bases[req.service];
    const rel = u.pathname.slice(base.pathname.replace(/\/$/, "").length);
    return READ_POSTS.some((r) => r.service === req.service && r.path.test(rel));
  }

  async request(req: TransportRequest): Promise<TransportResponse> {
    const u = this.resolve(req);
    if (!this.allowed(req, u)) throw new TransportRefused(`método ${req.method} no permitido (solo lectura) en ${req.service}`);
    const headers: Record<string, string> = { Accept: "application/json", ...req.headers };
    let body: string | undefined;
    if (req.body !== undefined) {
      body = JSON.stringify(req.body);
      headers["Content-Type"] = "application/json";
    }
    for (let attempt = 0; ; attempt++) {
      let res: Response;
      try {
        res = await this.fetchFn(u, {
          method: req.method.toUpperCase(), headers, body, redirect: "manual", signal: AbortSignal.timeout(this.timeoutMs),
        });
      } catch (e) {
        // Sin cabeceras ni URL completa: el mensaje no puede llevar el token.
        throw new Error(`${req.service}: fallo de red (${(e as Error).name})`);
      }
      const out = await this.read(res);
      if ((out.status === 429 || out.status === 503) && attempt < this.maxRetries) {
        const wait = parseRetryAfter(out.headers["retry-after"], this.now()) ?? Math.min(1000 * 2 ** attempt, this.maxWaitMs);
        if (wait <= this.maxWaitMs) {
          await this.sleep(wait);
          continue;
        }
      }
      return out;
    }
  }

  private async read(res: Response): Promise<TransportResponse> {
    const headers: Record<string, string> = {};
    res.headers.forEach((v, k) => { headers[k.toLowerCase()] = v; });
    const text = await res.text();
    let body: unknown = text;
    if (/json/i.test(headers["content-type"] ?? "") || /^[[{]/.test(text.trim())) {
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }
    }
    if (text === "") body = null;
    return { status: res.status, headers, body };
  }
}
