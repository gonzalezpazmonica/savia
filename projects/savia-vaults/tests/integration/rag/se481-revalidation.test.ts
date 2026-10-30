// SE-481 — RAG: cuarentena al indexar (AC-1), revalidación al servir sin sync (AC-4),
// includeStale no reabre nada (AC-5), polaridad e identificadores en BM25 (AC-7).
// Corpus sintéticos: eval/fixtures/{malformed-meta,negation-polarity,identifiers-exact}.json.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { RagService, type RagDomeRef } from '../../../src/rag/service.js';
import { HashEmbedder } from '../../../src/rag/embedder.js';
import { readActive, FlatVectorStore } from '../../../src/rag/store.js';
import { BM25_STOPWORDS, processTerm } from '../../../src/rag/retriever.js';
import type { ResolvedRagConfig, RagResponse } from '../../../src/rag/types.js';

const load = (name: string) => JSON.parse(fs.readFileSync(path.resolve(`eval/fixtures/${name}.json`), 'utf-8'));
const malformed = load('malformed-meta') as { domeLevel: string; notes: Record<string, { content: string; diagnostic?: string; kind: string }> };
const negation = load('negation-polarity') as { pairs: { query: string; expected: string; twin: string }[]; docs: Record<string, string> };
const identifiers = load('identifiers-exact') as { queries: { query: string; expected: string }[]; docs: Record<string, string> };

const long = (s: string) => `${s}. `.repeat(12);
const hitPaths = (r: RagResponse) => r.results[0].hits.map(h => h.path);

function writeDocs(dir: string, docs: Record<string, string>): void {
  for (const [p, c] of Object.entries(docs)) {
    fs.mkdirSync(path.dirname(path.join(dir, p)), { recursive: true });
    fs.writeFileSync(path.join(dir, p), c);
  }
}

/** Reescribe un fichero y adelanta su mtime para que el cambio sea visible. */
function rewrite(file: string, content: string): void {
  fs.writeFileSync(file, content);
  const t = new Date(Date.now() + 5_000);
  fs.utimesSync(file, t, t);
}

describe('SE-481 RAG', () => {
  let root: string;
  let home: string;
  let vault: string;
  let dome: RagDomeRef;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se481-rag-'));
    home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se481-rag-home-'));
    vault = path.join(root, 'D');
    fs.mkdirSync(vault);
    // inlineSyncBudget 0: ninguna consulta sincroniza; lo servido sale del índice ya construido.
    dome = { name: 'D', path: vault, confidentiality: 'N2', rag: { enabled: true, model: 'm', inlineSyncBudget: 0 } };
  });
  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
    fs.rmSync(home, { recursive: true, force: true });
  });

  const service = () => new RagService({
    domes: () => [dome], home,
    embedderFactory: (cfg: ResolvedRagConfig) => new HashEmbedder(64, cfg, cfg.model),
  });
  const ask = (query: string, extra: Record<string, unknown> = {}) =>
    service().search({ queries: [query], domes: ['D'], mode: 'bm25', k: 10, ...extra });

  describe('AC-1/AC-2: cuarentena al indexar y al servir', () => {
    beforeEach(() => writeDocs(vault, Object.fromEntries(Object.entries(malformed.notes).map(([p, n]) => [p, n.content]))));

    it('el sync no indexa las notas en cuarentena y las cuenta por código', async () => {
      const r = await service().sync('D');
      expect(r.docs.quarantined).toBe(5);
      expect(r.quarantine).toEqual({ 'yaml-unparsable': 1, 'unknown-level': 2, 'non-string': 1, 'forbidden-char': 1 });
      expect(JSON.stringify(r)).not.toMatch(/mal\//);
      const gen = readActive(home, 'D').active!;
      const docs = FlatVectorStore.readManifest(path.join(home, 'D', gen))!.docs;
      for (const [p, n] of Object.entries(malformed.notes)) {
        if (n.diagnostic) expect(docs[p]).toMatchObject({ chunkIds: [], skipped: `quarantine:${n.diagnostic}` });
      }
    });

    it.each(Object.entries(malformed.notes).filter(([, n]) => n.diagnostic))('vault_rag no devuelve %s', async (p, n) => {
      await service().sync('D');
      const word = n.content.match(/CANARIO-[A-Z0-9]+/)![0];
      const res = await ask(word);
      expect(hitPaths(res)).not.toContain(p);
      expect(JSON.stringify(res.results[0].hits)).not.toContain(word);
    });

    it('caso negativo: las notas sin clasificación sí se sirven', async () => {
      await service().sync('D');
      expect(hitPaths(await ask('VISIBLE-SIN corriente'))).toContain('ok/sin-clave.md');
      expect(hitPaths(await ask('VISIBLE-ROTO corriente'))).toContain('ok/yaml-roto-sin-clave.md');
    });
  });

  describe('AC-4: revalidación al servir, sin sync', () => {
    beforeEach(() => writeDocs(vault, {
      'a.md': `---\nconfidentiality: N2\n---\n# Alfa\n\n${long('el halcón peregrino anida en acantilados')}`,
      'b.md': `# Beta\n\n${long('el halcón peregrino caza en vuelo')}`,
    }));

    it('una nota reclasificada a N4 en disco desaparece en la siguiente consulta', async () => {
      await service().sync('D');
      expect(hitPaths(await ask('halcón acantilados'))).toContain('a.md');
      const seq = FlatVectorStore.readManifest(path.join(home, 'D', readActive(home, 'D').active!))!.seq;
      rewrite(path.join(vault, 'a.md'), fs.readFileSync(path.join(vault, 'a.md'), 'utf-8').replace('N2', 'N4'));
      const res = await ask('halcón acantilados');
      expect(hitPaths(res)).not.toContain('a.md');
      expect(hitPaths(res)).toContain('b.md');
      expect(res.domes[0].status).toBe('stale'); // no hubo sync inline
      expect(res.domes[0].degradation).toEqual({ revalidated: 1 });
      expect(JSON.stringify(res.domes)).not.toContain('a.md');
      expect(FlatVectorStore.readManifest(path.join(home, 'D', readActive(home, 'D').active!))!.seq).toBe(seq);
    });

    it('una nota que pasa a cuarentena en disco desaparece en la siguiente consulta', async () => {
      await service().sync('D');
      rewrite(path.join(vault, 'a.md'), fs.readFileSync(path.join(vault, 'a.md'), 'utf-8').replace('N2', '[N4'));
      expect(hitPaths(await ask('halcón acantilados'))).not.toContain('a.md');
    });

    it('una nota indexada y borrada desaparece en la siguiente consulta', async () => {
      await service().sync('D');
      fs.unlinkSync(path.join(vault, 'a.md'));
      const res = await ask('halcón acantilados');
      expect(hitPaths(res)).not.toContain('a.md');
      expect(res.domes[0].degradation).toEqual({ revalidated: 1 });
    });

    it('caso negativo: sin cambios en disco no se descarta nada', async () => {
      await service().sync('D');
      const res = await ask('halcón');
      expect(hitPaths(res).sort()).toEqual(['a.md', 'b.md']);
      expect(res.domes[0].degradation).toBeUndefined();
    });
  });

  describe('AC-5: includeStale no reabre cuarentena ni fuera de nivel', () => {
    beforeEach(() => writeDocs(vault, {
      'q.md': `---\nconfidentiality: N2\n---\n# Q\n\n${long('el cormorán moñudo bucea')}`,
      'o.md': `---\nconfidentiality: N2\n---\n# O\n\n${long('el cormorán grande seca sus alas')}`,
      'old.md': `---\nstatus: deprecated\n---\n# Old\n\n${long('el cormorán antiguo regla retirada')}`,
    }));

    it('con includeStale solo vuelven las notas obsoletas, no las vetadas', async () => {
      await service().sync('D');
      rewrite(path.join(vault, 'q.md'), fs.readFileSync(path.join(vault, 'q.md'), 'utf-8').replace('N2', 'N7'));
      rewrite(path.join(vault, 'o.md'), fs.readFileSync(path.join(vault, 'o.md'), 'utf-8').replace('N2', 'N3'));
      const stale = await ask('cormorán', { includeStale: true });
      expect(hitPaths(stale)).toEqual(['old.md']);
      expect(hitPaths(await ask('cormorán'))).toEqual([]);
    });
  });

  describe('reglas nuevas sobre un índice construido con las anteriores', () => {
    it('el sync reclasifica las notas reutilizadas aunque su mtime no cambie', async () => {
      writeDocs(vault, { 'r.md': `---\nconfidentiality: N2\n---\n# R\n\n${long('la garcilla bueyera')}` });
      await service().sync('D');
      const genDir = path.join(home, 'D', readActive(home, 'D').active!);
      // Simula un índice de main: la nota se indexó y no consta versión de reglas.
      const st = fs.statSync(path.join(vault, 'r.md'));
      fs.writeFileSync(path.join(vault, 'r.md'), fs.readFileSync(path.join(vault, 'r.md'), 'utf-8').replace('N2', 'N9'));
      fs.utimesSync(path.join(vault, 'r.md'), st.atime, st.mtime);
      const m = JSON.parse(fs.readFileSync(path.join(genDir, 'manifest.json'), 'utf-8'));
      delete m.classificationRules;
      fs.writeFileSync(path.join(genDir, 'manifest.json'), JSON.stringify(m));
      const r = await service().sync('D');
      expect(r.quarantine).toEqual({ 'unknown-level': 1 });
      expect(FlatVectorStore.readManifest(genDir)!.docs['r.md'].skipped).toBe('quarantine:unknown-level');
      // caso negativo: con la versión de reglas al día, el mtime igual se reutiliza sin releer
      // (prueba observable: se corrige el contenido conservando el mtime; si releyera, saldría de cuarentena)
      fs.writeFileSync(path.join(vault, 'r.md'), fs.readFileSync(path.join(vault, 'r.md'), 'utf-8').replace('N9', 'N2'));
      fs.utimesSync(path.join(vault, 'r.md'), st.atime, st.mtime);
      const again = await service().sync('D');
      expect(again.docs.quarantined).toBe(1);
      expect(again.docs.added + again.docs.updated).toBe(0);
      expect(FlatVectorStore.readManifest(genDir)!.docs['r.md'].skipped).toBe('quarantine:unknown-level');
    });

    it('el cambio de código de cuarentena se refleja en el manifiesto', async () => {
      writeDocs(vault, { 'c.md': `---\nconfidentiality: [N4\n---\n# C\n\n${long('la espátula común')}` });
      await service().sync('D');
      const genDir = path.join(home, 'D', readActive(home, 'D').active!);
      expect(FlatVectorStore.readManifest(genDir)!.docs['c.md'].skipped).toBe('quarantine:yaml-unparsable');
      rewrite(path.join(vault, 'c.md'), fs.readFileSync(path.join(vault, 'c.md'), 'utf-8').replace('[N4', 'N7'));
      await service().sync('D');
      const after = FlatVectorStore.readManifest(path.join(home, 'D', readActive(home, 'D').active!))!;
      expect(after.docs['c.md'].skipped).toBe('quarantine:unknown-level');
      expect(after.docs['c.md'].mtimeMs).toBe(fs.statSync(path.join(vault, 'c.md')).mtimeMs);
    });
  });

  describe('AC-7: polaridad e identificadores en BM25', () => {
    it('las negaciones y los marcadores de excepción no son stopwords', () => {
      for (const w of ['no', 'not', 'ni', 'sin', 'nada', 'nunca', 'salvo', 'excepto', 'prohibido', 'never']) {
        expect(BM25_STOPWORDS.has(w)).toBe(false);
        expect(processTerm(w)).toBe(w);
      }
      expect(processTerm('de')).toBeNull(); // caso negativo: las stopwords siguen ahí
    });

    it.each(negation.pairs)('«$query» puntúa por encima la variante con negación', async ({ query, expected, twin }) => {
      writeDocs(vault, negation.docs);
      await service().sync('D');
      const hits = (await ask(query)).results[0].hits;
      const neg = hits.find(h => h.path === expected);
      const pos = hits.find(h => h.path === twin);
      expect(neg).toBeDefined();
      expect(pos).toBeDefined();
      expect(neg!.signals.bm25!).toBeGreaterThan(pos!.signals.bm25!);
      expect(hits.findIndex(h => h.path === expected)).toBeLessThan(hits.findIndex(h => h.path === twin));
    });

    it.each(identifiers.queries)('«$query» devuelve el documento exacto en primera posición', async ({ query, expected }) => {
      writeDocs(vault, identifiers.docs);
      await service().sync('D');
      const hits = (await ask(query)).results[0].hits;
      expect(hits[0]?.path).toBe(expected);
      // margen estricto: el exacto no empata con el siguiente
      if (hits[1]) expect(hits[0].signals.bm25!).toBeGreaterThan(hits[1].signals.bm25!);
    });
  });
});
