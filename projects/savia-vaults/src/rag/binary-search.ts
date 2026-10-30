import { assertDimsSupported } from './binary-store.js';
import { popcount32 } from './quantize.js';


/**
 * SE-489 M7 — Búsqueda Hamming sobre la proyección binaria: xor + popcount por palabra de 32 bits
 * (el resultado no depende de la endianness: el popcount de un xor no depende del orden de bytes).
 * Top-M con desempate estable: menor distancia primero, y a igual distancia, menor índice.
 */

/** Filas binarias alineadas a 32 bits (lo implementa BinaryProjection; los bancos sintéticos usan filas crudas). */
export interface BinaryRows { readonly words: Uint32Array; readonly rowWords: number; readonly size: number }

export interface HammingHit { index: number; distance: number }

/** Distancias de la consulta a todas las filas. `accept` excluye filas (se marcan con 0xFFFF). */
export function hammingDistances(proj: BinaryRows, query: Uint32Array, accept?: (index: number) => boolean): Uint16Array {
  const rw = proj.rowWords;
  assertDimsSupported(rw * 32);
  if (query.length !== rw) throw new RangeError(`consulta de ${query.length} palabras, filas de ${rw}`);
  const n = proj.size;
  const words = proj.words;
  const dist = new Uint16Array(n);
  for (let i = 0; i < n; i++) {
    if (accept && !accept(i)) { dist[i] = 0xffff; continue; }
    let d = 0;
    const off = i * rw;
    for (let w = 0; w < rw; w++) d += popcount32((words[off + w] ^ query[w]) >>> 0);
    dist[i] = d;
  }
  return dist;
}

/** Selección O(n) por histograma de distancias; salida ordenada por (distancia, índice). */
export function topMFromDistances(dist: Uint16Array, m: number): HammingHit[] {
  if (m <= 0) return [];
  const hist = new Uint32Array(0x10000);
  for (let i = 0; i < dist.length; i++) if (dist[i] !== 0xffff) hist[dist[i]]++;
  let cum = 0;
  let cut = -1;
  for (let d = 0; d < 0xffff; d++) {
    cum += hist[d];
    if (cum >= m) { cut = d; break; }
  }
  if (cut < 0) cut = 0xfffe;
  const out: HammingHit[] = [];
  for (let i = 0; i < dist.length; i++) if (dist[i] < cut) out.push({ index: i, distance: dist[i] });
  let room = m - out.length;
  for (let i = 0; i < dist.length && room > 0; i++) {
    if (dist[i] === cut) { out.push({ index: i, distance: cut }); room--; }
  }
  return out.sort((a, b) => a.distance - b.distance || a.index - b.index).slice(0, m);
}

export function hammingTopM(proj: BinaryRows, query: Uint32Array, m: number, accept?: (index: number) => boolean): HammingHit[] {
  return topMFromDistances(hammingDistances(proj, query, accept), m);
}
