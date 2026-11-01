// CLI de validación de grabaciones: códigos de salida 0/1/2 (revisión #1443, P2-3).
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const RAIZ = join(import.meta.dirname, "..");
const RECETA = join(RAIZ, "recetas", "sinteticas", "correo.json");
const O = "http://127.0.0.5:8490";
// Directorio de datos propio: la CLI nunca escribe en el del usuario durante los tests.
const DATOS = mkdtempSync(join(tmpdir(), "soul-cli-datos-"));
process.on("exit", () => rmSync(DATOS, { recursive: true, force: true }));
const cli = (...a: string[]) => spawnSync(process.execPath,
  ["--experimental-strip-types", "--no-warnings", join(RAIZ, "adaptador", "cli-grabacion.ts"), ...a],
  { encoding: "utf8", env: { ...process.env, SOUL_DATA_DIR: DATOS } });
const har = { log: { version: "1.2", entries: [
  { request: { method: "GET", url: `${O}/correo`, headers: [] }, response: { status: 200 }, _resourceType: "document" },
  { request: { method: "POST", url: `${O}/correo/api/servicio`, headers: [{ name: "x-accion", value: "BuscarElementos" }],
    postData: { text: "{}" } }, response: { status: 200 }, _resourceType: "fetch" },
] } };

test("una opción sin valor (seguida de otra opción) es uso incorrecto: código 2", () => {
  const r = cli("--receta", "--har", "x.har");
  assert.equal(r.status, 2, r.stderr);
  assert.match(r.stderr, /uso:/);
});

test("pasa pero no se puede guardar el recibo: código 1 con mensaje claro, sin traza", () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cli-"));
  try {
    const h = join(d, "g.har");
    writeFileSync(h, JSON.stringify(har));
    const ok = cli("--receta", RECETA, "--har", h, "--var", "puerto=8490");
    assert.equal(ok.status, 0, ok.stderr);
    const bloqueo = join(d, "fichero");
    writeFileSync(bloqueo, "no es un directorio");
    const r = cli("--receta", RECETA, "--har", h, "--var", "puerto=8490", "--emitir-recibo", "--validaciones", join(bloqueo, "sub"));
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, /no se pudo guardar el recibo/);
    assert.doesNotMatch(r.stderr, /\n\s+at /);
  } finally { rmSync(d, { recursive: true, force: true }); }
});

test("--validaciones sin valor tras --emitir-recibo: código 2 y no escribe nada", () => {
  const d = mkdtempSync(join(tmpdir(), "soul-cli-"));
  try {
    const h = join(d, "g.har");
    writeFileSync(h, JSON.stringify(har));
    const r = cli("--receta", RECETA, "--har", h, "--var", "puerto=8490", "--emitir-recibo", "--validaciones");
    assert.equal(r.status, 2, r.stderr);
    assert.match(r.stderr, /uso:/);
    assert.doesNotMatch(r.stderr, /recibo:/);
    assert.deepEqual(readdirSync(DATOS), [], "no cae al directorio por defecto");
  } finally { rmSync(d, { recursive: true, force: true }); }
});

test("--emitir-recibo con éxito: escribe el recibo y la misma receta queda activa en el adaptador (viaje CLI → adaptador)", async () => {
  const { comprobarActivacion, rutaRecibo } = await import("../adaptador/activacion.ts");
  const { cargarReceta } = await import("../receta/validar.ts");
  const d = mkdtempSync(join(tmpdir(), "soul-cli-"));
  try {
    const h = join(d, "g.har");
    writeFileSync(h, JSON.stringify(har));
    const val = join(d, "validaciones");
    const receta = cargarReceta(RECETA, { puerto: 8490 });
    assert.equal(comprobarActivacion(receta, val).activa, false, "sin recibo no está activa");
    const r = cli("--receta", RECETA, "--har", h, "--var", "puerto=8490", "--emitir-recibo", "--validaciones", val);
    assert.equal(r.status, 0, r.stderr);
    assert.ok(existsSync(rutaRecibo(val, receta.id)));
    assert.equal(comprobarActivacion(receta, val).activa, true);
    // Con otra variable la receta es otra: el recibo no vale.
    assert.equal(comprobarActivacion(cargarReceta(RECETA, { puerto: 8491 }), val).activa, false);
  } finally { rmSync(d, { recursive: true, force: true }); }
});
