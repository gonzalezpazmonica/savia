import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cargarReceta, RecetaInvalida, validarReceta } from "../receta/validar.ts";
import type { Receta } from "../receta/tipos.ts";

const R = (n: string) => join(import.meta.dirname, "..", "recetas", "sinteticas", `${n}.json`);
const base = (n = "correo"): Receta => {
  const r = JSON.parse(readFileSync(R(n), "utf8"));
  r.origen = r.origen.replace("{puerto}", "8490");
  return r;
};
const rechaza = (cambio: (r: Receta) => void, patron: RegExp, n = "correo") => {
  const r = base(n);
  cambio(r);
  assert.throws(() => validarReceta(r), (e: Error) => e instanceof RecetaInvalida && patron.test(e.message));
};

test("las cuatro recetas sintéticas son válidas", () => {
  for (const n of ["tareas", "aprobaciones", "noticias", "correo"]) assert.ok(cargarReceta(R(n), { puerto: 8490 }));
});

test("{puerto} sin puerto se rechaza", () => {
  assert.throws(() => cargarReceta(R("tareas")), RecetaInvalida);
});

test("enlaces de acción nunca entran en la lista", () => {
  for (const p of ["/approve?id=*", "/logout", "/tareas/*/cerrar", "/noticias/*/confirmar", "/unsubscribe", "/api/markRead"]) {
    rechaza((r) => { r.urls.push(p); }, /enlace de acción/, "tareas");
  }
});

test("una operación no puede ser lectura y escritura a la vez", () => {
  rechaza((r) => { r.post_lectura[0].escritura_conocida.push("BuscarElementos"); }, /lectura y escritura/);
});

test("post_lectura sin operaciones de lectura o sin fuente se rechaza", () => {
  rechaza((r) => { r.post_lectura[0].lectura = []; }, /vacía/);
  rechaza((r) => { (r.post_lectura[0] as { operacion: unknown }).operacion = {}; }, /dónde se declara/);
});

test("javascript debe declararse", () => {
  rechaza((r) => { delete (r as Partial<Receta>).javascript; }, /javascript/);
});

test("origen con ruta, comodín o credenciales se rechaza", () => {
  rechaza((r) => { r.origen = "http://127.0.0.5:8490/correo"; }, /origen/);
  rechaza((r) => { r.origen = "http://*.ejemplo.test"; }, /origen/);
  rechaza((r) => { r.origen = "http://u:p@127.0.0.5:8490"; }, /origen/);
  rechaza((r) => { r.origen = "file:///etc"; }, /origen/);
});

test("páginas, acciones y humo deben estar dentro de la lista", () => {
  rechaza((r) => { r.paginas = ["/otra"]; }, /no casa con urls/, "tareas");
  rechaza((r) => { r.acciones[0].urls = ["/tareas?otra=*"]; }, /no está en urls/, "tareas");
  rechaza((r) => { r.acciones[0].max_repeticiones = 0; }, /max_repeticiones/, "tareas");
  rechaza((r) => { r.humo.pagina = "/tareas?pagina=2"; }, /humo/, "tareas");
  rechaza((r) => { r.humo.campos_obligatorios = ["inventado"]; }, /humo: campo desconocido/, "tareas");
});

test("la página de login no puede estar en la lista", () => {
  rechaza((r) => { r.urls.push("/login"); r.sesion.login = ["/login"]; }, /sesion.login/, "tareas");
});

test("condiciones con campos u operadores desconocidos se rechazan", () => {
  rechaza((r) => { r.preguntas.q1 = { campo: "nada", op: "igual", valor: "x" }; }, /campo desconocido/, "tareas");
  rechaza((r) => { r.preguntas.q1 = { campo: "estado", op: "parecido" as "igual", valor: "x" }; }, /op desconocida/, "tareas");
  rechaza((r) => { r.preguntas = {}; }, /sin preguntas/, "tareas");
});

test("formato desconocido se rechaza", () => {
  const d = mkdtempSync(join(tmpdir(), "receta-"));
  const r = base("tareas");
  (r as { formato: string }).formato = "otro/9";
  writeFileSync(join(d, "x.json"), JSON.stringify(r));
  assert.throws(() => cargarReceta(join(d, "x.json")), /formato/);
});

// --- Producto: estado, plantillas, absolutos y login SSO ---
import { completarPlantilla } from "../receta/validar.ts";

test("estado obligatorio: experimental o estable", () => {
  rechaza((r) => { delete (r as Partial<Receta>).estado; }, /estado/);
  rechaza((r) => { (r as { estado: string }).estado = "activa"; }, /estado/);
});

test("plantilla sin completar en origen o URLs se rechaza; {yo} de las preguntas se respeta", () => {
  rechaza((r) => { r.origen = "https://{inquilino}.example"; }, /plantilla sin completar/);
  rechaza((r) => { r.urls.push("/x/{region}"); }, /plantilla sin completar/);
  const t = completarPlantilla('{"o":"https://{inquilino}.example","q":"{yo}"}', { inquilino: "contoso" });
  assert.equal(t, '{"o":"https://contoso.example","q":"{yo}"}');
  assert.throws(() => completarPlantilla("{x}", { x: "a/b" }), RecetaInvalida);
  assert.throws(() => completarPlantilla("{x}", { x: "a*" }), RecetaInvalida);
  assert.throws(() => completarPlantilla("{yo}", { yo: "otra" }), RecetaInvalida);
});

test("absolutos: http(s) en urls, ws(s) en websocket; nada de acciones ni páginas absolutas", () => {
  assert.ok(validarReceta(Object.assign(base(), { urls: [...base().urls, "https://cdn.example/a/*.js"] })));
  rechaza((r) => { r.urls.push("wss://cdn.example/a"); }, /esquema/);
  rechaza((r) => { r.websocket.urls.push("https://cdn.example/a"); }, /esquema/);
  rechaza((r) => { r.urls.push("https://cdn.example/approve?id=*"); }, /acción/);
  rechaza((r) => { r.urls.push("https://cdn.example/a"); r.paginas.push("https://cdn.example/a"); }, /relativo/);
});

test("login SSO: origen entero, nunca el de la receta ni con URLs en la lista", () => {
  assert.ok(validarReceta(Object.assign(base(), { sesion: { login: ["/login", "https://sso.example"] } })));
  rechaza((r) => { r.sesion.login.push(r.origen); }, /origen de la receta/);
  rechaza((r) => { r.sesion.login.push("https://sso.example/authorize"); }, /origen entero/);
  rechaza((r) => { r.urls.push("https://sso.example/a.js"); r.sesion.login.push("https://sso.example"); }, /URLs en la lista/);
});

test("websocket.mantenimiento no admite el marcador de mensaje binario", () => {
  rechaza((r) => { r.websocket.mantenimiento = ["<binario>"]; }, /binario/);
});
