import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { HttpTransport, TransportRefused, parseRetryAfter } from "../../src/adapters/http-transport.ts";

async function serve(handler: (req: IncomingMessage, res: ServerResponse, body: string) => void) {
  const srv = createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => handler(req, res, body));
  });
  await new Promise<void>((r) => srv.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${(srv.address() as AddressInfo).port}`;
  return { base, close: () => new Promise<void>((r) => srv.close(() => r())) };
}

const json = (res: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}) => {
  res.writeHead(status, { "content-type": "application/json", ...headers });
  res.end(JSON.stringify(body));
};

test("GET relativo contra la base del servicio, con JSON y cabeceras en minúscula", async () => {
  const s = await serve((req, res) => json(res, 200, { path: req.url, auth: req.headers.authorization }, { "X-Uno": "1" }));
  try {
    const t = new HttpTransport({ bases: { graph: `${s.base}/v1.0-base` } });
    const r = await t.request({ service: "graph", method: "GET", url: "/v1.0/me?x=1", headers: { Authorization: "Bearer abc" } });
    assert.equal(r.status, 200);
    assert.deepEqual(r.body, { path: "/v1.0-base/v1.0/me?x=1", auth: "Bearer abc" });
    assert.equal(r.headers["x-uno"], "1");
  } finally {
    await s.close();
  }
});

test("429 con Retry-After: espera lo indicado y reintenta", async () => {
  let n = 0;
  const waits: number[] = [];
  const s = await serve((_q, res) => (++n < 3 ? json(res, 429, { error: {} }, { "Retry-After": "2" }) : json(res, 200, { ok: true })));
  try {
    const t = new HttpTransport({ bases: { graph: s.base }, sleep: async (ms) => { waits.push(ms); } });
    const r = await t.request({ service: "graph", method: "GET", url: "/x" });
    assert.equal(r.status, 200);
    assert.equal(n, 3);
    assert.deepEqual(waits, [2000, 2000]);
  } finally {
    await s.close();
  }
});

test("429 persistente: devuelve el 429 tras el máximo de reintentos (no bucle infinito)", async () => {
  let n = 0;
  const s = await serve((_q, res) => { n++; json(res, 429, {}, { "Retry-After": "1" }); });
  try {
    const t = new HttpTransport({ bases: { graph: s.base }, maxRetries: 2, sleep: async () => {} });
    const r = await t.request({ service: "graph", method: "GET", url: "/x" });
    assert.equal(r.status, 429);
    assert.equal(n, 3);
  } finally {
    await s.close();
  }
});

test("Retry-After por encima del tope: no espera, devuelve el 429", async () => {
  let n = 0;
  const waits: number[] = [];
  const s = await serve((_q, res) => { n++; json(res, 429, {}, { "Retry-After": "3600" }); });
  try {
    const t = new HttpTransport({ bases: { graph: s.base }, maxWaitMs: 30_000, sleep: async (ms) => { waits.push(ms); } });
    const r = await t.request({ service: "graph", method: "GET", url: "/x" });
    assert.equal(r.status, 429);
    assert.equal(n, 1);
    assert.deepEqual(waits, []);
  } finally {
    await s.close();
  }
});

test("parseRetryAfter: segundos, fecha HTTP y valores inválidos", () => {
  assert.equal(parseRetryAfter("5", 0), 5000);
  assert.equal(parseRetryAfter(new Date(10_000).toUTCString(), 4_000), 6000);
  assert.equal(parseRetryAfter(undefined, 0), null);
  assert.equal(parseRetryAfter("mañana", 0), null);
  assert.equal(parseRetryAfter("-3", 0), null);
});

test("solo lectura: rechaza POST salvo las lecturas por POST de la lista cerrada", async () => {
  let hits = 0;
  const s = await serve((req, res, body) => { hits++; json(res, 200, { method: req.method, body: JSON.parse(body || "null") }); });
  try {
    const t = new HttpTransport({ bases: { ado: s.base, graph: s.base } });
    await assert.rejects(t.request({ service: "graph", method: "POST", url: "/v1.0/me/sendMail", body: {} }), TransportRefused);
    await assert.rejects(t.request({ service: "graph", method: "PATCH", url: "/v1.0/me/messages/1", body: {} }), TransportRefused);
    await assert.rejects(t.request({ service: "ado", method: "POST", url: "/_apis/wit/workitems/1", body: {} }), TransportRefused);
    assert.equal(hits, 0);
    const r = await t.request({ service: "ado", method: "POST", url: "/proj/_apis/wit/wiql?api-version=7.1", body: { query: "SELECT" } });
    assert.deepEqual(r.body, { method: "POST", body: { query: "SELECT" } });
  } finally {
    await s.close();
  }
});

test("POST de lectura: una URL absoluta del mismo origen fuera de la ruta de la base se rechaza", async () => {
  let hits = 0;
  const s = await serve((_q, res) => { hits++; json(res, 200, { ok: true }); });
  try {
    const t = new HttpTransport({ bases: { ado: `${s.base}/org` } });
    await assert.rejects(t.request({ service: "ado", method: "POST", url: `${s.base}/abc/proj/_apis/wit/wiql`, body: {} }), TransportRefused);
    await assert.rejects(t.request({ service: "ado", method: "POST", url: `${s.base}/orgx/_apis/wit/wiql`, body: {} }), TransportRefused);
    assert.equal(hits, 0);
    assert.equal((await t.request({ service: "ado", method: "POST", url: `${s.base}/org/proj/_apis/wit/wiql`, body: {} })).status, 200);
    assert.equal((await t.request({ service: "ado", method: "POST", url: "/proj/_apis/wit/wiql", body: {} })).status, 200);
  } finally {
    await s.close();
  }
});

test("respuesta por encima de maxBytes: error, con o sin Content-Length; en el tope, se lee", async () => {
  const big = "x".repeat(2000);
  const s = await serve((req, res) => {
    if (req.url === "/chunked") { res.writeHead(200, { "content-type": "text/plain" }); res.write(big); res.end(big); return; }
    if (req.url === "/justo") { res.writeHead(200, { "content-type": "text/plain" }); res.end("y".repeat(1000)); return; }
    res.writeHead(200, { "content-type": "text/plain", "content-length": String(big.length) });
    res.end(big);
  });
  try {
    const t = new HttpTransport({ bases: { graph: s.base }, maxBytes: 1000 });
    await assert.rejects(t.request({ service: "graph", method: "GET", url: "/declarada" }), /supera 1000 bytes/);
    await assert.rejects(t.request({ service: "graph", method: "GET", url: "/chunked" }), /supera 1000 bytes/);
    assert.equal((await t.request({ service: "graph", method: "GET", url: "/justo" })).body, "y".repeat(1000));
  } finally {
    await s.close();
  }
});

test("rechaza URL absoluta de otro origen y servicios sin base", async () => {
  const t = new HttpTransport({ bases: { graph: "https://graph.example" } });
  await assert.rejects(t.request({ service: "graph", method: "GET", url: "https://malo.example/v1.0/me" }), TransportRefused);
  await assert.rejects(t.request({ service: "nadie", method: "GET", url: "/x" }), TransportRefused);
});

test("no sigue redirecciones: el token no viaja a otro host", async () => {
  let other = 0;
  const o = await serve((_q, res) => { other++; json(res, 200, {}); });
  const s = await serve((_q, res) => { res.writeHead(302, { Location: `${o.base}/robo` }); res.end(); });
  try {
    const t = new HttpTransport({ bases: { graph: s.base } });
    const r = await t.request({ service: "graph", method: "GET", url: "/x", headers: { Authorization: "Bearer secreto" } });
    assert.equal(r.status, 302);
    assert.equal(other, 0);
  } finally {
    await s.close();
    await o.close();
  }
});

test("un error de red no filtra el token en el mensaje", async () => {
  const t = new HttpTransport({ bases: { graph: "http://127.0.0.1:9" }, timeoutMs: 2000 });
  await assert.rejects(t.request({ service: "graph", method: "GET", url: "/x", headers: { Authorization: "Bearer secreto-123" } }),
    (e: Error) => !e.message.includes("secreto-123"));
});

test("una ruta relativa al esquema (//host o /\\host) no saca el token a otro host", async () => {
  const seen: string[] = [];
  const fetchFn = (async (u: URL | string) => {
    seen.push(String(u));
    return new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  // Base sin ruta, como Graph, GitHub o Google: el caso que antes resolvía a otro host.
  const t = new HttpTransport({ bases: { graph: "https://graph.example" }, fetch: fetchFn });
  for (const url of ["//atacante.example/x", "/\\atacante.example/x", "/v1.0/a\\b"]) {
    await assert.rejects(t.request({ service: "graph", method: "GET", url, headers: { Authorization: "Bearer secreto" } }), TransportRefused);
  }
  assert.deepEqual(seen, []);
  await t.request({ service: "graph", method: "GET", url: "/v1.0/me" });
  assert.deepEqual(seen, ["https://graph.example/v1.0/me"]);
});

test("la ruta relativa siempre lleva el prefijo de la base, aunque empiece igual (proyecto de ADO llamado como la organización)", async () => {
  const s = await serve((req, res) => json(res, 200, { path: req.url }));
  try {
    const t = new HttpTransport({ bases: { ado: `${s.base}/contoso` } });
    const a = await t.request({ service: "ado", method: "POST", url: "/contoso/_apis/wit/wiql?api-version=7.1", body: { query: "x" } });
    assert.deepEqual(a.body, { path: "/contoso/contoso/_apis/wit/wiql?api-version=7.1" });
    const b = await t.request({ service: "ado", method: "GET", url: "/contoso" });
    assert.deepEqual(b.body, { path: "/contoso/contoso" });
  } finally {
    await s.close();
  }
});

test("segmentos `.` y `..` (también codificados) se rechazan: no sacan la ruta del prefijo", async () => {
  const seen: string[] = [];
  const fetchFn = (async (u: URL | string) => {
    seen.push(String(u));
    return new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  const t = new HttpTransport({ bases: { ado: "https://dev.example/contoso" }, fetch: fetchFn });
  for (const url of ["/../otra/_apis/x", "/a/./b", "/%2e%2e/otra/x", "/.%2E/otra/x", "/%2E/x",
    "/proj%2f..%2fotra/_apis/x", "/proj%2F..%2Fotra/x", "/proj%5c..%5cotra/x", "https://dev.example/contoso/p%2f..%2fotra/x"]) {
    await assert.rejects(t.request({ service: "ado", method: "GET", url, headers: { Authorization: "Bearer secreto" } }), TransportRefused, url);
  }
  assert.deepEqual(seen, []);
  // Un punto dentro de un segmento no es un segmento de punto, ni lo es en la consulta.
  await t.request({ service: "ado", method: "GET", url: "/proj/v1.2/x?q=../a" });
  // `%2f` en la consulta no es ruta: se permite.
  await t.request({ service: "ado", method: "GET", url: "/proj/x?q=a%2Fb" });
  assert.deepEqual(seen, ["https://dev.example/contoso/proj/v1.2/x?q=../a", "https://dev.example/contoso/proj/x?q=a%2Fb"]);
});

test("GET absoluto del mismo origen fuera del prefijo de la base: rechazado, no solo el POST", async () => {
  const seen: string[] = [];
  const fetchFn = (async (u: URL | string) => {
    seen.push(String(u));
    return new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  const t = new HttpTransport({ bases: { ado: "https://dev.example/contoso" }, fetch: fetchFn });
  for (const url of ["https://dev.example/otra-org/_apis/x", "https://dev.example/contoso-b/_apis/x"]) {
    await assert.rejects(t.request({ service: "ado", method: "GET", url, headers: { Authorization: "Bearer secreto" } }), TransportRefused, url);
  }
  assert.deepEqual(seen, []);
  await t.request({ service: "ado", method: "GET", url: "https://dev.example/contoso/_apis/x" });
  assert.deepEqual(seen, ["https://dev.example/contoso/_apis/x"]);
});
