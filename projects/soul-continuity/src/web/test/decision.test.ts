import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { decidirEnvioWs, decidirHttp, operacionDe, soloConsultas, type PeticionHttp } from "../cortafuegos/decision.ts";
import { validarReceta } from "../receta/validar.ts";
import type { Receta } from "../receta/tipos.ts";

const carga = (n: string): Receta => {
  const r = JSON.parse(readFileSync(join(import.meta.dirname, "..", "recetas", "sinteticas", `${n}.json`), "utf8"));
  r.origen = r.origen.replace("{puerto}", "8490");
  return validarReceta(r);
};
const correo = carga("correo"), tareas = carga("tareas");
const O = correo.origen;
const pet = (x: Partial<PeticionHttp>): PeticionHttp =>
  ({ url: `${O}/correo`, metodo: "GET", cabeceras: {}, cuerpo: null, navegacion: true, ...x });
const sin = { accion: null };
const post = (ruta: string, cab: Record<string, string>, cuerpo: unknown) =>
  pet({ url: `${O}${ruta}`, metodo: "POST", cabeceras: cab, cuerpo: JSON.stringify(cuerpo), navegacion: false });

test("GET en la lista pasa; fuera de la lista no", () => {
  assert.equal(decidirHttp(correo, sin, pet({})).permitir, true);
  const d = decidirHttp(correo, sin, pet({ url: `${O}/logout` }));
  assert.deepEqual([d.permitir, d.motivo], [false, "fuera_de_lista"]);
});

test("métodos distintos de GET/HEAD/POST se cortan aunque la URL case", () => {
  for (const m of ["PUT", "DELETE", "PATCH", "OPTIONS"]) {
    assert.equal(decidirHttp(correo, sin, pet({ metodo: m, url: `${O}/correo/api/servicio` })).motivo, "metodo");
  }
});

test("POST a una URL de la lista sin operaciones declaradas se corta", () => {
  assert.equal(decidirHttp(correo, sin, pet({ metodo: "POST", url: `${O}/correo` })).motivo, "metodo");
});

test("POST de lectura por cabecera pasa; escritura conocida se corta sin desactivar", () => {
  const ok = decidirHttp(correo, sin, post("/correo/api/servicio", { "x-accion": "BuscarElementos" }, {}));
  assert.deepEqual([ok.permitir, ok.op], [true, "BuscarElementos"]);
  const w = decidirHttp(correo, sin, post("/correo/api/servicio", { "x-accion": "MarcarLeido" }, { id: "M-1" }));
  assert.deepEqual([w.permitir, w.motivo, w.desactivar], [false, "escritura_conocida", undefined]);
});

test("operación desconocida o ausente: se corta y desactiva la receta", () => {
  const n = decidirHttp(correo, sin, post("/correo/api/servicio", { "x-accion": "BuscarElementosV2" }, {}));
  assert.deepEqual([n.permitir, n.motivo, n.desactivar], [false, "operacion_desconocida", true]);
  const a = decidirHttp(correo, sin, post("/correo/api/servicio", {}, {}));
  assert.deepEqual([a.permitir, a.desactivar], [false, true]);
  const dos = decidirHttp(correo, sin, post("/correo/api/servicio", { "x-accion": "BuscarElementos,MarcarLeido" }, {}));
  assert.equal(dos.permitir, false);
});

test("GraphQL: operationName de lectura con documento mutation se corta", () => {
  const ok = decidirHttp(correo, sin, post("/correo/graphql", {}, { operationName: "ListarChats", query: "query ListarChats { chats { id } }" }));
  assert.equal(ok.permitir, true);
  const mal = decidirHttp(correo, sin, post("/correo/graphql", {}, { operationName: "ListarChats", query: "mutation ListarChats { x }" }));
  assert.deepEqual([mal.permitir, mal.motivo, mal.desactivar], [false, "graphql_no_consulta", true]);
  const sinDoc = decidirHttp(correo, sin, post("/correo/graphql", {}, { operationName: "ListarChats" }));
  assert.equal(sinDoc.permitir, false);
  const lote = decidirHttp(correo, sin, pet({ url: `${O}/correo/graphql`, metodo: "POST", navegacion: false,
    cuerpo: JSON.stringify([{ operationName: "ListarChats", query: "query ListarChats { a }" }]) }));
  assert.equal(lote.permitir, false);
});

test("soloConsultas: cadenas y comentarios no engañan; vacío falla", () => {
  assert.equal(soloConsultas('query A { f(x: "mutation B { y }") }'), true);
  assert.equal(soloConsultas("# mutation\nquery A { f }"), true);
  assert.equal(soloConsultas("{ f }"), true);
  assert.equal(soloConsultas("query A { f } mutation B { g }"), false);
  assert.equal(soloConsultas("subscription S { f }"), false);
  assert.equal(soloConsultas(""), false);
  assert.equal(soloConsultas("query A { f "), false);
});

test("operacionDe: cuerpo no JSON u objeto raro = desconocida", () => {
  const o = correo.post_lectura[1];
  assert.equal(operacionDe(o, pet({ cuerpo: "no json" })).op, null);
  assert.equal(operacionDe(o, pet({ cuerpo: '{"operationName":7}' })).op, null);
});

test("renovación de sesión: solo la de la lista", () => {
  assert.equal(decidirHttp(correo, sin, pet({ metodo: "POST", url: `${O}/sesion/renovar`, navegacion: false })).motivo, "renovacion");
  assert.equal(decidirHttp(correo, sin, pet({ metodo: "POST", url: `${O}/sesion/renovar?x=1`, navegacion: false })).permitir, false);
});

test("login detecta sesión caducada", () => {
  const d = decidirHttp(tareas, sin, pet({ url: `${tareas.origen}/login?vuelta=%2Ftareas` }));
  assert.deepEqual([d.permitir, d.sesion], [false, true]);
});

test("durante una acción solo pasan las URLs ligadas a ella", () => {
  const accion = tareas.acciones[0];
  const fuera = decidirHttp(tareas, { accion }, pet({ url: `${tareas.origen}/tareas?vista=resumen` }));
  assert.deepEqual([fuera.permitir, fuera.motivo], [false, "accion_no_ligada"]);
  assert.equal(decidirHttp(tareas, sin, pet({ url: `${tareas.origen}/tareas?vista=resumen` })).permitir, true);
  assert.equal(decidirHttp(tareas, { accion }, pet({ url: `${tareas.origen}/tareas?pagina=2` })).permitir, true);
});

test("esquemas no http se cortan", () => {
  assert.equal(decidirHttp(tareas, sin, pet({ url: "file:///etc/passwd" })).motivo, "esquema");
  assert.equal(decidirHttp(tareas, sin, pet({ url: "javascript:alert(1)" })).motivo, "esquema");
});

test("WebSocket: solo el mensaje exacto de mantenimiento sale", () => {
  assert.equal(decidirEnvioWs(correo, '{"tipo":"ping"}'), true);
  assert.equal(decidirEnvioWs(correo, '{"tipo":"ping","x":1}'), false);
  assert.equal(decidirEnvioWs(correo, '{"tipo":"ack","id":"M-9"}'), false);
  assert.equal(decidirEnvioWs(tareas, '{"tipo":"ping"}'), false);
});

// --- Otro origen: subrecursos sí, navegación nunca (producto) ---
test("un patrón absoluto deja pasar subrecursos pero nunca navegar a otro origen", () => {
  const r = { ...tareas, urls: [...tareas.urls, "http://127.0.0.9:8490/estatico/*.js"] };
  const sub = decidirHttp(r, sin, pet({ url: "http://127.0.0.9:8490/estatico/a.js", navegacion: false }));
  assert.deepEqual([sub.permitir, sub.motivo], [true, "lista"]);
  const nav = decidirHttp(r, sin, pet({ url: "http://127.0.0.9:8490/estatico/a.js", navegacion: true }));
  assert.deepEqual([nav.permitir, nav.motivo], [false, "otro_origen"]);
  const mut = decidirHttp(r, sin, pet({ url: "http://127.0.0.9:8490/estatico/a.js", navegacion: true }), "absoluto_navegable");
  assert.equal(mut.permitir, true);
});

test("login federado: el salto al origen de SSO es sesión caducada; el mutante no lo ve", () => {
  const r = { ...tareas, sesion: { login: [...tareas.sesion.login, "http://127.0.0.9:8490"] } };
  const d = decidirHttp(r, sin, pet({ url: "http://127.0.0.9:8490/authorize?client_id=x&vuelta=y" }));
  assert.deepEqual([d.permitir, d.motivo, d.sesion], [false, "login", true]);
  const m = decidirHttp(r, sin, pet({ url: "http://127.0.0.9:8490/authorize?client_id=x" }), "sin_login_externo");
  assert.deepEqual([m.permitir, m.sesion], [false, undefined]);
});

test("POST de lectura a un origen absoluto de la lista se decide por su operación", () => {
  const api = "https://api.example/v1/buscar";
  const r = { ...correo, urls: [...correo.urls, api], post_lectura: [...correo.post_lectura,
    { url: api, operacion: { cabecera: "x-op" }, lectura: ["Buscar"], escritura_conocida: ["Marcar"] }] };
  const p = (op: string) => pet({ url: api, metodo: "POST", cabeceras: { "x-op": op }, navegacion: false });
  assert.equal(decidirHttp(r, sin, p("Buscar")).permitir, true);
  assert.deepEqual([decidirHttp(r, sin, p("Marcar")).permitir, decidirHttp(r, sin, p("Marcar")).motivo], [false, "escritura_conocida"]);
  assert.equal(decidirHttp(r, sin, p("Nueva")).desactivar, true);
});

test("un endpoint de operaciones solo admite POST: GET/HEAD a él se cortan aunque la URL esté en la lista", () => {
  for (const m of ["GET", "HEAD"]) {
    for (const ruta of ["/correo/api/servicio", "/correo/api/servicio?x-accion=MarcarLeido", "/correo/graphql"]) {
      const d = decidirHttp(correo, sin, pet({ metodo: m, url: `${O}${ruta}`, navegacion: false }));
      assert.deepEqual([d.permitir, d.motivo], [false, "metodo"], `${m} ${ruta}`);
    }
  }
  // Una URL de la lista sin operaciones declaradas sigue pasando por GET.
  assert.equal(decidirHttp(correo, sin, pet({ url: `${O}/correo/app.js`, navegacion: false })).permitir, true);
  // El mutante quita esta defensa.
  const m = decidirHttp(correo, sin, pet({ url: `${O}/correo/api/servicio?x-accion=MarcarLeido`, navegacion: false }), "post_lectura_por_get");
  assert.equal(m.permitir, true);
});

test("la operación de la consulta tiene que coincidir con la declarada: si no, se corta y desactiva", () => {
  const ok = decidirHttp(correo, sin, post("/correo/api/servicio?x-accion=BuscarElementos", { "x-accion": "BuscarElementos" }, {}));
  assert.deepEqual([ok.permitir, ok.motivo], [true, "post_lectura"]);
  const d = decidirHttp(correo, sin, post("/correo/api/servicio?x-accion=MarcarLeido", { "x-accion": "BuscarElementos" }, {}));
  assert.deepEqual([d.permitir, d.motivo, d.desactivar], [false, "operacion_url_distinta", true]);
  // Otra grafía de la clave no casa con el patrón: se corta antes.
  assert.equal(decidirHttp(correo, sin, post("/correo/api/servicio?X-Accion=MarcarLeido", { "x-accion": "BuscarElementos" }, {})).permitir, false);
  // También con la operación en el cuerpo JSON (GraphQL `operationName`).
  const g = decidirHttp(validarReceta({ ...correo, urls: [...correo.urls, "/correo/graphql?operationName=*"],
    post_lectura: [...correo.post_lectura, { ...correo.post_lectura[2], url: "/correo/graphql?operationName=*" }] }), sin,
    post("/correo/graphql?operationName=MarcarChatVisto", {}, { operationName: "ListarChats", query: "query ListarChats { chats { id } }" }));
  assert.deepEqual([g.permitir, g.motivo], [false, "operacion_url_distinta"]);
  const m = decidirHttp(correo, sin, post("/correo/api/servicio?x-accion=MarcarLeido", { "x-accion": "BuscarElementos" }, {}), "operacion_url_sin_cotejar");
  assert.equal(m.permitir, true);
});
