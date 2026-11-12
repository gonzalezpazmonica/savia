// Cola única de atención (SE-514 S1): vista de solo lectura sobre las fuentes que ya piden algo a
// la persona. No es otra bandeja: no guarda nada, no contesta nada y no decide nada. Solo junta
// lo que cada fuente entrega y dice, por cada petición, las cinco cosas de la spec: qué se pide,
// por qué ahora, qué pasa si no contestas, qué cuesta aplazarla y hasta cuándo vale. Lo que la
// fuente no dice se marca como tal; la vista nunca lo inventa.
//
// Fail-closed: una fuente que no entrega una lista es «fallida», no «vacía»; una entrada ilegible
// se cuenta; un nivel ausente o raro es N4 y su contenido no se enseña por encima del canal.
// Ningún texto eleva la urgencia: solo `critica === true`, que ponen los adaptadores desde un
// campo estructurado, adelanta una petición. En S1 nada se oculta por modo: el orden es la
// única diferencia.

import type { Item } from './bandeja.ts';
import type { MotivoK } from './decision.ts';
import type { CosteRetraso, Nivel } from './modelo.ts';
import { DIA, type Minuto } from './tiempo.ts';

/** Las siete fuentes de la tabla de SE-514, en su orden. */
export type Fuente =
  | 'PR_REVISION'
  | 'TARJETA_APROBACION'
  | 'AVISO_SOUL'
  | 'RELEVO_NOCTURNO'
  | 'PENDIENTE_MANANA'
  | 'ESPERAN_ALGO'
  | 'AVISO_RUN';

export const FUENTES: readonly Fuente[] = Object.freeze([
  'PR_REVISION', 'TARJETA_APROBACION', 'AVISO_SOUL', 'RELEVO_NOCTURNO', 'PENDIENTE_MANANA',
  'ESPERAN_ALGO', 'AVISO_RUN',
]);

/** Nombre en lenguaje llano y spec que define cada fuente. */
export const FUENTE_INFO: Readonly<Record<Fuente, { nombre: string; spec: string }>> = Object.freeze({
  PR_REVISION: { nombre: 'PRs esperando revisión', spec: 'SE-458' },
  TARJETA_APROBACION: { nombre: 'Tarjeta de aprobación', spec: 'SE-459' },
  AVISO_SOUL: { nombre: 'Avisos de Soul', spec: 'SE-490' },
  RELEVO_NOCTURNO: { nombre: 'Relevo nocturno', spec: 'SE-471' },
  PENDIENTE_MANANA: { nombre: 'Pendientes de la mañana', spec: 'SE-512' },
  ESPERAN_ALGO: { nombre: 'Esperan algo de ti', spec: 'SE-504' },
  AVISO_RUN: { nombre: 'Avisos de runs', spec: 'SE-507' },
});

/** Las cinco cosas que dice cada petición. */
export type Campo = 'que' | 'porQue' | 'siNoContestas' | 'siAplazas' | 'caduca';
export const CAMPOS: readonly Campo[] = Object.freeze(['que', 'porQue', 'siNoContestas', 'siAplazas', 'caduca']);

/** La fuente no pudo leerse: se enseña como fallida, nunca como vacía. */
export interface FuenteFallida {
  error: string;
}

/**
 * Lo que entrega cada fuente: su lista de entradas (contrato normalizado, ver `Peticion`) o un
 * fallo. Una fuente ausente está sin conectar.
 */
export type Fuentes = Partial<Record<Fuente, readonly unknown[] | FuenteFallida>>;

export interface Peticion {
  readonly fuente: Fuente;
  readonly id: string;
  /** `null` si la fuente no lo dice o si el contenido supera el nivel del canal. */
  readonly que: string | null;
  readonly porQue: string | null;
  readonly siNoContestas: string | null;
  readonly siAplazas: string | null;
  /** Hasta cuándo vale; `null` si la fuente no lo dice. */
  readonly caduca: Minuto | null;
  /** Desde cuándo espera, si la fuente lo sabe. */
  readonly desde: Minuto | null;
  /** Autorización obligatoria o parada, según un campo estructurado de la fuente. */
  readonly critica: boolean;
  readonly nivel: Nivel;
  /** Campos que la fuente no dio. No incluye los ocultos por nivel. */
  readonly faltan: readonly Campo[];
  readonly caducada: boolean;
  /** El contenido supera el nivel del canal: solo se enseña la referencia. */
  readonly redactada: boolean;
}

export type EstadoFuente = 'CONECTADA' | 'SIN_CONECTAR' | 'FALLIDA';

export interface Cobertura {
  readonly fuente: Fuente;
  readonly estado: EstadoFuente;
  readonly peticiones: number;
  readonly error: string | null;
}

export interface Descartada {
  readonly fuente: string;
  readonly indice: number;
  readonly motivo: 'fuente desconocida' | 'no es un objeto' | 'sin id';
}

export interface Cola {
  readonly ahora: Minuto;
  /** Vigentes primero (críticas, luego por caducidad y antigüedad); caducadas al final. */
  readonly peticiones: readonly Peticion[];
  readonly cobertura: readonly Cobertura[];
  readonly descartadas: readonly Descartada[];
  /** Entradas repetidas (misma fuente y mismo id) que se contaron una sola vez. */
  readonly duplicadas: number;
}

const ES_FUENTE: ReadonlySet<string> = new Set(FUENTES);

function texto(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : null;
}

function minuto(v: unknown): Minuto | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/** Un nivel ausente o fuera de 1..4 es N4 (fail-closed). */
function nivelDe(v: unknown): Nivel {
  return v === 1 || v === 2 || v === 3 || v === 4 ? v : 4;
}

function esFallida(v: unknown): v is FuenteFallida {
  return v !== null && typeof v === 'object' && !Array.isArray(v) && typeof (v as FuenteFallida).error === 'string';
}

function normalizar(fuente: Fuente, e: Record<string, unknown>, id: string, ahora: Minuto, nivelMax: Nivel): Peticion {
  const crudo = {
    que: texto(e.que),
    porQue: texto(e.porQue),
    siNoContestas: texto(e.siNoContestas),
    siAplazas: texto(e.siAplazas),
  };
  const caduca = minuto(e.caduca);
  const faltan = CAMPOS.filter((c) => (c === 'caduca' ? caduca === null : crudo[c] === null));
  const nivel = nivelDe(e.nivel);
  const redactada = nivel > nivelMax;
  const visible = redactada ? { que: null, porQue: null, siNoContestas: null, siAplazas: null } : crudo;
  return Object.freeze({
    fuente,
    id,
    ...visible,
    caduca,
    desde: minuto(e.desde),
    critica: e.critica === true,
    nivel,
    faltan: Object.freeze(faltan),
    caducada: caduca !== null && caduca <= ahora,
    redactada,
  });
}

function comparar(a: Peticion, b: Peticion): number {
  if (a.caducada !== b.caducada) return a.caducada ? 1 : -1;
  if (a.critica !== b.critica) return a.critica ? -1 : 1;
  const ca = a.caduca ?? Infinity;
  const cb = b.caduca ?? Infinity;
  if (ca !== cb) return ca - cb;
  const da = a.desde ?? Infinity;
  const db = b.desde ?? Infinity;
  if (da !== db) return da - db;
  const fa = FUENTES.indexOf(a.fuente);
  const fb = FUENTES.indexOf(b.fuente);
  if (fa !== fb) return fa - fb;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/**
 * Junta las fuentes en una sola cola. Pura y de solo lectura: no toca la entrada y devuelve
 * un objeto congelado. `nivelMax` es el nivel más alto que puede enseñar el canal de la vista.
 */
export function construirCola(fuentes: Fuentes, ahora: Minuto, nivelMax: Nivel): Cola {
  // Canal mal configurado (no es 1..4): no se enseña contenido de ningún nivel, solo referencias.
  const max = nivelMax === 1 || nivelMax === 2 || nivelMax === 3 || nivelMax === 4 ? nivelMax : 0;
  const origen: Fuentes = fuentes !== null && typeof fuentes === 'object' ? fuentes : {};
  const descartadas: Descartada[] = [];
  // Mismo id en la misma fuente: se fusiona de forma conservadora (crítica = OR, nivel = máximo).
  const vistas = new Map<string, { fuente: Fuente; id: string; r: Record<string, unknown> }>();
  let duplicadas = 0;

  const cobertura: Cobertura[] = FUENTES.map((fuente) => {
    if (!Object.hasOwn(origen, fuente) || origen[fuente] === undefined) {
      return { fuente, estado: 'SIN_CONECTAR', peticiones: 0, error: null };
    }
    const lista = origen[fuente];
    if (!Array.isArray(lista)) {
      const error = esFallida(lista) ? lista.error : 'no entregó una lista';
      return { fuente, estado: 'FALLIDA', peticiones: 0, error };
    }
    let n = 0;
    lista.forEach((e: unknown, indice: number) => {
      if (e === null || typeof e !== 'object' || Array.isArray(e)) {
        descartadas.push({ fuente, indice, motivo: 'no es un objeto' });
        return;
      }
      const r = e as Record<string, unknown>;
      const id = texto(r.id);
      if (id === null) {
        descartadas.push({ fuente, indice, motivo: 'sin id' });
        return;
      }
      const clave = `${fuente}\u0000${id}`;
      const previa = vistas.get(clave);
      if (previa) {
        duplicadas++;
        previa.r = {
          ...previa.r,
          critica: previa.r.critica === true || r.critica === true,
          nivel: Math.max(nivelDe(previa.r.nivel), nivelDe(r.nivel)),
        };
        return;
      }
      vistas.set(clave, { fuente, id, r: { ...r } });
      n++;
    });
    return { fuente, estado: 'CONECTADA', peticiones: n, error: null };
  });

  for (const [clave, lista] of Object.entries(origen)) {
    if (ES_FUENTE.has(clave)) continue;
    const n = Array.isArray(lista) ? lista.length : 1;
    for (let i = 0; i < n; i++) descartadas.push({ fuente: clave, indice: i, motivo: 'fuente desconocida' });
  }

  const peticiones = [...vistas.values()].map((v) => normalizar(v.fuente, v.r, v.id, ahora, max as Nivel));
  peticiones.sort(comparar);
  return Object.freeze({
    ahora,
    peticiones: Object.freeze(peticiones),
    cobertura: Object.freeze(cobertura.map((c) => Object.freeze(c))),
    descartadas: Object.freeze(descartadas.map((d) => Object.freeze(d))),
    duplicadas,
  });
}

// ---------------------------------------------------------------------------------------------
// Texto en lenguaje llano, como las tarjetas del prototipo de S0.

const NO_LO_DICE = 'La fuente no lo dice.';

/** Un texto de la fuente no puede abrir líneas ni tarjetas: saltos y caracteres de control a espacio. */
function limpio(s: string): string {
  return s.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, ' ').trim();
}

function hhmm(t: Minuto): string {
  const m = ((t % DIA) + DIA) % DIA;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

function cuando(t: Minuto, ahora: Minuto): string {
  const d = Math.floor(t / DIA) - Math.floor(ahora / DIA);
  if (d === 0) return `hoy ${hhmm(t)}`;
  if (d === 1) return `mañana ${hhmm(t)}`;
  if (d === -1) return `ayer ${hhmm(t)}`;
  const f = new Date(Math.floor(t / DIA) * DIA * 60_000);
  return `${String(f.getUTCDate()).padStart(2, '0')}/${String(f.getUTCMonth() + 1).padStart(2, '0')} ${hhmm(t)}`;
}

function hace(desde: Minuto, ahora: Minuto): string {
  const m = ahora - desde;
  if (m < 1) return 'ahora mismo';
  if (m < 60) return `hace ${m} min`;
  if (m < DIA) return `hace ${Math.floor(m / 60)} h`;
  return `hace ${Math.floor(m / DIA)} días`;
}

function tarjeta(p: Peticion, ahora: Minuto): string[] {
  const origen = FUENTE_INFO[p.fuente].nombre + (p.desde !== null ? ` · ${hace(p.desde, ahora)}` : '');
  if (p.redactada) {
    return [
      `- Contenido de nivel N${p.nivel}: no se enseña en este canal. Ábrelo donde se pueda ver.`,
      `  Vale hasta: ${p.caduca !== null ? cuando(p.caduca, ahora) : NO_LO_DICE}`,
      `  Viene de: ${origen} (ref. ${limpio(p.id)})`,
    ];
  }
  const v = (s: string | null) => (s === null ? NO_LO_DICE : limpio(s));
  const vale = p.caduca === null ? NO_LO_DICE : p.caducada ? `caducó ${cuando(p.caduca, ahora)}` : cuando(p.caduca, ahora);
  return [
    `- ${p.critica ? '[Obligatoria] ' : ''}${v(p.que)}`,
    `  Por qué ahora: ${v(p.porQue)}`,
    `  Si no contestas: ${v(p.siNoContestas)}`,
    `  Si lo aplazas: ${v(p.siAplazas)}`,
    `  Vale hasta: ${vale}`,
    `  Viene de: ${origen}`,
  ];
}

/** La cola en texto llano. Dice qué fuentes faltan o fallaron y cuántas entradas no se leyeron. */
export function textoCola(c: Cola): string {
  const vigentes = c.peticiones.filter((p) => !p.caducada);
  const caducadas = c.peticiones.filter((p) => p.caducada);
  const conectadas = c.cobertura.filter((x) => x.estado === 'CONECTADA');
  const out: string[] = [];
  if (conectadas.length === 0) {
    out.push(c.cobertura.some((x) => x.estado === 'FALLIDA')
      ? 'No se pudo leer ninguna fuente: no puedo decir qué espera tu respuesta.'
      : 'Ninguna fuente conectada: no puedo decir qué espera tu respuesta.');
  } else if (vigentes.length === 0) {
    out.push('Nada pendiente en las fuentes conectadas.');
  } else {
    out.push(`Esperan algo de ti (${vigentes.length})`);
    for (const p of vigentes) out.push(...tarjeta(p, c.ahora));
  }
  if (caducadas.length > 0) {
    out.push('', `Caducadas (${caducadas.length}): ya no valen; la fuente tiene que volver a preguntar.`);
    for (const p of caducadas) out.push(...tarjeta(p, c.ahora));
  }
  const notas: string[] = [];
  for (const x of c.cobertura.filter((y) => y.estado === 'FALLIDA')) {
    notas.push(`No se pudo leer ${FUENTE_INFO[x.fuente].nombre}: ${limpio(x.error ?? '')}`);
  }
  const sin = c.cobertura.filter((x) => x.estado === 'SIN_CONECTAR');
  if (sin.length > 0 && sin.length < c.cobertura.length) {
    notas.push(`Sin datos de: ${sin.map((x) => FUENTE_INFO[x.fuente].nombre).join(', ')}.`);
  }
  if (c.descartadas.length > 0) {
    notas.push(`${c.descartadas.length} ${c.descartadas.length === 1 ? 'entrada no se pudo leer' : 'entradas no se pudieron leer'}.`);
  }
  if (c.duplicadas > 0) notas.push(`${c.duplicadas} repetida(s) contada(s) una vez.`);
  if (notas.length > 0) out.push('', ...notas);
  return out.join('\n') + '\n';
}

// ---------------------------------------------------------------------------------------------
// Adaptadores de las fuentes con código en este repo. Devuelven entradas del contrato
// normalizado o un fallo; `construirCola` valida igual lo que entreguen.

/** Convierte una fecha ISO en minuto local declarado; `null` si no se puede. */
export type AMinuto = (iso: string) => Minuto | null;

const POR_QUE_SOUL: Partial<Record<MotivoK, string>> = {
  PUEDE_ESPERAR: 'Puede esperar: se dejó para la siguiente ventana.',
  PRESUPUESTO_AGOTADO: 'Se agotaron los avisos de esta ventana: se dejó para después.',
  FUERA_DE_VENTANA: 'Llegó fuera de tus horas de aviso.',
  MODO_NO_DISPONIBLE: 'Llegó mientras estabas en un modo que no admite preguntas.',
  SIN_DECLARACION: 'No hay modo declarado: no se te interrumpió.',
  APROBACION_SEGURIDAD: 'Es una aprobación de seguridad: sin ella el trabajo no sigue.',
  EFECTO_AMBIGUO: 'Un reintento puede repetir un efecto que quizá ya ocurrió.',
  PARADO: 'Todo está parado por orden tuya; esto espera a que decidas.',
  VETADO: 'Afecta a algo que vetaste.',
  CONTEXTO_VENCIDO: 'Su contexto venció: hay que decidir qué hacer con ello.',
  PERMISO_ILEGITIMO: 'Pide un permiso fuera de contrato o sin identidad: está bloqueado.',
  SILENCIO_NO_ES_PERMISO: 'Venció su plazo sin respuesta y sigue esperando.',
};

/** Las preguntas de agentes (SE-514 S2) viven en la misma bandeja pero se enseñan por su propio adaptador. */
export const PREFIJO_AGENTE = 'agente:';

const COSTE_SOUL: Record<CosteRetraso, string> = {
  BAJO: 'Retrasarlo cuesta poco.',
  MEDIO: 'Retrasarlo tiene un coste medio.',
  ALTO: 'Retrasarlo cuesta mucho.',
};

/**
 * Soul (SE-490): las decisiones pendientes de la bandeja. Lo informativo (sin `decisionId`) no
 * pide respuesta y no entra. `nivelCanal` es el `canalNivelMax` de la política: el texto que la
 * bandeja guardó no lo supera; el que redactó (texto `null`) cuenta como N4. `Item` no guarda el
 * nivel: `nivelCanal` DEBE ser el mismo con el que la bandeja redactó; uno mayor deja pasar
 * texto guardado para un canal superior (sin defensa en profundidad en S1).
 */
export function deBandejaSoul(items: readonly Item[], nivelCanal: Nivel): unknown[] {
  return items
    .filter((i) => i.pendiente && i.decisionId !== null && !i.decisionId.startsWith(PREFIJO_AGENTE))
    .map((i) => {
      const ultimo = i.historial.at(-1);
      return {
        id: i.decisionId,
        que: i.texto,
        porQue: ultimo ? (POR_QUE_SOUL[ultimo.motivo.k] ?? null) : null,
        siNoContestas: 'Queda pendiente: el silencio no es respuesta y no se decide nada por ti.',
        siAplazas: COSTE_SOUL[i.coste],
        caduca: i.plazo,
        desde: i.historial[0]?.en ?? null,
        critica: i.individual,
        nivel: i.texto === null ? 4 : nivelCanal,
      };
    });
}

const POR_QUE_RELEVO: Record<string, string> = {
  sin_marca_rc: 'Terminó con error y sin dejar marca de fin.',
  fallo: 'El trabajo terminó en fallo esta noche.',
  ok_no_validado: 'Dice que terminó, pero su comprobación no pasa.',
  parcial: 'Quedó a medias.',
  malformada: 'Su marca de fin no se puede leer.',
};

/**
 * Relevo nocturno (SE-471): las decisiones del digest JSON (`--format json`, versión 1). El `id`
 * de la petición es el nombre del run y se enseña tal cual aunque el contenido se redacte: los
 * runs deben tener nombres no sensibles.
 */
export function deRelevoNocturno(digest: unknown, aMinuto: AMinuto, nivel: Nivel): unknown[] | FuenteFallida {
  if (digest === null || typeof digest !== 'object') return { error: 'el relevo no es un objeto' };
  const d = digest as Record<string, unknown>;
  if (d.version !== 1) return { error: `versión ${String(d.version)} desconocida` };
  if (!Array.isArray(d.decisiones)) return { error: 'el relevo no trae decisiones' };
  const hasta = (d.ventana as Record<string, unknown> | undefined)?.hasta;
  const desde = typeof hasta === 'string' ? aMinuto(hasta) : null;
  return d.decisiones.map((x: unknown) => {
    const r = (x !== null && typeof x === 'object' ? x : {}) as Record<string, unknown>;
    const run = texto(r.run);
    const etiqueta = texto(r.etiqueta);
    return {
      id: run,
      que: run ? `Decidir qué hacer con el trabajo nocturno «${run}»${etiqueta ? ` (${etiqueta})` : ''}.` : null,
      porQue: typeof r.categoria === 'string' ? (POR_QUE_RELEVO[r.categoria] ?? null) : null,
      siNoContestas: 'Nada se fusiona ni se repite solo: el trabajo queda como está.',
      siAplazas: null,
      caduca: null,
      desde,
      critica: false,
      nivel,
    };
  });
}

/**
 * PRs esperando revisión (SE-458): salida de `gh pr list --json number,title,createdAt,reviewDecision`.
 * Entran las abiertas sin aprobar; los borradores también, porque los agentes abren en borrador
 * para que los revise la persona. `limite` es el `--limit` con el que se pidió la lista (gh usa 30
 * por defecto): si la lista lo alcanza puede estar truncada y se da por fallida, no por completa.
 */
export function dePrsEnRevision(prs: unknown, aMinuto: AMinuto, nivel: Nivel, limite = 30): unknown[] | FuenteFallida {
  if (!Array.isArray(prs)) return { error: 'la lista de PRs no es una lista' };
  if (prs.length >= limite) return { error: `la lista llegó al límite de ${limite} y puede estar truncada` };
  return prs
    .filter((x: unknown) => !(x !== null && typeof x === 'object' && (x as Record<string, unknown>).reviewDecision === 'APPROVED'))
    .map((x: unknown) => {
      const r = (x !== null && typeof x === 'object' ? x : {}) as Record<string, unknown>;
      const n = Number.isInteger(r.number) ? String(r.number) : null;
      const titulo = texto(r.title);
      return {
        id: n,
        que: n ? `Revisar la PR #${n}${titulo ? `: ${titulo}` : ''}.` : null,
        porQue: r.reviewDecision === 'CHANGES_REQUESTED' ? 'Se pidieron cambios en esta PR: hay que ver si ya están.' : 'Espera tu revisión.',
        siNoContestas: 'La PR sigue abierta: nada se fusiona sin tu revisión.',
        siAplazas: null,
        caduca: null,
        desde: typeof r.createdAt === 'string' ? aMinuto(r.createdAt) : null,
        critica: false,
        nivel,
      };
    });
}
