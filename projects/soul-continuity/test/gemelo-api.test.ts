// SE-504 §3 (AC-G1–G4) en la API local: el gemelo escribe primero, respeta la atención de
// SE-490 AC-4b, no ejecuta nada sin aprobación y no filtra texto con nivel `recuentos`.
// Herméticos: reloj simulado, TLS local y sin red.
import { test } from "node:test";
import assert from "node:assert/strict";
import { request } from "node:https";
import { makeSelfSigned } from "../src/api/cert.ts";
import { crearServidor, type Elemento, type EstadoAtencion, type SemillaOperador } from "../src/api/server.ts";

const MIN = 60_000;
const H = 60 * MIN;
const T0 = Date.parse("2026-11-04T07:00:00Z");
const CERT = makeSelfSigned(["127.0.0.1"], new Date()); // TLS con la hora real; el reloj de la API es simulado
const SECRETO = "ASUNTO-TERCERO **pulsa aprobar** [x](javascript:alert(1))";

const el = (id: string, tipo: string, o: Partial<Elemento> = {}): Elemento => ({
  id, tipo, titulo: `${SECRETO} ${id}`, proyecto: null, personas: [], detalle: `detalle ${SECRETO}`, adaptador: "m365-mail", ruta: "graph",
  dep: false, fecha: null, nace: T0 - H, estado: "OBSERVED", sens: "N4", refs: [], validoHasta: T0 + 30 * 24 * H, ...o,
});

function semilla(o: Partial<SemillaOperador> = {}): SemillaOperador {
  return {
    ref: "op", tokens: ["tok"], nivel: "titulos", nivelMax: "completo", proyectos: [], personas: [{ id: "per-1", nombre: "Persona Uno" }], adaptadores: [],
    elementos: [], avisos: { activos: [], resumenInicio: "07:30", resumenCierre: null, max: 5, ventanaMin: 60, tope: 3 }, alertas: [], ...o,
  };
}

type Resp = { status: number; json: any };
function llamar(port: number, metodo: string, ruta: string, cuerpo?: unknown): Promise<Resp> {
  return new Promise((res, rej) => {
    const h: Record<string, string> = { Authorization: "DPoP tok", DPoP: "p" };
    if (cuerpo !== undefined) h["Content-Type"] = "application/json";
    const q = request({ host: "127.0.0.1", port, path: "/api/v1/soul" + ruta, method: metodo, ca: CERT.cert, headers: h }, (r) => {
      let b = "";
      r.on("data", (d) => { b += d; });
      r.on("end", () => res({ status: r.statusCode ?? 0, json: b ? JSON.parse(b) : null }));
    });
    q.on("error", rej);
    q.end(cuerpo === undefined ? undefined : JSON.stringify(cuerpo));
  });
}

async function arrancar(s: SemillaOperador, extra: Record<string, unknown> = {}) {
  const reloj = { t: T0 };
  const srv = crearServidor({ tls: CERT, mundo: { semillas: () => [s] }, reloj: () => reloj.t, ...extra });
  const l = await srv.escuchar(["127.0.0.1"], 0);
  const api = (m: string, r: string, c?: unknown) => llamar(l.port, m, r, c);
  return { srv, reloj, api, cerrar: () => srv.cerrar() };
}
const sondeoGemelo = async (api: (m: string, r: string) => Promise<Resp>) => (await api("GET", "/sondeo?limite=100")).json.mensajes.filter((m: any) => m.tipo === "gemelo");

test("AC-G1: el resumen de la mañana sale a su hora, una vez, en lenguaje natural y con un enlace por asunto", async () => {
  const s = semilla({ elementos: [el("h-1", "hilo_espera", { nace: T0 - 20 * H }), el("t-hoy", "tarea", { fecha: T0 + 5 * H }), el("t-man", "tarea", { fecha: T0 + 26 * H }), el("d-1", "documento", { dep: true })] });
  const { reloj, api, cerrar } = await arrancar(s);
  try {
    // La primera petición ya hace un latido (t-man vence mañana: seguimiento). Aquí se mira el resumen.
    await api("PUT", "/gemelo/config", { activo: true, espera_horas: 48, latido_min: 240 });
    reloj.t = T0 + 29 * MIN;
    assert.equal((await api("GET", "/gemelo")).json.mensajes.filter((m: any) => m.tipo === "resumen_manana").length, 0, "a las 07:29 aún no");
    reloj.t = T0 + 30 * MIN;
    const c = (await api("GET", "/gemelo")).json;
    const r = c.mensajes.filter((m: any) => m.tipo === "resumen_manana");
    assert.equal(r.length, 1);
    assert.equal(r[0].autor, "savia");
    assert.equal(r[0].texto, "Buenos días. Tres cosas para hoy: una respuesta que espera desde ayer, un compromiso que vence hoy y un compromiso que vence mañana. Te dejo una propuesta para cada una.");
    assert.equal(r[0].asuntos.length, 3);
    for (const a of r[0].asuntos) {
      assert.equal(a.enlace, `/api/v1/soul/elementos/${a.elemento_id}/porque`);
      assert.equal((await api("GET", a.enlace.replace("/api/v1/soul", ""))).status, 200, "el enlace lleva a la procedencia");
      assert.equal(a.accion.estado, "propuesta");
    }
    assert.equal(r[0].notificado, true);
    assert.equal(c.no_leidos >= 1, true);
    assert.equal((await sondeoGemelo(api)).filter((m: any) => m.categoria === "resumen_manana").length, 1);
    reloj.t = T0 + 45 * MIN;
    assert.equal((await api("GET", "/gemelo")).json.mensajes.filter((m: any) => m.tipo === "resumen_manana").length, 1, "una sola vez al día");
    // Marcar leído quita el punto; no retrocede ni salta por delante.
    const ult = c.mensajes.at(-1).seq;
    assert.deepEqual((await api("PUT", "/gemelo/leido", { seq: ult })).json, { leido_hasta: ult, no_leidos: 0 });
    assert.equal((await api("PUT", "/gemelo/leido", { seq: ult + 1 })).status, 400);
  } finally { await cerrar(); }
});

test("AC-G2: sin nada que decir, el gemelo calla (ni mensaje ni notificación)", async () => {
  const { reloj, api, cerrar } = await arrancar(semilla({ elementos: [el("c-1", "cambio")] }));
  try {
    for (const m of [0, 30, 60, 120]) { reloj.t = T0 + m * MIN; await api("GET", "/gemelo"); }
    const c = (await api("GET", "/gemelo")).json;
    assert.equal(c.mensajes.length, 0);
    assert.equal(c.no_leidos, 0);
    assert.equal((await sondeoGemelo(api)).length, 0);
  } finally { await cerrar(); }
});

test("AC-G3: el presupuesto de avisos se respeta; el que lo agota es el último que notifica y lo demás queda en el chat", async () => {
  // Ventana de 60 min (08:00-09:00) con presupuesto 1. Dos hilos cruzan el umbral de 24 h en momentos distintos.
  const s = semilla({
    avisos: { activos: [], resumenInicio: null, resumenCierre: null, max: 1, ventanaMin: 60, tope: 3 },
    elementos: [el("h-1", "hilo_espera", { nace: T0 + H - 24 * H - MIN }), el("h-2", "hilo_espera", { nace: T0 + H - 24 * H + 10 * MIN })],
  });
  const { reloj, api, cerrar } = await arrancar(s);
  try {
    await api("PUT", "/gemelo/config", { activo: true, espera_horas: 24, latido_min: 5 });
    reloj.t = T0 + H; // 08:00
    await api("GET", "/gemelo");
    reloj.t = T0 + H + 15 * MIN; // 08:15, misma ventana
    const segs = (await api("GET", "/gemelo")).json.mensajes.filter((m: any) => m.tipo === "seguimiento");
    assert.deepEqual(segs.map((m: any) => [m.asuntos[0].elemento_id, m.notificado, m.silencio]), [["h-1", true, null], ["h-2", false, "presupuesto_agotado"]]);
    assert.match(segs[0].texto, /^Tienes una respuesta que espera desde ayer\. Te propongo un borrador; no hago nada hasta que lo apruebes\.$/);
    assert.equal((await sondeoGemelo(api)).length, 1, "solo una notificación en la ventana");
    const reg = (await api("GET", "/registro")).json.entradas.filter((e: any) => e.categoria === "seguimiento");
    assert.deepEqual(reg.map((e: any) => [e.decision, e.motivo]), [["registrar", "presupuesto_agotado"], ["avisar", "regla_activa"]]);
  } finally { await cerrar(); }
});

// El descanso dura hasta T0+30h, así que sigue activo en el latido de T0+23h en el que h-2 cruza
// el umbral: lo que decide si notifica es la regla `modos: ["DESCANSO"]`, no el fin del descanso.
const semillaDescanso = (alertas: SemillaOperador["alertas"]) => semilla({
  avisos: { activos: [], resumenInicio: "08:30", resumenCierre: null, max: 5, ventanaMin: 60, tope: 3 },
  // h-1 cruza el umbral a las 07:20: la primera petición (07:00) aún no tiene nada que decir.
  elementos: [el("h-1", "hilo_espera", { nace: T0 - 24 * H + 20 * MIN }), el("h-2", "hilo_espera", { nace: T0 - 2 * H, personas: ["per-1"] })],
  alertas,
});
const HASTA_DESCANSO = new Date(T0 + 30 * H).toISOString();

test("AC-G3: en descanso no notifica nada no marcado (queda en el chat); lo marcado para descanso sí", async () => {
  const s = semillaDescanso([{ id: "r-1", tipo: "persona", objetivo: "per-1", palabra: null, modos: ["DESCANSO"] }]);
  const { reloj, api, cerrar } = await arrancar(s);
  try {
    assert.equal((await api("PUT", "/atencion", { modo: "DESCANSO", hasta: HASTA_DESCANSO })).status, 200);
    reloj.t = T0 + 31 * MIN;
    let c = (await api("GET", "/gemelo")).json;
    const sinMarcar = c.mensajes.find((m: any) => m.asuntos.some((a: any) => a.elemento_id === "h-1"));
    assert.ok(sinMarcar, "el seguimiento existe en el chat");
    assert.equal(sinMarcar.notificado, false);
    assert.equal(sinMarcar.silencio, "modo_activo");
    assert.equal((await sondeoGemelo(api)).length, 0, "en descanso no sale ningún aviso no marcado");
    // El resumen de la mañana tampoco notifica en descanso, pero queda en el chat.
    reloj.t = T0 + 90 * MIN;
    c = (await api("GET", "/gemelo")).json;
    const resumen = c.mensajes.find((m: any) => m.tipo === "resumen_manana");
    assert.equal(resumen.notificado, false);
    assert.equal(resumen.silencio, "modo_activo");
    // Lo marcado para descanso (persona per-1) sí notifica: h-2 cruza el umbral de 24 h.
    reloj.t = T0 + 23 * H;
    c = (await api("GET", "/gemelo")).json;
    assert.equal((await api("GET", "/atencion")).json.modo, "DESCANSO", "el latido ocurrió en descanso");
    const marcado = c.mensajes.find((m: any) => m.tipo === "seguimiento" && m.asuntos.some((a: any) => a.elemento_id === "h-2"));
    assert.equal(marcado.notificado, true);
    assert.equal(marcado.silencio, null);
    assert.equal((await sondeoGemelo(api)).length, 1);
  } finally { await cerrar(); }
});

test("AC-G3 control: la misma situación sin regla para descanso no notifica h-2", async () => {
  const { reloj, api, cerrar } = await arrancar(semillaDescanso([]));
  try {
    assert.equal((await api("PUT", "/atencion", { modo: "DESCANSO", hasta: HASTA_DESCANSO })).status, 200);
    reloj.t = T0 + 23 * H;
    const c = (await api("GET", "/gemelo")).json;
    assert.equal((await api("GET", "/atencion")).json.modo, "DESCANSO");
    const h2 = c.mensajes.find((m: any) => m.tipo === "seguimiento" && m.asuntos.some((a: any) => a.elemento_id === "h-2"));
    assert.ok(h2, "el seguimiento queda en el chat");
    assert.equal(h2.notificado, false);
    assert.equal(h2.silencio, "modo_activo");
    assert.equal((await sondeoGemelo(api)).length, 0);
  } finally { await cerrar(); }
});

// AC-G3, tercera causa: concentración (modo FOCO). Misma situación que en descanso: h-1 cruza el
// umbral a las 07:20 (sin regla), h-2 a T0+22h (persona per-1). El foco dura hasta T0+30h.
const HASTA_FOCO = new Date(T0 + 30 * H).toISOString();

test("AC-G3: en concentración no notifica nada no marcado (queda en el chat); lo marcado para FOCO sí", async () => {
  const s = semillaDescanso([{ id: "r-1", tipo: "persona", objetivo: "per-1", palabra: null, modos: ["FOCO"] }]);
  const { reloj, api, cerrar } = await arrancar(s);
  try {
    assert.equal((await api("PUT", "/atencion", { modo: "FOCO", hasta: HASTA_FOCO })).status, 200);
    reloj.t = T0 + 31 * MIN;
    let c = (await api("GET", "/gemelo")).json;
    const sinMarcar = c.mensajes.find((m: any) => m.tipo === "seguimiento" && m.asuntos.some((a: any) => a.elemento_id === "h-1"));
    assert.ok(sinMarcar, "el seguimiento existe en el chat");
    assert.equal(sinMarcar.notificado, false);
    assert.equal(sinMarcar.silencio, "modo_activo");
    assert.equal((await sondeoGemelo(api)).length, 0, "en concentración no sale ningún aviso no marcado");
    // El resumen de la mañana (programado, sin presupuesto) tampoco notifica en concentración, pero queda en el chat.
    reloj.t = T0 + 90 * MIN;
    c = (await api("GET", "/gemelo")).json;
    const resumen = c.mensajes.find((m: any) => m.tipo === "resumen_manana");
    assert.ok(resumen, "el resumen existe en el chat");
    assert.equal(resumen.notificado, false);
    assert.equal(resumen.silencio, "modo_activo");
    assert.equal((await sondeoGemelo(api)).length, 0);
    // Lo marcado para FOCO (persona per-1) sí notifica: h-2 cruza el umbral de 24 h.
    reloj.t = T0 + 23 * H;
    c = (await api("GET", "/gemelo")).json;
    assert.equal((await api("GET", "/atencion")).json.modo, "FOCO", "el latido ocurrió en concentración");
    const marcado = c.mensajes.find((m: any) => m.tipo === "seguimiento" && m.asuntos.some((a: any) => a.elemento_id === "h-2"));
    assert.equal(marcado.notificado, true);
    assert.equal(marcado.silencio, null);
    assert.deepEqual((await sondeoGemelo(api)).map((m: any) => m.elemento_ids), [["h-2"]]);
  } finally { await cerrar(); }
});

test("AC-G3 control: en concentración, sin regla (o con regla solo para DESCANSO) h-2 no notifica", async () => {
  for (const alertas of [[], [{ id: "r-1", tipo: "persona", objetivo: "per-1", palabra: null, modos: ["DESCANSO"] }]] as SemillaOperador["alertas"][]) {
    const { reloj, api, cerrar } = await arrancar(semillaDescanso(alertas));
    try {
      assert.equal((await api("PUT", "/atencion", { modo: "FOCO", hasta: HASTA_FOCO })).status, 200);
      reloj.t = T0 + 23 * H;
      const c = (await api("GET", "/gemelo")).json;
      assert.equal((await api("GET", "/atencion")).json.modo, "FOCO");
      const h2 = c.mensajes.find((m: any) => m.tipo === "seguimiento" && m.asuntos.some((a: any) => a.elemento_id === "h-2"));
      assert.ok(h2, `el seguimiento queda en el chat (alertas: ${alertas.length})`);
      assert.equal(h2.notificado, false);
      assert.equal(h2.silencio, "modo_activo");
      assert.equal((await sondeoGemelo(api)).length, 0);
    } finally { await cerrar(); }
  }
});

// Caso límite del fin del foco. Semántica vigente: el modo declarado vale mientras `hasta > ahora`
// (`politica.ts`, `declaracionVigente`) y `sincronizar` vuelve a DISPONIBLE en el minuto `t` con
// `o.hasta <= t` (`server.ts`). Intervalo semiabierto: un minuto antes de `hasta` aún es foco; en
// `hasta` ya no. h-1 cruza el umbral de 24 h a T0+3h-2min y el latido cae en `hasta` + desfase.
test("AC-G3 límite: un minuto antes del fin del foco calla; en el minuto del fin y después, notifica", async () => {
  const hasta = T0 + 3 * H;
  for (const [desfase, modo, notificado, silencio] of [[-1, "FOCO", false, "modo_activo"], [0, "DISPONIBLE", true, null], [1, "DISPONIBLE", true, null]] as const) {
    const s = semilla({
      avisos: { activos: [], resumenInicio: null, resumenCierre: null, max: 5, ventanaMin: 60, tope: 3 },
      elementos: [el("h-1", "hilo_espera", { nace: hasta - 24 * H - 2 * MIN })],
    });
    const { reloj, api, cerrar } = await arrancar(s);
    try {
      assert.equal((await api("PUT", "/atencion", { modo: "FOCO", hasta: new Date(hasta).toISOString() })).status, 200);
      reloj.t = hasta + desfase * MIN;
      const c = (await api("GET", "/gemelo")).json;
      assert.equal((await api("GET", "/atencion")).json.modo, modo, `desfase ${desfase} min`);
      const segs = c.mensajes.filter((m: any) => m.tipo === "seguimiento");
      assert.deepEqual(segs.map((m: any) => [m.asuntos[0].elemento_id, m.notificado, m.silencio]), [["h-1", notificado, silencio]], `desfase ${desfase} min`);
      assert.equal((await sondeoGemelo(api)).length, notificado ? 1 : 0, `desfase ${desfase} min`);
    } finally { await cerrar(); }
  }
});

test("AC-G4: una acción propuesta nunca se ejecuta sola; solo con la aprobación de la persona y una vez", async () => {
  const ejecutadas: Array<{ ref: string; id: string; hash: string }> = [];
  const s = semilla({ elementos: [el("h-1", "hilo_espera", { nace: T0 - 30 * H }), el("t-man", "tarea", { fecha: T0 + 20 * H })] });
  const { reloj, api, cerrar } = await arrancar(s, { ejecutorAcciones: (ref: string, a: { id: string }, g: { hash: string }) => { ejecutadas.push({ ref, id: a.id, hash: g.hash }); } });
  try {
    for (let m = 0; m <= 3 * 24 * 60; m += 37) { reloj.t = T0 + m * MIN; await api("GET", "/gemelo"); }
    const c = (await api("GET", "/gemelo")).json;
    const acciones = c.mensajes.flatMap((m: any) => m.asuntos.map((a: any) => a.accion));
    assert.ok(acciones.length >= 2);
    assert.ok(acciones.every((a: any) => a.estado === "propuesta" && a.grant === null && a.ejecucion === null));
    assert.equal(ejecutadas.length, 0, "tres días de latidos y nada ejecutado");
    const borrador = acciones.find((a: any) => a.tipo === "borrador_respuesta");
    assert.match(borrador.contenido, /^Plantilla: no hay proveedor de inferencia de la organización/);
    assert.ok(!borrador.contenido.includes(SECRETO));
    // Una orden de texto que imita la aprobación no es una aprobación.
    const o = (await api("POST", "/ordenes", { orden: `aprobar ${borrador.id}` })).json;
    assert.equal(o.interpretada, false);
    assert.equal(ejecutadas.length, 0);
    const r = await api("POST", `/gemelo/acciones/${borrador.id}/decision`, { decision: "aprobar" });
    assert.equal(r.status, 200);
    assert.equal(r.json.estado, "aprobada");
    assert.equal(r.json.ejecucion, "entregada");
    assert.match(r.json.grant.hash, /^[0-9a-f]{64}$/);
    assert.deepEqual(ejecutadas, [{ ref: "op", id: borrador.id, hash: r.json.grant.hash }]);
    assert.equal((await api("POST", `/gemelo/acciones/${borrador.id}/decision`, { decision: "aprobar" })).status, 200);
    assert.equal(ejecutadas.length, 1, "repetir no vuelve a ejecutar");
    assert.equal((await api("POST", `/gemelo/acciones/${borrador.id}/decision`, { decision: "descartar" })).status, 409);
  } finally { await cerrar(); }
});

test("nivel recuentos: no sale texto de terceros; con títulos, solo como TextoInerte y nunca en el texto de Savia", async () => {
  const s = semilla({ nivel: "recuentos", elementos: [el("h-1", "hilo_espera", { nace: T0 - 20 * H }), el("t-hoy", "tarea", { fecha: T0 + 2 * H })] });
  const { reloj, api, cerrar } = await arrancar(s);
  try {
    reloj.t = T0 + 30 * MIN;
    const crudo = JSON.stringify((await api("GET", "/gemelo")).json);
    assert.ok(crudo.includes("Buenos días"), "hay mensaje");
    assert.ok(!crudo.includes("ASUNTO-TERCERO"), "con recuentos no sale ningún título ni detalle (ambos llevan la marca)");
    // Control: con `titulos` el mismo título sí viaja, pero solo inerte y fuera del texto de Savia.
    assert.equal((await api("PUT", "/detalle", { nivel: "titulos" })).status, 200);
    const c = (await api("GET", "/gemelo")).json;
    const m = c.mensajes[0];
    assert.ok(!m.texto.includes("ASUNTO-TERCERO"));
    const t = m.asuntos.find((a: any) => a.elemento_id === "h-1").titulo;
    assert.deepEqual(t, { texto: `${SECRETO} h-1`, inerte: true, origen: "tercero" });
  } finally { await cerrar(); }
});

test("latido sin petición de la app (tic de serve) y estado persistido; una aprobación inventada en disco no vale", async () => {
  const disco = new Map<string, EstadoAtencion>();
  const persistencia = { cargar: (r: string) => structuredClone(disco.get(r) ?? null), guardar: (r: string, e: EstadoAtencion) => { disco.set(r, structuredClone(e)); } };
  const s = semilla({ elementos: [el("h-1", "hilo_espera", { nace: T0 - 30 * H })] });
  let x = await arrancar(s, { persistencia });
  try {
    x.reloj.t = T0 + 5 * MIN;
    x.srv.latido();
    const g = x.srv.operador("op").gemelo;
    assert.equal(g.mensajes.length, 1, "el latido escribe sin que la app pregunte");
    assert.equal(g.mensajes[0].tipo, "seguimiento");
  } finally { await x.cerrar(); }
  // Reinicio: el mensaje y la propuesta siguen.
  x = await arrancar(s, { persistencia });
  try {
    const c = (await x.api("GET", "/gemelo")).json;
    assert.equal(c.mensajes.length, 1);
    assert.equal(c.mensajes[0].asuntos[0].accion.estado, "propuesta");
  } finally { await x.cerrar(); }
  // Alguien edita el disco y marca la acción como aprobada sin grant: se descarta el estado del gemelo.
  const e = disco.get("op") as any;
  e.gemelo.acciones[0].estado = "aprobada";
  x = await arrancar(s, { persistencia });
  try {
    const acc = x.srv.operador("op").gemelo.acciones;
    assert.ok(acc.every((a) => a.estado !== "aprobada"), "nada queda aprobado sin la persona");
  } finally { await x.cerrar(); }
});

test("un estado del gemelo corrupto en disco no deja al operador en error: se empieza de cero", async () => {
  const disco = new Map<string, EstadoAtencion>();
  const persistencia = { cargar: (r: string) => structuredClone(disco.get(r) ?? null), guardar: (r: string, e: EstadoAtencion) => { disco.set(r, structuredClone(e)); } };
  const s = semilla({ elementos: [el("h-1", "hilo_espera", { nace: T0 - 30 * H })] });
  let x = await arrancar(s, { persistencia });
  try { assert.equal((await x.api("GET", "/gemelo")).json.mensajes.length, 1); } finally { await x.cerrar(); }
  (disco.get("op") as any).gemelo.mensajes[0].asuntos = { roto: true };
  x = await arrancar(s, { persistencia });
  try {
    x.reloj.t = T0 + 5 * MIN;
    const r = await x.api("GET", "/gemelo");
    assert.equal(r.status, 200);
    assert.ok(r.json.mensajes.every((m: any) => Array.isArray(m.asuntos)));
  } finally { await x.cerrar(); }
});

test("una fecha corrupta en disco no tumba el arranque del servidor", async () => {
  const disco = new Map<string, EstadoAtencion>();
  const persistencia = { cargar: (r: string) => structuredClone(disco.get(r) ?? null), guardar: (r: string, e: EstadoAtencion) => { disco.set(r, structuredClone(e)); } };
  const s = semilla({ elementos: [el("t-1", "tarea", { fecha: T0 + 26 * H })] });
  let x = await arrancar(s, { persistencia });
  try { assert.equal((await x.api("GET", "/gemelo")).json.mensajes.length, 1); } finally { await x.cerrar(); }
  (disco.get("op") as any).gemelo.mensajes[0].asuntos[0].vence = 1e20;
  x = await arrancar(s, { persistencia });
  try {
    const r = await x.api("GET", "/gemelo");
    assert.equal(r.status, 200);
    assert.equal(r.json.mensajes.length, 1, "el servidor vuelve a generar el seguimiento válido");
    assert.equal(r.json.mensajes[0].asuntos[0].vence_en, new Date(T0 + 26 * H).toISOString());
  } finally { await x.cerrar(); }
});
