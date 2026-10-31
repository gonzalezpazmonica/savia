/**
 * Piezas de ejecución real del núcleo (SE-490): transporte de solo lectura y registro de
 * adaptadores del producto.
 *
 * - `fetchTransport`: solo GET/HEAD; un POST de lectura solo si su URL exacta está en una
 *   lista cerrada que declara el adaptador. Solo HTTPS, salvo loopback (dobles locales).
 * - `productionAdapters`: los adaptadores de fuente se integran desde la parte `adapters`
 *   de SE-490. Mientras no estén, una fuente configurada falla cerrada («no instalado»).
 */

import type { AdapterRegistry } from "./engine.ts";
import type { Transport, TransportRequest, TransportResponse } from "../contract/adapter.ts";

export function productionAdapters(): AdapterRegistry {
  return {};
}

const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);
const MAX_BODY = 8 * 1024 * 1024;

export function fetchTransport(opts: { readPost?: string[]; timeoutMs?: number } = {}): Transport {
  const readPost = new Set(opts.readPost ?? []);
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
      const text = await r.text();
      if (text.length > MAX_BODY) throw new Error("respuesta demasiado grande");
      let body: unknown = text;
      try { body = text ? JSON.parse(text) : null; } catch { /* no JSON: se devuelve texto */ }
      const headers: Record<string, string> = {};
      r.headers.forEach((v, k) => { headers[k] = v; });
      return { status: r.status, headers, body };
    },
  };
}
