// SE-411 G4 — respuesta compacta de vault_rag (perfil lean, maxChars sobre la respuesta entera)
import { describe, it, expect } from 'vitest';
import { formatRagResponse } from '../../../src/rag/format.js';
import type { RagHit, RagResponse } from '../../../src/rag/types.js';

const hit = (i: number, text = 'x'.repeat(1200), extra: Partial<RagHit> = {}): RagHit => ({
  dome: 'D', confidentiality: 'N2', path: `docs/nota-${i}.md`, chunkId: `docs/nota-${i}.md#0`,
  heading: `Nota ${i} › Sección`, text, score: 0.0163934426 - i * 0.0001,
  signals: { denseRank: i + 1, dense: 0.61234, bm25Rank: i + 2, bm25: 12.3456 },
  freshness: { modified: '2026-09-01', decay: 1 }, generation: 'abc123def456', ...extra,
});
const response = (n: number, queries = 1): RagResponse => ({
  results: Array.from({ length: queries }, (_, q) => ({ query: `q${q}`, hits: Array.from({ length: n }, (_, i) => hit(i)) })),
  ...(queries > 1 ? { merged: Array.from({ length: n }, (_, i) => hit(i)) } : {}),
  domes: [{ name: 'D', status: 'ok', generation: 'abc123def456' }],
  timings: { totalMs: 120, embedMs: 100, syncMs: 3 },
  fusion: 'cosine',
});

describe('formatRagResponse', () => {
  it('lean: JSON compacto con campos mínimos por hit', () => {
    const out = formatRagResponse(response(2), { fields: 'lean', maxChars: 100000 });
    expect(out).not.toContain('\n');
    const body = JSON.parse(out);
    expect(Object.keys(body.results[0].hits[0]).sort()).toEqual(['confidentiality', 'dome', 'heading', 'modified', 'path', 'score', 'text']);
    expect(body.results[0].hits[0].score).toBe(0.0164);
    expect(body.domes[0]).toEqual({ name: 'D', status: 'ok' });
  });

  it('lean conserva superseded_by y status de frescura cuando existen', () => {
    const r = response(1);
    r.results[0].hits[0] = hit(0, 'y', { freshness: { modified: '', decay: 1, supersededBy: 'nueva.md', status: 'deprecated' } });
    const h = JSON.parse(formatRagResponse(r, { fields: 'lean', maxChars: 100000 })).results[0].hits[0];
    expect(h.supersededBy).toBe('nueva.md');
    expect(h.status).toBe('deprecated');
  });

  it('lean conserva la fecha de modificación (modified) para que el cliente muestre frescura', () => {
    const h = JSON.parse(formatRagResponse(response(1), { fields: 'lean', maxChars: 100000 })).results[0].hits[0];
    expect(h.modified).toBe('2026-09-01');
  });

  it('lean omite modified cuando el servicio no la conoce (cadena vacía)', () => {
    const r = response(1);
    r.results[0].hits[0] = hit(0, 'y', { freshness: { modified: '', decay: 1 } });
    const h = JSON.parse(formatRagResponse(r, { fields: 'lean', maxChars: 100000 })).results[0].hits[0];
    expect('modified' in h).toBe(false);
  });

  it('maxChars acota la respuesta entera y el texto es la mayor parte (AC4)', () => {
    const out = formatRagResponse(response(8), { fields: 'lean', maxChars: 6000 });
    expect(out.length).toBeLessThanOrEqual(6000);
    const body = JSON.parse(out);
    const text = body.results[0].hits.reduce((s: number, h: { text: string }) => s + h.text.length, 0);
    expect(text / out.length).toBeGreaterThanOrEqual(0.6);
    expect(body.results[0].hits).toHaveLength(8);
  });

  it('merged en lean no repite el texto de los hits', () => {
    const body = JSON.parse(formatRagResponse(response(3, 2), { fields: 'lean', maxChars: 100000 }));
    expect(body.merged[0].text).toBeUndefined();
    expect(body.merged[0].path).toBe('docs/nota-0.md');
  });

  it('full: JSON compacto con todos los campos', () => {
    const out = formatRagResponse(response(2), { fields: 'full', maxChars: 100000 });
    expect(out).not.toContain('\n');
    expect(JSON.parse(out).results[0].hits[0].signals.dense).toBe(0.61234);
  });
});
