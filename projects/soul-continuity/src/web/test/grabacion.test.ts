// Validación de una receta contra una grabación (HAR) del tráfico real del operador.
import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { enmascarar, validarGrabacion } from "../adaptador/grabacion.ts";
import { cargarReceta } from "../receta/validar.ts";
import type { Receta } from "../receta/tipos.ts";

const correo = (): Receta => cargarReceta(join(import.meta.dirname, "..", "recetas", "sinteticas", "correo.json"), { puerto: 8490 });
const O = "http://127.0.0.5:8490";
type E = { request: { method: string; url: string; headers: { name: string; value: string }[]; postData?: { text: string } };
  response: { status: number }; _resourceType: string };
const ent = (method: string, ruta: string, tipo: string, cab: Record<string, string> = {}, cuerpo?: unknown, status = 200): E => ({
  request: { method, url: ruta.startsWith("http") ? ruta : O + ruta, headers: Object.entries(cab).map(([name, value]) => ({ name, value })),
    ...(cuerpo === undefined ? {} : { postData: { text: JSON.stringify(cuerpo) } }) },
  response: { status }, _resourceType: tipo,
});
const har = (...e: E[]) => ({ log: { version: "1.2", entries: e } });
const buena = () => [
  ent("GET", "/correo", "document"),
  ent("GET", "/correo/app.js", "script"),
  ent("POST", "/correo/api/servicio", "fetch", { "x-accion": "BuscarElementos" }, { carpeta: "entrada" }),
  ent("POST", "/correo/graphql", "fetch", {}, { operationName: "ListarChats", query: "query ListarChats { chats { id } }" }),
  ent("POST", "/correo/api/servicio", "fetch", { "x-accion": "MarcarLeido" }, { id: "M-1" }),
  ent("POST", "/sesion/renovar", "fetch"),
];

test("grabación limpia: pasa, con las operaciones clasificadas", () => {
  const i = validarGrabacion(correo(), har(...buena()));
  assert.equal(i.pasa, true, i.fallos.join("; "));
  assert.equal(i.peticiones, 6);
  const ops = Object.fromEntries(i.operaciones.map((o) => [o.op, o.clase]));
  assert.deepEqual(ops, { BuscarElementos: "lectura", ListarChats: "lectura", MarcarLeido: "escritura_conocida" });
  assert.ok(i.avisos.some((a) => a.includes("ObtenerCarpetas")), "lectura declarada que no aparece en la grabación");
});

test("operación desconocida: no pasa y pide clasificarla", () => {
  const i = validarGrabacion(correo(), har(...buena(), ent("POST", "/correo/api/servicio", "fetch", { "x-accion": "MoverElemento" }, {})));
  assert.equal(i.pasa, false);
  assert.ok(i.fallos.some((f) => f.includes("MoverElemento")));
});

test("POST a URL de lectura sin operación declarada: no se distingue lectura de escritura", () => {
  const i = validarGrabacion(correo(), har(...buena(), ent("POST", "/correo/api/servicio", "fetch", {}, {})));
  assert.equal(i.pasa, false);
  assert.ok(i.fallos.some((f) => /no se distingue/.test(f)));
});

test("GraphQL con nombre de lectura y documento mutation: no pasa", () => {
  const i = validarGrabacion(correo(), har(...buena(),
    ent("POST", "/correo/graphql", "fetch", {}, { operationName: "ListarChats", query: "mutation ListarChats { x }" })));
  assert.equal(i.pasa, false);
  assert.ok(i.fallos.some((f) => /mutation|consulta/.test(f)));
});

test("una lectura con nombre de escritura no pasa aunque la receta la declare", () => {
  const r = correo();
  r.post_lectura[0].lectura.push("UpdateItem");
  const i = validarGrabacion(r, har(...buena(), ent("POST", "/correo/api/servicio", "fetch", { "x-accion": "UpdateItem" }, {})));
  assert.equal(i.pasa, false);
  assert.ok(i.fallos.some((f) => f.includes("UpdateItem") && /escritura/.test(f)));
});

test("la grabación tiene que cubrir las páginas de la receta", () => {
  const i = validarGrabacion(correo(), har(...buena().slice(1)));
  assert.equal(i.pasa, false);
  assert.ok(i.fallos.some((f) => f.includes("/correo")));
  const j = validarGrabacion(correo(), har(ent("GET", "/correo", "document", {}, undefined, 302), ...buena().slice(1)));
  assert.equal(j.pasa, false, "una página que no respondió 200 no está cubierta");
});

test("HAR mal formado o vacío: no pasa", () => {
  for (const h of [null, {}, { log: {} }, { log: { entries: [] } }, "texto"]) assert.equal(validarGrabacion(correo(), h).pasa, false);
});

test("el informe nunca lleva valores de consulta, cuerpos ni identificadores largos", () => {
  const raro = ent("GET", `/correo/item/AAMkAGI2THVSAAA1234567890abcdef?usuario=secreto@empresa.example&x=1`, "fetch");
  const post = ent("POST", "/correo/api/servicio", "fetch", { "x-accion": "BuscarElementos" }, { texto: "cuerpo-secreto" });
  const i = JSON.stringify(validarGrabacion(correo(), har(...buena(), raro, post)));
  for (const s of ["secreto@empresa", "cuerpo-secreto", "AAMkAGI2THVSAAA1234567890abcdef"]) assert.ok(!i.includes(s), s);
  assert.equal(enmascarar(`${O}/a/AAMkAGI2THVSAAA1234567890abcdef?u=x@y&k=2`), `${O}/a/…?u=…&k=…`);
});
