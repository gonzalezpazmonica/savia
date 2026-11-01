// Un mutante solo muere por una comprobación de SU defensa (revisión #1443, P2-4 y P1-1).
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { MUTANTES } from "../cortafuegos/decision.ts";
import { clasificarMutante, fallosVigentes, huellaCodigo, MAPA } from "../bench/mapa-mutantes.ts";

const RES = join(import.meta.dirname, "..", "resultados");
const leer = (f: string) => JSON.parse(readFileSync(join(RES, f), "utf8"));
/** Universo: los ids que la batería emite de verdad (informe sin mutante). */
const universo = (): string[] => leer("bateria-ninguno.json").comprobaciones.map((c: { id: string }) => c.id);

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

test("cada mutante tiene al menos una comprobación real y ningún id casa con dos mutantes (revisión #1443 P1-1)", () => {
  const ids = universo();
  assert.ok(ids.length >= 300, `${ids.length} ids`);
  const duenos = new Map<string, string[]>();
  for (const [m, re] of Object.entries(MAPA)) {
    const suyos = ids.filter((id) => re.test(id));
    assert.ok(suyos.length > 0, `${m}: su regex no casa con ninguna comprobación de la batería`);
    for (const id of suyos) duenos.set(id, [...(duenos.get(id) ?? []), m]);
  }
  const compartidos = [...duenos].filter(([, ms]) => ms.length > 1).map(([id, ms]) => `${id} ← ${ms.join(", ")}`);
  assert.deepEqual(compartidos, []);
});

test("los resultados versionados son de ESTE código y cada mutante muere por la suya (revisión #1443 P1-1 y P2-3)", () => {
  const h = huellaCodigo();
  const base = leer("bateria-ninguno.json");
  assert.equal(base.huella_codigo, h, "bateria-ninguno.json es de otro código: re-ejecuta la batería");
  assert.equal(base.fallidas, 0);
  const mut = leer("mutantes.json");
  assert.equal(mut.huella_codigo, h, "mutantes.json es de otro código: re-ejecuta bench/mutantes.ts");
  assert.deepEqual(mut.filas.map((f: { mutante: string }) => f.mutante).sort(), [...MUTANTES].sort());
  // Los informes por mutante no se versionan (.gitignore): se comprueba la fila resumida.
  for (const f of mut.filas as { mutante: keyof typeof MAPA; estado: string; muertoPor: string[] }[]) {
    assert.equal(f.estado, "MUERTO", f.mutante);
    assert.ok(f.muertoPor.length > 0 && f.muertoPor.every((id) => MAPA[f.mutante].test(id)), `${f.mutante}: ${f.muertoPor.join(", ")}`);
  }
});

test("fallosVigentes: un informe de otro código o sin huella no cuenta (revisión #1443 P2-3)", () => {
  const inf = { huella_codigo: "aaaa", comprobaciones: [{ id: "x", ok: false }, { id: "y", ok: true }] };
  assert.deepEqual(fallosVigentes(inf, "aaaa"), ["x"]);
  assert.equal(fallosVigentes(inf, "bbbb"), null);
  assert.equal(fallosVigentes({ comprobaciones: inf.comprobaciones }, "aaaa"), null);
  assert.equal(fallosVigentes(null, "aaaa"), null);
  assert.equal(clasificarMutante("sin_descargas", fallosVigentes(inf, "bbbb")).estado, "SIN_INFORME");
});

test("bench/mutantes.ts rechaza --paralelo no entero y mutantes desconocidos sin lanzar nada (revisión #1443 P2-3)", () => {
  const correr = (...a: string[]) => spawnSync(process.execPath,
    ["--experimental-strip-types", "--no-warnings", join(import.meta.dirname, "..", "bench", "mutantes.ts"), ...a], { encoding: "utf8" });
  for (const a of [["--paralelo", "x"], ["--paralelo", "0"], ["--paralelo", "1.5"], ["--solo", "inventado"]]) {
    const r = correr(...a);
    assert.equal(r.status, 2, a.join(" "));
    assert.match(r.stderr, /uso:/);
  }
});
