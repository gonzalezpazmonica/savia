// SE-489 M7 — punto de entrada de la ruta cuantizada
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { BinaryProjection, Int8Projection } from '../../../src/rag/binary-store.js';
import { QuantizedIndex, type QuantizedStrategy } from '../../../src/rag/quantized-search.js';
import { makeStore } from './quant-fixture.js';

describe('QuantizedIndex', () => {
  let home: string;
  beforeEach(() => { home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m7-qi-')); });
  afterEach(() => { fs.rmSync(home, { recursive: true, force: true }); });

  it('con M = n, binary-rescore e int8-rescore (disco y memoria) devuelven el top-k exacto', async () => {
    const { store, dir } = await makeStore(home, { dims: 64, n: 150 });
    BinaryProjection.build(store, 'N2');
    Int8Projection.build(store, 'N2');
    const q = store.vector(9);
    const exact = store.topK(q, 10).map((h) => h.index);
    for (const rows of [undefined, store]) {
      const qi = QuantizedIndex.open(dir, 'N2', undefined, rows);
      try {
        for (const strategy of ['binary-rescore', 'int8-rescore'] as QuantizedStrategy[]) {
          expect(qi.search(q, { strategy, k: 10, m: 150, accept: () => true }).map((h) => h.index)).toEqual(exact);
        }
      } finally { qi.close(); }
    }
  });

  it('accept excluye filas en todas las estrategias (autorización previa a abrir el nodo)', async () => {
    const { store, dir } = await makeStore(home, { dims: 64, n: 60 });
    BinaryProjection.build(store, 'N2');
    Int8Projection.build(store, 'N2');
    const q = store.vector(4);
    const qi = QuantizedIndex.open(dir, 'N2', undefined, store);
    for (const strategy of ['binary-pure', 'binary-rescore', 'int8-pure', 'int8-rescore'] as QuantizedStrategy[]) {
      const hits = qi.search(q, { strategy, k: 10, m: 30, accept: (i) => i % 2 === 1 });
      expect(hits.length).toBeGreaterThan(0);
      expect(hits.every((h) => h.index % 2 === 1), strategy).toBe(true);
    }
  });

  it('rows de otro tamaño o de otra generación se rechazan al abrir', async () => {
    const { store, dir } = await makeStore(home, { dims: 32, n: 10 });
    const other = await makeStore(home, { dims: 32, n: 12, dome: 'E', digest: 'otro' });
    BinaryProjection.build(store, 'N2');
    expect(() => QuantizedIndex.open(dir, 'N2', undefined, other.store)).toThrow(/CONTRACT_MISMATCH/);
    expect(() => QuantizedIndex.open(dir, 'N2', undefined, store)).not.toThrow();
  });

  it('proyección ausente o de otra clasificación → rechaza, no sirve resultados', async () => {
    const { store, dir } = await makeStore(home, { n: 10 });
    expect(() => QuantizedIndex.open(dir, 'N2').search(store.vector(0), { strategy: 'binary-pure', k: 3, accept: () => true })).toThrow(/PROJECTION_MISMATCH/);
    BinaryProjection.build(store, 'N2');
    expect(() => QuantizedIndex.open(dir, 'N4').search(store.vector(0), { strategy: 'binary-pure', k: 3, accept: () => true })).toThrow(/classification/);
  });
});
