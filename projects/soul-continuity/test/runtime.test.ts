import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { fetchTransport, productionAdapters } from "../src/core/runtime.ts";

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

test("productionAdapters: solo nombres del contrato", () => {
  const ad = productionAdapters();
  for (const [k, v] of Object.entries(ad)) assert.equal(v?.name, k);
});
