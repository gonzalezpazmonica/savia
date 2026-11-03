// SE-489 M2 — carga de las dependencias opcionales del reranker (onnxruntime-node y
// @huggingface/tokenizers). Son `optionalDependencies`: npm puede no instalarlas (instalación con
// --omit=optional, o un postinstall que falla, como la descarga de binarios CUDA de onnxruntime-node
// en Linux x64, tras lo cual npm retira el paquete sin error). El código no puede depender de sus
// tipos para compilar: aquí se declara solo la parte de su API que usa el reranker y la carga
// comprueba esa forma en tiempo de ejecución.

/** Tensor de onnxruntime: solo se lee `data`. */
export interface OrtTensor { readonly data: unknown }

export interface OrtSession {
  readonly inputNames: readonly string[];
  readonly outputNames: readonly string[];
  run(feeds: Record<string, OrtTensor>): Promise<Record<string, OrtTensor>>;
}

/** Subconjunto de `onnxruntime-node` que usa el reranker. */
export interface OrtModule {
  Tensor: new (type: 'int64', data: BigInt64Array, dims: readonly number[]) => OrtTensor;
  InferenceSession: { create(model: Uint8Array, options: { graphOptimizationLevel: 'all' }): Promise<OrtSession> };
}

export interface Encoded { ids: number[] }
export interface TokenizerLike { encode(text: string, opts: { text_pair: string }): Encoded }

/** Subconjunto de `@huggingface/tokenizers` que usa el reranker. */
export interface TokenizersModule { Tokenizer: new (tokenizerJson: unknown, config: object) => TokenizerLike }

export interface RerankDeps { ort: OrtModule; tokenizers: TokenizersModule }

/** Importa un módulo por nombre. Inyectable para probar la ausencia de las dependencias. */
export type ModuleImporter = (specifier: string) => Promise<unknown>;

// El especificador va en una variable a propósito: tsc no resuelve el paquete y compila igual esté
// o no instalado. La forma real se valida abajo; no se da por supuesta.
const nativeImport: ModuleImporter = specifier => import(specifier);

export const ORT_MODULE = 'onnxruntime-node';
export const TOKENIZERS_MODULE = '@huggingface/tokenizers';

/** Error de carga con mensaje apto para la traza (sin rutas ni detalle de la librería). */
export class RerankDepsError extends Error {}

const isFn = (x: unknown): boolean => typeof x === 'function';
const field = (o: unknown, k: string): unknown =>
  (o !== null && typeof o === 'object') || isFn(o) ? (o as Record<string, unknown>)[k] : undefined;

function isOrt(m: unknown): m is OrtModule {
  return isFn(field(m, 'Tensor')) && isFn(field(field(m, 'InferenceSession'), 'create'));
}

function isTokenizers(m: unknown): m is TokenizersModule {
  return isFn(field(m, 'Tokenizer'));
}

/** Carga y valida las dos dependencias. Lanza `RerankDepsError` si falta alguna o no tiene la forma esperada. */
export async function loadRerankDeps(importer: ModuleImporter = nativeImport): Promise<RerankDeps> {
  let ort: unknown;
  let tokenizers: unknown;
  try {
    ort = await importer(ORT_MODULE);
    tokenizers = await importer(TOKENIZERS_MODULE);
  } catch {
    throw new RerankDepsError('dependencia opcional del reranker no instalada');
  }
  if (!isOrt(ort) || !isTokenizers(tokenizers)) throw new RerankDepsError('dependencia opcional del reranker con API no reconocida');
  return { ort, tokenizers };
}
