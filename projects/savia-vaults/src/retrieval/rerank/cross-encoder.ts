// SE-489 M2 — reranker cross-encoder local (ONNX). El modelo y su tokenizador se fijan por
// digest sha256 (declarado en la configuración, no en el directorio del modelo) y se cargan del
// disco: este módulo no abre ninguna conexión. Si falta una dependencia, un fichero o el digest
// no coincide, `load` falla y la ruta devuelve el orden de M0 (fail-open en calidad).
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';

/** Puntúa pares (consulta, documento): más alto = más relevante. */
export interface RerankScorer {
  /** Identificador legible del modelo (para la traza). */
  id: string;
  /** Digest sha256 del fichero del modelo que se está usando. */
  digest: string;
  /** Una puntuación por documento, en el mismo orden. Lanza si no puede puntuar. */
  score(query: string, docs: string[], deadline: number): Promise<number[]>;
}

export interface RerankConfig {
  modelDir: string;
  modelSha256: string;
  tokenizerSha256: string;
  /** Candidatos a reordenar (N). */
  topN: number;
  /** Tope de tiempo del reranker, en ms. */
  maxMs: number;
}

const BATCH = 8;
export const RERANK_MAX_TOKENS = 512;
/** Tope de la consulta: si la consulta sola llenara el par, el documento se truncaría entero. */
export const RERANK_MAX_QUERY_CHARS = 1024;

/** Error con mensaje propio, apto para la traza (sin rutas ni detalle de librerías). */
export class RerankError extends Error {}

/** Puntúa por lotes y comprueba el plazo antes y después de cada lote. */
export async function scoreInBatches(scoreBatch: (docs: string[]) => Promise<number[]>, docs: string[], deadline: number, batch = BATCH): Promise<number[]> {
  const scores: number[] = [];
  for (let i = 0; i < docs.length; i += batch) {
    if (Date.now() > deadline) throw new RerankError('tiempo del reranker agotado');
    scores.push(...await scoreBatch(docs.slice(i, i + batch)));
    if (Date.now() > deadline) throw new RerankError('tiempo del reranker agotado');
  }
  return scores;
}
const SHA = /^[0-9a-f]{64}$/;

export type RerankConfigResult = { ok: true; config: RerankConfig } | { ok: false; reason: string };

/** Configuración desde variables de entorno; sin modelo o sin digest fijados, no hay reranker. */
export function resolveRerankConfig(env: NodeJS.ProcessEnv = process.env): RerankConfigResult {
  const modelDir = env.SAVIA_RERANK_MODEL_DIR;
  if (!modelDir) return { ok: false, reason: 'SAVIA_RERANK_MODEL_DIR sin definir' };
  const modelSha256 = (env.SAVIA_RERANK_MODEL_SHA256 ?? '').toLowerCase();
  const tokenizerSha256 = (env.SAVIA_RERANK_TOKENIZER_SHA256 ?? '').toLowerCase();
  if (!SHA.test(modelSha256) || !SHA.test(tokenizerSha256)) return { ok: false, reason: 'digests sha256 del modelo y del tokenizador sin fijar' };
  const topN = Number(env.SAVIA_RERANK_TOPN ?? 20);
  if (!Number.isInteger(topN) || topN < 1 || topN > 50) return { ok: false, reason: 'SAVIA_RERANK_TOPN: entero 1-50' };
  const maxMs = Number(env.SAVIA_RERANK_MAX_MS ?? 4000);
  if (!Number.isInteger(maxMs) || maxMs < 1) return { ok: false, reason: 'SAVIA_RERANK_MAX_MS: entero ≥ 1' };
  return { ok: true, config: { modelDir: path.resolve(modelDir), modelSha256, tokenizerSha256, topN, maxMs } };
}

const sha256 = (b: Buffer): string => crypto.createHash('sha256').update(b).digest('hex');

interface Encoded { ids: number[] }
interface TokenizerLike { encode(text: string, opts: { text_pair: string }): Encoded }

/** Carga el modelo verificando los digests. Lanza con un motivo corto si algo no cuadra. */
export async function loadOnnxCrossEncoder(cfg: RerankConfig): Promise<RerankScorer> {
  const modelFile = path.join(cfg.modelDir, 'model.onnx');
  const tokFile = path.join(cfg.modelDir, 'tokenizer.json');
  if (!fs.existsSync(modelFile) || !fs.existsSync(tokFile)) throw new RerankError('modelo o tokenizador ausentes');
  // Cada fichero se lee UNA vez: se hashea y se carga esa misma copia (sin ventana entre verificar y usar).
  const modelBytes = fs.readFileSync(modelFile);
  if (sha256(modelBytes) !== cfg.modelSha256) throw new RerankError('digest del modelo distinto del fijado');
  const tokBytes = fs.readFileSync(tokFile);
  if (sha256(tokBytes) !== cfg.tokenizerSha256) throw new RerankError('digest del tokenizador distinto del fijado');
  // Dependencias opcionales: si no están instaladas, el reranker no existe (fail-open).
  let ort: typeof import('onnxruntime-node');
  let tok: TokenizerLike;
  let session: Awaited<ReturnType<typeof import('onnxruntime-node').InferenceSession.create>>;
  try {
    ort = await import('onnxruntime-node');
    const { Tokenizer } = await import('@huggingface/tokenizers');
    tok = new Tokenizer(JSON.parse(tokBytes.toString('utf-8')), {}) as unknown as TokenizerLike;
    session = await ort.InferenceSession.create(modelBytes, { graphOptimizationLevel: 'all' });
  } catch {
    throw new RerankError('dependencia o modelo no cargables');
  }
  if (!session.inputNames.includes('input_ids') || !session.inputNames.includes('attention_mask')) throw new RerankError('entradas del modelo no reconocidas');
  const withTypes = session.inputNames.includes('token_type_ids');
  const out = session.outputNames[0];

  async function scoreBatch(query: string, docs: string[]): Promise<number[]> {
    const enc = docs.map(d => {
      const ids = tok.encode(query.slice(0, RERANK_MAX_QUERY_CHARS), { text_pair: d }).ids;
      // Truncado por la cola conservando el separador final (</s>, id 2 en XLM-R).
      return ids.length > RERANK_MAX_TOKENS ? [...ids.slice(0, RERANK_MAX_TOKENS - 1), ids[ids.length - 1]] : ids;
    });
    const len = Math.max(...enc.map(e => e.length));
    const ids = new BigInt64Array(enc.length * len).fill(1n);
    const mask = new BigInt64Array(enc.length * len);
    enc.forEach((e, i) => e.forEach((v, j) => { ids[i * len + j] = BigInt(v); mask[i * len + j] = 1n; }));
    const shape = [enc.length, len];
    const feeds: Record<string, InstanceType<typeof ort.Tensor>> = {
      input_ids: new ort.Tensor('int64', ids, shape), attention_mask: new ort.Tensor('int64', mask, shape),
    };
    if (withTypes) feeds.token_type_ids = new ort.Tensor('int64', new BigInt64Array(enc.length * len), shape);
    const res = await session.run(feeds);
    const data = Array.from(res[out].data as ArrayLike<number>);
    if (data.length !== docs.length || data.some(x => !Number.isFinite(x))) throw new RerankError('salida del modelo no válida');
    return data;
  }

  return {
    id: path.basename(cfg.modelDir), digest: cfg.modelSha256,
    score: (query, docs, deadline) => scoreInBatches(b => scoreBatch(query, b), docs, deadline),
  };
}
