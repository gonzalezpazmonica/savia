// El ejecutor es fail-closed: una excepción a mitad de lectura no revienta ni
// devuelve datos a medias. Y el caso normal sigue devolviendo OK.
import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { AlmacenRecetas, ejecutarReceta } from "../adaptador/ejecutor.ts";
import { buscarNavegador } from "../cortafuegos/perfil.ts";
import { cargarReceta } from "../receta/validar.ts";
import { Banco } from "../banco/servidor.ts";

const receta = (b: Banco) => cargarReceta(join(import.meta.dirname, "..", "recetas", "sinteticas", "tareas.json"), { puerto: b.puerto });

test("error en la página → ERROR sin elementos, sin excepción", { timeout: 60_000 }, async () => {
  const b = await new Banco().arrancar();
  try {
    const r = receta(b);
    r.extraccion.elemento = "li.tarea:::no-es-css";
    const res = await ejecutarReceta({ receta: r, yo: "ana.prueba", ejecutable: buscarNavegador().ruta, banco: true, cookies: [b.cookieSesion("tareas")] });
    assert.equal(res.estado, "ERROR");
    assert.equal(res.elementos.length, 0);
    assert.match(res.aviso ?? "", /no se devuelven datos/);
    assert.equal(b.mutaciones.length, 0);
  } finally { await b.parar(); }
});

test("receta sana → OK con elementos", { timeout: 60_000 }, async () => {
  const b = await new Banco().arrancar();
  try {
    const res = await ejecutarReceta({ receta: receta(b), yo: "ana.prueba", ejecutable: buscarNavegador().ruta, banco: true, cookies: [b.cookieSesion("tareas")] });
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
    const res = await ejecutarReceta({ receta: receta(b), yo: "ana.prueba", ejecutable: buscarNavegador().ruta, banco: true, perfil,
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

test("sitio inalcanzable → ERROR transitorio: la receta NO se desactiva ni queda apagada", { timeout: 60_000 }, async () => {
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const dir = mkdtempSync(join(tmpdir(), "soul-estado-"));
  const b = await new Banco().arrancar();
  const r = receta(b);
  await b.parar(); // el puerto queda cerrado: conexión rechazada
  try {
    const almacen = new AlmacenRecetas(join(dir, "recetas-estado.json"));
    const res = await ejecutarReceta({ receta: r, yo: "ana.prueba", ejecutable: buscarNavegador().ruta, banco: true, almacen });
    assert.equal(res.estado, "ERROR", `${res.estado} ${res.aviso}`);
    assert.match(res.aviso ?? "", /no se pudo cargar/i);
    assert.equal(almacen.aviso(r.id), null, "un fallo de red no apaga la receta");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("AlmacenRecetas: desactivar persiste con permisos 0600, reactivar la devuelve y un fichero corrupto deja todo desactivado", async () => {
  const { mkdtempSync, rmSync, statSync, writeFileSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const dir = mkdtempSync(join(tmpdir(), "soul-estado-"));
  try {
    const ruta = join(dir, "sub", "recetas-estado.json");
    const a = new AlmacenRecetas(ruta);
    a.desactivar("r1", "dejó de ser fiable");
    assert.equal(new AlmacenRecetas(ruta).aviso("r1"), "dejó de ser fiable");
    assert.equal(statSync(ruta).mode & 0o777, 0o600);
    assert.equal(a.reactivar("r1"), true);
    assert.equal(a.aviso("r1"), null);
    assert.equal(a.reactivar("r1"), false);
    writeFileSync(ruta, "{no json");
    // Fail-closed: un estado ilegible no reactiva en silencio lo que estaba apagado.
    assert.match(a.aviso("otra") ?? "", /ilegible/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
