/**
 * Piezas de ejecución real del núcleo (SE-490): transporte de solo lectura.
 *
 * - `fetchTransport`: solo GET/HEAD; un POST de lectura solo si su URL exacta está en una
 *   lista cerrada que declara el adaptador. Solo HTTPS, salvo loopback (dobles locales).
 * - El registro de adaptadores del producto está en `connectors.ts` (`productionAdapters`).
 */

import type { Transport, TransportRequest, TransportResponse } from "../contract/adapter.ts";

// Solo literales: un nombre como «localhost» se resuelve por DNS o por hosts y podría no ser loopback.
const LOOPBACK = new Set(["127.0.0.1", "[::1]"]);
const MAX_BODY = 8 * 1024 * 1024;

/** Lee el cuerpo cortando en cuanto pasa de `max` bytes: una fuente hostil no llena la memoria. */
async function readCapped(r: Response, max: number): Promise<string> {
  const declared = Number(r.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > max) {
    await r.body?.cancel();
    throw new Error("respuesta demasiado grande");
  }
  if (!r.body) return "";
  const reader = r.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      await reader.cancel();
      throw new Error("respuesta demasiado grande");
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString("utf8");
}

export function fetchTransport(opts: { readPost?: string[]; timeoutMs?: number; maxBody?: number } = {}): Transport {
  const readPost = new Set(opts.readPost ?? []);
  const maxBody = opts.maxBody ?? MAX_BODY;
  return {
    async request(req: TransportRequest): Promise<TransportResponse> {
      const url = new URL(req.url);
      if (url.protocol !== "https:" && !(url.protocol === "http:" && LOOPBACK.has(url.hostname))) {
        throw new Error(`solo https: ${url.origin}`);
      }
      const m = req.method;
      const readOnly = m === "GET" || m === "HEAD" || (m === "POST" && readPost.has(req.url) && url.href === req.url);
      if (!readOnly) throw new Error(`solo lectura: ${m} no permitido`);
      const r = await fetch(url, {
        method: m,
        headers: { ...(req.headers ?? {}), ...(req.body !== undefined ? { "content-type": "application/json" } : {}) },
        body: req.body === undefined ? undefined : JSON.stringify(req.body),
        redirect: "manual",
        signal: AbortSignal.timeout(opts.timeoutMs ?? 20_000),
      });
      const text = await readCapped(r, maxBody);
      let body: unknown = text;
      try { body = text ? JSON.parse(text) : null; } catch { /* no JSON: se devuelve texto */ }
      const headers: Record<string, string> = {};
      r.headers.forEach((v, k) => { headers[k] = v; });
      return { status: r.status, headers, body };
    },
  };
}
