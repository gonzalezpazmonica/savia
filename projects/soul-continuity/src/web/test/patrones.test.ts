import { test } from "node:test";
import assert from "node:assert/strict";
import { casa, compilarPatron } from "../receta/patrones.ts";

const O = "http://127.0.0.2:8490";

test("coincidencia exacta de ruta y consulta", () => {
  assert.equal(casa(`${O}/tareas?vista=resumen`, O, ["/tareas?vista=resumen"]), true);
  assert.equal(casa(`${O}/tareas?vista=otra`, O, ["/tareas?vista=resumen"]), false);
});

test("el comodín no cruza / ? & = #", () => {
  const p = ["/tareas?pagina=*"];
  assert.equal(casa(`${O}/tareas?pagina=2`, O, p), true);
  assert.equal(casa(`${O}/tareas?pagina=1&_form=1`, O, p), false);
  assert.equal(casa(`${O}/tareas?pagina=1/x`, O, p), false);
  assert.equal(casa(`${O}/tareas?pagina=`, O, p), false);
});

test("sin prefijos: /tareas no admite /tareas/T-1/cerrar", () => {
  assert.equal(casa(`${O}/tareas/T-1/cerrar`, O, ["/tareas"]), false);
  assert.equal(casa(`${O}/tareas`, O, ["/tareas"]), true);
});

test("origen exacto: esquema, host y puerto", () => {
  assert.equal(casa("http://127.0.0.2:8491/tareas", O, ["/tareas"]), false);
  assert.equal(casa("https://127.0.0.2:8490/tareas", O, ["/tareas"]), false);
  assert.equal(casa("http://127.0.0.3:8490/tareas", O, ["/tareas"]), false);
});

test("credenciales en la URL y rutas con .. se rechazan o normalizan", () => {
  assert.equal(casa("http://u:p@127.0.0.2:8490/tareas", O, ["/tareas"]), false);
  assert.equal(casa(`${O}/tareas/../approve`, O, ["/tareas/*"]), false);
  assert.equal(casa(`${O}/tareas/%2e%2e/approve`, O, ["/tareas/*"]), false);
  assert.equal(casa("no es una url", O, ["/tareas"]), false);
});

test("el fragmento no cuenta", () => {
  assert.equal(casa(`${O}/tareas#x`, O, ["/tareas"]), true);
});

test("patrones mal formados se rechazan", () => {
  assert.throws(() => compilarPatron("tareas"));
  assert.throws(() => compilarPatron("/a/**"));
  assert.throws(() => compilarPatron("/a#b"));
});

test("el modo prefijo (solo mutante) sí deja pasar lo que no debe", () => {
  assert.equal(casa(`${O}/tareas?pagina=1&_form=1`, O, ["/tareas?pagina=*"], true), true);
});

// --- Patrones absolutos y login federado (producto) ---
import { casaLogin } from "../receta/patrones.ts";

test("patrón absoluto: casa solo su origen exacto, con la misma regla de comodín", () => {
  const p = ["https://cdn.example/app/*.js"];
  assert.equal(casa("https://cdn.example/app/main.js", O, p), true);
  assert.equal(casa("https://cdn.example/app/a/b.js", O, p), false);
  assert.equal(casa("https://cdn.example.evil/app/main.js", O, p), false);
  assert.equal(casa("http://cdn.example/app/main.js", O, p), false);
  assert.equal(casa("https://user:x@cdn.example/app/main.js", O, p), false);
  // Un absoluto no abre el origen de la receta ni al revés.
  assert.equal(casa(`${O}/app/main.js`, O, p), false);
});

test("patrón absoluto sin comodín en el host ni credenciales", () => {
  assert.throws(() => compilarPatron("https://*.example/x"));
  assert.throws(() => compilarPatron("https://u@cdn.example/x"));
  assert.throws(() => compilarPatron("https://cdn.example"));
});

test("login: relativo estricto u origen entero de SSO; el mutante ignora el SSO", () => {
  const login = ["/login", "https://sso.example"];
  assert.equal(casaLogin(`${O}/login`, O, login), true);
  assert.equal(casaLogin("https://sso.example/a/b?c=1&d=2", O, login), true);
  assert.equal(casaLogin("https://sso.example.evil/a", O, login), false);
  assert.equal(casaLogin(`${O}/login/otra`, O, login), false);
  assert.equal(casaLogin("https://sso.example/a", O, login, false, true), false);
});
