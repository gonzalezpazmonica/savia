import { sha256Json } from './canon.js';
import { BENCH_SCHEMA_VERSION, STRATA, type BenchCorpus, type BenchDataset, type BenchDoc, type BenchQuery, type BenchVault, type Split, type Stratum } from './types.js';

// SE-395 R01 — corpus y dataset sintéticos, deterministas por semilla. Las etiquetas
// (relevant/useful/forbidden) salen de la construcción del corpus, nunca de un router.
export const DEFAULT_SEED = 395;
const QUERIES_PER_STRATUM = 20;
const VARIANTS = 5;

const VAULTS: BenchVault[] = [
  { id: 'local', name: 'Local', weight: 1, local: true },
  { id: 'beta', name: 'Beta', weight: 1, local: false },
  { id: 'gamma', name: 'Gamma', weight: 0.8, local: false },
  { id: 'delta', name: 'Delta', weight: 0.5, local: false },
];
// Dominio d -> vault de origen y vault donde vive la copia enlazada (tópicos cross).
const HOME = ['local', 'beta', 'gamma', 'delta'];
const LINK = ['beta', 'gamma', 'delta', 'local'];
const FILLER = [
  ['sprint', 'backlog', 'velocidad', 'capacidad', 'riesgo', 'entrega', 'equipo', 'ritual'],
  ['factura', 'cobro', 'asiento', 'balance', 'partida', 'mayor', 'cierre', 'tasa'],
  ['despliegue', 'rama', 'pipeline', 'artefacto', 'versión', 'rollback', 'canal', 'entorno'],
  ['alumno', 'rúbrica', 'tarea', 'portafolio', 'curso', 'nota', 'sesión', 'diario'],
];
const SYL = ['ba', 'ke', 'di', 'lo', 'mu', 'na', 'ri', 'so', 'tu', 've', 'xa', 'zo'];

// Roles de tópico por posición dentro del dominio.
const ROLE = ['mono', 'cross', 'conflict', 'stale', 'restricted', 'unhealthy', 'new'] as const;

export function prng(seed: number): () => number {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// Split por familia de intención (tópico). Estratificado por rol: en cada rol los dominios 0-1 van a
// train, el 2 a calibration y el 3 a test, de modo que cada estrato tiene consultas en los tres splits.
function splitOf(domain: number): Split { return domain <= 1 ? 'train' : domain === 2 ? 'calibration' : 'test'; }

interface Topic { id: string; domain: number; role: typeof ROLE[number]; anchors: [string, string]; docs: BenchDoc[]; }

export function generateCorpus(seed = DEFAULT_SEED): { corpus: BenchCorpus; topics: Topic[] } {
  const rand = prng(seed);
  const used = new Set<string>();
  const word = (): string => { for (;;) { const w = SYL[Math.floor(rand() * 12)] + SYL[Math.floor(rand() * 12)] + SYL[Math.floor(rand() * 12)]; if (!used.has(w)) { used.add(w); return w; } } };
  const topics: Topic[] = []; const docs: BenchDoc[] = []; const conflictPairs: Array<[string, string]> = [];
  for (let d = 0; d < 4; d++) {
    ROLE.forEach((role, t) => {
      const id = `d${d}t${t}`;
      const anchors: [string, string] = [word(), word()];
      const filler = (n: number): string => Array.from({ length: n }, () => FILLER[d][Math.floor(rand() * 8)]).join(' ');
      const mk = (n: number, vault: string, extra = '', stale = false, useful = true): BenchDoc => {
        const doc = { id: `${vault}/${id}-${n}.md`, vault, topic: id, text: `${anchors[0]} ${anchors[1]} ${filler(8)} ${extra}`.trim(), stale, useful };
        docs.push(doc); return doc;
      };
      const own: BenchDoc[] = [];
      const hasLink = role === 'cross' || role === 'restricted' || role === 'unhealthy' || role === 'conflict';
      if (role === 'conflict') { own.push(mk(0, HOME[d], 'permitido'), mk(1, LINK[d], 'prohibido')); conflictPairs.push([own[0].id, own[1].id]); mk(2, HOME[d], '', false, false); }
      else if (role === 'stale') { own.push(mk(0, HOME[d], 'vigente'), mk(1, HOME[d], 'obsoleto', true, false), mk(2, HOME[d], '', false, true)); }
      else { own.push(mk(0, HOME[d]), mk(1, HOME[d]), mk(2, HOME[d], '', false, false)); if (hasLink) { own.push(mk(3, LINK[d]), mk(4, LINK[d], '', false, false)); } }
      topics.push({ id, domain: d, role, anchors, docs: docs.filter(x => x.topic === id) });
    });
  }
  return { corpus: { schemaVersion: BENCH_SCHEMA_VERSION, seed, vaults: VAULTS, docs, conflictPairs }, topics };
}

export function generateDataset(seed = DEFAULT_SEED): { corpus: BenchCorpus; dataset: BenchDataset } {
  const { corpus, topics } = generateCorpus(seed);
  const corpusSha256 = sha256Json(corpus);
  const allVaults = VAULTS.map(v => v.id);
  const byRole = (role: string): Topic[] => topics.filter(t => t.role === role);
  const queries: BenchQuery[] = [];
  const text = (t: Topic, v: number, extra = ''): string => {
    const f = FILLER[t.domain];
    const variants = [`${t.anchors[0]} ${t.anchors[1]}`, `${t.anchors[0]} ${f[0]}`, `${t.anchors[1]} ${f[1]}`, `${t.anchors[0]} ${t.anchors[1]} ${f[2]}`, `${f[3]} ${t.anchors[1]}`];
    return `${variants[v % VARIANTS]} ${extra}`.trim();
  };
  const push = (stratum: Stratum, n: number, t: Topic, q: string, o: Partial<BenchQuery>): void => {
    const family = t.id;
    const rel = (o.relevant ?? t.docs.filter(d => !d.stale).map(d => d.id));
    queries.push({
      id: `${stratum}-${String(n).padStart(2, '0')}`, stratum, family, split: splitOf(t.domain), query: q,
      allowedVaults: allVaults, unhealthyVaults: [], relevant: rel,
      useful: t.docs.filter(d => d.useful && rel.includes(d.id)).map(d => d.id), forbidden: [], conflictPairs: [], baselineAdvantage: false, ...o,
    });
  };
  const each = (role: string, stratum: Stratum, fn: (t: Topic, v: number, n: number) => void): void => {
    let n = 0; for (let v = 0; v < VARIANTS; v++) for (const t of byRole(role)) fn(t, v, n++);
    if (n !== QUERIES_PER_STRATUM) throw new Error(`${stratum}: ${n} consultas`);
  };

  each('mono', 'monodomain', (t, v, n) => push('monodomain', n, t, text(t, v), { baselineAdvantage: t.domain === 0 }));
  each('cross', 'cross_domain', (t, v, n) => push('cross_domain', n, t, text(t, v), { baselineAdvantage: t.domain === 3 }));
  // Ambiguas: un término compartido entre dos tópicos; la relevancia es solo del tópico intencionado.
  const mono = byRole('mono');
  for (let i = 0; i < 4; i++) {
    const t = mono[i]; const other = mono[i ^ 1];
    for (let v = 0; v < VARIANTS; v++) {
      const q = `${t.anchors[0]} ${other.anchors[0]} ${FILLER[t.domain][v]}`;
      push('ambiguous', i * VARIANTS + v, t, q, {});
    }
  }
  each('conflict', 'conflicting', (t, v, n) => push('conflicting', n, t, text(t, v), { conflictPairs: corpus.conflictPairs.filter(p => t.docs.some(d => d.id === p[0])) }));
  each('stale', 'stale', (t, v, n) => push('stale', n, t, text(t, v), { relevant: t.docs.filter(d => !d.stale).map(d => d.id) }));
  each('restricted', 'restricted', (t, v, n) => {
    const home = HOME[t.domain]; const allowed = allVaults.filter(x => x !== home);
    const rel = t.docs.filter(d => allowed.includes(d.vault)).map(d => d.id);
    push('restricted', n, t, text(t, v), { allowedVaults: allowed, relevant: rel, forbidden: t.docs.filter(d => d.vault === home).map(d => d.id) });
  });
  each('unhealthy', 'unhealthy', (t, v, n) => {
    const remote = t.docs.find(d => d.vault !== 'local')!.vault;
    push('unhealthy', n, t, text(t, v), { unhealthyVaults: [remote] });
  });
  // Repetidas: texto idéntico; la segunda ejecución es la que ejercita la cache.
  mono.forEach((t, i) => { for (let v = 0; v < VARIANTS; v++) push('repeated', i * VARIANTS + v, t, text(t, 0), {}); });
  each('new', 'new', (t, v, n) => push('new', n, t, text(t, v), {}));

  const dataset: BenchDataset = { schemaVersion: BENCH_SCHEMA_VERSION, seed, corpusSha256, queries };
  return { corpus, dataset };
}

export { STRATA };
