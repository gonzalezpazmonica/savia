// Pruebas propias del servidor del producto. Los 27 tests de contrato de Labs, adaptados,
// están en test/api/contrato.test.mjs y corren contra este mismo servidor (con el mundo simulado).
import { test } from "node:test";
import assert from "node:assert/strict";
import { request } from "node:https";
import { makeSelfSigned } from "../src/api/cert.ts";
import { crearServidor, type SemillaOperador } from "../src/api/server.ts";

const T0 = Date.parse("2026-10-31T08:00:00Z");
const CERT = makeSelfSigned(["127.0.0.1"], new Date(T0));

function semilla(): SemillaOperador {
  return {
    ref: "op", tokens: ["tok-1"], nivel: "titulos", nivelMax: "completo", proyectos: [], personas: [], adaptadores: [],
    elementos: [{ id: "e-1", tipo: "tarea", titulo: "Algo", proyecto: null, personas: [], detalle: null, adaptador: "jira", ruta: "api", dep: true, fecha: null, nace: T0 - 60_000, estado: "OBSERVED", sens: "N4", refs: [] }],
    avisos: { activos: [], resumenInicio: null, resumenCierre: null, max: 5, ventanaMin: 60, tope: 3 }, alertas: [],
  };
}

function get(port: number, path: string, headers: Record<string, string> = { Authorization: "DPoP tok-1", DPoP: "p" }) {
  return new Promise<{ status: number; body: string }>((res, rej) => {
    const q = request({ host: "127.0.0.1", port, path: "/api/v1/soul" + path, ca: CERT.cert, headers }, (r) => {
      let b = "";
      r.on("data", (d) => { b += d; });
      r.on("end", () => res({ status: r.statusCode ?? 0, body: b }));
    });
    q.on("error", rej);
    q.end();
  });
}

test("el servidor solo sirve por TLS y en las direcciones dadas", async () => {
  const s = crearServidor({ tls: CERT, mundo: { semillas: () => [semilla()] }, reloj: () => T0 });
  const l = await s.escuchar(["127.0.0.1"], 0);
  try {
    assert.equal((await get(l.port, "/estado")).status, 200);
    assert.equal((await get(l.port, "/estado", {})).status, 401);
  } finally { await s.cerrar(); }
});

test("sin direcciones configuradas no arranca (fail-closed)", async () => {
  const s = crearServidor({ tls: CERT, mundo: { semillas: () => [semilla()] }, reloj: () => T0 });
  await assert.rejects(s.escuchar([], 0), /ninguna dirección/);
  await assert.rejects(s.escuchar(["0.0.0.0"], 0), /todas las interfaces/);
});

test("con STOP la API responde 503 y no sirve datos", async () => {
  let parado = false;
  const s = crearServidor({ tls: CERT, mundo: { semillas: () => [semilla()] }, reloj: () => T0, detenido: () => parado });
  const l = await s.escuchar(["127.0.0.1"], 0);
  try {
    assert.equal((await get(l.port, "/q/q1")).status, 200);
    parado = true;
    const r = await get(l.port, "/q/q1");
    assert.equal(r.status, 503);
    assert.ok(!r.body.includes("Algo"));
  } finally { await s.cerrar(); }
});

test("sin TLS no se crea el servidor", () => {
  assert.throws(() => crearServidor({ tls: { cert: "", key: "" }, mundo: { semillas: () => [] } }), /TLS/);
});
