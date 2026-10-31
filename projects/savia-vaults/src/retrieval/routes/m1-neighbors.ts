// SE-489 M1 — ampliación acotada al padre (sección contenedora) y a los vecinos del mismo
// documento. Parte de los candidatos de M0 y añade, para los mejores, el chunk de la sección
// padre y los chunks contiguos del mismo documento. Garantías:
//   - los `ceil(k/2)` primeros hits de M0 conservan su posición (R@5 no puede bajar con k=10);
//   - cada chunk añadido sale de `ctx.documentChunks` (guard sobre el documento, 1 `nodes`) y se
//     comprueba otra vez con `ctx.evidenceOf` antes de incluirlo;
//   - presupuesto por documento (`perDoc`, variante de `maxChunksPerDoc`) y por petición
//     (`maxNodes`, `maxHops`: un nivel de expansión por salto; nivel 1 = padre y ±1, nivel 2 =
//     abuelo y ±2);
//   - sin ciclos: `visited` por chunkId.
// Variantes: M1 (2 por documento, el valor actual), M1-c3 y M1-c4.
import { RAG_LIMITS, type RagHit } from '../../rag/types.js';
import {
  ROUTE_CONTRACT_VERSION, registerRoute,
  type OpenedChunk, type RetrievalRoute,
} from '../route.js';

const SEP = ' › ';
/** Fracción de la lista que conserva la posición de M0 y fracción de huecos para ampliaciones. */
const anchorCount = (k: number): number => Math.ceil(k / 2);
const expansionSlots = (k: number): number => Math.floor(k / 3);

/** Primer chunk cuyo encabezado es el del ancestro más cercano (distinto del propio chunk). */
function parentOf(chunks: OpenedChunk[], of: OpenedChunk): OpenedChunk | undefined {
  const parts = of.heading.split(SEP);
  for (let n = parts.length - 1; n >= 1; n--) {
    const h = parts.slice(0, n).join(SEP);
    const c = chunks.find(x => x.heading === h && x.chunkId !== of.chunkId);
    if (c) return c;
  }
  return undefined;
}

export function makeNeighborsRoute(id: string, perDoc: number): RetrievalRoute {
  return {
    id,
    description: `Híbrido + padre y vecinos del mismo documento (máx. ${perDoc} chunks por documento)`,
    contractVersion: ROUTE_CONTRACT_VERSION,
    supportsAsOf: false,
    requiresDeclaredBudget: false,
    async run(req, ctx) {
      const seeds = await ctx.candidates(req.query, { k: req.k, mode: req.mode });
      const anchors = seeds.slice(0, anchorCount(req.k));
      const rest = seeds.slice(anchors.length);
      const visited = new Set(seeds.map(h => h.chunkId));
      const count = new Map<string, number>();
      for (const h of seeds) count.set(`${h.dome}\u0000${h.path}`, (count.get(`${h.dome}\u0000${h.path}`) ?? 0) + 1);

      const docs = new Map<string, OpenedChunk[] | null>();
      const open = (h: RagHit): OpenedChunk[] | null => {
        const key = `${h.dome}\u0000${h.path}`;
        if (!docs.has(key)) {
          const c = ctx.documentChunks({ dome: h.dome, path: h.path, ...(h.source ? { documentId: h.source.documentId } : {}) });
          docs.set(key, c ?? null);
        }
        return docs.get(key)!;
      };

      const per = Math.max(200, Math.floor((req.maxChars ?? RAG_LIMITS.defaultMaxChars) / req.k));
      const slots = expansionSlots(req.k);
      const added: RagHit[] = [];
      // Referencia de cada nivel por ancla: el chunk desde el que se amplía (el padre del nivel anterior).
      const from = new Map<string, OpenedChunk>();
      let level = 0;
      while (added.length < slots && level < req.budget.maxHops && ctx.consume('hops')) {
        level++;
        let progress = false;
        for (const a of anchors) {
          if (added.length >= slots) break;
          const key = `${a.dome}\u0000${a.path}`;
          if ((count.get(key) ?? 0) >= perDoc) continue;
          const chunks = open(a);
          if (!chunks) continue;
          const self = chunks.find(c => c.chunkId === a.chunkId);
          if (!self) continue;
          const parent = parentOf(chunks, from.get(a.chunkId) ?? self);
          if (parent) from.set(a.chunkId, parent);
          const wanted = [parent, ...[-level, level].map(d => chunks.find(c => c.ordinal === self.ordinal + d))];
          for (const c of wanted) {
            if (!c || visited.has(c.chunkId) || added.length >= slots || (count.get(key) ?? 0) >= perDoc) continue;
            const text = c.text.length > per ? `${c.text.slice(0, per - 1)}…` : c.text;
            const hit: RagHit = {
              dome: a.dome, confidentiality: a.confidentiality, path: a.path, chunkId: c.chunkId, heading: c.heading, text,
              score: a.score * (1 - 0.01 * (added.length + 1)), signals: {}, freshness: a.freshness, generation: a.generation,
              ...(a.source ? { source: a.source } : {}),
            };
            if (!ctx.evidenceOf(hit)) continue;
            visited.add(c.chunkId);
            count.set(key, (count.get(key) ?? 0) + 1);
            added.push(hit);
            progress = true;
          }
        }
        ctx.step('m1:hop', `nivel ${level}`, added.length);
        if (!progress && level > 1) break;
      }
      ctx.step('m1:expand', `perDoc=${perDoc}`, added.length);
      // Orden: anclas de M0, ampliados, resto de M0. Los ampliados no se reordenan por puntuación; al
      // truncar a k, los ampliados desplazan al final de la lista de M0 (efecto medido en el informe).
      return { hits: [...anchors, ...added, ...rest].slice(0, req.k) };
    },
  };
}

for (const [id, perDoc] of [['M1', RAG_LIMITS.maxChunksPerDoc], ['M1-c3', 3], ['M1-c4', 4]] as const) {
  registerRoute(makeNeighborsRoute(id, perDoc));
}
