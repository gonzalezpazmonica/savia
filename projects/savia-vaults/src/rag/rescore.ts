import * as fs from 'node:fs';
import * as path from 'node:path';
import { scaleQuery } from './quantize.js';
import type { Int8Calibration } from './quantize.js';
import type { ProjectionSource } from './binary-store.js';
import type { TopKHit } from './store.js';
import { RagError } from './types.js';

/**
 * SE-489 M7 — Rescoring de candidatos. El float32 es la fuente de verdad: la preselección binaria
 * o int8 solo decide qué filas se releen. Desempate estable: mayor score, y a igual score menor índice.
 */

/** Filas float32 en memoria (lo implementa FlatVectorStore). */
export interface VectorRows { readonly dims: number; vector(index: number): Float32Array }

/** Filas int8 con su calibración (lo implementa Int8Projection). */
export interface Int8Rows { readonly dims: number; readonly size: number; readonly calibration: Pick<Int8Calibration, 'scale' | 'dims'>; readonly codes: Int8Array }

const byScore = (a: TopKHit, b: TopKHit) => b.score - a.score || a.index - b.index;

/** Rescoring exacto en float32 con los vectores ya cargados del almacén. */
export function rescoreFloat32(store: VectorRows, query: Float32Array, candidates: number[], k: number): TopKHit[] {
  if (query.length !== store.dims) throw new RagError('CONTRACT_MISMATCH', `consulta de ${query.length} dims, índice ${store.dims}`);
  const out: TopKHit[] = candidates.map((index) => {
    const v = store.vector(index);
    let s = 0;
    for (let j = 0; j < v.length; j++) s += v[j] * query[j];
    return { index, score: s };
  });
  return out.sort(byScore).slice(0, k);
}

/** Rescoring en int8 asimétrico (documento int8, consulta float32). */
export function rescoreInt8(proj: Int8Rows, query: Float32Array, candidates: number[], k: number): TopKHit[] {
  if (query.length !== proj.dims) throw new RagError('CONTRACT_MISMATCH', `consulta de ${query.length} dims, proyección ${proj.dims}`);
  const q = scaleQuery(query, proj.calibration);
  const d = proj.dims;
  const out: TopKHit[] = candidates.map((index) => {
    let s = 0;
    const off = index * d;
    for (let j = 0; j < d; j++) s += proj.codes[off + j] * q[j];
    return { index, score: s };
  });
  return out.sort(byScore).slice(0, k);
}

/** Top-k completo en int8 (sin preselección): comparación directa con el exacto. */
export function topKInt8(proj: Int8Rows, query: Float32Array, k: number, accept?: (index: number) => boolean): TopKHit[] {
  const all: number[] = [];
  for (let i = 0; i < proj.size; i++) if (!accept || accept(i)) all.push(i);
  return rescoreInt8(proj, query, all, k);
}

/**
 * Lector de filas float32 desde disco (pread), para rescorar sin tener los vectores en RAM.
 * Solo vale para índices en claro: uno sellado exige descifrar el fichero entero, que anula el ahorro.
 */
export class DiskVectorReader {
  private readonly fd: number;
  private readonly rowBytes: number;
  private readonly buf: Buffer;
  readonly dims: number;

  constructor(store: ProjectionSource) {
    if (store.manifest.sealed) throw new RagError('PROJECTION_MISMATCH', 'lectura de filas desde disco no disponible en índices cifrados');
    this.dims = store.dims;
    this.rowBytes = this.dims * 4;
    this.buf = Buffer.alloc(this.rowBytes);
    this.fd = fs.openSync(path.join(store.dir, `vectors-${store.manifest.seq}.f32`), 'r');
  }

  /** Producto escalar de la fila `index` con la consulta. */
  dot(index: number, query: Float32Array): number {
    const n = fs.readSync(this.fd, this.buf, 0, this.rowBytes, index * this.rowBytes);
    if (n !== this.rowBytes) throw new RagError('CORRUPT_INDEX', `fila ${index} truncada`);
    let s = 0;
    for (let j = 0; j < this.dims; j++) s += this.buf.readFloatLE(j * 4) * query[j];
    return s;
  }

  rescore(query: Float32Array, candidates: number[], k: number): TopKHit[] {
    return candidates.map((index) => ({ index, score: this.dot(index, query) })).sort(byScore).slice(0, k);
  }

  close(): void { fs.closeSync(this.fd); }
}
