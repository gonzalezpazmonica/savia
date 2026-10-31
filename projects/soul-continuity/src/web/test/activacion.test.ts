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

test("una receta estable se ejecuta sin recibo", () => {
  assert.deepEqual(comprobarActivacion(R("tareas"), undefined), { activa: true, aviso: null });
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
