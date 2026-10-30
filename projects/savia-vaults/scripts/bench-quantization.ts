/**
 * SE-489 M7 — Medición de la cuantización en sombra.
 *   tsx scripts/bench-quantization.ts real  --src <rag/savia-docs> --bench <banco.json> --out <res.json> [--work <dir>]
 *   tsx scripts/bench-quantization.ts synth --sizes 10000,100000,1000000 --out <res.json> [--work <dir>]
 * `real` COPIA el índice origen a un directorio temporal y trabaja ahí: nunca escribe en el origen.
 * Cada variante corre en un proceso hijo nuevo para que RSS y pico de RSS sean suyos.
 * Salida: JSON (los datos del informe). Los datos de `synth` son sintéticos y así se marcan.
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { hammingTopM } from '../src/rag/binary-search.js';
import { BinaryProjection, Int8Projection, openProjectionSource, rowWordsFor, type ProjectionSource } from '../src/rag/binary-store.js';
import { OllamaEmbedder } from '../src/rag/embedder.js';
import { calibrateInt8Rows, packSigns, quantizeInt8 } from '../src/rag/quantize.js';
import { DiskVectorReader, rescoreFloat32, topKInt8, rescoreInt8, type Int8Rows, type VectorRows } from '../src/rag/rescore.js';
import { FlatVectorStore, readActive } from '../src/rag/store.js';

const SELF = fileURLToPath(import.meta.url);
const TSX = path.join(path.dirname(SELF), '..', 'node_modules', '.bin', 'tsx');
const MB = 1024 * 1024;
const MS = [50, 100, 200, 400];

const arg = (name: string, def?: string): string | undefined => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : def;
};
const pct = (xs: number[], p: number): number => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)] : 0;
};

interface QueryFile {
  queries: { text?: string; relevant?: string[]; vec: number[]; truth: number[] }[];
  dims: number;
}

export function variantsFor(): string[] {
  const v = ['f32', 'bin-pure'];
  for (const m of MS) v.push(`bin-m${m}-mem`, `bin-m${m}-disk`);
  v.push('i8-pure', 'i8-m100-disk', 'i8-m400-disk');
  return v;
}

// ── hijo: una variante ──────────────────────────────────────────────────

interface Ctx {
  n: number;
  dims: number;
  docOf?: (i: number) => string;
  rows: () => VectorRows;           // float32 residente
  disk: () => DiskVectorReader;
  bin: () => { words: Uint32Array; rowWords: number; size: number; packQuery(q: Float32Array): Uint32Array };
  i8: () => Int8Rows;
  exact: (q: Float32Array, k: number) => number[];
  bytes: { f32: number; bin: number; i8: number };
}

function readInto(file: string, target: Uint8Array): void {
  const fd = fs.openSync(file, 'r');
  try {
    let off = 0;
    while (off < target.length) {
      const n = fs.readSync(fd, target, off, Math.min(target.length - off, 256 * MB), off);
      if (n <= 0) throw new Error(`lectura truncada de ${file}`);
      off += n;
    }
  } finally { fs.closeSync(fd); }
}

function exactFlat(v: Float32Array, n: number, d: number, q: Float32Array, k: number): number[] {
  const best: { i: number; s: number }[] = [];
  for (let i = 0; i < n; i++) {
    let s = 0;
    const off = i * d;
    for (let j = 0; j < d; j++) s += v[off + j] * q[j];
    if (best.length < k) { best.push({ i, s }); if (best.length === k) best.sort((a, b) => b.s - a.s); }
    else if (s > best[k - 1].s) { best[k - 1] = { i, s }; best.sort((a, b) => b.s - a.s); }
  }
  return best.sort((a, b) => b.s - a.s).map((b) => b.i);
}

function realCtx(dir: string): Ctx {
  let src: ProjectionSource | undefined;
  let store: FlatVectorStore | undefined;
  const source = () => (src ??= openProjectionSource(dir));
  const full = () => (store ??= FlatVectorStore.load(dir));
  const seq = source().manifest.seq;
  const sz = (f: string) => fs.statSync(path.join(dir, f)).size;
  return {
    n: source().size, dims: source().dims, docOf: (i) => source().chunks[i].path,
    rows: () => full(),
    disk: () => new DiskVectorReader(source()),
    bin: () => BinaryProjection.load(source(), 'N2'),
    i8: () => Int8Projection.load(source(), 'N2'),
    exact: (q, k) => full().topK(q, k).map((h) => h.index),
    bytes: { f32: sz(`vectors-${seq}.f32`), bin: sz(`proj-${seq}-binary.bin`), i8: sz(`proj-${seq}-int8.bin`) },
  };
}

function synthCtx(dir: string): Ctx {
  const meta = JSON.parse(fs.readFileSync(path.join(dir, 'meta.json'), 'utf-8')) as { n: number; dims: number };
  const { n, dims } = meta;
  const rw = rowWordsFor(dims);
  let f32: Float32Array | undefined;
  const flat = () => {
    if (!f32) { f32 = new Float32Array(n * dims); readInto(path.join(dir, 'vectors-0.f32'), new Uint8Array(f32.buffer)); }
    return f32;
  };
  const fake = { manifest: { sealed: false, seq: 0 }, dims, dir, size: n } as unknown as ProjectionSource;
  return {
    n, dims,
    rows: () => ({ dims, vector: (i: number) => flat().subarray(i * dims, (i + 1) * dims) }),
    disk: () => new DiskVectorReader(fake),
    bin: () => {
      const words = new Uint32Array(n * rw);
      readInto(path.join(dir, 'bin.u32'), new Uint8Array(words.buffer));
      return { words, rowWords: rw, size: n, packQuery: (q: Float32Array) => { const b = new Uint8Array(rw * 4); packSigns(q, b); return new Uint32Array(b.buffer); } };
    },
    i8: () => {
      const codes = new Int8Array(n * dims);
      readInto(path.join(dir, 'int8.codes'), new Uint8Array(codes.buffer));
      const scale = new Float32Array(dims);
      readInto(path.join(dir, 'int8.scale'), new Uint8Array(scale.buffer));
      return { dims, size: n, calibration: { dims, scale }, codes };
    },
    exact: (q, k) => exactFlat(flat(), n, dims, q, k),
    bytes: { f32: n * dims * 4, bin: n * rw * 4, i8: n * dims + dims * 4 },
  };
}

function runVariant(kind: string, dir: string, variant: string, qfile: string): void {
  const REPS = Number(arg('reps', '5'));
  const qf = JSON.parse(fs.readFileSync(qfile, 'utf-8')) as QueryFile;
  const rssBase = process.memoryUsage().rss;
  const ctx = kind === 'real' ? realCtx(dir) : synthCtx(dir);
  const K = 20;
  let search: (q: Float32Array) => number[];
  let onDisk: number;
  const mm = variant.match(/-m(\d+)-(mem|disk)$/);
  const M = mm ? Number(mm[1]) : 0;
  if (variant === 'f32') {
    ctx.rows();
    search = (q) => ctx.exact(q, K);
    onDisk = ctx.bytes.f32;
  } else if (variant === 'bin-pure') {
    const b = ctx.bin();
    search = (q) => hammingTopM(b, b.packQuery(q), K).map((h) => h.index);
    onDisk = ctx.bytes.bin;
  } else if (variant.startsWith('bin-')) {
    const b = ctx.bin();
    if (mm![2] === 'mem') {
      const rows = ctx.rows();
      search = (q) => rescoreFloat32(rows, q, hammingTopM(b, b.packQuery(q), M).map((h) => h.index), K).map((h) => h.index);
    } else {
      const rd = ctx.disk();
      search = (q) => rd.rescore(q, hammingTopM(b, b.packQuery(q), M).map((h) => h.index), K).map((h) => h.index);
    }
    onDisk = ctx.bytes.bin + ctx.bytes.f32;
  } else if (variant === 'i8-pure') {
    const p = ctx.i8();
    search = (q) => topKInt8(p, q, K).map((h) => h.index);
    onDisk = ctx.bytes.i8;
  } else if (variant.startsWith('i8-')) {
    const p = ctx.i8();
    const rd = ctx.disk();
    search = (q) => rd.rescore(q, topKInt8(p, q, M).map((h) => h.index), K).map((h) => h.index);
    onDisk = ctx.bytes.i8 + ctx.bytes.f32;
  } else throw new Error(`variante desconocida ${variant}`);
  const rssLoad = process.memoryUsage().rss;

  const qs = qf.queries.map((q) => Float32Array.from(q.vec));
  search(qs[0]); // calentamiento
  const times: number[] = [];
  let r10 = 0, mrr = 0, ov10 = 0, top1 = 0, withRel = 0;
  qs.forEach((q, qi) => {
    let hits: number[] = [];
    for (let r = 0; r < REPS; r++) {
      const t = performance.now();
      hits = search(q);
      times.push(performance.now() - t);
    }
    const truth = qf.queries[qi].truth;
    const t10 = new Set(truth.slice(0, 10));
    ov10 += hits.slice(0, 10).filter((h) => t10.has(h)).length / Math.max(1, t10.size);
    top1 += hits[0] === truth[0] ? 1 : 0;
    const rel = qf.queries[qi].relevant;
    if (rel && ctx.docOf) {
      withRel++;
      const docs = [...new Set(hits.map(ctx.docOf))];
      const rs = new Set(rel);
      r10 += docs.slice(0, 10).filter((p) => rs.has(p)).length / (rs.size || 1);
      const first = docs.findIndex((p) => rs.has(p));
      mrr += first >= 0 ? 1 / (first + 1) : 0;
    }
  });
  const nq = qs.length;
  console.log(JSON.stringify({
    variant, n: ctx.n, dims: ctx.dims, nQueries: nq,
    rssBaseMB: rssBase / MB, rssLoadedMB: rssLoad / MB, rssPeakMB: process.resourceUsage().maxRSS / 1024,
    p50Ms: pct(times, 50), p95Ms: pct(times, 95),
    overlap10: ov10 / nq, top1: top1 / nq,
    ...(withRel ? { recall10: r10 / withRel, mrr: mrr / withRel } : {}),
    diskBytes: onDisk,
  }));
  process.exit(0);
}

function child(kind: string, dir: string, variant: string, qfile: string, reps = 5): Record<string, unknown> {
  const r = spawnSync(TSX, [SELF, 'variant', '--kind', kind, '--dir', dir, '--variant', variant, '--queries', qfile, '--reps', String(reps)], { encoding: 'utf-8', maxBuffer: 64 * MB });
  if (r.status !== 0) throw new Error(`variante ${variant} falló: ${r.stderr.slice(-800)}`);
  return JSON.parse(r.stdout.trim().split('\n').pop()!);
}

// ── real ────────────────────────────────────────────────────────────────

async function real(): Promise<void> {
  const src = path.resolve(arg('src')!);
  const bench = JSON.parse(fs.readFileSync(arg('bench')!, 'utf-8')) as { query: string; relevantPaths: string[] }[];
  const work = fs.mkdtempSync(path.join(arg('work') ?? os.tmpdir(), 'se489-m7-real-'));
  try {
    fs.cpSync(src, path.join(work, 'savia-docs'), { recursive: true });
    const gen = readActive(work, 'savia-docs').active!;
    const dir = path.join(work, 'savia-docs', gen);
    const store = FlatVectorStore.load(dir);
    const c = store.manifest.contract;
    const emb = new OllamaEmbedder({ model: c.model, queryPrefix: c.queryPrefix, docPrefix: c.docPrefix });
    const live = await emb.digest();
    if (live !== c.modelDigest) throw new Error(`digest vivo ${live} ≠ índice ${c.modelDigest}: la medición no sería válida`);
    await emb.embed(['calentamiento'], 'query');
    const embMs: number[] = [];
    const queries: QueryFile['queries'] = [];
    for (const b of bench) {
      const t = performance.now();
      const [v] = await emb.embed([b.query], 'query');
      embMs.push(performance.now() - t);
      queries.push({ text: b.query, relevant: b.relevantPaths, vec: Array.from(v), truth: store.topK(v, 20).map((h) => h.index) });
    }
    const t0 = performance.now();
    BinaryProjection.build(store, 'N2');
    const tBin = performance.now() - t0;
    const t1 = performance.now();
    Int8Projection.build(store, 'N2');
    const tI8 = performance.now() - t1;
    const qfile = path.join(work, 'queries.json');
    fs.writeFileSync(qfile, JSON.stringify({ queries, dims: c.dims } satisfies QueryFile));
    const results = variantsFor().map((v) => { console.error(`real ${v}`); return child('real', dir, v, qfile); });
    const out = {
      kind: 'real', corpus: 'savia-docs (copia temporal)', generation: gen, chunks: store.size, dims: c.dims, model: c.model,
      queries: bench.length, embedP50Ms: pct(embMs, 50), embedP95Ms: pct(embMs, 95), buildBinaryMs: tBin, buildInt8Ms: tI8, results,
    };
    fs.writeFileSync(arg('out')!, JSON.stringify(out, null, 2));
    console.log(JSON.stringify(out, null, 2));
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

// ── sintético ───────────────────────────────────────────────────────────

const SYN_DIMS = 1024;
const LATENT = 16;

function xorshift(seed: number): () => number {
  let s = (seed >>> 0) || 1;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 0x100000000; };
}

/** Datos con estructura: mezcla de clusters en un espacio latente de 16 dim proyectado a 1024 + ruido. SINTÉTICO. */
function makeGenerator(n: number) {
  const r = xorshift(12345);
  const basis = new Float32Array(LATENT * SYN_DIMS).map(() => r() * 2 - 1);
  const K = Math.max(10, Math.round(n / 2000));
  const centers = new Float32Array(K * LATENT).map(() => (r() * 2 - 1) * 2);
  return (rng: () => number, out: Float32Array): void => {
    const k = Math.floor(rng() * K);
    out.fill(0);
    for (let l = 0; l < LATENT; l++) {
      const z = centers[k * LATENT + l] + (rng() + rng() - 1) * 0.8;
      const b = l * SYN_DIMS;
      for (let j = 0; j < SYN_DIMS; j++) out[j] += z * basis[b + j];
    }
    let norm = 0;
    for (let j = 0; j < SYN_DIMS; j++) { out[j] += (rng() - 0.5) * 1.2; norm += out[j] * out[j]; }
    norm = Math.sqrt(norm);
    for (let j = 0; j < SYN_DIMS; j++) out[j] /= norm;
  };
}

function synthPrep(n: number, dir: string, nq: number): string {
  fs.mkdirSync(dir, { recursive: true });
  const gen = makeGenerator(n);
  const rng = xorshift(777);
  const rw = rowWordsFor(SYN_DIMS);
  const vfile = path.join(dir, 'vectors-0.f32');
  const fd = fs.openSync(vfile, 'w');
  const BLOCK = 2048;
  const row = new Float32Array(SYN_DIMS);
  for (let i = 0; i < n; i += BLOCK) {
    const m = Math.min(BLOCK, n - i);
    const blk = new Float32Array(m * SYN_DIMS);
    for (let r = 0; r < m; r++) { gen(rng, row); blk.set(row, r * SYN_DIMS); }
    fs.writeSync(fd, new Uint8Array(blk.buffer), 0, blk.byteLength);
  }
  fs.closeSync(fd);
  // queries: puntos nuevos del mismo generador
  const qrng = xorshift(999);
  const queries = Array.from({ length: nq }, () => { const q = new Float32Array(SYN_DIMS); gen(qrng, q); return q; });
  // calibración + proyecciones + verdad exacta, en streaming
  const rfd = fs.openSync(vfile, 'r');
  const rowBuf = Buffer.alloc(SYN_DIMS * 4);
  const cal = calibrateInt8Rows(n, SYN_DIMS, (i) => {
    fs.readSync(rfd, rowBuf, 0, rowBuf.length, i * SYN_DIMS * 4);
    return new Float32Array(rowBuf.buffer.slice(rowBuf.byteOffset, rowBuf.byteOffset + rowBuf.length));
  });
  const binFd = fs.openSync(path.join(dir, 'bin.u32'), 'w');
  const i8Fd = fs.openSync(path.join(dir, 'int8.codes'), 'w');
  const best: { i: number; s: number }[][] = queries.map(() => []);
  const K = 20;
  for (let i = 0; i < n; i += BLOCK) {
    const m = Math.min(BLOCK, n - i);
    const bytes = Buffer.alloc(m * SYN_DIMS * 4);
    fs.readSync(rfd, bytes, 0, bytes.length, i * SYN_DIMS * 4);
    const blk = new Float32Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length));
    const bin = new Uint8Array(m * rw * 4);
    const codes = new Int8Array(m * SYN_DIMS);
    for (let r = 0; r < m; r++) {
      const v = blk.subarray(r * SYN_DIMS, (r + 1) * SYN_DIMS);
      packSigns(v, bin.subarray(r * rw * 4, (r + 1) * rw * 4));
      quantizeInt8(v, cal, codes.subarray(r * SYN_DIMS, (r + 1) * SYN_DIMS));
    }
    fs.writeSync(binFd, bin);
    fs.writeSync(i8Fd, new Uint8Array(codes.buffer));
    queries.forEach((q, qi) => {
      const b = best[qi];
      for (let r = 0; r < m; r++) {
        let s = 0;
        const off = r * SYN_DIMS;
        for (let j = 0; j < SYN_DIMS; j++) s += blk[off + j] * q[j];
        if (b.length < K) { b.push({ i: i + r, s }); if (b.length === K) b.sort((x, y) => y.s - x.s); }
        else if (s > b[K - 1].s) { b[K - 1] = { i: i + r, s }; b.sort((x, y) => y.s - x.s); }
      }
    });
  }
  fs.closeSync(binFd); fs.closeSync(i8Fd); fs.closeSync(rfd);
  fs.writeFileSync(path.join(dir, 'int8.scale'), new Uint8Array(cal.scale.buffer));
  fs.writeFileSync(path.join(dir, 'meta.json'), JSON.stringify({ n, dims: SYN_DIMS, synthetic: true }));
  const qfile = path.join(dir, 'queries.json');
  fs.writeFileSync(qfile, JSON.stringify({
    dims: SYN_DIMS,
    queries: queries.map((q, qi) => ({ vec: Array.from(q), truth: best[qi].map((b) => b.i) })),
  } satisfies QueryFile));
  return qfile;
}

function synth(): void {
  const sizes = (arg('sizes', '10000,100000,1000000') as string).split(',').map(Number);
  const nq = Number(arg('queries', '50'));
  const root = fs.mkdtempSync(path.join(arg('work') ?? os.tmpdir(), 'se489-m7-synth-'));
  const all: Record<string, unknown>[] = [];
  try {
    for (const n of sizes) {
      const dir = path.join(root, `n${n}`);
      const t = performance.now();
      console.error(`synth prep n=${n}`);
      const qfile = synthPrep(n, dir, nq);
      const prepMs = performance.now() - t;
      const results = variantsFor().map((v) => { console.error(`synth n=${n} ${v}`); return child('synth', dir, v, qfile, n >= 500_000 ? 1 : n >= 100_000 ? 2 : 5); });
      all.push({ synthetic: true, n, dims: SYN_DIMS, queries: nq, prepMs, results });
      fs.rmSync(dir, { recursive: true, force: true });
      fs.writeFileSync(arg('out')!, JSON.stringify({ kind: 'synthetic', runs: all }, null, 2));
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
  console.log(JSON.stringify({ kind: 'synthetic', runs: all }, null, 2));
}

const mode = process.argv[2];
const needs: Record<string, string[]> = { variant: ['kind', 'dir', 'variant', 'queries'], real: ['src', 'bench', 'out'], synth: ['out'] };
const missing = (needs[mode] ?? []).filter((a) => arg(a) === undefined);
if (!needs[mode] || missing.length) {
  console.error(`uso: real|synth|variant (ver cabecera)${missing.length ? `; faltan: ${missing.map((m) => `--${m}`).join(', ')}` : ''}`);
  process.exit(2);
}
if (mode === 'variant') runVariant(arg('kind')!, arg('dir')!, arg('variant')!, arg('queries')!);
else if (mode === 'real') await real();
else synth();
