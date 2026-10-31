// SE-489 M3/M4 — medición sobre el banco de evidencia y el de regresión (36).
// Cada ruta corre en su propio proceso (RSS pico no contaminado por otra ruta) y escribe un
// RouteReport; `compare` empareja por pregunta contra la línea base y aplica la regla de AC-6.
// En M4 cuenta además los tokens reales que devuelve Ollama (prompt_eval_count / eval_count).
//
// Uso (SAVIA_RAG_HOME temporal, nunca la de producción):
//   SAVIA_RAG_HOME=/tmp/x/rag npx tsx scripts/bench-m34.ts run --domes-file /tmp/x/domes.json \
//     --route M4 --bench eval/evidence-bench --budget '{"maxModelCalls":4,"maxInputTokens":8000}' --out m4.json
//   … run --route M0 --legacy eval/rag-savia-docs.json --dome savia-docs --out m0-36.json
//   npx tsx scripts/bench-m34.ts compare --base m0.json --route m4.json [--metric m] [--bench dir --split test] [--out cmp.json]
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { DomeRegistry } from '../src/registry/domes.js';
import { RagService, type EvalQueryInput } from '../src/rag/service.js';
import { registerRoute, unregisterRoute } from '../src/retrieval/route.js';
import '../src/retrieval/routes/index.js';
import { OllamaNavigator, createM4Route } from '../src/retrieval/routes/m4-llm-nav.js';
import { CATEGORIES, compareReports, evaluateRoute, legacyToCases, loadBench, type RouteReport } from '../src/retrieval/evidence-eval.js';

const arg = (k: string): string | undefined => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : undefined; };
const need = (k: string): string => { const v = arg(k); if (!v) throw new Error(`falta ${k}`); return v; };

async function run(): Promise<void> {
  const ragHome = process.env.SAVIA_RAG_HOME;
  if (!ragHome) throw new Error('SAVIA_RAG_HOME obligatorio (temporal, nunca la de producción)');
  const tmp = fs.realpathSync(os.tmpdir());
  if (!path.resolve(ragHome).startsWith(tmp + path.sep)) throw new Error(`SAVIA_RAG_HOME debe estar bajo ${tmp}`);
  const route = need('--route');
  const reg = new DomeRegistry(path.resolve(need('--domes-file')));
  reg.load();
  const denied = new Set<string>();
  const svc = new RagService({
    domes: () => reg.listActive().map(d => ({ name: d.name, path: d.path, confidentiality: d.confidentiality, rag: d.rag, files: d.files })),
    background: false,
    authorize: async (dome: string) => { if (denied.has(dome)) throw new Error('acceso denegado'); return undefined; },
  });
  const bench = arg('--bench');
  const legacy = arg('--legacy');
  const split = arg('--split') as 'dev' | 'test' | undefined;
  const cases = bench
    ? loadBench(path.resolve(bench), split ? { split } : {})
    : legacyToCases(JSON.parse(fs.readFileSync(path.resolve(need('--legacy')), 'utf-8')) as EvalQueryInput[]);
  if (!bench && !legacy) throw new Error('--bench o --legacy');
  let nav: OllamaNavigator | undefined;
  if (route === 'M4') {
    nav = new OllamaNavigator(process.env.SAVIA_M4_MODEL || 'qwen2.5:3b', process.env.SAVIA_OLLAMA_URL || 'http://127.0.0.1:11434');
    unregisterRoute('M4');
    registerRoute(createM4Route({ navigator: nav }));
  }
  const budget = arg('--budget') ? JSON.parse(arg('--budget')!) : undefined;
  const t0 = Date.now();
  const report = await evaluateRoute(svc, cases, {
    route, mode: (arg('--mode') ?? 'hybrid') as 'hybrid', k: Number(arg('--k') ?? 20), seed: 0, iterations: 2000,
    ...(budget ? { budget } : {}), ...(legacy ? { domes: [need('--dome')] } : {}),
    deny: (names) => { denied.clear(); for (const n of names) denied.add(n); },
  });
  const out = { report, wallMs: Date.now() - t0, ...(nav ? { model: nav.model, llm: nav.usage } : {}) };
  fs.writeFileSync(need('--out'), JSON.stringify(out, null, 1));
  console.log(`${route}: n=${report.n} errores=${report.errors} violaciones=${report.violations} p50=${report.latency.p50Ms} p95=${report.latency.p95Ms} RSS=${report.rssPeakMb}MB llamadas=${report.cost.modelCalls}${nav ? ` llm=${JSON.stringify(nav.usage)}` : ''}`);
}

/** AC-6: no inferioridad en A/B (IC inferior ≥ −1 pp) y ganancia en C/D/E con IC que excluye 0. */
function compare(): void {
  const load = (f: string) => JSON.parse(fs.readFileSync(f, 'utf-8')) as { report: RouteReport };
  let base = load(need('--base')).report;
  let r = load(need('--route')).report;
  const split = arg('--split');
  if (split) {
    // Solo los casos del split (dev/test) del banco: misma comparación pareada sobre ese subconjunto.
    const ids = new Set(loadBench(path.resolve(need('--bench')), { split: split as 'dev' | 'test' }).map(c => c.id));
    const only = (x: RouteReport): RouteReport => ({ ...x, cases: x.cases.filter(c => ids.has(c.id)), byCategory: Object.fromEntries(CATEGORIES.map(c => [c, x.byCategory[c]])) });
    base = only(base); r = only(r);
  }
  const cmp = compareReports(r, base, { iterations: 2000, seed: 0 });
  const metric = (arg('--metric') ?? 'evidenceRecall') as 'evidenceRecall';
  const ab = (['A', 'B'] as const).map(c => cmp.byCategory[c]?.[metric]).filter(Boolean);
  const nonInferior = ab.every(d => d!.lo >= -0.01);
  const gains = (['C', 'D', 'E'] as const).filter(c => (cmp.byCategory[c]?.[metric]?.lo ?? 0) > 0);
  const out = { metric, comparison: cmp, ac6: { nonInferiorAB: nonInferior, gainsCDE: gains, pass: nonInferior && gains.length > 0 } };
  if (arg('--out')) fs.writeFileSync(arg('--out')!, JSON.stringify(out, null, 1));
  const f = (d?: { diff: number; lo: number; hi: number; n: number }) => (d ? `${(d.diff * 100).toFixed(1)} [${(d.lo * 100).toFixed(1)}, ${(d.hi * 100).toFixed(1)}] n=${d.n}` : '-');
  console.log(`${r.route} − ${base.route} (${metric}, pp${split ? `, split ${split}` : ''})`);
  for (const c of CATEGORIES) console.log(`  ${c}: ${f(cmp.byCategory[c]?.[metric])}`);
  console.log(`  global: ${f(cmp.overall[metric])}`);
  console.log(`  AC-6: no-inferioridad A/B=${nonInferior} ganancia C/D/E=${gains.join(',') || 'ninguna'} → ${out.ac6.pass ? 'PASA' : 'NO PASA'}`);
}

const cmd = process.argv[2];
(cmd === 'run' ? run() : cmd === 'compare' ? Promise.resolve(compare()) : Promise.reject(new Error('uso: run | compare')))
  .catch(e => { console.error(`Error: ${e instanceof Error ? e.message : String(e)}`); process.exit(1); });
