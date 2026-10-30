import type { RagHit, RagResponse } from './types.js';

/**
 * SE-411 G4 — Respuesta de `vault_rag` para agentes.
 * `lean`: JSON compacto con lo mínimo por hit; `maxChars` acota la respuesta
 * entera recortando el texto de los hits (nunca omite un hit).
 * `full`: JSON compacto con todos los campos (depuración).
 */
export type RagFields = 'lean' | 'full';

const MIN_TEXT_PER_HIT = 200;
const round = (n: number) => Math.round(n * 10000) / 10000;

function leanHit(h: RagHit, withText: boolean) {
  return {
    dome: h.dome,
    confidentiality: h.confidentiality,
    path: h.path,
    heading: h.heading,
    ...(withText ? { text: h.text } : {}),
    score: round(h.score),
    ...(h.freshness.status ? { status: h.freshness.status } : {}),
    ...(h.freshness.supersededBy ? { supersededBy: h.freshness.supersededBy } : {}),
    // SE-413: procedencia de fichero (documento, revisión, localizador) para citar.
    ...(h.source ? { source: h.source } : {}),
    // SE-485 R4: vecino de un identificador buscado (false) o documento literal (true).
    ...(h.exactMatch !== undefined ? { exactMatch: h.exactMatch } : {}),
  };
}

function lean(res: RagResponse) {
  return {
    results: res.results.map(r => ({ query: r.query, hits: r.hits.map(h => leanHit(h, true)), ...(r.warnings ? { warnings: r.warnings } : {}) })),
    // Los textos ya van en `results`: `merged` solo ordena.
    ...(res.merged ? { merged: res.merged.map(h => leanHit(h, false)) } : {}),
    domes: res.domes.map(d => ({ name: d.name, status: d.status, ...(d.detail ? { detail: d.detail } : {}) })),
    ...(res.fusion ? { fusion: res.fusion } : {}),
    totalMs: res.timings.totalMs,
  };
}

export function formatRagResponse(res: RagResponse, opts: { fields: RagFields; maxChars: number }): string {
  if (opts.fields === 'full') return JSON.stringify(res);
  const body = lean(res);
  let out = JSON.stringify(body);
  if (out.length <= opts.maxChars) return out;
  const hits = body.results.flatMap(r => r.hits);
  const texts = hits.map(h => h.text ?? '');
  for (const h of hits) h.text = '';
  const overhead = JSON.stringify(body).length;
  const per = Math.max(MIN_TEXT_PER_HIT, Math.floor((opts.maxChars - overhead) / Math.max(1, hits.length)));
  hits.forEach((h, i) => { h.text = texts[i].length > per ? `${texts[i].slice(0, per - 1)}…` : texts[i]; });
  out = JSON.stringify(body);
  return out;
}
