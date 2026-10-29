// SE-410/411 — CLI de Savia RAG. Módulo separado para que `savia-vaults rag …`
// no cargue el servidor MCP/A2A ni la capa de conocimiento (arranque en frío).
import { Command } from 'commander';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { DomeRegistry } from '../registry/domes.js';
import { RagService, type EvalQueryInput } from '../rag/service.js';
import { RagError, RAG_LIMITS, type RagMode } from '../rag/types.js';
import { formatRagResponse } from '../rag/format.js';

const program = new Command();
program.name('savia-vaults');

function ragService(domesFile: string): RagService {
  const reg = new DomeRegistry(path.resolve(domesFile));
  reg.load();
  return new RagService({
    domes: () => reg.listActive().map(d => ({ name: d.name, path: d.path, confidentiality: d.confidentiality, rag: d.rag, files: d.files })),
    background: false,
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
        console.log(`[${r.dome}] gen=${r.generation}${r.promoted ? ' (activa)' : r.shadow ? ' (sombra)' : ''} docs +${r.docs.added} ~${r.docs.updated} -${r.docs.deleted} =${r.docs.unchanged} omitidos ${r.docs.skipped} chunks ${r.chunks.total} (embebidos ${r.chunks.embedded}, reutilizados ${r.chunks.reused}) ${r.durationMs} ms`);
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

ragCmd.command('eval').description('Evalúa recall@5/@10, MRR y latencia sobre un banco de consultas')
  .option(...domesOpt).requiredOption('--dome <name>').option('--queries <file>', 'banco JSON (def. rag.evalSet de la cúpula)')
  .option('--generation <id>').option('--mode <mode>', 'hybrid|dense|bm25|all', 'all').option('--json', 'salida JSON', false)
  .action(async (opts) => {
    try {
      const svc = ragService(opts.domesFile);
      const reg = new DomeRegistry(path.resolve(opts.domesFile)); reg.load();
      const dome = reg.get(opts.dome);
      if (!dome) throw new RagError('UNKNOWN_DOME', opts.dome);
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
