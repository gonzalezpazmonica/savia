import { test } from "node:test";
import assert from "node:assert/strict";
import {
  MemoryBackend, SystemCredentialStore, entryKey,
} from "../../src/adapters/credential-store.ts";

const NOW = 1_000_000_000;
const set = (over = {}) => JSON.stringify({ access_token: "at-ok", refresh_token: "rt-ok", expires_at: NOW + 3600_000, scopes: ["Mail.Read"], ...over });

test("entryKey: por operador (con hash), servicio y permisos, sin el ref en claro", () => {
  const k = entryKey("op-pm", "graph", ["Mail.Read"]);
  assert.match(k, /^soul-continuity\/[0-9a-f]{16}\/graph\/[0-9a-f]{16}$/);
  assert.ok(!k.includes("op-pm"));
  assert.equal(k, entryKey("op-pm", "graph", ["Mail.Read"]));
  assert.notEqual(k, entryKey("op-pm", "graph", ["Mail.ReadBasic"]));
  assert.notEqual(k, entryKey("op-dir", "graph", ["Mail.Read"]));
  assert.equal(entryKey("op", "g", ["b", "a"]), entryKey("op", "g", ["a", "b"]));
});

test("acquire: sin entrada → no_credential; vigente → el token", async () => {
  const b = new MemoryBackend();
  const s = new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW });
  await assert.rejects(s.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "no_credential");
  await b.set(entryKey("op-pm", "graph", ["Mail.Read"]), set());
  assert.equal(await s.acquire("graph", ["Mail.Read"]), "at-ok");
  await assert.rejects(new SystemCredentialStore({ backend: b, operatorRef: "op-otro", now: () => NOW }).acquire("graph", ["Mail.Read"]),
    (e: { code?: string }) => e.code === "no_credential", "otro operador no usa el token");
});

test("acquire: caducado → renueva con el refresh y guarda el nuevo en el almacén", async () => {
  const b = new MemoryBackend();
  const key = entryKey("op-pm", "graph", ["Mail.Read"]);
  await b.set(key, set({ expires_at: NOW - 1 }));
  const calls: string[] = [];
  const s = new SystemCredentialStore({
    backend: b, operatorRef: "op-pm", now: () => NOW,
    refresh: async (service, rt, scopes) => { calls.push(`${service}:${rt}:${scopes.join(",")}`); return { access_token: "at-new", refresh_token: "rt-new", expires_at: NOW + 3600_000, scopes }; },
  });
  assert.equal(await s.acquire("graph", ["Mail.Read"]), "at-new");
  assert.deepEqual(calls, ["graph:rt-ok:Mail.Read"]);
  assert.equal(JSON.parse((await b.get(key))!).access_token, "at-new");
});

test("acquire: dos lecturas a la vez con el token caducado renuevan una sola vez", async () => {
  const b = new MemoryBackend();
  await b.set(entryKey("op-pm", "graph", ["Mail.Read"]), set({ expires_at: NOW - 1 }));
  let calls = 0;
  const s = new SystemCredentialStore({
    backend: b, operatorRef: "op-pm", now: () => NOW,
    refresh: async (_s, _rt, scopes) => { calls++; await new Promise((r) => setTimeout(r, 10)); return { access_token: `at-${calls}`, refresh_token: `rt-${calls}`, expires_at: NOW + 3600_000, scopes }; },
  });
  assert.deepEqual(await Promise.all([s.acquire("graph", ["Mail.Read"]), s.acquire("graph", ["Mail.Read"])]), ["at-1", "at-1"]);
  assert.equal(calls, 1);
  // Terminada la renovación, la siguiente lectura usa el token guardado sin renovar.
  assert.equal(await s.acquire("graph", ["Mail.Read"]), "at-1");
  assert.equal(calls, 1);
});

test("acquire: caducado sin forma de renovar → no_credential; renovación con administración → admin_consent_required", async () => {
  const b = new MemoryBackend();
  await b.set(entryKey("op-pm", "graph", ["Mail.Read"]), set({ expires_at: NOW - 1 }));
  await assert.rejects(new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW }).acquire("graph", ["Mail.Read"]),
    (e: { code?: string }) => e.code === "no_credential");
  const s = new SystemCredentialStore({
    backend: b, operatorRef: "op-pm", now: () => NOW,
    refresh: async () => { throw Object.assign(new Error("x"), { code: "admin_consent_required" }); },
  });
  await assert.rejects(s.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "admin_consent_required");
});

test("marca de administración guardada: acquire falla cerrado sin red", async () => {
  const b = new MemoryBackend();
  const s = new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW, refresh: async () => { throw new Error("no debe llamarse"); } });
  await s.markAdminRequired("graph", ["Mail.Read"]);
  await assert.rejects(s.acquire("graph", ["Mail.Read"]), (e: { code?: string }) => e.code === "admin_consent_required");
});

test("put y revoke: guardar un login y revocarlo deja el almacén sin la entrada", async () => {
  const b = new MemoryBackend();
  const s = new SystemCredentialStore({ backend: b, operatorRef: "op-pm", now: () => NOW });
  await s.put("graph", ["Chat.Read"], { access_token: "at", refresh_token: "rt", expires_at: NOW + 1000_000, scopes: ["Chat.Read"] });
  assert.equal(await s.acquire("graph", ["Chat.Read"]), "at");
  assert.equal(await s.revoke("graph", ["Chat.Read"]), true);
  assert.equal(await b.get(entryKey("op-pm", "graph", ["Chat.Read"])), null);
  assert.equal(await s.revoke("graph", ["Chat.Read"]), false);
});

// Los backends del sistema (Secret Service, Llavero, Credential Manager) son los del almacén único
// del núcleo: sus pruebas están en test/credentials.test.ts, junto a las de su vista `keyed()`.
