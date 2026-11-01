import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const BIN = fileURLToPath(new URL("../bin/soul.mjs", import.meta.url));

function soul(args: string[], extra: Record<string, string> = {}) {
  const dir = mkdtempSync(join(tmpdir(), "soul-bin-"));
  // Entorno mínimo: sin señales de frontend de agente, sin red configurada, sin Space.
  const env: Record<string, string> = { PATH: process.env.PATH ?? "", HOME: dir, SOUL_DATA_DIR: join(dir, "data"), ...extra };
  if (process.platform === "win32") Object.assign(env, { SystemRoot: process.env.SystemRoot ?? "", LOCALAPPDATA: dir });
  const t0 = performance.now();
  const r = spawnSync(process.execPath, [BIN, ...args], { env, encoding: "utf8" });
  return { ...r, ms: performance.now() - t0 };
}

test("AC-1: `soul status` responde en frío, sin perfil ni red, en menos de 1 s", () => {
  soul(["status"]); // calienta la caché del sistema de ficheros, no la del proceso
  // Mejor de 3 procesos: un arranque en frío de Node en un CI cargado no es una regresión; 3 lentos seguidos sí.
  let r = soul(["status", "--json"]);
  for (let i = 1; i < 3 && r.ms >= 1000; i++) { const n = soul(["status", "--json"]); if (n.ms < r.ms) r = n; }
  assert.equal(r.status, 0, r.stderr);
  const j = JSON.parse(r.stdout);
  assert.equal(j.profile, null);
  assert.ok(r.ms < 1000, `status tardó ${Math.round(r.ms)} ms`);
});

test("sin perfil, una pregunta da la negativa clara con código 3", () => {
  const r = soul(["q1"]);
  assert.equal(r.status, 3);
  assert.match(r.stderr, /No sé quién eres/);
});

test("texto libre: no se interpreta, código 2", () => {
  const r = soul(["qué", "tengo"]);
  assert.equal(r.status, 2);
});

test("desde un frontend de agente, export se rechaza con código 4", () => {
  const r = soul(["export"], { CLAUDECODE: "1" });
  assert.equal(r.status, 4);
});
