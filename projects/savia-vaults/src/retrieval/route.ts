// SE-489 — contrato común de las rutas de recuperación (M0..M7).
// Una ruta recibe la consulta, las cúpulas ya autorizadas por el plano de control y un
// presupuesto; devuelve hits compatibles con RagHit, la evidencia de cada uno, la traza y el
// presupuesto consumido. Las rutas no abren contenido salvo a través de `RouteContext`, que
// aplica el guard (`guard.ts`) a cada nodo antes de abrirlo. Guía: docs/retrieval-routes.md.
import type { RagHit, RagMode } from '../rag/types.js';
import type { StructureNode } from '../rag/structure-index.js';

/** Contrato estable: sube si cambia de forma incompatible (las rutas declaran la versión que implementan). */
export const ROUTE_CONTRACT_VERSION = 1;

export interface RetrievalBudget {
  /** Tiempo de pared máximo de la ruta, en ms. */
  maxLatencyMs: number;
  /** Llamadas a modelo (embeddings de consulta, reranker, LLM local). */
  maxModelCalls: number;
  /** Nodos abiertos a través del guard (hits admitidos, notas leídas, chunks de un documento). */
  maxNodes: number;
  /** Saltos de expansión (vecinos, padre, vínculos). */
  maxHops: number;
  /** Tokens de entrada a modelos (estimación: caracteres / 4). */
  maxInputTokens: number;
}

export type BudgetKey = 'latencyMs' | 'modelCalls' | 'nodes' | 'hops' | 'inputTokens';
export type BudgetUse = Record<BudgetKey, number>;

/** Presupuesto por defecto: holgado para M0..M3/M5; M4 exige uno declarado (AC-7). */
export const DEFAULT_BUDGET: RetrievalBudget = Object.freeze({
  maxLatencyMs: 8000, maxModelCalls: 4, maxNodes: 200, maxHops: 2, maxInputTokens: 8000,
});

/** Topes duros: ninguna petición puede pedir más. */
export const BUDGET_CAPS: RetrievalBudget = Object.freeze({
  maxLatencyMs: 120_000, maxModelCalls: 64, maxNodes: 5000, maxHops: 8, maxInputTokens: 200_000,
});

/** Cúpula autorizada por el plano de control. Solo nombre y nivel: la ruta no ve rutas en disco. */
export interface AuthorizedDome {
  name: string;
  confidentiality: string;
}

export interface RetrievalRequest {
  query: string;
  /** Cúpulas autorizadas: las fija el plano de control (authorize), nunca el modelo ni la consulta. */
  domes: readonly AuthorizedDome[];
  /** Fecha ISO para versiones y tiempo; una ruta que no lo soporta lo avisa en `warnings`. */
  asOf?: string;
  budget: RetrievalBudget;
  /** true si el presupuesto lo declaró la petición (no es el de por defecto). */
  budgetDeclared: boolean;
  /** Semilla de toda decisión no determinista de la ruta. */
  seed: number;
  k: number;
  mode: RagMode;
  pathPrefix?: string;
  includeStale?: boolean;
  maxChars?: number;
}

/** Procedencia verificable de un hit. */
export interface Evidence {
  /** chunkId del hit al que respalda. */
  chunkId: string;
  dome: string;
  /** Ruta relativa de la nota, o `files/<id>` en Savia Files. */
  document: string;
  /** Nota: `sha256:<hex>` de los bytes actuales; fichero: id de revisión. */
  revision: string;
  /** Solo notas: id de blob de git (SHA-1 de `blob <n>\0<bytes>`), el que usa el banco R1. */
  gitBlob?: string;
  /** Nota: `#<ordinal> <heading>`; fichero: localizador canónico (`page:3`, `cell:Hoja!B2`…). */
  locator: string;
  /** `sha256:<hex>` del texto servido en el hit. */
  contentHash: string;
}

export interface TraceStep {
  step: string;
  detail?: string;
  /** Nodos que tocó el paso (sin rutas ni títulos de lo denegado). */
  nodes?: number;
}

export interface RetrievalTrace {
  route: string;
  /** Por qué se eligió la ruta (petición explícita, router…). */
  reason: string;
  seed: number;
  steps: TraceStep[];
  /** Nodos denegados por el guard: solo el número, nunca cuáles. */
  denied: number;
}

/** Resultado final de una ruta, tal como lo devuelve el runner tras el guard final. */
export interface RetrievalResult {
  hits: RagHit[];
  /** Una por hit (mismo `chunkId`), más la que la ruta aporte de nodos leídos y aún servibles. */
  evidence: Evidence[];
  trace: RetrievalTrace;
  consumed: BudgetUse;
  /** La ruta decide no responder (sin evidencia suficiente). */
  abstain?: boolean;
  warnings?: string[];
}

/**
 * Lo que devuelve `run`. El runner (`runner.ts`) completa traza, presupuesto consumido y
 * evidencia, y vuelve a pasar cada hit por el guard: lo que ya no es servible se descarta.
 */
export interface RouteOutput {
  hits: RagHit[];
  evidence?: Evidence[];
  abstain?: boolean;
  warnings?: string[];
}

/** Referencia a un nodo antes de abrirlo. */
export interface NodeRef {
  dome: string;
  /** Ruta relativa de la nota o `files/<id>`. */
  path: string;
  documentId?: string;
}

/** Nota abierta por el guard: su contenido es dato, nunca instrucción. */
export interface OpenedNote {
  dome: string;
  path: string;
  revision: string;
  text: string;
}

/** Chunk del índice activo de un documento, abierto por el guard. */
export interface OpenedChunk {
  chunkId: string;
  ordinal: number;
  heading: string;
  text: string;
}

/**
 * Árbol de un documento (StructureIndex de M3) abierto por el guard: nodos en pre-orden (el primero
 * es el documento) y los documentos Markdown de su directorio que el guard admite ahora y que no
 * están excluidos por estado (salvo `includeStale`). Sin texto: el texto se lee con `documentChunks`.
 */
export interface OpenedStructure {
  nodes: StructureNode[];
  siblings: NodeRef[];
}

export interface CandidateOptions {
  k?: number;
  mode?: RagMode;
}

/**
 * Lo único que una ruta puede usar para leer. Cada método pasa por el guard y descuenta
 * del presupuesto; devuelve `undefined` si el nodo no se puede abrir (denegado, inexistente o
 * presupuesto agotado), sin distinguir el motivo hacia la ruta.
 */
export interface RouteContext {
  /** Candidatos iniciales de RagService (BM25 + denso + RRF), ya filtrados por el guard. */
  candidates(query: string, opts?: CandidateOptions): Promise<RagHit[]>;
  /** Abre una nota (contenido actual en disco). */
  openNote(ref: NodeRef): OpenedNote | undefined;
  /** Chunks del índice activo de un documento (vecinos/padre). */
  documentChunks(ref: NodeRef): OpenedChunk[] | undefined;
  /**
   * SE-489 M3 (aditivo, opcional para dobles de test): árbol del documento en la generación activa.
   * 1 `nodes` por el documento y 1 por cada hermano devuelto.
   */
  documentStructure?(ref: NodeRef): OpenedStructure | undefined;
  /** Descuenta presupuesto; false si se agotaría (no descuenta). */
  consume(key: Exclude<BudgetKey, 'latencyMs'>, n?: number): boolean;
  /** Milisegundos que quedan del presupuesto de latencia. */
  timeLeftMs(): number;
  /** Añade un paso a la traza. */
  step(step: string, detail?: string, nodes?: number): void;
  /** Evidencia de un hit (la calcula el guard; undefined si ya no es servible). */
  evidenceOf(hit: RagHit): Evidence | undefined;
}

export interface RetrievalRoute {
  /** Identificador estable (`M0`…`M7`). */
  id: string;
  description: string;
  contractVersion: typeof ROUTE_CONTRACT_VERSION;
  /** Soporta `asOf`; si no, se avisa con `AS_OF_UNSUPPORTED`. */
  supportsAsOf: boolean;
  /** AC-7: la ruta no corre sin presupuesto declarado en la petición (p. ej. M4). */
  requiresDeclaredBudget: boolean;
  run(req: RetrievalRequest, ctx: RouteContext): Promise<RouteOutput>;
}

export const AS_OF_UNSUPPORTED = 'AS_OF_UNSUPPORTED';
export const BUDGET_EXHAUSTED = 'BUDGET_EXHAUSTED';

export type RouteErrorCode = 'UNKNOWN_ROUTE' | 'INVALID_BUDGET' | 'BUDGET_REQUIRED' | 'DUPLICATE_ROUTE' | 'INVALID_ROUTE';

export class RouteError extends Error {
  constructor(public readonly code: RouteErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'RouteError';
  }
}

const ROUTE_ID = /^[A-Za-z][A-Za-z0-9_-]{0,31}$/;
const registry = new Map<string, RetrievalRoute>();

/** Registra una ruta; un id repetido es un error (no se sustituyen rutas en silencio). */
export function registerRoute(route: RetrievalRoute): void {
  if (!ROUTE_ID.test(route.id)) throw new RouteError('INVALID_ROUTE', `id de ruta no válido: ${route.id}`);
  if (route.contractVersion !== ROUTE_CONTRACT_VERSION) {
    throw new RouteError('INVALID_ROUTE', `${route.id} implementa el contrato v${route.contractVersion}, se espera v${ROUTE_CONTRACT_VERSION}`);
  }
  if (registry.has(route.id)) throw new RouteError('DUPLICATE_ROUTE', `ruta ${route.id} ya registrada`);
  registry.set(route.id, route);
}

export function getRoute(id: string): RetrievalRoute {
  const r = registry.get(id);
  if (!r) throw new RouteError('UNKNOWN_ROUTE', `ruta "${id}" no registrada (${listRoutes().join(', ') || 'ninguna'})`);
  return r;
}

export const listRoutes = (): string[] => [...registry.keys()].sort();

/** Solo tests: retira una ruta registrada por el propio test. */
export function unregisterRoute(id: string): boolean {
  return registry.delete(id);
}

const BUDGET_FIELDS = Object.keys(DEFAULT_BUDGET) as (keyof RetrievalBudget)[];

/**
 * Presupuesto efectivo. Ausente ⇒ el de por defecto (`declared: false`). Cada campo
 * presente debe ser un entero ≥ 0 y ≤ su tope; un campo desconocido es un error (cierre seguro).
 */
export function resolveBudget(input: unknown): { budget: RetrievalBudget; declared: boolean } {
  if (input === undefined || input === null) return { budget: { ...DEFAULT_BUDGET }, declared: false };
  if (typeof input !== 'object' || Array.isArray(input)) throw new RouteError('INVALID_BUDGET', 'budget debe ser un objeto');
  const raw = input as Record<string, unknown>;
  for (const k of Object.keys(raw)) {
    if (!BUDGET_FIELDS.includes(k as keyof RetrievalBudget)) throw new RouteError('INVALID_BUDGET', `campo desconocido: ${k}`);
  }
  const budget = { ...DEFAULT_BUDGET };
  for (const k of BUDGET_FIELDS) {
    if (raw[k] === undefined) continue;
    const v = raw[k];
    if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v > BUDGET_CAPS[k]) {
      throw new RouteError('INVALID_BUDGET', `${k}: entero entre 0 y ${BUDGET_CAPS[k]}`);
    }
    budget[k] = v;
  }
  return { budget, declared: true };
}

const LIMIT_OF: Record<Exclude<BudgetKey, 'latencyMs'>, keyof RetrievalBudget> = {
  modelCalls: 'maxModelCalls', nodes: 'maxNodes', hops: 'maxHops', inputTokens: 'maxInputTokens',
};

/** Contador de presupuesto: nunca deja pasar de un límite. */
export class BudgetMeter {
  private readonly used: BudgetUse = { latencyMs: 0, modelCalls: 0, nodes: 0, hops: 0, inputTokens: 0 };
  private readonly t0: number;
  exhausted?: BudgetKey;

  constructor(private readonly budget: RetrievalBudget, private readonly now: () => number = Date.now) {
    this.t0 = now();
  }

  consume(key: Exclude<BudgetKey, 'latencyMs'>, n = 1): boolean {
    if (!Number.isFinite(n) || n < 0) return false;
    if (this.timeLeftMs() <= 0) { this.exhausted ??= 'latencyMs'; return false; }
    if (this.used[key] + n > this.budget[LIMIT_OF[key]]) { this.exhausted ??= key; return false; }
    this.used[key] += n;
    return true;
  }

  /** Todo o nada: si alguna cantidad no cabe, no descuenta ninguna. */
  consumeMany(items: [Exclude<BudgetKey, 'latencyMs'>, number][]): boolean {
    if (this.timeLeftMs() <= 0) { this.exhausted ??= 'latencyMs'; return false; }
    for (const [key, n] of items) {
      if (!Number.isFinite(n) || n < 0) return false;
      if (this.used[key] + n > this.budget[LIMIT_OF[key]]) { this.exhausted ??= key; return false; }
    }
    for (const [key, n] of items) this.used[key] += n;
    return true;
  }

  timeLeftMs(): number {
    return Math.max(0, this.budget.maxLatencyMs - (this.now() - this.t0));
  }

  snapshot(): BudgetUse {
    return { ...this.used, latencyMs: this.now() - this.t0 };
  }
}

/** Estimación de tokens de entrada (sin tokenizer: caracteres / 4, por arriba). */
export const estimateTokens = (text: string): number => Math.ceil(text.length / 4);
