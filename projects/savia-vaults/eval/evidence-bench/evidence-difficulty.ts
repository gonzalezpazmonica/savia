// SE-489 R1 — validación de dificultad del banco de evidencia.
// Ejecuta el baseline actual (RagService híbrido, M0) sobre los casos y mide
// Recall@10 de documento y EvidenceRecall@10 (la cita aparece en un hit) por
// categoría. No es el runner de R2: solo dice si el banco discrimina.
//
// Uso (SAVIA_RAG_HOME temporal, nunca la de producción):
//   SAVIA_RAG_HOME=/tmp/x npx tsx eval/evidence-bench/evidence-difficulty.ts \
//     --domes-file /tmp/x/domes.json --cases eval/evidence-bench/cases.jsonl [--out f.json]
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

export interface BenchEvidence { dome: string; document: string; locator: { section: string | null; quote: string } }
export interface BenchCase {
  id: string; category: string; split: string; query: string;
  scope: { allowed_domes: string[]; as_of: string | null };
  expected: { required_evidence: BenchEvidence[]; forbidden_evidence: { dome: string; document: string }[]; must_abstain: boolean };
}
export interface HitLike { dome: string; path: string; text: string }
export interface CaseScore {
  recall10: number | null; evidenceRecall10: number | null; forbiddenAt10: boolean; abstained: boolean; top: string[];
}

const norm = (s: string) => s.replace(/\s+/g, ' ').trim();

export function rankedDocs(hits: HitLike[]): string[] {
  const out: string[] = [];
  for (const h of hits) {
    const k = `${h.dome}:${h.path}`;
    if (!out.includes(k)) out.push(k);
  }
  return out;
}

export function scoreCase(c: BenchCase, hits: HitLike[]): CaseScore {
  const top = rankedDocs(hits).slice(0, 10);
  const inTop = new Set(top);
  const req = c.expected.required_evidence;
  const reqDocs = [...new Set(req.map(e => `${e.dome}:${e.document}`))];
  const recall10 = reqDocs.length ? reqDocs.filter(d => inTop.has(d)).length / reqDocs.length : null;
  const evidenceRecall10 = req.length
    ? req.filter(e => hits.some(h => inTop.has(`${h.dome}:${h.path}`) && h.dome === e.dome && h.path === e.document
      && norm(h.text).includes(norm(e.locator.quote)))).length / req.length
    : null;
  const forbiddenAt10 = c.expected.forbidden_evidence.some(f => inTop.has(`${f.dome}:${f.document}`));
  return { recall10, evidenceRecall10, forbiddenAt10, abstained: hits.length === 0, top };
}

export interface CategoryAgg {
  n: number; nRecall: number; recall10: number | null; evidenceRecall10: number | null;
  forbiddenRate: number; nAbstain: number; abstainCorrect: number;
}

export function aggregate(rows: { c: BenchCase; s: CaseScore }[]): Record<string, CategoryAgg> {
  const out: Record<string, CategoryAgg> = {};
  for (const cat of [...new Set(rows.map(r => r.c.category))].sort()) {
    const rs = rows.filter(r => r.c.category === cat);
    const withEv = rs.filter(r => r.s.recall10 !== null);
    const abst = rs.filter(r => r.c.expected.must_abstain);
    const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
    out[cat] = {
      n: rs.length, nRecall: withEv.length,
      recall10: mean(withEv.map(r => r.s.recall10 as number)),
      evidenceRecall10: mean(withEv.map(r => r.s.evidenceRecall10 as number)),
      forbiddenRate: rs.length ? rs.filter(r => r.s.forbiddenAt10).length / rs.length : 0,
      nAbstain: abst.length, abstainCorrect: abst.filter(r => r.s.abstained).length,
    };
  }
  return out;
}

async function main(): Promise<void> {
  const arg = (k: string) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : undefined; };
  const domesFile = arg('--domes-file'); const casesFile = arg('--cases'); const outFile = arg('--out');
  if (!domesFile || !casesFile) throw new Error('uso: --domes-file F --cases F [--out F]');
  const ragHome = process.env.SAVIA_RAG_HOME;
  if (!ragHome) throw new Error('SAVIA_RAG_HOME obligatorio (temporal, nunca la de producción)');
  const tmp = fs.realpathSync(os.tmpdir());
  if (!path.resolve(ragHome).startsWith(tmp + path.sep)) throw new Error(`SAVIA_RAG_HOME debe estar bajo ${tmp} (temporal)`);
  const { DomeRegistry } = await import('../../src/registry/domes.js');
  const { RagService } = await import('../../src/rag/service.js');
  const reg = new DomeRegistry(path.resolve(domesFile)); reg.load();
  const svc = new RagService({
    domes: () => reg.listActive().map(d => ({ name: d.name, path: d.path, confidentiality: d.confidentiality, rag: d.rag, files: d.files })),
    background: false,
  });
  const cases = fs.readFileSync(casesFile, 'utf-8').split('\n').filter(Boolean).map(l => JSON.parse(l) as BenchCase);
  const rows: { c: BenchCase; s: CaseScore }[] = [];
  for (const c of cases) {
    const res = await svc.search({ queries: [c.query], domes: c.scope.allowed_domes, k: 30, mode: 'hybrid', maxChars: 1_000_000 });
    const bad = res.domes.filter(d => d.status !== 'ok' && d.status !== 'stale');
    if (bad.length) throw new Error(`${c.id}: cúpula no disponible ${bad.map(d => `${d.name}=${d.status}`).join(',')}`);
    rows.push({ c, s: scoreCase(c, res.results[0]?.hits ?? []) });
  }
  const report = {
    generatedAt: new Date().toISOString(), route: 'M0 hybrid (RagService.search, k=30, includeStale=false)',
    all: aggregate(rows),
    dev: aggregate(rows.filter(r => r.c.split === 'dev')), test: aggregate(rows.filter(r => r.c.split === 'test')),
    cases: rows.map(r => ({ id: r.c.id, ...r.s })),
  };
  if (outFile) fs.writeFileSync(outFile, JSON.stringify(report, null, 2));
  for (const [cat, a] of Object.entries(report.all)) {
    const f = (x: number | null) => (x === null ? '-' : x.toFixed(3));
    console.log(`${cat} n=${a.n} Recall@10=${f(a.recall10)} (n=${a.nRecall}) EvidenceRecall@10=${f(a.evidenceRecall10)} prohibida@10=${a.forbiddenRate.toFixed(3)} abstención=${a.abstainCorrect}/${a.nAbstain}`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(e => { console.error(`Error: ${e instanceof Error ? e.message : String(e)}`); process.exit(1); });
}
