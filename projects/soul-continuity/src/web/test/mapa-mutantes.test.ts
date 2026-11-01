// Un mutante solo muere por una comprobación de SU defensa (revisión #1443, P2-4).
import { test } from "node:test";
import assert from "node:assert/strict";
import { MUTANTES } from "../cortafuegos/decision.ts";
import { clasificarMutante, MAPA } from "../bench/mapa-mutantes.ts";

test("todo mutante tiene su mapa de comprobaciones", () => {
  assert.deepEqual(Object.keys(MAPA).sort(), [...MUTANTES].sort());
});

test("un fallo ajeno a la defensa no mata al mutante", () => {
  const r = clasificarMutante("sin_descargas", ["base:tareas:estado", "ejecucion:tareas:sin_excepcion"]);
  assert.equal(r.estado, "VIVO");
  assert.equal(r.ajenos, 2);
});

test("un fallo de su defensa sí lo mata, y se separa de los ajenos", () => {
  const r = clasificarMutante("sin_descargas", ["base:tareas:estado", "descarga_disfrazada:tareas:descargas"]);
  assert.deepEqual([r.estado, r.muertoPor, r.ajenos], ["MUERTO", ["descarga_disfrazada:tareas:descargas"], 1]);
  assert.equal(clasificarMutante("vigilancia_con_js", ["vigilancia:noticias:sin_javascript"]).estado, "MUERTO");
  assert.equal(clasificarMutante("ws_sin_lista", ["contenido_hostil:noticias:q2:precision>=0.9"]).estado, "VIVO");
});

test("fail-closed: sin informe o mutante sin mapa no cuenta como muerto", () => {
  assert.equal(clasificarMutante("sin_descargas", null).estado, "SIN_INFORME");
  assert.equal(clasificarMutante("inventado", ["descarga_disfrazada:tareas:descargas"]).estado, "SIN_MAPA");
});

test("dos mutantes no se matan con la misma comprobación (revisión #1443, P2-5 de corrección)", () => {
  const pares: [string, string, string][] = [
    ["post_lectura_por_get", "operacion_url_sin_cotejar", "operacion_en_url:correo:get_cortado"],
    ["operacion_url_sin_cotejar", "post_lectura_por_get", "operacion_en_url:correo:post_cortado"],
    ["ws_sin_lista", "absoluto_navegable", "contenido_hostil:noticias:ws_cortado"],
    ["absoluto_navegable", "ws_sin_lista", "contenido_hostil:noticias:navegacion_externa_cortada"],
  ];
  for (const [suyo, otro, f] of pares) {
    assert.equal(clasificarMutante(suyo, [f]).estado, "MUERTO", `${suyo} ← ${f}`);
    assert.equal(clasificarMutante(otro, [f]).estado, "VIVO", `${otro} ← ${f}`);
  }
  // Ni un fallo genérico del escenario basta.
  assert.equal(clasificarMutante("ws_sin_lista", ["contenido_hostil:noticias:peticiones_a_externo"]).estado, "VIVO");
});
