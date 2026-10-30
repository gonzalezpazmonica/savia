import * as path from 'node:path';
import { FlatVectorStore, domeDir, generationId } from '../../../src/rag/store.js';
import { HashEmbedder, normalize } from '../../../src/rag/embedder.js';
import type { Chunk, IndexCipher, Manifest } from '../../../src/rag/types.js';
import { RagError } from '../../../src/rag/types.js';

export const xorCipher = (k: number): IndexCipher => ({
  seal: (data, part) => Buffer.concat([Buffer.from(`${part}|${k}|`), Buffer.from(data.map((b) => b ^ k))]),
  open: (data, part) => {
    const prefix = Buffer.from(`${part}|${k}|`);
    if (!data.subarray(0, prefix.length).equals(prefix)) throw new RagError('CORRUPT_INDEX', 'autenticación fallida');
    return Buffer.from(data.subarray(prefix.length).map((b) => b ^ k));
  },
});

/** PRNG determinista (LCG) para vectores de prueba reproducibles. */
export function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 0x100000000; };
}

export interface FixtureOpts { dims?: number; n?: number; seq?: number; model?: string; digest?: string; cipher?: IndexCipher; dome?: string; confidentiality?: string }

/** Almacén sintético con vectores gaussianos normalizados (solo para tests). */
export async function makeStore(home: string, o: FixtureOpts = {}) {
  const dims = o.dims ?? 32;
  const n = o.n ?? 20;
  const seq = o.seq ?? 1;
  const dome = o.dome ?? 'D';
  const base = await new HashEmbedder(dims).contract();
  const contract = { ...base, model: o.model ?? base.model, modelDigest: o.digest ?? base.modelDigest };
  const gen = generationId(contract);
  const r = rng(42 + seq);
  const chunks: Chunk[] = [];
  const vectors: Float32Array[] = [];
  for (let i = 0; i < n; i++) {
    chunks.push({
      id: `d${i}.md#0`, path: `d${i}.md`, ordinal: 0, heading: 'T', text: `t${i}`, embedText: `T\n\nt${i}`, hash: `h${i}`,
      meta: { title: 'T', modified: '2026-09-01', ...(o.confidentiality ? { confidentiality: o.confidentiality } : {}) },
    });
    vectors.push(normalize(Float32Array.from({ length: dims }, () => r() - 0.5)));
  }
  const manifest: Manifest = {
    version: 1, dome, generation: gen, contract, seq, createdAt: 'x', updatedAt: 'x', docs: {}, chunkCount: n, fingerprint: 'f',
  };
  const dir = path.join(domeDir(home, dome), gen);
  FlatVectorStore.write(dir, manifest, chunks, vectors, o.cipher);
  const store = FlatVectorStore.load(dir, undefined, o.cipher);
  return { store, dir, gen, manifest, chunks, vectors, contract };
}
