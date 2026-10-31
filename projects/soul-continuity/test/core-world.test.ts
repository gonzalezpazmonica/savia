import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "node:https";
import type { SourceAdapter } from "../src/contract/adapter.ts";
import { makeSelfSigned } from "../src/api/cert.ts";
import { crearServidor } from "../src/api/server.ts";
import { coreWorld } from "../src/api/core-world.ts";
import { emptyConfig, elementId } from "../src/core/config.ts";
import { makeEngine } from "../src/core/engine.ts";

const NOW = "2026-10-31T09:00:00Z";
const T = Date.parse(NOW);
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
