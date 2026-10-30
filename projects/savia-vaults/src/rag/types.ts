// SE-410 — Savia RAG: tipos compartidos.
import type { Locator } from '../files/types.js';

/** Mismo orden que `LEVELS` de storage/note-level.ts (SE-481 R4). */
export type Confidentiality = 'N1' | 'N2' | 'N3' | 'N4' | 'N4B';
export type RagMode = 'hybrid' | 'dense' | 'bm25';
export type DomeRagStatus = 'ok' | 'stale' | 'degraded' | 'denied' | 'timeout' | 'error' | 'not_indexed';

/** Bloque opcional `rag` de una cúpula en savia-vaults.domes.json. */
export interface RagDomeConfig {
  enabled?: boolean;
  model?: string;
  chunkChars?: number;
  overlap?: number;
  halfLifeDays?: number;
  excludeStatuses?: string[];
  evalSet?: string;
  inlineSyncBudget?: number;
}

export interface ResolvedRagConfig {
  enabled: boolean;
  model: string;
  chunkChars: number;
  overlap: number;
  halfLifeDays: number;
  excludeStatuses: string[];
  evalSet?: string;
  inlineSyncBudget: number;
}

/** P1: contrato inmutable de una generación. Su hash es el id de generación. */
export interface EmbeddingContract {
  provider: 'ollama' | 'hash';
  model: string;
  modelDigest: string;
  dims: number;
  normalize: true;
  chunkerVersion: string;
  chunkChars: number;
  overlap: number;
  queryPrefix: string;
  docPrefix: string;
}

/** Metadatos de frescura extraídos del frontmatter. */
export interface ChunkMeta {
  title: string;
  status?: string;
  validUntil?: string;
  supersededBy?: string;
  modified: string;
  confidentiality?: string;
}

/** SE-413: procedencia de un chunk que viene de un fichero de Savia Files. */
export interface FileSourceRef {
  kind: 'file';
  documentId: string;
  revisionId: string;
  name: string;
  locator: Locator;
  /** Último localizador del chunk si abarca varias unidades (celdas, filas, líneas). */
  locatorEnd?: Locator;
}

/** SE-413: fuente no markdown que el indexer trata como documento (`files/<id>`). */
export interface VirtualSource {
  path: string;
  /** Cambia cuando cambia el contenido o el troceado: dispara re-embebido. */
  hash: string;
  mtimeMs: number;
  confidentiality?: string;
  chunks(opts: { chunkChars: number; overlap: number }): Chunk[];
}

export interface Chunk {
  id: string;          // `${path}#${ordinal}`
  path: string;
  ordinal: number;
  heading: string;     // "título › h2 › h3"
  text: string;        // texto del chunk sin cabecera
  embedText: string;   // cabecera contextual + texto (lo que se embebe)
  hash: string;        // sha256(embedText + generationId), rellenado por el indexer
  meta: ChunkMeta;
  source?: FileSourceRef;
}

export interface DocEntry {
  hash: string;        // sha256 de los bytes del fichero
  mtimeMs: number;
  chunkIds: string[];
  /** Motivo por el que no se embebe (p. ej. confidencialidad de la nota > cúpula). */
  skipped?: string;
}

export interface Manifest {
  version: 1;
  dome: string;
  generation: string;
  contract: EmbeddingContract;
  seq: number;
  createdAt: string;
  updatedAt: string;
  docs: Record<string, DocEntry>;
  chunkCount: number;
  fingerprint: string;
  /** SE-417: chunks, vectores y BM25 sellados con la clave de índice de la cúpula. */
  sealed?: boolean;
  /** SE-481: versión de las reglas de clasificación con que se evaluaron las notas reutilizadas. */
  classificationRules?: number;
}

/** SE-417: cifrado de los ficheros del índice de una cúpula cifrada. `part` va en los datos asociados. */
export interface IndexCipher {
  seal(data: Uint8Array, part: string): Buffer;
  open(data: Uint8Array, part: string): Buffer;
}

export interface ActivePointer {
  active?: string;
  previous?: string;
  shadow?: string;
  /** Métricas de eval registradas al activar cada generación (línea base de P5). */
  metrics?: Record<string, { recallAt10: number; mrr: number; at: string }>;
  updatedAt: string;
}

export interface SyncReport {
  dome: string;
  generation: string;
  promoted: boolean;
  shadow: boolean;
  docs: { added: number; updated: number; deleted: number; unchanged: number; skipped: number; quarantined: number };
  /** SE-481: notas en cuarentena por código de diagnóstico (sin rutas). */
  quarantine: Record<string, number>;
  chunks: { total: number; embedded: number; reused: number };
  durationMs: number;
}

export interface RagHit {
  dome: string;
  confidentiality: Confidentiality;
  path: string;
  chunkId: string;
  heading: string;
  text: string;
  score: number;
  signals: { denseRank?: number; bm25Rank?: number; dense?: number; bm25?: number };
  freshness: { modified: string; status?: string; supersededBy?: string; decay: number };
  generation: string;
  source?: FileSourceRef;
  /** SE-485 R4: solo si la consulta lleva un identificador con forma de código; falso = vecino, no respuesta. */
  exactMatch?: boolean;
}

export interface RagRequest {
  queries: string[];
  domes?: string[] | '*';
  k?: number;
  mode?: RagMode;
  pathPrefix?: string;
  includeStale?: boolean;
  maxChars?: number;
  concurrency?: number;
  timeoutMs?: number;
}

export interface DomeOutcome {
  name: string;
  status: DomeRagStatus;
  generation?: string;
  detail?: string;
  /** SE-419: hits de ficheros ocultos por permisos del documento (o borrados); solo el número. */
  filtered?: number;
  /** SE-481 R3: hits de notas descartados al revalidar al servir (borradas, fuera de nivel o en cuarentena); solo el número. */
  degradation?: { revalidated: number };
}

export interface RagResponse {
  results: { query: string; hits: RagHit[]; /** SE-485 R4: avisos de la consulta. */ warnings?: string[] }[];
  merged?: RagHit[];
  domes: DomeOutcome[];
  timings: { totalMs: number; embedMs: number; syncMs: number };
  /** SE-411 G1: `cosine` si todas las cúpulas comparten contrato; `rank` si no. */
  fusion?: 'cosine' | 'rank';
}

export type RagErrorCode =
  | 'CONTRACT_MISMATCH'
  | 'INVALID_INPUT'
  | 'UNKNOWN_DOME'
  | 'LOCKED'
  | 'CORRUPT_INDEX'
  | 'UNSAFE_HOME'
  | 'EMBEDDER_UNAVAILABLE'
  | 'NOT_INDEXED'
  | 'PROMOTION_REJECTED'
  | 'PROJECTION_MISMATCH';

export class RagError extends Error {
  constructor(public readonly code: RagErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'RagError';
  }
}

export const RAG_DEFAULTS: ResolvedRagConfig = {
  enabled: false,
  model: 'qwen3-embedding:0.6b',
  chunkChars: 1200,
  overlap: 0.15,
  halfLifeDays: 0,
  excludeStatuses: ['deprecated', 'superseded', 'archived'],
  inlineSyncBudget: 25,
};

export const RAG_LIMITS = {
  maxQueries: 8,
  maxQueryChars: 1000,
  maxK: 50,
  defaultK: 8,
  defaultMaxChars: 6000,
  defaultConcurrency: 4,
  defaultTimeoutMs: 8000,
  maxFileBytes: 1024 * 1024,
  candidateDepth: 50,
  rrfK: 60,
  maxChunksPerDoc: 2,
} as const;
