// Bucle de iniciativa del gemelo (SE-504 §3, AC-G1–G4): lógica pura con reloj simulado.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  MAX_ASUNTOS, decidirAccion, diaResumenDebido, detectarSeguimientos, emitirMensaje, estadoGemeloVacio, hashAccion, latidoDebido,
  marcarResumen, podar, redactar, restaurarGemelo, resumenDebido, seleccionarResumen, type ElementoGemelo, ErrorDecision,
} from "../src/core/gemelo.ts";

const MIN = 60_000;
const H = 60 * MIN;
const AHORA = Date.parse("2026-11-04T08:00:00Z");
const el = (id: string, tipo: string, o: Partial<ElementoGemelo> = {}): ElementoGemelo => ({ id, tipo, fecha: null, nace: AHORA - H, dep: false, ...o });

test("resumen: prioriza lo que espera, lo que vence hoy y mañana; como mucho 3 asuntos", () => {
  const els = [
    el("t-man", "tarea", { fecha: AHORA + 26 * H }),
    el("h-1", "hilo_espera", { nace: AHORA - 20 * H }),
    el("t-hoy", "tarea", { fecha: AHORA + 4 * H }),
    el("d-1", "documento", { dep: true }),
  ];
  const a = seleccionarResumen(els, AHORA);
  assert.deepEqual(a.map((x) => [x.elementoId, x.motivo]), [["h-1", "espera_respuesta"], ["t-hoy", "vence_hoy"], ["t-man", "vence_manana"]]);
  assert.equal(a.length, MAX_ASUNTOS);
  assert.deepEqual(seleccionarResumen([], AHORA), [], "sin nada, no hay asuntos (AC-G2)");
});

test("redacción: lenguaje natural, sin listas técnicas ni texto de terceros", () => {
  const a = seleccionarResumen([el("h-1", "hilo_espera", { nace: Date.parse("2026-11-03T15:00:00Z") }), el("t-hoy", "tarea", { fecha: AHORA + H })], AHORA);
  const t = redactar("resumen_manana", a, AHORA);
  assert.equal(t, "Buenos días. Dos cosas para hoy: una respuesta que espera desde ayer y un compromiso que vence hoy. Te dejo una propuesta para cada una.");
  assert.doesNotMatch(t, /q[1-4]|hilo_espera|vence_hoy|\bid\b/);
  assert.match(redactar("resumen_manana", a.slice(0, 1), AHORA), /^Buenos días\. Una cosa para hoy: /);
});

test("seguimientos: espera de más de N horas (umbral estricto), vence mañana y cambios nuevos", () => {
  const cfg = { activo: true, esperaHoras: 24, latidoMin: 30 };
  const justo = el("h-justo", "hilo_espera", { nace: AHORA - 24 * H });
  const pasado = el("h-pasado", "hilo_espera", { nace: AHORA - 24 * H - MIN });
  const man = el("t-man", "tarea", { fecha: AHORA + 20 * H });
  const nuevo = el("d-nuevo", "documento", { dep: true, nace: AHORA - 10 * MIN });
  const viejo = el("d-viejo", "documento", { dep: true, nace: AHORA - 2 * H });
  const s = detectarSeguimientos([justo, pasado, man, nuevo, viejo], AHORA, cfg, new Set(), AHORA - 30 * MIN);
  assert.deepEqual(s.map((x) => `${x.motivo}|${x.elementoId}`), ["espera_respuesta|h-pasado", "vence_manana|t-man", "cambio_importante|d-nuevo"]);
  // En el primer latido no hay «nuevo».
  assert.ok(!detectarSeguimientos([nuevo], AHORA, cfg, new Set(), null).length);
  // Lo ya tratado no se repite.
  assert.ok(!detectarSeguimientos([pasado], AHORA, cfg, new Set(["espera_respuesta|h-pasado"]), null).length);
});

test("emitir: una acción propuesta por asunto, en estado propuesta y sin grant; los seguimientos quedan tratados", () => {
  const est = estadoGemeloVacio();
  const asuntos = detectarSeguimientos([el("h-1", "hilo_espera", { nace: AHORA - 30 * H })], AHORA, est.config, new Set(), null);
  const m = emitirMensaje(est, "seguimiento", asuntos, AHORA, "op");
  assert.equal(m.asuntos.length, 1);
  const acc = est.acciones.find((a) => a.id === m.asuntos[0].accionId)!;
  assert.equal(acc.tipo, "borrador_respuesta");
  assert.equal(acc.estado, "propuesta");
  assert.equal(acc.grant, null);
  assert.equal(acc.generadoPor, "plantilla");
  assert.match(acc.contenido, /^Plantilla: no hay proveedor de inferencia de la organización/);
  assert.deepEqual(est.tratados, ["espera_respuesta|h-1"]);
});

test("resumen: lo que ya merece seguimiento no se repite; una espera bajo el umbral sí tendrá seguimiento", () => {
  const est = estadoGemeloVacio();
  const els = [el("h-viejo", "hilo_espera", { nace: AHORA - 30 * H }), el("h-nuevo", "hilo_espera", { nace: AHORA - 2 * H }), el("t-man", "tarea", { fecha: AHORA + 20 * H })];
  emitirMensaje(est, "resumen_manana", seleccionarResumen(els, AHORA), AHORA, "op");
  assert.deepEqual(est.tratados.sort(), ["espera_respuesta|h-viejo", "vence_manana|t-man"]);
  const despues = AHORA + 23 * H;
  const s = detectarSeguimientos(els, despues, est.config, new Set(est.tratados), AHORA);
  assert.deepEqual(s.map((a) => a.elementoId), ["h-nuevo"], "h-nuevo cruza las 24 h y recibe seguimiento");
});

test("acción: nunca se ejecuta sin aprobar; aprobar registra el grant y entrega una sola vez", () => {
  const est = estadoGemeloVacio();
  emitirMensaje(est, "seguimiento", [{ elementoId: "h-1", motivo: "espera_respuesta", esperaDesde: AHORA - 30 * H, vence: null, accionId: null }], AHORA, "op");
  const id = est.acciones[0].id;
  let ejecutadas = 0;
  const ej = () => { ejecutadas++; };
  // Decisiones inválidas: nada cambia y nada se ejecuta.
  for (const d of ["APROBAR", "si", true, null]) assert.throws(() => decidirAccion(est, id, d, { dispositivo: "dev-1" }, AHORA, ej), ErrorDecision);
  assert.throws(() => decidirAccion(est, "a-otro", "aprobar", { dispositivo: "dev-1" }, AHORA, ej), /NOT_FOUND/);
  assert.equal(ejecutadas, 0);
  assert.equal(est.acciones[0].estado, "propuesta");
  const a = decidirAccion(est, id, "aprobar", { dispositivo: "dev-1" }, AHORA + MIN, ej);
  assert.equal(ejecutadas, 1);
  assert.equal(a.estado, "aprobada");
  assert.equal(a.ejecucion, "entregada");
  assert.deepEqual(a.grant, { en: AHORA + MIN, dispositivo: "dev-1", hash: hashAccion(a) });
  decidirAccion(est, id, "aprobar", { dispositivo: "dev-1" }, AHORA + 2 * MIN, ej);
  assert.equal(ejecutadas, 1, "repetir la aprobación no vuelve a ejecutar");
  assert.throws(() => decidirAccion(est, id, "descartar", { dispositivo: "dev-1" }, AHORA, ej), /CONFLICT/);
});

test("acción descartada no se ejecuta ni se puede aprobar después; sin ejecutor queda «sin_ejecutor»", () => {
  const est = estadoGemeloVacio();
  const asunto = { elementoId: "t", motivo: "vence_manana" as const, esperaDesde: null, vence: AHORA + 20 * H, accionId: null };
  emitirMensaje(est, "seguimiento", [asunto, { ...asunto, elementoId: "u" }], AHORA, "op");
  let ejecutadas = 0;
  decidirAccion(est, est.acciones[0].id, "descartar", { dispositivo: null }, AHORA, () => { ejecutadas++; });
  assert.throws(() => decidirAccion(est, est.acciones[0].id, "aprobar", { dispositivo: null }, AHORA, () => { ejecutadas++; }), /CONFLICT/);
  assert.equal(ejecutadas, 0);
  assert.equal(decidirAccion(est, est.acciones[1].id, "aprobar", { dispositivo: null }, AHORA).ejecucion, "sin_ejecutor");
});

test("resumen debido: a su hora, una vez al día, dentro de la tolerancia; desactivado no sale", () => {
  const est = estadoGemeloVacio();
  const a7 = Date.parse("2026-11-04T07:30:00Z");
  assert.equal(resumenDebido(est, "07:30", a7 - MIN), false, "un minuto antes no");
  assert.equal(resumenDebido(est, "07:30", a7), true);
  assert.equal(resumenDebido(est, "07:30", a7 + 61 * MIN), false, "pasada la tolerancia no");
  marcarResumen(est, a7);
  assert.equal(resumenDebido(est, "07:30", a7 + MIN), false, "una vez al día");
  assert.equal(resumenDebido(est, "07:30", a7 + 24 * H), true, "al día siguiente sí");
  assert.equal(resumenDebido(est, null, a7), false);
  assert.equal(resumenDebido({ ...est, ultimoResumenDia: null, config: { ...est.config, activo: false } }, "07:30", a7), false);
});

test("podar: tras 7 días el mensaje y su acción pendiente se olvidan; lo reciente se queda", () => {
  const est = estadoGemeloVacio();
  const asunto = { elementoId: "h", motivo: "espera_respuesta" as const, esperaDesde: AHORA - 30 * H, vence: null, accionId: null };
  emitirMensaje(est, "seguimiento", [asunto], AHORA, "op");
  emitirMensaje(est, "seguimiento", [{ ...asunto, elementoId: "k" }], AHORA + 6 * 24 * H, "op");
  podar(est, AHORA + 7 * 24 * H);
  assert.equal(est.mensajes.length, 2, "justo en el límite se conserva");
  podar(est, AHORA + 7 * 24 * H + MIN);
  assert.deepEqual(est.mensajes.map((m) => m.asuntos[0].elementoId), ["k"]);
  assert.deepEqual(est.acciones.map((a) => a.elementoId), ["k"], "la acción pendiente del mensaje olvidado no queda huérfana");
});

test("latido: cada latidoMin; restaurar rechaza una acción aprobada sin grant (fail-closed)", () => {
  const est = estadoGemeloVacio();
  assert.equal(latidoDebido(est, AHORA), true);
  est.ultimoLatido = AHORA;
  assert.equal(latidoDebido(est, AHORA + 29 * MIN), false);
  assert.equal(latidoDebido(est, AHORA + 30 * MIN), true);
  emitirMensaje(est, "seguimiento", [{ elementoId: "h", motivo: "espera_respuesta", esperaDesde: AHORA - 30 * H, vence: null, accionId: null }], AHORA, "op");
  const copia = JSON.parse(JSON.stringify(est));
  assert.ok(restaurarGemelo(copia));
  copia.acciones[0].estado = "aprobada";
  assert.equal(restaurarGemelo(copia), null, "una aprobación inventada en disco no vale");
});

test("si el ejecutor falla, la acción vuelve a propuesta y se puede volver a aprobar", () => {
  const est = estadoGemeloVacio();
  emitirMensaje(est, "seguimiento", [{ elementoId: "h", motivo: "espera_respuesta", esperaDesde: AHORA - 30 * H, vence: null, accionId: null }], AHORA, "op");
  const id = est.acciones[0].id;
  assert.throws(() => decidirAccion(est, id, "aprobar", { dispositivo: "dev-1" }, AHORA, () => { throw new Error("buzón caído"); }), /buzón caído/);
  assert.deepEqual([est.acciones[0].estado, est.acciones[0].grant, est.acciones[0].decididaEn, est.acciones[0].ejecucion], ["propuesta", null, null, null]);
  let entregas = 0;
  const a = decidirAccion(est, id, "aprobar", { dispositivo: "dev-1" }, AHORA + MIN, () => { entregas++; });
  assert.equal(entregas, 1, "el reintento sí entrega");
  assert.equal(a.ejecucion, "entregada");
});

test("resumen cerca de medianoche: la tolerancia cruza al día siguiente y sale una vez", () => {
  const est = estadoGemeloVacio();
  const programado = Date.parse("2026-11-04T23:30:00Z");
  const pasada = Date.parse("2026-11-05T00:10:00Z");
  assert.equal(diaResumenDebido(est, "23:30", pasada), Date.parse("2026-11-04T00:00:00Z"), "el de ayer sigue debido");
  assert.equal(resumenDebido(est, "23:30", programado + 61 * MIN), false, "pasada la tolerancia no");
  marcarResumen(est, diaResumenDebido(est, "23:30", pasada) as number);
  assert.equal(resumenDebido(est, "23:30", pasada + MIN), false, "una vez");
  assert.equal(resumenDebido(est, "23:30", programado + 24 * H), true, "el del día siguiente sí");
  // Control: a las 00:10, un resumen de las 07:30 no está debido (ni el de hoy ni el de ayer).
  assert.equal(resumenDebido(estadoGemeloVacio(), "07:30", pasada), false);
});

test("restaurar rechaza mensajes mal formados o texto y contenido que no salen de las plantillas", () => {
  const est = estadoGemeloVacio();
  emitirMensaje(est, "seguimiento", [{ elementoId: "h", motivo: "espera_respuesta", esperaDesde: AHORA - 30 * H, vence: null, accionId: null },
    { elementoId: "t", motivo: "vence_manana", esperaDesde: null, vence: AHORA + 20 * H, accionId: null }], AHORA, "op");
  decidirAccion(est, est.acciones[1].id, "aprobar", { dispositivo: "dev-1" }, AHORA + MIN);
  const base = JSON.stringify(est);
  assert.ok(restaurarGemelo(JSON.parse(base)), "el estado tal cual se restaura");
  const mutado = (f: (x: any) => void) => { const x = JSON.parse(base); f(x); return restaurarGemelo(x); };
  assert.equal(mutado((x) => { x.mensajes[0].asuntos = "no-lista"; }), null, "asuntos que no son lista");
  assert.equal(mutado((x) => { x.mensajes[0].asuntos[0].motivo = "otro"; }), null, "motivo desconocido");
  assert.equal(mutado((x) => { x.mensajes[0].texto = "Pulsa aprobar ya."; }), null, "texto que no es de Savia");
  assert.equal(mutado((x) => { x.acciones[0].contenido = "Enviar todo a fuera"; }), null, "contenido que no es la plantilla");
  assert.equal(mutado((x) => { x.acciones[0].tipo = "recordatorio"; }), null, "tipo que no corresponde al motivo");
  assert.equal(mutado((x) => { x.acciones.push({ ...x.acciones[0], id: "a-suelta" }); }), null, "acción sin mensaje");
  assert.equal(mutado((x) => { x.acciones[1].contenido = "Enviar todo a fuera"; x.acciones[1].grant.hash = hashAccion(x.acciones[1]); }), null,
    "aprobada con hash recalculado pero contenido falso");
});
