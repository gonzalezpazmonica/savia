import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import { initConfig, loginPlan, oauthRefresher } from "../src/cli/login.ts";
import { emptyConfig, loadConfig, saveConfig } from "../src/core/config.ts";
import { filesUnder } from "../src/core/store.ts";
import { MemoryBackend, SystemCredentialStore as ApiTokenStore } from "../src/adapters/credential-store.ts";
import { DESCRIPTORS } from "../src/adapters/descriptors.ts";

const NOW = "2026-11-01T09:00:00Z";
const PAT = "ghp-canario-login-7f3e";

function setup(o: { cfg?: boolean } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "soul-login-"));
  if (o.cfg !== false) {
    const c = emptyConfig("i");
    c.active_profile = "yo";
    c.profiles.yo = { operator: { ref: "op-yo", identities: { emails: ["yo@example.test"] } }, sources: [] };
    saveConfig(dir, c);
  }
  const backend = new MemoryBackend();
  const out: string[] = [];
  const err: string[] = [];
  const deps: CliDeps = {
    dataDir: dir, env: {}, now: () => NOW, out: (s) => out.push(s), err: (s) => err.push(s), adapters: {},
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "x" } },
    credentials: { revoke: async () => ({ tokens_removed: 0, cache_removed: false }), forgetAll: async () => [] },
    tokenStore: (ref) => new ApiTokenStore({ backend, operatorRef: ref, now: () => Date.parse(NOW) }),
    readSecret: async () => PAT,
    platform: "linux", home: dir, run: async () => ({ code: 0, stdout: "", stderr: "" }), node: "n", entry: "e",
  };
  return { dir, deps, out, err, backend };
}

test("init crea un perfil sin fuentes ni adaptadores activos y con una referencia opaca", async () => {
  const s = setup({ cfg: false });
  assert.equal(await runCli(["init", "trabajo", "--email", "yo@example.test"], s.deps), 0, s.err.join("\n"));
  const c = loadConfig(s.dir);
  assert.equal(c.active_profile, "trabajo");
  assert.match(c.profiles.trabajo.operator.ref, /^op-[0-9a-f]{16}$/);
  assert.deepEqual(c.profiles.trabajo.sources, []);
  assert.deepEqual(c.connectors, { enabled: [] }, "ningún adaptador activo por defecto");
  assert.deepEqual(c.api.listen, [], "sin direcciones de escucha por defecto");
  assert.equal(await runCli(["init", "otro"], s.deps), 1, "no pisa una instalación existente");
  assert.equal(loadConfig(s.dir).active_profile, "trabajo");
});

test("init sin nombre o con nombre raro => uso", async () => {
  const s = setup({ cfg: false });
  assert.equal(await runCli(["init"], s.deps), 2);
  assert.equal(await runCli(["init", "a b/../c"], s.deps), 2);
  assert.throws(() => initConfig("x".repeat(80), [], "i"));
});

test("login --token-stdin guarda el token del adaptador en el almacén y nada en disco", async () => {
  const s = setup();
  assert.equal(await runCli(["login", "github", "--token-stdin"], s.deps), 0, s.err.join("\n"));
  const t = new ApiTokenStore({ backend: s.backend, operatorRef: "op-yo", now: () => Date.parse(NOW) });
  assert.equal(await t.acquire("github", DESCRIPTORS.github.scopes[0]), PAT);
  const disk = filesUnder(s.dir).map((f) => readFileSync(f, "utf8")).join("\n");
  assert.ok(!disk.includes(PAT), "0 tokens en disco");
  assert.ok(!s.out.join("\n").includes(PAT) && !s.err.join("\n").includes(PAT), "ni en la salida");
});

test("login --token-stdin con token vacío o adaptador desconocido falla sin guardar nada", async () => {
  const s = setup();
  s.deps.readSecret = async () => "  \n";
  assert.equal(await runCli(["login", "github", "--token-stdin"], s.deps), 2);
  assert.equal(await runCli(["login", "otro", "--token-stdin"], s.deps), 2);
  assert.equal(await runCli(["login", "web", "--token-stdin"], s.deps), 2, "web no tiene token: se inicia sesión en su perfil");
  assert.equal((s.backend as unknown as { m: Map<string, string> }).m.size, 0, "ningún token guardado");
});

test("login desde un frontend de agente se rechaza (código 4)", async () => {
  const s = setup();
  s.deps.env = { CLAUDECODE: "1" };
  assert.equal(await runCli(["login", "github", "--token-stdin"], s.deps), 4);
});

test("loginPlan: OAuth para Microsoft 365 y Google con aplicación propia; token pegado para el resto", () => {
  assert.equal(loginPlan("m365-mail").kind, "oauth");
  assert.equal(loginPlan("google-workspace").kind, "oauth");
  for (const a of ["github", "jira", "azure-devops"]) assert.equal(loginPlan(a).kind, "token");
  assert.equal(loginPlan("web").kind, "none");
  assert.deepEqual((loginPlan("m365-calendar") as { scopes: string[] }).scopes, DESCRIPTORS["m365-calendar"].scopes[0]);
});

test("login OAuth sin aplicación propia configurada => error claro, sin red", async () => {
  const s = setup();
  assert.equal(await runCli(["login", "m365-mail"], s.deps), 1);
  assert.match(s.err.join("\n"), /connectors\.oauth\.microsoft/);
});

test("oauthRefresher: sin aplicación configurada no renueva (fail-closed)", async () => {
  const r = oauthRefresher({ enabled: [] });
  await assert.rejects(r("graph", "rt", ["Mail.Read"]), /aplicación/);
});
