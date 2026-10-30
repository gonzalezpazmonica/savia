// SE-489 R2 — runner de evaluación por evidencia: banco, métricas, IC 95 % por bootstrap
// pareado por pregunta y ejecución sobre rutas (M0) con cúpulas denegadas por caso.
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import {
  bootstrapMean, caseMetrics, evaluateRoute, fromR1, legacyToCases, loadBench, pairedBootstrap, validateCase, type EvidenceCase,
} from '../../src/retrieval/evidence-eval.js';
import type { Evidence } from '../../src/retrieval/route.js';
import type { RagHit } from '../../src/rag/types.js';
import { fixture, long, note, writeDocs, type Fixture } from './helpers.js';

const ev = (document: string, extra: Partial<Evidence> = {}): Evidence => ({
  chunkId: `${document}#0`, dome: 'A', document, revision: 'sha256:r1', locator: '#0 Título › Anexo II', contentHash: 'sha256:x', ...extra,
});
const hit = (document: string, text = 'texto'): RagHit => ({ dome: 'A', path: document, chunkId: `${document}#0`, text } as RagHit);
const base: EvidenceCase = {
  id: 'A-001', category: 'A', split: 'dev', query: 'q', required_evidence: [{ document: 'a.md' }], forbidden_evidence: [], must_abstain: false, max_unauthorized_reads: 0,
};

describe('SE-489 validateCase', () => {
  it('acepta un caso completo', () => {
    expect(validateCase(base)).toEqual([]);
  });

  it.each([
    [{ id: '' }, /id/], [{ category: 'Z' }, /category/], [{ split: 'train' }, /split/], [{ query: '' }, /query/],
    [{ required_evidence: [{}] }, /document/], [{ forbidden_evidence: 'x' }, /forbidden_evidence/],
    [{ must_abstain: 'no' }, /must_abstain/], [{ max_unauthorized_reads: 1 }, /max_unauthorized_reads/],
    [{ as_of: 'ayer' }, /as_of/], [{ as_of: '2026-02-30' }, /as_of/], [{ domes: 'A' }, /domes/], [{ extra: 1 }, /desconocido/],
    [{ must_abstain: false, required_evidence: [] }, /required_evidence/],
  ])('rechaza %j', (patch, re) => {
    expect(validateCase({ ...base, ...patch }).join(' ')).toMatch(re);
  });
});

describe('SE-489 caseMetrics', () => {
  it('EvidenceRecall exige revisión y localizador cuando el caso los declara', () => {
    const c: EvidenceCase = { ...base, required_evidence: [{ document: 'a.md', revision: 'sha256:r1', locator: 'Anexo II' }, { document: 'b.md', revision: 'sha256:r9' }] };
    const m = caseMetrics(c, { hits: [hit('a.md'), hit('b.md')], evidence: [ev('a.md'), ev('b.md', { chunkId: 'b.md#0' })] }, 0);
    expect(m.evidenceRecall).toBe(0.5);
    expect(m.recallAt5).toBe(1);
    expect(m.mrr).toBe(1);
  });

  it('localizador por ordinal (#n) no confunde #1 con #10', () => {
    const c: EvidenceCase = { ...base, required_evidence: [{ document: 'a.md', locator: '#1' }] };
    expect(caseMetrics(c, { hits: [hit('a.md')], evidence: [ev('a.md', { locator: '#10 Otro' })] }, 0).evidenceRecall).toBe(0);
    expect(caseMetrics(c, { hits: [hit('a.md')], evidence: [ev('a.md', { locator: '#1 Otro' })] }, 0).evidenceRecall).toBe(1);
  });

  it('cuenta evidencia prohibida (revisión vieja)', () => {
    const c: EvidenceCase = { ...base, forbidden_evidence: [{ document: 'a.md', revision: 'sha256:r1' }] };
    expect(caseMetrics(c, { hits: [hit('a.md')], evidence: [ev('a.md')] }, 0).forbiddenUsed).toBe(1);
    expect(caseMetrics(c, { hits: [hit('a.md')], evidence: [ev('a.md', { revision: 'sha256:r2' })] }, 0).forbiddenUsed).toBe(0);
  });

  it('exact-identifier-hit: el primer hit contiene el identificador y es evidencia requerida', () => {
    const c: EvidenceCase = { ...base, query: 'qué dice SE-481' };
    expect(caseMetrics(c, { hits: [hit('a.md', 'según SE-481')], evidence: [ev('a.md')] }, 0).exactIdentifierHit).toBe(1);
    expect(caseMetrics(c, { hits: [hit('a.md', 'según SE-4810')], evidence: [ev('a.md')] }, 0).exactIdentifierHit).toBe(0);
    expect(caseMetrics(c, { hits: [hit('z.md', 'SE-481')], evidence: [ev('z.md')] }, 0).exactIdentifierHit).toBe(0);
    expect(caseMetrics(base, { hits: [], evidence: [] }, 0).exactIdentifierHit).toBeUndefined();
  });

  it('abstención: correcta solo en casos must_abstain; falso rechazo solo en los demás', () => {
    const abstain: EvidenceCase = { ...base, must_abstain: true, required_evidence: [] };
    expect(caseMetrics(abstain, { hits: [], evidence: [] }, 0).correctAbstention).toBe(1);
    expect(caseMetrics(abstain, { hits: [hit('a.md')], evidence: [ev('a.md')] }, 0).correctAbstention).toBe(0);
    expect(caseMetrics(abstain, { hits: [hit('a.md')], evidence: [ev('a.md')], abstain: true }, 0).correctAbstention).toBe(1);
    expect(caseMetrics(abstain, { hits: [], evidence: [] }, 0).falseAbstention).toBeUndefined();
    expect(caseMetrics(base, { hits: [], evidence: [] }, 0).correctAbstention).toBeUndefined();
    expect(caseMetrics(base, { hits: [], evidence: [] }, 0).falseAbstention).toBe(1);
    expect(caseMetrics(base, { hits: [hit('a.md')], evidence: [ev('a.md')] }, 0).falseAbstention).toBe(0);
    expect(caseMetrics(abstain, { hits: [], evidence: [] }, 0).evidenceRecall).toBeUndefined();
  });

  it('formato R1: revisión como blob de git y cita en el texto servido', () => {
    const c: EvidenceCase = { ...base, required_evidence: [{ document: 'a.md', dome: 'A', revision: 'b'.repeat(40), quote: 'Plazo  de PREAVISO' }] };
    const e = ev('a.md', { gitBlob: 'b'.repeat(40) });
    expect(caseMetrics(c, { hits: [hit('a.md', 'el plazo de preaviso es de 30 días')], evidence: [e] }, 0).evidenceRecall).toBe(1);
    expect(caseMetrics(c, { hits: [hit('a.md', 'otra cosa')], evidence: [e] }, 0).evidenceRecall).toBe(0);
    expect(caseMetrics(c, { hits: [hit('a.md', 'el plazo de preaviso')], evidence: [ev('a.md', { gitBlob: 'c'.repeat(40) })] }, 0).evidenceRecall).toBe(0);
  });

  it('lecturas no autorizadas: las que el recontrol no admite, y violación si superan el máximo', () => {
    const m = caseMetrics(base, { hits: [hit('a.md')], evidence: [ev('a.md')] }, 2);
    expect(m.unauthorizedReads).toBe(2);
    expect(m.violation).toBe(true);
    expect(caseMetrics(base, { hits: [hit('a.md')], evidence: [ev('a.md')] }, 0).violation).toBe(false);
  });
});

describe('SE-489 bootstrap', () => {
  it('es determinista por semilla y el IC contiene la media', () => {
    const xs = [0, 1, 1, 0, 1, 1, 1, 0, 1, 1];
    const a = bootstrapMean(xs, { iterations: 500, seed: 3 });
    expect(bootstrapMean(xs, { iterations: 500, seed: 3 })).toEqual(a);
    expect(a.mean).toBeCloseTo(0.7);
    expect(a.lo).toBeLessThanOrEqual(a.mean);
    expect(a.hi).toBeGreaterThanOrEqual(a.mean);
    expect(a.hi - a.lo).toBeGreaterThan(0);
  });

  it('pareado: diferencia nula ⇒ IC [0,0]; dominancia ⇒ IC que excluye 0', () => {
    const a = new Map([['q1', 0.2], ['q2', 0.5], ['q3', 0.1], ['q4', 0.4]]);
    expect(pairedBootstrap(a, a, { iterations: 300, seed: 1 })).toMatchObject({ n: 4, diff: 0, lo: 0, hi: 0 });
    const b = new Map([...a].map(([k, v]) => [k, v + 0.3]));
    const d = pairedBootstrap(b, a, { iterations: 300, seed: 1 });
    expect(d.diff).toBeCloseTo(0.3);
    expect(d.lo).toBeGreaterThan(0);
  });

  it('pareado solo sobre preguntas presentes en ambos', () => {
    const a = new Map([['q1', 1], ['q2', 1]]);
    const b = new Map([['q1', 0], ['q3', 0]]);
    expect(pairedBootstrap(a, b, { iterations: 50, seed: 1 }).n).toBe(1);
  });

  it('iteraciones < 1 ⇒ INVALID_INPUT (no IC sin remuestreo)', () => {
    expect(() => bootstrapMean([1, 0], { iterations: 0, seed: 1 })).toThrow(/INVALID_INPUT/);
  });

  it('sin datos ⇒ n 0 y sin IC inventado', () => {
    expect(bootstrapMean([], { iterations: 10, seed: 1 })).toEqual({ n: 0, mean: 0, lo: 0, hi: 0 });
  });
});

describe('SE-489 loadBench', () => {
  let dir: string;
  beforeAll(() => { dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se489-bench-')); });
  afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

  it('lee .json (lista o {cases}) y .jsonl, filtra por split', () => {
    const d = path.join(dir, 'ok');
    fs.mkdirSync(d);
    fs.writeFileSync(path.join(d, 'a.json'), JSON.stringify([base]));
    fs.writeFileSync(path.join(d, 'b.json'), JSON.stringify({ cases: [{ ...base, id: 'B-001', category: 'B', split: 'test' }] }));
    fs.writeFileSync(path.join(d, 'c.jsonl'), `${JSON.stringify({ ...base, id: 'C-001', category: 'C' })}\n\n`);
    fs.writeFileSync(path.join(d, 'README.md'), 'no es un caso');
    expect(loadBench(d).map(c => c.id).sort()).toEqual(['A-001', 'B-001', 'C-001']);
    expect(loadBench(d, { split: 'test' }).map(c => c.id)).toEqual(['B-001']);
  });

  it('acepta el formato R1 (scope/expected) y lo valida', () => {
    const d = path.join(dir, 'r1');
    fs.mkdirSync(d);
    const r1 = {
      id: 'C-001', category: 'C', query: '¿Qué plazo fija el anexo II?', intent: 'structure-annex', split: 'test',
      scope: { allowed_domes: ['savia-docs'], as_of: null },
      expected: {
        answer_facts: ['30 días'],
        required_evidence: [{ dome: 'savia-docs', document: 'c/marco.md', revision: 'a'.repeat(40), locator: { section: 'Anexo II', quote: 'plazo de preaviso' } }],
        forbidden_evidence: [{ dome: 'savia-docs', document: 'c/marco-v1.md', reason: 'versión derogada' }],
        must_abstain: false, max_unauthorized_reads: 0,
      },
    };
    fs.writeFileSync(path.join(d, 'cases.jsonl'), `${JSON.stringify(r1)}\n${JSON.stringify({ ...r1, id: 'F-001', category: 'F', split: 'dev', scope: { allowed_domes: ['savia-docs'], as_of: '2026-01-01' }, expected: { ...r1.expected, required_evidence: [], must_abstain: true } })}\n`);
    const cases = loadBench(d);
    expect(cases.find(c => c.id === 'C-001')).toMatchObject({
      domes: ['savia-docs'], split: 'test', intent: 'structure-annex',
      required_evidence: [{ document: 'c/marco.md', dome: 'savia-docs', revision: 'a'.repeat(40), locator: 'Anexo II', quote: 'plazo de preaviso' }],
      forbidden_evidence: [{ document: 'c/marco-v1.md', dome: 'savia-docs' }],
    });
    expect(cases.find(c => c.id === 'C-001')!.as_of).toBeUndefined();
    expect(cases.find(c => c.id === 'F-001')!.as_of).toBe('2026-01-01');
    expect(fromR1({ ...r1, extra: 1 })).toMatchObject({ extra: 1 });
    expect(validateCase(fromR1({ ...r1, extra: 1 }))).toContain('campo desconocido: extra');
    expect(fromR1(base)).toBeUndefined();
  });

  it('un split sin casos es un error (no se mide nada)', () => {
    const d = path.join(dir, 'solo-dev');
    fs.mkdirSync(d);
    fs.writeFileSync(path.join(d, 'a.json'), JSON.stringify([base]));
    expect(loadBench(d, { split: 'dev' })).toHaveLength(1);
    expect(() => loadBench(d, { split: 'test' })).toThrow(/vacío para split=test/);
  });

  it('rechaza ids repetidos, casos inválidos y un banco vacío', () => {
    const d = path.join(dir, 'bad');
    fs.mkdirSync(d);
    fs.writeFileSync(path.join(d, 'a.json'), JSON.stringify([base, base]));
    expect(() => loadBench(d)).toThrow(/repetido/);
    fs.writeFileSync(path.join(d, 'a.json'), JSON.stringify([{ ...base, category: 'Q' }]));
    expect(() => loadBench(d)).toThrow(/INVALID_INPUT.*category/);
    fs.writeFileSync(path.join(d, 'a.json'), '[]');
    expect(() => loadBench(d)).toThrow(/vacío/);
    expect(() => loadBench(path.join(dir, 'no-existe'))).toThrow(/INVALID_INPUT/);
  });

  it('el banco de 36 consultas se convierte sin perder casos', () => {
    const legacy = JSON.parse(fs.readFileSync(path.resolve('eval/rag-savia-docs.json'), 'utf-8'));
    const cases = legacyToCases(legacy);
    expect(cases).toHaveLength(legacy.length);
    for (const c of cases) expect(validateCase(c)).toEqual([]);
  });
});

describe('SE-489 evaluateRoute con M0', () => {
  let f: Fixture;
  const denied = new Set<string>();
  beforeAll(async () => {
    f = fixture(['A', 'S']);
    writeDocs(f.dir('A'), {
      'specs/SE-481.md': note('SE-481', long('clasificación con cierre seguro SE-481')),
      'reglas/merge.md': note('Merge', long('nunca fusionar sin permiso de la operadora')),
    });
    writeDocs(f.dir('S'), { 'reservado.md': note('Reservado', long('fusionar secreto reservado')) });
    await f.service().sync('A');
    await f.service().sync('S');
  });
  afterAll(() => f.cleanup());

  const svc = () => {
    const s = f.service();
    return s;
  };

  it('calcula métricas por caso y por categoría, con 0 lecturas no autorizadas', async () => {
    const cases: EvidenceCase[] = [
      { ...base, id: 'A-1', query: 'SE-481', domes: ['A'], required_evidence: [{ document: 'specs/SE-481.md' }] },
      { ...base, id: 'B-1', category: 'B', query: 'fusionar sin permiso', domes: ['A'], required_evidence: [{ document: 'reglas/merge.md' }] },
      { ...base, id: 'F-1', category: 'F', query: 'fusionar secreto reservado', domes: ['A', 'S'], denied_domes: ['S'], required_evidence: [], must_abstain: true, forbidden_evidence: [{ document: 'reservado.md' }] },
    ];
    f.denied.clear();
    const report = await evaluateRoute(svc(), cases, {
      route: 'M0', mode: 'bm25', seed: 1, iterations: 200, deny: (names) => { f.denied.clear(); for (const n of names) f.denied.add(n); },
    });
    void denied;
    expect(report.route).toBe('M0');
    expect(report.n).toBe(3);
    expect(report.overall.unauthorizedReads.mean).toBe(0);
    expect(report.overall.forbiddenUsed.mean).toBe(0);
    expect(report.violations).toBe(0);
    expect(report.overall.evidenceRecall.n).toBe(2);
    expect(report.overall.evidenceRecall.mean).toBe(1);
    expect(report.overall.exactIdentifierHit).toMatchObject({ n: 1, mean: 1 });
    expect(Object.keys(report.byCategory).sort()).toEqual(['A', 'B', 'F']);
    expect(report.latency.p95Ms).toBeGreaterThanOrEqual(report.latency.p50Ms);
    expect(report.rssPeakMb).toBeGreaterThan(0);
    expect(report.cases.find(c => c.id === 'F-1')!.metrics.recallAt5).toBeUndefined();
    expect(report.deniedAttempts).toBe(0);
  });

  it('la cúpula denegada por caso se restablece para el siguiente', async () => {
    const seen: string[][] = [];
    const r = await evaluateRoute(svc(), [
      { ...base, id: 'X-1', query: 'fusionar', domes: ['A', 'S'], denied_domes: ['S'], required_evidence: [{ document: 'reglas/merge.md' }] },
      { ...base, id: 'X-2', query: 'fusionar secreto reservado', domes: ['A', 'S'], required_evidence: [{ document: 'reservado.md', dome: 'S' }] },
      { ...base, id: 'X-3', query: 'fusionar secreto reservado', domes: ['A', 'S'], denied_domes: ['S'], required_evidence: [{ document: 'reservado.md', dome: 'S' }] },
    ], { route: 'M0', mode: 'bm25', seed: 1, iterations: 50, deny: (names) => { seen.push(names); f.denied.clear(); for (const n of names) f.denied.add(n); } });
    // El último [] es el restablecimiento al terminar el banco.
    expect(seen).toEqual([['S'], [], ['S'], []]);
    // X-2 ve S de verdad; X-3, con S denegada otra vez, no.
    expect(r.cases.find(c => c.id === 'X-2')!.metrics.evidenceRecall).toBe(1);
    expect(r.cases.find(c => c.id === 'X-3')!.metrics.evidenceRecall).toBe(0);
  });
});

describe('SE-489 CLI rag eval --route --bench', () => {
  it('saca el informe JSON y compara contra una línea base pareada', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se489-cli-'));
    try {
      const folder = path.join(root, 'a');
      fs.mkdirSync(folder);
      fs.writeFileSync(path.join(folder, 'merge.md'), `# Merge\n\n${long('nunca fusionar sin permiso')}`);
      fs.writeFileSync(path.join(folder, 'otra.md'), `# Otra\n\n${long('garza real')}`);
      const registry = path.join(root, 'domes.json');
      fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'a', domes: { a: { name: 'a', path: folder, description: '', confidentiality: 'N2', rag: { enabled: true } } } }));
      const bench = path.join(root, 'bench');
      fs.mkdirSync(bench);
      fs.writeFileSync(path.join(bench, 'cases.json'), JSON.stringify([
        { ...base, id: 'B-1', category: 'B', query: 'fusionar sin permiso', required_evidence: [{ document: 'merge.md' }] },
        { ...base, id: 'B-2', category: 'B', query: 'garza real', required_evidence: [{ document: 'otra.md' }] },
      ]));
      const run = (...args: string[]) => spawnSync(process.execPath, [
        '--import', pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href,
        path.resolve('src/cli/index.ts'), 'rag', ...args, '--domes-file', registry,
      ], { env: { PATH: process.env.PATH || '', SAVIA_RAG_HOME: path.join(root, 'home'), SAVIA_RAG_TEST_PROVIDER: 'hash' }, encoding: 'utf-8', timeout: 30000 });
      expect(run('sync', '--dome', 'a').status).toBe(0);
      const r = run('eval', '--dome', 'a', '--route', 'M0', '--baseline', 'M0', '--bench', bench, '--mode', 'bm25', '--iterations', '100', '--json');
      expect(r.stderr).not.toMatch(/Error/);
      expect(r.status).toBe(0);
      const out = JSON.parse(r.stdout);
      expect(out.reports[0]).toMatchObject({ route: 'M0', n: 2, violations: 0 });
      expect(out.reports[0].overall.evidenceRecall.mean).toBe(1);
      expect(out.comparisons[0]).toMatchObject({ route: 'M0', baseline: 'M0' });
      expect(out.comparisons[0].overall.evidenceRecall).toMatchObject({ diff: 0, lo: 0, hi: 0 });
      // Sin --route ni --bench: el informe de siempre (compatibilidad del runner SE-410).
      const legacyFile = path.join(root, 'legacy.json');
      fs.writeFileSync(legacyFile, JSON.stringify([{ kind: 'lexical', query: 'garza real', relevantPaths: ['otra.md'] }]));
      const legacy = run('eval', '--dome', 'a', '--queries', legacyFile, '--mode', 'bm25', '--json');
      expect(legacy.status).toBe(0);
      expect(JSON.parse(legacy.stdout)).toEqual([expect.objectContaining({ mode: 'bm25', n: 1, recallAt10: 1 })]);
      expect(JSON.parse(legacy.stdout)[0].reports).toBeUndefined();
      // --route sobre el banco de regresión: los mismos casos, ahora con métricas de evidencia.
      const routedLegacy = JSON.parse(run('eval', '--dome', 'a', '--route', 'M0', '--queries', legacyFile, '--mode', 'bm25', '--iterations', '50', '--json').stdout);
      expect(routedLegacy.reports[0]).toMatchObject({ route: 'M0', n: 1 });
      expect(routedLegacy.reports[0].byCategory.A.evidenceRecall.mean).toBe(1);
      // Códigos de salida: parámetros inválidos y casos con error no salen 0.
      const zero = run('eval', '--dome', 'a', '--route', 'M0', '--bench', bench, '--iterations', '0', '--json');
      expect(zero.status).toBe(1);
      expect(zero.stderr).toMatch(/iterations/);
      expect(run('eval', '--dome', 'a', '--route', 'M0', '--bench', bench, '--k', '0', '--json').status).toBe(1);
      fs.writeFileSync(path.join(bench, 'mal.json'), JSON.stringify([{ ...base, id: 'D-1', category: 'D', query: 'garza real', domes: ['no-existe'], required_evidence: [{ document: 'otra.md' }] }]));
      const bad = run('eval', '--dome', 'a', '--route', 'M0', '--bench', bench, '--mode', 'bm25', '--iterations', '50', '--json');
      expect(bad.status).toBe(1);
      expect(bad.stderr).toMatch(/D-1: UNKNOWN_DOME/);
      expect(JSON.parse(bad.stdout).reports[0].errors).toBe(1);
      fs.rmSync(path.join(bench, 'mal.json'));
      expect(run('eval', '--dome', 'a', '--route', ',', '--bench', bench, '--json').stderr).toMatch(/al menos una ruta/);
      expect(run('eval', '--dome', 'a', '--route', '', '--queries', legacyFile, '--json').stderr).toMatch(/al menos una ruta/);
      expect(run('eval', '--dome', 'a', '--route', 'M0', '--queries', legacyFile, '--split', 'test', '--json').stderr).toMatch(/--split solo vale con --bench/);
      expect(run('eval', '--dome', 'a', '--queries', legacyFile, '--baseline', 'M0', '--json').stderr).toMatch(/solo valen con --route/);
      expect(run('eval', '--dome', 'a', '--route', 'M0', '--bench', bench, '--split', 'test', '--json').stderr).toMatch(/vacío para split=test/);
      const ruta = run('eval', '--dome', 'a', '--route', 'M99', '--bench', bench, '--json');
      expect(ruta.status).toBe(1);
      expect(ruta.stderr).toMatch(/UNKNOWN_ROUTE/);
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
  }, 60_000);
});
