// El adaptador web cumple el contrato compartido: claves `web:*`, estados de
// adaptador y fail-closed. El navegador se sustituye por dobles del ejecutor y
// de la vigilancia; el cortafuegos se prueba en la batería.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { guardarRecibo } from "../adaptador/activacion.ts";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateAdapterResult, type AdapterContext } from "../../contract/adapter.ts";
import { crearAdaptadorWeb, type Dependencias } from "../adaptador/contrato.ts";
import type { Resultado } from "../adaptador/ejecutor.ts";
import { AlmacenHuellas, type OpcionesVigilancia, type ResultadoVigilancia } from "../adaptador/vigilancia.ts";
import { cargarReceta } from "../receta/validar.ts";

const receta = () => cargarReceta(join(import.meta.dirname, "..", "recetas", "sinteticas", "tareas.json"), { puerto: 1 });
const experimental = () => cargarReceta(join(import.meta.dirname, "..", "recetas", "producto", "teams-web-actividad.json"), { variables: VARS });

const VARS = { inquilino: "contoso", region: "emea" };
const NOW ="2026-10-20T08:00:00Z";
function ctx(params: Record<string, unknown>, route: AdapterContext["route"] = "web"): AdapterContext {
  return {
    operator: { ref: "op-1", identities: { emails: ["ana.prueba"] } },
    now: NOW, sensitivity: "N4", route, params,
    transport: { request: async () => { throw new Error("el adaptador web no usa el transporte"); } },
    credentials: { acquire: async () => { throw new Error("el adaptador web no pide credenciales"); } },
  };
}
const base = (extra: Record<string, unknown> = {}) =>
  ({ ejecutable: "/x/chrome", perfil: "/x/perfil", recetas: [receta()], desactivadas: "/x/desactivadas.json", ...extra });

function resultado(estado: Resultado["estado"], over: Partial<Resultado> = {}): Resultado {
  return { receta: "tareas", estado, aviso: estado === "OK" ? null : `aviso ${estado}`, elementos: [],
    preguntas: { q1: [], q2: [], q4: [] }, alertas: [], registro: [], ventanasAccion: [], descargas: 0, canal: null, ...over };
}
const el = (id: string, campos: Record<string, string>) => ({ id, fuente: "tareas", url: `http://127.0.0.1:1/tareas#${id}`, observado_en: NOW, campos });
const vig = (estado: ResultadoVigilancia["estado"]): ResultadoVigilancia =>
  ({ id: "p1", estado, aviso: estado === "CAMBIADA" ? "cambió" : estado === "REDIRIGIDA" ? "login" : null, enlace: "", alertas: [], registro: [], ventanasAccion: [], descargas: 0 });

function deps(ejec: Resultado | Error, v: ResultadoVigilancia = vig("SIN_CAMBIOS")): Dependencias & { llamadas: number } {
  const d = {
    llamadas: 0,
    banco: true,
    ejecutar: async () => { d.llamadas++; if (ejec instanceof Error) throw ejec; return ejec; },
    vigilar: async () => v,
  };
  return d;
}

test("OK → afirmaciones web válidas: Q1/Q2 son task_assigned, solo Q4 es dated_commitment", async () => {
  const res = resultado("OK", {
    elementos: [el("t1", { titulo: "Revisar informe", vence: "2026-10-22" }), el("t2", { titulo: "Plazo", vence: "2026-10-25" }), el("t3", { titulo: "Ajena" })],
    preguntas: { q1: ["t1"], q2: ["t1"], q4: ["t2"] },
  });
  const r = await crearAdaptadorWeb(deps(res)).read(ctx(base()));
  assert.deepEqual(validateAdapterResult(r, "web"), []);
  assert.equal(r.status, "ok");
  if (r.status !== "ok") return;
  const keys = r.claims.map((c) => c.key).sort();
  assert.deepEqual(keys, ["web:dated_commitment:tareas-sintetico~t2", "web:task_assigned:tareas-sintetico~t1"]);
  const t1 = r.claims.find((c) => c.key.endsWith("t1"))!;
  assert.equal(t1.awaiting_operator, true);
  assert.equal(t1.due_at, "2026-10-22T00:00:00Z");
  assert.equal(t1.title, "Revisar informe");
  assert.equal(t1.untrusted_text, true);
  assert.equal(t1.attrs.sender_auth, "unknown");
  assert.equal(r.claims.find((c) => c.key.endsWith("t2"))!.awaiting_operator, false);
});

test("Q1 sin Q2 → task_assigned que no espera al operador", async () => {
  const res = resultado("OK", { elementos: [el("t1", { titulo: "x" })], preguntas: { q1: ["t1"], q2: [], q4: [] } });
  const r = await crearAdaptadorWeb(deps(res)).read(ctx(base()));
  assert.equal(r.status, "ok");
  if (r.status === "ok") assert.equal(r.claims[0].awaiting_operator, false);
});

test("identificadores con ':', espacios o '~' se codifican y la clave sigue siendo válida", async () => {
  const res = resultado("OK", { elementos: [el("a:b c~d", { titulo: "x" })], preguntas: { q1: ["a:b c~d"], q2: [], q4: [] } });
  const r = await crearAdaptadorWeb(deps(res)).read(ctx(base()));
  assert.deepEqual(validateAdapterResult(r, "web"), []);
  if (r.status === "ok") assert.equal(r.claims[0].key, "web:task_assigned:tareas-sintetico~a%3Ab%20c%7Ed");
});

test("vencimiento que no es fecha → due_at nulo", async () => {
  const res = resultado("OK", { elementos: [el("t1", { titulo: "x", vence: "mañana" })], preguntas: { q1: ["t1"], q2: [], q4: [] } });
  const r = await crearAdaptadorWeb(deps(res)).read(ctx(base()));
  if (r.status === "ok") assert.equal(r.claims[0].due_at, null);
  else assert.fail(r.status);
});

for (const [estado, status] of [["SESION_CADUCADA", "session_expired"], ["DESACTIVADA", "recipe_disabled"], ["ERROR", "error"]] as const) {
  test(`${estado} → ${status} sin afirmaciones y con mensaje`, async () => {
    const r = await crearAdaptadorWeb(deps(resultado(estado))).read(ctx(base()));
    assert.deepEqual(validateAdapterResult(r, "web"), []);
    assert.equal(r.status, status);
    assert.ok(!("claims" in r));
  });
}

test("una receta caducada tumba el adaptador aunque otra vaya bien (fail-closed, gana la sesión)", async () => {
  const ok = resultado("OK", { elementos: [el("t1", { titulo: "x" })], preguntas: { q1: ["t1"], q2: [], q4: [] } });
  const seq = [resultado("ERROR"), ok, resultado("SESION_CADUCADA")];
  const d: Dependencias = { banco: true, ejecutar: async () => seq.shift()!, vigilar: async () => vig("SIN_CAMBIOS") };
  const r = await crearAdaptadorWeb(d).read(ctx(base({ recetas: [receta(), receta(), receta()] })));
  assert.equal(r.status, "session_expired");
  assert.ok(!("claims" in r));
});

test("excepción del ejecutor → error, no revienta", async () => {
  const r = await crearAdaptadorWeb(deps(new Error("navegador muerto\npila"))).read(ctx(base()));
  if (r.status === "ok") assert.fail("debía fallar");
  assert.equal(r.status, "error");
  assert.match(r.message, /navegador muerto/);
});

test("receta experimental sin recibo no se ejecuta; sin nada activo → recipe_disabled", async () => {
  const d = deps(resultado("OK"));
  const r = await crearAdaptadorWeb(d).read(ctx(base({ recetas: [experimental()] })));
  assert.equal(d.llamadas, 0);
  assert.equal(r.status, "recipe_disabled");
});

test("en producto (sin banco) una estable de origen local tampoco se ejecuta sin recibo (revisión #1443 P2-3)", async () => {
  const d = { ...deps(resultado("OK")), banco: undefined };
  let llamadas = 0;
  d.ejecutar = async () => { llamadas++; return resultado("OK"); };
  const r = await crearAdaptadorWeb(d).read(ctx(base()));
  assert.equal(llamadas, 0);
  assert.equal(r.status, "recipe_disabled");
});

test("sin perfil dedicado o sin navegador → not_configured, nunca un perfil temporal", async () => {
  for (const p of [{ ejecutable: "/x/chrome", recetas: [receta()] }, { perfil: "/x/p", recetas: [receta()] }]) {
    const d = deps(resultado("OK"));
    const r = await crearAdaptadorWeb(d).read(ctx(p));
    assert.equal(r.status, "not_configured");
    assert.equal(d.llamadas, 0);
  }
});

test("ruta distinta de web → error", async () => {
  const r = await crearAdaptadorWeb(deps(resultado("OK"))).read(ctx(base(), "graph"));
  assert.equal(r.status, "error");
});

test("página vigilada cambiada → web_page_change cerrada con event_at; login → session_expired; otra redirección → error", async () => {
  const v = { id: "p1", sitio: "intranet", url: "https://intranet.example/avisos" };
  const p = base({ recetas: [], vigiladas: [v], huellas: "/x/huellas.json" });
  const r = await crearAdaptadorWeb(deps(resultado("OK"), vig("CAMBIADA"))).read(ctx(p));
  assert.deepEqual(validateAdapterResult(r, "web"), []);
  assert.equal(r.status, "ok");
  if (r.status === "ok") {
    assert.equal(r.claims[0].key, "web:web_page_change:intranet~p1");
    assert.equal(r.claims[0].open, false);
    assert.equal(r.claims[0].event_at, "2026-10-20T08:00:00.000Z");
  }
  const sin = await crearAdaptadorWeb(deps(resultado("OK"), vig("SIN_CAMBIOS"))).read(ctx(p));
  assert.equal(sin.status, "ok");
  if (sin.status === "ok") assert.equal(sin.claims.length, 0);
  const login = await crearAdaptadorWeb(deps(resultado("OK"), vig("SESION_CADUCADA"))).read(ctx(p));
  assert.equal(login.status, "session_expired");
  // Una redirección que no es el login no se arregla iniciando sesión (revisión #1443, P2-2 de corrección).
  const red = await crearAdaptadorWeb(deps(resultado("OK"), vig("REDIRIGIDA"))).read(ctx(p));
  assert.equal(red.status, "error");
});

test("páginas vigiladas sin fichero de huellas → not_configured", async () => {
  const r = await crearAdaptadorWeb(deps(resultado("OK"))).read(ctx(base({ recetas: [], vigiladas: [{ id: "p", sitio: "s", url: "https://s.example/" }] })));
  assert.equal(r.status, "not_configured");
});

test("la huella de una página vigilada solo se confirma si el adaptador entrega: un fallo no consume el cambio", async () => {
  const fichero = join(mkdtempSync(join(tmpdir(), "soul-contrato-")), "huellas.json");
  const v = { id: "p1", sitio: "intranet", url: "https://intranet.example/avisos" };
  const p = base({ vigiladas: [v], huellas: fichero });
  const vistos: OpcionesVigilancia[] = [];
  const dep = (receta: Resultado): Dependencias => ({
    banco: true,
    ejecutar: async () => receta,
    vigilar: async (o) => { vistos.push(o); return { ...vig("CAMBIADA"), huella: "h-nueva" }; },
  });
  const fallo = await crearAdaptadorWeb(dep(resultado("ERROR"))).read(ctx(p));
  assert.equal(fallo.status, "error");
  assert.equal(vistos[0].diferirHuella, true, "la vigilancia no debe guardar la huella por su cuenta");
  assert.equal(new AlmacenHuellas(fichero).anterior("p1"), null, "el cambio descartado no puede quedar como visto");
  const bien = await crearAdaptadorWeb(dep(resultado("OK"))).read(ctx(p));
  assert.equal(bien.status, "ok");
  assert.equal(new AlmacenHuellas(fichero).anterior("p1"), "h-nueva");
});

test("una receta inválida en params no llega al navegador → not_configured", async () => {
  const d = deps(resultado("OK"));
  const mala = { ...receta(), urls: ["/tareas/*"], paginas: ["/otra"] };
  const r = await crearAdaptadorWeb(d).read(ctx(base({ recetas: [mala] })));
  assert.equal(r.status, "not_configured");
  assert.equal(d.llamadas, 0);
});

test("una página vigilada mal configurada → not_configured sin abrir el navegador", async () => {
  for (const v of [{ id: "p", sitio: "s", url: "javascript:alert(1)" }, { id: "p", sitio: "s", url: "https://s.example/logout" }, { id: "p", sitio: "s" }]) {
    let vistas = 0;
    const d = { ...deps(resultado("OK")), vigilar: async () => { vistas++; return vig("SIN_CAMBIOS"); } };
    const r = await crearAdaptadorWeb(d).read(ctx(base({ vigiladas: [v], huellas: "/x/h.json" })));
    assert.equal(r.status, "not_configured", JSON.stringify(v));
    assert.equal(d.llamadas + vistas, 0);
  }
});

test("receta experimental con recibo válido se ejecuta a través del adaptador", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-contrato-"));
  const r = experimental();
  guardarRecibo(dir, r, { peticiones: 1, permitidas: 1, operaciones_lectura: 1 });
  const d = deps(resultado("OK"));
  const res = await crearAdaptadorWeb(d).read(ctx(base({ recetas: [r], validaciones: dir })));
  assert.equal(d.llamadas, 1);
  assert.equal(res.status, "ok");
});

test("una receta configurada que no se activa no se omite en silencio aunque haya páginas vigiladas", async () => {
  const d = deps(resultado("OK"), vig("SIN_CAMBIOS"));
  const p = base({ recetas: [receta(), experimental()], vigiladas: [{ id: "p", sitio: "s", url: "https://s.example/avisos" }],
    huellas: join(mkdtempSync(join(tmpdir(), "soul-contrato-")), "h.json") });
  const r = await crearAdaptadorWeb(d).read(ctx(p));
  assert.deepEqual(validateAdapterResult(r, "web"), []);
  assert.equal(r.status, "recipe_disabled");
  assert.match("message" in r ? r.message : "", /experimental/);
  assert.equal(d.llamadas, 1, "las recetas activas se siguen ejecutando (una sesión caducada mandaría)");
});

test("recetas sin fichero de desactivadas → not_configured: la desactivación tiene que persistir (revisión #1443 P2-2)", async () => {
  const d = deps(resultado("OK"));
  for (const desactivadas of [undefined, ""]) {
    const r = await crearAdaptadorWeb(d).read(ctx(base({ desactivadas })));
    assert.equal(r.status, "not_configured");
    assert.match("message" in r ? r.message : "", /desactivadas/);
  }
  assert.equal(d.llamadas, 0);
  // Caso negativo: solo páginas vigiladas, sin recetas, no lo necesita.
  const v = { id: "p1", sitio: "intranet", url: "https://intranet.example/avisos" };
  const solo = await crearAdaptadorWeb(d).read(ctx(base({ recetas: [], desactivadas: undefined, vigiladas: [v], huellas: "/x/h.json" })));
  assert.equal(solo.status, "ok");
});

test("sin recetas ni páginas vigiladas → not_configured, no recipe_disabled (revisión #1443 P2-4)", async () => {
  const r = await crearAdaptadorWeb(deps(resultado("OK"))).read(ctx(base({ recetas: [] })));
  assert.equal(r.status, "not_configured");
});

test("no poder guardar la huella es error y no entrega el cambio; el directorio se crea si falta (revisión #1443 P2-1)", async () => {
  const v = { id: "p1", sitio: "intranet", url: "https://intranet.example/avisos" };
  const dep: Dependencias = { banco: true, ejecutar: async () => resultado("OK"),
    vigilar: async () => ({ ...vig("CAMBIADA"), huella: "h-nueva" }) };
  // Un fichero de huellas cuyo «directorio» es un fichero: no se puede escribir.
  const raiz = mkdtempSync(join(tmpdir(), "soul-contrato-"));
  writeFileSync(join(raiz, "fichero"), "x");
  const r = await crearAdaptadorWeb(dep).read(ctx(base({ vigiladas: [v], huellas: join(raiz, "fichero", "h.json") })));
  assert.equal(r.status, "error");
  assert.match("message" in r ? r.message : "", /huellas/);
  // Caso negativo: un directorio que aún no existe se crea y la huella queda guardada.
  const nuevo = join(raiz, "aun", "no", "h.json");
  const ok = await crearAdaptadorWeb(dep).read(ctx(base({ vigiladas: [v], huellas: nuevo })));
  assert.equal(ok.status, "ok");
  assert.equal(new AlmacenHuellas(nuevo).anterior("p1"), "h-nueva");
});
