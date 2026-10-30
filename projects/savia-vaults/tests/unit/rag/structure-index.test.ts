// SE-489 M3 — StructureIndex: árbol determinista, binding a la generación, cifrado y ciclo de vida (AC-3)
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';
import {
  StructureIndex, buildDocumentTree, buildStructure, ensureStructure, gcStructure, structurePath,
} from '../../../src/rag/structure-index.js';
import { openProjectionSource } from '../../../src/rag/binary-store.js';
import { FlatVectorStore, domeDir, readActive } from '../../../src/rag/store.js';
import { chunkMarkdown } from '../../../src/rag/chunker.js';
import { RagService, type RagDomeRef } from '../../../src/rag/service.js';
import { HashEmbedder } from '../../../src/rag/embedder.js';
import type { Chunk } from '../../../src/rag/types.js';
import { makeStore, xorCipher } from './quant-fixture.js';

const DOC = `---\ntitle: Contrato\n---\n# Contrato\n\nIntro del contrato con texto suficiente para un chunk propio. ${'x '.repeat(80)}\n\n## Cláusula 1. Objeto\n\nObjeto ${'a '.repeat(120)}\n\n### Detalle\n\nDetalle ${'b '.repeat(120)}\n\n## Cláusula 2. Precio\n\nPrecio del Anexo II ${'c '.repeat(120)}\n\n## Notas\n\nPrimera nota ${'d '.repeat(120)}\n\n## Cláusula 3. Fin\n\nFin ${'e '.repeat(120)}\n\n## Notas\n\nSegunda nota ${'f '.repeat(120)}\n`;

const chunksOf = (rel: string, raw: string): Chunk[] => chunkMarkdown(rel, raw, { chunkChars: 400, overlap: 0, minChars: 50 });

describe('buildDocumentTree (M3, puro)', () => {
  it('documento → sección → unidad con padres, hijos y localizadores', () => {
    const nodes = buildDocumentTree('D', 'c.md', chunksOf('c.md', DOC));
    const doc = nodes[0];
    expect(doc.kind).toBe('document');
    expect(doc.title).toBe('Contrato');
    const sections = nodes.filter(n => n.kind === 'section');
    expect(sections.map(s => s.title)).toEqual(['Cláusula 1. Objeto', 'Detalle', 'Cláusula 2. Precio', 'Notas', 'Cláusula 3. Fin', 'Notas']);
    const detalle = sections.find(s => s.title === 'Detalle')!;
    expect(nodes.find(n => n.nodeId === detalle.parent)!.title).toBe('Cláusula 1. Objeto');
    expect(detalle.locator).toBe('section:Cláusula 1. Objeto › Detalle');
    // Mismo encabezado repetido en otro punto del documento: otra sección, con ocurrencia en el localizador.
    const notas = sections.filter(s => s.title === 'Notas');
    expect(notas[0].nodeId).not.toBe(notas[1].nodeId);
    expect(notas[1].locator).toBe('section:Notas@1');
    const units = nodes.filter(n => n.kind === 'unit');
    expect(units.length).toBe(chunksOf('c.md', DOC).length);
    for (const u of units) {
      expect(u.chunkId).toMatch(/^c\.md#\d+$/);
      expect(u.locator).toMatch(/^#\d+ /);
      expect(u.contentHash).toMatch(/^sha256:[0-9a-f]{64}$/);
      expect(nodes.find(n => n.nodeId === u.parent)!.children).toContain(u.nodeId);
    }
  });

  it('determinista y nodeId estable: un cambio de contenido cambia contentHash, no nodeId', () => {
    const a = buildDocumentTree('D', 'c.md', chunksOf('c.md', DOC));
    const b = buildDocumentTree('D', 'c.md', chunksOf('c.md', DOC));
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
    const c = buildDocumentTree('D', 'c.md', chunksOf('c.md', DOC.replace('Precio del Anexo II', 'Precio del Anexo III')));
    expect(c.map(n => n.nodeId)).toEqual(a.map(n => n.nodeId));
    const changed = c.filter((n, i) => n.contentHash !== a[i].contentHash).map(n => n.kind === 'unit' ? 'unit' : n.title);
    // La unidad cambiada, su sección y el documento (Merkle); nada más.
    expect(changed).toEqual(['Contrato', 'Cláusula 2. Precio', 'unit']);
    // Otra cúpula u otro documento: otros identificadores.
    expect(buildDocumentTree('E', 'c.md', chunksOf('c.md', DOC))[0].nodeId).not.toBe(a[0].nodeId);
  });

  it('Savia Files: secciones por página/hoja desde los localizadores; líneas cuelgan del documento', () => {
    const src = (locator: Chunk['source'] extends infer S ? S extends { locator: infer L } ? L : never : never, end?: unknown) =>
      ({ kind: 'file' as const, documentId: 'd1', revisionId: 'r1', name: 'x.pdf', locator, ...(end ? { locatorEnd: end as typeof locator } : {}) });
    const mk = (i: number, source: ReturnType<typeof src>): Chunk => ({
      id: `files/d1#${i}`, path: 'files/d1', ordinal: i, heading: `x.pdf › ${i}`, text: `t${i}`, embedText: '', hash: '', meta: { title: 'x.pdf', modified: '' }, source,
    });
    const nodes = buildDocumentTree('D', 'files/d1', [
      mk(0, src({ type: 'page', page: 1 })), mk(1, src({ type: 'page', page: 1 })), mk(2, src({ type: 'page', page: 2 })),
      mk(3, src({ type: 'cell', sheet: 'Hoja1', cell: 'A1' }, { type: 'cell', sheet: 'Hoja1', cell: 'B4' })),
      mk(4, src({ type: 'lines', from: 1, to: 9 })),
    ]);
    const secs = nodes.filter(n => n.kind === 'section');
    expect(secs.map(s => s.locator)).toEqual(['page:1', 'page:2', 'sheet:Hoja1']);
    expect(nodes.filter(n => n.kind === 'unit').map(n => n.locator)).toEqual(['page:1', 'page:1', 'page:2', 'cell:Hoja1!A1..cell:Hoja1!B4', 'lines:1-9']);
    const lines = nodes.find(n => n.locator === 'lines:1-9')!;
    expect(lines.parent).toBe(nodes[0].nodeId);
    expect(secs[0].children.length).toBe(2);
  });

  it('navegación: padre, hijos, hermanos y documentos hermanos', () => {
    const chunks = [...chunksOf('ct/contrato.md', DOC), ...chunksOf('ct/anexo-I.md', '# Anexo I\n\nTabla S1 1 h.'), ...chunksOf('otro/x.md', '# X\n\ny')];
    const docs = buildStructure('D', chunks);
    const idx = new StructureIndex({ nodeCount: 0 } as never, docs);
    const unit = idx.unitOf('ct/contrato.md#3')!;
    const sec = idx.sectionOf('ct/contrato.md#3')!;
    expect(idx.parent(unit.nodeId)!.nodeId).toBe(sec.nodeId);
    expect(idx.children(sec.nodeId).map(n => n.nodeId)).toContain(unit.nodeId);
    expect(idx.siblings(sec.nodeId).map(n => n.title)).not.toContain(sec.title);
    expect(idx.siblingDocuments('ct/contrato.md')).toEqual(['ct/anexo-I.md']);
    expect(idx.siblingDocuments('otro/x.md')).toEqual([]);
    expect(idx.node('n_inexistente')).toBeUndefined();
  });
});

describe('StructureIndex persistido (M3)', () => {
  let home: string;
  beforeEach(() => { home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m3-struct-')); });
  afterEach(() => { fs.rmSync(home, { recursive: true, force: true }); });

  it('ida y vuelta idéntica; construcción determinista', async () => {
    const { dir } = await makeStore(home, { n: 6 });
    const src = openProjectionSource(dir);
    const a = StructureIndex.build(src, 'N2');
    const b = StructureIndex.load(src, 'N2');
    expect(JSON.stringify(b.docs)).toBe(JSON.stringify(a.docs));
    expect(StructureIndex.build(src, 'N2').header.payloadHash).toBe(a.header.payloadHash);
    expect(a.header.nodeCount).toBe(12);
  });

  it('cada campo del binding alterado hace rechazar la estructura; también un payload alterado', async () => {
    const { dir, manifest } = await makeStore(home, { n: 3 });
    const src = openProjectionSource(dir);
    StructureIndex.build(src, 'N2');
    const p = structurePath(dir, manifest.seq);
    const orig = fs.readFileSync(p.header, 'utf-8');
    for (const [k, v] of Object.entries({ generation: 'otra', seq: 9, chunkCount: 4, chunkOrder: '0', classification: 'N4', sealed: true, dome: 'X', builder: 'structure-v0', headerVersion: 2 })) {
      fs.writeFileSync(p.header, JSON.stringify({ ...JSON.parse(orig), [k]: v }));
      expect(() => StructureIndex.load(src, 'N2'), k).toThrow(new RegExp(`PROJECTION_MISMATCH.*${k}`));
    }
    fs.writeFileSync(p.header, orig);
    expect(() => StructureIndex.load(src, 'N3')).toThrow(/classification/);
    const payload = fs.readFileSync(p.payload, 'utf-8');
    fs.writeFileSync(p.payload, payload.replace('d0.md', 'dX.md'));
    expect(() => StructureIndex.load(src, 'N2')).toThrow(/alterado/);
  });

  it('una estructura de otro contenido no se sirve aunque el binding se recalcule a mano', async () => {
    const { dir, manifest } = await makeStore(home, { n: 3 });
    const src = openProjectionSource(dir);
    const built = StructureIndex.build(src, 'N2');
    // Unidad apuntando a un chunk con otro texto: se rechaza al cargar.
    const docs = JSON.parse(JSON.stringify(built.docs));
    docs['d0.md'][1].contentHash = 'sha256:' + '0'.repeat(64);
    const body = Buffer.from(JSON.stringify(docs));
    const p = structurePath(dir, manifest.seq);
    fs.writeFileSync(p.payload, body);
    const h = JSON.parse(fs.readFileSync(p.header, 'utf-8'));
    const { createHash } = await import('node:crypto');
    fs.writeFileSync(p.header, JSON.stringify({ ...h, payloadHash: createHash('sha256').update(body).digest('hex') }));
    expect(() => StructureIndex.load(src, 'N2')).toThrow(/sin chunk vigente/);
  });

  it('cifrado: sigue a la fuente sellada; sin cifrador no se construye ni se abre; no hay texto en claro', async () => {
    const cipher = xorCipher(7);
    const { dir, manifest } = await makeStore(home, { n: 3, cipher });
    const src = openProjectionSource(dir, cipher);
    expect(() => StructureIndex.build(src, 'N2')).toThrow(/cifrador/);
    StructureIndex.build(src, 'N2', cipher);
    const raw = fs.readFileSync(structurePath(dir, manifest.seq).payload);
    expect(raw.includes(Buffer.from('d0.md'))).toBe(false);
    expect(StructureIndex.load(src, 'N2', cipher).documents()).toContain('d0.md');
    expect(() => StructureIndex.load(src, 'N2')).toThrow(/PROJECTION_MISMATCH/);
    expect(() => StructureIndex.load(src, 'N2', xorCipher(9))).toThrow(/PROJECTION_MISMATCH/);
  });

  it('nunca se escribe dentro de un repo git', async () => {
    const { dir } = await makeStore(home, { n: 2 });
    const src = openProjectionSource(dir);
    execFileSync('git', ['init', '-q', home]);
    expect(() => StructureIndex.build(src, 'N2')).toThrow(/UNSAFE_HOME/);
  });

  it('GC: borra estructuras de otra seq y temporales; conserva la vigente; sin manifest no borra', async () => {
    const { dir, manifest } = await makeStore(home, { n: 2 });
    StructureIndex.build(openProjectionSource(dir), 'N2');
    fs.writeFileSync(path.join(dir, 'structure-0.json'), '{}');
    fs.writeFileSync(path.join(dir, 'structure-0.bin'), '{}');
    fs.writeFileSync(path.join(dir, 'structure-1.json.tmp-1-1'), '{}');
    expect(gcStructure(dir, manifest, 60_000)).toBe(0);
    expect(gcStructure(dir, undefined, 0)).toBe(0);
    fs.rmSync(path.join(dir, 'manifest.json'));
    expect(gcStructure(dir, undefined, 0)).toBe(0);
    expect(gcStructure(dir, manifest, 0)).toBe(3);
    expect(fs.readdirSync(dir).filter(f => f.startsWith('structure-')).sort()).toEqual(['structure-1.bin', 'structure-1.json']);
  });

  it('ensureStructure: construye si falta o no casa; reutiliza si casa', async () => {
    const { dir } = await makeStore(home, { n: 2 });
    expect(ensureStructure(dir, 'N2').built).toBe(true);
    expect(ensureStructure(dir, 'N2').built).toBe(false);
    expect(ensureStructure(dir, 'N3').built).toBe(true);
  });
});

describe('StructureIndex en el ciclo de vida de la generación (AC-3)', () => {
  let root: string;
  let home: string;
  let vault: string;
  let model: string;
  const mkSvc = (): RagService => {
    const d: RagDomeRef = { name: 'A', path: vault, confidentiality: 'N2', rag: { enabled: true, model, inlineSyncBudget: 0 } };
    return new RagService({ domes: () => [d], home, embedderFactory: (cfg) => new HashEmbedder(32, cfg, cfg.model) });
  };
  const write = (rel: string, body: string): void => {
    fs.mkdirSync(path.dirname(path.join(vault, rel)), { recursive: true });
    fs.writeFileSync(path.join(vault, rel), body);
    const t = new Date(Date.now() + Math.floor(Math.random() * 1000) + 2000);
    fs.utimesSync(path.join(vault, rel), t, t);
  };
  const structFiles = (gen: string): string[] => fs.readdirSync(path.join(domeDir(home, 'A'), gen)).filter(f => /^structure-\d+\./.test(f)).sort();

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m3-life-'));
    home = path.join(root, 'rag');
    vault = path.join(root, 'A');
    fs.mkdirSync(vault);
    model = 'm1';
  });
  afterEach(() => { fs.rmSync(root, { recursive: true, force: true }); });

  it('el sync construye la estructura de la seq vigente y la sirve para la generación activa', async () => {
    write('c.md', DOC);
    const svc = mkSvc();
    const r = await svc.sync('A');
    expect(structFiles(r.generation)).toEqual(['structure-1.bin', 'structure-1.json']);
    const s = svc.activeStructure('A')!;
    expect(s.header.generation).toBe(r.generation);
    expect(s.document('c.md')!.filter(n => n.kind === 'section').length).toBe(6);
    expect(svc.activeDocumentStructure('A', 'no-existe.md')).toBeUndefined();
  });

  it('un cambio de contenido crea seq nueva: la estructura vieja deja de servirse y el GC la retira', async () => {
    write('c.md', DOC);
    const svc = mkSvc();
    const r1 = await svc.sync('A');
    write('c.md', DOC.replace('Cláusula 3. Fin', 'Cláusula 3. Terminación'));
    const r2 = await svc.sync('A');
    expect(r2.generation).toBe(r1.generation);
    const s = svc.activeStructure('A')!;
    expect(s.header.seq).toBe(2);
    expect(s.document('c.md')!.some(n => n.title === 'Cláusula 3. Terminación')).toBe(true);
    expect(s.document('c.md')!.some(n => n.title === 'Cláusula 3. Fin')).toBe(false);
    // GC con el periodo de gracia vencido: solo queda la de la seq vigente.
    const genDir = path.join(domeDir(home, 'A'), r1.generation);
    const old = new Date(Date.now() - 3_600_000);
    for (const f of structFiles(r1.generation)) if (f.startsWith('structure-1.')) fs.utimesSync(path.join(genDir, f), old, old);
    expect(structFiles(r1.generation)).toEqual(['structure-1.bin', 'structure-1.json', 'structure-2.bin', 'structure-2.json']);
    await svc.gc('A');
    expect(structFiles(r1.generation)).toEqual(['structure-2.bin', 'structure-2.json']);
  });

  it('rollback: se sirve la estructura de la generación restaurada, no la de la retirada; GC borra la retirada entera', async () => {
    write('c.md', DOC);
    const s1 = mkSvc();
    const g1 = (await s1.sync('A')).generation;
    model = 'm2';
    write('c.md', DOC.replace('## Notas\n\nPrimera', '## Anotaciones\n\nPrimera'));
    const s2 = mkSvc();
    const r2 = await s2.sync('A');
    const g2 = r2.generation;
    expect(g2).not.toBe(g1);
    if (readActive(home, 'A').active !== g2) await s2.promote('A', g2, true);
    expect(s2.activeStructure('A')!.header.generation).toBe(g2);
    expect(s2.activeStructure('A')!.document('c.md')!.some(n => n.title === 'Anotaciones')).toBe(true);
    await s2.rollback('A');
    const back = s2.activeStructure('A')!;
    expect(back.header.generation).toBe(g1);
    expect(back.document('c.md')!.some(n => n.title === 'Anotaciones')).toBe(false);
    // La retirada sigue como `previous`; al dejar de estarlo, el GC la borra con su estructura.
    const p = readActive(home, 'A');
    expect(p.previous).toBe(g2);
    const { writeActive } = await import('../../../src/rag/store.js');
    writeActive(home, 'A', { active: g1 });
    await s2.gc('A');
    expect(fs.existsSync(path.join(domeDir(home, 'A'), g2))).toBe(false);
    expect(structFiles(g1).length).toBe(2);
  });

  it('estructura ausente o manipulada en la generación activa: no se sirve una que no casa (se reconstruye de la fuente)', async () => {
    write('c.md', DOC);
    const svc = mkSvc();
    const g = (await svc.sync('A')).generation;
    const dir = path.join(domeDir(home, 'A'), g);
    const p = structurePath(dir, FlatVectorStore.readManifest(dir)!.seq);
    const h = JSON.parse(fs.readFileSync(p.header, 'utf-8'));
    fs.writeFileSync(p.header, JSON.stringify({ ...h, payloadHash: '0'.repeat(64) }));
    const s = mkSvc().activeStructure('A')!;
    expect(s.header.payloadHash).not.toBe('0'.repeat(64));
    expect(s.document('c.md')).toBeDefined();
  });
});
