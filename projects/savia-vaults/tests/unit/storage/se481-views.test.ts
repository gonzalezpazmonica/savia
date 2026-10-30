// SE-481 AC-1/AC-2/AC-3/AC-6 — una clasificación explícita no interpretable deja la nota en
// cuarentena en todas las vistas (almacén, búsqueda, grafo, query, stats, A2A); una nota sin
// clasificación se sirve igual que antes; `write` rechaza la clasificación inválida.
// Fixture sintético: eval/fixtures/malformed-meta.json.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { VaultStorage } from '../../../src/storage/index.js';
import { SearchEngine } from '../../../src/search/index.js';
import { KnowledgeGraph } from '../../../src/knowledge/graph.js';
import { QueryEngine } from '../../../src/knowledge/query.js';
import { DomeRegistry } from '../../../src/registry/domes.js';
import { A2AServer } from '../../../src/server/a2a.js';
import type { VaultConfig } from '../../../src/types.js';

interface FixtureNote { content: string; kind: string; diagnostic?: string; level?: string }
const fixture = JSON.parse(fs.readFileSync(path.resolve('eval/fixtures/malformed-meta.json'), 'utf-8')) as {
  domeLevel: string; notes: Record<string, FixtureNote>;
};
const canary = (content: string) => content.match(/(CANARIO|VISIBLE|OCULTA)-[A-Z0-9]+/)![0];
const quarantined = Object.entries(fixture.notes).filter(([, n]) => n.diagnostic);
const absent = Object.entries(fixture.notes).filter(([, n]) => n.kind === 'ABSENT');

// AC-1: `[N4` (YAML roto); AC-2: N7, [N2], anchura cero; además «secreto».
const AC = (p: string) => (p === 'mal/yaml-roto.md' ? 'AC-1' : 'AC-2');

describe('SE-481 cuarentena en todas las vistas', () => {
  let root: string;
  let vault: string;
  let cfg: VaultConfig;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se481-views-'));
    vault = path.join(root, 'D');
    for (const [p, n] of Object.entries(fixture.notes)) {
      fs.mkdirSync(path.dirname(path.join(vault, p)), { recursive: true });
      // cada nota enlaza a la abierta: la cuarentena tampoco puede filtrarse por backlinks
      fs.writeFileSync(path.join(vault, p), `${n.content}\nEnlace a [[ok/n2]].\n`);
    }
    const schemaDir = path.join(root, 'schema');
    fs.mkdirSync(schemaDir);
    fs.writeFileSync(path.join(schemaDir, 'document.yaml'), 'type: document\nlabel: Documento\nproperties:\n  title: {type: string}\n');
    process.env.SAVIA_SEARCH_CACHE = path.join(root, 'cache');
    cfg = { name: 'D', path: vault, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1 << 20, confidentiality: fixture.domeLevel, schemaDir };
  });
  afterEach(() => { delete process.env.SAVIA_SEARCH_CACHE; fs.rmSync(root, { recursive: true, force: true }); });

  it.each(quarantined)('%s: list/read/diff/log/stats no la sirven', async (p, n) => {
    const st = new VaultStorage(cfg);
    expect(await st.list()).not.toContain(p);
    await expect(st.read(p)).rejects.toThrow(/Note not found/);
    await expect(st.diff(p)).rejects.toThrow(/Note not found/);
    await expect(st.log(p)).rejects.toThrow(/Note not found/);
    const stats = await st.stats();
    expect(stats.noteCount).toBe(Object.keys(fixture.notes).length - quarantined.length - 1); // -1: N4B fuera de nivel
    expect(stats.quarantined).toBe(quarantined.length);
    expect(stats.outOfLevel).toBe(1);
    expect(JSON.stringify(stats)).not.toContain(canary(n.content));
    expect(AC(p)).toMatch(/AC-[12]/);
  });

  it.each(quarantined)('%s: búsqueda, etiquetas, grafo y query no la incluyen', async (p, n) => {
    const word = canary(n.content);
    const se = new SearchEngine(cfg);
    se.buildIndex();
    expect(se.search({ query: word })).toEqual([]);
    const g = new KnowledgeGraph(cfg);
    const snap = await g.build();
    const paths = [...snap.nodes.values()].map(x => x.path);
    expect(paths).not.toContain(p);
    expect(JSON.stringify([...snap.nodes.values()])).not.toContain(p);
    const q = new QueryEngine(cfg);
    await q.ensureLoaded();
    const res = await q.query(word);
    expect(res.plan.type).toBe('search');
    expect(JSON.stringify(res.results)).not.toContain(p);
    expect(JSON.stringify(res.results)).not.toContain(word); // la cabecera repite la consulta; los resultados no
    expect(res.outputMarkdown).not.toContain(p);
  });

  it.each(quarantined)('%s: A2A no la lee ni la encuentra', async (p, n) => {
    const registry = path.join(root, 'domes.json');
    fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'D', domes: { D: { name: 'D', path: vault, description: '', confidentiality: fixture.domeLevel } } }));
    const reg = new DomeRegistry(registry);
    reg.load();
    const a2a = new A2AServer({ ...cfg, name: 'solo', path: path.join(root, 'single') }, reg);
    await expect(a2a.readDome('D', p)).rejects.toThrow(/Note not found/);
    expect(a2a.searchAll({ query: canary(n.content) }, 'D')).toEqual([]);
  });

  it('AC-1: el informe de salud cuenta por código, sin rutas', () => {
    const q = new VaultStorage(cfg).quarantine();
    expect(q.byCode).toEqual({ 'yaml-unparsable': 1, 'unknown-level': 2, 'non-string': 1, 'forbidden-char': 1 });
    expect(q.total).toBe(quarantined.length);
    expect(JSON.stringify(q.byCode)).not.toMatch(/mal\/|CANARIO/);
  });

  it('la cuarentena aplica también sin nivel de cúpula (CLI local)', async () => {
    const { confidentiality: _c, ...local } = cfg;
    const st = new VaultStorage(local);
    const listed = await st.list();
    for (const [p] of quarantined) expect(listed).not.toContain(p);
    expect(listed).toContain('ok/n4b-minus.md'); // sin nivel de cúpula, el nivel válido no oculta
  });

  it.each(absent)('AC-3 regresión: %s (sin clasificación) se sirve igual que en main', async (p, n) => {
    const word = canary(n.content);
    const st = new VaultStorage(cfg);
    expect(await st.list()).toContain(p);
    expect((await st.read(p)).content).toContain(word);
    const se = new SearchEngine(cfg);
    se.buildIndex();
    expect(se.search({ query: word }).map(r => r.path)).toContain(p);
    const snap = await new KnowledgeGraph(cfg).build();
    expect([...snap.nodes.values()].map(x => x.path)).toContain(p);
  });

  it.each(quarantined)('AC-6: write rechaza %s y no escribe nada', async (p, n) => {
    const st = new VaultStorage(cfg);
    const target = `nueva/${path.basename(p)}`;
    await expect(st.write(target, n.content)).rejects.toThrow(/INVALID_CLASSIFICATION/);
    expect(fs.existsSync(path.join(vault, target))).toBe(false);
    // tampoco sin nivel de cúpula
    const { confidentiality: _c, ...local } = cfg;
    await expect(new VaultStorage(local).write(target, n.content)).rejects.toThrow(/INVALID_CLASSIFICATION/);
    expect(fs.existsSync(path.join(vault, target))).toBe(false);
  });

  it('AC-6 caso negativo: una clasificación válida o ausente se escribe', async () => {
    const st = new VaultStorage(cfg);
    await st.write('nueva/ok.md', '---\nconfidentiality: n2\n---\nbien\n');
    await st.write('nueva/plano.md', 'sin frontmatter\n');
    await st.write('nueva/roto-sin-clave.md', '---\ntitle: a: b: c\n---\nbien\n');
    expect(await st.list()).toEqual(expect.arrayContaining(['nueva/ok.md', 'nueva/plano.md', 'nueva/roto-sin-clave.md']));
  });
});
