import * as fs from 'node:fs';
import * as path from 'node:path';
import { HashEmbedder, OllamaEmbedder, type Embedder } from './embedder.js';
import { FileStore } from '../files/store.js';
import { fileSources } from '../files/rag-source.js';
import { asPrincipal, canRead, type Principal } from '../files/policy.js';
import { indexCipher } from '../files/keys.js';
import { sodiumReady } from '../files/crypto.js';
import { RagIndexer, listIndexable, logEvent } from './indexer.js';
import { fileServable, isMarkdown } from '../storage/note-level.js';
import { fanOut, withTimeout, TimeoutError } from './parallel.js';
import { excludedReason, promotionDecision, resolveRagConfig, sloStatus, type EvalMetrics } from './policy.js';
import { containsIdentifier, IDENTIFIER_NOT_FOUND, queryIdentifiers } from '../search/identifiers.js';
import { applyCharBudget, fuseAcross, fuseByCosine, searchStore, warmBm25, type StoreHit } from './retriever.js';
import {
  FlatVectorStore, defaultRagHome, domeDir, ensureSafeHome, gcGeneration, generationId, readActive, writeActive,
} from './store.js';
import {
  RAG_LIMITS, RagError, type Confidentiality, type DomeOutcome, type EmbeddingContract, type RagDomeConfig,
  type RagHit, type RagMode, type RagRequest, type RagResponse, type ResolvedRagConfig, type SyncReport, type IndexCipher,
} from './types.js';

/**
 * SE-410 — RagService: orquesta frescura, embeddings por contrato, fan-out
 * paralelo y fusión. Una instancia por proceso (MCP server o CLI).
 */

export interface RagDomeRef {
  name: string;
  path: string;
  confidentiality: Confidentiality;
  rag?: RagDomeConfig;
  /** SE-413: bloque `files` de la cúpula; si está habilitado, sus ficheros entran en RAG. */
  files?: { enabled?: boolean; encryption?: boolean };
}

export interface RagServiceOptions {
  domes: () => RagDomeRef[];
  home?: string;
  embedderFactory?: (cfg: ResolvedRagConfig) => Embedder;
  /**
   * Lanza si la acción no está autorizada sobre la cúpula. SE-419: puede devolver el principal
   * `{username, role}`; con él, cada hit de un fichero se filtra con los permisos del documento.
   */
  authorize?: (dome: string, action: 'read' | 'write', tool: string) => Promise<unknown>;
  /** true en el servidor MCP (proceso largo): permite sync en segundo plano. */
  background?: boolean;
  env?: NodeJS.ProcessEnv;
}

export interface EvalQueryInput { query: string; relevantPaths: string[]; kind?: string }

export interface RagEvalResult extends EvalMetrics {
  n: number;
  recallAt5: number;
  mode: RagMode;
  generation: string;
  p50Ms: number;
  p95Ms: number;
  failed: { query: string; relevant: string[]; retrieved: string[] }[];
}

export interface DomeStatusReport {
  name: string;
  enabled: boolean;
  confidentiality: Confidentiality;
  active?: string;
  shadow?: string;
  previous?: string;
  contract?: EmbeddingContract;
  currentDigest?: string;
  digestMatch: boolean;
  chunks: number;
  totalDocs: number;
  pendingDocs: number;
  staleRatio: number;
  lagHours: number;
  generationAgeHours?: number;
  memoryBytes: number;
  slo: { ok: boolean; alerts: string[] };
}

export type SyncResult = SyncReport & { gate?: { promote: boolean; reason: string } };

/**
 * Fábrica por defecto: Ollama. `SAVIA_RAG_TEST_PROVIDER=hash` existe solo para
 * tests e2e sin red; el contrato resultante declara `provider: hash` (P9).
 */
let testProviderWarned = false;

export function defaultEmbedderFactory(env: NodeJS.ProcessEnv = process.env): (cfg: ResolvedRagConfig) => Embedder {
  if (env.SAVIA_RAG_TEST_PROVIDER === 'hash') {
    if (!testProviderWarned) console.error('[rag] WARNING: SAVIA_RAG_TEST_PROVIDER=hash — embeddings de test, no semánticos');
    testProviderWarned = true;
    // cfg.model puede venir ya como `hash:<modelo>` (reconstruido desde el contrato).
    return (cfg) => new HashEmbedder(256, cfg, `hash:${cfg.model.replace(/^hash:/, '')}`);
  }
  return (cfg) => new OllamaEmbedder({ model: cfg.model, params: { chunkChars: cfg.chunkChars, overlap: cfg.overlap } });
}

const LRU_MIN = 4;
const DEFAULT_MEMORY_MB = 512;
const WRITE_DEBOUNCE_MS = 2000;

function percentile(values: number[], p: number): number {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)];
}

export class RagService {
  private readonly home: string;
  private readonly env: NodeJS.ProcessEnv;
  private readonly embedders = new Map<string, Embedder>();
  private readonly stores = new Map<string, FlatVectorStore>();
  private readonly syncing = new Map<string, Promise<SyncResult>>();
  private readonly timers = new Map<string, NodeJS.Timeout>();

  constructor(private readonly o: RagServiceOptions) {
    this.home = o.home ?? defaultRagHome();
    this.env = o.env ?? process.env;
  }

  // ── Configuración y dependencias ──────────────────────────────────────

  private dome(name: string): RagDomeRef {
    const d = this.o.domes().find(x => x.name === name);
    if (!d) throw new RagError('UNKNOWN_DOME', `cúpula "${name}" no registrada`);
    return d;
  }

  config(d: RagDomeRef): ResolvedRagConfig {
    return resolveRagConfig(d.rag, this.env);
  }

  private embedder(cfg: ResolvedRagConfig): Embedder {
    const key = `${cfg.model}|${cfg.chunkChars}|${cfg.overlap}`;
    let e = this.embedders.get(key);
    if (!e) {
      e = (this.o.embedderFactory ?? defaultEmbedderFactory(this.env))(cfg);
      this.embedders.set(key, e);
    }
    return e;
  }

  private filesStore(d: RagDomeRef): FileStore | undefined {
    return d.files?.enabled
      ? new FileStore({ home: this.env.SAVIA_FILES_HOME || undefined, dome: d.name, domeLevel: d.confidentiality, keysHome: this.env.SAVIA_FILES_KEYS_HOME || undefined })
      : undefined;
  }

  /** SE-417: cifrador del índice si el almacén de ficheros de la cúpula está cifrado. */
  private cipherFor(d: RagDomeRef): IndexCipher | undefined {
    const files = this.filesStore(d);
    return files?.isEncrypted() ? indexCipher(files.keys) : undefined;
  }

  /**
   * SE-417: tras cifrar una cúpula, el índice se reescribe sellado (sin re-embeber: los
   * vectores se reutilizan) y se borran las generaciones que sigan en claro.
   */
  async sealIndex(name: string): Promise<void> {
    await sodiumReady();
    const d = this.dome(name);
    if (!this.cipherFor(d) || !this.config(d).enabled) return;
    await this.sync(name);
    const dir = domeDir(this.home, name);
    const pointer = readActive(this.home, name);
    for (const g of fs.existsSync(dir) ? fs.readdirSync(dir) : []) {
      const m = FlatVectorStore.readManifest(path.join(dir, g));
      if (m && !m.sealed) {
        fs.rmSync(path.join(dir, g), { recursive: true, force: true });
        if (pointer.previous === g || pointer.shadow === g) {
          writeActive(this.home, name, { active: pointer.active, previous: pointer.previous === g ? undefined : pointer.previous, shadow: pointer.shadow === g ? undefined : pointer.shadow });
        }
      }
    }
    for (const k of this.stores.keys()) if (k.startsWith(`${name}/`)) this.stores.delete(k);
  }

  /**
   * SE-417: durante una rotación de claves (la anterior aún abre), reescribe cada generación
   * sellada con la clave nueva en el mismo seq; el BM25 persistido se regenera.
   */
  resealIndex(name: string): void {
    const d = this.dome(name);
    const cipher = this.cipherFor(d);
    if (!cipher) return;
    const dir = domeDir(this.home, name);
    for (const g of fs.existsSync(dir) ? fs.readdirSync(dir) : []) {
      const genDir = path.join(dir, g);
      const m = FlatVectorStore.readManifest(genDir);
      if (!m?.sealed) continue;
      const st = FlatVectorStore.load(genDir, undefined, cipher);
      FlatVectorStore.write(genDir, st.manifest, st.chunks, st.chunks.map((_, i) => new Float32Array(st.vector(i))), cipher);
      for (const f of fs.readdirSync(genDir)) if (/^bm25-/.test(f)) fs.rmSync(path.join(genDir, f), { force: true });
    }
    for (const k of this.stores.keys()) if (k.startsWith(`${name}/`)) this.stores.delete(k);
  }

  private indexer(d: RagDomeRef, cfg = this.config(d)): RagIndexer {
    const files = this.filesStore(d);
    const cipher = files?.isEncrypted() ? indexCipher(files.keys) : undefined;
    return new RagIndexer({
      dome: d.name, vaultPath: d.path, home: this.home, cfg, embedder: this.embedder(cfg), domeLevel: d.confidentiality,
      ...(files ? { sources: () => fileSources(files) } : {}),
      ...(cipher ? { cipher } : {}),
    });
  }

  /**
   * Caché de índices (SE-411 G2): capacidad = cúpulas habilitadas (mín. 4) y tope de
   * memoria `SAVIA_RAG_MEMORY_MB` (def. 512). Clave con seq: se invalida tras cada sync.
   */
  private loadStore(dome: string, generation: string): FlatVectorStore {
    const dir = path.join(domeDir(this.home, dome), generation);
    const manifest = FlatVectorStore.readManifest(dir);
    if (!manifest) throw new RagError('NOT_INDEXED', `generación ${generation} de ${dome} no existe`);
    const key = `${dome}/${generation}/${manifest.seq}`;
    const hit = this.stores.get(key);
    if (hit) {
      this.stores.delete(key);
      this.stores.set(key, hit);
      return hit;
    }
    const ref = this.o.domes().find(x => x.name === dome);
    const store = FlatVectorStore.load(dir, undefined, ref ? this.cipherFor(ref) : undefined);
    for (const k of this.stores.keys()) if (k.startsWith(`${dome}/${generation}/`)) this.stores.delete(k);
    this.stores.set(key, store);
    const capacity = Math.max(LRU_MIN, this.o.domes().filter(d => this.config(d).enabled).length);
    const budget = Number(this.env.SAVIA_RAG_MEMORY_MB ?? DEFAULT_MEMORY_MB) * 1024 * 1024;
    const bytes = (st: FlatVectorStore) => st.size * st.dims * 4 + st.chunks.reduce((n, c) => n + c.text.length * 2, 0);
    let total = [...this.stores.values()].reduce((n, st) => n + bytes(st), 0);
    for (const [k, st] of this.stores) {
      if (this.stores.size <= 1 || (this.stores.size <= capacity && total <= budget)) break;
      if (k === key) continue;
      this.stores.delete(k);
      total -= bytes(st);
    }
    return store;
  }

  /** Bytes aproximados de los índices cargados (vectores + texto). */
  loadedMemoryBytes(): number {
    return [...this.stores.values()].reduce((n, st) => n + st.size * st.dims * 4 + st.chunks.reduce((m, c) => m + c.text.length * 2, 0), 0);
  }

  /** P1 sin sondeo (SE-411 G5): generación que produciría el modelo vivo. */
  private async liveGeneration(emb: Embedder, contract: EmbeddingContract): Promise<{ generation: string; digest: string }> {
    if (emb.digest) {
      const digest = await emb.digest();
      return { generation: generationId({ ...contract, modelDigest: digest }), digest };
    }
    const live = await emb.contract();
    return { generation: generationId(live), digest: live.modelDigest };
  }

  // ── Sync, promoción y generaciones ────────────────────────────────────

  sync(name: string, opts: { rebuild?: boolean } = {}): Promise<SyncResult> {
    const inflight = this.syncing.get(name);
    if (inflight && !opts.rebuild) return inflight;
    const run = this.runSync(name, opts).finally(() => this.syncing.delete(name));
    this.syncing.set(name, run);
    return run;
  }

  private async runSync(name: string, opts: { rebuild?: boolean }): Promise<SyncResult> {
    await sodiumReady();
    const d = this.dome(name);
    const cfg = this.config(d);
    const report: SyncResult = await this.indexer(d, cfg).sync(opts);
    if (report.shadow) {
      const { metrics, ...decision } = await this.gate(d, cfg, report.generation, false);
      report.gate = decision;
      if (decision.promote) {
        this.activate(name, report.generation);
        await this.recordBaseline(d, cfg, report.generation, metrics);
        report.promoted = true;
        report.shadow = false;
      }
      logEvent(this.home, { event: 'gate', dome: name, generation: report.generation, ...decision });
    } else if (report.promoted || !readActive(this.home, name).metrics?.[report.generation]) {
      await this.recordBaseline(d, cfg, report.generation);
    }
    return report;
  }

  private loadEvalSet(d: RagDomeRef, cfg: ResolvedRagConfig): EvalQueryInput[] | undefined {
    if (!cfg.evalSet) return undefined;
    // Ruta relativa al vault (o absoluta); la fija la operadora en el registry.
    const file = path.resolve(d.path, cfg.evalSet);
    if (!file.endsWith('.json') || !fs.existsSync(file)) return undefined;
    return JSON.parse(fs.readFileSync(file, 'utf-8')) as EvalQueryInput[];
  }

  /**
   * P5: la activa se evalúa en vivo; si su modelo ya no está disponible (deriva
   * de digest, P4), se usa la línea base registrada al activarla.
   */
  private async gate(d: RagDomeRef, cfg: ResolvedRagConfig, candidate: string, force: boolean) {
    const pointer = readActive(this.home, d.name);
    const hasActive = Boolean(pointer.active) && pointer.active !== candidate;
    const queries = this.loadEvalSet(d, cfg);
    let active: EvalMetrics | undefined;
    let cand: EvalMetrics | undefined;
    if (queries?.length && hasActive && !force) {
      try {
        active = await this.evaluate(d.name, queries, { generation: pointer.active });
      } catch (e) {
        if (!(e instanceof RagError) || !['CONTRACT_MISMATCH', 'EMBEDDER_UNAVAILABLE'].includes(e.code)) throw e;
        active = pointer.metrics?.[pointer.active!];
      }
      cand = await this.evaluate(d.name, queries, { generation: candidate });
    }
    const manifest = FlatVectorStore.readManifest(path.join(domeDir(this.home, d.name), candidate));
    const indexable = (await this.indexer(d).pending()).totalDocs;
    const coverage = manifest ? (indexable ? Object.keys(manifest.docs).length / indexable : 1) : 0;
    return { ...promotionDecision({ active, candidate: cand, coverage: Math.min(1, coverage), hasActive, force }), metrics: cand };
  }

  /** Registra la línea base de eval de una generación recién activada. */
  private async recordBaseline(d: RagDomeRef, cfg: ResolvedRagConfig, generation: string, known?: EvalMetrics): Promise<void> {
    let m = known;
    if (!m) {
      const queries = this.loadEvalSet(d, cfg);
      if (!queries?.length) return;
      try { m = await this.evaluate(d.name, queries, { generation }); } catch { return; }
    }
    const p = readActive(this.home, d.name);
    writeActive(this.home, d.name, {
      active: p.active, previous: p.previous, shadow: p.shadow,
      metrics: { ...(p.metrics ?? {}), [generation]: { recallAt10: m.recallAt10, mrr: m.mrr, at: new Date().toISOString() } },
    });
  }

  private activate(name: string, generation: string): void {
    const p = readActive(this.home, name);
    if (p.active === generation) return;
    writeActive(this.home, name, {
      active: generation,
      previous: p.active,
      shadow: p.shadow === generation ? undefined : p.shadow,
    });
  }

  async promote(name: string, generation: string, force = false): Promise<{ promote: boolean; reason: string }> {
    const d = this.dome(name);
    if (!FlatVectorStore.readManifest(path.join(domeDir(this.home, name), generation))) {
      throw new RagError('NOT_INDEXED', `generación ${generation} de ${name} no existe`);
    }
    const cfg = this.config(d);
    const { metrics, ...decision } = await this.gate(d, cfg, generation, force);
    if (!decision.promote) throw new RagError('PROMOTION_REJECTED', decision.reason);
    this.activate(name, generation);
    await this.recordBaseline(d, cfg, generation, metrics);
    logEvent(this.home, { event: 'promote', dome: name, generation, force, reason: decision.reason });
    return decision;
  }

  async rollback(name: string): Promise<string> {
    this.dome(name);
    const p = readActive(this.home, name);
    if (!p.previous) throw new RagError('NOT_INDEXED', `${name} no tiene generación anterior`);
    writeActive(this.home, name, { active: p.previous, previous: p.active, shadow: p.shadow });
    logEvent(this.home, { event: 'rollback', dome: name, from: p.active, to: p.previous });
    return p.previous;
  }

  async gc(name: string): Promise<number> {
    this.dome(name);
    const dir = domeDir(this.home, name);
    if (!fs.existsSync(dir)) return 0;
    const p = readActive(this.home, name);
    const keep = new Set([p.active, p.previous, p.shadow].filter(Boolean) as string[]);
    let removed = 0;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      const full = path.join(dir, e.name);
      if (keep.has(e.name)) removed += gcGeneration(full);
      else { fs.rmSync(full, { recursive: true, force: true }); removed++; }
    }
    return removed;
  }

  /** Borra todo el índice de una cúpula con rag.enabled=false; con rag.enabled=true se rechaza. */
  async drop(name: string): Promise<boolean> {
    const d = this.dome(name);
    if (this.config(d).enabled) throw new RagError('INVALID_INPUT', `${name} tiene rag.enabled=true; deshabilítala antes de borrar su índice`);
    const dir = domeDir(this.home, name);
    if (!fs.existsSync(dir)) return false;
    fs.rmSync(dir, { recursive: true, force: true });
    logEvent(this.home, { event: 'drop', dome: name });
    return true;
  }

  /** Disparador de escritura (P3): debounce de 2 s por cúpula; solo en el servidor. */
  scheduleSync(name: string): void {
    if (!this.o.background) return;
    const d = this.o.domes().find(x => x.name === name);
    if (!d || !this.config(d).enabled) return;
    clearTimeout(this.timers.get(name));
    const t = setTimeout(() => {
      this.timers.delete(name);
      this.sync(name).catch(e => logEvent(this.home, { event: 'sync_error', dome: name, detail: String(e) }));
    }, WRITE_DEBOUNCE_MS);
    t.unref?.();
    this.timers.set(name, t);
  }

  // ── Búsqueda ─────────────────────────────────────────────────────────

  private validate(req: RagRequest): Required<Pick<RagRequest, 'k' | 'mode' | 'maxChars' | 'concurrency' | 'timeoutMs'>> {
    const q = req.queries;
    if (!Array.isArray(q) || q.length < 1 || q.length > RAG_LIMITS.maxQueries) {
      throw new RagError('INVALID_INPUT', `queries: entre 1 y ${RAG_LIMITS.maxQueries}`);
    }
    for (const s of q) {
      if (typeof s !== 'string' || !s.trim() || s.length > RAG_LIMITS.maxQueryChars) {
        throw new RagError('INVALID_INPUT', `cada consulta: 1-${RAG_LIMITS.maxQueryChars} caracteres`);
      }
    }
    const k = req.k ?? RAG_LIMITS.defaultK;
    if (!Number.isInteger(k) || k < 1 || k > RAG_LIMITS.maxK) throw new RagError('INVALID_INPUT', `k: 1-${RAG_LIMITS.maxK}`);
    const mode = req.mode ?? 'hybrid';
    if (!['hybrid', 'dense', 'bm25'].includes(mode)) throw new RagError('INVALID_INPUT', `mode no válido: ${mode}`);
    const maxChars = req.maxChars ?? RAG_LIMITS.defaultMaxChars;
    if (!Number.isFinite(maxChars) || maxChars < 500) throw new RagError('INVALID_INPUT', 'maxChars ≥ 500');
    return {
      k, mode, maxChars,
      concurrency: Math.max(1, Math.min(16, req.concurrency ?? RAG_LIMITS.defaultConcurrency)),
      timeoutMs: Math.max(50, req.timeoutMs ?? RAG_LIMITS.defaultTimeoutMs),
    };
  }

  private targetDomes(req: RagRequest): RagDomeRef[] {
    const all = this.o.domes();
    if (!req.domes || req.domes === '*') {
      return all.filter(d => d.confidentiality !== 'N4' && d.confidentiality !== 'N4B' && this.config(d).enabled);
    }
    return [...new Set(req.domes)].map(n => this.dome(n));
  }

  async search(req: RagRequest): Promise<RagResponse> {
    await sodiumReady();
    const t0 = Date.now();
    const opt = this.validate(req);
    const targets = this.targetDomes(req);
    const outcomes = new Map<string, DomeOutcome>(targets.map(d => [d.name, { name: d.name, status: 'ok' }]));
    let syncMs = 0;

    // 2. Autorización por cúpula: las denegadas se declaran, nunca se omiten.
    const allowed: RagDomeRef[] = [];
    const principals = new Map<string, Principal | undefined>();
    for (const d of targets) {
      try {
        principals.set(d.name, asPrincipal(await this.o.authorize?.(d.name, 'read', 'vault_rag')));
        allowed.push(d);
      } catch (e) {
        outcomes.set(d.name, { name: d.name, status: 'denied', detail: e instanceof Error ? e.message : String(e) });
      }
    }

    // 3. Frescura (P3-lectura) y carga del índice por cúpula, en paralelo con timeout.
    interface Prepared { d: RagDomeRef; cfg: ResolvedRagConfig; store: FlatVectorStore }
    const prepared = await fanOut(allowed.map(d => ({
      key: d.name,
      fn: async (signal): Promise<Prepared | undefined> => {
        const cfg = this.config(d);
        if (!cfg.enabled) {
          outcomes.set(d.name, { name: d.name, status: 'not_indexed', detail: 'sin bloque rag habilitado' });
          return undefined;
        }
        const s0 = Date.now();
        const pending = await this.indexer(d, cfg).pending();
        let status: DomeOutcome['status'] = 'ok';
        let detail: string | undefined;
        if (pending.pendingDocs > 0) {
          if (pending.pendingDocs <= cfg.inlineSyncBudget) {
            try {
              await this.sync(d.name);
            } catch (e) {
              status = 'stale';
              detail = e instanceof Error ? e.message : String(e);
            }
          } else {
            status = 'stale';
            detail = `${pending.pendingDocs} documentos pendientes > presupuesto inline ${cfg.inlineSyncBudget}; ejecutar rag sync`;
            if (this.o.background) this.sync(d.name).catch(err => logEvent(this.home, { event: 'sync_error', dome: d.name, detail: String(err) }));
          }
        }
        syncMs += Date.now() - s0;
        // Si la cúpula ya se dio por perdida (timeout), el sync puede terminar,
        // pero no se carga su índice ni se toca el resultado (SE-412).
        if (signal.aborted) return undefined;
        const active = readActive(this.home, d.name).active;
        if (!active) {
          outcomes.set(d.name, { name: d.name, status: 'not_indexed', detail: detail ?? 'sin generación activa; ejecutar rag sync' });
          return undefined;
        }
        const store = this.loadStore(d.name, active);
        outcomes.set(d.name, { name: d.name, status, generation: active, detail });
        return { d, cfg, store };
      },
    })), { concurrency: opt.concurrency, timeoutMs: opt.timeoutMs });

    const ready: Prepared[] = [];
    for (const d of allowed) {
      const r = prepared.get(d.name)!;
      if (r.ok) { if (r.value) ready.push(r.value); }
      else outcomes.set(d.name, { name: d.name, status: r.timeout ? 'timeout' : 'error', detail: r.error });
    }

    // 4. Embeddings de consultas: un lote por contrato (P1); contrato vivo distinto ⇒ degradado.
    const e0 = Date.now();
    const queryVecs = new Map<string, Float32Array[]>();
    let embedding: Promise<unknown> = Promise.resolve();
    if (opt.mode !== 'bm25') {
      const byGen = new Map<string, Prepared[]>();
      for (const p of ready) byGen.set(p.store.manifest.generation, [...(byGen.get(p.store.manifest.generation) ?? []), p]);
      embedding = Promise.all([...byGen.entries()].map(async ([gen, group]) => {
        const degrade = (detail: string) => {
          for (const p of group) {
            const prev = outcomes.get(p.d.name)!;
            outcomes.set(p.d.name, { ...prev, status: 'degraded', detail: prev.detail ? `${prev.detail}; ${detail}` : detail });
          }
        };
        try {
          const contract = group[0].store.manifest.contract;
          const emb = this.embedder({ ...group[0].cfg, model: contract.model });
          const live = await withTimeout(this.liveGeneration(emb, contract), opt.timeoutMs);
          if (live.generation !== gen) {
            degrade(`CONTRACT_MISMATCH: el modelo vivo (${contract.model} ${live.digest.slice(0, 12)}) no es el de la generación ${gen}; generación sombra pendiente`);
            return;
          }
          queryVecs.set(gen, await withTimeout(emb.embed(req.queries, 'query'), opt.timeoutMs));
        } catch (e) {
          degrade(e instanceof TimeoutError ? `embed de consulta: ${e.message}` : (e instanceof Error ? e.message : String(e)));
        }
      }));
    }
    // SE-411 G5: mientras Ollama calcula (GPU), se carga BM25 en CPU. Se cede el
    // event loop un instante para que la petición HTTP salga antes del trabajo síncrono.
    let embedDone = e0;
    const tracked = embedding.then(() => { embedDone = Date.now(); });
    if (opt.mode !== 'dense') {
      await new Promise(r => setTimeout(r, 2));
      for (const p of ready) warmBm25(p.store);
    }
    await tracked;
    // Solo el tiempo del embedding (la carga de BM25 va solapada y no cuenta aquí).
    const embedMs = embedDone - e0;

    // 5. Puntuación por (cúpula, consulta).
    const perQuery: RagHit[][][] = req.queries.map(() => []);
    // SE-485 R4: identificadores de cada consulta y los que aparecen literales en algún documento servible.
    const queryIds = req.queries.map(queryIdentifiers);
    const foundIds = req.queries.map(() => new Set<string>());
    for (const p of ready) {
      const vecs = queryVecs.get(p.store.manifest.generation);
      const mode: RagMode = vecs ? opt.mode : 'bm25';
      // SE-419: los hits de ficheros se filtran con la política ACTUAL del documento (y los de
      // documentos ya borrados se descartan): se piden más candidatos para no quedarse corto.
      const files = this.filesStore(p.d);
      const principal = principals.get(p.d.name);
      const readable = new Map<string, boolean>();
      const canSee = (documentId: string): boolean => {
        let ok = readable.get(documentId);
        if (ok === undefined) {
          try { ok = canRead(principal, files!.get(documentId), p.d.confidentiality); } catch { ok = false; }
          readable.set(documentId, ok);
        }
        return ok;
      };
      // SE-481 R3: cada hit de nota se revalida con su estado ACTUAL en disco (borrada, fuera de
      // nivel o en cuarentena ⇒ fuera), sin esperar al siguiente sync. `includeStale` no influye.
      const servable = new Map<string, boolean>();
      const noteOk = (relPath: string): boolean => {
        let ok = servable.get(relPath);
        if (ok === undefined) {
          ok = isMarkdown(relPath) && fileServable(path.join(p.d.path, relPath), relPath, p.d.confidentiality);
          servable.set(relPath, ok);
        }
        return ok;
      };
      let filtered = 0;
      let revalidated = 0;
      req.queries.forEach((query, qi) => {
        for (const id of queryIds[qi]) {
          if (foundIds[qi].has(id)) continue;
          const present = p.store.chunks.some(c =>
            (req.includeStale || !excludedReason(c.meta, p.cfg))
            && (!req.pathPrefix || c.path.startsWith(req.pathPrefix))
            && containsIdentifier(c.text, id)
            && (c.source?.documentId ? canSee(c.source.documentId) : noteOk(c.path)));
          if (present) foundIds[qi].add(id);
        }
        let hits: StoreHit[] = searchStore({
          store: p.store, query, queryVec: vecs?.[qi], mode, k: Math.min(opt.k * 4, 200), cfg: p.cfg,
          pathPrefix: req.pathPrefix, includeStale: req.includeStale,
        });
        const before = hits.length;
        hits = hits.filter(h => h.source?.documentId || noteOk(h.path));
        revalidated += before - hits.length;
        if (files) {
          const n = hits.length;
          hits = hits.filter(h => !h.source?.documentId || canSee(h.source.documentId));
          filtered += n - hits.length;
        }
        hits = hits.slice(0, opt.k);
        perQuery[qi].push(hits.map(h => ({
          ...h, dome: p.d.name, confidentiality: p.d.confidentiality,
          ...(queryIds[qi].length ? { exactMatch: queryIds[qi].some(id => containsIdentifier(h.text, id)) } : {}),
        })));
      });
      if (filtered) outcomes.set(p.d.name, { ...outcomes.get(p.d.name)!, filtered });
      if (revalidated) outcomes.set(p.d.name, { ...outcomes.get(p.d.name)!, degradation: { revalidated } });
    }

    // 6. Fusión entre cúpulas (SE-411 G1): por coseno global si todas comparten
    //    contrato y hay vectores de consulta; si no, por rango con desempate determinista.
    const gens = new Set(ready.map(p => p.store.manifest.generation));
    const fusion: 'cosine' | 'rank' = ready.length > 1 && gens.size === 1 && queryVecs.size === 1 ? 'cosine' : 'rank';
    const results = req.queries.map((query, qi) => {
      const fused = fusion === 'cosine' ? fuseByCosine(perQuery[qi], opt.k) : fuseAcross(perQuery[qi], opt.k);
      // El documento con el identificador literal va primero; el resto conserva su orden.
      const ordered = queryIds[qi].length ? [...fused].sort((a, b) => Number(!!b.exactMatch) - Number(!!a.exactMatch)) : fused;
      const missing = queryIds[qi].some(id => !foundIds[qi].has(id));
      return { query, hits: applyCharBudget(ordered, opt.maxChars), ...(missing ? { warnings: [IDENTIFIER_NOT_FOUND] } : {}) };
    });
    const merged = req.queries.length > 1
      ? applyCharBudget(fuseAcross(results.map(r => r.hits), opt.k), opt.maxChars)
      : undefined;

    return {
      results,
      ...(merged ? { merged } : {}),
      domes: targets.map(d => outcomes.get(d.name)!),
      timings: { totalMs: Date.now() - t0, embedMs, syncMs },
      ...(ready.length > 1 ? { fusion } : {}),
    };
  }

  // ── Evaluación ───────────────────────────────────────────────────────

  async evaluate(name: string, queries: EvalQueryInput[], opts: { generation?: string; mode?: RagMode } = {}): Promise<RagEvalResult> {
    await sodiumReady();
    const d = this.dome(name);
    const cfg = this.config(d);
    const generation = opts.generation ?? readActive(this.home, name).active;
    if (!generation) throw new RagError('NOT_INDEXED', `${name} sin generación activa`);
    const store = this.loadStore(name, generation);
    const mode = opts.mode ?? 'hybrid';
    const emb = this.embedder({ ...cfg, model: store.manifest.contract.model });
    if (mode !== 'bm25') {
      const live = await this.liveGeneration(emb, store.manifest.contract);
      if (live.generation !== generation) {
        throw new RagError('CONTRACT_MISMATCH', `el embedder vivo no corresponde a la generación ${generation}`);
      }
    }
    let recall5 = 0, recall10 = 0, mrr = 0;
    const times: number[] = [];
    const failed: RagEvalResult['failed'] = [];
    for (const q of queries) {
      const t = Date.now();
      const vecs = mode !== 'bm25' ? await emb.embed([q.query], 'query') : undefined;
      const hits = searchStore({ store, query: q.query, queryVec: vecs?.[0], mode, k: 20, cfg });
      times.push(Date.now() - t);
      const docs = [...new Set(hits.map(h => h.path))];
      const rel = new Set(q.relevantPaths);
      const at = (k: number) => docs.slice(0, k).filter(p => rel.has(p)).length / (rel.size || 1);
      recall5 += at(5);
      recall10 += at(10);
      const first = docs.findIndex(p => rel.has(p));
      mrr += first >= 0 ? 1 / (first + 1) : 0;
      if (first < 0 || first >= 10) failed.push({ query: q.query, relevant: q.relevantPaths, retrieved: docs.slice(0, 5) });
    }
    const n = queries.length || 1;
    return {
      n: queries.length, mode, generation,
      recallAt5: recall5 / n, recallAt10: recall10 / n, mrr: mrr / n,
      p50Ms: percentile(times, 50), p95Ms: percentile(times, 95), failed,
    };
  }

  // ── Estado y SLO (P7) ────────────────────────────────────────────────

  async status(names?: string[]): Promise<DomeStatusReport[]> {
    await sodiumReady();
    const list = names?.length ? names.map(n => this.dome(n)) : this.o.domes();
    const out: DomeStatusReport[] = [];
    for (const d of list) {
      const cfg = this.config(d);
      const pointer = readActive(this.home, d.name);
      const pending = await this.indexer(d, cfg).pending();
      const manifest = pointer.active ? FlatVectorStore.readManifest(path.join(domeDir(this.home, d.name), pointer.active)) : undefined;
      let currentDigest: string | undefined;
      let digestMatch = true;
      if (cfg.enabled && manifest) {
        try {
          const live = await this.liveGeneration(this.embedder({ ...cfg, model: manifest.contract.model }), manifest.contract);
          currentDigest = live.digest;
          digestMatch = live.digest === manifest.contract.modelDigest;
        } catch {
          // proveedor caído: no es deriva de modelo; se refleja en búsqueda como degraded
        }
      }
      const slo = sloStatus({ enabled: cfg.enabled, hasGeneration: Boolean(manifest), indexed: Boolean(pointer.active || pointer.shadow || pointer.previous), totalDocs: pending.totalDocs, pendingDocs: pending.pendingDocs, lagHours: pending.lagHours, digestMatch });
      out.push({
        name: d.name, enabled: cfg.enabled, confidentiality: d.confidentiality,
        active: pointer.active, shadow: pointer.shadow, previous: pointer.previous,
        contract: manifest?.contract, currentDigest, digestMatch,
        chunks: manifest?.chunkCount ?? 0,
        totalDocs: pending.totalDocs, pendingDocs: pending.pendingDocs,
        staleRatio: slo.staleRatio, lagHours: Number(pending.lagHours.toFixed(2)),
        generationAgeHours: manifest ? Number(((Date.now() - Date.parse(manifest.createdAt)) / 3.6e6).toFixed(2)) : undefined,
        memoryBytes: manifest ? manifest.chunkCount * manifest.contract.dims * 4 : 0,
        slo: { ok: slo.ok, alerts: slo.alerts },
      });
    }
    return out;
  }

  /** Deja una alerta operativa en rag.jsonl (la lee el morning brief / success_checks). */
  recordAlert(kind: string, detail: unknown): void {
    // Sin repetir la misma alerta en el mismo día: una cron frecuente no debe crecer el log sin límite.
    const key = JSON.stringify({ kind, detail });
    const today = new Date().toISOString().slice(0, 10);
    try {
      const lines = fs.readFileSync(path.join(this.home, 'logs', 'rag.jsonl'), 'utf-8').trim().split('\n').slice(-50);
      for (const l of lines) {
        const e = JSON.parse(l) as { ts?: string; event?: string; kind?: string; detail?: unknown };
        if (e.event === 'alert' && e.ts?.startsWith(today) && JSON.stringify({ kind: e.kind, detail: e.detail }) === key) return;
      }
    } catch { /* sin log previo o línea ilegible: se registra */ }
    logEvent(this.home, { event: 'alert', kind, detail });
  }

  /** Comprueba que el home es seguro antes de operar (AC11). */
  ensureHome(): void {
    ensureSafeHome(this.home);
  }
}
