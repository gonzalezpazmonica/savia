/**
 * Bucle de iniciativa del gemelo (SE-504 §3 «Savia escribe primero», sobre la memoria de SE-490).
 *
 * Lógica pura y determinista, sin modelo, sin red y sin reloj propio: recibe los elementos vivos
 * y el instante, y devuelve qué decir. La API (`src/api/server.ts`) decide si además notifica,
 * con la política de atención de SE-490 AC-4b, y guarda el estado.
 *
 * - Resumen de la mañana: a la hora configurada, un mensaje breve en lenguaje natural con hasta
 *   3 asuntos (respuestas que esperan, vencimientos de hoy y mañana, dependencias, Q1).
 * - Seguimientos: en cada latido, lo que espera respuesta desde hace más de N horas, los
 *   compromisos que vencen mañana y los cambios importantes (dependencias nuevas desde el
 *   latido anterior). Un mensaje por latido con hasta 3 asuntos; cada asunto se propone una vez.
 * - Acciones propuestas: una por asunto. Nunca se ejecutan solas: solo `decidirAccion` con la
 *   decisión de la persona las aprueba, y la aprobación queda registrada como grant de esa
 *   acción concreta (dispositivo, hora y hash del contenido).
 *
 * El texto del mensaje es de Savia y sale de plantillas: nunca incluye texto de terceros
 * (asuntos de correo, títulos). Los títulos viajan aparte como `TextoInerte` y solo si el nivel
 * lo permite. Sin proveedor de inferencia de la organización, el borrador es una plantilla
 * honesta marcada como tal, no un texto generado. Días y horas en UTC, como los resúmenes de
 * SE-490 en la API.
 */

import { createHash } from "node:crypto";

const MIN = 60_000;
const HORA = 60 * MIN;
const DIA = 24 * HORA;

/** Máximo de asuntos por mensaje (SE-504 §3: «un mensaje de como máximo 3 asuntos»). */
export const MAX_ASUNTOS = 3;
/** Un resumen que sale más de esto después de su hora ya no tiene sentido (igual que SE-490). */
export const TOLERANCIA_RESUMEN_MS = 60 * MIN;

export type MotivoAsunto = "espera_respuesta" | "vence_hoy" | "vence_manana" | "depende_de_otros" | "abierto" | "cambio_importante";
export type TipoMensaje = "resumen_manana" | "seguimiento";
export type TipoAccion = "borrador_respuesta" | "recordatorio" | "revisar";
export type EstadoAccion = "propuesta" | "aprobada" | "descartada";

/** Lo que el gemelo necesita de un elemento. El título no se usa para redactar. */
export interface ElementoGemelo {
  id: string;
  tipo: string;
  /** Vencimiento o inicio (ms). */
  fecha: number | null;
  /** Desde cuándo existe (en un hilo que espera, el mensaje sin respuesta). */
  nace: number;
  dep: boolean;
}

export interface Asunto {
  elementoId: string;
  motivo: MotivoAsunto;
  esperaDesde: number | null;
  vence: number | null;
  accionId: string | null;
}

export interface Grant {
  en: number;
  dispositivo: string | null;
  /** sha256 de la acción exacta aprobada: no vale para otra. */
  hash: string;
}

export interface AccionPropuesta {
  id: string;
  tipo: TipoAccion;
  elementoId: string;
  creada: number;
  estado: EstadoAccion;
  contenido: string;
  generadoPor: "plantilla";
  grant: Grant | null;
  decididaEn: number | null;
  /** `null` mientras no se aprueba; tras aprobar, si había ejecutor o no. */
  ejecucion: "entregada" | "sin_ejecutor" | null;
}

export interface MensajeGemelo {
  id: string;
  seq: number;
  tipo: TipoMensaje;
  creado: number;
  texto: string;
  asuntos: Asunto[];
  notificado: boolean;
  /** Por qué no notificó (el mensaje queda en el chat igualmente). */
  silencio: string | null;
}

export interface ConfigGemelo {
  activo: boolean;
  /** Horas a partir de las cuales algo que espera respuesta merece seguimiento. */
  esperaHoras: number;
  /** Minutos entre latidos. */
  latidoMin: number;
}

export const CONFIG_GEMELO_DEFECTO: ConfigGemelo = { activo: true, esperaHoras: 24, latidoMin: 30 };

export interface EstadoGemelo {
  v: 1;
  config: ConfigGemelo;
  seq: number;
  mensajes: MensajeGemelo[];
  acciones: AccionPropuesta[];
  /** Claves `motivo|id` ya propuestas en un seguimiento: no se repiten. */
  tratados: string[];
  ultimoLatido: number | null;
  /** Día (ms a las 00:00 UTC) del último resumen de la mañana emitido. */
  ultimoResumenDia: number | null;
  leidoHasta: number;
}

export function estadoGemeloVacio(): EstadoGemelo {
  return { v: 1, config: { ...CONFIG_GEMELO_DEFECTO }, seq: 0, mensajes: [], acciones: [], tratados: [], ultimoLatido: null, ultimoResumenDia: null, leidoHasta: 0 };
}

export function validarConfigGemelo(c: unknown): c is ConfigGemelo {
  const x = c as Partial<ConfigGemelo> | null;
  return !!x && typeof x.activo === "boolean"
    && Number.isInteger(x.esperaHoras) && (x.esperaHoras as number) >= 1 && (x.esperaHoras as number) <= 168
    && Number.isInteger(x.latidoMin) && (x.latidoMin as number) >= 5 && (x.latidoMin as number) <= 240;
}

/** Estado guardado → estado usable; lo mal formado da `null` (fail-closed: nada se aprueba solo). */
export function restaurarGemelo(e: unknown): EstadoGemelo | null {
  const x = e as Partial<EstadoGemelo> | null;
  if (!x || x.v !== 1 || !Number.isInteger(x.seq) || !Array.isArray(x.mensajes) || !Array.isArray(x.acciones) || !Array.isArray(x.tratados)) return null;
  if (!validarConfigGemelo(x.config)) return null;
  if (!x.acciones.every((a) => a && typeof a.id === "string" && ["propuesta", "aprobada", "descartada"].includes(a.estado as string))) return null;
  // Una acción «aprobada» sin grant no es válida: se rechaza el estado entero.
  if (x.acciones.some((a) => a.estado === "aprobada" && (!a.grant || typeof a.grant.hash !== "string" || a.grant.hash !== hashAccion(a)))) return null;
  return {
    v: 1, config: x.config as ConfigGemelo, seq: x.seq as number, mensajes: x.mensajes as MensajeGemelo[], acciones: x.acciones as AccionPropuesta[],
    tratados: (x.tratados as unknown[]).filter((k): k is string => typeof k === "string"),
    ultimoLatido: typeof x.ultimoLatido === "number" ? x.ultimoLatido : null,
    ultimoResumenDia: typeof x.ultimoResumenDia === "number" ? x.ultimoResumenDia : null,
    leidoHasta: Number.isInteger(x.leidoHasta) ? (x.leidoHasta as number) : 0,
  };
}

const diaDe = (t: number) => Math.floor(t / DIA) * DIA;
const COMPROMISO = new Set(["tarea", "compromiso", "revision"]);
const ABIERTO = new Set(["reunion", "tarea", "revision", "hilo_espera", "documento", "compromiso"]);

/** Asuntos del resumen de la mañana, por prioridad: lo que espera, lo que vence, lo que bloquea, lo abierto. */
export function seleccionarResumen(els: readonly ElementoGemelo[], ahora: number): Asunto[] {
  const hoy = diaDe(ahora);
  const usados = new Set<string>();
  const out: Asunto[] = [];
  const tomar = (lista: ElementoGemelo[], motivo: MotivoAsunto) => {
    for (const e of lista) {
      if (out.length >= MAX_ASUNTOS) return;
      if (usados.has(e.id)) continue;
      usados.add(e.id);
      out.push({ elementoId: e.id, motivo, esperaDesde: motivo === "espera_respuesta" ? e.nace : null, vence: e.fecha, accionId: null });
    }
  };
  const orden = (a: ElementoGemelo, b: ElementoGemelo) => (a.fecha ?? Infinity) - (b.fecha ?? Infinity) || a.nace - b.nace || a.id.localeCompare(b.id);
  tomar(els.filter((e) => e.tipo === "hilo_espera").sort((a, b) => a.nace - b.nace || a.id.localeCompare(b.id)), "espera_respuesta");
  tomar(els.filter((e) => COMPROMISO.has(e.tipo) && e.fecha != null && diaDe(e.fecha) === hoy).sort(orden), "vence_hoy");
  tomar(els.filter((e) => COMPROMISO.has(e.tipo) && e.fecha != null && diaDe(e.fecha) === hoy + DIA).sort(orden), "vence_manana");
  tomar(els.filter((e) => e.dep).sort(orden), "depende_de_otros");
  tomar(els.filter((e) => ABIERTO.has(e.tipo)).sort(orden), "abierto");
  return out;
}

/**
 * Seguimientos del latido: espera de más de `esperaHoras`, vencimientos de mañana y dependencias
 * nuevas desde el latido anterior (en el primer latido no hay «nuevo»: todo sería cambio).
 * Excluye lo ya tratado. Hasta `MAX_ASUNTOS`; lo que no cabe sale en el siguiente latido.
 */
export function detectarSeguimientos(els: readonly ElementoGemelo[], ahora: number, cfg: ConfigGemelo, tratados: ReadonlySet<string>, ultimoLatido: number | null): Asunto[] {
  const manana = diaDe(ahora) + DIA;
  const cand: Asunto[] = [];
  const usados = new Set<string>();
  const add = (e: ElementoGemelo, motivo: MotivoAsunto) => {
    if (usados.has(e.id) || tratados.has(`${motivo}|${e.id}`)) return;
    usados.add(e.id);
    cand.push({ elementoId: e.id, motivo, esperaDesde: motivo === "espera_respuesta" ? e.nace : null, vence: e.fecha, accionId: null });
  };
  const umbral = cfg.esperaHoras * HORA;
  const porNace = (a: ElementoGemelo, b: ElementoGemelo) => a.nace - b.nace || a.id.localeCompare(b.id);
  for (const e of els.filter((x) => x.tipo === "hilo_espera" && ahora - x.nace > umbral).sort(porNace)) add(e, "espera_respuesta");
  for (const e of els.filter((x) => COMPROMISO.has(x.tipo) && x.fecha != null && diaDe(x.fecha) === manana)
    .sort((a, b) => (a.fecha as number) - (b.fecha as number) || a.id.localeCompare(b.id))) add(e, "vence_manana");
  if (ultimoLatido != null) for (const e of els.filter((x) => x.dep && x.nace > ultimoLatido && x.nace <= ahora).sort(porNace)) add(e, "cambio_importante");
  return cand.slice(0, MAX_ASUNTOS);
}

// ------------------------------------------------------------------ redacción (plantillas)

const NUM = ["Ninguna", "Una", "Dos", "Tres"];
const UNO: Record<MotivoAsunto, string> = {
  espera_respuesta: "una respuesta que espera",
  vence_hoy: "un compromiso que vence hoy",
  vence_manana: "un compromiso que vence mañana",
  depende_de_otros: "algo que depende de otra persona",
  abierto: "un asunto abierto",
  cambio_importante: "un cambio importante",
};

function hace(desde: number, ahora: number): string {
  if (diaDe(desde) === diaDe(ahora) - DIA) return "desde ayer";
  const h = Math.floor((ahora - desde) / HORA);
  if (h < 1) return "desde hace menos de una hora";
  if (h < 48) return `desde hace ${h} ${h === 1 ? "hora" : "horas"}`;
  return `desde hace ${Math.floor(h / 24)} días`;
}

const frase = (a: Asunto, ahora: number) =>
  a.motivo === "espera_respuesta" && a.esperaDesde != null ? `${UNO.espera_respuesta} ${hace(a.esperaDesde, ahora)}` : UNO[a.motivo];

function enumerar(partes: string[]): string {
  return partes.length <= 1 ? partes.join("") : `${partes.slice(0, -1).join(", ")} y ${partes.at(-1)}`;
}

/** Texto de Savia: natural, breve y sin texto de terceros (los títulos van aparte, inertes). */
export function redactar(tipo: TipoMensaje, asuntos: readonly Asunto[], ahora: number): string {
  const n = Math.min(asuntos.length, MAX_ASUNTOS);
  const lista = enumerar(asuntos.slice(0, MAX_ASUNTOS).map((a) => frase(a, ahora)));
  if (tipo === "resumen_manana") return `Buenos días. ${NUM[n]} ${n === 1 ? "cosa" : "cosas"} para hoy: ${lista}. Te dejo una propuesta para cada una.`;
  const propuesta = asuntos.some((a) => a.motivo === "espera_respuesta") ? "Te propongo un borrador" : "Te propongo cómo seguir";
  return `Tienes ${lista}. ${propuesta}; no hago nada hasta que lo apruebes.`;
}

const AVISO_PLANTILLA = "Plantilla: no hay proveedor de inferencia de la organización configurado; edítala antes de usarla.";

function plantilla(tipo: TipoAccion, a: Asunto): string {
  if (tipo === "borrador_respuesta") return `${AVISO_PLANTILLA}\n\nHola:\n\nGracias por tu mensaje. Lo he visto y te respondo con detalle en cuanto pueda.\n\nUn saludo.`;
  if (tipo === "recordatorio") {
    const cuando = a.vence != null ? `${new Date(a.vence).toISOString().slice(0, 16).replace("T", " ")} UTC` : "sin fecha";
    return `${AVISO_PLANTILLA}\n\nRecordatorio: reservar un rato antes del vencimiento (${cuando}).`;
  }
  return `${AVISO_PLANTILLA}\n\nRevisar este asunto y decidir el siguiente paso.`;
}

const TIPO_ACCION: Record<MotivoAsunto, TipoAccion> = {
  espera_respuesta: "borrador_respuesta", vence_hoy: "recordatorio", vence_manana: "recordatorio",
  depende_de_otros: "revisar", abierto: "revisar", cambio_importante: "revisar",
};

/** Hash de lo que se aprueba: tipo, elemento y contenido exacto. */
export function hashAccion(a: Pick<AccionPropuesta, "tipo" | "elementoId" | "contenido">): string {
  return createHash("sha256").update(JSON.stringify([a.tipo, a.elementoId, a.contenido])).digest("hex");
}

/**
 * Crea el mensaje con una acción propuesta por asunto y lo añade al estado. No notifica ni
 * ejecuta nada: devuelve el mensaje para que la API decida la notificación.
 */
export function emitirMensaje(est: EstadoGemelo, tipo: TipoMensaje, asuntos: Asunto[], ahora: number, prefijoId: string): MensajeGemelo {
  est.seq++;
  const seq = est.seq;
  const conAccion = asuntos.slice(0, MAX_ASUNTOS).map((a, i) => {
    const t = TIPO_ACCION[a.motivo];
    const acc: AccionPropuesta = {
      id: `a-${prefijoId}-${seq}-${i + 1}`, tipo: t, elementoId: a.elementoId, creada: ahora, estado: "propuesta",
      contenido: plantilla(t, a), generadoPor: "plantilla", grant: null, decididaEn: null, ejecucion: null,
    };
    est.acciones.push(acc);
    return { ...a, accionId: acc.id };
  });
  const m: MensajeGemelo = { id: `g-${prefijoId}-${seq}`, seq, tipo, creado: ahora, texto: redactar(tipo, conAccion, ahora), asuntos: conAccion, notificado: false, silencio: null };
  est.mensajes.push(m);
  // Lo dicho no se repite como seguimiento por el mismo motivo. Del resumen solo cuenta lo que ya
  // cumplía el criterio del seguimiento: una espera que aún no pasa del umbral sí tendrá seguimiento.
  const yaCumple = (a: Asunto) => a.motivo === "vence_manana"
    || (a.motivo === "espera_respuesta" && a.esperaDesde != null && ahora - a.esperaDesde > est.config.esperaHoras * HORA);
  for (const a of conAccion) if (tipo === "seguimiento" || yaCumple(a)) est.tratados.push(`${a.motivo}|${a.elementoId}`);
  return m;
}

/** ¿Toca el resumen de la mañana? `hhmm` en UTC, como los resúmenes de SE-490 en la API. */
export function resumenDebido(est: EstadoGemelo, hhmm: string | null, ahora: number): boolean {
  if (!est.config.activo || hhmm == null || !/^\d{2}:\d{2}$/.test(hhmm)) return false;
  const [h, m] = hhmm.split(":").map(Number);
  if (h > 23 || m > 59) return false;
  const programado = diaDe(ahora) + h * HORA + m * MIN;
  if (ahora < programado || ahora - programado > TOLERANCIA_RESUMEN_MS) return false;
  return est.ultimoResumenDia !== diaDe(ahora);
}

export function marcarResumen(est: EstadoGemelo, ahora: number): void { est.ultimoResumenDia = diaDe(ahora); }

export function latidoDebido(est: EstadoGemelo, ahora: number): boolean {
  return est.config.activo && (est.ultimoLatido == null || ahora - est.ultimoLatido >= est.config.latidoMin * MIN);
}

export class ErrorDecision extends Error {
  readonly code: "NOT_FOUND" | "CONFLICT" | "INVALID_INPUT";
  constructor(code: "NOT_FOUND" | "CONFLICT" | "INVALID_INPUT") { super(code); this.code = code; }
}

/**
 * La única vía por la que una acción propuesta cambia de estado. Solo la llama la API con la
 * decisión de la persona desde un dispositivo autenticado. Aprobar registra el grant de esa
 * acción concreta y entonces, y solo entonces, entrega al ejecutor si lo hay. Repetir la misma
 * decisión es idempotente (no vuelve a ejecutar); cambiarla tras decidir es un conflicto.
 */
export function decidirAccion(
  est: EstadoGemelo, id: string, decision: unknown, quien: { dispositivo: string | null }, ahora: number,
  ejecutor?: (a: AccionPropuesta, g: Grant) => void,
): AccionPropuesta {
  if (decision !== "aprobar" && decision !== "descartar") throw new ErrorDecision("INVALID_INPUT");
  const a = est.acciones.find((x) => x.id === id);
  if (!a) throw new ErrorDecision("NOT_FOUND");
  const destino: EstadoAccion = decision === "aprobar" ? "aprobada" : "descartada";
  if (a.estado === destino) return a;
  if (a.estado !== "propuesta") throw new ErrorDecision("CONFLICT");
  a.decididaEn = ahora;
  if (destino === "descartada") { a.estado = "descartada"; return a; }
  const g: Grant = { en: ahora, dispositivo: quien.dispositivo, hash: hashAccion(a) };
  a.grant = g;
  a.estado = "aprobada";
  if (ejecutor) { ejecutor(a, g); a.ejecucion = "entregada"; } else a.ejecucion = "sin_ejecutor";
  return a;
}

/**
 * Retención: los mensajes de más de `ms` se olvidan y, con ellos, sus acciones (una acción solo
 * se alcanza desde su mensaje). Una acción olvidada sin decidir no se ejecuta nunca.
 */
export function podar(est: EstadoGemelo, ahora: number, ms = 7 * DIA): void {
  const lim = ahora - ms;
  est.mensajes = est.mensajes.filter((m) => m.creado >= lim);
  const vivas = new Set(est.mensajes.flatMap((m) => m.asuntos.map((a) => a.accionId)));
  est.acciones = est.acciones.filter((a) => vivas.has(a.id));
  if (est.tratados.length > 2000) est.tratados = est.tratados.slice(-2000);
}
