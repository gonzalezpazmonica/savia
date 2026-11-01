import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FileDeltaCache, adapterCacheDir } from "../../src/adapters/delta-cache.ts";
import { MemoryBackend, SystemCredentialStore, entryKey } from "../../src/adapters/credential-store.ts";
import { revokeAdapter } from "../../src/adapters/revoke.ts";

const T = { access_token: "at", refresh_token: "rt", expires_at: Date.now() + 3600_000, scopes: [] as string[] };

test("revocar m365-mail borra su caché y sus tokens (todas las variantes de permisos) y nada más", async () => {
  const stateDir = mkdtempSync(join(tmpdir(), "s490-rv-"));
  const cache = new FileDeltaCache(stateDir);
  await cache.save("op-pm", "m365-mail", "inbox", { link: "/x", complete: true, items: {} });
  await cache.save("op-pm", "m365-teams", "k", { link: null, complete: true, items: {} });
  await cache.save("op-otra", "m365-mail", "inbox", { link: "/x", complete: true, items: {} });
  const b = new MemoryBackend();
  const store = new SystemCredentialStore({ backend: b, operatorRef: "op-pm" });
  await store.put("graph", ["Mail.Read"], T);
  await store.put("graph", ["Mail.ReadBasic"], T);
  await store.put("graph", ["Chat.Read"], T);
  await new SystemCredentialStore({ backend: b, operatorRef: "op-otra" }).put("graph", ["Mail.Read"], T);

  const r = await revokeAdapter({ adapter: "m365-mail", operatorRef: "op-pm", stateDir, store });
  assert.deepEqual(r, { adapter: "m365-mail", cache_removed: true, tokens_removed: 2 });
  assert.equal(existsSync(adapterCacheDir(stateDir, "op-pm", "m365-mail")), false);
  assert.equal(await b.get(entryKey("op-pm", "graph", ["Mail.Read"])), null);
  assert.equal(await b.get(entryKey("op-pm", "graph", ["Mail.ReadBasic"])), null);
  // Lo de otros adaptadores y otros operadores sigue.
  assert.ok(existsSync(adapterCacheDir(stateDir, "op-pm", "m365-teams")));
  assert.ok(existsSync(adapterCacheDir(stateDir, "op-otra", "m365-mail")));
  assert.notEqual(await b.get(entryKey("op-pm", "graph", ["Chat.Read"])), null);
  assert.notEqual(await b.get(entryKey("op-otra", "graph", ["Mail.Read"])), null);
  await assert.rejects(store.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "no_credential");
});

test("revocar dos veces es idempotente y lo dice", async () => {
  const stateDir = mkdtempSync(join(tmpdir(), "s490-rv-"));
  const store = new SystemCredentialStore({ backend: new MemoryBackend(), operatorRef: "op" });
  assert.deepEqual(await revokeAdapter({ adapter: "github", operatorRef: "op", stateDir, store }), { adapter: "github", cache_removed: false, tokens_removed: 0 });
});

test("un adaptador desconocido o el web no se revocan aquí (fail-closed)", async () => {
  const store = new SystemCredentialStore({ backend: new MemoryBackend(), operatorRef: "op" });
  await assert.rejects(revokeAdapter({ adapter: "web", operatorRef: "op", stateDir: "/tmp", store }));
  await assert.rejects(revokeAdapter({ adapter: "../../etc", operatorRef: "op", stateDir: "/tmp", store }));
});

test("si el almacén falla, la revocación no dice que borró los tokens", async () => {
  const stateDir = mkdtempSync(join(tmpdir(), "s490-rv-"));
  const broken = { async get() { return null; }, async set() {}, async delete(): Promise<boolean> { throw new Error("sin almacén"); } };
  const store = new SystemCredentialStore({ backend: broken, operatorRef: "op" });
  await new FileDeltaCache(stateDir).save("op", "jira", "k", { link: null, complete: true, items: { j1: { id: "j1", subject: "Asunto" } } });
  await assert.rejects(revokeAdapter({ adapter: "jira", operatorRef: "op", stateDir, store }), /sin almacén/);
  assert.equal(existsSync(adapterCacheDir(stateDir, "op", "jira")), false, "la caché con datos personales se borra aunque falle el almacén");
});
