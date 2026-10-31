import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  appendJsonl, dataDir, operatorDir, operatorDirName, readJson, readJsonl, writeJson,
} from "../src/core/store.ts";

const tmp = () => mkdtempSync(join(tmpdir(), "soul-st-"));

test("dataDir: directorio de datos del usuario por sistema, sin rutas de administrador", () => {
  const home = "/h";
  assert.equal(dataDir({ platform: "linux", env: {}, home }), "/h/.local/share/savia/soul-continuity");
  assert.equal(dataDir({ platform: "linux", env: { XDG_DATA_HOME: "/x" }, home }), "/x/savia/soul-continuity");
  assert.equal(dataDir({ platform: "darwin", env: {}, home }), "/h/Library/Application Support/Savia/soul-continuity");
  assert.match(dataDir({ platform: "win32", env: { LOCALAPPDATA: "C:/U/AppData/Local" }, home }), /^C:\/U\/AppData\/Local.Savia.soul-continuity$/);
  assert.equal(dataDir({ platform: "linux", env: { SOUL_DATA_DIR: "/d" }, home }), "/d");
});

test("writeJson es atómico: no deja temporales y el fichero queda solo para el usuario", () => {
  const d = tmp();
  const p = join(d, "a.json");
  writeJson(p, { a: 1 });
  writeJson(p, { a: 2 });
  assert.deepEqual(readJson(p, null), { a: 2 });
  assert.deepEqual(readdirSync(d), ["a.json"]);
  if (process.platform !== "win32") assert.equal(statSync(p).mode & 0o077, 0);
});

test("readJson con fichero corrupto lanza: no se adivina estado", () => {
  const d = tmp();
  writeFileSync(join(d, "c.json"), "{");
  assert.throws(() => readJson(join(d, "c.json"), {}));
  assert.deepEqual(readJson(join(d, "no.json"), { x: 1 }), { x: 1 });
});

test("readJsonl descarta la línea cortada y conserva las demás", () => {
  const d = tmp();
  const p = join(d, "l.jsonl");
  appendJsonl(p, { n: 1 });
  writeFileSync(p, '{"n":1}\n{"n":', { flag: "w" });
  appendJsonl(p, { n: 3 });
  const rows = readJsonl(p);
  assert.equal(rows.filter((r) => r !== null).length, 1);
});

test("cada operador tiene su directorio, distinto y estable", () => {
  const d = tmp();
  assert.notEqual(operatorDirName("op-a"), operatorDirName("op-b"));
  assert.equal(operatorDir(d, "op-a"), operatorDir(d, "op-a"));
  assert.ok(!operatorDirName("op-a").includes("op-a"), "la referencia no aparece en claro en la ruta");
});
