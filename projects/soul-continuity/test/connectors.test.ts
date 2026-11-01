import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { AdapterContext } from "../src/contract/adapter.ts";
import {
  apiTransport, enabledAdapters, productionAdapters, productionWebAdapter, revokeSource, validateConnectors, webDir,
} from "../src/core/connectors.ts";
import { entryKey, MemoryBackend, SystemCredentialStore } from "../src/adapters/credential-store.ts";
import { adapterCacheDir } from "../src/adapters/delta-cache.ts";
import { DESCRIPTORS } from "../src/adapters/descriptors.ts";

const tmp = () => mkdtempSync(join(tmpdir(), "soul-conn-"));
const ctx = (over: Partial<AdapterContext> = {}): AdapterContext => ({
  operator: { ref: "op-a", identities: { emails: ["yo@example.test"] } }, now: "2026-11-01T09:00:00Z", sensitivity: "N4",
  route: "web", params: {}, transport: { request: async () => ({ status: 500, headers: {}, body: null }) },
  credentials: { acquire: async () => "t" }, ...over,
});

test("H-1: sin connectors no se registra ningún adaptador (nada activo por defecto)", () => {
  assert.deepEqual(Object.keys(productionAdapters({ dataDir: tmp() })), []);
  assert.deepEqual(Object.keys(productionAdapters({ dataDir: tmp(), connectors: { enabled: [] } })), []);
});

test("H-1: solo se registran los adaptadores que el operador activa; web solo si lo nombra", () => {
  const r = productionAdapters({ dataDir: tmp(), connectors: { enabled: ["github", "m365-mail"] } });
  assert.deepEqual(Object.keys(r).sort(), ["github", "m365-mail"]);
  assert.equal(r.web, undefined);
  for (const [k, a] of Object.entries(r)) assert.equal(a?.name, k);
  const w = productionAdapters({ dataDir: tmp(), connectors: { enabled: ["web"] } });
  assert.deepEqual(Object.keys(w), ["web"]);
});

test("H-1: todos los adaptadores de API del contrato están disponibles para activarse", () => {
  const all = Object.keys(DESCRIPTORS);
  assert.deepEqual(Object.keys(productionAdapters({ dataDir: tmp(), connectors: { enabled: [...all, "web"] } })).sort(), [...all, "web"].sort());
});

test("validateConnectors: adaptador desconocido, base http remota o con credenciales => problema", () => {
  assert.deepEqual(validateConnectors(undefined), []);
  assert.deepEqual(validateConnectors({ enabled: ["jira"], bases: { jira: "https://sitio.example", ado: "http://127.0.0.1:9" } }), []);
  assert.equal(validateConnectors({ enabled: ["otro"] }).length, 1);
  assert.equal(validateConnectors({ enabled: "jira" }).length, 1);
  assert.equal(validateConnectors({ enabled: [], bases: { jira: "http://sitio.example" } }).length, 1);
  assert.equal(validateConnectors({ enabled: [], bases: { jira: "https://u:p@sitio.example" } }).length, 1);
  assert.equal(validateConnectors({ enabled: [], bases: { evil: "https://x.example" } }).length, 1);
  assert.deepEqual([...enabledAdapters({ enabled: ["jira", "otro" as never] })], ["jira"]);
});

test("apiTransport: solo lectura y solo hacia las bases; Jira sin base configurada se rechaza", async () => {
  const seen: string[] = [];
  const t = apiTransport({ enabled: [], bases: { jira: "https://sitio.example" } }, {
    fetch: (async (u: URL | string) => { seen.push(String(u)); return new Response("{}", { status: 200, headers: { "content-type": "application/json" } }); }) as typeof fetch,
  });
  assert.equal((await t.request({ service: "jira", method: "GET", url: "/rest/api/3/myself" })).status, 200);
  assert.equal((await t.request({ service: "graph", method: "GET", url: "/v1.0/me" })).status, 200);
  assert.deepEqual(seen, ["https://sitio.example/rest/api/3/myself", "https://graph.microsoft.com/v1.0/me"]);
  await assert.rejects(t.request({ service: "graph", method: "DELETE", url: "/v1.0/me/messages/1" }), /solo lectura/);
  await assert.rejects(t.request({ service: "ado", method: "GET", url: "/x" }), /sin base/);
  await assert.rejects(t.request({ service: "graph", method: "GET", url: "https://otro.example/v1.0/me" }), /origen/);
});

test("H-4: el adaptador web usa siempre el directorio de datos de Soul aunque la configuración diga otra cosa", async () => {
  const d = tmp();
  let got: Record<string, unknown> = {};
  const a = productionWebAdapter(d, async () => ({
    crearAdaptadorWeb: () => ({ name: "web", routes: ["web"], purpose: "p", read: async (c) => { got = c.params; return { status: "ok", route: "web", claims: [] }; } }),
    prepararPerfilSoul: (datos: string) => { const p = join(datos, "web", "perfil"); mkdirSync(p, { recursive: true }); return p; },
    buscarNavegador: () => ({ ruta: "/usr/bin/navegador" }),
  }));
  const r = await a.read(ctx({ params: { perfil: "/otro/sitio", huellas: "/otro/h.json", validaciones: "/otro/v" } }));
  assert.equal(r.status, "ok");
  for (const k of ["perfil", "huellas", "desactivadas", "validaciones"]) assert.ok(String(got[k]).startsWith(webDir(d)), `${k}: ${got[k]}`);
  assert.equal(got.ejecutable, "/usr/bin/navegador");
});

test("web sin playwright-core instalado: la fuente queda unavailable, sin romper la lectura", async () => {
  const a = productionWebAdapter(tmp(), async () => { throw new Error("Cannot find package 'playwright-core'"); });
  const r = await a.read(ctx());
  assert.equal(r.status, "unavailable");
});

test("web: si no hay navegador instalado, error con motivo (fail-closed, sin afirmaciones)", async () => {
  const a = productionWebAdapter(tmp(), async () => ({
    crearAdaptadorWeb: () => { throw new Error("no debería llegar"); },
    prepararPerfilSoul: () => "/p", buscarNavegador: () => { throw new Error("no hay Chrome ni Edge instalados"); },
  }));
  const r = await a.read(ctx());
  assert.equal(r.status, "error");
  assert.match(String((r as { message?: string }).message), /Chrome/);
});

test("AC-5 (H-3): revocar un adaptador de API borra su caché delta y sus tokens de todas las variantes", async () => {
  const d = tmp();
  const b = new MemoryBackend();
  const store = new SystemCredentialStore({ backend: b, operatorRef: "op-a" });
  for (const sc of DESCRIPTORS["m365-mail"].scopes) await store.put("graph", sc, { access_token: "x", expires_at: 9e15, scopes: sc });
  await store.put("graph", DESCRIPTORS["m365-calendar"].scopes[0], { access_token: "y", expires_at: 9e15, scopes: [] });
  const cache = adapterCacheDir(d, "op-a", "m365-mail");
  mkdirSync(cache, { recursive: true });
  writeFileSync(join(cache, "delta.json"), "{}");
  const r = await revokeSource({ adapter: "m365-mail", operatorRef: "op-a", dataDir: d, tokens: store });
  assert.deepEqual(r, { adapter: "m365-mail", cache_removed: true, tokens_removed: 2 });
  assert.equal(existsSync(cache), false);
  for (const sc of DESCRIPTORS["m365-mail"].scopes) assert.equal(await b.get(entryKey("op-a", "graph", sc)), null);
  assert.notEqual(await b.get(entryKey("op-a", "graph", DESCRIPTORS["m365-calendar"].scopes[0])), null, "otro adaptador conserva su token");
});

test("AC-5: revocar web borra todo <datos>/web (perfil con sesiones, huellas, recibos)", async () => {
  const d = tmp();
  mkdirSync(join(webDir(d), "perfil", "Default"), { recursive: true });
  writeFileSync(join(webDir(d), "perfil", "Default", "Cookies"), "sesion");
  const r = await revokeSource({ adapter: "web", operatorRef: "op-a", dataDir: d, tokens: { revoke: async () => true } });
  assert.equal(r.cache_removed, true);
  assert.equal(existsSync(webDir(d)), false);
});

test("revokeSource con un adaptador desconocido lanza", async () => {
  await assert.rejects(revokeSource({ adapter: "x", operatorRef: "op", dataDir: tmp(), tokens: { revoke: async () => true } }), /desconocido/);
});

const WEB_INSTALADO = existsSync(new URL("../src/web/node_modules/playwright-core/package.json", import.meta.url));

test("el registro carga el adaptador web real de src/web (rutas de importación correctas)", { skip: !WEB_INSTALADO && "playwright-core no instalado en src/web" }, async () => {
  const d = tmp();
  const antes = process.env.SOUL_NAVEGADOR;
  process.env.SOUL_NAVEGADOR = process.execPath; // existe en cualquier máquina; sin recetas no se lanza
  let r;
  try { r = await productionAdapters({ dataDir: d, connectors: { enabled: ["web"] } }).web?.read(ctx({ params: {} })); }
  finally { if (antes === undefined) delete process.env.SOUL_NAVEGADOR; else process.env.SOUL_NAVEGADOR = antes; }
  // Sin recetas ni páginas vigiladas no abre el navegador: el módulo real responde «sin configurar» (#1443), no «no instalado».
  assert.equal(r?.status, "not_configured");
  assert.ok(existsSync(join(webDir(d), "perfil", ".perfil-soul")), "perfil dedicado dentro del directorio de datos de Soul");
});

test("el ejecutable del navegador no sale de config.json: params.ejecutable se ignora y manda buscarNavegador()", async () => {
  let visto: unknown;
  type Load = NonNullable<Parameters<typeof productionWebAdapter>[1]>;
  const load: Load = async () => ({
    crearAdaptadorWeb: () => ({ name: "web", routes: ["web"], purpose: "", read: async (c: AdapterContext) => { visto = c.params.ejecutable; return { status: "ok" as const, route: "web", claims: [] }; } }),
    prepararPerfilSoul: (datos: string) => join(datos, "web", "perfil"),
    buscarNavegador: () => ({ ruta: "/ruta/conocida/chrome" }),
  });
  const r = await productionWebAdapter(tmp(), load).read(ctx({ params: { ejecutable: "/tmp/otro-binario" } }));
  assert.equal(r.status, "ok");
  assert.equal(visto, "/ruta/conocida/chrome");
  // Sin navegador conocido, falla cerrado aunque la configuración nombre uno.
  const sin: Load = async () => ({ ...(await load()), buscarNavegador: () => { throw new Error("No hay Chrome"); } });
  assert.equal((await productionWebAdapter(tmp(), sin).read(ctx({ params: { ejecutable: "/tmp/otro-binario" } }))).status, "error");
});
