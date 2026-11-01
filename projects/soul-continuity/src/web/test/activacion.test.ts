// Puerta de recetas experimentales: sin recibo válido no se ejecutan.
import { strict as assert } from "node:assert";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { comprobarActivacion, guardarRecibo, rutaRecibo } from "../adaptador/activacion.ts";
import { cargarReceta } from "../receta/validar.ts";

const R = (n: string) => cargarReceta(join(import.meta.dirname, "..", "recetas", "sinteticas", `${n}.json`), { puerto: 8490 });
const resumen = { peticiones: 3, permitidas: 3, operaciones_lectura: 1 };

test("una receta estable del banco se ejecuta sin recibo", () => {
  assert.deepEqual(comprobarActivacion(R("tareas"), undefined, true), { activa: true, aviso: null });
});

test("fuera del banco, una estable de origen local también necesita recibo (revisión #1443 P2-3)", () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-val-"));
  try {
    for (const d of [undefined, dir]) {
      const a = comprobarActivacion(R("tareas"), d);
      assert.equal(a.activa, false);
      assert.match(a.aviso ?? "", /validar-grabacion/);
    }
    guardarRecibo(dir, R("tareas"), resumen);
    assert.equal(comprobarActivacion(R("tareas"), dir).activa, true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("experimental sin directorio ni recibo: no se activa y lo dice", () => {
  const r = { ...R("tareas"), estado: "experimental" as const };
  const dir = mkdtempSync(join(tmpdir(), "soul-val-"));
  try {
    for (const d of [undefined, dir]) {
      const a = comprobarActivacion(r, d);
      assert.equal(a.activa, false);
      assert.match(a.aviso ?? "", /experimental/);
      assert.match(a.aviso ?? "", /validar-grabacion/);
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("experimental con recibo de esa receta: se activa; si la receta cambia, deja de valer", () => {
  const r = { ...R("tareas"), estado: "experimental" as const };
  const dir = mkdtempSync(join(tmpdir(), "soul-val-"));
  try {
    guardarRecibo(dir, r, resumen);
    assert.equal(comprobarActivacion(r, dir).activa, true);
    const cambiada = { ...r, urls: [...r.urls, "/tareas?vista=todo"] };
    const a = comprobarActivacion(cambiada, dir);
    assert.equal(a.activa, false);
    assert.match(a.aviso ?? "", /cambió/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("recibo ilegible o de otra receta o sin PASA: fail-closed", () => {
  const r = { ...R("tareas"), estado: "experimental" as const };
  const dir = mkdtempSync(join(tmpdir(), "soul-val-"));
  try {
    writeFileSync(rutaRecibo(dir, r.id), "{no es json");
    assert.equal(comprobarActivacion(r, dir).activa, false);
    guardarRecibo(dir, { ...r, id: "otra" }, resumen);
    writeFileSync(rutaRecibo(dir, r.id), JSON.stringify({ formato: "soul-recibo-web/1", receta: "otra", resultado: "PASA" }));
    assert.equal(comprobarActivacion(r, dir).activa, false);
    guardarRecibo(dir, r, resumen);
    const bueno = JSON.parse(readFileSync(rutaRecibo(dir, r.id), "utf8"));
    writeFileSync(rutaRecibo(dir, r.id), JSON.stringify({ ...bueno, resultado: "FALLA" }));
    assert.equal(comprobarActivacion(r, dir).activa, false);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("estable sin recibo solo en un origen local: con origen remoto declararse estable no salta la puerta", () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-val-"));
  try {
    for (const origen of ["http://localhost:8490", "http://127.0.0.5:8490", "http://[::1]:8490"]) {
      assert.equal(comprobarActivacion({ ...R("tareas"), origen }, undefined, true).activa, true, origen);
    }
    const remota = { ...R("tareas"), origen: "https://intranet.example" };
    for (const d of [undefined, dir]) {
      const a = comprobarActivacion(remota, d, true);
      assert.equal(a.activa, false);
      assert.match(a.aviso ?? "", /estable/);
    }
    guardarRecibo(dir, remota, resumen);
    assert.equal(comprobarActivacion(remota, dir).activa, true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("un id que no es [a-z0-9-] no se convierte en ruta de recibo", () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-val-"));
  try {
    assert.throws(() => rutaRecibo(dir, "../otra"), /id/);
    const r = { ...R("tareas"), id: "../otra", estado: "experimental" as const };
    assert.equal(comprobarActivacion(r, dir).activa, false);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("la huella no depende del orden de claves; sí del contenido (revisión #1443 P2-4)", async () => {
  const { huellaReceta } = await import("../adaptador/activacion.ts");
  const r = R("correo");
  const invertir = (x: unknown): unknown => Array.isArray(x) ? x.map(invertir)
    : x && typeof x === "object" ? Object.fromEntries(Object.entries(x).reverse().map(([k, v]) => [k, invertir(v)])) : x;
  const otra = invertir(r) as typeof r;
  assert.notEqual(JSON.stringify(otra), JSON.stringify(r));
  assert.equal(huellaReceta(otra), huellaReceta(r));
  assert.notEqual(huellaReceta({ ...r, urls: [...r.urls, "/otra"] }), huellaReceta(r));
  // Viaje CLI → adaptador: el recibo escrito para una receta vale para la misma con otro orden.
  const d = mkdtempSync(join(tmpdir(), "soul-act-"));
  try {
    const exp = { ...otra, estado: "experimental" as const };
    guardarRecibo(d, { ...r, estado: "experimental" }, resumen);
    assert.equal(comprobarActivacion(exp, d).activa, true);
  } finally { rmSync(d, { recursive: true, force: true }); }
});
