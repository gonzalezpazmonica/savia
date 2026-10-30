// SE-489 M7 — cuantización: signo con bitpacking e int8 calibrado
import { describe, it, expect } from 'vitest';
import {
  calibrateInt8, hammingBytes, packSigns, packedBytes, popcount32, quantizeInt8, scaleQuery, unpackSigns, INT8_MAX,
} from '../../../src/rag/quantize.js';

describe('packSigns', () => {
  it('golden: MSB primero, bytes fijos independientes de la endianness del host', () => {
    // + - + + | - - - +   → 1011 0001 = 0xB1 ; + (resto) → 1000 0000 = 0x80
    const v = [1, -1, 1, 1, -1, -1, -1, 1, 0.5];
    expect(Array.from(packSigns(v))).toEqual([0xb1, 0x80]);
  });

  it('dimensión no múltiplo de 8: relleno a 0 y tamaño ceil(d/8)', () => {
    for (const d of [1, 7, 8, 9, 15, 17, 1023]) {
      const p = packSigns(new Float32Array(d).fill(1));
      expect(p.length).toBe(packedBytes(d));
      const ones = Array.from(p).reduce((s, b) => s + popcount32(b), 0);
      expect(ones).toBe(d);
    }
  });

  it('NaN, 0 y -0 dan bit 0; infinitos respetan su signo', () => {
    const p = packSigns([NaN, 0, -0, Infinity, -Infinity, 1e-30, -1e-30, 2]);
    expect(Array.from(unpackSigns(p, 8))).toEqual([-1, -1, -1, 1, -1, 1, -1, 1]);
  });

  it('es determinista y no depende del contenido previo del buffer de salida', () => {
    const v = Float32Array.from({ length: 100 }, (_, i) => Math.sin(i * 1.3));
    const a = packSigns(v);
    const dirty = new Uint8Array(13).fill(0xff);
    const b = packSigns(v, dirty);
    expect(Array.from(b)).toEqual(Array.from(a));
  });

  it('rechaza un buffer de salida corto', () => {
    expect(() => packSigns(new Float32Array(16), new Uint8Array(1))).toThrow(RangeError);
  });

  it('el popcount por palabras coincide con la referencia por bytes (endianness)', () => {
    const a = new Uint8Array([1, 2, 3, 4, 250, 251, 252, 253]);
    const b = new Uint8Array([9, 8, 7, 6, 5, 4, 3, 2]);
    const wa = new Uint32Array(a.buffer);
    const wb = new Uint32Array(b.buffer);
    let words = 0;
    for (let i = 0; i < wa.length; i++) words += popcount32((wa[i] ^ wb[i]) >>> 0);
    expect(words).toBe(hammingBytes(a, b));
    // y con el orden de bytes invertido (lectura big-endian): mismo resultado
    const dva = new DataView(a.buffer), dvb = new DataView(b.buffer);
    let be = 0;
    for (let i = 0; i < 2; i++) be += popcount32((dva.getUint32(i * 4, false) ^ dvb.getUint32(i * 4, false)) >>> 0);
    expect(be).toBe(words);
  });
});

describe('int8 escalar calibrado', () => {
  const dims = 16;
  const make = (rows: number) => {
    const v = new Float32Array(rows * dims);
    let s = 7;
    for (let i = 0; i < v.length; i++) { s = (s * 1103515245 + 12345) & 0x7fffffff; v[i] = (s / 0x7fffffff - 0.5) * (1 + (i % dims)); }
    return v;
  };

  it('la calibración es determinista y la escala crece con la amplitud de cada dimensión', () => {
    const v = make(500);
    const a = calibrateInt8(v, dims);
    const b = calibrateInt8(v, dims);
    expect(Array.from(a.scale)).toEqual(Array.from(b.scale));
    expect(a.scale[dims - 1]).toBeGreaterThan(a.scale[0] * 5);
  });

  it('cuantiza dentro de [-127, 127] y satura valores fuera del percentil', () => {
    const cal = calibrateInt8(make(500), dims, 0.99);
    const out = quantizeInt8(new Float32Array(dims).fill(1e9), cal);
    expect(Array.from(out).every((x) => x === INT8_MAX)).toBe(true);
    expect(Array.from(quantizeInt8(new Float32Array(dims).fill(-1e9), cal)).every((x) => x === -INT8_MAX)).toBe(true);
  });

  it('error de reconstrucción acotado por media escala; NaN e infinitos dan 0', () => {
    const v = make(300);
    const cal = calibrateInt8(v, dims, 1);
    const row = v.subarray(0, dims);
    const q = quantizeInt8(row, cal);
    for (let j = 0; j < dims; j++) expect(Math.abs(q[j] * cal.scale[j] - row[j])).toBeLessThanOrEqual(cal.scale[j] / 2 + 1e-6);
    const z = quantizeInt8([NaN, Infinity, -Infinity, ...new Array(dims - 3).fill(0)], cal);
    expect(Array.from(z)).toEqual(new Array(dims).fill(0));
  });

  it('dimensión distinta de la calibración se rechaza; escala nunca 0 con columna nula', () => {
    const cal = calibrateInt8(new Float32Array(4 * dims), dims);
    expect(Array.from(cal.scale).every((s) => s > 0)).toBe(true);
    expect(() => quantizeInt8(new Float32Array(dims + 1), cal)).toThrow(RangeError);
    expect(() => calibrateInt8(new Float32Array(dims + 1), dims)).toThrow(RangeError);
    expect(() => calibrateInt8(new Float32Array(dims), dims, 0)).toThrow(RangeError);
  });

  it('scaleQuery anula las componentes no finitas', () => {
    const cal = calibrateInt8(make(50), dims);
    const q = new Float32Array(dims).fill(1);
    q[3] = NaN;
    const s = scaleQuery(q, cal);
    expect(s[3]).toBe(0);
    expect(s[0]).toBeCloseTo(cal.scale[0], 6);
  });
});
