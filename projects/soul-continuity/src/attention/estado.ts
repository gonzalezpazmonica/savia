// Estado persistente de la política. Sobrevive a un reinicio mediante texto de líneas
// `clave=valor`. Nunca guarda contenido de eventos: solo identificadores y contadores.
// Un texto ilegible devuelve `null` y quien lo use debe tratarlo como fallo y no arrancar
// con un estado vacío (que perdería el PARA).

import { MODOS, type Modo, type ModoDeclarado } from './modelo.ts';
import type { Minuto } from './tiempo.ts';

export interface Estado {
  parado: boolean;
  vetos: Set<string>;
  modoDeclarado: ModoDeclarado | null;
  /** Contactos consumidos por instancia de ventana (inicio → n). */
  usados: Map<Minuto, number>;
  /** Alertas emitidas por cubo de ventana (ver `cuboAlertas`) → n. Tope propio. */
  alertasUsadas: Map<Minuto, number>;
  /** Alertas por encima del tope pendientes de su mensaje agrupado (ids de evento). */
  excedidas: string[];
  /** Eventos ya tratados (pregunta, aviso o alerta): el mismo id no se repite. */
  preguntadas: Set<string>;
  /** Último resumen emitido, por su hora programada. */
  resumenes: { inicio: Minuto | null; cierre: Minuto | null };
}

export function estadoVacio(): Estado {
  return {
    parado: false,
    vetos: new Set(),
    modoDeclarado: null,
    usados: new Map(),
    alertasUsadas: new Map(),
    excedidas: [],
    preguntadas: new Set(),
    resumenes: { inicio: null, cierre: null },
  };
}

const CABECERA = 'soul-atencion-estado v2';

const cod = (s: string): string => s.replaceAll('%', '%25').replaceAll('\n', '%0A').replaceAll('\r', '%0D');
const decod = (s: string): string => s.replaceAll('%0A', '\n').replaceAll('%0D', '\r').replaceAll('%25', '%');

function entero(s: string): number | null {
  return /^-?\d+$/.test(s) && Number.isSafeInteger(Number(s)) ? Number(s) : null;
}

function esModo(s: string): s is Modo {
  return (MODOS as readonly string[]).includes(s);
}

export function estadoATexto(e: Estado): string {
  let out = `${CABECERA}\nparado=${e.parado ? 1 : 0}\n`;
  for (const v of [...e.vetos].sort()) out += `veto=${cod(v)}\n`;
  if (e.modoDeclarado) out += `modo=${e.modoDeclarado.modo},${e.modoDeclarado.hasta ?? '-'}\n`;
  for (const [i, n] of [...e.usados].sort((a, b) => a[0] - b[0])) out += `usado=${i},${n}\n`;
  for (const [i, n] of [...e.alertasUsadas].sort((a, b) => a[0] - b[0])) out += `alerta_usada=${i},${n}\n`;
  for (const id of e.excedidas) out += `excedida=${cod(id)}\n`;
  for (const p of [...e.preguntadas].sort()) out += `preguntada=${cod(p)}\n`;
  if (e.resumenes.inicio !== null) out += `resumen_inicio=${e.resumenes.inicio}\n`;
  if (e.resumenes.cierre !== null) out += `resumen_cierre=${e.resumenes.cierre}\n`;
  return out;
}

function par(v: string): [number, number] | null {
  const [a, b, ...resto] = v.split(',');
  if (a === undefined || b === undefined || resto.length > 0) return null;
  const x = entero(a);
  const y = entero(b);
  return x === null || y === null || y < 0 ? null : [x, y];
}

const SINGULARES: ReadonlySet<string> = new Set(['parado', 'modo', 'resumen_inicio', 'resumen_cierre']);

/** Cualquier línea desconocida, mal formada o repetida devuelve `null`. */
export function estadoDesdeTexto(s: string): Estado | null {
  const lineas = s.split('\n');
  if (lineas.at(-1) === '') lineas.pop();
  if (lineas[0] !== CABECERA) return null;
  const e = estadoVacio();
  let vistoParado = false;
  // El serializador nunca repite una línea: un duplicado es un fichero corrupto o manipulado
  // (p. ej. `parado=1` seguido de `parado=0` levantaría el PARA) y se rechaza entero.
  const vistas = new Set<string>();
  for (const l of lineas.slice(1)) {
    const ix = l.indexOf('=');
    if (ix < 0) return null;
    const k = l.slice(0, ix);
    const v = l.slice(ix + 1);
    // Una ventana por contador, una vez cada clave singular, un valor (decodificado) por lista.
    const unica = k === 'usado' || k === 'alerta_usada'
      ? `${k}=${entero(v.split(',')[0] ?? '')}`
      : SINGULARES.has(k) ? k : `${k}=${decod(v)}`;
    if (vistas.has(unica)) return null;
    vistas.add(unica);
    switch (k) {
      case 'parado':
        if (v !== '0' && v !== '1') return null;
        e.parado = v === '1';
        vistoParado = true;
        break;
      case 'veto':
        if (v === '') return null;
        e.vetos.add(decod(v));
        break;
      case 'modo': {
        const [m, h, ...resto] = v.split(',');
        if (m === undefined || h === undefined || resto.length > 0 || !esModo(m)) return null;
        const hasta = h === '-' ? null : entero(h);
        if (h !== '-' && hasta === null) return null;
        e.modoDeclarado = { modo: m, hasta };
        break;
      }
      case 'usado': {
        const p = par(v);
        if (!p) return null;
        e.usados.set(p[0], p[1]);
        break;
      }
      case 'alerta_usada': {
        const p = par(v);
        if (!p) return null;
        e.alertasUsadas.set(p[0], p[1]);
        break;
      }
      case 'excedida':
        if (v === '') return null;
        e.excedidas.push(decod(v));
        break;
      case 'preguntada':
        if (v === '') return null;
        e.preguntadas.add(decod(v));
        break;
      case 'resumen_inicio':
      case 'resumen_cierre': {
        const n = entero(v);
        if (n === null) return null;
        e.resumenes[k === 'resumen_inicio' ? 'inicio' : 'cierre'] = n;
        break;
      }
      default:
        return null;
    }
  }
  return vistoParado ? e : null;
}
