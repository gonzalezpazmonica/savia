import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "node:https";
import { createServer } from "node:net";
import { emptyConfig, saveConfig } from "../src/core/config.ts";
import { serveFromCli } from "../src/api/serve.ts";
import { pairDevice, revokeDevice } from "../src/api/devices.ts";
import { stop } from "../src/core/failsafe.ts";
import { newKey, proof } from "./dpop-helper.ts";
import { listDevices } from "../src/api/devices.ts";
import { ATTENTION_STATE } from "../src/api/serve.ts";
import { operatorDir } from "../src/core/store.ts";
import { LIMITES, crearServidor } from "../src/api/server.ts";
import { type CliDeps, runCli } from "../src/cli/cli.ts";

function deps(dir: string, out: string[], err: string[]): CliDeps {
  return {
    dataDir: dir, env: {}, now: () => new Date().toISOString(), out: (s) => out.push(s), err: (s) => err.push(s), adapters: {},
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } },
    credentials: { revoke: async () => ({ tokens_removed: 0, cache_removed: false }), forgetAll: async () => [] }, platform: "linux", home: dir,
    run: async () => ({ code: 0, stdout: "", stderr: "" }), node: "n", entry: "e",
  };
}

async function freePort(): Promise<number> {
  const s = createServer();
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const p = (s.address() as { port: number }).port;
  await new Promise<void>((r) => s.close(() => r()));
  return p;
}

function setup(listen: string[], port = 8787) {
  const dir = mkdtempSync(join(tmpdir(), "soul-sv-"));
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [] };
  cfg.api = { listen, port };
  saveConfig(dir, cfg);
  return dir;
}

const KEY = newKey();
/** Petición como la de la app: `Authorization: DPoP <token>` y una prueba nueva firmada con la clave del móvil. */
const call = (port: number, ca: string, token: string, o: { key?: ReturnType<typeof newKey>; path?: string; method?: string; body?: unknown; proofOverride?: string } = {}) =>
  new Promise<{ status: number; json: any }>((res, rej) => {
    const path = o.path ?? "/api/v1/soul/estado";
    const method = o.method ?? "GET";
    const prueba = o.proofOverride ?? proof(o.key ?? KEY, { htm: method, htu: `https://127.0.0.1:${port}${path.split("?")[0]}`, iat: Date.now(), token });
    const q = request({ host: "127.0.0.1", port, path, method, ca, headers: { Authorization: `DPoP ${token}`, DPoP: prueba, ...(o.body ? { "Content-Type": "application/json" } : {}) } }, (r) => {
      let b = "";
      r.on("data", (c) => (b += c));
      r.on("end", () => { let j: any = null; try { j = JSON.parse(b); } catch { j = null; } res({ status: r.statusCode ?? 0, json: j }); });
    });
    q.on("error", rej);
    q.end(o.body ? JSON.stringify(o.body) : undefined);
  });
const get = async (port: number, ca: string, token: string, key?: ReturnType<typeof newKey>) => (await call(port, ca, token, { key })).status;

async function start(dir: string, out: string[], d = deps(dir, out, [])) {
  const ac = new AbortController();
  const done = serveFromCli(d, { signal: ac.signal, refreshMs: 50 });
  for (let i = 0; i < 80 && !out.some((l) => l.includes("Escuchando")); i++) await new Promise((r) => setTimeout(r, 25));
  const port = Number(/:(\d+)/.exec(out.find((l) => l.includes("Escuchando")) ?? "")?.[1]);
  const ca = readFileSync(join(dir, "tls", "cert.pem"), "utf8");
  return { port, ca, stop: async () => { ac.abort(); return done; } };
}

test("serve sin direcciones configuradas no arranca: error claro y código 1", async () => {
  const dir = setup([]);
  const out: string[] = [];
  const err: string[] = [];
  assert.equal(await serveFromCli(deps(dir, out, err)), 1);
  assert.match(err.join("\n"), /ninguna dirección de escucha/);
});

test("serve: TLS propio, dispositivo emparejado entra, revocado recibe 401, STOP da 503", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const out: string[] = [];
  const err: string[] = [];
  const p = pairDevice(dir, "op-yo", "movil", new Date().toISOString());
  const ac = new AbortController();
  const done = serveFromCli(deps(dir, out, err), { signal: ac.signal, onListening: () => undefined });
  for (let i = 0; i < 50 && !out.some((l) => l.includes("Escuchando")); i++) await new Promise((r) => setTimeout(r, 50));
  const port = Number(/:(\d+)/.exec(out.find((l) => l.includes("Escuchando")) ?? "")?.[1]);
  const ca = readFileSync(join(dir, "tls", "cert.pem"), "utf8");
  try {
    assert.equal(await get(port, ca, p.token), 200);
    assert.equal(await get(port, ca, "otro-token"), 401);
    revokeDevice(dir, p.id, new Date().toISOString());
    assert.equal(await get(port, ca, p.token), 401);
    const q = pairDevice(dir, "op-yo", "tableta", new Date().toISOString());
    stop(dir, "prueba", new Date().toISOString());
    assert.equal(await get(port, ca, q.token), 503);
  } finally {
    ac.abort();
    assert.equal(await done, 0);
  }
  assert.ok(out.some((l) => /sha256\//.test(l)), "muestra la huella para fijar el certificado");
});

test("serve recarga la configuración en cada lectura: un revoke con el servicio en marcha deja de leer la fuente", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const cfg = JSON.parse(readFileSync(join(dir, "config.json"), "utf8"));
  cfg.profiles.yo.sources = [{ adapter: "github", purpose: "p", consent: { granted_at: "2026-10-01T00:00:00Z" } }];
  writeFileSync(join(dir, "config.json"), JSON.stringify(cfg));
  let calls = 0;
  const out: string[] = [];
  const d = deps(dir, out, []);
  d.adapters = { github: { name: "github", routes: ["api"], purpose: "t", async read() { calls++; return { status: "ok", route: "api", claims: [] }; } } };
  const ac = new AbortController();
  const done = serveFromCli(d, { signal: ac.signal, refreshMs: 50 });
  try {
    for (let i = 0; i < 40 && calls < 2; i++) await new Promise((r) => setTimeout(r, 25));
    assert.ok(calls >= 2, "control: el servicio relee la fuente");
    cfg.profiles.yo.sources[0].consent.revoked_at = "2026-10-02T00:00:00Z";
    writeFileSync(join(dir, "config.json"), JSON.stringify(cfg));
    await new Promise((r) => setTimeout(r, 120));
    const after = calls;
    await new Promise((r) => setTimeout(r, 250));
    assert.equal(calls, after, "tras revocar, no se vuelve a leer");
  } finally {
    ac.abort();
    await done;
  }
});

test("serve no solapa lecturas: una lectura lenta no acumula otras en paralelo", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const cfg = JSON.parse(readFileSync(join(dir, "config.json"), "utf8"));
  cfg.profiles.yo.sources = [{ adapter: "github", purpose: "p", consent: { granted_at: "2026-10-01T00:00:00Z" } }];
  writeFileSync(join(dir, "config.json"), JSON.stringify(cfg));
  let enCurso = 0, maximo = 0, calls = 0;
  const d = deps(dir, [], []);
  d.adapters = { github: { name: "github", routes: ["api"], purpose: "t", async read() {
    calls++; enCurso++; maximo = Math.max(maximo, enCurso);
    await new Promise((r) => setTimeout(r, 150));
    enCurso--;
    return { status: "ok", route: "api", claims: [] };
  } } };
  const ac = new AbortController();
  const done = serveFromCli(d, { signal: ac.signal, refreshMs: 10 });
  try {
    for (let i = 0; i < 60 && calls < 3; i++) await new Promise((r) => setTimeout(r, 25));
    assert.ok(calls >= 3, `control: el servicio sigue releyendo (${calls})`);
    assert.equal(maximo, 1, "nunca dos lecturas a la vez");
  } finally {
    ac.abort();
    await done;
  }
});

test("P1-1: la primera clave queda ligada; un token copiado con otra clave, sin prueba o con prueba repetida => 401", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const out: string[] = [];
  const p = pairDevice(dir, "op-yo", "movil", new Date().toISOString());
  const s = await start(dir, out);
  try {
    assert.equal(await get(s.port, s.ca, p.token), 200, "control: la app con su clave entra");
    assert.ok(listDevices(dir)[0].jkt, "huella de la clave ligada al dispositivo");
    assert.equal(await get(s.port, s.ca, p.token, newKey()), 401, "mismo token desde otra clave");
    assert.equal((await call(s.port, s.ca, p.token, { proofOverride: "p" })).status, 401, "sin prueba válida");
    const una = proof(KEY, { htu: `https://127.0.0.1:${s.port}/api/v1/soul/estado`, iat: Date.now(), token: p.token });
    assert.equal((await call(s.port, s.ca, p.token, { proofOverride: una })).status, 200);
    assert.equal((await call(s.port, s.ca, p.token, { proofOverride: una })).status, 401, "jti repetido");
    const vieja = proof(KEY, { htu: `https://127.0.0.1:${s.port}/api/v1/soul/estado`, iat: Date.now() - 5 * 60_000, token: p.token });
    assert.equal((await call(s.port, s.ca, p.token, { proofOverride: vieja })).status, 401, "prueba caducada");
  } finally { assert.equal(await s.stop(), 0); }
});

test("P2-8: un token caducado no entra aunque la prueba sea buena", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const out: string[] = [];
  const p = pairDevice(dir, "op-yo", "movil", new Date(Date.now() - 2 * 86_400_000).toISOString(), 1);
  const s = await start(dir, out);
  try { assert.equal(await get(s.port, s.ca, p.token), 401); } finally { await s.stop(); }
});

test("atención persistente: el modo declarado por la app sobrevive a reiniciar serve y el cursor sigue valiendo", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const p = pairDevice(dir, "op-yo", "movil", new Date().toISOString());
  const hasta = new Date(Date.now() + 2 * 3_600_000).toISOString();
  let s = await start(dir, []);
  let cursor = "";
  try {
    const r = await call(s.port, s.ca, p.token, { method: "PUT", path: "/api/v1/soul/atencion", body: { modo: "FOCO", hasta } });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    const sondeo = await call(s.port, s.ca, p.token, { path: "/api/v1/soul/sondeo" });
    assert.equal(sondeo.status, 200);
    cursor = sondeo.json.cursor;
  } finally { await s.stop(); }
  assert.ok(readFileSync(join(operatorDir(dir, "op-yo"), ATTENTION_STATE), "utf8").includes("FOCO"));
  s = await start(dir, []);
  try {
    const a = await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" });
    assert.equal(a.json.modo, "FOCO", "el modo no se pierde al reiniciar");
    const sondeo = await call(s.port, s.ca, p.token, { path: `/api/v1/soul/sondeo?cursor=${encodeURIComponent(cursor)}` });
    assert.equal(sondeo.status, 200, "el cursor anterior al reinicio sigue valiendo");
  } finally { await s.stop(); }
});

test("atención compartida: soul mode (attention.json) se aplica en serve sin reiniciar", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const p = pairDevice(dir, "op-yo", "movil", new Date().toISOString());
  const s = await start(dir, []);
  try {
    assert.equal((await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" })).json.modo, "DISPONIBLE", "control");
    writeFileSync(join(operatorDir(dir, "op-yo"), "attention.json"), JSON.stringify({ modo: "DESCANSO", hasta: new Date(Date.now() + 3_600_000).toISOString(), at: new Date().toISOString() }));
    let modo = "";
    for (let i = 0; i < 40 && modo !== "DESCANSO"; i++) {
      await new Promise((r) => setTimeout(r, 50));
      modo = (await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" })).json.modo;
    }
    assert.equal(modo, "DESCANSO");
  } finally { await s.stop(); }
});

test("P2-9: límites de conexión y tiempos de espera propios en el servidor TLS", async () => {
  const tlsDir = setup(["127.0.0.1"], await freePort());
  const out: string[] = [];
  const s = await start(tlsDir, out);
  await s.stop();
  const { ensureInstallCert } = await import("../src/api/cert.ts");
  const tls = ensureInstallCert(tlsDir, ["127.0.0.1"]);
  const srv = crearServidor({ tls, mundo: { semillas: () => [] } });
  const l = await srv.escuchar(["127.0.0.1"], 0);
  try {
    const h = (l as unknown as { servers: import("node:https").Server[] }).servers[0];
    assert.equal(h.maxConnections, LIMITES.maxConnections);
    assert.equal(h.headersTimeout, 10_000);
    assert.equal(h.requestTimeout, 15_000);
    assert.equal(h.keepAliveTimeout, 5_000);
  } finally { await srv.cerrar(); }
});

test("contrato soul mode → serve: la orden real de la CLI escribe lo que serve aplica (attention.json con at)", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const p = pairDevice(dir, "op-yo", "movil", new Date().toISOString());
  const s = await start(dir, []);
  try {
    assert.equal((await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" })).json.modo, "DISPONIBLE", "control");
    const d = deps(dir, [], []);
    assert.equal(await runCli(["mode", "FOCO", "--for", "2h"], d), 0);
    let modo = "";
    for (let i = 0; i < 40 && modo !== "FOCO"; i++) {
      await new Promise((r) => setTimeout(r, 50));
      modo = (await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" })).json.modo;
    }
    assert.equal(modo, "FOCO", "lo que escribe `soul mode` llega a la app");
  } finally { await s.stop(); }
});

test("attention.json sin «at» no se aplica y se avisa", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  writeFileSync(join(operatorDir(dir, "op-yo"), "attention.json"), JSON.stringify({ modo: "FOCO", hasta: new Date(Date.now() + 3_600_000).toISOString() }));
  const err: string[] = [];
  const out: string[] = [];
  const s = await start(dir, out, deps(dir, out, err));
  const avisos = () => err.filter((l) => /sin modo o sin «at»/.test(l)).length;
  let antes = -1;
  try {
    await new Promise((r) => setTimeout(r, 400)); // varios tics de 50 ms
    antes = avisos();
    // Otro contenido igual de inválido sí se vuelve a avisar.
    writeFileSync(join(operatorDir(dir, "op-yo"), "attention.json"), JSON.stringify({ modo: "DESCANSO" }));
    for (let i = 0; i < 40 && avisos() < 2; i++) await new Promise((r) => setTimeout(r, 25));
    await new Promise((r) => setTimeout(r, 200));
  } finally {
    await s.stop();
  }
  assert.equal(antes, 1, "se avisa una vez, no en cada tic");
  assert.equal(avisos(), 2, err.join("\n"));
});

test("P1-A: tras reiniciar serve, una declaración de soul mode ya aplicada no pisa el modo que fijó después la app", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const p = pairDevice(dir, "op-yo", "movil", new Date().toISOString());
  writeFileSync(join(operatorDir(dir, "op-yo"), "attention.json"), JSON.stringify({ modo: "FOCO", hasta: new Date(Date.now() + 3_600_000).toISOString(), at: new Date().toISOString() }));
  let s = await start(dir, []);
  try {
    assert.equal((await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" })).json.modo, "FOCO", "control: se aplica al arrancar");
    assert.equal((await call(s.port, s.ca, p.token, { method: "PUT", path: "/api/v1/soul/atencion", body: { modo: "DISPONIBLE" } })).status, 200);
  } finally { await s.stop(); }
  s = await start(dir, []);
  try {
    await new Promise((r) => setTimeout(r, 200)); // varios tics de serve
    assert.equal((await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" })).json.modo, "DISPONIBLE", "lo último lo decidió la app");
  } finally { await s.stop(); }
  // Una declaración nueva de soul mode sí se aplica.
  writeFileSync(join(operatorDir(dir, "op-yo"), "attention.json"), JSON.stringify({ modo: "DESCANSO", hasta: new Date(Date.now() + 3_600_000).toISOString(), at: new Date(Date.now() + 1000).toISOString() }));
  s = await start(dir, []);
  try { assert.equal((await call(s.port, s.ca, p.token, { path: "/api/v1/soul/atencion" })).json.modo, "DESCANSO"); } finally { await s.stop(); }
});

test("avisos: un elemento que desaparece y vuelve se avisa de nuevo; uno que sigue vivo no se repite", () => {
  const e = { id: "e1", tipo: "tarea", titulo: "t", proyecto: null, personas: [], detalle: null, adaptador: "github", ruta: "api", dep: true, fecha: null, nace: Date.now(), observado: Date.now(), estado: "OBSERVED", sens: "N2", refs: [], mio: false, noMio: false, fijo: true, validoHasta: Date.now() + 86_400_000 } as any;
  let presente = true;
  let fase = 0;
  const srv = crearServidor({
    tls: { cert: "x", key: "y" },
    mundo: {
      semillas: () => [{ ref: "op", tokens: ["t"], nivel: "titulos", nivelMax: "titulos", proyectos: [], personas: [], elementos: [], adaptadores: [],
        avisos: { activos: ["vencimiento"], resumenInicio: null, resumenCierre: null, max: 50, ventanaMin: 60, tope: 3 }, alertas: [] }],
      refrescar: (ctx, o, t) => {
        fase++;
        if (presente && !o.elementos.has("e1")) { o.elementos.set("e1", { ...e }); ctx.evento(o, { tipo: "aviso", categoria: "vencimiento", ids: ["e1"] }, t); }
        else if (presente) ctx.evento(o, { tipo: "aviso", categoria: "vencimiento", ids: ["e1"] }, t);
        if (!presente) o.elementos.delete("e1");
      },
    },
  });
  const avisos = () => srv.operador("op").mensajes.filter((m: { ids: string[]; tipo: string }) => m.tipo === "aviso" && m.ids.includes("e1")).length;
  srv.estadisticas("op"); srv.estadisticas("op");
  assert.equal(avisos(), 1, "vivo: no se repite");
  presente = false; srv.estadisticas("op");
  presente = true; srv.estadisticas("op");
  assert.equal(avisos(), 2, "reaparece: se avisa otra vez");
  assert.ok(fase >= 4);
});
