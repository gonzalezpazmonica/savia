import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FileDeltaCache, MemoryDeltaCache, adapterCacheDir, operatorDir } from "../../src/adapters/delta-cache.ts";

const st = { link: "/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=abc", complete: true, items: { m1: { id: "m1", subject: "Hola" } } };

test("operatorDir: hash estable del operador, sin el ref en claro", () => {
  const d = operatorDir("/s", "op-pm");
  assert.match(d, /^\/s\/op-[0-9a-f]{16}$/);
  assert.equal(d, operatorDir("/s", "op-pm"));
  assert.notEqual(d, operatorDir("/s", "op-dir"));
  assert.equal(adapterCacheDir("/s", "op-pm", "m365-mail"), join(d, "adapters", "m365-mail"));
});

test("FileDeltaCache: guarda y lee por operador, adaptador y clave, con permisos 0600", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-dc-"));
  const c = new FileDeltaCache(dir);
  await c.save("op-pm", "m365-mail", "inbox|Mail.Read", st);
  assert.deepEqual(await c.load("op-pm", "m365-mail", "inbox|Mail.Read"), st);
  assert.equal(await c.load("op-dir", "m365-mail", "inbox|Mail.Read"), null, "otro operador no ve la caché");
  assert.equal(await c.load("op-pm", "m365-mail", "sentitems|Mail.Read"), null);
  const files = readdirSync(adapterCacheDir(dir, "op-pm", "m365-mail"));
  assert.equal(files.length, 1);
  const f = join(adapterCacheDir(dir, "op-pm", "m365-mail"), files[0]);
  if (process.platform !== "win32") assert.equal(statSync(f).mode & 0o777, 0o600);
  assert.ok(!readFileSync(f, "utf8").includes("op-pm"));
});

test("FileDeltaCache: clear borra solo ese adaptador del operador", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-dc-"));
  const c = new FileDeltaCache(dir);
  await c.save("op-pm", "m365-mail", "k", st);
  await c.save("op-pm", "m365-teams", "k", st);
  await c.clear("op-pm", "m365-mail");
  assert.equal(existsSync(adapterCacheDir(dir, "op-pm", "m365-mail")), false);
  assert.deepEqual(await c.load("op-pm", "m365-teams", "k"), st);
});

test("FileDeltaCache: un fichero corrupto se trata como sin caché (resincroniza)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-dc-"));
  const c = new FileDeltaCache(dir);
  await c.save("op-pm", "m365-mail", "k", st);
  const d = adapterCacheDir(dir, "op-pm", "m365-mail");
  const { writeFileSync } = await import("node:fs");
  writeFileSync(join(d, readdirSync(d)[0]), "{no json");
  assert.equal(await c.load("op-pm", "m365-mail", "k"), null);
});

test("FileDeltaCache: rechaza campos de cuerpo en lo que se guarda", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-dc-"));
  const c = new FileDeltaCache(dir);
  await assert.rejects(c.save("op-pm", "m365-mail", "k", { link: null, complete: true, items: { m1: { id: "m1", body: "x" } } }));
  await assert.rejects(c.save("op-pm", "m365-mail", "k", { link: null, complete: true, items: { m1: { id: "m1", bodyPreview: "x" } } }));
});

test("MemoryDeltaCache: aislada por operador y copia profunda", async () => {
  const c = new MemoryDeltaCache();
  await c.save("op-pm", "m365-mail", "k", st);
  const got = await c.load("op-pm", "m365-mail", "k");
  (got!.items.m1 as Record<string, unknown>).subject = "cambiado";
  assert.equal((await c.load("op-pm", "m365-mail", "k"))!.items.m1.subject, "Hola");
  assert.equal(await c.load("op-otro", "m365-mail", "k"), null);
});
