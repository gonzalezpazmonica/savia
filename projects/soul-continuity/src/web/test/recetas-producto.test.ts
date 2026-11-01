// Recetas genéricas de producto: válidas, experimentales y desactivadas por defecto.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { comprobarActivacion } from "../adaptador/activacion.ts";
import { esAbsoluto, esOrigenLogin } from "../receta/patrones.ts";
import { cargarReceta, RecetaInvalida } from "../receta/validar.ts";

const DIR = join(import.meta.dirname, "..", "recetas", "producto");
const VARS = { inquilino: "contoso", region: "emea" };
const nombres = readdirSync(DIR).filter((n) => n.endsWith(".json")).sort();

test("hay recetas de Outlook (correo y calendario), Teams y SharePoint/OneDrive", () => {
  assert.deepEqual(nombres, ["outlook-web-calendario.json", "outlook-web-correo.json", "sharepoint-compartido.json", "teams-web-actividad.json"]);
});

for (const n of nombres) {
  test(`${n}: válida con variables, experimental, con humo, login SSO y lista de URLs cerrada`, () => {
    const r = cargarReceta(join(DIR, n), { variables: VARS });
    assert.equal(r.estado, "experimental");
    assert.ok((r.notas ?? []).some((x) => /SIN validar/.test(x)));
    assert.ok(r.sesion.login.some(esOrigenLogin), "login federado declarado");
    assert.ok(r.humo.minimo >= 1 && r.humo.campos_obligatorios.length > 0);
    assert.ok(r.paginas.every((p) => !esAbsoluto(p)));
    assert.equal(r.acciones.length, 0, "v1: vistas de lista sin clics");
    assert.equal(r.websocket.mantenimiento.length, 0);
  });

  test(`${n}: desactivada por defecto (sin recibo no se activa)`, () => {
    const a = comprobarActivacion(cargarReceta(join(DIR, n), { variables: VARS }), undefined);
    assert.equal(a.activa, false);
  });

  test(`${n}: sin datos de una organización real`, () => {
    const t = readFileSync(join(DIR, n), "utf8");
    assert.ok(!/contoso|@[a-z0-9-]+\.(com|es|net)/i.test(t));
  });
}

test("las plantillas con variables no cargan sin completarlas", () => {
  for (const n of ["sharepoint-compartido.json", "teams-web-actividad.json"]) {
    assert.throws(() => cargarReceta(join(DIR, n)), RecetaInvalida);
  }
});
