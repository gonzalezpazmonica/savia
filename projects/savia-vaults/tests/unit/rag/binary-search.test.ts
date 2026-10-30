// SE-489 M7 — Hamming xor+popcount, top-M con desempate estable
import { describe, it, expect } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { hammingDistances, hammingTopM, topMFromDistances } from '../../../src/rag/binary-search.js';
import { BinaryProjection } from '../../../src/rag/binary-store.js';
import { hammingBytes, packSigns } from '../../../src/rag/quantize.js';
import { makeStore } from './quant-fixture.js';

describe('topMFromDistances', () => {
  it('desempata por índice ascendente y devuelve exactamente M', () => {
    const d = Uint16Array.from([3, 1, 1, 2, 1, 2, 0]);
    expect(topMFromDistances(d, 4)).toEqual([
      { index: 6, distance: 0 }, { index: 1, distance: 1 }, { index: 2, distance: 1 }, { index: 4, distance: 1 },
    ]);
    // el corte cae dentro de un empate: 2 de los 3 de distancia 1
    expect(topMFromDistances(d, 2).map((h) => h.index)).toEqual([6, 1]);
  });

  it('M mayor que n devuelve todo; M ≤ 0 devuelve vacío; las filas excluidas no salen', () => {
    const d = Uint16Array.from([5, 0xffff, 2]);
    expect(topMFromDistances(d, 10).map((h) => h.index)).toEqual([2, 0]);
    expect(topMFromDistances(d, 0)).toEqual([]);
    expect(topMFromDistances(new Uint16Array(0), 3)).toEqual([]);
  });

  it('es estable entre ejecuciones con empates masivos', () => {
    const d = new Uint16Array(1000).fill(7);
    const a = topMFromDistances(d, 50).map((h) => h.index);
    expect(a).toEqual(Array.from({ length: 50 }, (_, i) => i));
  });
});

describe('hammingTopM', () => {
  const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m7-search-'));

  it('las distancias coinciden con la referencia por bytes para dims no múltiplo de 8', async () => {
    const home = tmp();
    try {
      const { store } = await makeStore(home, { dims: 37, n: 40 });
      const proj = BinaryProjection.build(store, 'N2');
      const qv = store.vector(5).map((x) => -x);
      const q = proj.packQuery(qv);
      const dist = hammingDistances(proj, q);
      const qb = packSigns(qv);
      for (let i = 0; i < store.size; i++) expect(dist[i]).toBe(hammingBytes(packSigns(store.vector(i)), qb));
    } finally { fs.rmSync(home, { recursive: true, force: true }); }
  });

  it('una fila idéntica a la consulta va primera con distancia 0; accept la excluye', async () => {
    const home = tmp();
    try {
      const { store } = await makeStore(home, { dims: 64, n: 30 });
      const proj = BinaryProjection.build(store, 'N2');
      const q = proj.packQuery(store.vector(11));
      expect(hammingTopM(proj, q, 3)[0]).toEqual({ index: 11, distance: 0 });
      expect(hammingTopM(proj, q, 3, (i) => i !== 11).every((h) => h.index !== 11)).toBe(true);
    } finally { fs.rmSync(home, { recursive: true, force: true }); }
  });

  it('consulta con el tamaño equivocado se rechaza', async () => {
    const home = tmp();
    try {
      const { store } = await makeStore(home, { dims: 64, n: 5 });
      const proj = BinaryProjection.build(store, 'N2');
      expect(() => proj.packQuery(new Float32Array(63))).toThrow(/dims/);
      expect(() => hammingDistances(proj, new Uint32Array(1))).toThrow(RangeError);
    } finally { fs.rmSync(home, { recursive: true, force: true }); }
  });
});
