// SE-485 R4 (N4) — RAG: un identificador con forma de código que no aparece literal en ningún
// documento permitido no se presenta como respuesta: los vecinos salen con exactMatch:false y
// aviso por consulta. Si existe, su documento va primero con exactMatch:true.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { RagService, type RagDomeRef } from '../../../src/rag/service.js';
import { HashEmbedder } from '../../../src/rag/embedder.js';
import { formatRagResponse } from '../../../src/rag/format.js';
import type { ResolvedRagConfig } from '../../../src/rag/types.js';

const NOTE = 'identificador no encontrado literalmente';

describe('SE-485 R4 RAG identificadores', () => {
  let root: string;
  let home: string;
  let vault: string;
  let dome: RagDomeRef;
  const put = (p: string, s: string) => fs.writeFileSync(path.join(vault, p), s);
  const service = () => new RagService({
    domes: () => [dome], home,
    embedderFactory: (cfg: ResolvedRagConfig) => new HashEmbedder(64, cfg, cfg.model),
  });
  const ask = (q: string, extra: Record<string, unknown> = {}) =>
    service().search({ queries: [q], domes: ['D'], mode: 'bm25', k: 10, ...extra });

  beforeEach(async () => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se485-rag-'));
    home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se485-rag-home-'));
    vault = path.join(root, 'D');
    fs.mkdirSync(vault);
    dome = { name: 'D', path: vault, confidentiality: 'N2', rag: { enabled: true, model: 'm', inlineSyncBudget: 0 } };
    put('contrato.md', '# Contrato\nCT-2026-047: contrato sintético de válvula.');
    put('vecino.md', '# Vecino\nCT-2026-048: contrato sintético de turbina.');
    put('oculta.md', '---\nconfidentiality: N3\n---\n# Oculta\nCT-2077-001: contrato reservado.');
    put('vieja.md', '---\nstatus: deprecated\n---\n# Vieja\nCT-2001-001: contrato antiguo.');
    put('ruido.md', '# Jardinería\nAzaleas y violetas.');
    await service().sync('D');
  });
  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
    fs.rmSync(home, { recursive: true, force: true });
  });

  it('CT-2099-999 inexistente: todos los hits exactMatch:false y aviso', async () => {
    const r = await ask('CT-2099-999');
    expect(r.results[0].hits.length).toBeGreaterThan(0);
    expect(r.results[0].hits.every(h => h.exactMatch === false)).toBe(true);
    expect(r.results[0].warnings?.join(' ')).toContain(NOTE);
  });

  it('CT-2026-047 existente: su documento primero con exactMatch:true y sin aviso', async () => {
    const r = await ask('CT-2026-047');
    expect(r.results[0].hits[0]).toMatchObject({ path: 'contrato.md', exactMatch: true });
    expect(r.results[0].warnings).toBeUndefined();
    expect(r.results[0].hits.find(h => h.path === 'vecino.md')?.exactMatch).toBe(false);
  });

  it('un identificador solo presente en una nota fuera de nivel cuenta como inexistente (sin oráculo)', async () => {
    const r = await ask('CT-2077-001');
    expect(r.results[0].hits.map(h => h.path)).not.toContain('oculta.md');
    expect(r.results[0].hits.every(h => h.exactMatch !== true)).toBe(true);
    expect(r.results[0].warnings?.join(' ')).toContain(NOTE);
    // idéntico a un identificador que no existe en ningún sitio
    const nowhere = await ask('CT-2088-002');
    expect(nowhere.results[0].warnings).toEqual(r.results[0].warnings);
  });

  it('un identificador solo presente en una nota obsoleta: aviso salvo includeStale', async () => {
    expect((await ask('CT-2001-001')).results[0].warnings?.join(' ')).toContain(NOTE);
    const r = await ask('CT-2001-001', { includeStale: true });
    expect(r.results[0].hits[0]).toMatchObject({ path: 'vieja.md', exactMatch: true });
    expect(r.results[0].warnings).toBeUndefined();
  });

  it('negativo: una consulta sin identificador no lleva exactMatch ni aviso', async () => {
    const r = await ask('azaleas');
    expect(r.results[0].hits.length).toBe(1);
    expect(r.results[0].hits[0].exactMatch).toBeUndefined();
    expect(r.results[0].warnings).toBeUndefined();
  });

  it('el formato lean conserva exactMatch y el aviso', async () => {
    const r = await ask('CT-2099-999');
    const lean = JSON.parse(formatRagResponse(r, { fields: 'lean', maxChars: 10000 }));
    expect(lean.results[0].hits[0].exactMatch).toBe(false);
    expect(lean.results[0].warnings.join(' ')).toContain(NOTE);
  });
});
