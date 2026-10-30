// SE-410/411 — CLI de Savia RAG. Módulo separado para que `savia-vaults rag …`
// no cargue el servidor MCP/A2A ni la capa de conocimiento (arranque en frío).
import { Command } from 'commander';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { DomeRegistry } from '../registry/domes.js';
import { RagService, type EvalQueryInput } from '../rag/service.js';
import { RagError, RAG_LIMITS, type RagMode } from '../rag/types.js';
import { formatRagResponse } from '../rag/format.js';
import { getRoute } from '../retrieval/route.js';
import '../retrieval/routes/index.js';
import { compareReports, evaluateRoute, legacyToCases, loadBench, type EvidenceCase, type RouteReport } from '../retrieval/evidence-eval.js';

const program = new Command();
program.name('savia-vaults');

function ragService(domesFile: string, denied?: ReadonlySet<string>): RagService {
  const reg = new DomeRegistry(path.resolve(domesFile));
  reg.load();
  return new RagService({
    domes: () => reg.listActive().map(d => ({ name: d.name, path: d.path, confidentiality: d.confidentiality, rag: d.rag, files: d.files })),
    background: false,
    // SE-489: en `rag eval`, los casos de categoría F simulan cúpulas denegadas por el plano de control.
    ...(denied ? { authorize: async (dome: string) => { if (denied.has(dome)) throw new Error('acceso denegado'); return undefined; } } : {}),
  });
}

function ragFail(e: unknown): never {
  const msg = e instanceof Error ? e.message : String(e);
  console.error(`Error: ${msg}`);
  process.exit(e instanceof RagError && e.code === 'LOCKED' ? 3 : 1);
}

const ragCmd = program.command('rag').description('SE-410 Savia RAG: búsqueda híbrida paralela y ciclo de vida de embeddings');
const domesOpt = ['--domes-file <file>', 'Registry de cúpulas', 'savia-vaults.domes.json'] as const;

ragCmd.command('search <queries...>').description('Busca una o varias consultas en paralelo sobre una o varias cúpulas')
  .option(...domesOpt).option('--domes <list>', 'a,b o all', 'all').option('--k <n>', 'hits por consulta', '8')
  .option('--mode <mode>', 'hybrid|dense|bm25', 'hybrid').option('--concurrency <n>', 'cúpulas en paralelo', '4')
  .option('--timeout <ms>', 'timeout por cúpula', '8000').option('--path-prefix <p>').option('--include-stale', 'incluir deprecados', false)
  .option('--max-chars <n>', 'tamaño máximo de la respuesta JSON', String(RAG_LIMITS.defaultMaxChars)).option('--json', 'salida JSON', false)
  .option('--fields <perfil>', 'lean|full (con --json)', 'lean')
  .action(async (queries: string[], opts) => {
    try {
      const svc = ragService(opts.domesFile);
      const res = await svc.search({
        queries, domes: opts.domes === 'all' ? '*' : String(opts.domes).split(',').map((s: string) => s.trim()).filter(Boolean),
        k: parseInt(opts.k, 10), mode: opts.mode as RagMode, concurrency: parseInt(opts.concurrency, 10),
        timeoutMs: parseInt(opts.timeout, 10), pathPrefix: opts.pathPrefix, includeStale: opts.includeStale, maxChars: parseInt(opts.maxChars, 10),
      });
      if (opts.json) { console.log(formatRagResponse(res, { fields: opts.fields === 'full' ? 'full' : 'lean', maxChars: parseInt(opts.maxChars, 10) })); return; }
      for (const d of res.domes) console.log(`[${d.name}] ${d.status}${d.generation ? ` gen=${d.generation}` : ''}${d.detail ? ` — ${d.detail}` : ''}`);
      for (const r of res.results) {
        console.log(`\n== ${r.query}`);
        r.hits.forEach((h, i) => {
          console.log(`${i + 1}. ${h.dome}:${h.path} (${h.score.toFixed(4)}) ${h.heading}${h.freshness.supersededBy ? ` [superseded_by ${h.freshness.supersededBy}]` : ''}`);
          console.log(`   ${h.text.replace(/\s+/g, ' ').slice(0, 200)}`);
        });
      }
      console.log(`\n${res.timings.totalMs} ms (embed ${res.timings.embedMs} ms, sync ${res.timings.syncMs} ms)`);
    } catch (e) { ragFail(e); }
  });

ragCmd.command('sync').description('Sincroniza el índice (incremental por hash). Cron: --all [--rebuild] --check')
  .option(...domesOpt).option('--dome <name>').option('--all', 'todas las cúpulas con rag.enabled', false)
  .option('--rebuild', 're-embebe todo (checkpoint semanal)', false).option('--json', 'salida JSON', false)
  .option('--check', 'tras sincronizar, sale 2 si algún SLO falla (P7)', false)
  .action(async (opts) => {
    try {
      const svc = ragService(opts.domesFile);
      const all = opts.all ? await svc.status() : [];
      const names = opts.all ? all.filter(s => s.enabled).map(s => s.name) : opts.dome ? [opts.dome] : [];
      // Cúpulas con índice pero rag.enabled=false: el cron las ignoraba y envejecían sin aviso.
      const orphans = all.filter(s => !s.enabled && (s.active || s.shadow || s.previous)).map(s => s.name);
      const alertExit = opts.check ? 2 : 1;
      if (orphans.length) {
        const msg = `--all ignora cúpulas con índice y rag.enabled=false: ${orphans.join(', ')}; sus índices envejecen sin sincronizar`;
        console.error(`ALERTA: ${msg}`);
        svc.recordAlert('sync_disabled_indexed', { domes: orphans });
      }
      if (!names.length) {
        if (opts.all) {
          // Registro sin cúpulas con rag.enabled: avería de configuración, no un "nada que hacer".
          console.error('ALERTA: --all no encontró ninguna cúpula con rag.enabled=true en el registro; no se indexa nada');
          svc.recordAlert('sync_no_enabled_domes', { registered: all.map(s => s.name) });
          process.exit(alertExit);
        }
        throw new RagError('INVALID_INPUT', 'indica --dome <name> o --all');
      }
      const reports = [];
      let failed = false;
      for (const n of names) {
        try {
          reports.push(await svc.sync(n, { rebuild: opts.rebuild }));
        } catch (e) {
          // Con --all, un lock ajeno no es fallo: otro proceso ya está sincronizando esa cúpula.
          if (e instanceof RagError && e.code === 'LOCKED' && opts.all) { console.log(`[${n}] sync en curso en otro proceso; se omite`); continue; }
          if (!opts.all) throw e;
          failed = true;
          console.error(`[${n}] Error: ${e instanceof Error ? e.message : String(e)}`);
        }
      }
      if (opts.json) console.log(JSON.stringify(reports, null, 2));
      else for (const r of reports) {
        console.log(`[${r.dome}] gen=${r.generation}${r.promoted ? ' (activa)' : r.shadow ? ' (sombra)' : ''} docs +${r.docs.added} ~${r.docs.updated} -${r.docs.deleted} =${r.docs.unchanged} omitidos ${r.docs.skipped} cuarentena ${r.docs.quarantined ?? 0} chunks ${r.chunks.total} (embebidos ${r.chunks.embedded}, reutilizados ${r.chunks.reused}) ${r.durationMs} ms`);
        if (r.gate) console.log(`   gate: ${r.gate.promote ? 'promovida' : 'no promovida'} — ${r.gate.reason}`);
      }
      if (failed) process.exit(1);
      if (opts.check) {
        const st = await svc.status([...names, ...orphans]);
        for (const s of st) for (const a of s.slo.alerts) {
          console.error(`[${s.name}] ALERTA: ${a}`);
        }
        if (st.some(s => !s.slo.ok)) {
          svc.recordAlert('slo', st.filter(s => !s.slo.ok).map(s => ({ dome: s.name, alerts: s.slo.alerts })));
          process.exit(2);
        }
      }
      if (orphans.length) process.exit(alertExit);
    } catch (e) { ragFail(e); }
  });

ragCmd.command('status').description('Estado del índice y SLO por cúpula')
  .option(...domesOpt).option('--dome <name>').option('--json', 'salida JSON', false)
  .option('--check', 'sale 2 si algún SLO falla', false)
  .action(async (opts) => {
    try {
      const svc = ragService(opts.domesFile);
      const st = await svc.status(opts.dome ? [opts.dome] : undefined);
      if (opts.json) console.log(JSON.stringify(st, null, 2));
      else for (const s of st) {
        console.log(`[${s.name}] ${s.enabled ? 'rag on' : 'rag off'} ${s.confidentiality} activa=${s.active ?? '-'} sombra=${s.shadow ?? '-'} anterior=${s.previous ?? '-'}`);
        if (s.enabled) {
          console.log(`   modelo=${s.contract?.model ?? '-'} digest ${s.digestMatch ? 'ok' : 'DISTINTO'} chunks=${s.chunks} docs=${s.totalDocs} pendientes=${s.pendingDocs} staleRatio=${s.staleRatio.toFixed(2)} lag=${s.lagHours}h mem=${(s.memoryBytes / 1048576).toFixed(1)}MB`);
        }
        for (const a of s.slo.alerts) console.log(`   ALERTA: ${a}`);
      }
      if (opts.check && st.some(s => !s.slo.ok)) {
        for (const s of st) for (const a of s.slo.alerts) console.error(`[${s.name}] ALERTA: ${a}`);
        svc.recordAlert('slo', st.filter(s => !s.slo.ok).map(s => ({ dome: s.name, alerts: s.slo.alerts })));
        process.exit(2);
      }
    } catch (e) { ragFail(e); }
  });

ragCmd.command('eval').description('Evalúa recall@5/@10, MRR y latencia; con --route/--bench, métricas de evidencia por ruta (SE-489)')
  .option(...domesOpt).requiredOption('--dome <name>').option('--queries <file>', 'banco JSON (def. rag.evalSet de la cúpula)')
  .option('--generation <id>').option('--mode <mode>', 'hybrid|dense|bm25|all', 'all').option('--json', 'salida JSON', false)
  .option('--route <ids>', 'SE-489: rutas a evaluar, separadas por comas (M0..M7)')
  .option('--bench <dir>', 'SE-489: banco de evidencia (directorio con *.json/*.jsonl)')
  .option('--baseline <id>', 'SE-489: ruta de referencia para la comparación pareada (def. la primera)')
  .option('--split <split>', 'SE-489: dev|test').option('--seed <n>', 'SE-489: semilla de rutas y bootstrap', '0')
  .option('--iterations <n>', 'SE-489: remuestreos del bootstrap', '2000').option('--k <n>', 'SE-489: hits por consulta', '20')
  .option('--budget <json>', 'SE-489: presupuesto declarado, p. ej. {"maxModelCalls":8}')
  .action(async (opts) => {
    try {
      const denied = new Set<string>();
      const svc = ragService(opts.domesFile, denied);
      const reg = new DomeRegistry(path.resolve(opts.domesFile)); reg.load();
      const dome = reg.get(opts.dome);
      if (!dome) throw new RagError('UNKNOWN_DOME', opts.dome);
      const routed = opts.route !== undefined || opts.bench !== undefined;
      if (!routed && (opts.baseline || opts.split || opts.budget)) {
        throw new RagError('INVALID_INPUT', '--baseline, --split y --budget solo valen con --route o --bench');
      }
      if (routed) {
        await routeEval(svc, opts, dome, denied);
        return;
      }
      const file = opts.queries ? path.resolve(opts.queries) : dome.rag?.evalSet ? path.resolve(dome.path, dome.rag.evalSet) : '';
      if (!file || !fs.existsSync(file)) throw new RagError('INVALID_INPUT', 'banco de eval no encontrado (--queries o rag.evalSet)');
      const queries = JSON.parse(fs.readFileSync(file, 'utf-8')) as EvalQueryInput[];
      const modes: RagMode[] = opts.mode === 'all' ? ['bm25', 'dense', 'hybrid'] : [opts.mode];
      const out = [];
      for (const m of modes) out.push(await svc.evaluate(opts.dome, queries, { generation: opts.generation, mode: m }));
      if (opts.json) { console.log(JSON.stringify(out, null, 2)); return; }
      for (const r of out) {
        console.log(`[${opts.dome}] ${r.mode.padEnd(6)} n=${r.n} recall@5=${r.recallAt5.toFixed(3)} recall@10=${r.recallAt10.toFixed(3)} MRR=${r.mrr.toFixed(3)} p50=${r.p50Ms}ms p95=${r.p95Ms}ms fallos=${r.failed.length}`);
      }
    } catch (e) { ragFail(e); }
  });

/** SE-489 R2: rutas sobre el banco de evidencia (o el de regresión), con comparación pareada. */
async function routeEval(svc: RagService, opts: Record<string, string | boolean | undefined>, dome: { path: string; rag?: { evalSet?: string } }, denied: Set<string>): Promise<void> {
  const int = (v: unknown, name: string) => {
    const n = Number(v);
    if (!Number.isSafeInteger(n) || n < 0) throw new RagError('INVALID_INPUT', `--${name}: entero ≥ 0`);
    return n;
  };
  if (opts.generation) throw new RagError('INVALID_INPUT', '--generation no se combina con --route/--bench (las rutas usan la generación activa)');
  if (opts.split !== undefined && opts.split !== 'dev' && opts.split !== 'test') throw new RagError('INVALID_INPUT', '--split: dev|test');
  if (opts.split !== undefined && !opts.bench) throw new RagError('INVALID_INPUT', '--split solo vale con --bench (el banco de regresión no tiene splits)');
  const routes = String(opts.route ?? 'M0').split(',').map(s => s.trim()).filter(Boolean);
  if (!routes.length) throw new RagError('INVALID_INPUT', '--route: al menos una ruta');
  for (const r of routes) getRoute(r);
  const baseline = String(opts.baseline ?? routes[0]);
  getRoute(baseline);
  let cases: EvidenceCase[];
  if (opts.bench) cases = loadBench(path.resolve(String(opts.bench)), { split: opts.split as 'dev' | 'test' | undefined });
  else {
    const file = opts.queries ? path.resolve(String(opts.queries)) : dome.rag?.evalSet ? path.resolve(dome.path, dome.rag.evalSet) : '';
    if (!file || !fs.existsSync(file)) throw new RagError('INVALID_INPUT', 'banco no encontrado (--bench, --queries o rag.evalSet)');
    cases = legacyToCases(JSON.parse(fs.readFileSync(file, 'utf-8')) as EvalQueryInput[]);
  }
  const mode = (opts.mode === 'all' ? 'hybrid' : opts.mode) as RagMode;
  if (!['hybrid', 'dense', 'bm25'].includes(mode)) throw new RagError('INVALID_INPUT', `mode no válido: ${mode}`);
  let budget: unknown;
  if (opts.budget) { try { budget = JSON.parse(String(opts.budget)); } catch { throw new RagError('INVALID_INPUT', '--budget: JSON'); } }
  const seed = int(opts.seed, 'seed');
  const iterations = int(opts.iterations, 'iterations');
  const k = int(opts.k, 'k');
  if (k < 1 || k > RAG_LIMITS.maxK) throw new RagError('INVALID_INPUT', `--k: 1-${RAG_LIMITS.maxK}`);
  const deny = (names: string[]) => { denied.clear(); for (const n of names) denied.add(n); };
  const reports: RouteReport[] = [];
  for (const r of [...new Set([baseline, ...routes])]) {
    reports.push(await evaluateRoute(svc, cases, { route: r, mode, k, seed, iterations, budget, domes: [String(opts.dome)], deny }));
  }
  const base = reports.find(r => r.route === baseline)!;
  const shown = reports.filter(r => routes.includes(r.route));
  const comparisons = shown.map(r => compareReports(r, base, { iterations, seed }));
  // Códigos de salida: 2 si hay lecturas no autorizadas (prevalece: es una fuga), 1 si algún caso falló.
  const exitCode = reports.some(r => r.violations > 0) ? 2 : reports.some(r => r.errors > 0) ? 1 : 0;
  const finish = () => {
    for (const r of reports) {
      if (r.errors) console.error(`[${r.route}] ${r.errors} casos con error: ${r.cases.filter(c => c.error).slice(0, 3).map(c => `${c.id}: ${c.error}`).join(' | ')}`);
      if (r.violations) console.error(`[${r.route}] ALERTA: ${r.violations} casos con lecturas no autorizadas`);
    }
    if (exitCode) process.exit(exitCode);
  };
  if (opts.json) { console.log(JSON.stringify({ reports: shown, comparisons }, null, 2)); finish(); return; }
  const f = (i: { mean: number; lo: number; hi: number; n: number }) => (i.n ? `${i.mean.toFixed(3)} [${i.lo.toFixed(3)}, ${i.hi.toFixed(3)}]` : '-');
  for (const r of shown) {
    console.log(`[${opts.dome}] ruta ${r.route} ${r.mode} n=${r.n} errores=${r.errors} violaciones=${r.violations} denegados=${r.deniedAttempts} p50=${r.latency.p50Ms}ms p95=${r.latency.p95Ms}ms RSS=${r.rssPeakMb}MB llamadas=${r.cost.modelCalls}`);
    console.log(`   EvidenceRecall=${f(r.overall.evidenceRecall)} exact-id=${f(r.overall.exactIdentifierHit)} R@10=${f(r.overall.recallAt10)} MRR=${f(r.overall.mrr)} nDCG@10=${f(r.overall.ndcgAt10)}`);
    console.log(`   no-autorizadas=${f(r.overall.unauthorizedReads)} prohibidas=${f(r.overall.forbiddenUsed)} abstención-correcta=${f(r.overall.correctAbstention)} falso-rechazo=${f(r.overall.falseAbstention)}`);
    for (const [cat, m] of Object.entries(r.byCategory)) console.log(`   ${cat}: EvidenceRecall=${f(m!.evidenceRecall)} R@10=${f(m!.recallAt10)} abstención=${f(m!.correctAbstention)}`);
  }
  for (const c of comparisons) {
    if (c.route === c.baseline) continue;
    const d = c.overall.evidenceRecall;
    console.log(`${c.route} − ${c.baseline}: ΔEvidenceRecall=${d ? `${d.diff.toFixed(3)} [${d.lo.toFixed(3)}, ${d.hi.toFixed(3)}] n=${d.n}` : '-'}`);
  }
  finish();
}

ragCmd.command('promote <dome> <generation>').description('Promueve una generación (gate de eval; --force = decisión humana)')
  .option(...domesOpt).option('--force', 'saltar el gate', false)
  .action(async (dome, generation, opts) => {
    try { const d = await ragService(opts.domesFile).promote(dome, generation, opts.force); console.log(`[${dome}] ${generation} activa — ${d.reason}`); }
    catch (e) { ragFail(e); }
  });

ragCmd.command('rollback <dome>').description('Restaura la generación anterior')
  .option(...domesOpt)
  .action(async (dome, opts) => {
    try { console.log(`[${dome}] activa=${await ragService(opts.domesFile).rollback(dome)}`); }
    catch (e) { ragFail(e); }
  });

ragCmd.command('gc').description('Borra generaciones y ficheros no referenciados')
  .option(...domesOpt).option('--dome <name>').option('--all', 'solo las cúpulas con rag.enabled', false)
  .action(async (opts) => {
    try {
      const svc = ragService(opts.domesFile);
      const names = opts.dome ? [opts.dome]
        : opts.all ? (await svc.status()).filter(s => s.enabled).map(s => s.name)
        : (await svc.status()).map(s => s.name); // compat: sin flags, todas
      for (const n of names) console.log(`[${n}] eliminados ${await svc.gc(n)}`);
    } catch (e) { ragFail(e); }
  });

ragCmd.command('drop').description('Borra el índice de una cúpula con rag.enabled=false (limpia la alerta de índice huérfano)')
  .argument('<dome>').option(...domesOpt)
  .action(async (dome, opts) => {
    try { console.log(`[${dome}] ${await ragService(opts.domesFile).drop(dome) ? 'índice eliminado' : 'sin índice'}`); }
    catch (e) { ragFail(e); }
  });

program.parse();
