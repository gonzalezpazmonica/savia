import * as fs from 'node:fs';
import * as path from 'node:path';
import { check, config, fixture, paths } from './common.js';
import { processTerm } from '../../src/rag/retriever.js';
import { exceedsDomeLevel, parseClassification } from '../../src/storage/note-level.js';
import { VaultStorage } from '../../src/storage/index.js';
import { ProvenanceEngine } from '../../src/knowledge/provenance.js';
import { detectConflicts } from '../../src/knowledge/conflicts.js';
import { promotionDecision, resolveRagConfig } from '../../src/rag/policy.js';
import { readActive, FlatVectorStore, generationId } from '../../src/rag/store.js';
import { HashEmbedder } from '../../src/rag/embedder.js';
import { RagService } from '../../src/rag/service.js';
import { FileStore } from '../../src/files/store.js';
import { FilesService } from '../../src/files/service.js';
import { fileSources } from '../../src/files/rag-source.js';
import { formatRagResponse } from '../../src/rag/format.js';
import type { ExtractionStatus } from '../../src/files/types.js';
import type { Principal } from '../../src/files/policy.js';
import type { Chunk, Manifest } from '../../src/rag/types.js';

async function H1() {
  const f = fixture('h1');
  const inputs = {
    'broken.md': '---\nconfidentiality: N3\ninvalid: [\n---\n# Auditoría\nquasar metadatos rotos',
    'nokey-broken.md': '---\ninvalid: [\n---\n# Auditoría\nquasar yaml roto sin clave de nivel',
    'unknown.md': '---\nconfidentiality: TOPSECRET\n---\n# Auditoría\nquasar nivel desconocido',
    'invalid-date.md': '---\nvalid_until: not-a-date\n---\n# Auditoría\nquasar fecha no válida',
    'public.md': '---\nconfidentiality: N2\n---\n# Auditoría\nquasar permitido',
    'secret.md': '---\nconfidentiality: N3\n---\n# Auditoría\nquasar reservado',
    'expired.md': '---\nvalid_until: 2000-01-01\n---\n# Auditoría\nquasar caducado',
  };
  for (const [p, raw] of Object.entries(inputs)) f.put(p, raw);
  await f.rag.sync('h1');
  const r = await f.query('quasar');
  const served = paths(r).sort();
  // SE-481 R1/R2: YAML roto que menciona el nivel y nivel desconocido quedan en cuarentena.
  check('H1', served, ['invalid-date.md', 'nokey-broken.md', 'public.md']);
  check('H1-level-control', exceedsDomeLevel('N3', 'N2'), true);
  check('H1-unknown', exceedsDomeLevel('TOPSECRET', 'N2'), true);
  check('H1-yaml-kind', parseClassification('broken.md', inputs['broken.md']).kind, 'UNPARSABLE');
  check('H1-unknown-kind', parseClassification('unknown.md', inputs['unknown.md']).kind, 'UNKNOWN_LEVEL');
  // Control negativo: YAML roto que no menciona la clave mantiene la semántica heredada (ABSENT).
  check('H1-nokey-kind', parseClassification('nokey-broken.md', inputs['nokey-broken.md']).kind, 'ABSENT');
  const dateOpen = served.includes('invalid-date.md');
  return { verdict: dateOpen ? 'PARTIALLY_CONFIRMED' : 'ALREADY_SOLVED', returned: served,
    components: {
      brokenYamlMentioningLevel: 'ALREADY_SOLVED (SE-481 R1/R2: cuarentena)',
      unknownLevel: 'ALREADY_SOLVED (SE-481: exceedsDomeLevel cierra de forma segura)',
      invalidValidUntil: dateOpen ? 'CONFIRMED: `Date.parse` devuelve NaN y la nota se sirve (policy.ts:35)' : 'ALREADY_SOLVED',
    },
    negativeControls: 'N3 válida y fecha caducada excluidas; YAML roto sin clave de nivel sigue como ABSENT', response: r };
}

async function H2() {
  const f = fixture('h2');
  const corpus = {
    'permitido.md': '# Norma A\nEstá permitido exportar el informe sintético.',
    'prohibido.md': '# Norma B\nNo está permitido exportar el informe sintético.',
    'autorizado.md': '# Norma C\nExportar con autorización.',
    'sin-autorizacion.md': '# Norma D\nExportar sin autorización.',
    'expediente.md': '# Caso E\nE-1047: calibración de válvula.',
    'expediente-vecino.md': '# Caso F\nE-1048: calibración de turbina.',
    'contrato.md': '# Caso G\nCT-2026-047: contrato sintético de válvula.',
    'contrato-vecino.md': '# Caso H\nCT-2026-048: contrato sintético de turbina.',
    'ruido.md': '# Jardinería\nAzaleas y violetas.',
  };
  for (const [p, text] of Object.entries(corpus)) f.put(p, text);
  await f.rag.sync('h2');
  const queries = ['permitido exportar informe', 'no permitido exportar informe', 'exportar con autorización',
    'exportar sin autorización', 'no', 'not', 'ni', 'sin', 'nada', 'E-1047', 'CT-2026-047', 'E-9999', 'CT-2099-999', 'azaleas'];
  const observations = [];
  for (const query of queries) {
    const r = await f.query(query);
    observations.push({ query, hits: r.results[0].hits.map(h => ({ path: h.path, score: h.score, bm25: h.signals.bm25, text: h.text })) });
  }
  const top = (i: number) => observations[i].hits[0]?.path;
  const ids = (i: number) => observations[i].hits.map(h => h.path);
  // SE-481 R5: las negaciones puntúan y la polaridad cambia el primer resultado.
  check('H2-pair-affirmative', top(0), 'permitido.md');
  check('H2-pair-negated', top(1), 'prohibido.md');
  check('H2-pair-sin', top(3), 'sin-autorizacion.md');
  check('H2-pair-differs', JSON.stringify(observations[0].hits) === JSON.stringify(observations[1].hits), false);
  check('H2-sin-differs', JSON.stringify(observations[2].hits) === JSON.stringify(observations[3].hits), false);
  check('H2-stopwords', ['no', 'not', 'ni', 'sin', 'nada'].map(processTerm), ['no', 'not', 'ni', 'sin', 'nada']);
  check('H2-stopword-control', processTerm('de'), null);
  check('H2-negation-only', [4, 5, 6, 7, 8].map(ids), [['prohibido.md'], [], [], ['sin-autorizacion.md'], []]);
  check('H2-id-E', ids(9), ['expediente.md', 'expediente-vecino.md']);
  check('H2-id-E-ranking', observations[9].hits[0].bm25 > observations[9].hits[1].bm25, true);
  check('H2-id-CT', ids(10), ['contrato.md', 'contrato-vecino.md']);
  check('H2-id-CT-ranking', observations[10].hits[0].bm25 > observations[10].hits[1].bm25, true);
  check('H2-id-absent-E', ids(11), []);
  check('H2-id-absent-CT', ids(12).sort(), ['contrato-vecino.md', 'contrato.md']);
  check('H2-control', ids(13), ['ruido.md']);
  return { verdict: ids(12).length > 0 ? 'PARTIALLY_CONFIRMED' : 'ALREADY_SOLVED', corpus, observations,
    components: {
      negationStopwords: 'ALREADY_SOLVED (SE-481 R5)',
      idRanking: 'ALREADY_SOLVED: el identificador exacto queda primero',
      absentIdentifier: 'CONFIRMED (matizado): `CT-2099-999` inexistente devuelve ambos contratos; el token suelto `ct` casa por OR en BM25, no es una ausencia general de abstención (`E-9999` no devuelve nada porque `e` es stopword)',
    },
    scope: 'Recuperación y puntuación; sin generador de respuestas ni inferencia sobre su veracidad.' };
}

async function H3() {
  const f = fixture('h3');
  for (const [p, value] of [['a.md', 'permitido'], ['b.md', 'prohibido']]) {
    f.put(p, `---\nentity: { id: norma, type: document }\nexportacion: ${value}\nsource_type: primary\nassertions:\n  - { property: exportacion, value: ${value} }\n---\n# Norma\nNebulosa: exportación ${value}.`);
  }
  const storage = new VaultStorage(config(f.vault));
  const notes = await Promise.all(['a.md', 'b.md'].map(p => storage.read(p)));
  const conflicts = detectConflicts(notes);
  const provenance = new ProvenanceEngine(config(f.vault));
  const assertions = (await Promise.all(['a.md', 'b.md'].map(p => provenance.extractAssertions(p)))).flat();
  check('H3-detection', conflicts.some(c => c.property === 'exportacion'), true);
  check('H3-provenance', provenance.findConflicts('norma', assertions).length, 1);
  check('H3-negative', detectConflicts([notes[0]]).length, 0);
  await f.rag.sync('h3');
  const r = await f.query('nebulosa');
  check('H3-both', paths(r).sort(), ['a.md', 'b.md']);
  check('H3', /"(?:conflicts|assertions|sourceType|source_type)"/.test(JSON.stringify(r)), false);
  return { verdict: 'CONFIRMED', conflicts: conflicts.map(({ id: _id, ...c }) => c), assertions, response: r,
    qualification: 'RAG conserva ruta/heading/generación y source para Files; falta la procedencia estructurada de Knowledge y el aviso de conflicto.' };
}

async function H4() {
  const first = promotionDecision({ coverage: 1, hasActive: false });
  check('H4', first.promote, true);
  const below = promotionDecision({ coverage: 0.999999, hasActive: false });
  const later = promotionDecision({ coverage: 1, hasActive: true });
  check('H4-coverage', below.promote, false);
  check('H4-later', later.promote, false);
  const f = fixture('h4');
  f.put('a.md', '# Norma\nPulsar primera promoción.');
  const report = await f.rag.sync('h4');
  const pointer = readActive(f.home, 'h4');
  check('H4-active', Boolean(pointer.active), true);
  check('H4-no-baseline', pointer.metrics, undefined);
  // Banco explícito con recall cero: la primera generación ya está activa cuando se registra.
  const bad = fixture('h4bad');
  bad.put('a.md', '# Norma\nPulsar primera promoción.');
  bad.put('eval.json', JSON.stringify([{ query: 'pulsar', relevantPaths: ['inexistente.md'] }]));
  bad.dome.rag!.evalSet = 'eval.json';
  const badReport = await bad.rag.sync('h4bad');
  const badPointer = readActive(bad.home, 'h4bad');
  check('H4-zero', badPointer.metrics?.[badPointer.active!].recallAt10, 0);
  check('H4-zero-active', badReport.promoted, true);
  const invalidCoverage = promotionDecision({ coverage: Number.NaN, hasActive: false });
  check('H4-NaN', invalidCoverage.promote, true);
  return { verdict: 'CONFIRMED', first, below, later, report, pointer, badReport, badPointer,
    extra: 'La función pura acepta coverage=NaN; no se demuestra alcance externo con una manifest normal.' };
}

async function H5() {
  const f = fixture('h5', 'N2', true);
  const store = new FileStore({ home: process.env.SAVIA_FILES_HOME!, dome: 'h5', keysHome: process.env.SAVIA_FILES_KEYS_HOME! });
  const documents: Record<string, string> = {};
  for (const status of ['READY', 'PARTIAL', 'FAILED', 'PENDING', 'ARCHIVE_ONLY', 'QUARANTINED'] as ExtractionStatus[]) {
    const added = store.add({ name: `${status.toLowerCase()}.txt`, bytes: Buffer.from(`helio ${status}`) });
    documents[status] = added.document.id;
    store.saveExtraction(added.revision.id, { units: [{ locator: { type: 'page', page: 1 }, kind: 'text', text: `helio ${status}` }] },
      { status, method: 'synthetic-audit-fixture', units: 2, extracted: 1, skipped: [{ reason: 'synthetic-page-omitted', count: 1 }] }, added.document.id);
  }
  check('H5-indexable', fileSources(store).map(s => s.path).sort(), [documents.READY, documents.PARTIAL].map(id => `files/${id}`).sort());
  await f.rag.sync('h5');
  const r = await f.query('helio');
  const partial = r.results[0].hits.find(h => h.source?.documentId === documents.PARTIAL);
  check('H5-hit', Boolean(partial), true);
  const full = formatRagResponse(r, { fields: 'full', maxChars: 10000 });
  const lean = formatRagResponse(r, { fields: 'lean', maxChars: 10000 });
  check('H5', Object.hasOwn(partial!.source!, 'status') || Object.hasOwn(partial!, 'extraction'), false);
  check('H5-skipped', full.includes('synthetic-page-omitted') || lean.includes('synthetic-page-omitted'), false);
  return { verdict: 'CONFIRMED', documents, extraction: store.get(documents.PARTIAL).revisions[0].extraction,
    response: r, full: JSON.parse(full), lean: JSON.parse(lean),
    fixtureMethod: 'Inyección de estados de extracción mediante FileStore.saveExtraction, sin simular un worker real. PARTIAL aparece en texto/nombre sintético, pero no como campo de estado.' };
}

async function H6() {
  const f = fixture('h6', 'N2', true);
  f.put('removed.md', '# Borrado\nzirconio nota eliminable');
  f.put('kept.md', '# Intacta\nzirconio nota sin cambios');
  f.put('raised.md', '---\nconfidentiality: N2\n---\n# Nivel\nzirconio nota reclasificable');
  let who: Principal | undefined = { username: 'audit-admin', role: 'admin' };
  const authorize = async () => who;
  const rag = new RagService({ domes: () => [f.dome], home: f.home, env: process.env, authorize,
    embedderFactory: cfg => new HashEmbedder(64, cfg, cfg.model) });
  const files = new FilesService({ domes: () => [f.dome], env: process.env, scanMode: 'off', authorize, onChange: () => undefined });
  const doc = await files.put({ dome: 'h6', name: 'acl.txt', contentBase64: Buffer.from('zirconio documento restringible').toString('base64') });
  const query = (includeStale = false) => rag.search({ queries: ['zirconio'], domes: ['h6'], mode: 'bm25', k: 20, includeStale });
  await rag.sync('h6');
  who = { username: 'audit-reader', role: 'reader' };
  const before = await query();
  check('H6-before', paths(before).length, 4);
  check('H6-memory', rag.loadedMemoryBytes() > 0, true);
  const seq = f.store().manifest.seq;
  who = { username: 'audit-admin', role: 'admin' };
  await files.policy({ dome: 'h6', id: doc.documentId, readers: [] });
  fs.unlinkSync(path.join(f.vault, 'removed.md'));
  f.put('raised.md', '---\nconfidentiality: N3\n---\n# Nivel\nzirconio nota reclasificable ahora reservada');
  who = { username: 'audit-reader', role: 'reader' };
  const after = await query();
  const stale = await query(true);
  // SE-481 R3: borrada, reclasificada y fichero revocado desaparecen sin sync; la nota intacta sigue.
  check('H6', paths(after), ['kept.md']);
  check('H6-stale', paths(stale), ['kept.md']);
  check('H6-no-sync', f.store().manifest.seq, seq);
  const storage = new VaultStorage(config(f.vault));
  await checkRejected(() => storage.read('raised.md'), 'H6-live-level');
  await checkRejected(() => storage.read('removed.md'), 'H6-live-delete');
  await checkRejected(() => files.get({ dome: 'h6', id: doc.documentId }), 'H6-acl-negative');
  // Un principal aún autorizado mantiene acceso; después se comprueba borrado de fichero.
  who = { username: 'audit-admin', role: 'admin' };
  check('H6-admin', paths(await query()).includes(`files/${doc.documentId}`), true);
  await files.delete({ dome: 'h6', id: doc.documentId });
  check('H6-file-delete', paths(await query(true)).includes(`files/${doc.documentId}`), false);
  await rag.sync('h6');
  check('H6-after-sync', paths(await query()), ['kept.md']);
  // Presupuesto por defecto: un lote mayor que el presupuesto impide el sync inline, pero los
  // hits se revalidan al servir. El estado `stale` prueba que el sync inline no actuó.
  const defaults = fixture('h6default');
  const budget = resolveRagConfig({ enabled: true }).inlineSyncBudget;
  delete defaults.dome.rag!.inlineSyncBudget;
  defaults.put('kept.md', '# Intacta\nxenon contenido que permanece');
  for (let i = 0; i <= budget; i++) defaults.put(`${i}.md`, '# Lote\nxenon contenido');
  await defaults.rag.sync('h6default');
  for (let i = 0; i <= budget; i++) fs.unlinkSync(path.join(defaults.vault, `${i}.md`));
  const defaultAfter = await defaults.query('xenon');
  check('H6-default', paths(defaultAfter), ['kept.md']);
  // Control negativo: con presupuesto suficiente el sync inline sí actúa y el dominio no queda stale.
  const sized = fixture('h6sized');
  sized.dome.rag!.inlineSyncBudget = budget + 5;
  sized.put('kept.md', '# Intacta\nxenon contenido que permanece');
  for (let i = 0; i <= budget; i++) sized.put(`${i}.md`, '# Lote\nxenon contenido');
  await sized.rag.sync('h6sized');
  for (let i = 0; i <= budget; i++) fs.unlinkSync(path.join(sized.vault, `${i}.md`));
  const sizedAfter = await sized.query('xenon');
  check('H6-default-control', paths(sizedAfter), ['kept.md']);
  check('H6-default-control-fresh', sizedAfter.domes[0].status !== 'stale', true);
  check('H6-default-stale', defaultAfter.domes[0].status, 'stale');
  return { verdict: 'ALREADY_SOLVED', components: {
    filesAcl: 'ALREADY_SOLVED: deniega con índice en memoria y seq idéntico', filesDelete: 'ALREADY_SOLVED',
    markdownDelete: 'ALREADY_SOLVED (SE-481 R3)', markdownRaise: 'ALREADY_SOLVED (SE-481 R3)',
    defaultBudget: 'ALREADY_SOLVED (SE-481 R3): revalidación al servir con sync inline omitido',
    bundles: 'NOT_REPRODUCED: superficie inexistente',
  }, before, after, includeStale: stale, defaultBudget: budget, defaultBatch: budget + 1, defaultAfter };
}

async function checkRejected(fn: () => Promise<unknown>, label: string) {
  let rejected = false;
  try { await fn(); } catch { rejected = true; }
  check(label, rejected, true);
}

async function H7() {
  const f = fixture('h7');
  f.put('norma.md', '# Norma\nNo está permitido exportar plutonio.');
  await f.rag.sync('h7');
  const good = await f.rag.evaluate('h7', [{ query: 'permitido exportar plutonio', relevantPaths: ['norma.md'] }], { mode: 'bm25' });
  const bad = await f.rag.evaluate('h7', [{ query: 'permitido exportar plutonio', relevantPaths: ['otra.md'] }], { mode: 'bm25' });
  check('H7', [good.recallAt5, good.recallAt10, good.mrr], [1, 1, 1]);
  check('H7-negative', [bad.recallAt10, bad.mrr], [0, 0]);
  check('H7-answer', Object.keys(good).some(k => /answer|citation|polarity|conflict|absten/i.test(k)), false);
  return { verdict: 'PARTIALLY_CONFIRMED', good, bad,
    qualification: 'CONFIRMED para RagService.evaluate: puntúa rutas, no respuestas. No equivale a ausencia de tests E2E de transporte, permisos, citas y formato en el repo.' };
}

async function H8() {
  const f = fixture('h8');
  const contract = await new HashEmbedder(3).contract();
  const gen = generationId(contract);
  const chunks: Chunk[] = [0, 1, 2, 3].map(i => ({ id: `${i}.md#0`, path: `${i}.md`, ordinal: 0, heading: 'Sintético', text: `v${i}`, embedText: `v${i}`, hash: `${i}`, meta: { title: 'Sintético', modified: '2026-10-01' } }));
  const vectors = [[1, 0, 0], [0.8, 0.6, 0], [0, 0, 1], [-1, 0, 0]].map(v => new Float32Array(v));
  const manifest: Manifest = { version: 1, dome: 'h8', generation: gen, contract, seq: 1, createdAt: '2026-10-01', updatedAt: '2026-10-01', docs: {}, chunkCount: 4, fingerprint: 'synthetic' };
  const dir = path.join(f.root, gen);
  FlatVectorStore.write(dir, manifest, chunks, vectors);
  const store = FlatVectorStore.load(dir);
  const visited: number[] = [];
  const hits = store.topK(new Float32Array([1, 0, 0]), 3, i => { visited.push(i); return true; });
  check('H8', hits.map(h => h.index), [0, 1, 2]);
  check('H8-visited', visited, [0, 1, 2, 3]);
  check('H8-filter', store.topK(new Float32Array([1, 0, 0]), 1, i => i !== 0).map(h => h.index), [1]);
  let mismatch = false;
  try { store.topK(new Float32Array([1, 0]), 1); } catch { mismatch = true; }
  check('H8-dims', mismatch, true);
  return { verdict: 'CONFIRMED', defect: false, hits, visited,
    qualification: 'Producto escalar exacto y recorrido completo. Sin benchmark que justifique ANN; no se extrapola rendimiento de cuatro vectores.' };
}

export const probes = { H1, H2, H3, H4, H5, H6, H7, H8 };
