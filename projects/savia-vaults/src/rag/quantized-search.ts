import { hammingTopM } from './binary-search.js';
import { BinaryProjection, Int8Projection, openProjectionSource, type ProjectionSource } from './binary-store.js';
import { DiskVectorReader, rescoreFloat32, topKInt8, type VectorRows } from './rescore.js';
import type { TopKHit } from './store.js';
import { RagError, type IndexCipher } from './types.js';

/**
 * SE-489 M7 — Punto de entrada único de la ruta cuantizada. Aún no está registrada como ruta:
 * cuando exista el contrato común (`RetrievalRoute`), el adaptador solo llama a `search` y envuelve
 * hits y traza; la autorización por cúpula/nota se aplica antes (aquí llega como `accept`).
 *
 * Es opt-in: nada en `vault_rag` ni en `RagService` la usa. El float32 sigue siendo la fuente de verdad.
 */

export type QuantizedStrategy = 'binary-rescore' | 'int8-rescore' | 'binary-pure' | 'int8-pure';

export interface QuantizedSearchOptions {
  strategy: QuantizedStrategy;
  k: number;
  /** Candidatos que se rescoran en float32 (ignorado en las variantes `-pure`). Por defecto 100. */
  m?: number;
  /** Autorización por fila (cúpula, nota, cuarentena): obligatoria; para «todo permitido» pasar `() => true` de forma explícita. */
  accept: (index: number) => boolean;
}

export class QuantizedIndex {
  private bin?: BinaryProjection;
  private i8?: Int8Projection;
  private disk?: DiskVectorReader;

  private constructor(
    readonly source: ProjectionSource,
    private readonly classification: string,
    private readonly cipher?: IndexCipher,
    private readonly rows?: VectorRows,
  ) {}

  /** `rows` opcional: float32 residente para rescorar; sin él se leen las filas candidatas desde disco (solo índices en claro). */
  static open(dir: string, classification: string, cipher?: IndexCipher, rows?: VectorRows): QuantizedIndex {
    const source = openProjectionSource(dir, cipher);
    const r = rows as (VectorRows & { size?: number; manifest?: { generation: string; seq: number } }) | undefined;
    if (r && ((r.size !== undefined && r.size !== source.size) || (r.manifest && (r.manifest.generation !== source.manifest.generation || r.manifest.seq !== source.manifest.seq)))) {
      throw new RagError('CONTRACT_MISMATCH', 'los vectores en memoria no corresponden a la generación y seq de la proyección');
    }
    return new QuantizedIndex(source, classification, cipher, rows);
  }

  search(query: Float32Array, o: QuantizedSearchOptions): TopKHit[] {
    const m = Math.max(o.k, o.m ?? 100);
    if (o.strategy === 'binary-pure' || o.strategy === 'binary-rescore') {
      const b = (this.bin ??= BinaryProjection.load(this.source, this.classification, this.cipher));
      const hits = hammingTopM(b, b.packQuery(query), o.strategy === 'binary-pure' ? o.k : m, o.accept);
      if (o.strategy === 'binary-pure') return hits.map((h) => ({ index: h.index, score: -h.distance }));
      return this.rescore(query, hits.map((h) => h.index), o.k);
    }
    const p = (this.i8 ??= Int8Projection.load(this.source, this.classification, this.cipher));
    if (o.strategy === 'int8-pure') return topKInt8(p, query, o.k, o.accept);
    return this.rescore(query, topKInt8(p, query, m, o.accept).map((h) => h.index), o.k);
  }

  private rescore(query: Float32Array, candidates: number[], k: number): TopKHit[] {
    if (this.rows) return rescoreFloat32(this.rows, query, candidates, k);
    return (this.disk ??= new DiskVectorReader(this.source)).rescore(query, candidates, k);
  }

  close(): void { this.disk?.close(); }
}
