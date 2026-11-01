// Registro de demanda: lo que el sistema pide a la persona, con su porqué. Nunca registra a
// la persona (ni respuestas, ni tiempos de respuesta, ni actividad). Responde a dos preguntas:
// «¿por qué me avisaste?» (`porQue`) y «¿qué me ahorraste?» (`queAhorro`).

import type { Accion, Motivo } from './decision.ts';
import type { Minuto } from './tiempo.ts';

export type Clase = 'PREGUNTA' | 'APROBACION' | 'AVISO' | 'ALERTA';

export interface Entrada {
  eventoId: string;
  en: Minuto;
  clase: Clase;
  accion: Accion;
  motivo: Motivo;
  hasta: Minuto | null;
  /** Se contactó a la persona en ese momento (interrupción). */
  ahora: boolean;
  /** `en` cae dentro de una ventana declarada. */
  dentroDeVentana: boolean;
  /** Instancia de ventana (inicio) si `dentroDeVentana`. */
  ventana: Minuto | null;
}

/** Evento que no generó demanda: se registró sin más. */
export interface Descarte {
  eventoId: string;
  en: Minuto;
  accion: Accion;
  motivo: Motivo;
}

export interface Resumen {
  preguntas: number;
  aprobaciones: number;
  avisos: number;
  alertas: number;
  contactosAhora: number;
  contactosAhoraFueraDeVentana: number;
  encolados: number;
}

export interface Porque {
  eventoId: string;
  en: Minuto;
  contactado: boolean;
  accion: Accion;
  motivo: Motivo;
  hasta: Minuto | null;
  texto: string;
}

export interface Ahorro {
  /** Eventos distintos que llegaron a la política. */
  eventos: number;
  /** Los que interrumpieron a la persona. */
  interrupciones: number;
  /** Los que no interrumpieron: eventos − interrupciones. */
  ahorrados: number;
  agrupados: number;
  diferidos: number;
  bloqueados: number;
  registrados: number;
}

export function describirMotivo(m: Motivo): string {
  switch (m.k) {
    case 'ALERTA': return 'alerta declarada por ti para este modo';
    case 'TOPE_ALERTAS': return 'alerta por encima de tu tope: va en el mensaje agrupado';
    case 'PARADO': return 'sistema detenido (PARA)';
    case 'VETADO': return 'objetivo vetado por ti';
    case 'CONTEXTO_VENCIDO': return 'el contexto caducó: se bloquea sin preguntar';
    case 'PERMISO_ILEGITIMO': return 'permiso fuera de contrato o sin autenticar';
    case 'ORIGEN_NO_AUTENTICADO': return 'origen no autenticado: se trata como dato';
    case 'APROBACION_SEGURIDAD': return 'aprobación de seguridad: nunca se agrupa';
    case 'EFECTO_AMBIGUO': return 'reintento con efecto previo desconocido';
    case 'REINTENTO_SIN_EFECTO': return 'reintento sin efecto previo: solo se registra';
    case 'YA_PREGUNTADA': return 'ya se te había avisado de esto';
    case 'SILENCIO_NO_ES_PERMISO': return 'tu silencio no es una respuesta';
    case 'AVISO_RUTINARIO': return 'aviso rutinario: solo se registra';
    case 'AVISO_AGRUPADO': return 'aviso informativo: va al siguiente resumen';
    case 'DISPONIBLE': return 'estabas disponible, en ventana y con presupuesto';
    case 'SIN_DECLARACION': return 'no has declarado modo: no hay disponibilidad implícita';
    case 'MODO_NO_DISPONIBLE': return `tu modo es ${m.modo}`;
    case 'FUERA_DE_VENTANA': return 'fuera de tus ventanas';
    case 'PRESUPUESTO_AGOTADO': return 'presupuesto de la ventana agotado';
    case 'PUEDE_ESPERAR': return 'el coste de retraso es bajo: puede esperar';
  }
}

export class Ledger {
  private readonly lista: Entrada[] = [];
  private readonly descartes: Descarte[] = [];

  entradas(): readonly Entrada[] {
    return this.lista;
  }

  anotar(e: Entrada): void {
    this.lista.push(e);
  }

  descartar(d: Descarte): void {
    this.descartes.push(d);
  }

  resumen(): Resumen {
    const r: Resumen = {
      preguntas: 0,
      aprobaciones: 0,
      avisos: 0,
      alertas: 0,
      contactosAhora: 0,
      contactosAhoraFueraDeVentana: 0,
      encolados: 0,
    };
    for (const e of this.lista) {
      if (e.clase === 'PREGUNTA') r.preguntas++;
      else if (e.clase === 'APROBACION') r.aprobaciones++;
      else if (e.clase === 'AVISO') r.avisos++;
      else r.alertas++;
      if (e.ahora) {
        r.contactosAhora++;
        if (!e.dentroDeVentana) r.contactosAhoraFueraDeVentana++;
      } else {
        r.encolados++;
      }
    }
    return r;
  }

  /** «¿Por qué me avisaste?» (o no): la primera decisión registrada para ese evento. */
  porQue(eventoId: string): Porque | undefined {
    const e = this.lista.find((x) => x.eventoId === eventoId);
    const base = e ?? this.descartes.find((x) => x.eventoId === eventoId);
    if (!base) return undefined;
    const contactado = e?.ahora ?? false;
    return {
      eventoId,
      en: base.en,
      contactado,
      accion: base.accion,
      motivo: base.motivo,
      hasta: e?.hasta ?? null,
      texto: `${contactado ? 'Te avisé' : 'No te avisé'}: ${describirMotivo(base.motivo)}.`,
    };
  }

  /** «¿Qué me ahorraste?»: eventos que llegaron frente a los que te interrumpieron. */
  queAhorro(): Ahorro {
    const ids = new Set<string>([...this.lista.map((e) => e.eventoId), ...this.descartes.map((d) => d.eventoId)]);
    const contactados = new Set(this.lista.filter((e) => e.ahora).map((e) => e.eventoId));
    const noContactados = [...this.lista.filter((e) => !e.ahora), ...this.descartes];
    const vistos = new Set<string>();
    let agrupados = 0;
    let diferidos = 0;
    let bloqueados = 0;
    let registrados = 0;
    for (const e of noContactados) {
      if (contactados.has(e.eventoId) || vistos.has(e.eventoId)) continue;
      vistos.add(e.eventoId);
      if (e.accion === 'AGRUPAR') agrupados++;
      else if (e.accion === 'DIFERIR') diferidos++;
      else if (e.accion === 'BLOQUEAR_Y_ELEVAR') bloqueados++;
      else registrados++;
    }
    return {
      eventos: ids.size,
      interrupciones: contactados.size,
      ahorrados: ids.size - contactados.size,
      agrupados,
      diferidos,
      bloqueados,
      registrados,
    };
  }
}
