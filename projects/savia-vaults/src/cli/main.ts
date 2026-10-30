import { getAINotice } from '../compliance/transparency.js';
import { Command } from 'commander';
import { VaultStorage } from '../storage/index.js';
import { SearchEngine } from '../search/index.js';
import { MCPVaultServer } from '../server/mcp.js';
import { A2AServer } from '../server/a2a.js';
import { BackupManager } from '../backup/index.js';
import { FederationRegistry } from '../federation/registry.js';
import { Introspector } from '../knowledge/introspector.js';
import { KnowledgeGraph } from '../knowledge/graph.js';
import { PPRRanker } from '../knowledge/ppr.js';
import { QueryEngine } from '../knowledge/query.js';
import { QualityEngine } from '../knowledge/quality.js';
import type { VaultConfig } from '../types.js';
import { DomeRegistry, isGitTracked } from '../registry/domes.js';
import { UserStore, ConfidentialityGuard, AuditLogger, UserQuotaStore, AccessController } from '../auth/index.js';
import * as fs from 'node:fs';
import * as path from 'node:path';

function makeConfig(name: string, vaultPath: string): VaultConfig {
  return { name, path: vaultPath, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 10 * 1024 * 1024 };
}

const program = new Command();
program.name('savia-vaults').description('Context Dome Server — MCP + A2A server for AI agent knowledge vaults').version('0.2.0');

program.command('init <name>').description('Create a new vault')
  .option('-p, --path <path>', 'Parent directory', process.cwd())
  .action(async (name, opts) => {
    const vaultPath = `${opts.path}/vaults/${name}`;
    const config = makeConfig(name, vaultPath);
    const storage = new VaultStorage(config);
    await storage.init();
    console.log(`Vault "${name}" created at ${vaultPath}`);
    console.log(`Next: savia-vaults serve --transport mcp --path ${vaultPath}`);
  });

program.command('serve').description('Start MCP, A2A or HTTP (Savia Files) server')
  .option('--transport <type>', 'mcp, a2a or http (SE-422: API HTTP de ficheros con tus 1.0)', 'mcp')
  .option('--port <port>', 'Port for A2A (8923) or HTTP (8924)')
  .option('--tls-cert <file>', 'http: certificado TLS (PEM)')
  .option('--tls-key <file>', 'http: clave TLS (PEM)')
  .option('--behind-proxy', 'http: TLS terminado en un proxy delante (permite escuchar fuera de loopback sin TLS propio)', false)
  .option('--host <host>', 'Bind host', '127.0.0.1')
  .option('-p, --path <path>', 'Vault path (legacy single-dome)', process.cwd())
  .option('--domes <file>', 'Domes registry file', 'savia-vaults.domes.json')
  .option('--rag-autosync <minutes>', 'a2a: sync incremental de RAG de las cúpulas habilitadas cada N minutos (SE-480; desactivado por defecto)')
  .action(async (opts, command) => {
    const authToken = process.env.SAVIA_VAULTS_TOKEN;
    let autosyncMin: number | undefined;
    if (opts.ragAutosync !== undefined) {
      autosyncMin = Number(opts.ragAutosync);
      if (!Number.isFinite(autosyncMin) || autosyncMin <= 0 || opts.transport !== 'a2a') {
        console.error('--rag-autosync <minutos> exige minutos > 0 y --transport a2a');
        process.exit(1);
      }
    }

    // SE-310: si --path se paso EXPLICITO, el usuario pide single-dome legacy;
    // el registry por defecto no debe secuestrar la ruta (bug: antes se cargaba
    // savia-vaults.domes.json del cwd aunque se pasara --path).
    const explicitPath = command.getOptionValueSource('path') === 'cli';

    let domeReg: DomeRegistry | undefined;
    let userStore: UserStore | undefined;

    const domesFile = path.resolve(opts.domes);
    if (!explicitPath && fs.existsSync(domesFile)) {
      domeReg = new DomeRegistry(domesFile);
      try {
        domeReg.load();
        console.error(`[serve] Multi-dome mode: ${domeReg.listActive().length} domes loaded from ${domesFile}`);
      } catch (e) {
        console.error(`[serve] WARNING: failed to load domes from ${domesFile}: ${e instanceof Error ? e.message : e}`);
        console.error('[serve] Falling back to single-dome legacy mode.');
        domeReg = undefined;
      }
    }

    if (!domeReg) {
      console.error(`[serve] Legacy single-dome mode: ${opts.path}`);
    }

    const config = makeConfig('vault', opts.path);

    if (domeReg) {
      const defaultDome = domeReg.listActive()[0];
      if (defaultDome?.schemaDir) {
        config.schemaDir = defaultDome.schemaDir;
        console.error(`[serve] Knowledge layer enabled: schemaDir=${config.schemaDir}`);
      }

      const usersFile = 'savia-vaults.users.json';
      if (fs.existsSync(usersFile)) {
        userStore = new UserStore(usersFile);
        try { userStore.load(); console.error('[serve] Auth enabled: users loaded'); } catch {}
      }
    }

    if (opts.transport === 'mcp') {
      const server = new MCPVaultServer(config, domeReg, userStore);
      await server.start();
    } else if (opts.transport === 'a2a') {
      // SE-424 H2: CORS solo para orígenes explícitos; sin token, solo loopback.
      const corsOrigins = (process.env.SAVIA_A2A_CORS_ORIGINS ?? '').split(',').map((o) => o.trim()).filter(Boolean);
      // SE-423: con registro de cúpulas, A2A autoriza por usuario en cuanto exista el fichero de usuarios.
      const access = domeReg
        ? new AccessController(userStore ?? new UserStore('savia-vaults.users.json'), domeReg, new AuditLogger())
        : undefined;
      const server = new A2AServer(config, domeReg, { corsOrigins, access });
      if (autosyncMin !== undefined && domeReg) {
        const { RagService } = await import('../rag/service.js');
        const { RagAutosync } = await import('../rag/autosync.js');
        const rag = new RagService({
          domes: () => domeReg.listActive().map(d => ({ name: d.name, path: d.path, confidentiality: d.confidentiality, rag: d.rag, files: d.files })),
        });
        const autosync = new RagAutosync(rag, { intervalMin: autosyncMin, refresh: () => { server.refreshRegistry(); }, startDelayMs: process.env.SAVIA_RAG_AUTOSYNC_DELAY_MS ? Number(process.env.SAVIA_RAG_AUTOSYNC_DELAY_MS) : undefined });
        rag.setAutosyncState(() => autosync.getState());
        server.onRegistryReload = () => autosync.onRegistryReload();
        server.autosync = autosync;
        autosync.start();
      } else if (autosyncMin !== undefined) {
        console.error('[serve] --rag-autosync ignorado: sin registro de cúpulas no hay RAG que sincronizar');
      }
      try {
        await server.start(parseInt(opts.port ?? '8923', 10), opts.host, authToken || undefined);
      } catch (e) {
        console.error(e instanceof Error ? e.message : String(e));
        process.exit(1);
      }
    } else if (opts.transport === 'http') {
      // SE-422: exige registro de cúpulas y usuarios; fuera de loopback, TLS o --behind-proxy.
      if (!domeReg) { console.error('La API HTTP necesita un registro de cúpulas (--domes).'); process.exit(1); }
      const users = userStore ?? new UserStore('savia-vaults.users.json');
      if ((opts.tlsCert === undefined) !== (opts.tlsKey === undefined)) { console.error('--tls-cert y --tls-key van juntos.'); process.exit(1); }
      const tls = opts.tlsCert ? { cert: fs.readFileSync(opts.tlsCert), key: fs.readFileSync(opts.tlsKey) } : undefined;
      const { FilesHttpServer } = await import('../server/http.js');
      const { AccessController } = await import('../auth/index.js');
      const server = new FilesHttpServer({
        domes: domeReg, users, access: new AccessController(users, domeReg, new AuditLogger(), new UserQuotaStore()),
        host: opts.host, port: parseInt(opts.port ?? '8924', 10), tls, behindProxy: opts.behindProxy === true,
      });
      try {
        const { url } = await server.start();
        console.error(`[serve] API HTTP de ficheros en ${url}/v1/files/<cúpula>/… (define SAVIA_FILES_HTTP_URL=${url} para vault_files upload/link)`);
      } catch (e) {
        console.error(e instanceof Error ? e.message : String(e));
        process.exit(1);
      }
    } else {
      console.error(`Transporte desconocido: ${opts.transport} (mcp, a2a o http)`);
      process.exit(1);
    }
  });

// SE-412: `search` vive en ./search.ts y se carga sin el resto de la CLI.
program.command('search <query>').description('Search the vault (BM25) — ver `savia-vaults search --help`');

program.command('stats').description('Show vault statistics')
  .option('-p, --path <path>', 'Vault path', process.cwd()).option('--json', 'JSON output', false)
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config); await storage.init();
    const stats = await storage.stats();
    if (opts.json) { console.log(JSON.stringify(stats, null, 2)); }
    else { console.log(`Vault: ${stats.name}\nNotes: ${stats.noteCount}\nSize:  ${(stats.totalSize / 1024).toFixed(1)} KB`); if (stats.commitCount) console.log(`Commits: ${stats.commitCount}`); }
  });

program.command('introspect').description('Discover entity types and coverage')
  .option('-p, --path <path>', process.cwd()).option('-e, --entity <path>').option('--json')
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const introspector = new Introspector(config);
    if (opts.entity) {
      const result = await introspector.introspectEntity(opts.entity);
      console.log(opts.json ? JSON.stringify(result, null, 2) : result ? `${result.type}:${result.id}` : 'Not found');
    } else {
      const result = await introspector.introspectVault();
      if (opts.json) console.log(JSON.stringify(result, null, 2));
      else { console.log(`Documents: ${result.totalDocuments}\nEntities: ${result.totalEntities}`); for (const t of result.entityTypes) console.log(`  ${t.label}: ${t.count}`); }
    }
  });

program.command('graph').description('Knowledge graph operations')
  .option('-p, --path <path>', process.cwd()).option('--action <action>', 'stats')
  .option('--id <id>').option('--depth <n>', '3').option('--query <q>').option('--json')
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const graph = new KnowledgeGraph(config); await graph.build();
    if (opts.action === 'traverse') {
      const result = graph.traverse(opts.id, parseInt(opts.depth, 10));
      if (opts.json) console.log(JSON.stringify(result, null, 2));
      else { console.log(`${result.nodes.length} nodes, ${result.relations.length} relations`); for (const r of result.relations) console.log(`  ${r.from} --[${r.type}]--> ${r.to}`); }
    } else if (opts.action === 'search') {
      const nodes = graph.searchNodes(opts.query || '');
      for (const n of nodes) console.log(`${n.id} (${n.type}) — ${n.outgoing.length} out, ${n.incoming.length} in`);
    } else if (opts.action === 'ppr') {
      // SE-327: Personalized PageRank — ranking de relevancia dado un seed set.
      const ranker = new PPRRanker();
      const seeds = (opts.id ? [opts.id] : []);
      const topN = parseInt(opts.depth ?? '10', 10);
      const snapshot = graph.getSnapshot() ?? { nodes: new Map() };
      const top = ranker.top(snapshot, seeds, topN);
      if (opts.json) console.log(JSON.stringify(top, null, 2));
      else for (const t of top) console.log(`${t.id}\t${t.score.toFixed(6)}`);
    } else { const s = graph.getStats(); console.log(`Nodes: ${s.nodeCount}\nRelations: ${s.relationCount}`); }
  });

program.command('query <expression>').description('Deterministic entity query (--mode local|global|hybrid)')
  .option('-p, --path <path>', process.cwd()).option('--json').option('--mode <mode>', 'local|global|hybrid', 'local')
  .action(async (expression, opts) => {
    const config = makeConfig('vault', opts.path);
    const engine = new QueryEngine(config); await engine.ensureLoaded();
    if (opts.mode === 'global') {
      const result = await engine.queryGlobal();
      if (opts.json) console.log(JSON.stringify(result.outputRows, null, 2));
      else console.log(result.outputMarkdown);
      return;
    }
    if (opts.mode === 'hybrid') {
      const result = await engine.queryHybrid(expression);
      if (opts.json) console.log(JSON.stringify(result.outputRows, null, 2));
      else console.log(result.outputMarkdown);
      return;
    }
    const result = await engine.query(expression);
    if (opts.json) console.log(JSON.stringify(result.outputRows, null, 2));
    else console.log(result.outputMarkdown);
  });

program.command('eval-search').description('SE-331: evaluación de recuperación (precision@k / recall@k)')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .option('--eval-file <path>', 'Banco de queries JSON externo').option('--modes <modes>', 'bm25,enriched', 'bm25')
  .option('--top-k <n>', 'k máximo', '10').option('--json')
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const engine = new SearchEngine(config);
    engine.buildIndex();
    const modes = (opts.modes || 'bm25').split(',').map((m: string) => m.trim()).filter((m: string) => m === 'bm25' || m === 'enriched') as ('bm25' | 'enriched')[];
    const maxResults = parseInt(opts.topK ?? '10', 10);

    let queries: import('../search/eval.js').EvalQuery[] = [];
    if (opts.evalFile && fs.existsSync(opts.evalFile)) {
      queries = JSON.parse(fs.readFileSync(opts.evalFile, 'utf-8'));
    } else {
      // seeder: entidades del grafo como banco mínimo auto-generado
      const graph = new KnowledgeGraph(config);
      await graph.build();
      const nodes = graph.searchNodes('');
      queries = nodes.slice(0, 20).map(n => ({ query: n.id, relevantPaths: [n.path] }));
    }

    const searcher: import('../search/eval.js').Searcher = async (q, max) => {
      const res = engine.search({ query: q, maxResults: max });
      return res;
    };
    const { evaluate } = await import('../search/eval.js');
    const result = await evaluate(queries, searcher, modes, { maxResults });
    if (opts.json) { console.log(JSON.stringify(result, null, 2)); return; }
    for (const mode of modes) {
      const r = result[mode];
      console.log(`\n== ${mode} (${queries.length} queries, top-${maxResults}) ==`);
      console.log(`  meanPrecision@${maxResults}: ${r.meanPrecisionAtK.toFixed(3)}`);
      console.log(`  meanRecall@${maxResults}: ${r.meanRecallAtK.toFixed(3)}`);
      console.log(`  failedQueries: ${r.failedQueries.length}`);
    }
  });

program.command('health-report').description('Vault quality health report')
  .option('-p, --path <path>', process.cwd()).option('--json')
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const quality = new QualityEngine(config);
    const indicators = await quality.assess();
    if (opts.json) console.log(JSON.stringify(indicators, null, 2));
    else console.log(quality.formatReport(indicators));
  });

program.command('verify')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config); await storage.init();
    const files = await storage.list();
    let ok = 0, fail = 0;
    for (const f of files) {
      try {
        const note = await storage.read(f);
        const content = fs.readFileSync(path.join(opts.path, f), 'utf-8');
        const { verifySignature } = await import('../security/index.js');
        if (verifySignature(content, note.frontmatter._signature as string || '')) ok++; else { fail++; console.log(`  FAIL: ${f}`); }
      } catch { fail++; }
    }
    console.log(`Verified ${files.length} notes: ${ok} OK, ${fail} FAIL`);
  });

program.command('export').description('Export vault to portable format')
  .option('-p, --path <path>', 'Vault path', process.cwd()).option('-o, --output <dir>', 'Output directory')
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config);
    const outputDir = opts.output || `${opts.path}-export`;
    fs.mkdirSync(outputDir, { recursive: true });
    const files = await storage.list();
    for (const f of files) {
      try { const note = await storage.read(f); const dest = path.join(outputDir, f); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, note.content); }
      catch (e) { console.error(`Failed to export ${f}: ${e instanceof Error ? e.message : e}`); }
    }
    console.log(`Exported ${files.length} notes to ${outputDir}`);
  });

// OKF interop commands (SE-307)
program.command('okf-conformance').description('Check vault conformance with Open Knowledge Format v0.1')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config);
    const { checkOkfConformance } = await import('../knowledge/okf-conformance.js');
    const report = await checkOkfConformance(storage, opts.path);
    console.log(`OKF Conformance: ${report.conformant ? 'CONFORMANT' : 'NON-CONFORMANT'} (${report.noteCount} notes)`);
    for (const v of report.violations) console.log(`  VIOLATION: ${v}`);
    for (const w of report.warnings) console.log(`  warning: ${w}`);
    if (!report.conformant) process.exit(1);
  });

program.command('okf-export').description('Export vault as OKF v0.1 bundle')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .option('-o, --output <dir>', 'Output directory')
  .option('--no-index', 'Skip index.md files')
  .option('--no-log', 'Skip log.md files')
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config);
    const outputDir = opts.output || `${opts.path}-okf-export`;
    const { exportOkfBundle } = await import('../knowledge/okf-export.js');
    const result = await exportOkfBundle(storage, outputDir, {
      includeIndexFiles: opts.index !== false,
      includeLogFiles: opts.log !== false,
    });
    console.log(`Exported ${result.exported} notes to ${outputDir}`);
    for (const s of result.skipped) console.log(`  skipped: ${s}`);
  });

program.command('okf-import').description('Import an OKF v0.1 bundle into the vault')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .option('-s, --source <dir>', 'Source bundle directory', '')
  .option('--strip-prefix <prefix>', 'Strip path prefix from imported notes', '')
  .option('--force', 'Overwrite existing notes', false)
  .action(async (opts) => {
    if (!opts.source) { console.error('ERROR: --source is required'); process.exit(1); }
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config);
    const { importOkfBundle } = await import('../knowledge/okf-import.js');
    const result = await importOkfBundle(storage, {
      sourceDir: opts.source,
      stripPrefix: opts.stripPrefix || undefined,
      force: opts.force,
    });
    console.log(`Imported ${result.imported} notes`);
    for (const r of result.rejected) console.log(`  rejected: ${r}`);
  });

// SE-309 — Knowledge Governance commands
const decisionCmd = program.command('decision').description('Manage decision records (SE-309)');
decisionCmd.command('record').description('Record a decision as a first-class knowledge node')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .option('--category <cat>', 'Decision category', '')
  .option('--scenario <scenario>', 'Decision scenario', '')
  .option('--reasoning <reasoning>', 'Decision reasoning', '')
  .option('--outcome <outcome>', 'Decision outcome', '')
  .option('--confidence <n>', 'Confidence 0-1', '0.5')
  .option('--maker <maker>', 'Decision maker', 'savia')
  .action(async (opts) => {
    if (!opts.category || !opts.outcome) {
      console.error('ERROR: --category and --outcome are required'); process.exit(1);
    }
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config);
    const { createDecisionRecord } = await import('../knowledge/decision.js');
    const rec = createDecisionRecord({
      category: opts.category,
      scenario: opts.scenario,
      reasoning: opts.reasoning,
      outcome: opts.outcome,
      confidence: parseFloat(opts.confidence),
      decisionMaker: opts.maker,
    });
    const fileName = `decisions/${rec.id.slice(0, 8)}.md`;
    const content = [
      '---',
      `entity: {type: decision, id: ${rec.id}}`,
      `category: ${rec.category}`,
      `scenario: ${rec.scenario}`,
      `reasoning: ${rec.reasoning}`,
      `outcome: ${rec.outcome}`,
      `confidence: ${rec.confidence}`,
      `state: ${rec.state}`,
      `decision_maker: ${rec.decision_maker}`,
      '---',
      `# Decision: ${rec.category}`,
      '',
      `**Scenario**: ${rec.scenario}`,
      `**Reasoning**: ${rec.reasoning}`,
      `**Outcome**: ${rec.outcome}`,
    ].join('\n');
    await storage.write(fileName, content, `Decision ${rec.id}`);
    console.log(`Recorded decision ${rec.id} → ${fileName}`);
  });

decisionCmd.command('promote').description('Change decision state (accepted/rejected) with reason')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .option('--id <id>', 'Decision id', '')
  .option('--state <state>', 'New state: accepted|rejected', '')
  .option('--reason <reason>', 'Reason for the change', '')
  .option('--by <by>', 'Who is promoting', 'savia')
  .action(async (opts) => {
    if (!opts.id || !opts.state || !opts.reason) {
      console.error('ERROR: --id, --state and --reason are required'); process.exit(1);
    }
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config);
    const note = await storage.read(`decisions/${opts.id}.md`).catch(() => null);
    if (!note) { console.error(`Decision ${opts.id} not found`); process.exit(1); }
    const { serializeOkfNote, parseOkfFrontmatter } = await import('../knowledge/okf.js');
    // Robust: si frontmatter parseado vacio pero content empieza con ---, re-extraer
    let fm = { ...note.frontmatter } as Record<string, unknown>;
    let body = note.content;
    if (Object.keys(fm).length === 0 && body.startsWith('---')) {
      const parsed = parseOkfFrontmatter(body);
      fm = parsed.frontmatter;
      body = parsed.content;
    }
    fm.state = opts.state;
    fm.state_reason = opts.reason;
    const noteContent = serializeOkfNote(fm, body);
    await storage.write(`decisions/${opts.id}.md`, noteContent, `Promote ${opts.id} → ${opts.state}`);
    console.log(`Promoted ${opts.id} → ${opts.state} (${opts.reason})`);
  });

const conflictCmd = program.command('conflict').description('Detect and resolve contradictory facts (SE-309)');
conflictCmd.command('scan').description('Detect contradictory facts in the vault')
  .option('-p, --path <path>', 'Vault path', process.cwd())
  .action(async (opts) => {
    const config = makeConfig('vault', opts.path);
    const storage = new VaultStorage(config);
    const { detectConflicts } = await import('../knowledge/conflicts.js');
    const paths = await storage.list();
    const notes = [];
    for (const p of paths) {
      try { notes.push(await storage.read(p)); } catch { /* skip */ }
    }
    const conflicts = detectConflicts(notes as never[]);
    if (conflicts.length === 0) {
      console.log('No conflicts detected');
      return;
    }
    console.log(`Detected ${conflicts.length} conflict(s):`);
    for (const c of conflicts) {
      console.log(`  [${c.entityId}.${c.property}] ${c.valueA} (${c.sourceA}) vs ${c.valueB} (${c.sourceB})`);
    }
  });

// Federate commands
const federateCmd = program.command('federate').description('Manage federated domes');
federateCmd.command('add <id> <url>').description('Register a remote dome')
  .option('--token <token>', 'Auth token').option('--weight <n>', 'Weight', '1.0').option('--tags <tags>', 'Comma-separated tags', '')
  .action((id, url, opts) => {
    const registry = new FederationRegistry(path.join(process.cwd(), '.savia-vault'));
    registry.add({ id, name: id, url, authToken: opts.token, timeout: 5000, enabled: true, weight: parseFloat(opts.weight), tags: opts.tags ? opts.tags.split(',') : [], status: 'unknown' });
    console.log(`Dome "${id}" registered at ${url}`);
  });
federateCmd.command('list').description('List federated domes').action(() => {
  const registry = new FederationRegistry(path.join(process.cwd(), '.savia-vault'));
  const domes = registry.list();
  domes.length ? domes.forEach(d => console.log(`${d.id} (${d.status}) — ${d.url}`)) : console.log('No federated domes.');
});
federateCmd.command('remove <id>').description('Remove a dome').action((id) => {
  const registry = new FederationRegistry(path.join(process.cwd(), '.savia-vault'));
  console.log(registry.remove(id) ? `Removed "${id}".` : `Dome "${id}" not found.`);
});
federateCmd.command('health').description('Check health of all domes').action(async () => {
  const { FederatedSearchEngine } = await import('../federation/search.js');
  const { SearchEngine: SE } = await import('../search/index.js');
  const config = makeConfig('vault', process.cwd());
  const local = new SE(config);
  local.buildIndex();
  const registry = new FederationRegistry(path.join(process.cwd(), '.savia-vault'));
  const engine = new FederatedSearchEngine(local, registry);
  const results = await engine.healthCheckAll();
  results.forEach(r => console.log(`${r.id}: ${r.healthy ? 'healthy' : 'unhealthy'} (${r.latencyMs}ms)`));
});

// Backup commands
const backupCmd = program.command('backup').description('Manage vault backups');
const bm = new BackupManager();
backupCmd.command('create').description('Create a backup').option('-p, --path <path>', 'Vault path', process.cwd())
  .action((opts) => {
    const entry = bm.create(opts.path, path.basename(opts.path));
    console.log(`Backup created: ${entry.id}`);
    console.log(`  Size: ${(entry.size / 1024).toFixed(1)} KB`);
    console.log(`  File: ${entry.file}`);
  });
backupCmd.command('list').description('List backups').action(() => {
  const entries = bm.list();
  entries.length ? entries.forEach(e => console.log(`${e.id}  ${e.vault}  ${(e.size / 1024).toFixed(1)} KB  ${e.timestamp}`)) : console.log('No backups found.');
});
backupCmd.command('restore <id>').description('Restore a backup').option('--target <dir>', 'Target directory')
  .action((id, opts) => {
    const target = opts.target || path.join(process.cwd(), 'restored');
    bm.restore(id, target);
    console.log(`Restored ${id} to ${target}`);
  });
backupCmd.command('status').description('Backup system status').action(() => {
  const s = bm.status();
  console.log(`Backups: ${s.count} in ${s.backupsDir}`);
  console.log(`Nextcloud: ${s.nextcloudConfigured ? 'configured' : 'not configured'}`);
});

// ── User management commands (SE-291 S6) ──
const userCmd = program.command('user').description('Manage users and permissions');

userCmd.command('create <username>').description('Create a new user and generate token')
  .option('--expires <days>', 'días de validez del token (SE-423; por defecto 90, máximo SAVIA_VAULTS_PAT_MAX_DAYS)')
  .option('--service', 'cuenta de servicio (no humana)', false)
  .action((username, opts) => {
    const store = new UserStore();
    try { store.load(); } catch {}
    try {
      const token = store.createUser(username, { type: opts.service ? 'service' : 'human', expiresDays: opts.expires ? Number(opts.expires) : undefined });
      store.save();
      console.log('═'.repeat(70));
      console.log(`User "${username}" created.`);
      console.log(`Token:  ${token}`);
      console.log('═'.repeat(70));
      console.log('SAVE THIS TOKEN. It will not be shown again.');
      console.log('Configure it in your MCP client as SAVIA_AUTH_TOKEN.');
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('delete <username>').description('Delete a user')
  .action((username) => {
    const store = new UserStore();
    store.load();
    try {
      store.deleteUser(username);
      store.save();
      console.log(`User "${username}" deleted.`);
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('list').description('List all users')
  .option('--json', 'JSON output')
  .action((opts) => {
    const store = new UserStore();
    store.load();
    const users = store.listUsers();
    if (users.length === 0) { console.log('No users configured.'); return; }
    const soon = Date.now() + 14 * 86_400_000;
    const active = (u: (typeof users)[number]) => u.credentials.filter((c) => !c.revokedAt && Date.parse(c.expiresAt) > Date.now());
    if (opts.json) {
      const safe = users.map(u => ({
        username: u.username, subjectId: u.subjectId, type: u.type, createdAt: u.createdAt,
        domeCount: Object.keys(u.permissions).length, credentials: u.credentials,
      }));
      console.log(JSON.stringify(safe, null, 2));
    } else {
      for (const u of users) {
        const domes = Object.keys(u.permissions).join(', ') || '(none)';
        console.log(`  ${u.username}  [${Object.keys(u.permissions).length} domes]  ${domes}  · ${active(u).length} token(s) vigentes`);
        for (const c of active(u)) {
          if (Date.parse(c.expiresAt) < soon) console.log(`    AVISO: el token "${c.name}" (${c.id}) caduca el ${c.expiresAt.slice(0, 10)}; crea otro con user token-create`);
        }
        if (!active(u).length) console.log('    AVISO: sin tokens vigentes; crea uno con user token-create');
      }
    }
  });

userCmd.command('token <username>').description('Show or regenerate user token')
  .option('--regenerate', 'Generate new token (revokes all the previous ones)')
  .action((username, opts) => {
    const store = new UserStore();
    store.load();
    try {
      if (opts.regenerate) {
        const token = store.regenerateToken(username);
        store.save();
        console.log('═'.repeat(70));
        console.log(`New token for "${username}":`);
        console.log(`Token:  ${token}`);
        console.log('═'.repeat(70));
        console.log('Previous tokens are now REVOKED. Update your MCP client config.');
      } else {
        console.log(`Use --regenerate to generate a new token for "${username}".`);
        console.log('The current token cannot be displayed (only its hash is stored).');
      }
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

// SE-423: varias credenciales por usuario, con caducidad, alcance y revocación individual.
userCmd.command('tokens <username>').description('Lista los tokens del usuario (sin secretos)')
  .option('--json', 'salida JSON', false)
  .action((username, opts) => {
    const store = new UserStore();
    store.load();
    try {
      const list = store.listTokens(username);
      if (opts.json) { console.log(JSON.stringify(list, null, 2)); return; }
      for (const c of list) {
        const state = c.revokedAt ? 'revocado' : Date.parse(c.expiresAt) <= Date.now() ? 'caducado' : 'vigente';
        const scope = [c.domes ? `cúpulas ${c.domes.join(',')}` : '', c.maxRole ? `máx. ${c.maxRole}` : ''].filter(Boolean).join(' · ');
        console.log(`  ${c.id}  ${c.name.padEnd(16)} ${state.padEnd(9)} caduca ${c.expiresAt.slice(0, 10)}${scope ? `  ${scope}` : ''}`);
      }
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('token-create <username>').description('Crea un token adicional con caducidad y alcance opcional')
  .requiredOption('--name <name>', 'nombre del token (p. ej. portátil, servidor)')
  .option('--expires <days>', 'días de validez (por defecto 90)')
  .option('--domes <list>', 'solo estas cúpulas (a,b)')
  .option('--max-role <role>', 'rol máximo: reader o writer (nunca amplía el del usuario)')
  .action((username, opts) => {
    if (opts.maxRole && !['admin', 'writer', 'reader'].includes(opts.maxRole)) {
      console.error('--max-role debe ser reader, writer o admin.');
      process.exit(1);
    }
    const store = new UserStore();
    store.load();
    try {
      const token = store.createToken(username, {
        name: opts.name, expiresDays: opts.expires ? Number(opts.expires) : undefined,
        domes: opts.domes ? String(opts.domes).split(',').map((d: string) => d.trim()).filter(Boolean) : undefined,
        maxRole: opts.maxRole,
      });
      store.save();
      console.log('═'.repeat(70));
      console.log(`Token "${opts.name}" para "${username}":`);
      console.log(`Token:  ${token}`);
      console.log('═'.repeat(70));
      console.log('Guárdalo ahora: no se vuelve a mostrar.');
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('token-revoke <username> <id>').description('Revoca un token concreto (los demás siguen valiendo)')
  .action((username, id) => {
    const store = new UserStore();
    store.load();
    try {
      store.revokeToken(username, id);
      store.save();
      console.log(`Token ${id} de ${username} revocado.`);
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('rename <username> <newName>').description('Cambia el nombre conservando identidad, tokens, permisos y acceso por documento (SE-423)')
  .action((username, newName) => {
    const store = new UserStore();
    store.load();
    try {
      store.renameUser(username, newName);
      store.save();
      console.log(`${username} ahora es ${newName}. Sus tokens siguen valiendo; "${username}" no podrá reutilizarse.`);
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('grant <username> <dome> <role>').description('Grant role to user on a dome')
  .action((username, dome, role) => {
    if (!['admin', 'writer', 'reader'].includes(role)) {
      console.error('Role must be admin, writer, or reader.');
      process.exit(1);
    }
    const store = new UserStore();
    store.load();
    try {
      store.setPermission(username, dome, role as 'admin' | 'writer' | 'reader');
      store.save();
      console.log(`Granted ${role} on "${dome}" to ${username}.`);
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('revoke <username> <dome>').description('Revoke user access to a dome')
  .action((username, dome) => {
    const store = new UserStore();
    store.load();
    try {
      store.removePermission(username, dome);
      store.save();
      console.log(`Revoked access to "${dome}" from ${username}.`);
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

userCmd.command('permissions <username>').description('List permissions for a user')
  .option('--json', 'JSON output')
  .action((username, opts) => {
    const store = new UserStore();
    store.load();
    try {
      const perms = store.getPermissions(username);
      const entries = Object.entries(perms);
      if (entries.length === 0) { console.log(`No permissions for "${username}".`); return; }
      if (opts.json) {
        console.log(JSON.stringify(entries.map(([dome, p]) => ({ dome, role: p.role })), null, 2));
      } else {
        console.log(`Permissions for ${username}:`);
        for (const [dome, p] of entries) {
          console.log(`  ${dome}: ${p.role}`);
        }
      }
    } catch (e) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });


// ── Dome management commands (SE-291 S3) ──
const domeCmd = program.command('dome').description('Manage context domes');

domeCmd.command('create <name>').description('Create a new dome')
  .option('--path <dir>', 'Dome directory path')
  .option('--description <text>', 'Dome description', '')
  .option('--confidentiality <level>', 'N1|N2|N3|N4', 'N2')
  .action((name, opts) => {
    const registry = new DomeRegistry();
    const registryFile = registry.getFilePath();
    if (isGitTracked(registryFile)) {
      console.error(`Error: ${registryFile} está versionado en git; el registro de cúpulas guarda rutas locales.`);
      console.error('  Sácalo del índice (git rm --cached) y añádelo a .gitignore, o copia savia-vaults.domes.example.json fuera del repo.');
      process.exit(1);
    }
    const domePath = opts.path || path.join(process.cwd(), 'vaults', name);
    fs.mkdirSync(domePath, { recursive: true });

    try {
      registry.load();
    } catch {
    }

    try {
      registry.add({
        name,
        path: domePath,
        description: opts.description,
        confidentiality: opts.confidentiality,
        active: true,
      });
      registry.save();
      console.log(`Dome "${name}" created at ${domePath}`);
      console.log(`  Registry (local, no versionado): ${registryFile}`);
      if (!registry.defaultDome) {
        registry.setDefault(name);
        console.log(`  Set as default dome`);
      }
    } catch (e: unknown) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

domeCmd.command('list').description('List registered domes')
  .option('--json', 'JSON output')
  .action((opts) => {
    const registry = new DomeRegistry();
    try { registry.load(); } catch { console.log('No domes registered.'); return; }
    const domes = registry.list();
    if (domes.length === 0) { console.log('No domes registered.'); return; }
    if (opts.json) {
      console.log(JSON.stringify(domes.map(d => ({ name: d.name, path: d.path, description: d.description, confidentiality: d.confidentiality, active: d.active })), null, 2));
    } else {
      console.log(`Domes (default: ${registry.defaultDome}):`);
      for (const d of domes) {
        console.log(`  ${d.active ? '●' : '○'} ${d.name}  [${d.confidentiality}]  ${d.path}${d.name === registry.defaultDome ? '  ← default' : ''}`);
      }
    }
  });

domeCmd.command('info <name>').description('Show dome details')
  .option('--json', 'JSON output')
  .action((name, opts) => {
    const registry = new DomeRegistry();
    registry.load();
    const dome = registry.get(name);
    if (!dome) { console.error(`Dome "${name}" not found.`); process.exit(1); }
    if (opts.json) {
      console.log(JSON.stringify({ name: dome.name, path: dome.path, description: dome.description, confidentiality: dome.confidentiality, active: dome.active, schemaDir: dome.schemaDir, isDefault: name === registry.defaultDome }, null, 2));
    } else {
      console.log(`Name: ${dome.name}`);
      console.log(`Path: ${dome.path}`);
      console.log(`Description: ${dome.description || '(none)'}`);
      console.log(`Confidentiality: ${dome.confidentiality}`);
      console.log(`Active: ${dome.active ? 'yes' : 'no'}`);
      console.log(`Default: ${name === registry.defaultDome ? 'yes' : 'no'}`);
    }
  });

domeCmd.command('delete <name>').description('Remove dome from registry')
  .option('--force', 'Also delete dome files from disk')
  .action((name, opts) => {
    const registry = new DomeRegistry();
    registry.load();
    const dome = registry.get(name);
    if (!dome) { console.error(`Dome "${name}" not found.`); process.exit(1); }
    try {
      registry.remove(name);
      registry.save();
      console.log(`Dome "${name}" removed from registry.`);
      if (opts.force && dome.active) {
        fs.rmSync(dome.path, { recursive: true, force: true });
        console.log(`  Files deleted: ${dome.path}`);
      }
    } catch (e: unknown) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });

domeCmd.command('set-default <name>').description('Set default dome')
  .action((name) => {
    const registry = new DomeRegistry();
    registry.load();
    try {
      registry.setDefault(name);
      console.log(`Default dome set to "${name}".`);
    } catch (e: unknown) {
      console.error(`Error: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
  });


// ── Confidentiality commands (SE-291 S7) ──
const confCmd = program.command('confidentiality').description('Manage dome confidentiality levels');

confCmd.command('set <level>').description('Set confidentiality level for a dome')
  .option('--dome <name>', 'Dome name')
  .action((level, opts) => {
    if (!['N1', 'N2', 'N3', 'N4'].includes(level)) {
      console.error('Level must be N1, N2, N3, or N4.');
      process.exit(1);
    }
    const registry = new DomeRegistry();
    registry.load();
    const domeName = opts.dome || registry.getDefaultName();
    const dome = registry.get(domeName);
    if (!dome) { console.error(`Dome "${domeName}" not found.`); process.exit(1); }
    dome.confidentiality = level as 'N1'|'N2'|'N3'|'N4';
    registry.save();
    console.log(`Confidentiality for "${domeName}" set to ${level}.`);
  });

confCmd.command('get').description('Get confidentiality level for a dome')
  .option('--dome <name>', 'Dome name')
  .action((opts) => {
    const registry = new DomeRegistry();
    registry.load();
    const domeName = opts.dome || registry.getDefaultName();
    const dome = registry.get(domeName);
    if (!dome) { console.error(`Dome "${domeName}" not found.`); process.exit(1); }
    console.log(`${dome.name}: ${dome.confidentiality}`);
  });

confCmd.command('audit').description('Audit confidentiality across all domes')
  .action(() => {
    const registry = new DomeRegistry();
    registry.load();
    const audit = ConfidentialityGuard.audit(registry.list());
    console.log(ConfidentialityGuard.formatAudit(audit));
  });


// ── Audit commands (SE-293 S2) ──
const auditCmd = program.command('audit').description('Query access audit logs');

auditCmd.command('show').description('Show audit entries')
  .option('--username <name>', 'Filter by username')
  .option('--dome <name>', 'Filter by dome')
  .option('--action <action>', 'Filter by action (read|write|admin)')
  .option('--result <result>', 'Filter by result (allowed|denied)')
  .option('--since <date>', 'From date (YYYY-MM-DD)')
  .option('--until <date>', 'To date (YYYY-MM-DD)')
  .option('--last <N>', 'Last N entries (default 50)')
  .option('--json', 'JSON output')
  .action((opts: any) => {
    const logger = new AuditLogger();
    const entries = logger.query({
      username: opts.username,
      dome: opts.dome,
      action: opts.action,
      result: opts.result,
      since: opts.since,
      until: opts.until,
      last: opts.last ? parseInt(opts.last, 10) : 50,
    });
    if (opts.json) {
      console.log(JSON.stringify(entries, null, 2));
    } else {
      if (entries.length === 0) { console.log('No audit entries found.'); return; }
      for (const e of entries) {
        const icon = e.result === 'allowed' ? 'OK' : 'NO';
        console.log(`[${e.ts.slice(0,19)}] ${icon} ${e.username.padEnd(12)} ${e.dome.padEnd(16)} ${e.action.padEnd(6)} ${e.reason || ''}`);
      }
    }
  });

auditCmd.command('stats').description('Show audit statistics')
  .option('--since <date>', 'From date (YYYY-MM-DD)')
  .option('--until <date>', 'To date (YYYY-MM-DD)')
  .option('--json', 'JSON output')
  .action((opts: any) => {
    const logger = new AuditLogger();
    const stats = logger.stats({ since: opts.since, until: opts.until });
    if (opts.json) {
      console.log(JSON.stringify(stats, null, 2));
    } else {
      console.log('Audit Summary');
      console.log('='.repeat(60));
      console.log(`Total: ${stats.total} accesses (${stats.allowed} allowed, ${stats.denied} denied)`);
      console.log('');
      if (Object.keys(stats.byUser).length > 0) {
        console.log('By user:');
        for (const [u, c] of Object.entries(stats.byUser)) {
          console.log(`  ${u}: ${c}`);
        }
        console.log('');
      }
      if (Object.keys(stats.byDome).length > 0) {
        console.log('By dome:');
        for (const [d, c] of Object.entries(stats.byDome)) {
          console.log(`  ${d}: ${c}`);
        }
        console.log('');
      }
      if (Object.keys(stats.byAction).length > 0) {
        console.log('By action:');
        for (const [a, c] of Object.entries(stats.byAction)) {
          console.log(`  ${a}: ${c}`);
        }
      }
    }
  });


// ── Quota commands (SE-293 S4) ──
userCmd.command('quota <username>').description('Show or configure user quotas')
  .option('--set-rpm <N>', 'Set requests per minute')
  .option('--set-rph <N>', 'Set requests per hour')
  .option('--set-rpd <N>', 'Set requests per day')
  .option('--reset', 'Reset counters to zero')
  .option('--json', 'JSON output')
  .action((username: string, opts: any) => {
    const store = new UserQuotaStore();
    store.load();

    if (opts.reset) {
      store.resetCounters(username);
      console.log(`Quota counters reset for "${username}".`);
      return;
    }

    if (opts.setRpm || opts.setRph || opts.setRpd) {
      const config: Record<string, number> = {};
      if (opts.setRpm) config.requestsPerMinute = parseInt(opts.setRpm, 10);
      if (opts.setRph) config.requestsPerHour = parseInt(opts.setRph, 10);
      if (opts.setRpd) config.requestsPerDay = parseInt(opts.setRpd, 10);
      store.setConfig(username, config);
      store.persist();
      console.log(`Quotas updated for "${username}".`);
    }

    const config = store.getConfig(username);
    const status = store.check(username);

    if (opts.json) {
      console.log(JSON.stringify({ username, config, remaining: status.remaining }, null, 2));
    } else {
      console.log(`Quotas for ${username}:`);
      console.log(`  Requests per minute:  ${config.requestsPerMinute === 0 ? 'unlimited' : String(config.requestsPerMinute)}`);
      console.log(`  Requests per hour:    ${config.requestsPerHour === 0 ? 'unlimited' : String(config.requestsPerHour)}`);
      console.log(`  Requests per day:     ${config.requestsPerDay === 0 ? 'unlimited' : String(config.requestsPerDay)}`);
      if (status.warning) console.log(`  WARNING: ${status.warning}`);
    }
  });


// SE-411 G5: los comandos `rag` viven en ./rag.ts y se cargan sin el resto de la CLI.
program.command('rag').description('Savia RAG (SE-410/411): búsqueda híbrida y ciclo de vida de embeddings — ver `savia-vaults rag --help`');

program.parse();
