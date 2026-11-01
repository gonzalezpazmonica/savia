import { test } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { FileDeltaCache, MemoryDeltaCache, adapterCacheDir, operatorDir } from "../../src/adapters/delta-cache.ts";

const st = { link: "/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=abc", complete: true, items: { m1: { id: "m1", subject: "Hola" } } };

test("operatorDir: hash estable del operador, sin el ref en claro", () => {
  const d = operatorDir("/s", "op-pm");
  // Separador de la plataforma: en Windows `join` usa «\».
  assert.equal(dirname(d), join("/s"));
  assert.match(basename(d), /^op-[0-9a-f]{16}$/);
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

test("FileDeltaCache: lo cargado se valida como lo guardado (sin cuerpos, tipos de Meta)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-dc-"));
  const c = new FileDeltaCache(dir);
  await c.save("op-pm", "m365-mail", "k", st);
  const d = adapterCacheDir(dir, "op-pm", "m365-mail");
  const f = join(d, readdirSync(d)[0]);
  const put = (items: unknown) => writeFileSync(f, JSON.stringify({ link: null, complete: true, items }));
  put({ m1: { id: "m1", to: ["a@b.example"], n: 1, ok: true, due: null } });
  assert.deepEqual((await c.load("op-pm", "m365-mail", "k"))!.items.m1.to, ["a@b.example"], "una Meta válida se carga");
  put({ m1: { id: "m1", body: "texto" } });
  assert.equal(await c.load("op-pm", "m365-mail", "k"), null, "un campo de cuerpo manipulado no se carga");
  put({ m1: { id: "m1", to: { x: 1 } } });
  assert.equal(await c.load("op-pm", "m365-mail", "k"), null, "un valor que no es de Meta no se carga");
  put({ m1: "texto" });
  assert.equal(await c.load("op-pm", "m365-mail", "k"), null);
  put([{ id: "m1" }]);
  assert.equal(await c.load("op-pm", "m365-mail", "k"), null);
});

test("MemoryDeltaCache: aislada por operador y copia profunda", async () => {
  const c = new MemoryDeltaCache();
  await c.save("op-pm", "m365-mail", "k", st);
  const got = await c.load("op-pm", "m365-mail", "k");
  (got!.items.m1 as Record<string, unknown>).subject = "cambiado";
  assert.equal((await c.load("op-pm", "m365-mail", "k"))!.items.m1.subject, "Hola");
  assert.equal(await c.load("op-otro", "m365-mail", "k"), null);
});

test("FileDeltaCache: endurece a 0700 directorios previos y no reutiliza un .tmp ajeno", { skip: process.platform === "win32" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "s490-dc-"));
  const ad = adapterCacheDir(dir, "op-pm", "m365-mail");
  mkdirSync(ad, { recursive: true, mode: 0o755 });
  for (const d of [ad, join(ad, ".."), operatorDir(dir, "op-pm")]) chmodSync(d, 0o755);
  // Un .tmp de nombre fijo con permisos abiertos, como el que dejaba la versión anterior.
  const files0 = new FileDeltaCache(dir);
  await files0.save("op-pm", "m365-mail", "k", st);
  const f = join(ad, readdirSync(ad)[0]);
  writeFileSync(`${f}.tmp`, "{}", { mode: 0o644 });
  chmodSync(`${f}.tmp`, 0o644);
  chmodSync(f, 0o644);
  for (const d of [ad, join(ad, ".."), operatorDir(dir, "op-pm")]) chmodSync(d, 0o755);
  await files0.save("op-pm", "m365-mail", "k", st);
  for (const d of [ad, join(ad, ".."), operatorDir(dir, "op-pm")]) assert.equal(statSync(d).mode & 0o777, 0o700, d);
  assert.equal(statSync(f).mode & 0o777, 0o600, "el fichero final sale de un temporal nuevo con 0600");
  const stale = `${readdirSync(ad).find((y) => y.endsWith(".json"))}.tmp`;
  assert.deepEqual(readdirSync(ad).filter((x) => x.endsWith(".tmp") && x !== stale), [], "no quedan temporales propios");
});
