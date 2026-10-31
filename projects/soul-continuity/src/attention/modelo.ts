// Lo que declara la persona (configuración) y lo que llega del sistema (eventos).
// No hay ningún campo que describa a la persona: ni fatiga, ni actividad, ni respuestas.

import type { Franja, Minuto } from './tiempo.ts';

export type Modo = 'DISPONIBLE' | 'FOCO' | 'DESCANSO' | 'FUERA';
export const MODOS: readonly Modo[] = ['DISPONIBLE', 'FOCO', 'DESCANSO', 'FUERA'];

/** N1 (público) … N4 (el más confidencial). */
export type Nivel = 1 | 2 | 3 | 4;

/** Modo declarado por la persona; `hasta = null` no vence. */
export interface ModoDeclarado {
  modo: Modo;
  hasta: Minuto | null;
}

/**
 * Alerta que la persona ha declarado como urgente (lista cerrada). Solo cuenta si el evento
 * trae su `codigo`, la fuente está autenticada y el modo activo está en `modos`.
 * En `DISPONIBLE` una alerta declarada siempre pasa.
 */
export interface ReglaAlerta {
  codigo: string;
  /** Modos en los que la persona marcó que esta alerta llega aunque el modo difiera todo. */
  modos: readonly Modo[];
  /**
   * Regla por remitente. La configuración lo declara para que se vea; en la ruta web ninguna
   * regla produce alerta (de remitente o no), solo aviso, porque allí no hay identidad.
   */
  porRemitente?: boolean;
}

/** Hora fija (minuto del día, hora local) de un resumen. */
export interface Resumenes {
  inicio?: number;
  cierre?: number;
}

/** Política de atención que decide la persona. Todo es declarado; nada se calcula de ella. */
export interface Config {
  /** Ventanas en las que acepta avisos y preguntas. */
  ventanas: readonly Franja[];
  /** Franjas de descanso declaradas: modo efectivo `DESCANSO` salvo declaración vigente. */
  descansos: readonly Franja[];
  /** Máximo de contactos (preguntas, aprobaciones y avisos) por instancia de ventana. */
  presupuesto: number;
  /** Tope propio de alertas por ventana, fuera del presupuesto. Por defecto 3. */
  topeAlertas?: number;
  /** `null` = no ha declarado: no hay disponibilidad implícita. */
  modoPorDefecto: Modo | null;
  alertas: readonly ReglaAlerta[];
  /** Nivel máximo que puede viajar por el canal de avisos. */
  canalNivelMax: Nivel;
  resumenes?: Resumenes;
}

export const TOPE_ALERTAS_POR_DEFECTO = 3;

export type Origen = 'PERSONA' | 'AGENTE_AUTENTICADO' | 'NO_AUTENTICADO';
export type Urgencia = 'NORMAL' | 'ALTA' | 'CRITICA';
export type CosteRetraso = 'BAJO' | 'MEDIO' | 'ALTO';
export type EfectoPrevio = 'NO_OCURRIO' | 'DESCONOCIDO';
/** Ruta por la que llegó el evento: la web no tiene identidad autenticada del remitente. */
export type Ruta = 'API' | 'WEB';

export type Tipo =
  /** Informativo: no interrumpe; va al siguiente resumen o se registra. */
  | { k: 'AVISO'; rutinario: boolean }
  /** Aviso a notificar (reunión en 15 min…): gasta presupuesto dentro de ventana. */
  | { k: 'NOTIFICACION' }
  | { k: 'DECISION'; decisionId: string }
  | { k: 'APROBACION_SEGURIDAD'; decisionId: string }
  | { k: 'PETICION_PERMISO'; dentroDeContrato: boolean }
  | { k: 'REINTENTO'; efectoPrevio: EfectoPrevio }
  /** Venció el plazo de una pregunta sin respuesta. */
  | { k: 'SILENCIO'; decisionId: string };

export interface Evento {
  id: string;
  origen: Origen;
  tipo: Tipo;
  ruta: Ruta;
  objetivo: string | null;
  plazo: Minuto | null;
  costeRetraso: CosteRetraso;
  nivel: Nivel;
  caduca: Minuto | null;
  /** Código de alerta estructurado; solo cuenta si la fuente está autenticada y hay regla. */
  codigoAlerta: string | null;
  /** Lo que dice el contenido. Se guarda; no decide. */
  urgenciaEnContenido: Urgencia;
  /** Lo que sugiere un LLM. Se guarda; no decide. */
  urgenciaSugeridaLlm: Urgencia | null;
  texto: string;
}

/** Evento mínimo de un agente autenticado, nivel N1, coste medio, ruta API. */
export function deAgente(id: string, tipo: Tipo): Evento {
  return {
    id,
    origen: 'AGENTE_AUTENTICADO',
    tipo,
    ruta: 'API',
    objetivo: null,
    plazo: null,
    costeRetraso: 'MEDIO',
    nivel: 1,
    caduca: null,
    codigoAlerta: null,
    urgenciaEnContenido: 'NORMAL',
    urgenciaSugeridaLlm: null,
    texto: '',
  };
}

export function pideDecision(ev: Evento): boolean {
  return ev.tipo.k !== 'AVISO' && ev.tipo.k !== 'SILENCIO' && ev.tipo.k !== 'NOTIFICACION';
}

/** Órdenes de control. Detener siempre se acepta; reanudar y cambiar el modo, solo la persona. */
export type Control =
  | { k: 'PARA' }
  | { k: 'REANUDAR' }
  | { k: 'VETAR'; objetivo: string }
  | { k: 'LEVANTAR_VETO'; objetivo: string }
  | { k: 'DECLARAR_MODO'; modo: ModoDeclarado }
  | { k: 'RESPONDER'; decisionId: string };
