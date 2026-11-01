import { test } from "node:test";
import assert from "node:assert/strict";
import { DpopError, DPOP_SKEW_MS, makeDpopVerifier, thumbprint } from "../src/api/dpop.ts";

import { HTU, NOW, TOKEN, newKey, proof } from "./dpop-helper.ts";


const req = (p: string, over: Partial<Parameters<ReturnType<typeof makeDpopVerifier>>[0]> = {}) =>
  ({ proof: p, method: "GET", path: "/api/v1/soul/q/q1", host: "100.64.0.7:8787", token: TOKEN, now: NOW, ...over });

const code = (f: () => unknown) => { try { f(); return "ok"; } catch (e) { assert.ok(e instanceof DpopError, String(e)); return e.code; } };

test("P1-1: una prueba válida de la app verifica y devuelve la huella de su clave", () => {
  const k = newKey();
  const v = makeDpopVerifier();
  const r = v(req(proof(k)));
  assert.equal(r.jkt, thumbprint(k.publicKey.export({ format: "jwk" }) as { x: string; y: string }));
  assert.match(r.jkt, /^[A-Za-z0-9_-]{43}$/);
});

test("P1-1: el htu va sin consulta (como la app); una prueba cuyo htu lleva la consulta se rechaza", () => {
  const k = newKey();
  const v = makeDpopVerifier();
  // Quien llama pasa la ruta sin consulta (serve la quita): la prueba de la app, sin consulta, casa.
  assert.equal(code(() => v(req(proof(k), { path: "/api/v1/soul/q/q1" }))), "ok");
  assert.equal(code(() => v(req(proof(k, { htu: `${HTU}?limite=5` }), { path: "/api/v1/soul/q/q1" }))), "htu");
});

test("P1-1: prueba firmada con otra clave que la ligada al dispositivo => clave", () => {
  const v = makeDpopVerifier();
  const ligada = v(req(proof(newKey()))).jkt;
  assert.equal(code(() => v(req(proof(newKey()), { expectedJkt: ligada }))), "clave");
});

test("P1-1: jti repetido => reenvio; jti nuevo con la misma clave sí pasa", () => {
  const k = newKey();
  const v = makeDpopVerifier();
  const p = proof(k, { jti: "jti-fijo-123456" });
  assert.equal(code(() => v(req(p))), "ok");
  assert.equal(code(() => v(req(p))), "reenvio");
  assert.equal(code(() => v(req(proof(k)))), "ok");
});

test("P1-1: prueba caducada o adelantada más allá de la tolerancia => tiempo (borde incluido)", () => {
  const k = newKey();
  const v = makeDpopVerifier();
  assert.equal(code(() => v(req(proof(k, { iat: NOW - DPOP_SKEW_MS - 1000 })))), "tiempo");
  assert.equal(code(() => v(req(proof(k, { iat: NOW + DPOP_SKEW_MS + 1000 })))), "tiempo");
  assert.equal(code(() => v(req(proof(k, { iat: NOW - DPOP_SKEW_MS })))), "ok");
});

test("P1-1: método, URL, host o token que no casan => rechazo", () => {
  const k = newKey();
  const v = makeDpopVerifier();
  assert.equal(code(() => v(req(proof(k, { htm: "POST" })))), "htm");
  assert.equal(code(() => v(req(proof(k, { htu: "https://100.64.0.7:8787/api/v1/soul/q/q2" })))), "htu");
  assert.equal(code(() => v(req(proof(k), { host: "10.0.0.9:8787" }))), "htu");
  assert.equal(code(() => v(req(proof(k, { htu: "http://100.64.0.7:8787/api/v1/soul/q/q1" })))), "htu");
  assert.equal(code(() => v(req(proof(k, { token: "otro-token" })))), "ath");
  assert.equal(code(() => v(req(proof(k, { token: null })))), "ath");
});

test("P1-1: firma manipulada, cabecera ajena o clave privada en el jwk => rechazo", () => {
  const k = newKey();
  const v = makeDpopVerifier();
  const p = proof(k);
  const roto = p.slice(0, -4) + (p.endsWith("AAAA") ? "BBBB" : "AAAA");
  assert.equal(code(() => v(req(roto))), "firma");
  assert.equal(code(() => v(req(proof(k, { typ: "JWT" })))), "cabecera");
  assert.equal(code(() => v(req(proof(k, { alg: "none" })))), "cabecera");
  assert.equal(code(() => v(req(proof(k, { extraJwk: { d: "secreto" } })))), "cabecera");
  assert.equal(code(() => v(req("no.es.unjwt"))), "forma");
  assert.equal(code(() => v(req(""))), "forma");
});

test("la ventana anti-reenvío está acotada en memoria", () => {
  const k = newKey();
  const v = makeDpopVerifier({ maxJti: 4 });
  for (let i = 0; i < 4; i++) v(req(proof(k)));
  // Llena: una prueba nueva dentro de la ventana falla cerrado en vez de olvidar un jti vivo.
  assert.equal(code(() => v(req(proof(k)))), "reenvio");
  assert.equal(code(() => v(req(proof(k, { iat: NOW + 3 * DPOP_SKEW_MS }), { now: NOW + 3 * DPOP_SKEW_MS }))), "ok", "los vencidos se purgan");
});
