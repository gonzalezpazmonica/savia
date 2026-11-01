/**
 * AC-5 de punta a punta por la CLI, con la composición real de `soul.ts`: almacén único sobre un
 * doble de `secret-tool`, tokens de dos adaptadores de API, caché delta y perfil web.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import { emptyConfig, saveConfig } from "../src/core/config.ts";
import { productionAdapters, revokeSource, webDir } from "../src/core/connectors.ts";
import { type Run, SystemCredentialStore, linuxBackend } from "../src/credentials/store.ts";
import { SystemCredentialStore as ApiTokenStore } from "../src/adapters/credential-store.ts";
import { adapterCacheDir } from "../src/adapters/delta-cache.ts";
import { DESCRIPTORS } from "../src/adapters/descriptors.ts";

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

async function setup() {
  const dir = mkdtempSync(join(tmpdir(), "soul-ac5-"));
  const st = fakeSecretTool();
  const core = new SystemCredentialStore(linuxBackend(st.run), dir);
  const tokens = (ref: string) => new ApiTokenStore({ backend: core.keyed(), operatorRef: ref });
  const cfg = emptyConfig("inst-ac5");
  cfg.active_profile = "yo";
  cfg.connectors = { enabled: ["m365-mail", "github", "web"] };
  const consent = { granted_at: "2026-10-01T00:00:00Z", statement: "bajo mi responsabilidad" };
  cfg.profiles.yo = {
    operator: { ref: "op-yo", identities: { emails: ["yo@example.test"] } },
    sources: [{ adapter: "m365-mail", purpose: "correo", consent }, { adapter: "github", purpose: "revisiones", consent }, { adapter: "web", purpose: "webs", consent }],
  };
  saveConfig(dir, cfg);
  const t = tokens("op-yo");
  for (const sc of DESCRIPTORS["m365-mail"].scopes) await t.put("graph", sc, { access_token: "tok-correo", expires_at: 9e15, scopes: sc });
  await t.put("github", DESCRIPTORS.github.scopes[0], { access_token: "tok-gh", expires_at: 9e15, scopes: [] });
  mkdirSync(adapterCacheDir(dir, "op-yo", "m365-mail"), { recursive: true });
  writeFileSync(join(adapterCacheDir(dir, "op-yo", "m365-mail"), "inbox.json"), "{}");
  mkdirSync(join(webDir(dir), "perfil"), { recursive: true });
  writeFileSync(join(webDir(dir), "perfil", "Cookies"), "sesion");
  const out: string[] = [];
  const err: string[] = [];
  const deps: CliDeps = {
    dataDir: dir, env: {}, now: () => "2026-11-01T09:00:00Z", out: (s) => out.push(s), err: (s) => err.push(s),
    adapters: {}, adaptersFor: (c) => productionAdapters({ connectors: c.connectors, dataDir: dir }),
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "x" } },
    credentials: { revoke: (a, ref) => revokeSource({ adapter: a, operatorRef: ref, dataDir: dir, tokens: tokens(ref) }), forgetAll: () => core.forgetAll() },
    platform: "linux", home: dir, run: async () => ({ code: 0, stdout: "", stderr: "" }), node: "n", entry: "e",
  };
  return { dir, st, core, deps, out, err };
}

test("AC-5: soul revoke m365-mail borra sus tokens (todas las variantes) y su caché delta; GitHub sigue", async () => {
  const s = await setup();
  assert.equal(s.st.vault.size, 3);
  assert.equal(await runCli(["revoke", "m365-mail", "--json"], s.deps), 0, s.err.join("\n"));
  const r = JSON.parse(s.out.at(-1) as string);
  assert.equal(r.tokens_removed, 2);
  assert.equal(r.adapter_cache_removed, true);
  assert.equal(existsSync(adapterCacheDir(s.dir, "op-yo", "m365-mail")), false);
  assert.equal(s.st.vault.size, 1, "solo queda el token de GitHub");
  assert.equal(s.core.index().length, 1);
});

test("AC-5: soul revoke web borra el perfil del navegador con sus sesiones", async () => {
  const s = await setup();
  assert.equal(await runCli(["revoke", "web"], s.deps), 0, s.err.join("\n"));
  assert.equal(existsSync(webDir(s.dir)), false);
});

test("AC-5: soul uninstall --yes borra los tokens de todos los adaptadores, la caché delta y web/", async () => {
  const s = await setup();
  assert.equal(await runCli(["uninstall", "--yes"], s.deps), 0, s.err.join("\n"));
  assert.equal(s.st.vault.size, 0, "ningún token en el almacén del sistema");
  assert.equal(existsSync(s.dir), false, "no queda el directorio de datos");
});

test("AC-5: si el almacén no puede borrar, uninstall falla y no dice «desinstalado»", async () => {
  const s = await setup();
  s.deps.credentials.forgetAll = async () => { throw new Error("no se pudieron borrar 1 credencial(es)"); };
  assert.equal(await runCli(["uninstall", "--yes"], s.deps), 1);
  assert.ok(!s.out.join("\n").includes("Desinstalado"));
});
