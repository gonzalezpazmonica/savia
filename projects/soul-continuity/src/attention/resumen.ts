// Resúmenes de inicio y de cierre a la hora fijada por la persona. Son mensajes programados:
// no gastan presupuesto. Recogen lo que quedó pendiente en la bandeja (avisos que excedieron
// el presupuesto, diferidos por el modo, alertas sin marcar). Lo que solo informa sale una vez:
// tras el resumen ya está entregado. Lo que pide una decisión sigue pendiente hasta que la
// persona responde; el resumen nunca resuelve una decisión.

import type { Item } from './bandeja.ts';
import type { Politica } from './politica.ts';
import { DIA, type Minuto } from './tiempo.ts';

export type TipoResumen = 'INICIO' | 'CIERRE';

/** Un resumen que sale más de esto después de su hora ya no tiene sentido y no se emite. */
export const TOLERANCIA_RESUMEN: Minuto = 60;

export interface LineaResumen {
  eventoId: string;
  /** `null` si el contenido superaba el nivel del canal: solo viaja la referencia. */
  texto: string | null;
}

export interface GrupoResumen {
  /** `null` = elementos que van solos (alertas diferidas, aprobaciones, bloqueos). */
  objetivo: string | null;
  lineas: LineaResumen[];
}

export interface MensajeResumen {
  tipo: TipoResumen;
  /** Hora fijada a la que correspondía. */
  programado: Minuto;
  emitido: Minuto;
  pendientes: number;
  grupos: GrupoResumen[];
  texto: string;
}

function ultimaHora(ahora: Minuto, horaDelDia: number): Minuto {
  const hoy = Math.floor(ahora / DIA) * DIA + horaDelDia;
  return hoy <= ahora ? hoy : hoy - DIA;
}

export function resumenesDebidos(pol: Politica, ahora: Minuto): MensajeResumen[] {
  const cfg = pol.config.resumenes;
  if (!cfg) return [];
  const salida: MensajeResumen[] = [];
  const entregados = new Set<Item>();
  const casos: Array<[TipoResumen, number | undefined, 'inicio' | 'cierre']> = [
    ['INICIO', cfg.inicio, 'inicio'],
    ['CIERRE', cfg.cierre, 'cierre'],
  ];
  for (const [tipo, hora, clave] of casos) {
    if (hora === undefined || !Number.isInteger(hora) || hora < 0 || hora >= DIA) continue;
    const programado = ultimaHora(ahora, hora);
    if (ahora - programado > TOLERANCIA_RESUMEN) continue;
    const previo = pol.estado.resumenes[clave];
    if (previo !== null && previo >= programado) continue;
    pol.estado.resumenes[clave] = programado;
    const grupos: GrupoResumen[] = pol.bandeja.grupos().map(([k, items]) => ({
      objetivo: k === null ? null : k.objetivo,
      lineas: items.map((i) => {
        if (i.decisionId === null) entregados.add(i);
        return { eventoId: i.eventoId, texto: i.texto };
      }),
    }));
    const pendientes = grupos.reduce((n, g) => n + g.lineas.length, 0);
    const titulo = tipo === 'INICIO' ? 'Resumen de inicio' : 'Resumen de cierre';
    salida.push({
      tipo, programado, emitido: ahora, pendientes, grupos,
      texto: `${titulo}: ${pendientes} ${pendientes === 1 ? 'pendiente' : 'pendientes'}.`,
    });
  }
  // Al final, para que inicio y cierre debidos a la vez lleven lo mismo.
  for (const i of entregados) i.pendiente = false;
  // Una alerta sobre el tope que ya salió en el resumen no vuelve en «hay N alertas más».
  const dados = new Set([...entregados].map((i) => i.eventoId));
  if (dados.size > 0) pol.estado.excedidas = pol.estado.excedidas.filter((id) => !dados.has(id));
  return salida;
}
