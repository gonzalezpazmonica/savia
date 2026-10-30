// SE-489 M7 — rescoring float32 e int8, lector de disco
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { BinaryProjection, Int8Projection } from '../../../src/rag/binary-store.js';
import { hammingTopM } from '../../../src/rag/binary-search.js';
import { DiskVectorReader, rescoreFloat32, rescoreInt8, topKInt8 } from '../../../src/rag/rescore.js';
import { makeStore, xorCipher } from './quant-fixture.js';

describe('rescore', () => {
  let home: string;
  beforeEach(() => { home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m7-rescore-')); });
  afterEach(() => { fs.rmSync(home, { recursive: true, force: true }); });

  it('con M = n, binario + float32 reproduce exactamente el top-k exacto (mismo orden)', async () => {
    const { store } = await makeStore(home, { dims: 48, n: 200 });
    const proj = BinaryProjection.build(store, 'N2');
    for (const qi of [0, 17, 133]) {
      const q = store.vector(qi);
      const exact = store.topK(q, 10);
      const cand = hammingTopM(proj, proj.packQuery(q), store.size).map((h) => h.index);
      expect(rescoreFloat32(store, q, cand, 10).map((h) => h.index)).toEqual(exact.map((h) => h.index));
    }
  });

  it('M pequeño puede perder resultados: el recall depende de M (caso límite M = k)', async () => {
    const { store } = await makeStore(home, { dims: 48, n: 400 });
    const proj = BinaryProjection.build(store, 'N2');
    let lossAtK = 0, lossAtAll = 0;
    for (let qi = 0; qi < 40; qi++) {
      const q = store.vector(qi).map((x, j) => x + 0.05 * Math.sin(qi * 7 + j));
      const exact = new Set(store.topK(new Float32Array(q), 10).map((h) => h.index));
      for (const [m, tally] of [[10, 'k'], [400, 'all']] as const) {
        const cand = hammingTopM(proj, proj.packQuery(q), m).map((h) => h.index);
        const got = rescoreFloat32(store, new Float32Array(q), cand, 10).filter((h) => exact.has(h.index)).length;
        if (tally === 'k') lossAtK += 10 - got; else lossAtAll += 10 - got;
      }
    }
    expect(lossAtAll).toBe(0);
    expect(lossAtK).toBeGreaterThan(0);
  });

  it('desempate estable por índice en rescoring con scores iguales', async () => {
    const { store } = await makeStore(home, { dims: 16, n: 5 });
    const q = new Float32Array(16);
    expect(rescoreFloat32(store, q, [4, 2, 3, 0], 3).map((h) => h.index)).toEqual([0, 2, 3]);
  });

  it('int8: el top-10 coincide en ≥ 9/10 de media con el exacto y los scores aproximan al float32', async () => {
    const { store } = await makeStore(home, { dims: 128, n: 300 });
    const i8 = Int8Projection.build(store, 'N2');
    let hit = 0;
    for (let qi = 0; qi < 20; qi++) {
      const q = store.vector(qi);
      const exact = store.topK(q, 10);
      const got = topKInt8(i8, q, 10);
      hit += got.filter((g) => exact.some((e) => e.index === g.index)).length;
      expect(Math.abs(got[0].score - exact[0].score)).toBeLessThan(0.02);
    }
    expect(hit / 200).toBeGreaterThanOrEqual(0.9);
  });

  it('rescoreInt8 con candidatos acotados solo devuelve candidatos; dims erróneas se rechazan', async () => {
    const { store } = await makeStore(home, { dims: 32, n: 20 });
    const i8 = Int8Projection.build(store, 'N2');
    const r = rescoreInt8(i8, store.vector(3), [1, 3, 5], 2);
    expect(r.map((h) => h.index).every((i) => [1, 3, 5].includes(i))).toBe(true);
    expect(r[0].index).toBe(3);
    expect(() => rescoreInt8(i8, new Float32Array(31), [1], 1)).toThrow(/dims/);
    expect(() => rescoreFloat32(store, new Float32Array(31), [1], 1)).toThrow(/dims/);
  });

  it('DiskVectorReader da los mismos scores que la memoria; se niega en índices cifrados', async () => {
    const { store } = await makeStore(home, { dims: 24, n: 30 });
    const rd = new DiskVectorReader(store);
    try {
      const q = store.vector(7);
      const cand = [3, 7, 9, 20];
      expect(rd.rescore(q, cand, 4)).toEqual(rescoreFloat32(store, q, cand, 4));
      expect(() => rd.dot(999, q)).toThrow(/truncada/);
    } finally { rd.close(); }
    const sealed = await makeStore(home, { dims: 24, n: 5, dome: 'S', cipher: xorCipher(3) });
    expect(() => new DiskVectorReader(sealed.store)).toThrow(/cifrados/);
  });
});
