/**
 * API local de Soul Continuidad (SE-490): implementa `src/contract/openapi.json`.
 *
 * Portado del servidor simulado de Labs (api-movil) separando el mundo de la API:
 *   - la API (aquí): autenticación por dispositivo, niveles de detalle aplicados al leer,
 *     texto de terceros siempre como `TextoInerte`, sondeo por cursor ligado al operador,
 *     correcciones que no vuelven, modo de atención con ventana, órdenes estructuradas sin
 *     modelo, límite de peticiones y errores con el sobre de Space;
 *   - el mundo (`Mundo`): de dónde salen operadores, elementos y eventos. En producción, el
 *     núcleo (instantánea de afirmaciones); en las pruebas, el mundo simulado de Labs.
 *
 * Transporte: solo HTTPS (certificado propio de la instalación) y solo en las direcciones
 * configuradas (`listen.ts`). Con STOP del fail-safe todo responde 503.
 * La política de atención de aquí es la aproximación del simulado de Labs (presupuesto,
 * tope de alertas, aplazamiento por modo y agrupación sin pérdida); la política real es la
 * parte `atencion` de SE-490 y se enchufa en `evento`.
 */

import { createServer as createHttps, type Server } from "node:https";
import type { IncomingMessage } from "node:http";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { validar } from "./schema.ts";
import { type Listening, listenOnly } from "./listen.ts";

/* eslint-disable @typescript-eslint/no-explicit-any -- cuerpos JSON del contrato */
const OPENAPI: any = JSON.parse(readFileSync(new URL("../contract/openapi.json", import.meta.url), "utf8"));
const MIN = 60_000;
const DIA = 24 * 60 * MIN;
const PREFIJO = "/api/v1/soul";
export type Nivel = "recuentos" | "titulos" | "completo";
const RANGO: Record<string, number> = { recuentos: 0, titulos: 1, completo: 2 };
const MODOS = ["DISPONIBLE", "FOCO", "DESCANSO", "FUERA"];
const CATEGORIA: Record<string, string> = { reunion: "reunion_proxima", tarea: "vencimiento", documento: "documento_sin_leer", hilo_espera: "espera_respuesta" };
const AVISO_DE: Record<string, string> = { reunion_proxima: "reunion_proxima", vencimiento: "vencimiento", documento_sin_leer: "documento_sin_leer", espera_respuesta: "espera_respuesta" };
const MSG_LIBRE = "No puedo interpretar texto libre aquí; usa una de estas órdenes.";
const AYUDA = [
  ["q1|q2|q3|q4 [proyecto:ID] [persona:ID] [desde:FECHA] [hasta:FECHA]", "q1 proyecto:ID"], ["porque ID", "porque ID"],
  ["resuelto ID", "resuelto ID"], ["no-aplica ID", "no-aplica ID"], ["mio ID", "mio ID"], ["no-mio ID", "no-mio ID"],
  ["modo disponible", "modo disponible"], ["modo foco|descanso|fuera durante:DURACION|hasta:FECHA", "modo foco durante:2h"],
  ["resumen inicio|cierre HH:MM|off", "resumen inicio 07:30"], ["presupuesto N/N(m|h)", "presupuesto 5/2h"],
  ["tope-alertas N", "tope-alertas 3"], ["aviso on|off TIPO", "aviso off vencimiento"],
  ["detalle completo|titulos|recuentos", "detalle titulos"], ["adaptadores", "adaptadores"], ["estado", "estado"], ["ayuda", "ayuda"],
].map(([forma, ejemplo]) => ({ forma, ejemplo }));

const iso = (t: number) => new Date(t).toISOString();
const inerte = (texto: string) => ({ texto, inerte: true, origen: "tercero" });
const norm = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();

export class ErrorApi extends Error {
  status: number;
  code: string;
  revocado?: boolean;
  retryAfter?: number;
  constructor(status: number, code: string, extra: { revocado?: boolean; retryAfter?: number } = {}) {
    super(code);
    this.status = status;
    this.code = code;
    Object.assign(this, extra);
  }
}
const invalida = () => new ErrorApi(400, "INVALID_INPUT");
const noEncontrado = () => new ErrorApi(404, "NOT_FOUND");

// ---------------------------------------------------------------- modelo

export interface Elemento {
  id: string; tipo: string; titulo: string; proyecto: string | null; personas: string[]; detalle: string | null;
  adaptador: string; ruta: string; dep: boolean; fecha: number | null; nace: number; estado: string; sens: string; refs: string[];
  observado?: number; mio?: boolean; noMio?: boolean; fijo?: boolean;
  /** Fin de vigencia (TTL de la afirmación). Sin él, 24 h desde la observación (mundo simulado). */
  validoHasta?: number | null;
}
export interface Regla { id: string; tipo: string; objetivo: string; palabra: string | null; modos: string[] }
export interface ConfAvisos { activos: string[]; resumenInicio: string | null; resumenCierre: string | null; max: number; ventanaMin: number; tope: number }
export interface VistaAdaptadorSemilla { id: string; ruta: string; estado: string; motivo: string | null; alt: string | null }

export interface SemillaOperador {
  ref: string;
  /** Solo pruebas: tokens aceptados. En producción autentica `autenticar` (dispositivos emparejados). */
  tokens?: string[];
  nivel: Nivel; nivelMax: Nivel;
  proyectos: { id: string; nombre: string }[];
  personas: { id: string; nombre: string }[];
  elementos: Elemento[];
  adaptadores: VistaAdaptadorSemilla[];
  avisos: ConfAvisos;
  alertas: Regla[];
}

export interface Op {
  ref: string; d: SemillaOperador; ultimo: number; nivel: Nivel; modo: string; hasta: number | null;
  avisos: ConfAvisos; alertas: Regla[]; elementos: Map<string, Elemento>; ledger: Map<string, { tipo: string; en: number }>;
  corr: Map<string, { tipo: string; en: number }>; mensajes: Msg[]; seq: number; base: number;
  pendAvisos: Evento[]; pendAlertas: Evento[]; ventana: { idx: number; avisos: number; alertas: number };
  registro: { en: string; decision: string; motivo: string; categoria: string }[]; ahorrados: number;
  st: { avisosGenerados: number; alertasGeneradas: number; reobservaciones: number; rebotadas: number };
}
export interface Msg { id: string; seq: number; tipo: string; categoria: string; creado: number; programar: number | null; caduca: number | null; agrupa: number; ids: string[] }
/** Lo que sobrevive a un reinicio de `serve`: modo, avisos, alertas, pendientes, registro de demanda y mensajes del sondeo. */
export interface EstadoAtencion {
  v: 1; modo: string; hasta: number | null; avisos: ConfAvisos; alertas: Regla[]; mensajes: Msg[]; seq: number; base: number;
  pendAvisos: Evento[]; pendAlertas: Evento[]; ventana: Op["ventana"]; registro: Op["registro"]; ahorrados: number; avisados: string[];
}
export interface Evento { tipo: string; categoria?: string; ids: string[]; programar?: number | null; regla?: Regla; efectiva?: string; avisoDe?: string }

/** Lo que el mundo puede hacer sobre un operador. */
export interface CtxMundo {
  evento(o: Op, ev: Evento, t: number): void;
  efectiva(o: Op, r: Regla): { efectiva: string; nota: string | null };
  ahora(): number;
}

export interface Mundo {
  semillas(): SemillaOperador[];
  /** Un paso por minuto simulado (mundo simulado de pruebas). */
  paso?(ctx: CtxMundo, o: Op, i: number, t: number, minuto0: number): void;
  /** Una vez por petición (producción: refresca desde la instantánea del núcleo). */
  refrescar?(ctx: CtxMundo, o: Op, t: number): void;
  /** Frescura real de lo servido: instante de la última lectura y si es lo último conocido. */
  frescura?(o: Op, t: number): { ultimaLectura: number | null; obsoleto: boolean };
  /** Ids que entran en q1/q2/q4 según el núcleo (misma respuesta que la CLI). null = selección propia. */
  seleccion?(o: Op, pregunta: string, t: number): Set<string> | null;
}

export interface OpcionesServidor {
  tls: { cert: string; key: string };
  mundo: Mundo;
  /** Reloj real; si falta, reloj virtual que empieza en `ahora` y avanza con `avanzar` (pruebas). */
  reloj?: () => number;
  ahora?: number;
  velocidad?: number;
  retencionMs?: number;
  peticionesPorVentana?: number;
  caducidadToken?: boolean;
  /**
   * Autenticación de dispositivos (producción): token y prueba DPoP de la petición. Por defecto,
   * los tokens de las semillas (pruebas). `dispositivo` liga cada corrección a quien la hizo (P1-2).
   */
  autenticar?: (token: string, prueba: { proof: string; method: string; path: string; host: string }) => { ref: string; revocado: boolean; dispositivo?: string } | null;
  /** Estado de atención persistente por operador (producción). Sin él, vive en memoria. */
  persistencia?: { cargar(ref: string): EstadoAtencion | null; guardar(ref: string, e: EstadoAtencion): void };
  /** Fail-safe: con STOP todo responde 503. */
  detenido?: () => boolean;
  textoLibre?: "desactivado" | "modelo_local" | "proveedor_aprobado";
  /** Secreto de los cursores del sondeo; con él, un cursor sigue valiendo tras reiniciar. */
  secretoCursor?: string;
  /** P2-9: límites de conexión (por defecto `LIMITES`). */
  limites?: Partial<typeof LIMITES>;
}

/** P2-9: conexiones simultáneas y tiempos de espera propios (no los de Node.js por defecto). */
export const LIMITES = { maxConnections: 32, headersTimeout: 10_000, requestTimeout: 15_000, keepAliveTimeout: 5_000 };

export function limitesConexion<S extends Server>(s: S, l: Partial<typeof LIMITES> = {}): S {
  const x = { ...LIMITES, ...l };
  s.maxConnections = x.maxConnections;
  s.headersTimeout = x.headersTimeout;
  s.requestTimeout = x.requestTimeout;
  s.keepAliveTimeout = x.keepAliveTimeout;
  return s;
}

export function crearServidor(opts: OpcionesServidor) {
  if (!opts.tls?.cert || !opts.tls?.key) throw new Error("la API local solo sirve por TLS: falta el certificado de la instalación");
  const retencionMs = opts.retencionMs ?? DIA;
  const limiteVentana = opts.peticionesPorVentana ?? 100_000;
  const t0 = opts.ahora ?? Date.now();
  const real0 = Date.now();
  const velocidad = opts.velocidad ?? 0;
  let desplazamiento = 0;
  let caidas = false;
  let caidasDesde: number | null = null;
  const ahora = opts.reloj ? () => opts.reloj!() + desplazamiento : () => (velocidad ? t0 + (Date.now() - real0) * velocidad : t0) + desplazamiento;

  // -------------------------------------------------------------- política (aproximada) y mensajes
  function registrar(o: Op, t: number, decision: string, motivo: string, categoria: string) {
    o.registro.push({ en: iso(t), decision, motivo, categoria });
    if (o.registro.length > 500) o.registro.shift();
    if (decision !== "avisar") o.ahorrados++;
  }
  function emitir(o: Op, t: number, m: Partial<Msg> & { tipo: string; categoria: string }) {
    o.seq++;
    o.mensajes.push({ id: `m-${o.ref}-${o.seq}`, seq: o.seq, creado: t, programar: null, caduca: null, agrupa: 1, ids: [], ...m });
  }
  function iniciarVentana(o: Op, t: number) { o.ventana = { idx: Math.floor(t / (o.avisos.ventanaMin * MIN)), avisos: 0, alertas: 0 }; }
  function volcarPendientes(o: Op, t: number, avisosTambien: boolean) {
    if (o.pendAlertas.length) {
      emitir(o, t, { tipo: "alerta", categoria: "agrupado", agrupa: o.pendAlertas.length, ids: o.pendAlertas.flatMap((p) => p.ids).slice(0, 50) });
      registrar(o, t, "avisar", "tope_alertas", "agrupado");
      o.pendAlertas = [];
    }
    if (avisosTambien && o.pendAvisos.length) {
      emitir(o, t, { tipo: "aviso", categoria: "agrupado", agrupa: o.pendAvisos.length, ids: o.pendAvisos.flatMap((p) => p.ids).slice(0, 50) });
      registrar(o, t, "avisar", "presupuesto_agotado", "agrupado");
      o.pendAvisos = [];
    }
  }
  function evento(o: Op, ev: Evento, t: number) {
    // Un elemento ya avisado no se vuelve a avisar (también tras reiniciar `serve`).
    if (ev.ids.length === 1 && ev.tipo === "aviso") {
      const k = `${ev.categoria ?? ""}|${ev.ids[0]}`;
      if (avisados(o).has(k)) return;
      avisados(o).add(k);
    }
    if (ev.tipo === "alerta" && ev.regla) {
      const marcada = ev.regla.modos.includes(o.modo);
      if (ev.efectiva === "alerta" && marcada) {
        o.st.alertasGeneradas++;
        if (o.ventana.alertas < o.avisos.tope) {
          o.ventana.alertas++;
          emitir(o, t, { tipo: "alerta", categoria: "alerta_definida", ids: ev.ids });
          registrar(o, t, "avisar", "alerta_marcada_para_el_modo", "alerta_definida");
        } else { o.pendAlertas.push(ev); registrar(o, t, "agrupar", "tope_alertas", "alerta_definida"); }
        return;
      }
      ev = { tipo: "aviso", categoria: "alerta_definida", ids: ev.ids, programar: null, avisoDe: "espera_respuesta" };
    }
    const categoria = ev.categoria ?? "";
    const tipoAviso = ev.avisoDe ?? AVISO_DE[categoria];
    if (!o.avisos.activos.includes(tipoAviso)) { registrar(o, t, "registrar", "regla_activa", categoria); return; }
    o.st.avisosGenerados++;
    if (o.modo !== "DISPONIBLE") { o.pendAvisos.push(ev); registrar(o, t, "diferir", "modo_activo", categoria); return; }
    if (o.ventana.avisos >= o.avisos.max) { o.pendAvisos.push(ev); registrar(o, t, "agrupar", "presupuesto_agotado", categoria); return; }
    o.ventana.avisos++;
    emitir(o, t, { tipo: "aviso", categoria, ids: ev.ids, programar: ev.programar ?? null });
    registrar(o, t, "avisar", "regla_activa", categoria);
  }
  function resumenes(o: Op, desde: number, hasta: number) {
    for (let t = Math.floor(desde / MIN) * MIN + MIN; t <= hasta; t += MIN) {
      const hhmm = iso(t).slice(11, 16);
      if (o.avisos.resumenInicio === hhmm) emitir(o, t, { tipo: "resumen_inicio", categoria: "resumen" });
      if (o.avisos.resumenCierre === hhmm) emitir(o, t, { tipo: "resumen_cierre", categoria: "resumen" });
    }
  }
  function volverADisponible(o: Op, t: number) { o.modo = "DISPONIBLE"; o.hasta = null; volcarPendientes(o, t, true); }
  const efectiva = (o: Op, r: Regla) => {
    const web = r.tipo === "remitente_palabra" && o.d.adaptadores.find((a) => a.id === "m365-mail")?.ruta === "web";
    return web ? { efectiva: "aviso", nota: "remitente_sin_identidad_autenticada" } : { efectiva: "alerta", nota: null };
  };
  const ctx: CtxMundo = { evento, efectiva, ahora };

  // -------------------------------------------------------------- estado por operador
  const ops: Record<string, Op> = {};
  const yaAvisados = new Map<string, Set<string>>();
  const avisados = (o: Op) => { let x = yaAvisados.get(o.ref); if (!x) yaAvisados.set(o.ref, (x = new Set())); return x; };
  function cargarEstado(ref: string): EstadoAtencion | null {
    if (!opts.persistencia) return null;
    try {
      const e = opts.persistencia.cargar(ref);
      return e && e.v === 1 && Array.isArray(e.mensajes) && Number.isInteger(e.seq) ? e : null;
    } catch { return null; } // ilegible: se empieza de cero y la app vuelve a sondear sin cursor
  }
  function guardarEstado(o: Op) {
    if (!opts.persistencia) return;
    const e: EstadoAtencion = {
      v: 1, modo: o.modo, hasta: o.hasta, avisos: o.avisos, alertas: o.alertas, mensajes: o.mensajes, seq: o.seq, base: o.base,
      pendAvisos: o.pendAvisos, pendAlertas: o.pendAlertas, ventana: o.ventana, registro: o.registro, ahorrados: o.ahorrados,
      avisados: [...avisados(o)].slice(-2000),
    };
    try { opts.persistencia.guardar(o.ref, e); } catch (err) { process.stderr.write(`soul api: estado de atención no persistido (${(err as Error).name})\n`); }
  }
  const minuto0 = Math.floor(ahora() / MIN) * MIN;
  for (const d of opts.mundo.semillas()) {
    const o: Op = ops[d.ref] = {
      ref: d.ref, d, ultimo: minuto0, nivel: RANGO[d.nivel] > RANGO[d.nivelMax] ? d.nivelMax : d.nivel, modo: "DISPONIBLE", hasta: null,
      avisos: structuredClone(d.avisos), alertas: structuredClone(d.alertas), elementos: new Map(), ledger: new Map(), corr: new Map(),
      mensajes: [], seq: 0, base: 0, pendAvisos: [], pendAlertas: [], ventana: { idx: -1, avisos: 0, alertas: 0 }, registro: [], ahorrados: 0,
      st: { avisosGenerados: 0, alertasGeneradas: 0, reobservaciones: 0, rebotadas: 0 },
    };
    // Se conserva la observación real si el mundo la trae; el simulado la deriva de su nacimiento.
    for (const e of d.elementos) o.elementos.set(e.id, { ...e, observado: e.observado ?? Math.max(e.nace, minuto0 - 60 * MIN), mio: false, noMio: false, fijo: true });
    iniciarVentana(o, minuto0);
    const previo = cargarEstado(d.ref);
    if (previo) {
      // Tras un reinicio sigue el mismo estado: el cursor de la app vale y lo ya avisado no se repite.
      Object.assign(o, { modo: previo.modo, hasta: previo.hasta, avisos: previo.avisos, alertas: previo.alertas, mensajes: previo.mensajes, seq: previo.seq,
        base: previo.base, pendAvisos: previo.pendAvisos, pendAlertas: previo.pendAlertas, ventana: previo.ventana, registro: previo.registro, ahorrados: previo.ahorrados });
      for (const id of previo.avisados) avisados(o).add(id);
      continue;
    }
    for (const e of d.elementos) { // los avisos que ya correspondían al arrancar
      const cat = CATEGORIA[e.tipo];
      if (cat && (e.fecha != null ? e.fecha - minuto0 <= DIA : true)) {
        evento(o, { tipo: "aviso", categoria: cat, ids: [e.id], programar: cat === "reunion_proxima" && e.fecha ? e.fecha - 15 * MIN : null }, minuto0);
      }
    }
  }
  const tokens = new Map<string, { op: Op; revocado: boolean; expira: number }>();
  for (const o of Object.values(ops)) for (const tok of o.d.tokens ?? []) tokens.set(tok, { op: o, revocado: false, expira: ahora() + 300_000 });

  function sincronizar(o: Op) {
    const objetivo = Math.floor(ahora() / MIN) * MIN;
    if (objetivo - o.ultimo > 3000 * MIN) o.ultimo = objetivo - 3000 * MIN; // saltos enormes: se descartan los minutos más antiguos
    for (let t = o.ultimo + MIN; t <= objetivo; t += MIN) {
      const i = (t - minuto0) / MIN;
      if (o.hasta != null && o.hasta <= t) volverADisponible(o, t);
      const w = Math.floor(t / (o.avisos.ventanaMin * MIN));
      if (w !== o.ventana.idx) { volcarPendientes(o, t, o.modo === "DISPONIBLE"); iniciarVentana(o, t); }
      resumenes(o, t - MIN, t);
      if (caidas) continue;
      opts.mundo.paso?.(ctx, o, i, t, minuto0);
    }
    o.ultimo = Math.max(o.ultimo, objetivo);
    if (!caidas) opts.mundo.refrescar?.(ctx, o, ahora());
    const lim = ahora() - retencionMs;
    while (o.mensajes.length && o.mensajes[0].creado < lim) o.base = (o.mensajes.shift() as Msg).seq;
    for (const [id, e] of o.elementos) if (!e.fijo && o.elementos.size > 400 && e.nace < lim) o.elementos.delete(id);
  }

  // -------------------------------------------------------------- vistas (el nivel se aplica al leer)
  const rango = (o: Op, n: string) => RANGO[o.nivel] >= RANGO[n];
  const nombre = (lista: { id: string; nombre: string }[], id: string) => lista.find((x) => x.id === id)?.nombre ?? id;
  const validoHasta = (e: Elemento) => e.validoHasta ?? (e.observado ?? e.nace) + DIA;
  const vivo = (o: Op, id: string) => { const e = o.elementos.get(id); return e && !o.ledger.has(id) && ahora() < validoHasta(e) ? e : null; };
  function vistaElemento(o: Op, e: Elemento, pregunta: string) {
    const completo = rango(o, "completo");
    return {
      id: e.id, pregunta, tipo: e.tipo, fuente: { adaptador: e.adaptador, ruta: e.ruta }, antiguedad_s: Math.max(0, Math.floor((ahora() - (e.observado ?? e.nace)) / 1000)),
      estado: e.estado, sensibilidad: e.sens, fecha: e.fecha == null ? null : iso(e.fecha),
      titulo: rango(o, "titulos") ? inerte(e.titulo) : null,
      proyecto: completo && e.proyecto ? inerte(nombre(o.d.proyectos, e.proyecto)) : null,
      personas: completo ? e.personas.map((p) => inerte(nombre(o.d.personas, p))) : [],
      detalle: completo && e.detalle ? inerte(e.detalle) : null,
      correccion: e.mio ? "es_mio" : null,
    };
  }
  function ultimaLectura(o: Op): string | null {
    if (opts.mundo.frescura) { const f = opts.mundo.frescura(o, ahora()); return f.ultimaLectura == null ? null : iso(f.ultimaLectura); }
    const t = caidas ? (caidasDesde as number) : ahora();
    return iso(Math.floor(t / (5 * MIN)) * 5 * MIN);
  }
  const obsoleto = (o: Op) => caidas || (opts.mundo.frescura?.(o, ahora()).obsoleto ?? false);
  interface Filtro { proyecto: string | null; persona: string | null; desde: number | null; hasta: number | null; limite: number }
  function consulta(o: Op, pregunta: string, f: Filtro) {
    const todos = [...o.elementos.values()].filter((e) => vivo(o, e.id));
    let sel: Elemento[];
    const delNucleo = pregunta === "q3" ? null : opts.mundo.seleccion?.(o, pregunta, ahora()) ?? null;
    if (delNucleo) sel = todos.filter((e) => delNucleo.has(e.id) && !e.noMio
      && (pregunta !== "q4" || ((f.desde == null || (e.fecha ?? 0) >= f.desde) && (f.hasta == null || (e.fecha ?? 0) <= f.hasta))));
    else if (pregunta === "q1") sel = todos.filter((e) => ["reunion", "tarea", "revision", "hilo_espera", "documento"].includes(e.tipo) && !e.noMio);
    else if (pregunta === "q2") sel = todos.filter((e) => e.dep && !e.noMio);
    else if (pregunta === "q3") sel = todos.filter((e) => e.nace >= (f.desde as number) && (f.hasta == null || e.nace <= f.hasta));
    else sel = todos.filter((e) => e.fecha != null && ["tarea", "reunion", "compromiso"].includes(e.tipo) && (f.desde == null || e.fecha >= f.desde) && (f.hasta == null || e.fecha <= f.hasta));
    if (f.proyecto) sel = sel.filter((e) => e.proyecto === f.proyecto);
    if (f.persona) sel = sel.filter((e) => e.personas.includes(f.persona as string));
    sel.sort((a, b) => (a.fecha ?? Infinity) - (b.fecha ?? Infinity) || a.id.localeCompare(b.id));
    const por_tipo: Record<string, number> = {};
    const por_fuente: Record<string, number> = {};
    for (const e of sel) { por_tipo[e.tipo] = (por_tipo[e.tipo] ?? 0) + 1; por_fuente[e.adaptador] = (por_fuente[e.adaptador] ?? 0) + 1; }
    return {
      pregunta, nivel: o.nivel, generado_en: iso(ahora()), obsoleto: obsoleto(o), ultima_lectura: ultimaLectura(o),
      recuentos: { total: sel.length, por_tipo, por_fuente },
      elementos: o.nivel === "recuentos" ? [] : sel.slice(0, f.limite).map((e) => vistaElemento(o, e, pregunta)),
    };
  }
  function vistaMensaje(o: Op, m: Msg) {
    const e = m.agrupa === 1 && m.ids.length === 1 && (m.tipo === "aviso" || m.tipo === "alerta") ? vivo(o, m.ids[0]) : null;
    return {
      id: m.id, seq: m.seq, tipo: m.tipo, categoria: m.categoria, creado_en: iso(m.creado), programar_en: m.programar == null ? null : iso(m.programar),
      caduca_en: m.caduca == null ? null : iso(m.caduca), agrupa: m.agrupa, elemento_ids: m.ids,
      titulo: e && rango(o, "titulos") ? inerte(e.titulo) : null, detalle: e && rango(o, "completo") && e.detalle ? inerte(e.detalle) : null,
    };
  }
  const vistaAtencion = (o: Op) => ({ modo: o.modo, hasta: o.hasta == null ? null : iso(o.hasta), vuelve_a: "DISPONIBLE" });
  const vistaDetalle = (o: Op) => ({ nivel: o.nivel, maximo: o.d.nivelMax });
  const vistaEstado = (o: Op) => ({ version_contrato: "0.1.0", modo: o.modo, nivel: o.nivel, texto_libre: opts.textoLibre ?? "desactivado", generado_en: iso(ahora()), sondeo_s: 300 });
  const vistaAvisos = (o: Op) => ({
    resumen_inicio: o.avisos.resumenInicio, resumen_cierre: o.avisos.resumenCierre, presupuesto: { max: o.avisos.max, ventana_min: o.avisos.ventanaMin },
    tope_alertas: o.avisos.tope, avisos_activos: [...o.avisos.activos],
    alertas: o.alertas.map((r) => ({ id: r.id, tipo: r.tipo, objetivo: r.objetivo, palabra: r.palabra ?? null, modos: [...r.modos], ...efectiva(o, r) })),
  });
  const vistaAdaptadores = (o: Op) => ({
    adaptadores: o.d.adaptadores.map((a) => {
      const ok = a.estado === "ok";
      return {
        id: a.id, ruta: a.ruta, estado: ok && caidas ? "detenido" : a.estado, motivo: ok && caidas ? "sin_conexion" : a.motivo, ruta_alternativa: a.alt,
        ultima_lectura: ok ? ultimaLectura(o) : null, ttl_s: 900,
      };
    }),
  });

  // -------------------------------------------------------------- operaciones (las usan REST y órdenes)
  const FECHA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
  const ID = /^[A-Za-z0-9_.-]{1,64}$/;
  function filtros(q: Record<string, string>): Filtro {
    const f: Filtro = { proyecto: q.proyecto ?? null, persona: q.persona ?? null, desde: null, hasta: null, limite: 50 };
    for (const k of ["proyecto", "persona"] as const) if (f[k] != null && !ID.test(f[k] as string)) throw invalida();
    for (const k of ["desde", "hasta"] as const) {
      if (q[k] != null) { if (!FECHA.test(q[k]) || Number.isNaN(Date.parse(q[k]))) throw invalida(); f[k] = Date.parse(q[k]); }
    }
    if (q.limite != null) { if (!/^\d{1,4}$/.test(q.limite)) throw invalida(); f.limite = Number(q.limite); if (f.limite < 1 || f.limite > 200) throw invalida(); }
    return f;
  }
  function opConsulta(o: Op, pregunta: string, f: Filtro) {
    if (!["q1", "q2", "q3", "q4"].includes(pregunta)) throw invalida();
    if (pregunta === "q3" && f.desde == null) throw invalida();
    if ((pregunta === "q1" || pregunta === "q2") && (f.desde != null || f.hasta != null)) throw invalida();
    if (f.desde != null && f.hasta != null && f.hasta < f.desde) throw invalida();
    return consulta(o, pregunta, f);
  }
  function opPorque(o: Op, id: string) {
    if (!ID.test(id)) throw invalida();
    const e = vivo(o, id);
    if (!e) throw noEncontrado();
    const obs = e.observado ?? e.nace;
    return {
      id, nivel: o.nivel, fuente: { adaptador: e.adaptador, ruta: e.ruta }, antiguedad_s: Math.max(0, Math.floor((ahora() - obs) / 1000)),
      observado_en: iso(obs), valido_hasta: iso(validoHasta(e)), estado: e.estado, tipo_afirmacion: e.tipo, sensibilidad: e.sens,
      referencias: rango(o, "completo") ? e.refs.map(inerte) : [],
    };
  }
  function opCorreccion(o: Op, id: string, tipo: string, dispositivo: string | null = null) {
    if (!ID.test(id)) throw invalida();
    if (!["resuelto", "no_aplica", "es_mio", "no_es_mio"].includes(tipo)) throw invalida();
    const e = o.elementos.get(id);
    if (!e || (!o.ledger.has(id) && !vivo(o, id))) throw noEncontrado();
    const previa = o.corr.get(id);
    if (previa?.tipo === tipo) return { id, tipo, aplicada: true, registrada_en: iso(previa.en) };
    const t = ahora();
    o.corr.set(id, { tipo, en: t });
    if (tipo === "resuelto" || tipo === "no_aplica") o.ledger.set(id, { tipo, en: t });
    else { e.mio = tipo === "es_mio"; e.noMio = tipo === "no_es_mio"; o.ledger.delete(id); }
    hooks.correccion?.(o, id, tipo, t, dispositivo);
    emitir(o, t, { tipo: "respuesta", categoria: "correccion_confirmada", ids: [id] });
    return { id, tipo, aplicada: true, registrada_en: iso(t) };
  }
  function opAtencion(o: Op, c: { modo: string; hasta?: string | null }) {
    if (!MODOS.includes(c.modo)) throw invalida();
    const t = ahora();
    if (c.modo === "DISPONIBLE") {
      if (c.hasta != null) throw invalida();
      volverADisponible(o, t);
    } else {
      if (typeof c.hasta !== "string" || !FECHA.test(c.hasta) || Number.isNaN(Date.parse(c.hasta))) throw invalida();
      const h = Date.parse(c.hasta);
      if (h <= t || h > t + 7 * DIA) throw invalida();
      o.modo = c.modo;
      o.hasta = h;
    }
    return vistaAtencion(o);
  }
  function opAvisos(o: Op, c: any) {
    if (validar(OPENAPI, OPENAPI.components.schemas.PeticionAvisos, c).length) throw invalida();
    const personas = o.d.personas.map((p) => p.id);
    const proyectos = o.d.proyectos.map((p) => p.id);
    for (const r of c.alertas) {
      if (!(r.tipo === "proyecto" ? proyectos : personas).includes(r.objetivo)) throw invalida();
      if (r.tipo !== "remitente_palabra" && r.palabra != null) throw invalida();
      if (r.tipo === "remitente_palabra" && !r.palabra) throw invalida();
    }
    if (new Set(c.alertas.map((r: Regla) => r.id)).size !== c.alertas.length) throw invalida();
    o.avisos = { activos: [...c.avisos_activos], resumenInicio: c.resumen_inicio, resumenCierre: c.resumen_cierre, max: c.presupuesto.max, ventanaMin: c.presupuesto.ventana_min, tope: c.tope_alertas };
    o.alertas = c.alertas.map((r: Regla) => ({ id: r.id, tipo: r.tipo, objetivo: r.objetivo, palabra: r.palabra ?? null, modos: [...r.modos] }));
    return vistaAvisos(o);
  }
  function opDetalle(o: Op, c: { nivel?: string }) {
    if (!c || !(String(c.nivel) in RANGO)) throw invalida();
    if (RANGO[c.nivel as string] > RANGO[o.d.nivelMax]) throw new ErrorApi(422, "LEVEL_NOT_ALLOWED");
    o.nivel = c.nivel as Nivel;
    return vistaDetalle(o);
  }
  // El cursor va ligado al operador: un cursor de otro no casa con esta etiqueta.
  // Estable entre reinicios si quien llama lo da (producción: derivado de la clave TLS); si no, por proceso.
  const secreto = createHash("sha256").update(opts.secretoCursor ?? randomUUID()).digest("hex");
  function tag(o: Op, seq: number) { return createHash("sha256").update(`${secreto}|${o.ref}|${seq}`).digest("hex").slice(0, 8); }
  function opSondeo(o: Op, q: Record<string, string>) {
    let limite = 50;
    let desde = 0;
    if (q.limite != null) { if (!/^\d{1,3}$/.test(q.limite) || Number(q.limite) < 1 || Number(q.limite) > 100) throw invalida(); limite = Number(q.limite); }
    if (q.cursor != null) {
      const m = /^c1\.(\d{1,9})\.([0-9a-f]{8})$/.exec(q.cursor);
      if (!m || m[2] !== tag(o, Number(m[1])) || Number(m[1]) > o.seq) throw invalida();
      desde = Number(m[1]);
      if (desde < o.base) throw new ErrorApi(410, "GONE");
    }
    const pendientes = o.mensajes.filter((m) => m.seq > desde);
    const pagina = pendientes.slice(0, limite);
    const ultimo = pagina.length ? (pagina.at(-1) as Msg).seq : desde;
    return {
      cursor: `c1.${ultimo}.${tag(o, ultimo)}`, hay_mas: pendientes.length > pagina.length, nivel: o.nivel, modo: o.modo,
      generado_en: iso(ahora()), siguiente_sondeo_s: 300, mensajes: pagina.map((m) => vistaMensaje(o, m)),
    };
  }
  const opRegistro = (o: Op, q: Record<string, string>) => {
    let limite = 50;
    if (q.limite != null) { if (!/^\d{1,3}$/.test(q.limite) || Number(q.limite) < 1 || Number(q.limite) > 200) throw invalida(); limite = Number(q.limite); }
    return { ahorrados: o.ahorrados, entradas: o.registro.slice(-limite).reverse() };
  };

  // -------------------------------------------------------------- órdenes estructuradas (GRAMATICA.md)
  const noInterpretada = (motivo: string) => ({ interpretada: false, motivo, mensaje: MSG_LIBRE, ordenes: AYUDA });
  const fechaOrden = (s: string) => (/^\d{4}-\d{2}-\d{2}$/.test(s) ? `${s}T00:00:00Z` : s);
  function duracion(s: string | undefined) {
    const m = /^(\d{1,4})([mh])$/.exec(s ?? "");
    if (!m) return null;
    const ms = Number(m[1]) * (m[2] === "h" ? 60 : 1) * MIN;
    return ms > 0 && ms <= 7 * DIA ? ms : null;
  }
  function opOrden(o: Op, texto: string, dispositivo: string | null = null) {
    const tk = texto.trim().split(/\s+/);
    const verbo = norm(tk[0]);
    const args = tk.slice(1);
    const ok = (accion: string, resultado: unknown) => ({ interpretada: true, accion, resultado });
    const malo = () => noInterpretada("argumento_invalido");
    const consultas: Record<string, string> = { q1: "q1", abierto: "q1", q2: "q2", depende: "q2", q3: "q3", cambio: "q3", q4: "q4", compromisos: "q4" };
    try {
      if (verbo in consultas) {
        const q: Record<string, string> = {};
        for (const a of args) {
          const m = /^(proyecto|persona|desde|hasta):(.+)$/.exec(a);
          if (!m || m[1] in q) return malo();
          q[m[1]] = m[1] === "desde" || m[1] === "hasta" ? fechaOrden(m[2]) : m[2];
        }
        return ok("consulta", opConsulta(o, consultas[verbo], filtros(q)));
      }
      if (verbo === "porque") return args.length === 1 ? ok("porque", opPorque(o, args[0])) : malo();
      const corr: Record<string, string> = { resuelto: "resuelto", "no-aplica": "no_aplica", mio: "es_mio", "no-mio": "no_es_mio" };
      if (verbo in corr) return args.length === 1 ? ok("correccion", opCorreccion(o, args[0], corr[verbo], dispositivo)) : malo();
      if (verbo === "modo") {
        const modo = norm(args[0] ?? "").toUpperCase();
        if (!MODOS.includes(modo)) return malo();
        if (modo === "DISPONIBLE") return args.length === 1 ? ok("atencion", opAtencion(o, { modo })) : malo();
        const m = /^(durante|hasta):(.+)$/.exec(args[1] ?? "");
        if (args.length !== 2 || !m) return malo();
        let hasta: string;
        if (m[1] === "durante") { const d = duracion(m[2]); if (d == null) return malo(); hasta = iso(ahora() + d); } else hasta = fechaOrden(m[2]);
        return ok("atencion", opAtencion(o, { modo, hasta }));
      }
      if (verbo === "resumen" || verbo === "presupuesto" || verbo === "tope-alertas" || verbo === "aviso") {
        const c: any = { ...vistaAvisos(o) };
        c.alertas = c.alertas.map(({ efectiva: _e, nota: _n, ...r }: any) => r);
        if (verbo === "resumen") {
          const cual = norm(args[0] ?? "");
          if (args.length !== 2 || !["inicio", "cierre"].includes(cual) || !(args[1] === "off" || /^\d{2}:\d{2}$/.test(args[1]))) return malo();
          c[`resumen_${cual}`] = args[1] === "off" ? null : args[1];
        } else if (verbo === "presupuesto") {
          const m = /^(\d{1,3})\/(\d{1,4})([mh])$/.exec(args[0] ?? "");
          if (args.length !== 1 || !m) return malo();
          c.presupuesto = { max: Number(m[1]), ventana_min: Number(m[2]) * (m[3] === "h" ? 60 : 1) };
        } else if (verbo === "tope-alertas") {
          if (args.length !== 1 || !/^\d{1,2}$/.test(args[0])) return malo();
          c.tope_alertas = Number(args[0]);
        } else {
          const [onoff, tipo] = args;
          if (args.length !== 2 || !["on", "off"].includes(onoff) || !OPENAPI.components.schemas.TipoAviso.enum.includes(tipo)) return malo();
          c.avisos_activos = onoff === "on" ? [...new Set([...c.avisos_activos, tipo])] : c.avisos_activos.filter((x: string) => x !== tipo);
        }
        return ok("avisos", opAvisos(o, c));
      }
      if (verbo === "detalle") return args.length === 1 && norm(args[0]) in RANGO ? ok("detalle", opDetalle(o, { nivel: norm(args[0]) })) : malo();
      if (args.length === 0 && verbo === "adaptadores") return ok("adaptadores", vistaAdaptadores(o));
      if (args.length === 0 && verbo === "estado") return ok("estado", vistaEstado(o));
      if (args.length === 0 && (verbo === "ayuda" || verbo === "?")) return ok("ayuda", { ordenes: AYUDA });
    } catch (e) {
      if (e instanceof ErrorApi && (e.status === 400 || e.status === 422)) return malo();
      throw e;
    }
    return noInterpretada("texto_libre"); // nunca se guarda, se registra ni se envía a un modelo
  }

  // -------------------------------------------------------------- HTTP
  // Una ventana por dirección de origen: un equipo de la VPN sin token no agota el cupo de la app legítima.
  const ventanas = new Map<string, { inicio: number; n: number }>();
  function limitar(origen: string, t: number) {
    let v = ventanas.get(origen);
    if (!v || t - v.inicio > 10_000) {
      if (!v && ventanas.size >= 1024) {
        for (const [k, w] of ventanas) if (t - w.inicio > 10_000) ventanas.delete(k);
        // Memoria acotada: con 1024 orígenes vivos a la vez, uno nuevo espera (fail-closed).
        if (ventanas.size >= 1024) throw new ErrorApi(429, "RATE_LIMITED", { retryAfter: 10 });
      }
      v = { inicio: t, n: 0 };
      ventanas.set(origen, v);
    }
    if (++v.n > limiteVentana) throw new ErrorApi(429, "RATE_LIMITED", { retryAfter: Math.max(1, Math.ceil((v.inicio + 10_000 - t) / 1000)) });
  }
  function autenticar(req: IncomingMessage): { o: Op; dispositivo: string | null } {
    const au = req.headersDistinct.authorization;
    const dp = req.headersDistinct.dpop;
    const m = au?.length === 1 ? /^DPoP ([A-Za-z0-9._~+/=-]{1,512})$/.exec(au[0]) : null;
    if (!m || dp?.length !== 1 || !dp[0]) throw new ErrorApi(401, "UNAUTHENTICATED");
    if (opts.autenticar) {
      const path = new URL(req.url ?? "/", "http://x").pathname;
      const r = opts.autenticar(m[1], { proof: dp[0], method: req.method ?? "", path, host: req.headers.host ?? "" });
      if (!r || !ops[r.ref]) throw new ErrorApi(401, "UNAUTHENTICATED");
      if (r.revocado) throw new ErrorApi(401, "UNAUTHENTICATED", { revocado: true });
      return { o: ops[r.ref], dispositivo: r.dispositivo ?? null };
    }
    const d = tokens.get(m[1]);
    if (!d) throw new ErrorApi(401, "UNAUTHENTICATED");
    if (d.revocado) throw new ErrorApi(401, "UNAUTHENTICATED", { revocado: true });
    if (opts.caducidadToken && ahora() > d.expira) throw new ErrorApi(401, "UNAUTHENTICATED");
    return { o: d.op, dispositivo: null };
  }
  async function cuerpo(req: IncomingMessage): Promise<any> {
    const trozos: Buffer[] = [];
    let n = 0;
    for await (const c of req) { n += (c as Buffer).length; if (n > 16 * 1024) throw invalida(); trozos.push(c as Buffer); }
    if (!n) throw invalida();
    let j: unknown;
    try { j = JSON.parse(Buffer.concat(trozos).toString("utf8")); } catch { throw invalida(); }
    if (!j || typeof j !== "object" || Array.isArray(j)) throw invalida();
    return j;
  }
  function quien(req: IncomingMessage) {
    const u = new URL(req.url ?? "/", "http://x");
    return { ruta: u.pathname, q: Object.fromEntries(u.searchParams) as Record<string, string>, claves: [...u.searchParams.keys()] };
  }
  const sinParametros = (u: { claves: string[] }, permitidos: string[]) => {
    if (u.claves.some((k) => !permitidos.includes(k)) || new Set(u.claves).size !== u.claves.length) throw invalida();
  };

  async function manejar(req: IncomingMessage) {
    limitar(req.socket.remoteAddress ?? "desconocido", Date.now());
    const { o, dispositivo } = autenticar(req);
    if (opts.detenido?.()) throw new ErrorApi(503, "UNAVAILABLE");
    sincronizar(o);
    try { return await rutas(req, o, dispositivo); } finally { guardarEstado(o); }
  }

  async function rutas(req: IncomingMessage, o: Op, dispositivo: string | null) {
    const u = quien(req);
    const m = req.method;
    if (!u.ruta.startsWith(PREFIJO + "/")) throw noEncontrado();
    const r = u.ruta.slice(PREFIJO.length);
    let x: RegExpExecArray | null;
    if (m === "GET" && r === "/estado") { sinParametros(u, []); return vistaEstado(o); }
    if (m === "GET" && (x = /^\/q\/([^/]+)$/.exec(r))) { sinParametros(u, ["proyecto", "persona", "desde", "hasta", "limite"]); return opConsulta(o, x[1], filtros(u.q)); }
    if (m === "GET" && r === "/filtros") {
      sinParametros(u, []);
      const c = o.nivel === "completo";
      return {
        nivel: o.nivel, proyectos: c ? o.d.proyectos.map((p) => ({ id: p.id, nombre: inerte(p.nombre) })) : [],
        personas: c ? o.d.personas.map((p) => ({ id: p.id, nombre: inerte(p.nombre) })) : [],
      };
    }
    if (m === "GET" && (x = /^\/elementos\/([^/]+)\/porque$/.exec(r))) { sinParametros(u, []); return opPorque(o, x[1]); }
    if (m === "POST" && (x = /^\/elementos\/([^/]+)\/correccion$/.exec(r))) {
      const c = await cuerpo(req);
      if (validar(OPENAPI, OPENAPI.components.schemas.PeticionCorreccion, c).length) throw invalida();
      return opCorreccion(o, x[1], c.tipo, dispositivo);
    }
    if (m === "GET" && r === "/atencion") { sinParametros(u, []); return vistaAtencion(o); }
    if (m === "PUT" && r === "/atencion") {
      const c = await cuerpo(req);
      if (validar(OPENAPI, OPENAPI.components.schemas.PeticionAtencion, c).length) throw invalida();
      return opAtencion(o, c);
    }
    if (m === "GET" && r === "/avisos") { sinParametros(u, []); return vistaAvisos(o); }
    if (m === "PUT" && r === "/avisos") return opAvisos(o, await cuerpo(req));
    if (m === "GET" && r === "/sondeo") { sinParametros(u, ["cursor", "limite"]); return opSondeo(o, u.q); }
    if (m === "GET" && r === "/adaptadores") { sinParametros(u, []); return vistaAdaptadores(o); }
    if (m === "GET" && r === "/detalle") { sinParametros(u, []); return vistaDetalle(o); }
    if (m === "PUT" && r === "/detalle") {
      const c = await cuerpo(req);
      if (validar(OPENAPI, OPENAPI.components.schemas.PeticionDetalle, c).length) throw invalida();
      return opDetalle(o, c);
    }
    if (m === "GET" && r === "/registro") { sinParametros(u, ["limite"]); return opRegistro(o, u.q); }
    if (m === "POST" && r === "/ordenes") {
      const c = await cuerpo(req);
      if (validar(OPENAPI, OPENAPI.components.schemas.PeticionOrden, c).length) throw invalida();
      return opOrden(o, c.orden, dispositivo);
    }
    throw noEncontrado();
  }

  const servidor = (): Server => limitesConexion(createHttps({ cert: opts.tls.cert, key: opts.tls.key, minVersion: "TLSv1.3", handshakeTimeout: 10_000 }, async (req, res) => {
    const salir = (status: number, json: unknown, extra: Record<string, string> = {}) => {
      res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...extra });
      res.end(JSON.stringify(json));
    };
    try {
      salir(200, await manejar(req));
    } catch (err) {
      // Nunca se registran datos de trabajo: solo el tipo de error.
      const e = err instanceof ErrorApi ? err : (process.stderr.write(`soul api: ${(err as Error)?.name ?? "error"}\n`), new ErrorApi(503, "UNAVAILABLE"));
      const sobre: Record<string, unknown> = { code: e.code, message: e.revocado ? "device revoked" : e.code.toLowerCase().replace(/_/g, " "), requestId: randomUUID(), retryable: e.code === "RATE_LIMITED" || e.code === "UNAVAILABLE" };
      if (e.revocado) sobre.error = "DEVICE_REVOKED";
      const extra: Record<string, string> = e.status === 401 ? { "WWW-Authenticate": "DPoP" } : e.retryAfter ? { "Retry-After": String(e.retryAfter) } : {};
      salir(e.status, sobre, extra);
    }
  }), opts.limites);

  const hooks: { correccion?: (o: Op, id: string, tipo: string, t: number, dispositivo: string | null) => void } = {};
  let escucha: Listening | null = null;
  return {
    /** Escucha solo en esas direcciones (las de la VPN del operador) y por TLS. */
    escuchar: async (direcciones: string[], puerto = 0) => {
      escucha = await listenOnly(direcciones, puerto, servidor);
      return escucha;
    },
    cerrar: async () => { await escucha?.close(); escucha = null; },
    direcciones: () => escucha?.addresses ?? [],
    ahora,
    avanzar: (ms: number) => { desplazamiento += ms; },
    revocar: (tok: string) => { const d = tokens.get(tok); if (d) d.revocado = true; },
    renovar: (tok: string) => { const d = tokens.get(tok); if (d) d.expira = ahora() + 300_000; },
    caerFuentes: (b: boolean) => { if (b && !caidas) caidasDesde = ahora(); caidas = b; },
    estadisticas: (ref: string) => { const o = ops[ref]; sincronizar(o); return { ...o.st, pendientesAvisos: o.pendAvisos.length, pendientesAlertas: o.pendAlertas.length }; },
    egresos: () => 0,
    volcarEstado: () => JSON.stringify(Object.values(ops), (_k, v) => (v instanceof Map ? [...v] : v)),
    /** Producción: persiste las correcciones en el libro del núcleo. */
    alCorregir: (f: (o: Op, id: string, tipo: string, t: number, dispositivo: string | null) => void) => { hooks.correccion = f; },
    operador: (ref: string) => ops[ref],
    /** Modo declarado fuera de la API (`soul mode`): se aplica como si llegara de la app y se persiste. */
    declararModo: (ref: string, modo: string, hasta: string | null) => {
      const o = ops[ref];
      if (!o) return false;
      sincronizar(o);
      try { opAtencion(o, modo === "DISPONIBLE" ? { modo } : { modo, hasta }); } catch { return false; } finally { guardarEstado(o); }
      return true;
    },
  };
}
