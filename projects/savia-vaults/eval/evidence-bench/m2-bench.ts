// SE-489 M2 — medición del reranker: M0 frente a M2 con cada modelo candidato y N = 20, 50.
// Mide calidad (evaluateRoute, pareado con M0, IC 95 % por bootstrap) y la latencia del reranker
// aparte (takeRerankTimings). Los modelos se pasan como `nombre=directorio`; los digests se
// calculan aquí y se fijan por entorno, igual que en ejecución.
//
// Uso (SAVIA_RAG_HOME temporal bajo /tmp, nunca la de producción):
//   SAVIA_RAG_HOME=/tmp/x/rag npx tsx eval/evidence-bench/m2-bench.ts --domes-file /tmp/x/domes.json \
//     --bench eval/evidence-bench --legacy eval/rag-savia-docs.json \
//     --model bge=/models/bge --model mmarco=/models/mmarco --out /tmp/x/m2.json [--limit 40 | --per-category 10]
//     [--sets dev,test,legacy36] [--budget-tokens 60000]
// --budget-tokens declara maxInputTokens: el defecto del contrato (8000) no cubre 50 pasajes, y la ruta
// cae a M0 por presupuesto (se cuenta en `fallbacks`). Por defecto aquí es 60000 para medir al reranker.
// --per-category N toma los N primeros casos de cada categoría en el orden fijo del banco (muestra
// estratificada y reproducible); --limit N toma los N primeros sin estratificar.
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { RerankTiming } from '../../src/retrieval/routes/m2-rerank.js';
import type { EvidenceCase } from '../../src/retrieval/evidence-eval.js';

export interface LatencySummary { calls: number; failed: number; p50Ms: number | null; p95Ms: number | null; meanMsPerPair: number | null }

/** Latencia del reranker: percentiles y coste por par solo con las llamadas que terminaron bien. */
export function latencySummary(timings: RerankTiming[]): LatencySummary {
  const okRuns = timings.filter(t => t.ok);
  const ms = okRuns.map(t => t.scoreMs).sort((a, b) => a - b);
  const q = (p: number): number | null => (ms.length ? ms[Math.min(ms.length - 1, Math.ceil(p * ms.length) - 1)] : null);
  const pairs = okRuns.reduce((s, t) => s + t.pairs, 0);
  return {
    calls: timings.length, failed: timings.length - okRuns.length, p50Ms: q(0.5), p95Ms: q(0.95),
    meanMsPerPair: pairs ? ms.reduce((s, x) => s + x, 0) / pairs : null,
  };
}

/** N primeros casos de cada categoría, en el orden de entrada (reproducible). */
export function stratify<T extends { category: string }>(cases: T[], perCategory: number): T[] {
  const seen = new Map<string, number>();
  return cases.filter(c => {
    const n = seen.get(c.category) ?? 0;
    seen.set(c.category, n + 1);
    return n < perCategory;
  });
}

function sha256(file: string): string {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const opt = (k: string): string | undefined => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined; };
  const multi = (k: string): string[] => args.flatMap((a, i) => (a === k ? [args[i + 1]] : []));
  const domesFile = opt('--domes-file'); const benchDir = opt('--bench'); const out = opt('--out');
  const models = multi('--model').map(m => { const [name, dir] = m.split('='); return { name, dir: path.resolve(dir) }; });
  if (!domesFile || !benchDir || !out || !models.length) throw new Error('uso: --domes-file F --bench D --model nombre=dir [...] --out F [--legacy F] [--limit N]');
  const ragHome = process.env.SAVIA_RAG_HOME;
  const tmp = fs.realpathSync(os.tmpdir());
  if (!ragHome || !path.resolve(ragHome).startsWith(tmp + path.sep)) throw new Error(`SAVIA_RAG_HOME debe estar bajo ${tmp} (temporal)`);

  const { DomeRegistry } = await import('../../src/registry/domes.js');
  const { RagService } = await import('../../src/rag/service.js');
  const { evaluateRoute, compareReports, loadBench, legacyToCases } = await import('../../src/retrieval/evidence-eval.js');
  const { takeRerankTimings, takeRerankFallbacks } = await import('../../src/retrieval/routes/m2-rerank.js');
  const { loadOnnxCrossEncoder, resolveRerankConfig } = await import('../../src/retrieval/rerank/cross-encoder.js');

  const denied = new Set<string>();
  const reg = new DomeRegistry(path.resolve(domesFile)); reg.load();
  const svc = new RagService({
    domes: () => reg.listActive().map(d => ({ name: d.name, path: d.path, confidentiality: d.confidentiality, rag: d.rag, files: d.files })),
    background: false,
    authorize: async (dome: string) => { if (denied.has(dome)) throw new Error('acceso denegado'); return undefined; },
  });
  const deny = (names: string[]) => { denied.clear(); for (const n of names) denied.add(n); };

  const limit = opt('--limit') ? Number(opt('--limit')) : undefined;
  const perCat = opt('--per-category') ? Number(opt('--per-category')) : undefined;
  if (limit !== undefined && perCat !== undefined) throw new Error('--limit y --per-category son excluyentes');
  const take = (xs: EvidenceCase[]): EvidenceCase[] => {
    if (perCat) return stratify(xs, perCat);
    return limit ? xs.slice(0, limit) : xs;
  };
  const sets: Record<string, EvidenceCase[]> = {
    dev: take(loadBench(path.resolve(benchDir), { split: 'dev' })),
    test: take(loadBench(path.resolve(benchDir), { split: 'test' })),
  };
  const only = opt('--sets')?.split(',');
  if (only) for (const k of Object.keys(sets)) if (!only.includes(k)) delete sets[k];
  if (opt('--legacy') && (!only || only.includes('legacy36'))) sets.legacy36 = take(legacyToCases(JSON.parse(fs.readFileSync(path.resolve(opt('--legacy')!), 'utf-8'))));

  const budgetTokens = Number(opt('--budget-tokens') ?? 60000);
  if (!Number.isInteger(budgetTokens) || budgetTokens < 1) throw new Error('--budget-tokens: entero ≥ 1');
  const boot = { iterations: 2000, seed: 0 };
  const base = { mode: 'hybrid' as const, k: 20, seed: 0, iterations: boot.iterations, deny };
  const result: Record<string, unknown> = { generatedAt: new Date().toISOString(), k: base.k, models: {}, sets: {} };

  // Preflight: cada modelo se carga con su digest antes de medir; si no carga, no hay medición válida.
  const digests: Record<string, { model: string; tokenizer: string }> = {};
  const pin = (m: { name: string; dir: string }, topN?: number): void => {
    process.env.SAVIA_RERANK_MODEL_DIR = m.dir;
    process.env.SAVIA_RERANK_MODEL_SHA256 = digests[m.name].model;
    process.env.SAVIA_RERANK_TOKENIZER_SHA256 = digests[m.name].tokenizer;
    if (topN) process.env.SAVIA_RERANK_TOPN = String(topN);
    process.env.SAVIA_RERANK_MAX_MS = '120000'; // se mide la calidad sin corte; la latencia va aparte
  };
  for (const m of models) {
    digests[m.name] = { model: sha256(path.join(m.dir, 'model.onnx')), tokenizer: sha256(path.join(m.dir, 'tokenizer.json')) };
    pin(m);
    const r = resolveRerankConfig();
    if (!r.ok) throw new Error(`${m.name}: ${r.reason}`);
    await loadOnnxCrossEncoder(r.config);
  }
  result.models = digests;

  for (const [setName, cases] of Object.entries(sets)) {
    const domes = cases[0]?.domes ?? ['savia-docs'];
    const m0 = await evaluateRoute(svc, cases, { ...base, route: 'M0', domes });
    const configs: Record<string, unknown> = {};
    for (const m of models) {
      for (const topN of [20, 50]) {
        pin(m, topN);
        takeRerankTimings(); takeRerankFallbacks();
        const t0 = Date.now();
        const rep = await evaluateRoute(svc, cases, { ...base, route: 'M2', domes, budget: { maxLatencyMs: 120000, maxInputTokens: budgetTokens } });
        const lat = latencySummary(takeRerankTimings());
        const fallbacks: Record<string, number> = {};
        for (const why of takeRerankFallbacks()) fallbacks[why] = (fallbacks[why] ?? 0) + 1;
        const label = `${m.name}-N${topN}`;
        configs[label] = { report: rep, vsM0: compareReports(rep, m0, boot), rerankerLatency: lat, fallbacks, wallMs: Date.now() - t0 };
        console.log(`${setName} ${label} n=${cases.length} errores=${rep.errors} viol=${rep.violations} rerank p50=${lat.p50Ms}ms p95=${lat.p95Ms}ms fallos=${lat.failed} fallbacks=${JSON.stringify(fallbacks)}`);
      }
    }
    (result.sets as Record<string, unknown>)[setName] = { n: cases.length, M0: m0, configs };
    fs.writeFileSync(out, JSON.stringify(result));
  }
  console.log(`escrito ${out}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(e => { console.error(`Error: ${e instanceof Error ? e.message : String(e)}`); process.exit(1); });
}
