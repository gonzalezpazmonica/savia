/**
 * Punta a punta (SE-490): la composición de producción con un adaptador real (GitHub) contra un
 * doble HTTP local, el almacén único sobre un doble de `secret-tool` y la API por TLS propio.
 * init → login → serve → pair por clave (soul-pair-v2) → Q1–Q4 y sondeo por cursor con DPoP → corrección ligada al
 * dispositivo → revoke de la fuente y unpair del móvil → uninstall, sin dejar estado ni tokens.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { request } from "node:https";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import { oauthRefresher } from "../src/cli/login.ts";
import { loadConfig, saveConfig } from "../src/core/config.ts";
import { apiTransport, productionAdapters, revokeSource } from "../src/core/connectors.ts";
import { operatorDir } from "../src/core/store.ts";
import { type Run, SystemCredentialStore, linuxBackend } from "../src/credentials/store.ts";
import { SystemCredentialStore as ApiTokenStore } from "../src/adapters/credential-store.ts";
import { serveFromCli } from "../src/api/serve.ts";
import { emptyData, startMock } from "./adapters/mock-apis.ts";
import { newKey, proof } from "./dpop-helper.ts";
import { emparejarComoApp } from "./pair-helper.ts";

const MOCK_TOKEN = "tok-e2e-canario-55aa";

function fakeSecretTool() {
  const vault = new Map<string, string>();
  const run: Run = async (_c, args, input = "") => {
    const k = args.slice(1).join("|").replace(/^--label=[^|]*\|/, "");
    if (args[0] === "store") { vault.set(k, input); return { code: 0, stdout: "", stderr: "" }; }
    if (args[0] === "lookup") return vault.has(k) ? { code: 0, stdout: vault.get(k) as string, stderr: "" } : { code: 1, stdout: "", stderr: "" };
    if (args[0] === "clear") { vault.delete(k); return { code: 0, stdout: "", stderr: "" }; }
    return { code: 0, stdout: "", stderr: "" };
  };
  return { vault, run };
}

async function freePort(): Promise<number> {
  const s = createServer();
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const p = (s.address() as { port: number }).port;
  await new Promise<void>((r) => s.close(() => r()));
  return p;
}

test("e2e: instalar, emparejar, consultar Q1–Q4 por cursor, corregir, revocar y desinstalar sin dejar estado", async () => {
  const d = emptyData();
  d.tokens[MOCK_TOKEN] = ["repo:read"];
  d.github.items.push({ repo: "api", number: 1, title: "Revisa el cambio", is_pr: true, assignees: [], requested: ["yo-gh"], mentions: [] });
  d.github.items.push({ repo: "api", number: 2, title: "Tarea asignada", is_pr: false, assignees: ["yo-gh"], requested: [], mentions: [] });
  const mock = await startMock(d);

  const dir = join(mkdtempSync(join(tmpdir(), "soul-e2e-")), "datos");
  const st = fakeSecretTool();
  const core = new SystemCredentialStore(linuxBackend(st.run), dir);
  const tokens = (ref: string) => new ApiTokenStore({ backend: core.keyed(), operatorRef: ref, refresh: oauthRefresher(undefined) });
  const out: string[] = [];
  const err: string[] = [];
  const deps: CliDeps = {
    dataDir: dir, env: {}, now: () => new Date().toISOString(), out: (s) => out.push(s), err: (s) => err.push(s),
    adapters: {}, adaptersFor: (c) => productionAdapters({ connectors: c.connectors, dataDir: dir }),
    sourceEnv: { transport: apiTransport(undefined), credentials: { acquire: () => Promise.reject(new Error("sin operador")) } },
    sourceEnvFor: (ref, c) => ({ transport: apiTransport(c.connectors), credentials: tokens(ref) }),
    credentials: { revoke: (a, ref) => revokeSource({ adapter: a, operatorRef: ref, dataDir: dir, tokens: tokens(ref) }), forgetAll: () => core.forgetAll() },
    tokenStore: (ref) => tokens(ref), readSecret: async () => MOCK_TOKEN,
    platform: "linux", home: dir, run: async () => ({ code: 0, stdout: "", stderr: "" }), node: "n", entry: "e",
  };
  const cli = async (...a: string[]) => { out.length = 0; const c = await runCli(a, deps); return { c, j: (() => { try { return JSON.parse(out.join("\n")); } catch { return null; } })() }; };
  const ac = new AbortController();
  let served: Promise<number> | null = null;
  try {
    // 1. Instalar y activar una fuente (por configuración del operador, nada por defecto).
    assert.equal((await cli("init", "trabajo", "--email", "yo@example.test")).c, 0, err.join("\n"));
    const cfg = loadConfig(dir);
    const ref = cfg.profiles.trabajo.operator.ref;
    cfg.profiles.trabajo.operator.identities.github = "yo-gh";
    cfg.profiles.trabajo.sources = [{ adapter: "github", purpose: "revisiones y tareas", consent: { granted_at: "2026-10-01T00:00:00Z", statement: "bajo mi responsabilidad" } }];
    cfg.connectors = { enabled: ["github"], bases: { github: mock.bases.github } };
    cfg.api = { listen: ["127.0.0.1"], port: await freePort() };
    saveConfig(dir, cfg);
    assert.equal((await cli("login", "github", "--token-stdin")).c, 0, err.join("\n"));
    const q1cli = await cli("q1", "--json");
    assert.equal(q1cli.c, 0, err.join("\n"));
    assert.equal(q1cli.j.total, 2, `la CLI lee GitHub con el adaptador real: ${JSON.stringify(q1cli.j.adapters)}`);

    // 2. Arrancar la API con su certificado propio y emparejar por código, como la app.
    served = serveFromCli(deps, { signal: ac.signal, refreshMs: 100 });
    for (let i = 0; i < 80 && !out.some((l) => l.includes("Escuchando")); i++) await new Promise((r) => setTimeout(r, 25));
    const port = cfg.api.port;
    const ca = readFileSync(join(dir, "tls", "cert.pem"), "utf8");
    const pair = await cli("pair", "--json");
    assert.equal(pair.c, 0, err.join("\n"));
    assert.equal(pair.j.token, undefined, "la CLI ya no muestra ningún token");
    const key = newKey();
    const { token, device_id: device } = await emparejarComoApp(port, `  ${pair.j.clave}\n`, key);
    const api = (path: string, method = "GET", body?: unknown) => new Promise<{ status: number; json: any }>((res, rej) => {
      const p = proof(key, { htm: method, htu: `https://127.0.0.1:${port}${path.split("?")[0]}`, iat: Date.now(), token });
      const q = request({ host: "127.0.0.1", port, path, method, ca, headers: { Authorization: `DPoP ${token}`, DPoP: p, ...(body ? { "Content-Type": "application/json" } : {}) } }, (r) => {
        let b = "";
        r.on("data", (c) => (b += c));
        r.on("end", () => res({ status: r.statusCode ?? 0, json: b ? JSON.parse(b) : null }));
      });
      q.on("error", rej);
      q.end(body ? JSON.stringify(body) : undefined);
    });

    // 3. Q1–Q4 y sondeo por cursor.
    const q1 = await api("/api/v1/soul/q/q1");
    assert.equal(q1.status, 200, JSON.stringify(q1.json));
    assert.equal(q1.json.recuentos.total, 2);
    assert.equal((await api("/api/v1/soul/q/q2")).status, 200);
    assert.equal((await api(`/api/v1/soul/q/q3?desde=${encodeURIComponent(new Date(Date.now() - 3_600_000).toISOString())}`)).status, 200);
    assert.equal((await api("/api/v1/soul/q/q4")).status, 200);
    const s1 = await api("/api/v1/soul/sondeo");
    assert.equal(s1.status, 200);
    assert.ok(s1.json.mensajes.length >= 1, "los elementos nuevos generan avisos en el sondeo");
    const s2 = await api(`/api/v1/soul/sondeo?cursor=${encodeURIComponent(s1.json.cursor)}`);
    assert.equal(s2.status, 200);
    assert.equal(s2.json.mensajes.filter((m: { categoria: string }) => m.categoria !== "correccion_confirmada").length, 0, "con cursor no se repite lo ya entregado");

    // 4. Corregir desde la app: queda en el libro con el dispositivo.
    const target = q1.json.elementos[0].id;
    const c = await api(`/api/v1/soul/elementos/${target}/correccion`, "POST", { tipo: "resuelto" });
    assert.equal(c.status, 200, JSON.stringify(c.json));
    await new Promise((r) => setTimeout(r, 100));
    const ledger = readFileSync(join(operatorDir(dir, ref), "ledger.jsonl"), "utf8");
    assert.ok(ledger.includes(`"device":"${device}"`), "corrección ligada al dispositivo (P1-2)");
    assert.equal((await api("/api/v1/soul/q/q1")).json.recuentos.total, 1, "lo resuelto no vuelve");

    // 5. Revocar la fuente: tokens y caché fuera; el servicio deja de leerla.
    const control = mock.log.length;
    await new Promise((r) => setTimeout(r, 400));
    assert.ok(mock.log.slice(control).some((l: { url: string }) => l.url.includes("search/issues")), "control: serve relee GitHub en cada tic");
    const rv = await cli("revoke", "github", "--json");
    assert.equal(rv.c, 0, err.join("\n"));
    assert.equal(rv.j.tokens_removed, 1);
    assert.equal(st.vault.size, 0, "ningún token en el almacén tras revocar");
    // Una lectura que ya estaba en curso al revocar puede terminar después: se espera a que acabe
    // (las lecturas no se solapan) y desde ahí ningún tic debe volver a leer GitHub.
    const lecturas = () => mock.log.filter((l: { url: string }) => l.url.includes("search/issues")).length;
    for (let n = lecturas(), quieto = 0, i = 0; quieto < 3 && i < 30; i++) {
      await new Promise((r) => setTimeout(r, 100));
      const m = lecturas();
      quieto = m === n ? quieto + 1 : 0;
      n = m;
    }
    const antes = mock.log.length;
    await new Promise((r) => setTimeout(r, 400)); // varios tics de serve (refreshMs 100)
    assert.equal(mock.log.slice(antes).filter((l: { url: string }) => l.url.includes("search/issues")).length, 0, "el servicio deja de leer la fuente revocada");

    // 6. Revocar el móvil: su token deja de valer.
    assert.equal((await api("/api/v1/soul/estado")).status, 200, "control: el móvil entra antes de revocarlo");
    assert.equal((await cli("unpair", device)).c, 0, err.join("\n"));
    const r = await api("/api/v1/soul/estado");
    assert.equal(r.status, 401);
    assert.equal(r.json.error, "DEVICE_REVOKED");
  } finally {
    ac.abort();
    if (served) assert.equal(await served, 0);
    await mock.close();
  }

  // 7. Desinstalar: no queda nada.
  assert.equal((await cli("uninstall", "--yes")).c, 0, err.join("\n"));
  assert.equal(existsSync(dir), false, "no queda el directorio de datos");
  assert.equal(st.vault.size, 0);
  const all = [...out, ...err].join("\n");
  assert.ok(!all.includes(MOCK_TOKEN), "el token de la fuente no aparece en ninguna salida");
});
