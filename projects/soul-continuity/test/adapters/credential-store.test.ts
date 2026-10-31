import { test } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  MemoryBackend, SecretToolBackend, SystemCredentialStore, entryKey, macosCommands, windowsCommands,
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

test("secret-tool: el secreto viaja por stdin, nunca en argv", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-st-"));
  const store = join(dir, "store.json");
  const argvLog = join(dir, "argv.log");
  const fake = join(dir, "secret-tool");
  // Doble de secret-tool: guarda por atributo account en un JSON de prueba.
  writeFileSync(fake, `#!/usr/bin/env node
const fs=require("fs");const [cmd,...a]=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(argvLog)},JSON.stringify(process.argv.slice(2))+"\\n");
const f=${JSON.stringify(store)};const db=fs.existsSync(f)?JSON.parse(fs.readFileSync(f,"utf8")):{};const acc=a[a.indexOf("account")+1];
if(cmd==="store"){let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{db[acc]=s;fs.writeFileSync(f,JSON.stringify(db));});}
else if(cmd==="lookup"){if(acc in db)process.stdout.write(db[acc]);else process.exit(1);}
else if(cmd==="clear"){delete db[acc];fs.writeFileSync(f,JSON.stringify(db));}
`);
  chmodSync(fake, 0o755);
  const b = new SecretToolBackend({ command: fake });
  await b.set("soul-continuity/x/graph/y", "SECRETO-123");
  assert.equal(await b.get("soul-continuity/x/graph/y"), "SECRETO-123");
  await b.delete("soul-continuity/x/graph/y");
  assert.equal(await b.get("soul-continuity/x/graph/y"), null);
  assert.ok(existsSync(argvLog));
  assert.ok(!readFileSync(argvLog, "utf8").includes("SECRETO-123"), "el secreto no aparece en la línea de órdenes");
});

test("secret-tool ausente: falla cerrado con error, no devuelve vacío", async () => {
  const b = new SecretToolBackend({ command: "/nonexistent/secret-tool" });
  await assert.rejects(b.set("k", "v"));
  await assert.rejects(b.get("k"));
});

test("macOS y Windows: órdenes con el secreto solo en stdin", () => {
  const m = macosCommands.set("soul-continuity/x/graph/y", "SECRETO-123");
  assert.ok(!m.args.join(" ").includes("SECRETO"));
  assert.ok(m.stdin.includes(Buffer.from("SECRETO-123").toString("base64")));
  assert.ok(!m.stdin.includes("SECRETO-123"));
  const w = windowsCommands.set("soul-continuity/x/graph/y", "SECRETO-123");
  assert.ok(!w.args.join(" ").includes("SECRETO"));
  assert.ok(w.stdin.includes(Buffer.from("SECRETO-123").toString("base64")));
  assert.ok(!w.stdin.includes("SECRETO-123"));
  assert.throws(() => macosCommands.set('k"; rm', "v"), /clave/);
});
