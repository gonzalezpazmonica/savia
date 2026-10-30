import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { UserStore } from '../../src/auth/store.js';
import { AccessController } from '../../src/auth/controller.js';
import { DomeRegistry } from '../../src/registry/domes.js';
import { RagService } from '../../src/rag/service.js';
import { HashEmbedder } from '../../src/rag/embedder.js';
import { FileStore } from '../../src/files/store.js';
import { A2AServer } from '../../src/server/a2a.js';
import { check, config } from './common.js';

const project = fileURLToPath(new URL('../../', import.meta.url));
const text = (r: any): string => r.content.map((c: any) => c.text ?? '').join('\n');

/** Transporte MCP real y HTTP A2A real; no reemplaza handlers ni la autorización. */
export async function surfaces() {
  const root = path.join(process.env.AUDIT_TMP!, 'surfaces');
  const schema = path.join(root, 'schema');
  fs.mkdirSync(schema, { recursive: true });
  const domes: Record<string, any> = {};
  for (const name of ['open', 'restricted', 'ungranted']) {
    const dir = path.join(root, name);
    fs.mkdirSync(dir);
    domes[name] = { name, path: dir, description: '', confidentiality: name === 'restricted' ? 'N3' : 'N2', schemaDir: schema,
      rag: { enabled: true, model: 'audit', inlineSyncBudget: 0, halfLifeDays: 0 }, files: { enabled: true, scan: 'off' } };
    fs.writeFileSync(path.join(dir, 'public.md'), '---\nconfidentiality: N2\nentity: { id: visible-entity, type: document }\n---\n# Visible\nsurfaceprobe visible contenido. [[target.md]]');
  }
  const put = (p: string, s: string) => fs.writeFileSync(path.join(domes.open.path, p), s);
  put('target.md', '# Destino\nsurfaceprobe destino');
  put('by-name.md', '# Por nombre\nsurfaceprobe enlace [[by-target]]');
  put('by-target.md', '# Por nombre destino\nsurfaceprobe destino-nombre');
  put('hidden.md', '---\nconfidentiality: N3\nentity: { id: hidden-entity, type: document }\n---\n# Oculta\nsurfaceprobe hidden-sentinel [[target.md]]');
  put('old.md', '---\nstatus: deprecated\nentity: { id: old-entity, type: document }\n---\n# Obsoleta\nsurfaceprobe old-sentinel [[target.md]]');
  put('invalid.md', '---\nconfidentiality: UNKNOWN\nentity: { id: invalid-entity, type: document }\n---\n# Desconocida\nsurfaceprobe invalid-sentinel');
  const registryPath = path.join(root, 'domes.json');
  fs.writeFileSync(registryPath, JSON.stringify({ version: 1, defaultDome: 'open', domes }));
  const registry = new DomeRegistry(registryPath);
  registry.load();
  const users = new UserStore(path.join(root, 'savia-vaults.users.json'));
  const token = users.createUser('audit-reader');
  users.setPermission('audit-reader', 'open', 'reader');
  users.setPermission('audit-reader', 'restricted', 'reader');
  users.save();
  // La misma extracción está restringida por ACL; no se copia su texto a Markdown.
  const files = new FileStore({ home: process.env.SAVIA_FILES_HOME!, keysHome: process.env.SAVIA_FILES_KEYS_HOME!, dome: 'open' });
  const doc = files.add({ name: 'acl-hidden.txt', bytes: Buffer.from('surfaceprobe file-hidden-sentinel') });
  files.saveExtraction(doc.revision.id, { units: [{ locator: { type: 'lines', from: 1, to: 1 }, kind: 'text', text: 'surfaceprobe file-hidden-sentinel' }] },
    { status: 'READY', method: 'synthetic', units: 1, extracted: 1, skipped: [] }, doc.document.id);
  files.setPolicy(doc.document.id, { readers: [] });
  const partial = files.add({ name: 'fragmento.txt', bytes: Buffer.from('surfaceprobe partial-sentinel') });
  files.saveExtraction(partial.revision.id, { units: [{ locator: { type: 'page', page: 1 }, kind: 'text', text: 'surfaceprobe partial-sentinel' }] },
    { status: 'PARTIAL', method: 'synthetic', units: 2, extracted: 1, skipped: [{ reason: 'audit-omitted-page', count: 1 }] }, partial.document.id);
  const rag = new RagService({ domes: () => Object.values(domes), home: process.env.SAVIA_RAG_HOME!, env: process.env,
    embedderFactory: cfg => new HashEmbedder(64, cfg, cfg.model) });
  for (const name of Object.keys(domes)) await rag.sync(name);
  const childEnv = Object.fromEntries(Object.entries(process.env).filter(([k, v]) => k.startsWith('SAVIA_') && typeof v === 'string')) as Record<string, string>;
  // Solo las variables de aislamiento anteriores; nunca credenciales heredadas.
  for (const k of Object.keys(childEnv)) if (!['SAVIA_RAG_HOME', 'SAVIA_FILES_HOME', 'SAVIA_FILES_KEYS_HOME', 'SAVIA_SEARCH_CACHE', 'SAVIA_VAULTS_HOME'].includes(k)) delete childEnv[k];
  childEnv.PATH = process.env.PATH ?? '';
  childEnv.HOME = process.env.HOME!;
  childEnv.SAVIA_AUTH_TOKEN = token;
  childEnv.SAVIA_RAG_TEST_PROVIDER = 'hash';
  const transport = new StdioClientTransport({ command: process.execPath,
    args: ['--import', path.join(project, 'node_modules/tsx/dist/loader.mjs'), path.join(project, 'src/cli/index.ts'), 'serve', '--transport', 'mcp', '--domes', registryPath],
    cwd: root, env: childEnv, stderr: 'pipe' });
  // Drena stderr sin exportar rutas ni logs de credenciales.
  transport.stderr?.on('data', () => undefined);
  const client = new Client({ name: 'svtc00-audit', version: '1' });
  const observations: Record<string, any> = {};
  const requests: [string, Record<string, unknown>][] = [
    ['vault_read', { path: 'public.md' }], ['vault_search', { query: 'surfaceprobe', maxResults: 20 }],
    ['vault_list', {}], ['vault_graph', { action: 'search', query: 'entity' }],
    ['vault_query', { expression: 'hidden-entity.type' }], ['vault_stats', {}],
  ];
  try {
    await client.connect(transport);
    for (const [name, args] of requests) {
      const r = await client.callTool({ name, arguments: { ...args, vault: 'open' } });
      check(`surface-${name}-ok`, Boolean(r.isError), false);
      observations[name] = { response: text(r) };
      for (const dome of ['restricted', 'ungranted']) {
        const denied = await client.callTool({ name, arguments: { ...args, vault: dome } });
        check(`surface-${name}-${dome}`, denied.isError, true);
        observations[name][dome] = text(denied);
      }
    }
    const hidden = await client.callTool({ name: 'vault_read', arguments: { vault: 'open', path: 'hidden.md' } });
    check('surface-read-hidden', hidden.isError, true);
    const old = await client.callTool({ name: 'vault_read', arguments: { vault: 'open', path: 'old.md', includeStale: false } });
    check('surface-read-old', text(old).includes('old-sentinel'), true);
    const back = await client.callTool({ name: 'vault_read', arguments: { vault: 'open', path: 'target.md' } });
    const backBody = JSON.parse(text(back));
    check('surface-backlinks-hidden', JSON.stringify(backBody.backlinks).includes('hidden.md'), false);
    check('surface-backlinks-old', JSON.stringify(backBody.backlinks).includes('old.md'), true);
    observations.backlinks = backBody;
    const byName = JSON.parse(text(await client.callTool({ name: 'vault_read', arguments: { vault: 'open', path: 'by-target.md' } })));
    // Hallazgo nuevo: [[nombre]] nunca resuelve backlinks (compara destino con ruta .md).
    check('surface-backlinks-by-name-defect', byName.backlinks, undefined);
    observations.backlinksByName = byName;
    const graph = JSON.parse(observations.vault_graph.response);
    check('surfaces', graph.some((n: any) => n.id === 'hidden-entity'), false);
    check('surface-graph-visible', graph.some((n: any) => n.id === 'visible-entity'), true);
    check('surface-graph-old', graph.some((n: any) => n.id === 'old-entity'), true);
    const oldQuery = await client.callTool({ name: 'vault_query', arguments: { vault: 'open', expression: 'old-entity.type', includeStale: false } });
    check('surface-query-old', text(oldQuery).includes('node:old-entity'), true);
    observations.oldQuery = text(oldQuery);
    check('surface-query-hidden', observations.vault_query.response.includes('node:hidden-entity'), false);
    const stats = JSON.parse(observations.vault_stats.response);
    check('surface-stats-hidden', stats.outOfLevel, 1);
    const search = JSON.parse(observations.vault_search.response);
    check('surface-search-hidden', search.some((h: any) => h.path === 'hidden.md'), false);
    check('surface-search-old', search.some((h: any) => h.path === 'old.md'), true);
    const list = JSON.parse(observations.vault_list.response); 
    check('surface-list-hidden', list.includes('hidden.md'), false);
    check('surface-list-old', list.includes('old.md'), true);
    check('surface-search-invalid', search.some((h: any) => h.path === 'invalid.md'), false);
    check('surface-list-invalid', list.includes('invalid.md'), false);
    for (const includeStale of [false, true]) {
      for (const fields of ['full', 'lean']) {
        const r = await client.callTool({ name: 'vault_rag', arguments: { query: 'surfaceprobe', domes: ['open', 'restricted', 'ungranted'], mode: 'bm25', k: 20, fields, includeStale, maxChars: 30000 } });
        check(`surface-rag-${includeStale}-${fields}-ok`, Boolean(r.isError), false);
        const b = JSON.parse(text(r));
        observations[`vault_rag_${includeStale}_${fields}`] = b;
        const hits = b.results[0].hits;
        check(`surface-rag-hidden-${includeStale}-${fields}`, hits.some((h: any) => h.path === 'hidden.md'), false);
        check(`surface-rag-acl-${includeStale}-${fields}`, hits.some((h: any) => h.source?.documentId === doc.document.id), false);
        check(`surface-rag-invalid-${includeStale}-${fields}`, hits.some((h: any) => h.path === 'invalid.md'), false);
        check(`surface-rag-old-${includeStale}-${fields}`, hits.some((h: any) => h.path === 'old.md'), includeStale);
        check(`surface-rag-denied-${includeStale}-${fields}`, b.domes.filter((d: any) => d.status === 'denied').length, 2);
        const hit = hits.find((h: any) => h.source?.documentId === partial.document.id);
        check(`surface-rag-partial-${includeStale}-${fields}`, Boolean(hit), true);
        check(`surface-rag-partial-status-${includeStale}-${fields}`, JSON.stringify(hit).includes('PARTIAL') || JSON.stringify(hit).includes('audit-omitted-page'), false);
      }
    }
    // SE-480 extra: el proceso vivo no relee la configuración RAG tras modificar el registro.
    domes.open.rag.enabled = false;
    fs.writeFileSync(registryPath, JSON.stringify({ version: 1, defaultDome: 'open', domes }));
    const afterRegistryEdit = await client.callTool({ name: 'vault_rag_status', arguments: { domes: ['open'] } });
    const status = JSON.parse(text(afterRegistryEdit));
    check('surface-registry-reload', status[0].enabled, true);
    observations.registryReload = { configuredEnabled: false, liveEnabled: status[0].enabled };
  } finally {
    await client.close();
  }
  // A2A: el registro en memoria original sigue enabled; las vistas no son RAG.
  const access = new AccessController(users, registry);
  const a2a = new A2AServer(config(domes.open.path), registry, { access });
  try {
    const { url } = await a2a.start(0, '127.0.0.1');
    const get = async (route: string, auth = true) => {
      const r = await fetch(url + route, { headers: auth ? { authorization: `Bearer ${token}` } : {} });
      return { status: r.status, body: await r.json() };
    };
    const search = await get('/search?q=surfaceprobe&dome=open&includeStale=false');
    check('surface-a2a-ok', search.status, 200);
    check('surface-a2a-hidden', search.body.results.some((r: any) => r.path === 'hidden.md'), false);
    check('surface-a2a-invalid', search.body.results.some((r: any) => r.path === 'invalid.md'), false);
    check('surface-a2a-old', search.body.results.some((r: any) => r.path === 'old.md'), true);
    const denied = await get('/search?q=surfaceprobe&dome=restricted');
    check('surface-a2a-level', denied.status, 403);
    const ungranted = await get('/search?q=surfaceprobe&dome=ungranted');
    check('surface-a2a-permission', ungranted.status, 403);
    const anonymous = await get('/search?q=surfaceprobe&dome=open', false);
    check('surface-a2a-auth', anonymous.status, 401);
    const hidden = await get('/context/audit/hidden.md?dome=open');
    check('surface-a2a-hidden-read', hidden.status, 500);
    const publicRead = await get('/context/audit/public.md?dome=open');
    check('surface-a2a-read', publicRead.status, 200);
    const oldRead = await get('/context/audit/old.md?dome=open&includeStale=false');
    check('surface-a2a-read-old', oldRead.body.content.includes('old-sentinel'), true);
    const stats = await get('/stats?dome=open');
    check('surface-a2a-stats', stats.status, 400);
    observations.a2a = { search, denied, ungranted, anonymous, hidden, publicRead, oldRead, stats };
  } finally { await a2a.stop(); }
  return { verdict: 'CONFIRMED', observations,
    scope: 'Con usuarios: reader N2, reader N3 denegado, N2 sin grant denegado; Files viven fuera del árbol Markdown. A2A /stats ignora dome y no funciona en modo usuario.' };
}
