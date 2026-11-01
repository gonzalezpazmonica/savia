// Salida de la política: acción, motivo y plazo. Compartido por bandeja, registro y política.

import type { Modo } from './modelo.ts';
import type { Minuto } from './tiempo.ts';

export type Accion = 'REGISTRAR' | 'AGRUPAR' | 'AVISAR' | 'PREGUNTAR_UNA_VEZ' | 'BLOQUEAR_Y_ELEVAR' | 'DIFERIR';

export type Motivo =
  | { k: 'ALERTA' }
  | { k: 'TOPE_ALERTAS' }
  | { k: 'PARADO' }
  | { k: 'VETADO' }
  | { k: 'CONTEXTO_VENCIDO' }
  | { k: 'PERMISO_ILEGITIMO' }
  | { k: 'ORIGEN_NO_AUTENTICADO' }
  | { k: 'APROBACION_SEGURIDAD' }
  | { k: 'EFECTO_AMBIGUO' }
  | { k: 'REINTENTO_SIN_EFECTO' }
  | { k: 'YA_PREGUNTADA' }
  | { k: 'SILENCIO_NO_ES_PERMISO' }
  | { k: 'AVISO_RUTINARIO' }
  | { k: 'AVISO_AGRUPADO' }
  | { k: 'DISPONIBLE' }
  | { k: 'SIN_DECLARACION' }
  | { k: 'MODO_NO_DISPONIBLE'; modo: Modo }
  | { k: 'FUERA_DE_VENTANA' }
  | { k: 'PRESUPUESTO_AGOTADO' }
  | { k: 'PUEDE_ESPERAR' };

export type MotivoK = Motivo['k'];

export function motivo(k: Exclude<MotivoK, 'MODO_NO_DISPONIBLE'>): Motivo {
  return { k } as Motivo;
}

export function modoNoDisponible(modo: Modo): Motivo {
  return { k: 'MODO_NO_DISPONIBLE', modo };
}

export function mismoMotivo(a: Motivo, b: Motivo): boolean {
  return a.k === b.k && (a.k !== 'MODO_NO_DISPONIBLE' || (b.k === 'MODO_NO_DISPONIBLE' && a.modo === b.modo));
}

export interface Decision {
  accion: Accion;
  motivo: Motivo;
  /** Se contacta a la persona ahora. */
  contactarAhora: boolean;
  /** Hasta cuándo se aplaza, si se aplaza. */
  hasta: Minuto | null;
  /** El contenido supera el nivel del canal: solo viaja la referencia. */
  redactado: boolean;
  /** El evento traía urgencia (contenido o LLM) que no se ha tenido en cuenta. */
  urgenciaIgnorada: boolean;
  /** Una regla de alerta por remitente llegó por la ruta web: se trató como aviso. */
  degradadaAAviso: boolean;
}

export interface Aplazamiento {
  en: Minuto;
  accion: Accion;
  motivo: Motivo;
  hasta: Minuto | null;
}
