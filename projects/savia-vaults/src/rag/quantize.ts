/**
 * SE-489 M7 — Cuantización en sombra de vectores normalizados.
 * El float32 sigue siendo la fuente de verdad; estas formas son derivadas y solo preseleccionan.
 *
 * Binario: un bit por dimensión (1 si v > 0; NaN, 0 y -0 dan 0). Bit i en el byte i>>3, posición
 * (7 - i%8), es decir MSB primero: el formato en bytes no depende de la endianness del host.
 * Los bits de relleno del último byte son 0 en todos los vectores, no suman distancia.
 *
 * Int8: escala por dimensión calibrada con un percentil de |x| sobre una muestra determinista.
 * Asimétrico: el documento va en int8 y la consulta en float32 (score = Σ q_j·s_j·c_j).
 */

export const QUANTIZER_VERSION = 'sq-v1';
export const INT8_MAX = 127;
const CALIBRATION_SAMPLE = 20_000;

export function packedBytes(dims: number): number {
  return Math.ceil(dims / 8);
}

/** Signo con bitpacking. */
export function packSigns(v: ArrayLike<number>, out?: Uint8Array): Uint8Array {
  const bytes = packedBytes(v.length);
  const res = out ?? new Uint8Array(bytes);
  if (res.length < bytes) throw new RangeError(`buffer de ${res.length} bytes, hacen falta ${bytes}`);
  res.fill(0, 0, bytes);
  for (let i = 0; i < v.length; i++) {
    if (v[i] > 0) res[i >> 3] |= 0x80 >> (i & 7);
  }
  return res;
}

/** Inversa para tests: bit → ±1 (los bits de relleno no se devuelven). */
export function unpackSigns(packed: Uint8Array, dims: number): Int8Array {
  const out = new Int8Array(dims);
  for (let i = 0; i < dims; i++) out[i] = packed[i >> 3] & (0x80 >> (i & 7)) ? 1 : -1;
  return out;
}

const POP8 = (() => {
  const t = new Uint8Array(256);
  for (let i = 0; i < 256; i++) t[i] = (i & 1) + t[i >> 1];
  return t;
})();

export function popcount32(x: number): number {
  x = x - ((x >>> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >>> 2) & 0x33333333);
  x = (x + (x >>> 4)) & 0x0f0f0f0f;
  return Math.imul(x, 0x01010101) >>> 24;
}

/** Referencia lenta, por bytes: los tests la contrastan con la versión por palabras. */
export function hammingBytes(a: Uint8Array, b: Uint8Array): number {
  let d = 0;
  for (let i = 0; i < a.length; i++) d += POP8[a[i] ^ b[i]];
  return d;
}

export interface Int8Calibration {
  version: typeof QUANTIZER_VERSION;
  dims: number;
  percentile: number;
  /** Escala por dimensión: valor ≈ code · scale[j]. Nunca 0. */
  scale: Float32Array;
}

function sampleRows(rows: number): number[] {
  const n = Math.min(rows, CALIBRATION_SAMPLE);
  const step = rows / n;
  return Array.from({ length: n }, (_, i) => Math.floor(i * step));
}

/** Calibración determinista: percentil de |x| por dimensión sobre un muestreo con paso fijo. */
export function calibrateInt8Rows(rows: number, dims: number, row: (i: number) => ArrayLike<number>, percentile = 0.999): Int8Calibration {
  if (!(percentile > 0 && percentile <= 1)) throw new RangeError('percentil fuera de (0, 1]');
  const sample = sampleRows(rows).map(row);
  const scale = new Float32Array(dims);
  const col = new Float32Array(sample.length);
  for (let j = 0; j < dims; j++) {
    for (let r = 0; r < sample.length; r++) {
      const x = Math.abs(sample[r][j]);
      col[r] = Number.isFinite(x) ? x : 0;
    }
    col.sort();
    const m = col.length ? col[Math.min(col.length - 1, Math.ceil(percentile * col.length) - 1)] : 0;
    scale[j] = m > 0 ? m / INT8_MAX : 1;
  }
  return { version: QUANTIZER_VERSION, dims, percentile, scale };
}

export function calibrateInt8(vectors: Float32Array, dims: number, percentile = 0.999): Int8Calibration {
  if (vectors.length % dims !== 0) throw new RangeError('longitud no múltiplo de dims');
  return calibrateInt8Rows(vectors.length / dims, dims, (i) => vectors.subarray(i * dims, (i + 1) * dims), percentile);
}

export function quantizeInt8(v: ArrayLike<number>, cal: Int8Calibration, out?: Int8Array): Int8Array {
  if (v.length !== cal.dims) throw new RangeError(`vector de ${v.length} dims, calibración ${cal.dims}`);
  const res = out ?? new Int8Array(v.length);
  for (let j = 0; j < v.length; j++) {
    const x = v[j];
    if (!Number.isFinite(x)) { res[j] = 0; continue; }
    const q = Math.round(x / cal.scale[j]);
    res[j] = q > INT8_MAX ? INT8_MAX : q < -INT8_MAX ? -INT8_MAX : q;
  }
  return res;
}

/** Consulta pre-escalada para el producto escalar asimétrico. */
export function scaleQuery(q: Float32Array, cal: Pick<Int8Calibration, "scale">): Float32Array {
  const out = new Float32Array(q.length);
  for (let j = 0; j < q.length; j++) out[j] = Number.isFinite(q[j]) ? q[j] * cal.scale[j] : 0;
  return out;
}
