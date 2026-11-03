import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "node:https";
import type { SourceAdapter } from "../src/contract/adapter.ts";
import { makeSelfSigned } from "../src/api/cert.ts";
import { crearServidor } from "../src/api/server.ts";
import { coreWorld } from "../src/api/core-world.ts";
import { emptyConfig, elementId } from "../src/core/config.ts";
import { makeEngine } from "../src/core/engine.ts";
import { operatorDir } from "../src/core/store.ts";

const NOW = "2026-10-31T09:00:00Z";
const T = Date.parse(NOW);
const MIN = 60_000;
const TLS = makeSelfSigned(["127.0.0.1"], new Date(T));
const TITLE = "Asunto de tercero <b>urgente</b>";

const mail: SourceAdapter = {
  name: "m365-mail", routes: ["graph"], purpose: "t",
  async read(ctx) {
    return {
      status: "ok", route: "graph", claims: [{
        key: "m365-mail:awaiting_reply:c1@m1", claim_type: "awaiting_reply", state: "OBSERVED",
        source_refs: [{ adapter: "m365-mail", route: "graph", ref: "c1@m1" }], sensitivity: ctx.sensitivity,
        observed_at: ctx.now, valid_until: "2026-10-31T10:00:00Z", event_at: "2026-10-31T08:00:00Z",
        open: true, awaiting_operator: true, title: TITLE, untrusted_text: true, attrs: { last_from: "x@example.test", sender_auth: "tenant" },
      }],
    };
  },
};

async function setup(level: "titulos" | "recuentos" = "titulos") {
  const dir = mkdtempSync(join(tmpdir(), "soul-cw-"));
  const cfg = emptyConfig("i");
  cfg.detail = { level, max: "completo" };
  cfg.active_profile = "yo";
  cfg.profiles.yo = {
    operator: { ref: "op-yo", identities: { emails: ["yo@example.test"] } },
    sources: [
      { adapter: "m365-mail", purpose: "correo", consent: { granted_at: "2026-10-01T00:00:00Z" } },
      { adapter: "jira", purpose: "tareas", consent: { granted_at: "2026-10-01T00:00:00Z" } },
    ],
  };
  const engine = makeEngine({ "m365-mail": mail });
  const install = { id: "i", operator: cfg.profiles.yo.operator, sources: cfg.profiles.yo.sources };
  await engine.snapshot({ install, now: NOW, stateDir: dir, env: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } } });
  const world = coreWorld({ cfg, engine, stateDir: dir });
  const s = crearServidor({ tls: TLS, mundo: world, reloj: () => T, autenticar: (tok) => (tok === "tok" ? { ref: "op-yo", revocado: false } : null) });
  world.conectar(s);
  const l = await s.escuchar(["127.0.0.1"], 0);
  const call = (method: string, path: string, body?: unknown) => new Promise<{ status: number; json: any; text: string }>((res, rej) => {
    const q = request({ host: "127.0.0.1", port: l.port, path: "/api/v1/soul" + path, method, ca: TLS.cert,
      headers: { Authorization: "DPoP tok", DPoP: "p", ...(body ? { "Content-Type": "application/json" } : {}) } }, (r) => {
      let t = "";
      r.on("data", (d) => { t += d; });
      r.on("end", () => res({ status: r.statusCode ?? 0, json: JSON.parse(t), text: t }));
    });
    q.on("error", rej);
    q.end(body ? JSON.stringify(body) : undefined);
  });
  return { dir, engine, s, call };
}

test("la API sirve Q2 desde la instantánea del núcleo, con id opaco y título inerte", async () => {
  const { s, call } = await setup();
  try {
    const r = await call("GET", "/q/q2");
    assert.equal(r.status, 200);
    assert.equal(r.json.recuentos.total, 1);
    const e = r.json.elementos[0];
    assert.equal(e.id, elementId("op-yo", "m365-mail:awaiting_reply:c1@m1"));
    assert.equal(e.tipo, "hilo_espera");
    assert.deepEqual(e.titulo, { texto: TITLE, inerte: true, origen: "tercero" });
    assert.deepEqual(e.fuente, { adaptador: "m365-mail", ruta: "graph" });
  } finally { await s.cerrar(); }
});

test("con recuentos no sale el asunto por la API (control: con titulos sí sale)", async () => {
  const { s, call } = await setup("recuentos");
  try {
    const all = (await Promise.all(["/q/q1", "/q/q2", "/sondeo?limite=100", "/adaptadores"].map((p) => call("GET", p)))).map((r) => r.text).join("\n");
    assert.ok(!all.includes("Asunto de tercero"));
    assert.ok(!all.includes("c1@m1"));
  } finally { await s.cerrar(); }
});

test("una corrección desde la app queda en el libro del núcleo y no vuelve al releer la fuente", async () => {
  const { dir, engine, s, call } = await setup();
  try {
    const id = (await call("GET", "/q/q2")).json.elementos[0].id;
    assert.equal((await call("POST", `/elementos/${id}/correccion`, { tipo: "resuelto" })).status, 200);
    assert.equal(engine.ledger(dir, "op-yo").length, 1);
    const install = { id: "i", operator: { ref: "op-yo", identities: { emails: [] } }, sources: [{ adapter: "m365-mail", purpose: "c", consent: { granted_at: "2026-10-01T00:00:00Z" } }] };
    const snap = await engine.snapshot({ install, now: NOW, stateDir: dir, env: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } } });
    assert.equal(snap.claims[0].state, "REVOKED");
  } finally { await s.cerrar(); }
});

test("estado de adaptadores del núcleo traducido al contrato", async () => {
  const { s, call } = await setup();
  try {
    const a = (await call("GET", "/adaptadores")).json.adaptadores;
    const by = Object.fromEntries(a.map((x: any) => [x.id, x]));
    assert.equal(by["m365-mail"].estado, "ok");
    assert.equal(by.jira.estado, "detenido");
    assert.equal(by.jira.motivo, "sin_conexion");
    assert.equal(by.jira.ruta_alternativa, "manual");
  } finally { await s.cerrar(); }
});

test("frescura real: ultima_lectura es la de la instantánea; caducada => obsoleto y fuera lo que pasó su TTL", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-cw-"));
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [{ adapter: "m365-mail", purpose: "c", consent: { granted_at: "2026-10-01T00:00:00Z" } }] };
  const engine = makeEngine({ "m365-mail": mail });
  await engine.snapshot({ install: { id: "i", operator: cfg.profiles.yo.operator, sources: cfg.profiles.yo.sources }, now: NOW, stateDir: dir,
    env: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } } });
  let now = T + 10 * 60_000;
  const world = coreWorld({ cfg, engine, stateDir: dir });
  const s = crearServidor({ tls: TLS, mundo: world, reloj: () => now, autenticar: () => ({ ref: "op-yo", revocado: false }) });
  const l = await s.escuchar(["127.0.0.1"], 0);
  const get = (path: string) => new Promise<any>((res, rej) => {
    const q = request({ host: "127.0.0.1", port: l.port, path: "/api/v1/soul" + path, ca: TLS.cert, headers: { Authorization: "DPoP x", DPoP: "p" } }, (r) => {
      let t = ""; r.on("data", (d) => { t += d; }); r.on("end", () => res(JSON.parse(t)));
    });
    q.on("error", rej); q.end();
  });
  try {
    const fresh = await get("/q/q2");
    assert.equal(fresh.ultima_lectura, NOW.replace("Z", ".000Z"));
    assert.equal(fresh.obsoleto, false);
    assert.equal(fresh.recuentos.total, 1);
    const id = fresh.elementos[0].id;
    const pq = await get(`/elementos/${id}/porque`);
    assert.equal(pq.valido_hasta, "2026-10-31T10:00:00.000Z");
    assert.equal(pq.observado_en, "2026-10-31T09:00:00.000Z", "la observación real, no una fabricada al arrancar");
    assert.equal(pq.antiguedad_s, 600);
    now = Date.parse("2026-10-31T10:30:00Z"); // pasado el TTL de la afirmación y de la instantánea
    const stale = await get("/q/q2");
    assert.equal(stale.obsoleto, true);
    assert.equal(stale.recuentos.total, 0, "lo caducado no se sirve como vigente");
  } finally { await s.cerrar(); }
});

test("la API selecciona Q1/Q2/Q4 como el núcleo: ni cerrados ni reuniones fuera de ventana", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-cw-"));
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [{ adapter: "jira", purpose: "t", consent: { granted_at: "2026-10-01T00:00:00Z" } }, { adapter: "m365-calendar", purpose: "c", consent: { granted_at: "2026-10-01T00:00:00Z" } }] };
  const claim = (adapter: string, type: any, ref: string, over: any) => ({ key: `${adapter}:${type}:${ref}`, claim_type: type, state: "OBSERVED", source_refs: [{ adapter, route: "api", ref }],
    sensitivity: "N4", observed_at: NOW, valid_until: "2026-10-31T10:00:00Z", open: true, awaiting_operator: false, attrs: {}, title: ref, untrusted_text: true, ...over });
  const jira: SourceAdapter = { name: "jira", routes: ["api"], purpose: "t", async read() { return { status: "ok", route: "api", claims: [
    claim("jira", "task_assigned", "ABIERTA-1", { awaiting_operator: true }), claim("jira", "task_assigned", "CERRADA-2", { open: false, awaiting_operator: true })] as any }; } };
  const cal: SourceAdapter = { name: "m365-calendar", routes: ["api"], purpose: "t", async read() { return { status: "ok", route: "api", claims: [
    claim("m365-calendar", "meeting", "HOY", { due_at: "2026-10-31T15:00:00Z" }), claim("m365-calendar", "meeting", "LEJANA", { due_at: "2026-11-25T15:00:00Z" })] as any }; } };
  const engine = makeEngine({ jira, "m365-calendar": cal });
  await engine.snapshot({ install: { id: "i", operator: cfg.profiles.yo.operator, sources: cfg.profiles.yo.sources }, now: NOW, stateDir: dir,
    env: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } } });
  const world = coreWorld({ cfg, engine, stateDir: dir });
  const s = crearServidor({ tls: TLS, mundo: world, reloj: () => T, autenticar: () => ({ ref: "op-yo", revocado: false }) });
  const l = await s.escuchar(["127.0.0.1"], 0);
  const get = (path: string) => new Promise<any>((res, rej) => {
    const q = request({ host: "127.0.0.1", port: l.port, path: "/api/v1/soul" + path, ca: TLS.cert, headers: { Authorization: "DPoP x", DPoP: "p" } }, (r) => {
      let t = ""; r.on("data", (d) => { t += d; }); r.on("end", () => res(JSON.parse(t)));
    });
    q.on("error", rej); q.end();
  });
  try {
    const titles = (j: any) => j.elementos.map((e: any) => e.titulo.texto).sort();
    assert.deepEqual(titles(await get("/q/q1")), ["ABIERTA-1", "HOY"]);
    assert.deepEqual(titles(await get("/q/q2")), ["ABIERTA-1"]);
    assert.ok(!titles(await get("/q/q4")).includes("CERRADA-2"));
  } finally { await s.cerrar(); }
});

test("TTL por afirmación evaluado en la petición: valid_until anterior a la caducidad de la instantánea", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-cw-"));
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [{ adapter: "jira", purpose: "t", consent: { granted_at: "2026-10-01T00:00:00Z" } }] };
  const jira: SourceAdapter = { name: "jira", routes: ["api"], purpose: "t", async read(ctx) { return { status: "ok", route: "api", claims: [{
    key: "jira:task_assigned:CORTA-1", claim_type: "task_assigned", state: "OBSERVED", source_refs: [{ adapter: "jira", route: "api", ref: "CORTA-1" }],
    sensitivity: "N4", observed_at: ctx.now, valid_until: "2026-10-31T09:10:00Z", open: true, awaiting_operator: true, attrs: {} }] }; } };
  const engine = makeEngine({ jira });
  await engine.snapshot({ install: { id: "i", operator: cfg.profiles.yo.operator, sources: cfg.profiles.yo.sources }, now: NOW, stateDir: dir,
    env: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } } });
  const world = coreWorld({ cfg, engine, stateDir: dir });
  const op = { ref: "op-yo" } as never;
  assert.equal(world.seleccion?.(op, "q2", Date.parse("2026-10-31T09:05:00Z"))?.size, 1, "control: vigente");
  assert.equal(world.seleccion?.(op, "q2", Date.parse("2026-10-31T09:20:00Z"))?.size, 0, "pasado su valid_until, fuera aunque la instantánea siga vigente");
});

test("una corrección desde la CLI (sin lectura nueva) se ve en la API sin esperar a la siguiente lectura", async () => {
  const { dir, engine, s, call } = await setup();
  try {
    const id = (await call("GET", "/q/q2")).json.elementos[0].id;
    assert.equal((await call("GET", `/elementos/${id}/porque`)).status, 200, "control: el elemento existe");
    const install = { id: "i", operator: { ref: "op-yo", identities: { emails: [] } }, sources: [] };
    await engine.correct({ install, stateDir: dir, now: NOW, key: "m365-mail:awaiting_reply:c1@m1", action: "revoke" });
    assert.equal((await call("GET", `/elementos/${id}/porque`)).status, 404, "revocado: fuera de las listas de la API");
    await engine.correct({ install, stateDir: dir, now: NOW, key: "m365-mail:awaiting_reply:c1@m1", action: "restore" });
    assert.equal((await call("GET", `/elementos/${id}/porque`)).status, 200, "restaurado: vuelve");
  } finally { await s.cerrar(); }
});

test("soul revoke (purga sin lectura nueva) saca de la API lo del adaptador revocado", async () => {
  const { dir, engine, s, call } = await setup();
  try {
    const id = (await call("GET", "/q/q2")).json.elementos[0].id;
    assert.equal((await call("GET", `/elementos/${id}/porque`)).status, 200, "control: el elemento existe");
    assert.ok(engine.purgeAdapter(dir, "op-yo", "m365-mail") > 0);
    assert.equal((await call("GET", `/elementos/${id}/porque`)).status, 404, "purgado: fuera de la API sin esperar a la relectura");
    const by = Object.fromEntries((await call("GET", "/adaptadores")).json.adaptadores.map((x: any) => [x.id, x]));
    assert.equal(by["m365-mail"].estado, "revocado");
  } finally { await s.cerrar(); }
});

test("Q3 de la API es la diferencia del núcleo (como `soul q3 --since`), no la fecha del evento", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-cw-"));
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [{ adapter: "jira", purpose: "t", consent: { granted_at: "2026-10-01T00:00:00Z" } }] };
  const VIEJO = "2026-10-24T08:00:00Z"; // event_at de hace una semana
  let lectura = 1;
  const tarea = (ref: string, over: any, now: string) => ({ key: `jira:task_assigned:${ref}`, claim_type: "task_assigned", state: "OBSERVED",
    source_refs: [{ adapter: "jira", route: "api", ref }], sensitivity: "N4", observed_at: now, valid_until: "2026-10-31T12:00:00Z",
    event_at: VIEJO, open: true, awaiting_operator: true, attrs: {}, title: ref, untrusted_text: true, ...over });
  const jira: SourceAdapter = { name: "jira", routes: ["api"], purpose: "t", async read(ctx) {
    const c = lectura === 1 ? [tarea("FIJA-1", {}, ctx.now), tarea("CAMBIA-2", { due_at: "2026-11-02T10:00:00Z" }, ctx.now)]
      : [tarea("FIJA-1", {}, ctx.now), tarea("CAMBIA-2", { due_at: "2026-11-05T10:00:00Z" }, ctx.now), tarea("NUEVA-ANTIGUA-3", {}, ctx.now)];
    return { status: "ok", route: "api", claims: c as any };
  } };
  const engine = makeEngine({ jira });
  const install = { id: "i", operator: cfg.profiles.yo.operator, sources: cfg.profiles.yo.sources };
  const env = { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } };
  await engine.snapshot({ install, now: "2026-10-31T08:00:00Z", stateDir: dir, env });
  lectura = 2;
  await engine.snapshot({ install, now: NOW, stateDir: dir, env });
  const world = coreWorld({ cfg, engine, stateDir: dir });
  const s = crearServidor({ tls: TLS, mundo: world, reloj: () => T, autenticar: () => ({ ref: "op-yo", revocado: false }) });
  const l = await s.escuchar(["127.0.0.1"], 0);
  const get = (path: string) => new Promise<{ status: number; json: any }>((res, rej) => {
    const q = request({ host: "127.0.0.1", port: l.port, path: "/api/v1/soul" + path, ca: TLS.cert, headers: { Authorization: "DPoP x", DPoP: "p" } }, (r) => {
      let t = ""; r.on("data", (d) => { t += d; }); r.on("end", () => res({ status: r.statusCode ?? 0, json: JSON.parse(t) }));
    });
    q.on("error", rej); q.end();
  });
  try {
    const titles = (j: any) => j.elementos.map((e: any) => e.titulo.texto).sort();
    // Ni FIJA-1 (sin cambios) ni la ausencia de NUEVA-ANTIGUA-3/CAMBIA-2 por tener event_at viejo.
    assert.deepEqual(titles((await get("/q/q3?desde=2026-10-31T08:30:00Z")).json), ["CAMBIA-2", "NUEVA-ANTIGUA-3"]);
    // D6: sin lectura anterior a desde, la base es la primera lectura guardada (08:00), no un 400.
    const sinBase = await get("/q/q3?desde=2026-10-31T07:00:00Z");
    assert.equal(sinBase.status, 200);
    assert.deepEqual(titles(sinBase.json), ["CAMBIA-2", "NUEVA-ANTIGUA-3"]);
    // Mismo resultado que el núcleo con la CLI.
    const prev = engine.snapshotAt(dir, "op-yo", "2026-10-31T08:30:00Z");
    const cli = engine.answer(engine.cachedSnapshot(dir, "op-yo", NOW) as any, { q: "Q3", detail: "titulos", previous: prev as any }, { install, now: NOW });
    assert.deepEqual(cli.items.map((i) => i.key.split(":")[2]).sort(), ["CAMBIA-2", "NUEVA-ANTIGUA-3"]);
  } finally { await s.cerrar(); }
});

test("si el libro no se puede escribir, la API responde 503 y no confirma la corrección", async () => {
  const { dir, engine, s, call } = await setup();
  try {
    const id = (await call("GET", "/q/q2")).json.elementos[0].id;
    writeFileSync(join(operatorDir(dir, "op-yo"), "ledger.jsonl"), "", { mode: 0o400 }); // libro de solo lectura: append falla
    const r = await call("POST", `/elementos/${id}/correccion`, { tipo: "resuelto" });
    assert.equal(r.status, 503);
    assert.equal(r.json.code, "UNAVAILABLE");
    assert.equal(engine.ledger(dir, "op-yo").length, 0);
    assert.equal((await call("GET", `/elementos/${id}/porque`)).status, 200, "no se da por resuelto lo que no se guardó");
    const o = await call("POST", "/ordenes", { orden: `resuelto ${id}` });
    assert.equal(o.status, 503, "también por la orden de texto");
  } finally { await s.cerrar(); }
});

test("«es mío» sobrevive a reiniciar el servicio: sale del libro, no de memoria", async () => {
  const { dir, engine, s, call } = await setup();
  let id: string;
  try {
    id = (await call("GET", "/q/q2")).json.elementos[0].id;
    assert.equal((await call("POST", `/elementos/${id}/correccion`, { tipo: "es_mio" })).status, 200);
  } finally { await s.cerrar(); }
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [] };
  const world = coreWorld({ cfg, engine, stateDir: dir }); // servicio nuevo, mismo directorio de datos
  const s2 = crearServidor({ tls: TLS, mundo: world, reloj: () => T, autenticar: () => ({ ref: "op-yo", revocado: false }) });
  const l = await s2.escuchar(["127.0.0.1"], 0);
  try {
    const r = await new Promise<any>((res, rej) => {
      const q = request({ host: "127.0.0.1", port: l.port, path: "/api/v1/soul/q/q2", ca: TLS.cert, headers: { Authorization: "DPoP x", DPoP: "p" } }, (x) => {
        let t = ""; x.on("data", (d) => { t += d; }); x.on("end", () => res(JSON.parse(t)));
      });
      q.on("error", rej); q.end();
    });
    const e = r.elementos.find((x: any) => x.id === id);
    assert.equal(e.correccion, "es_mio");
  } finally { await s2.cerrar(); }
});

test("D8: proyectos, personas y reglas de alerta salen de los adaptadores y del perfil; la alerta solo con remitente autenticado", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-cw-"));
  const cfg = emptyConfig("i");
  cfg.detail = { level: "completo", max: "completo" };
  cfg.active_profile = "yo";
  cfg.profiles.yo = {
    operator: { ref: "op-yo", identities: { emails: ["yo@example.test"] } },
    sources: [
      { adapter: "m365-mail", purpose: "correo", consent: { granted_at: "2026-10-01T00:00:00Z" } },
      { adapter: "jira", purpose: "tareas", consent: { granted_at: "2026-10-01T00:00:00Z" } },
    ],
    alert_rules: [{ id: "jefa", sender: "Jefa@Example.test" }],
  };
  const hilo = (ref: string, from: string, auth: string, now: string) => ({
    key: `m365-mail:awaiting_reply:${ref}`, claim_type: "awaiting_reply", state: "OBSERVED", source_refs: [{ adapter: "m365-mail", route: "graph", ref }],
    sensitivity: "N4", observed_at: now, valid_until: "2026-10-31T12:00:00Z", event_at: now, open: true, awaiting_operator: true,
    title: `hilo ${ref}`, untrusted_text: true, attrs: { last_from: from, sender_auth: auth },
  });
  let lectura = 1;
  const mail: SourceAdapter = { name: "m365-mail", routes: ["graph"], purpose: "t", async read(ctx) {
    const c: any[] = [hilo("c1@m1", "jefa@example.test", "tenant", ctx.now)];
    if (lectura === 2) c.push(hilo("c2@m2", "jefa@example.test", "tenant", ctx.now), hilo("c3@m3", "jefa@example.test", "unauthenticated", ctx.now));
    return { status: "ok", route: "graph", claims: c };
  } };
  const jira: SourceAdapter = { name: "jira", routes: ["api"], purpose: "t", async read(ctx) {
    return { status: "ok", route: "api", claims: [{ key: "jira:task_assigned:ALFA-12", claim_type: "task_assigned", state: "OBSERVED", source_refs: [{ adapter: "jira", route: "api", ref: "ALFA-12" }],
      sensitivity: "N4", observed_at: ctx.now, valid_until: "2026-10-31T12:00:00Z", event_at: ctx.now, open: true, awaiting_operator: true, title: "Tarea", untrusted_text: true, attrs: {} }] as any };
  } };
  const engine = makeEngine({ "m365-mail": mail, jira });
  const install = { id: "i", operator: cfg.profiles.yo.operator, sources: cfg.profiles.yo.sources };
  const env = { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } };
  await engine.snapshot({ install, now: NOW, stateDir: dir, env });
  const world = coreWorld({ cfg, engine, stateDir: dir });
  let reloj = T;
  const s = crearServidor({ tls: TLS, mundo: world, reloj: () => reloj, autenticar: () => ({ ref: "op-yo", revocado: false }) });
  world.conectar(s);
  const l = await s.escuchar(["127.0.0.1"], 0);
  const get = (path: string) => new Promise<any>((res, rej) => {
    const q = request({ host: "127.0.0.1", port: l.port, path: "/api/v1/soul" + path, ca: TLS.cert, headers: { Authorization: "DPoP x", DPoP: "p" } }, (r) => {
      let t = ""; r.on("data", (d) => { t += d; }); r.on("end", () => res(JSON.parse(t)));
    });
    q.on("error", rej); q.end();
  });
  try {
    const f = await get("/filtros");
    assert.deepEqual(f.proyectos.map((p: any) => p.nombre.texto), ["ALFA"]);
    assert.deepEqual(f.personas.map((p: any) => p.nombre.texto), ["jefa@example.test"]);
    const els = (await get("/q/q1")).elementos;
    const tarea = els.find((e: any) => e.tipo === "tarea");
    assert.equal(tarea.proyecto.texto, "ALFA");
    const h = els.find((e: any) => e.tipo === "hilo_espera");
    assert.deepEqual(h.personas.map((p: any) => p.texto), ["jefa@example.test"]);
    // El filtro por proyecto usa los ids de /filtros.
    assert.deepEqual((await get(`/q/q1?proyecto=${f.proyectos[0].id}`)).elementos.map((e: any) => e.tipo), ["tarea"]);
    const av = await get("/avisos");
    assert.equal(av.alertas.length, 1);
    assert.equal(av.alertas[0].tipo, "persona");
    assert.equal(av.alertas[0].objetivo, f.personas[0].id, "la regla del perfil apunta a la persona (correo normalizado)");

    const antes = (await get("/sondeo")).cursor;
    lectura = 2;
    reloj += 5 * MIN;
    await engine.snapshot({ install, now: new Date(reloj).toISOString(), stateDir: dir, env });
    const sondeo = await get(`/sondeo?cursor=${encodeURIComponent(antes)}`);
    const alertas = sondeo.mensajes.filter((m: any) => m.tipo === "alerta");
    const id2 = elementId("op-yo", "m365-mail:awaiting_reply:c2@m2");
    const id3 = elementId("op-yo", "m365-mail:awaiting_reply:c3@m3");
    assert.deepEqual(alertas.map((m: any) => m.elemento_ids), [[id2]], "solo el remitente autenticado dispara la alerta");
    assert.ok(sondeo.mensajes.some((m: any) => m.tipo === "aviso" && m.elemento_ids.includes(id3)), "el no autenticado llega como aviso");
  } finally { await s.cerrar(); }
});
