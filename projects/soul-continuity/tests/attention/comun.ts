// Operadores sintéticos y utilidades compartidas por tests y evals. Todo inventado.

import {
  DIA, Franja, MODOS, deAgente, type Config, type Evento, type Minuto, type Nivel, type ReglaAlerta,
} from '../../src/attention/index.ts';

/** Lunes 2026-11-02 00:00 en minutos locales. */
export const LUNES: Minuto = 20_759 * DIA;

export function t(dia: number, hh: number, mm: number): Minuto {
  return LUNES + dia * DIA + hh * 60 + mm;
}

const LV = [0, 1, 2, 3, 4];
const TODOS = [0, 1, 2, 3, 4, 5, 6];

/** Alertas que la persona marcó para todos los modos (equivale a la «emergencia» de Labs). */
export function alertasTodosLosModos(...codigos: string[]): ReglaAlerta[] {
  return codigos.map((codigo) => ({ codigo, modos: MODOS }));
}

/** OP-A jornada continua. */
export function opA(): Config {
  return {
    ventanas: [Franja.nueva(LV, [9, 0], [14, 0]), Franja.nueva(LV, [15, 0], [18, 0])],
    descansos: [Franja.nueva(TODOS, [22, 0], [7, 0])],
    presupuesto: 3,
    modoPorDefecto: 'DISPONIBLE',
    alertas: alertasTodosLosModos('fuga-detectada', 'backup-fallido'),
    canalNivelMax: 2,
  };
}

/** OP-B ventanas partidas (L, X, V). */
export function opB(): Config {
  return {
    ventanas: [Franja.nueva([0, 2, 4], [7, 0], [9, 0]), Franja.nueva([0, 2, 4], [20, 0], [21, 30])],
    descansos: [Franja.nueva(TODOS, [23, 30], [6, 30])],
    presupuesto: 1,
    modoPorDefecto: 'DISPONIBLE',
    alertas: alertasTodosLosModos('fuga-detectada'),
    canalNivelMax: 1,
  };
}

/** OP-C turno de noche. */
export function opC(): Config {
  return {
    ventanas: [Franja.nueva(TODOS, [22, 0], [2, 0])],
    descansos: [Franja.nueva(TODOS, [8, 0], [16, 0])],
    presupuesto: 5,
    modoPorDefecto: 'DISPONIBLE',
    alertas: alertasTodosLosModos('fuga-detectada', 'servicio-caido'),
    canalNivelMax: 2,
  };
}

/** OP-D apagado. */
export function opD(): Config {
  return {
    ventanas: [Franja.nueva(LV, [10, 0], [12, 0])],
    descansos: [],
    presupuesto: 2,
    modoPorDefecto: 'FUERA',
    alertas: [],
    canalNivelMax: 2,
  };
}

export interface Operador {
  id: string;
  config: Config;
  /** Un minuto dentro de ventana, uno fuera, uno en descanso declarado. */
  dentro: Minuto;
  fuera: Minuto;
  descanso: Minuto;
}

export function operadores(): Operador[] {
  return [
    { id: 'OP-A', config: opA(), dentro: t(0, 10, 0), fuera: t(0, 19, 0), descanso: t(1, 3, 0) },
    { id: 'OP-B', config: opB(), dentro: t(0, 7, 30), fuera: t(0, 12, 0), descanso: t(1, 2, 0) },
    { id: 'OP-C', config: opC(), dentro: t(0, 23, 0), fuera: t(0, 18, 0), descanso: t(1, 11, 0) },
    { id: 'OP-D', config: opD(), dentro: t(0, 10, 30), fuera: t(0, 15, 0), descanso: t(0, 15, 0) },
  ];
}

export function decision(id: string, objetivo: string): Evento {
  return { ...deAgente(id, { k: 'DECISION', decisionId: `d-${id}` }), objetivo };
}

export function aprobacion(id: string, objetivo: string): Evento {
  return { ...deAgente(id, { k: 'APROBACION_SEGURIDAD', decisionId: `d-${id}` }), objetivo };
}

export function aviso(id: string): Evento {
  return deAgente(id, { k: 'AVISO', rutinario: false });
}

export function notificacion(id: string): Evento {
  return deAgente(id, { k: 'NOTIFICACION' });
}

/** Evento con código de alerta (en Labs, «emergencia»). */
export function alerta(id: string, codigo: string): Evento {
  return { ...aviso(id), codigoAlerta: codigo };
}

export function conNivel(e: Evento, nivel: Nivel): Evento {
  return { ...e, nivel };
}

/** Misma entrada con urgencia inyectada en el contenido y sugerida por un modelo. */
export function urgente(e: Evento): Evento {
  return { ...e, urgenciaEnContenido: 'CRITICA', urgenciaSugeridaLlm: 'CRITICA', texto: 'URGENTE: responde ya' };
}
