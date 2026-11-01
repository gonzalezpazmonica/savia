import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { fetchTransport } from "../src/core/runtime.ts";
import { productionAdapters } from "../src/core/connectors.ts";
import { ADAPTERS } from "../src/contract/adapter.ts";

async function server() {
  let hits = 0;
  const s = createServer((req, res) => {
    hits++;
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ method: req.method, url: req.url }));
  });
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const base = `http://127.0.0.1:${(s.address() as AddressInfo).port}`;
  return { base, hits: () => hits, close: () => new Promise<void>((r) => s.close(() => r())) };
}

test("fetchTransport: GET llega y devuelve JSON", async () => {
  const s = await server();
  const t = fetchTransport();
  const r = await t.request({ service: "x", method: "GET", url: `${s.base}/a` });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { method: "GET", url: "/a" });
  await s.close();
});

test("fetchTransport: solo lectura — POST, PUT, PATCH y DELETE se abortan sin salir a la red", async () => {
  const s = await server();
  const t = fetchTransport();
  for (const m of ["POST", "PUT", "PATCH", "DELETE", "get "]) {
    await assert.rejects(t.request({ service: "x", method: m, url: `${s.base}/w` }), /solo lectura/);
  }
  assert.equal(s.hits(), 0);
  await s.close();
});

test("fetchTransport: POST de lectura solo si la URL exacta está en la lista cerrada", async () => {
  const s = await server();
  const t = fetchTransport({ readPost: [`${s.base}/search`] });
  assert.equal((await t.request({ service: "x", method: "POST", url: `${s.base}/search`, body: { q: 1 } })).status, 200);
  await assert.rejects(t.request({ service: "x", method: "POST", url: `${s.base}/search/../update` }), /solo lectura/);
  assert.equal(s.hits(), 1);
  await s.close();
});

test("fetchTransport: solo https salvo loopback", async () => {
  const t = fetchTransport();
  await assert.rejects(t.request({ service: "x", method: "GET", url: "http://example.test/a" }), /https/);
});

test("fetchTransport: «localhost» no cuenta como loopback (se resuelve por DNS); los literales sí", async () => {
  const s = await server();
  const t = fetchTransport();
  await assert.rejects(t.request({ service: "x", method: "GET", url: `${s.base.replace("127.0.0.1", "localhost")}/a` }), /https/);
  assert.equal((await t.request({ service: "x", method: "GET", url: `${s.base}/a` })).status, 200, "control: 127.0.0.1 sí");
  await s.close();
});

test("fetchTransport: corta una respuesta sin fin por encima del límite sin esperar a recibirla entera", async () => {
  const s = createServer((_req, res) => {
    res.writeHead(200, { "content-type": "application/json" }); // sin content-length: chunked
    const chunk = "x".repeat(16 * 1024);
    const iv = setInterval(() => res.write(chunk), 1);
    res.on("close", () => clearInterval(iv));
  });
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const base = `http://127.0.0.1:${(s.address() as AddressInfo).port}`;
  const t = fetchTransport({ maxBody: 64 * 1024, timeoutMs: 5000 });
  await assert.rejects(t.request({ service: "x", method: "GET", url: `${base}/big` }), /demasiado grande/);
  s.closeAllConnections();
  await new Promise<void>((r) => s.close(() => r()));
});

test("fetchTransport: content-length declarado por encima del límite se rechaza; por debajo pasa", async () => {
  const body = JSON.stringify({ a: "y".repeat(2000) });
  const s = createServer((_req, res) => { res.writeHead(200, { "content-type": "application/json", "content-length": Buffer.byteLength(body) }); res.end(body); });
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const base = `http://127.0.0.1:${(s.address() as AddressInfo).port}`;
  await assert.rejects(fetchTransport({ maxBody: 1000 }).request({ service: "x", method: "GET", url: `${base}/a` }), /demasiado grande/);
  assert.equal((await fetchTransport({ maxBody: 4000 }).request({ service: "x", method: "GET", url: `${base}/a` })).status, 200, "control: dentro del límite");
  await new Promise<void>((r) => s.close(() => r()));
});

test("productionAdapters: con todo activado, un adaptador por cada nombre del contrato y con ese nombre", () => {
  const ad = productionAdapters({ dataDir: "/no/se/usa", connectors: { enabled: [...ADAPTERS] } });
  assert.deepEqual(Object.keys(ad).sort(), [...ADAPTERS].sort());
  for (const [k, v] of Object.entries(ad)) assert.equal(v?.name, k);
});
