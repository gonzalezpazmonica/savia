import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { calibrateInt8Rows, packSigns, packedBytes, QUANTIZER_VERSION, quantizeInt8, type Int8Calibration } from './quantize.js';
import { ensureSafeHome, FlatVectorStore, generationId, readActive, writeAtomic } from './store.js';
import { RagError, type Chunk, type IndexCipher, type Manifest } from './types.js';

/**
 * SE-489 M7 — Proyecciones derivadas (binaria e int8) de una generación.
 * Viven dentro del directorio de la generación: la retirada de la generación las borra con ella.
 * Cada fichero lleva un `binding` (hash) que liga la proyección a generación, modelo + digest,
 * dimensiones, orden y contenido de los chunks, clasificación y versión del cuantizador.
 * Si algo no casa se rechaza: nunca se sirven resultados de una proyección que no corresponde.
 * No se versionan: `ensureSafeHome` impide escribir dentro de un repo git y el cifrado sigue a la fuente.
 */

export type ProjectionKind = 'binary' | 'int8';

/** Lo mínimo de una generación para validar y servir una proyección: no exige los vectores float32 en RAM. */
export interface ProjectionSource {
  readonly manifest: Manifest;
  readonly chunks: Chunk[];
  readonly size: number;
  readonly dims: number;
  readonly dir: string;
}

/** Fuente con acceso a los vectores: necesaria solo para construir. */
export interface VectorSource extends ProjectionSource {
  vector(index: number): Float32Array;
}

/**
 * Abre manifest y chunks de una generación SIN cargar los vectores: es lo que permite servir
 * búsqueda binaria/int8 con rescoring desde disco sin el float32 residente. Mismas comprobaciones
 * de contrato y cifrado que FlatVectorStore.load.
 */
export function openProjectionSource(dir: string, cipher?: IndexCipher): ProjectionSource {
  const manifest = FlatVectorStore.readManifest(dir);
  if (!manifest) throw new RagError('NOT_INDEXED', `sin manifest en ${dir}`);
  if (generationId(manifest.contract) !== manifest.generation) throw new RagError('CORRUPT_INDEX', `manifest de ${dir} no coincide con su contrato`);
  if (manifest.sealed && !cipher) throw new RagError('CORRUPT_INDEX', `el índice de ${manifest.dome} está cifrado y falta su clave`);
  let chunks: Chunk[];
  try {
    const raw = fs.readFileSync(path.join(dir, `chunks-${manifest.seq}.jsonl`));
    const text = (manifest.sealed ? cipher!.open(raw, `chunks-${manifest.seq}`) : raw).toString('utf-8');
    chunks = text.split('\n').filter(Boolean).map((line) => {
      const c = JSON.parse(line) as Omit<Chunk, 'embedText'>;
      return { ...c, embedText: `${c.heading}\n\n${c.text}` };
    });
  } catch (e) {
    throw new RagError('CORRUPT_INDEX', `no se pudieron leer los chunks de ${manifest.generation}: ${e instanceof Error ? e.message : e}`);
  }
  if (chunks.length !== manifest.chunkCount) throw new RagError('CORRUPT_INDEX', `chunks ${chunks.length}/${manifest.chunkCount} en ${manifest.generation}`);
  return { manifest, chunks, size: chunks.length, dims: manifest.contract.dims, dir };
}
const HEADER_VERSION = 1;

export interface ProjectionHeader {
  headerVersion: number;
  kind: ProjectionKind;
  quantizer: string;
  dome: string;
  generation: string;
  seq: number;
  model: string;
  modelDigest: string;
  dims: number;
  chunkCount: number;
  chunkOrder: string;
  classification: string;
  sealed: boolean;
  /** sha256 del payload en claro (integridad, además del AEAD si está sellado). */
  payloadHash: string;
  binding: string;
}

type Binding = Omit<ProjectionHeader, 'payloadHash' | 'binding'>;

const sha = (data: string | Uint8Array): string => createHash('sha256').update(data).digest('hex');

export function chunkOrderHash(store: ProjectionSource): string {
  const h = createHash('sha256');
  for (const c of store.chunks) h.update(`${c.id}\t${c.hash}\t${c.meta.confidentiality ?? ''}\n`);
  return h.digest('hex');
}

function bindingOf(b: Binding): string {
  return sha(JSON.stringify(Object.entries(b).sort(([x], [y]) => (x < y ? -1 : 1))));
}

export function expectedBinding(store: ProjectionSource, kind: ProjectionKind, classification: string): Binding {
  const m = store.manifest;
  return {
    headerVersion: HEADER_VERSION, kind, quantizer: QUANTIZER_VERSION, dome: m.dome, generation: m.generation, seq: m.seq,
    model: m.contract.model, modelDigest: m.contract.modelDigest, dims: m.contract.dims,
    chunkCount: store.size, chunkOrder: chunkOrderHash(store), classification, sealed: Boolean(m.sealed),
  };
}

const base = (seq: number, kind: ProjectionKind) => `proj-${seq}-${kind}`;
export const projectionPaths = (dir: string, seq: number, kind: ProjectionKind) => ({
  header: path.join(dir, `${base(seq, kind)}.json`),
  payload: path.join(dir, `${base(seq, kind)}.bin`),
});

/** Datos asociados del AEAD: el binding liga el payload sellado a su generación, modelo, orden y clasificación. */
function sealPart(kind: ProjectionKind, seq: number, binding: string): string {
  return `${base(seq, kind)}|${binding}`;
}

/** Las distancias Hamming van en Uint16 con 0xFFFF reservado para filas excluidas. */
export function assertDimsSupported(dims: number): void {
  if (rowWordsFor(dims) * 32 >= 0xffff) throw new RangeError(`dims=${dims} no soportado por la búsqueda binaria (distancia en 16 bits)`);
}

function writeProjection(store: ProjectionSource, kind: ProjectionKind, classification: string, payload: Uint8Array, cipher?: IndexCipher): ProjectionHeader {
  const m = store.manifest;
  assertDimsSupported(store.dims);
  if (m.sealed && !cipher) throw new RagError('PROJECTION_MISMATCH', 'la fuente está cifrada: la proyección exige el mismo cifrador');
  ensureSafeHome(store.dir);
  const b = expectedBinding(store, kind, classification);
  const header: ProjectionHeader = { ...b, payloadHash: sha(payload), binding: bindingOf(b) };
  const p = projectionPaths(store.dir, m.seq, kind);
  // Payload primero, cabecera después: sin cabecera válida la proyección no existe.
  writeAtomic(p.payload, m.sealed ? cipher!.seal(payload, sealPart(kind, m.seq, header.binding)) : payload);
  writeAtomic(p.header, JSON.stringify(header, null, 2));
  return header;
}

function readProjection(store: ProjectionSource, kind: ProjectionKind, classification: string, cipher?: IndexCipher): { header: ProjectionHeader; payload: Buffer } {
  const m = store.manifest;
  const p = projectionPaths(store.dir, m.seq, kind);
  let header: ProjectionHeader;
  let raw: Buffer;
  try {
    header = JSON.parse(fs.readFileSync(p.header, 'utf-8')) as ProjectionHeader;
    raw = fs.readFileSync(p.payload);
  } catch {
    throw new RagError('PROJECTION_MISMATCH', `sin proyección ${kind} para ${m.generation} seq ${m.seq}`);
  }
  if (!header || typeof header !== 'object') throw new RagError('PROJECTION_MISMATCH', `cabecera de la proyección ${kind} no válida`);
  const want = expectedBinding(store, kind, classification);
  for (const k of Object.keys(want) as (keyof Binding)[]) {
    if (header[k] !== want[k]) throw new RagError('PROJECTION_MISMATCH', `proyección ${kind} obsoleta o ajena: difiere ${k}`);
  }
  if (header.binding !== bindingOf(want)) throw new RagError('PROJECTION_MISMATCH', `binding de la proyección ${kind} no válido`);
  if (m.sealed && !cipher) throw new RagError('PROJECTION_MISMATCH', 'proyección cifrada sin cifrador');
  let payload: Buffer;
  try {
    payload = m.sealed ? cipher!.open(raw, sealPart(kind, m.seq, header.binding)) : raw;
  } catch {
    throw new RagError('PROJECTION_MISMATCH', `no se pudo abrir la proyección ${kind}`);
  }
  if (sha(payload) !== header.payloadHash) throw new RagError('PROJECTION_MISMATCH', `contenido de la proyección ${kind} alterado`);
  return { header, payload };
}

function toBuffer(src: Uint8Array): ArrayBuffer {
  return src.buffer.slice(src.byteOffset, src.byteOffset + src.byteLength) as ArrayBuffer;
}

// ── Binaria ────────────────────────────────────────────────────────────

/** Filas alineadas a 32 bits: el recorrido de Hamming lee palabras. */
export function rowWordsFor(dims: number): number {
  return Math.ceil(packedBytes(dims) / 4);
}

export class BinaryProjection {
  constructor(
    public readonly header: ProjectionHeader,
    /** n filas × rowWords palabras. */
    public readonly words: Uint32Array,
  ) {}
  get size(): number { return this.header.chunkCount; }
  get dims(): number { return this.header.dims; }
  get rowWords(): number { return rowWordsFor(this.header.dims); }
  get bytes(): number { return this.words.byteLength; }

  /** Consulta empaquetada con el mismo relleno que las filas. */
  packQuery(q: ArrayLike<number>): Uint32Array {
    if (q.length !== this.dims) throw new RagError('CONTRACT_MISMATCH', `consulta de ${q.length} dims, proyección ${this.dims}`);
    const buf = new Uint8Array(this.rowWords * 4);
    packSigns(q, buf);
    return new Uint32Array(buf.buffer);
  }

  static build(store: VectorSource, classification: string, cipher?: IndexCipher): BinaryProjection {
    const rw = rowWordsFor(store.dims);
    const bytes = new Uint8Array(store.size * rw * 4);
    for (let i = 0; i < store.size; i++) packSigns(store.vector(i), bytes.subarray(i * rw * 4, (i + 1) * rw * 4));
    const header = writeProjection(store, 'binary', classification, bytes, cipher);
    return new BinaryProjection(header, new Uint32Array(toBuffer(bytes)));
  }

  static load(store: ProjectionSource, classification: string, cipher?: IndexCipher): BinaryProjection {
    const { header, payload } = readProjection(store, 'binary', classification, cipher);
    const rw = rowWordsFor(store.dims);
    if (payload.byteLength !== store.size * rw * 4) throw new RagError('PROJECTION_MISMATCH', 'tamaño de la proyección binaria inconsistente');
    return new BinaryProjection(header, new Uint32Array(toBuffer(payload)));
  }
}

// ── Int8 ───────────────────────────────────────────────────────────────

export class Int8Projection {
  constructor(
    public readonly header: ProjectionHeader,
    public readonly calibration: Int8Calibration,
    /** n filas × dims códigos. */
    public readonly codes: Int8Array,
  ) {}
  get size(): number { return this.header.chunkCount; }
  get dims(): number { return this.header.dims; }
  get bytes(): number { return this.codes.byteLength + this.calibration.scale.byteLength; }

  /** Payload: [percentil f64][scale f32 × dims][códigos i8 × n·dims]. */
  private static encode(cal: Int8Calibration, codes: Int8Array): Uint8Array {
    const out = new Uint8Array(8 + cal.dims * 4 + codes.length);
    const dv = new DataView(out.buffer);
    dv.setFloat64(0, cal.percentile, true);
    for (let j = 0; j < cal.dims; j++) dv.setFloat32(8 + j * 4, cal.scale[j], true);
    out.set(new Uint8Array(codes.buffer, codes.byteOffset, codes.length), 8 + cal.dims * 4);
    return out;
  }

  static build(store: VectorSource, classification: string, cipher?: IndexCipher): Int8Projection {
    const d = store.dims;
    const cal = calibrateInt8Rows(store.size, d, (i) => store.vector(i));
    const codes = new Int8Array(store.size * d);
    for (let i = 0; i < store.size; i++) quantizeInt8(store.vector(i), cal, codes.subarray(i * d, (i + 1) * d));
    const header = writeProjection(store, 'int8', classification, Int8Projection.encode(cal, codes), cipher);
    return new Int8Projection(header, cal, codes);
  }

  static load(store: ProjectionSource, classification: string, cipher?: IndexCipher): Int8Projection {
    const { header, payload } = readProjection(store, 'int8', classification, cipher);
    const d = store.dims;
    if (payload.byteLength !== 8 + d * 4 + store.size * d) throw new RagError('PROJECTION_MISMATCH', 'tamaño de la proyección int8 inconsistente');
    const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    const scale = new Float32Array(d);
    for (let j = 0; j < d; j++) scale[j] = dv.getFloat32(8 + j * 4, true);
    const codes = new Int8Array(toBuffer(payload.subarray(8 + d * 4)));
    return new Int8Projection(header, { version: QUANTIZER_VERSION, dims: d, percentile: dv.getFloat64(0, true), scale }, codes);
  }
}

// ── Ciclo de vida ──────────────────────────────────────────────────────

const PROJ_FILE = /^proj-(\d+)-(binary|int8)\.(json|bin)$/;

/** Borra proyecciones de una generación que no corresponden a su manifest vigente (otra seq). Devuelve ficheros borrados. */
export function gcProjections(dir: string, manifest: Manifest | undefined, tmpGraceMs = 10 * 60 * 1000): number {
  let removed = 0;
  for (const f of fs.existsSync(dir) ? fs.readdirSync(dir) : []) {
    const m = f.match(PROJ_FILE);
    const tmp = !m && /^proj-.*\.tmp-/.test(f);
    if (!m && !tmp) continue;
    if (m && manifest && Number(m[1]) === manifest.seq) continue;
    // Un build en curso escribe un tmp y lo renombra: no se barre hasta pasado el periodo de gracia.
    if (tmp && Date.now() - fs.statSync(path.join(dir, f)).mtimeMs < tmpGraceMs) continue;
    fs.rmSync(path.join(dir, f), { force: true });
    removed++;
  }
  return removed;
}

/**
 * Reconcilia una cúpula con su puntero: las generaciones que ya no son activa/previa/sombra
 * se borran enteras en el servicio (con sus proyecciones); aquí se barren además las proyecciones
 * obsoletas dentro de las que se conservan y cualquier directorio de generación huérfano.
 */
export function reconcileProjections(home: string, dome: string): number {
  const domeRoot = path.join(home, dome);
  const pointer = readActive(home, dome);
  // Puntero ausente o ilegible: no se destruye nada (readActive no distingue ambos casos).
  if (!pointer.updatedAt) return 0;
  const keep = new Set([pointer.active, pointer.previous, pointer.shadow].filter(Boolean) as string[]);
  let removed = 0;
  for (const e of fs.existsSync(domeRoot) ? fs.readdirSync(domeRoot, { withFileTypes: true }) : []) {
    if (!e.isDirectory()) continue;
    const full = path.join(domeRoot, e.name);
    if (keep.has(e.name)) removed += gcProjections(full, FlatVectorStore.readManifest(full));
    else removed += gcProjections(full, undefined);
  }
  return removed;
}
