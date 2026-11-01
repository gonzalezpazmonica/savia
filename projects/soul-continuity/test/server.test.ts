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

test("límite de peticiones por origen: agotarlo desde una dirección no deja sin servicio a otra", async () => {
  const cert = makeSelfSigned(["127.0.0.1", "::1"], new Date(T0));
  const s = crearServidor({ tls: cert, mundo: { semillas: () => [semilla()] }, reloj: () => T0, peticionesPorVentana: 3 });
  const l = await s.escuchar(["127.0.0.1", "::1"], 0);
  const desde = (host: string, headers: Record<string, string> = { Authorization: "DPoP tok-1", DPoP: "p" }) =>
    new Promise<number>((res, rej) => {
      const q = request({ host, port: l.port, path: "/api/v1/soul/estado", ca: cert.cert, headers }, (r) => { r.resume(); r.on("end", () => res(r.statusCode ?? 0)); });
      q.on("error", rej);
      q.end();
    });
  try {
    const atacante: number[] = [];
    for (let i = 0; i < 5; i++) atacante.push(await desde("127.0.0.1", {})); // sin token
    assert.deepEqual(atacante, [401, 401, 401, 429, 429], "control: el origen que abusa sí se frena");
    assert.equal(await desde("::1"), 200, "otro origen sigue con servicio");
  } finally { await s.cerrar(); }
});

test("un operator_ref «constructor» o «__proto__» no autentica contra el prototipo (401, no 503)", async () => {
  let ref = "constructor";
  const s = crearServidor({ tls: CERT, mundo: { semillas: () => [semilla()] }, reloj: () => T0, autenticar: () => ({ ref, revocado: false }) });
  const l = await s.escuchar(["127.0.0.1"], 0);
  try {
    assert.equal((await get(l.port, "/estado")).status, 401);
    ref = "__proto__";
    assert.equal((await get(l.port, "/estado")).status, 401);
    ref = "op";
    assert.equal((await get(l.port, "/estado")).status, 200, "control: el operador real sí");
  } finally { await s.cerrar(); }
});

test("D4/D5: con el estado perdido, el cursor anterior da 410 (no 400) y los ids nuevos no repiten los ya vistos", async () => {
  const sem = () => ({ ...semilla(), avisos: { ...semilla().avisos, activos: ["vencimiento"] } });
  const disco = new Map<string, any>();
  const persistencia = { cargar: (r: string) => disco.get(r) ?? null, guardar: (r: string, e: any) => { disco.set(r, structuredClone(e)); } };
  const arrancar = async () => {
    const s = crearServidor({ tls: CERT, mundo: { semillas: () => [sem()] }, reloj: () => T0, persistencia, secretoCursor: "fijo" });
    return { s, port: (await s.escuchar(["127.0.0.1"], 0)).port };
  };
  let a = await arrancar();
  let cursor: string;
  let ids: string[];
  try {
    const j = JSON.parse((await get(a.port, "/sondeo")).body);
    cursor = j.cursor;
    ids = j.mensajes.map((m: { id: string }) => m.id);
    assert.ok(ids.length >= 1, "control: el arranque avisa del vencimiento");
  } finally { await a.s.cerrar(); }

  // Reinicio con el estado guardado: el cursor sigue valiendo y no se reemite nada.
  a = await arrancar();
  try {
    const r = await get(a.port, `/sondeo?cursor=${encodeURIComponent(cursor)}`);
    assert.equal(r.status, 200);
    assert.deepEqual(JSON.parse(r.body).mensajes, [], "tras reiniciar no se reemiten los avisos ya dados");
  } finally { await a.s.cerrar(); }

  // Reinicio con el estado perdido (fichero borrado o ilegible).
  disco.clear();
  a = await arrancar();
  try {
    const r = await get(a.port, `/sondeo?cursor=${encodeURIComponent(cursor)}`);
    assert.equal(r.status, 410, r.body);
    assert.equal(JSON.parse(r.body).code, "GONE");
    const nuevos = JSON.parse((await get(a.port, "/sondeo")).body).mensajes.map((m: { id: string }) => m.id);
    assert.ok(nuevos.length >= 1);
    assert.deepEqual(nuevos.filter((id: string) => ids.includes(id)), [], "ningún id nuevo coincide con uno ya entregado");
    // Un cursor manipulado sigue siendo 400.
    assert.equal((await get(a.port, `/sondeo?cursor=${encodeURIComponent(cursor.replace(/.$/, (c) => (c === "0" ? "1" : "0")))}`)).status, 400);
  } finally { await a.s.cerrar(); }
});
