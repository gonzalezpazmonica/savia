// El ejecutor es fail-closed: una excepción a mitad de lectura no revienta ni
// devuelve datos a medias. Y el caso normal sigue devolviendo OK.
import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { ejecutarReceta } from "../adaptador/ejecutor.ts";
import { buscarNavegador } from "../cortafuegos/perfil.ts";
import { cargarReceta } from "../receta/validar.ts";
import { Banco } from "../banco/servidor.ts";

const receta = (b: Banco) => cargarReceta(join(import.meta.dirname, "..", "recetas", "sinteticas", "tareas.json"), { puerto: b.puerto });

test("error en la página → ERROR sin elementos, sin excepción", { timeout: 60_000 }, async () => {
  const b = await new Banco().arrancar();
  try {
    const r = receta(b);
    r.extraccion.elemento = "li.tarea:::no-es-css";
    const res = await ejecutarReceta({ receta: r, yo: "ana.prueba", ejecutable: buscarNavegador().ruta, cookies: [b.cookieSesion("tareas")] });
    assert.equal(res.estado, "ERROR");
    assert.equal(res.elementos.length, 0);
    assert.match(res.aviso ?? "", /no se devuelven datos/);
    assert.equal(b.mutaciones.length, 0);
  } finally { await b.parar(); }
});

test("receta sana → OK con elementos", { timeout: 60_000 }, async () => {
  const b = await new Banco().arrancar();
  try {
    const res = await ejecutarReceta({ receta: receta(b), yo: "ana.prueba", ejecutable: buscarNavegador().ruta, cookies: [b.cookieSesion("tareas")] });
    assert.equal(res.estado, "OK");
    assert.equal(res.elementos.length, 7);
  } finally { await b.parar(); }
});

test("perfil persistente del directorio de datos: se usa y NO se borra al terminar", { timeout: 60_000 }, async () => {
  const { existsSync, mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { prepararPerfilSoul, MARCA } = await import("../cortafuegos/perfil.ts");
  const datos = mkdtempSync(join(tmpdir(), "soul-datos-"));
  const b = await new Banco().arrancar();
  try {
    const perfil = prepararPerfilSoul(datos);
    const res = await ejecutarReceta({ receta: receta(b), yo: "ana.prueba", ejecutable: buscarNavegador().ruta, perfil,
      cookies: [b.cookieSesion("tareas")] });
    assert.equal(res.estado, "OK");
    assert.ok(existsSync(join(perfil, MARCA)), "el perfil persistente sigue ahí");
    assert.ok(existsSync(join(perfil, "hogar")), "HOME del navegador dentro del perfil");
    assert.equal(b.mutaciones.length, 0);
  } finally {
    await b.parar();
    rmSync(datos, { recursive: true, force: true });
  }
});
