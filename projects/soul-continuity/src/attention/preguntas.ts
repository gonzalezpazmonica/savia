// Preguntas de agentes en la cola única (SE-514 S2). Registro sobre la política y la bandeja de
// SE-490: no hay otro almacén ni otro planificador. Cada pregunta tiene identificador, versión de
// lo que se enseñó y caducidad. El silencio no aprueba nada: al vencer, el trabajo queda en
// espera (`DEFER`) y ningún efecto se autoriza. Dos preguntas de decisión sobre lo mismo se
// unen en una tarjeta; un permiso nunca se une con otro. Una respuesta vale solo para la tarjeta
// y la versión que se enseñaron y mientras no haya vencido.
//
// Fail-closed: entrada ilegible, origen sin autenticar, valor de respuesta raro o tarjeta que ya
// no existe = rechazo, sin efecto. Sin reloj propio: el minuto entra como argumento.

import { PREFIJO_AGENTE } from './cola.ts';
import { type Decision, motivo as m } from './decision.ts';
import {
  type CosteRetraso, type Evento, type Nivel, type Origen, type Tipo, deAgente,
} from './modelo.ts';
import { type Politica, redactar } from './politica.ts';
import { DIA, type Minuto, instanciaEn } from './tiempo.ts';

export type ClasePregunta = 'DECISION' | 'PERMISO';
export type EstadoPregunta = 'ABIERTA' | 'DEFER' | 'RESPONDIDA';

/** Lo que entrega un agente. Las cinco cosas de la spec van todas: qué, por qué, alternativa, coste y caducidad. */
export interface PreguntaAgente {
  id: string;
  agente: string;
  /** Trabajo que espera esta respuesta. */
  trabajo: string;
  /** Versión de lo que se enseña. Si el contenido cambia, cambia la versión. */
  version: string;
  clase: ClasePregunta;
  /** Dos decisiones con el mismo tema se unen en una tarjeta. No aplica a permisos. */
  tema?: string;
  /** Qué permiso concreto se pide (obligatorio en `PERMISO`). */
  permiso?: string;
  que: string;
  porQue: string;
  /** Qué hace el sistema si no contestas. */
  siNoContestas: string;
  siAplazas: string;
  /** Hasta cuándo vale (minuto local). */
  caduca: Minuto;
  /** Autorización obligatoria: sin ella el trabajo no sigue. */
  obligatoria?: boolean;
  nivel?: Nivel;
  costeRetraso?: CosteRetraso;
}

export type MotivoRechazoPregunta =
  | 'ENTRADA_INVALIDA' | 'ORIGEN_NO_AUTENTICADO' | 'YA_CADUCADA' | 'ID_REUTILIZADO' | 'YA_PREGUNTADA'
  | 'BLOQUEADA' | 'NO_ADMITIDA' | 'YA_REPREGUNTADA_EN_VENTANA';

export type ResultadoPreguntar =
  | { ok: true; nueva: boolean; estado: EstadoPregunta; tarjeta: string; decision: Decision | null }
  | { ok: false; motivo: MotivoRechazoPregunta; detalle: string };

export type MotivoRechazoRespuesta =
  | 'ENTRADA_INVALIDA' | 'ORIGEN_NO_VALIDO' | 'DESCONOCIDA' | 'CADUCADA' | 'VERSION_CAMBIADA'
  | 'YA_RESPONDIDA' | 'VALOR_INVALIDO';

export type ResultadoRepregunta =
  | { ok: true; caduca: Minuto }
  | { ok: false; motivo: 'DESCONOCIDA' | 'NO_ESTA_EN_DEFER' | 'CADUCA_INVALIDA' | 'YA_REPREGUNTADA_EN_VENTANA' | 'BLOQUEADA' };

/** Lo que ve la persona: una o varias preguntas unidas. */
export interface Tarjeta {
  readonly id: string;
  readonly version: string;
  readonly estado: 'ABIERTA' | 'DEFER';
  readonly clase: ClasePregunta;
  readonly preguntas: readonly string[];
  readonly trabajos: readonly string[];
  readonly obligatoria: boolean;
  readonly caduca: Minuto;
  readonly desde: Minuto;
  readonly nivel: Nivel;
  /** El contenido supera el nivel del canal: solo la referencia. */
  readonly redactada: boolean;
  readonly que: string | null;
  readonly porQue: string | null;
  readonly siNoContestas: string | null;
  readonly siAplazas: string | null;
}

export type ResultadoRespuesta =
  | { ok: true; tarjeta: string; valor: string; resueltas: readonly string[] }
  | { ok: false; motivo: MotivoRechazoRespuesta; volverAEnsenar: Tarjeta | null; texto: string };

export interface EstadoPreguntas {
  /** Tarjetas esperando respuesta y tarjetas cuyo plazo venció sin ella. */
  readonly abiertas: number;
  readonly enEspera: number;
  /** Tarjetas con alguna autorización obligatoria sin respuesta (abiertas o en espera). */
  readonly obligatorias: number;
  /** Tarjetas que el modo actual no deja enseñar todavía; no se pierden. */
  readonly ocultasPorModo: number;
  readonly trabajosEnEspera: readonly string[];
  /** Minutos que lleva esperando la más antigua. */
  readonly masAntiguaMin: number | null;
}

type Normalizada = PreguntaAgente & { nivel: Nivel; costeRetraso: CosteRetraso; obligatoria: boolean };

interface Registro {
  e: Normalizada;
  estado: EstadoPregunta;
  caduca: Minuto;
  desde: Minuto;
  respuesta: string | null;
  /** Repreguntas hechas, por ventana. */
  repreguntas: Map<Minuto, number>;
}

const COSTES: readonly string[] = ['BAJO', 'MEDIO', 'ALTO'];
export const VALORES_PERMISO: readonly string[] = Object.freeze(['CONCEDER', 'DENEGAR']);
const SUFIJO_VENCIDA = '#vencida';

function cad(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : null;
}

function plano(s: string): string {
  return s.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, ' ').trim();
}

/** Valida y normaliza. Devuelve el motivo si no se puede leer. */
function leer(x: unknown): Normalizada | string {
  if (x === null || typeof x !== 'object' || Array.isArray(x)) return 'la pregunta no es un objeto';
  const r = x as Record<string, unknown>;
  const falta: string[] = [];
  const t = (k: string): string => {
    const v = cad(r[k]);
    if (v === null) falta.push(k);
    return v ?? '';
  };
  const id = t('id');
  const agente = t('agente');
  const trabajo = t('trabajo');
  const version = t('version');
  const que = t('que');
  const porQue = t('porQue');
  const siNoContestas = t('siNoContestas');
  const siAplazas = t('siAplazas');
  if (r.clase !== 'DECISION' && r.clase !== 'PERMISO') falta.push('clase');
  if (typeof r.caduca !== 'number' || !Number.isFinite(r.caduca)) falta.push('caduca');
  const clase = r.clase as ClasePregunta;
  let permiso: string | undefined;
  let tema: string | undefined;
  if (clase === 'PERMISO') {
    const p = cad(r.permiso);
    if (p === null) falta.push('permiso');
    else permiso = p;
  }
  if (r.tema !== undefined && r.tema !== null) {
    const tm = cad(r.tema);
    if (tm === null || tm.includes('#')) falta.push('tema');
    else tema = tm;
  }
  if (falta.length > 0) return `faltan o no se leen: ${falta.join(', ')}`;
  const nivel: Nivel = r.nivel === 1 || r.nivel === 2 || r.nivel === 3 || r.nivel === 4 ? r.nivel : 4;
  const costeRetraso = typeof r.costeRetraso === 'string' && COSTES.includes(r.costeRetraso)
    ? (r.costeRetraso as CosteRetraso) : 'MEDIO';
  return {
    id, agente, trabajo, version, clase, que, porQue, siNoContestas, siAplazas,
    caduca: r.caduca as Minuto, nivel, costeRetraso, obligatoria: r.obligatoria === true,
    ...(tema !== undefined ? { tema } : {}), ...(permiso !== undefined ? { permiso } : {}),
  };
}

/**
 * Clave de unión: solo se unen decisiones con el mismo tema Y el mismo texto de la pregunta (lo
 * que se enseña es lo que se responde); un permiso o una decisión obligatoria van solos, siempre.
 */
function claveGrupo(e: PreguntaAgente): string {
  if (e.clase === 'PERMISO') return `p:${e.id}`;
  if (e.obligatoria === true || e.tema === undefined) return `q:${e.id}`;
  return `g:${e.tema.trim().toLowerCase()}|${e.que.trim().replace(/\s+/g, ' ').toLowerCase()}`;
}

export class Preguntas {
  readonly politica: Politica;
  private readonly reg = new Map<string, Registro>();

  constructor(politica: Politica) {
    this.politica = politica;
  }

  private cubo(ahora: Minuto): Minuto {
    return instanciaEn(this.politica.config.ventanas, ahora) ?? -(Math.floor(ahora / DIA) + 1);
  }

  /** PARA y veto de la persona: ninguna pregunta nueva, reabierta o respondible los esquiva. */
  private bloqueo(trabajo: string): 'PARADO' | 'VETADO' | null {
    if (this.politica.estado.parado) return 'PARADO';
    return this.politica.estado.vetos.has(trabajo) ? 'VETADO' : null;
  }

  /** Gasta la única repregunta de la ventana. `false` si ya estaba gastada (no cambia nada). */
  private gastarVentana(r: Registro, ahora: Minuto): boolean {
    const cubo = this.cubo(ahora);
    if ((r.repreguntas.get(cubo) ?? 0) >= 1) return false;
    r.repreguntas.set(cubo, 1);
    return true;
  }

  private decisionId(id: string): string {
    return `${PREFIJO_AGENTE}${id}`;
  }

  private redactada(nivel: Nivel): boolean {
    return redactar(nivel, this.politica.config.canalNivelMax);
  }

  /**
   * Las preguntas abiertas cuyo plazo llegó pasan a `DEFER`: el trabajo espera, no se ejecuta
   * nada y no se decide por la persona. Vencer es `caduca <= ahora`. Idempotente.
   */
  vencer(ahora: Minuto): string[] {
    const vencidas: string[] = [];
    for (const [id, r] of this.reg) {
      if (r.estado !== 'ABIERTA' || r.caduca > ahora) continue;
      r.estado = 'DEFER';
      vencidas.push(id);
      const did = this.decisionId(id);
      this.politica.decidir(deAgente(`${did}#silencio`, { k: 'SILENCIO', decisionId: did }), ahora);
    }
    return vencidas;
  }

  /** Una pregunta de un agente entra en la cola. Repetirla con la misma versión no la repite. */
  preguntar(entrada: unknown, ahora: Minuto, origen: Origen): ResultadoPreguntar {
    this.vencer(ahora);
    const e = leer(entrada);
    if (typeof e === 'string') return { ok: false, motivo: 'ENTRADA_INVALIDA', detalle: e };
    if (origen !== 'AGENTE_AUTENTICADO') {
      return { ok: false, motivo: 'ORIGEN_NO_AUTENTICADO', detalle: 'solo un agente autenticado pregunta' };
    }
    const previa = this.reg.get(e.id);
    if (previa && (previa.e.clase !== e.clase || previa.e.trabajo !== e.trabajo || previa.e.agente !== e.agente || previa.e.tema !== e.tema)) {
      return { ok: false, motivo: 'ID_REUTILIZADO', detalle: 'ese identificador es de otra pregunta' };
    }
    if (previa && previa.e.version === e.version) {
      return { ok: true, nueva: false, estado: previa.estado, tarjeta: claveGrupo(previa.e), decision: null };
    }
    if (e.caduca <= ahora) {
      return { ok: false, motivo: 'YA_CADUCADA', detalle: 'llegó ya vencida: el trabajo queda en espera' };
    }
    const bq = this.bloqueo(e.trabajo);
    if (bq !== null) {
      return { ok: false, motivo: 'BLOQUEADA', detalle: `el sistema está en ${bq}: la pregunta no entra` };
    }
    // Reabrir una pregunta vencida o ya contestada con otra versión cuenta como la repregunta de
    // la ventana, igual que `repreguntar`: sin tope, un agente insistiría con v2, v3… cada minuto.
    if (previa && previa.estado !== 'ABIERTA' && !this.gastarVentana(previa, ahora)) {
      return { ok: false, motivo: 'YA_REPREGUNTADA_EN_VENTANA', detalle: 'ya se volvió a preguntar en esta ventana' };
    }
    if (previa) {
      // El contenido cambió: la versión anterior y cualquier respuesta a ella ya no valen.
      previa.e = e;
      previa.estado = 'ABIERTA';
      previa.caduca = e.caduca;
      previa.respuesta = null;
      const item = this.politica.bandeja.porDecision(this.decisionId(e.id));
      if (item) {
        item.texto = this.redactada(e.nivel) ? null : e.que;
        item.pendiente = true;
      }
      return { ok: true, nueva: false, estado: 'ABIERTA', tarjeta: claveGrupo(e), decision: null };
    }

    const did = this.decisionId(e.id);
    const unida = e.clase === 'DECISION' && e.tema !== undefined && [...this.reg.values()].some(
      (r) => r.estado === 'ABIERTA' && claveGrupo(r.e) === claveGrupo(e),
    );
    let decision: Decision | null = null;
    if (unida) {
      // Misma pregunta que otra abierta: no gasta otro aviso, se une a su tarjeta.
      const ap = { en: ahora, accion: 'AGRUPAR' as const, motivo: m('AVISO_AGRUPADO'), hasta: null };
      this.politica.bandeja.meter({
        eventoId: did, decisionId: did, objetivo: e.trabajo, plazo: e.caduca, coste: e.costeRetraso,
        individual: false, texto: this.redactada(e.nivel) ? null : e.que, historial: [ap], pendiente: true,
      });
      this.politica.estado.preguntadas.add(did);
      this.politica.ledger.descartar({ eventoId: did, en: ahora, accion: ap.accion, motivo: ap.motivo });
    } else {
      const tipo: Tipo = e.clase === 'PERMISO'
        ? { k: 'APROBACION_SEGURIDAD', decisionId: did }
        : { k: 'DECISION', decisionId: did };
      const ev: Evento = {
        ...deAgente(did, tipo), origen, objetivo: e.trabajo, plazo: e.caduca, caduca: e.caduca,
        costeRetraso: e.costeRetraso, nivel: e.nivel, texto: e.que,
      };
      decision = this.politica.decidir(ev, ahora);
      if (decision.accion === 'REGISTRAR') {
        const k = decision.motivo.k;
        if (k === 'ORIGEN_NO_AUTENTICADO') {
          return { ok: false, motivo: 'ORIGEN_NO_AUTENTICADO', detalle: 'solo un agente autenticado pregunta' };
        }
        return { ok: false, motivo: k === 'YA_PREGUNTADA' ? 'YA_PREGUNTADA' : 'NO_ADMITIDA', detalle: `la política no la admite (${k})` };
      }
    }
    this.reg.set(e.id, { e, estado: 'ABIERTA', caduca: e.caduca, desde: ahora, respuesta: null, repreguntas: new Map() });
    return { ok: true, nueva: true, estado: 'ABIERTA', tarjeta: claveGrupo(e), decision };
  }

  /**
   * Vuelve a poner en la cola una pregunta vencida con un plazo nuevo. Como mucho una vez por
   * ventana y por pregunta; el intento rechazado no cambia nada.
   */
  repreguntar(id: string, nuevaCaduca: unknown, ahora: Minuto): ResultadoRepregunta {
    this.vencer(ahora);
    const r = this.reg.get(id);
    if (!r) return { ok: false, motivo: 'DESCONOCIDA' };
    if (r.estado !== 'DEFER') return { ok: false, motivo: 'NO_ESTA_EN_DEFER' };
    if (typeof nuevaCaduca !== 'number' || !Number.isFinite(nuevaCaduca) || nuevaCaduca <= ahora) {
      return { ok: false, motivo: 'CADUCA_INVALIDA' };
    }
    if (this.bloqueo(r.e.trabajo) !== null) return { ok: false, motivo: 'BLOQUEADA' };
    if (!this.gastarVentana(r, ahora)) return { ok: false, motivo: 'YA_REPREGUNTADA_EN_VENTANA' };
    r.estado = 'ABIERTA';
    r.caduca = nuevaCaduca;
    return { ok: true, caduca: nuevaCaduca };
  }

  private miembros(clave: string, estado: EstadoPregunta): Array<[string, Registro]> {
    return [...this.reg].filter(([, r]) => r.estado === estado && claveGrupo(r.e) === clave);
  }

  private tarjetaDe(clave: string, estado: 'ABIERTA' | 'DEFER'): Tarjeta | null {
    const ms = this.miembros(clave, estado).sort((a, b) => (a[0] < b[0] ? -1 : 1));
    const primera = ms[0];
    if (!primera) return null;
    const nivel = Math.max(...ms.map(([, r]) => r.e.nivel)) as Nivel;
    const redactada = this.redactada(nivel);
    const e = primera[1].e;
    const extra = ms.length > 1 ? ` (+${ms.length - 1} más con la misma pregunta)` : '';
    return Object.freeze({
      id: estado === 'ABIERTA' ? clave : `${clave}${SUFIJO_VENCIDA}`,
      version: ms.map(([id, r]) => `${id}@${r.e.version}`).join('|'),
      estado,
      clase: e.clase,
      preguntas: Object.freeze(ms.map(([id]) => id)),
      trabajos: Object.freeze([...new Set(ms.map(([, r]) => r.e.trabajo))].sort()),
      obligatoria: ms.some(([, r]) => r.e.obligatoria),
      caduca: Math.min(...ms.map(([, r]) => r.caduca)),
      desde: Math.min(...ms.map(([, r]) => r.desde)),
      nivel,
      redactada,
      que: redactada ? null : plano(e.que) + extra,
      porQue: redactada ? null : plano(e.porQue),
      siNoContestas: redactada ? null : plano(e.siNoContestas),
      siAplazas: redactada ? null : plano(e.siAplazas),
    });
  }

  /** Todas las tarjetas sin responder, vigentes y vencidas, sin mirar el modo. */
  private todas(ahora: Minuto): Tarjeta[] {
    this.vencer(ahora);
    const claves = new Set([...this.reg.values()].filter((r) => r.estado !== 'RESPONDIDA').map((r) => claveGrupo(r.e)));
    const out: Tarjeta[] = [];
    for (const k of claves) {
      for (const est of ['ABIERTA', 'DEFER'] as const) {
        const t = this.tarjetaDe(k, est);
        if (t) out.push(t);
      }
    }
    return out.sort((a, b) => Number(b.obligatoria) - Number(a.obligatoria) || a.caduca - b.caduca || (a.id < b.id ? -1 : 1));
  }

  /**
   * Lo que se puede enseñar ahora. Con un modo que no admite preguntas (foco, descanso, fuera
   * o sin declarar) no se enseña nada, pero nada se pierde: sigue pendiente, `estado` lo cuenta
   * y al volver el modo disponible aparece, también lo que venció mientras tanto.
   */
  visibles(ahora: Minuto): Tarjeta[] {
    const t = this.todas(ahora);
    return this.politica.modoEfectivo(ahora) === 'DISPONIBLE' ? t : [];
  }

  /**
   * Una respuesta de la persona. Vale solo si la tarjeta existe, sigue abierta, su versión es la
   * que se enseñó y no ha vencido. Si no, se rechaza sin efecto y se devuelve la tarjeta actual.
   */
  responder(respuesta: unknown, ahora: Minuto, origen: Origen): ResultadoRespuesta {
    this.vencer(ahora);
    const rechazo = (motivo: MotivoRechazoRespuesta, clave: string | null, texto: string): ResultadoRespuesta => {
      const actual = clave === null ? null : (this.tarjetaDe(clave, 'ABIERTA') ?? this.tarjetaDe(clave, 'DEFER'));
      return { ok: false, motivo, volverAEnsenar: actual, texto };
    };
    if (respuesta === null || typeof respuesta !== 'object' || Array.isArray(respuesta)) {
      return rechazo('ENTRADA_INVALIDA', null, 'La respuesta no se puede leer.');
    }
    const r = respuesta as Record<string, unknown>;
    const tarjeta = cad(r.tarjeta);
    const version = cad(r.version);
    const valor = cad(r.valor);
    if (tarjeta === null || version === null || valor === null) {
      return rechazo('ENTRADA_INVALIDA', null, 'Falta la tarjeta, su versión o el valor de la respuesta.');
    }
    if (origen !== 'PERSONA') return rechazo('ORIGEN_NO_VALIDO', null, 'Solo la persona responde.');
    const vencida = tarjeta.endsWith(SUFIJO_VENCIDA);
    const clave = vencida ? tarjeta.slice(0, -SUFIJO_VENCIDA.length) : tarjeta;
    const abierta = vencida ? null : this.tarjetaDe(clave, 'ABIERTA');
    if (abierta === null) {
      if (this.tarjetaDe(clave, 'DEFER') !== null) {
        return rechazo('CADUCADA', clave, 'Esa pregunta caducó y el trabajo sigue en espera. Te la vuelvo a enseñar con lo actual.');
      }
      if (this.miembros(clave, 'RESPONDIDA').length > 0) return rechazo('YA_RESPONDIDA', null, 'Esa pregunta ya tiene respuesta.');
      return rechazo('DESCONOCIDA', null, 'No conozco esa tarjeta.');
    }
    if (abierta.version !== version) {
      return rechazo('VERSION_CAMBIADA', clave, 'Esa pregunta cambió desde que la viste. Te la vuelvo a enseñar con lo actual.');
    }
    if (abierta.clase === 'PERMISO' && !VALORES_PERMISO.includes(valor)) {
      return rechazo('VALOR_INVALIDO', clave, 'Un permiso solo se concede o se deniega.');
    }
    const resueltas: string[] = [];
    for (const [id, reg] of this.miembros(clave, 'ABIERTA')) {
      reg.estado = 'RESPONDIDA';
      reg.respuesta = valor;
      this.politica.control({ k: 'RESPONDER', decisionId: this.decisionId(id) }, 'PERSONA', ahora);
      resueltas.push(id);
    }
    return { ok: true, tarjeta: clave, valor, resueltas };
  }

  /** Respuesta humana registrada a una pregunta; `null` si no la hay o su versión cambió. */
  respuestaDe(id: string): string | null {
    const r = this.reg.get(id);
    return r && r.estado === 'RESPONDIDA' ? r.respuesta : null;
  }

  /**
   * ¿Puede ejecutarse el efecto que esperaba esta pregunta? Solo con una respuesta humana
   * registrada y, si es un permiso, concedida. Sin pregunta, vencida o sin respuesta: no. Con el
   * sistema en PARA o el trabajo vetado: no, aunque la respuesta exista. En una decisión solo
   * dice que la persona contestó: el valor elegido se lee con `respuestaDe`.
   */
  puedeEjecutar(id: string): boolean {
    const r = this.reg.get(id);
    if (!r || r.estado !== 'RESPONDIDA' || r.respuesta === null) return false;
    if (this.bloqueo(r.e.trabajo) !== null) return false;
    return r.e.clase === 'PERMISO' ? r.respuesta === 'CONCEDER' : true;
  }

  /** `LIBRE` si no tiene ninguna pregunta sin responder; `DEFER` si alguna venció; `EN_ESPERA` si no. */
  estadoTrabajo(trabajo: string, ahora: Minuto): 'LIBRE' | 'EN_ESPERA' | 'DEFER' {
    this.vencer(ahora);
    const mias = [...this.reg.values()].filter((r) => r.e.trabajo === trabajo && r.estado !== 'RESPONDIDA');
    if (mias.length === 0) return 'LIBRE';
    return mias.some((r) => r.estado === 'DEFER') ? 'DEFER' : 'EN_ESPERA';
  }

  /** Qué ocupa al sistema. No depende de que ningún agente esté libre: solo lee el registro. */
  estado(ahora: Minuto): EstadoPreguntas {
    const todas = this.todas(ahora);
    const enseñable = this.politica.modoEfectivo(ahora) === 'DISPONIBLE';
    const desde = todas.map((t) => t.desde);
    return Object.freeze({
      abiertas: todas.filter((t) => t.estado === 'ABIERTA').length,
      enEspera: todas.filter((t) => t.estado === 'DEFER').length,
      obligatorias: todas.filter((t) => t.obligatoria).length,
      ocultasPorModo: enseñable ? 0 : todas.length,
      trabajosEnEspera: Object.freeze([...new Set(todas.flatMap((t) => t.trabajos))].sort()),
      masAntiguaMin: desde.length === 0 ? null : ahora - Math.min(...desde),
    });
  }
}

/**
 * Adaptador para `construirCola` (fuente «Esperan algo de ti»): una entrada por tarjeta visible.
 * Una tarjeta vencida lleva su `caduca` pasada, así que la cola la enseña en «Caducadas».
 */
export function dePreguntasAgentes(pr: Preguntas, ahora: Minuto): unknown[] {
  return pr.visibles(ahora).map((t) => ({
    id: t.id,
    que: t.que,
    porQue: t.porQue,
    siNoContestas: t.estado === 'DEFER'
      ? `El trabajo ${t.trabajos.map((x) => `«${plano(x)}»`).join(', ')} sigue en espera; no se ejecutó nada.`
      : t.siNoContestas,
    siAplazas: t.siAplazas,
    caduca: t.caduca,
    desde: t.desde,
    critica: t.obligatoria,
    nivel: t.nivel,
  }));
}
