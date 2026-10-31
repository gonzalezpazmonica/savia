// Tiempo local declarado. La librería no lee el reloj: el minuto entra como argumento.
// `Minuto` = minutos desde 1970-01-01 00:00 en la hora local que declara la persona.

export type Minuto = number;
export const DIA: Minuto = 1440;

/** 0 = lunes … 6 = domingo (1970-01-01 fue jueves). */
export function diaSemana(t: Minuto): number {
  return (Math.floor(t / DIA) + 3) % 7;
}

export function minutoDelDia(t: Minuto): number {
  return t % DIA;
}

/**
 * Franja semanal declarada: días (bit 0 = lunes) y horas `[inicio, fin)`.
 * Si `fin < inicio`, cruza la medianoche y pertenece al día en que empieza.
 * `fin == inicio` no contiene ningún minuto (falla cerrado).
 */
export class Franja {
  readonly dias: number;
  readonly inicio: number;
  readonly fin: number;

  constructor(dias: number, inicio: number, fin: number) {
    this.dias = dias;
    this.inicio = inicio;
    this.fin = fin;
  }

  /** `dias`: 0 = lunes … 6 = domingo. Horas como `[hh, mm]`. */
  static nueva(dias: readonly number[], inicio: readonly [number, number], fin: readonly [number, number]): Franja {
    let mascara = 0;
    for (const d of dias) {
      if (Number.isInteger(d) && d >= 0 && d < 7) mascara |= 1 << d;
    }
    return new Franja(mascara, inicio[0] * 60 + inicio[1], fin[0] * 60 + fin[1]);
  }

  private diaIncluido(diaAbs: number): boolean {
    return (this.dias & (1 << diaSemana(diaAbs * DIA))) !== 0;
  }

  /** Inicio de la instancia de la franja que contiene `t`, si la hay. */
  instancia(t: Minuto): Minuto | null {
    const d = Math.floor(t / DIA);
    const m = minutoDelDia(t);
    if (this.inicio < this.fin) {
      if (this.diaIncluido(d) && m >= this.inicio && m < this.fin) return d * DIA + this.inicio;
    } else if (this.inicio > this.fin) {
      if (this.diaIncluido(d) && m >= this.inicio) return d * DIA + this.inicio;
      if (d > 0 && this.diaIncluido(d - 1) && m < this.fin) return (d - 1) * DIA + this.inicio;
    }
    return null;
  }

  /** Primer inicio de instancia estrictamente posterior a `t`. */
  siguienteInicio(t: Minuto): Minuto | null {
    if (this.inicio === this.fin) return null;
    for (let k = 0; k <= 7; k++) {
      const d = Math.floor(t / DIA) + k;
      if (!this.diaIncluido(d)) continue;
      const s = d * DIA + this.inicio;
      if (s > t) return s;
    }
    return null;
  }
}

function minimo(xs: Array<number | null>): number | null {
  const v = xs.filter((x): x is number => x !== null);
  return v.length === 0 ? null : Math.min(...v);
}

/** Instancia de ventana que contiene `t` (la de inicio más temprano si se solapan). */
export function instanciaEn(franjas: readonly Franja[], t: Minuto): Minuto | null {
  return minimo(franjas.map((f) => f.instancia(t)));
}

/** Siguiente inicio de cualquier franja, estrictamente posterior a `t`. */
export function siguienteInicioEn(franjas: readonly Franja[], t: Minuto): Minuto | null {
  return minimo(franjas.map((f) => f.siguienteInicio(t)));
}
