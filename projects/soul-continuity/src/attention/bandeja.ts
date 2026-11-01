// Bandeja de decisiones: agrupa por objetivo, plazo (día) y coste de retraso.
// Las aprobaciones de seguridad y los bloqueos van siempre solos. Cada aplazamiento queda
// registrado con motivo, acción y hasta cuándo, y la persona puede listarlo.

import type { Aplazamiento } from './decision.ts';
import type { CosteRetraso } from './modelo.ts';
import { DIA, type Minuto } from './tiempo.ts';

export interface ClaveGrupo {
  objetivo: string;
  plazoDia: number | null;
  coste: CosteRetraso;
}

export interface Item {
  eventoId: string;
  decisionId: string | null;
  objetivo: string | null;
  plazo: Minuto | null;
  coste: CosteRetraso;
  /** Va solo: nunca se agrupa (seguridad, bloqueo, permiso, alerta). */
  individual: boolean;
  /** `null` si el contenido superaba el nivel del canal: solo queda la referencia. */
  texto: string | null;
  historial: Aplazamiento[];
  pendiente: boolean;
}

export function claveDe(i: Item): ClaveGrupo | null {
  if (i.individual) return null;
  return {
    objetivo: i.objetivo ?? '(sin objetivo)',
    plazoDia: i.plazo === null ? null : Math.floor(i.plazo / DIA),
    coste: i.coste,
  };
}

const ORDEN_COSTE: Record<CosteRetraso, number> = { BAJO: 0, MEDIO: 1, ALTO: 2 };

function comparar(a: ClaveGrupo, b: ClaveGrupo): number {
  if (a.objetivo !== b.objetivo) return a.objetivo < b.objetivo ? -1 : 1;
  if (a.plazoDia !== b.plazoDia) return (a.plazoDia ?? -1) - (b.plazoDia ?? -1);
  return ORDEN_COSTE[a.coste] - ORDEN_COSTE[b.coste];
}

export class Bandeja {
  private readonly lista: Item[] = [];

  items(): readonly Item[] {
    return this.lista;
  }

  porDecision(decisionId: string): Item | undefined {
    return this.lista.find((i) => i.decisionId === decisionId);
  }

  porEvento(eventoId: string): Item | undefined {
    return this.lista.find((i) => i.eventoId === eventoId);
  }

  meter(item: Item): void {
    this.lista.push(item);
  }

  anotar(decisionId: string, a: Aplazamiento): void {
    this.porDecision(decisionId)?.historial.push(a);
  }

  resolver(decisionId: string): boolean {
    let hecho = false;
    for (const i of this.lista) {
      if (i.decisionId === decisionId) {
        i.pendiente = false;
        hecho = true;
      }
    }
    return hecho;
  }

  /** Por qué y hasta cuándo se aplazó un evento. */
  explicar(eventoId: string): readonly Aplazamiento[] | undefined {
    return this.porEvento(eventoId)?.historial;
  }

  /** Grupos de pendientes. Los individuales salen cada uno en su grupo, con clave `null`. */
  grupos(): Array<[ClaveGrupo | null, Item[]]> {
    const agrupados: Array<[ClaveGrupo, Item[]]> = [];
    const solos: Array<[ClaveGrupo | null, Item[]]> = [];
    for (const i of this.lista.filter((x) => x.pendiente)) {
      const k = claveDe(i);
      if (k === null) {
        solos.push([null, [i]]);
        continue;
      }
      const g = agrupados.find(([c]) => comparar(c, k) === 0);
      if (g) g[1].push(i);
      else agrupados.push([k, [i]]);
    }
    agrupados.sort((a, b) => comparar(a[0], b[0]));
    return [...solos, ...agrupados];
  }
}
