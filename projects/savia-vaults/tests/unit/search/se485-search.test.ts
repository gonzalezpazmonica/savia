// SE-485 R4/R5 sobre SearchEngine (vault_search y A2A /search): identificadores inexistentes
// marcados con exactMatch:false y aviso; includeStale con la misma función excludedReason.
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { SearchEngine } from '../../../src/search/index.js';
import type { VaultConfig } from '../../../src/types.js';

describe('SE-485 SearchEngine', () => {
  let root: string;
  let engine: SearchEngine;
  const put = (p: string, s: string) => fs.writeFileSync(path.join(root, p), s);

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se485-search-'));
    put('contrato.md', '# Contrato\nCT-2026-047: contrato sintético de válvula.');
    put('vecino.md', '# Vecino\nCT-2026-048: contrato sintético de turbina.');
    put('vieja.md', '---\nstatus: deprecated\n---\n# Vieja\nnorma sintética obsoleta zafiro.');
    put('caducada.md', '---\nvalid_until: 2000-01-01\n---\n# Caducada\nnorma sintética caducada zafiro.');
    put('vigente.md', '# Vigente\nnorma sintética vigente zafiro.');
    const cfg: VaultConfig = { name: 't', path: root, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024 };
    engine = new SearchEngine(cfg);
    engine.buildIndex();
  });
  afterEach(() => fs.rmSync(root, { recursive: true, force: true }));

  const paths = (r: { path: string }[]) => r.map(x => x.path).sort();

  it('R4: identificador inexistente ⇒ vecinos con exactMatch:false y aviso', () => {
    const r = engine.search({ query: 'CT-2099-999' });
    expect(r.length).toBeGreaterThan(0);
    for (const h of r) {
      expect(h.exactMatch).toBe(false);
      expect(h.warnings).toContain('identificador no encontrado literalmente');
    }
  });

  it('R4: identificador existente ⇒ su documento primero con exactMatch:true y sin aviso', () => {
    const r = engine.search({ query: 'CT-2026-047' });
    expect(r[0].path).toBe('contrato.md');
    expect(r[0].exactMatch).toBe(true);
    expect(r[0].warnings).toBeUndefined();
    const neighbour = r.find(h => h.path === 'vecino.md');
    expect(neighbour?.exactMatch).toBe(false);
  });

  it('R4 límite: CT-2026-04 no casa literalmente dentro de CT-2026-047', () => {
    const r = engine.search({ query: 'CT-2026-04' });
    expect(r.every(h => h.exactMatch === false)).toBe(true);
  });

  it('R4 negativo: una consulta sin identificador no lleva exactMatch', () => {
    const r = engine.search({ query: 'zafiro' });
    expect(r.length).toBeGreaterThan(0);
    expect(r.every(h => h.exactMatch === undefined && h.warnings === undefined)).toBe(true);
  });

  it('R5: includeStale:false excluye deprecated y valid_until vencido; true los incluye', () => {
    expect(paths(engine.search({ query: 'zafiro', includeStale: false }))).toEqual(['vigente.md']);
    expect(paths(engine.search({ query: 'zafiro', includeStale: true }))).toEqual(['caducada.md', 'vieja.md', 'vigente.md']);
  });

  it('R5: sin includeStale el valor por defecto excluye lo obsoleto, como vault_rag', () => {
    expect(paths(engine.search({ query: 'zafiro' }))).toEqual(['vigente.md']);
  });

  it('R5: excludeStatuses propio de la cúpula sustituye al de RAG por defecto', () => {
    expect(paths(engine.search({ query: 'zafiro', excludeStatuses: ['archived'] }))).toEqual(['vieja.md', 'vigente.md']);
  });

  it('R5: el identificador solo presente en una nota obsoleta no cuenta como encontrado con includeStale:false', () => {
    put('contrato-viejo.md', '---\nstatus: superseded\n---\n# Viejo\nCT-2001-001 contrato antiguo.');
    engine.buildIndex();
    const r = engine.search({ query: 'CT-2001-001', includeStale: false });
    expect(r.find(h => h.path === 'contrato-viejo.md')).toBeUndefined();
    const withStale = engine.search({ query: 'CT-2001-001', includeStale: true });
    expect(withStale[0]).toMatchObject({ path: 'contrato-viejo.md', exactMatch: true });
  });
});
