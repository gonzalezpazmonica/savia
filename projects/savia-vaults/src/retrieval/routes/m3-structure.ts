// SE-489 M3 — navegación determinista sobre el StructureIndex (sin modelo).
// Parte de los candidatos de M0 y, en los primeros documentos:
//   1. sección citada: si la consulta nombra «cláusula 5», «artículo 3», «anexo II»…, trae las
//      unidades de la sección cuyo título la nombra;
//   2. sección del hit (padre y hermanos): reúne el texto de la sección de cada hit y busca en él
//      referencias a anexos/apéndices;
//   3. documento hermano: sigue cada referencia al documento del mismo directorio que la nombra
//      (`contrato.md` → `anexo-I.md`), un `hops` por salto.
// Lo añadido se coloca tras el grupo del documento que lo cita: el orden de documentos de M0 no
// cambia. Todo pasa por el contexto (guard + presupuesto); el texto leído solo se usa para buscar
// referencias estructurales, nunca como instrucción.
import { ROUTE_CONTRACT_VERSION, registerRoute, type NodeRef, type OpenedChunk, type RetrievalRoute, type RouteContext } from '../route.js';
import type { RagHit } from '../../rag/types.js';
import type { StructureNode } from '../../rag/structure-index.js';

export const STRUCTURE_UNAVAILABLE = 'STRUCTURE_UNAVAILABLE';

/** Documentos de cabeza que se navegan, unidades por sección citada y por anexo, referencias seguidas. */
export const M3_LIMITS = Object.freeze({ docs: 5, sectionUnits: 3, annexUnits: 2, refsPerDoc: 3, siblingProbes: 6, siblings: 32 });

const ROMAN: Record<string, number> = { i: 1, v: 5, x: 10, l: 50, c: 100 };
function romanValue(s: string): number | undefined {
  if (!/^(x{0,3})(ix|iv|v?i{0,3})$/.test(s) || !s) return undefined;
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const v = ROMAN[s[i]], next = ROMAN[s[i + 1]] ?? 0;
    n += v < next ? -v : v;
  }
  return n;
}

const fold = (s: string): string => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const CUE = /(?:^|[^\p{L}\p{N}])(anexo|apendice|clausula|articulo|seccion|capitulo|apartado)[\s_-]+([ivxlc]+|\d+)(?![\p{L}\p{N}])/gu;
const PARAGRAPH = /§\s*(\d+(?:\.\d+)*)/g;

/** Referencias estructurales de un texto, normalizadas (`anexo 2`, `clausula 5`, `§ 4.2`), únicas y ordenadas. */
export function structuralCues(text: string): string[] {
  const t = fold(text);
  const out = new Set<string>();
  for (const m of t.matchAll(CUE)) {
    const n = /^\d+$/.test(m[2]) ? Number(m[2]) : romanValue(m[2]);
    if (n !== undefined && n > 0) out.add(`${m[1]} ${n}`);
  }
  for (const m of t.matchAll(PARAGRAPH)) out.add(`§ ${m[1]}`);
  return [...out].sort();
}

const isAnnex = (cue: string): boolean => cue.startsWith('anexo ') || cue.startsWith('apendice ');
const basename = (p: string): string => p.slice(p.lastIndexOf('/') + 1).replace(/\.md$/i, '');
const keyOf = (dome: string, path: string): string => `${dome}\u0000${path}`;

/** Hit de un chunk leído por el contexto; sin `freshness`, el runner la toma del propio chunk. */
function hitOf(ref: NodeRef, c: OpenedChunk, like: RagHit): RagHit {
  const h = {
    dome: ref.dome, confidentiality: like.confidentiality, path: ref.path, chunkId: c.chunkId, heading: c.heading, text: c.text,
    score: like.score, signals: {}, generation: like.generation,
  };
  return h as RagHit;
}

interface DocGroup { ref: NodeRef; hits: RagHit[] }

function unitsOf(nodes: StructureNode[], section: StructureNode): StructureNode[] {
  const byId = new Map(nodes.map(n => [n.nodeId, n]));
  return section.children.map(id => byId.get(id)!).filter(n => n?.kind === 'unit');
}

async function navigate(req: Parameters<RetrievalRoute['run']>[0], ctx: RouteContext & Required<Pick<RouteContext, 'documentStructure'>>, groups: DocGroup[]): Promise<Map<string, RagHit[]>> {
  const extras = new Map<string, RagHit[]>();
  const queryCues = structuralCues(req.query);
  const followed = new Set<string>();
  for (const g of groups.slice(0, M3_LIMITS.docs)) {
    const st = ctx.documentStructure(g.ref);
    if (!st) continue;
    let chunks: Map<string, OpenedChunk> | undefined;
    const chunkMap = (): Map<string, OpenedChunk> => (chunks ??= new Map((ctx.documentChunks(g.ref) ?? []).map(c => [c.chunkId, c])));
    const add: RagHit[] = [];
    const like = g.hits[0];
    // 1. Secciones que la consulta nombra.
    if (queryCues.length) {
      for (const s of st.nodes) {
        if (s.kind !== 'section' || !structuralCues(s.title).some(c => queryCues.includes(c))) continue;
        const units = unitsOf(st.nodes, s).slice(0, M3_LIMITS.sectionUnits);
        for (const u of units) { const c = chunkMap().get(u.chunkId!); if (c) add.push(hitOf(g.ref, c, like)); }
        ctx.step('m3:section', undefined, units.length);
      }
    }
    // 2. Texto de la sección de cada hit (y de las citadas): referencias a anexos.
    const byChunk = new Map(st.nodes.filter(n => n.chunkId).map(n => [n.chunkId!, n]));
    const byId = new Map(st.nodes.map(n => [n.nodeId, n]));
    const texts: string[] = add.map(h => h.text);
    for (const h of g.hits) {
      texts.push(h.text);
      const parent = byChunk.get(h.chunkId)?.parent;
      const sec = parent ? byId.get(parent) : undefined;
      if (sec?.kind !== 'section') continue;
      for (const u of unitsOf(st.nodes, sec)) { const c = chunkMap().get(u.chunkId!); if (c) texts.push(c.text); }
    }
    const refs = [...new Set([...queryCues, ...structuralCues(texts.join('\n'))])].filter(isAnnex).slice(0, M3_LIMITS.refsPerDoc);
    // 3. Documento hermano que nombra cada referencia: por nombre de fichero, o por título.
    //    Los hermanos solo se listan si hay referencias (cada uno cuesta 1 `nodes`).
    const siblings = refs.length ? ctx.documentStructure(g.ref, { maxSiblings: M3_LIMITS.siblings })?.siblings ?? [] : [];
    const titleCues = new Map<string, string[]>();
    for (const cue of refs) {
      let target = siblings.find(s => structuralCues(basename(s.path).replace(/[-_]/g, ' ')).includes(cue));
      if (!target) {
        for (const s of siblings.slice(0, M3_LIMITS.siblingProbes)) {
          const k = keyOf(s.dome, s.path);
          if (!titleCues.has(k)) {
            const t = ctx.documentStructure(s);
            titleCues.set(k, t ? structuralCues(t.nodes.filter(n => n.depth <= 1).map(n => n.title).join('\n')) : []);
          }
          if (titleCues.get(k)!.includes(cue)) { target = s; break; }
        }
      }
      if (!target || followed.has(keyOf(target.dome, target.path))) continue;
      if (!ctx.consume('hops')) break;
      followed.add(keyOf(target.dome, target.path));
      const tc = (ctx.documentChunks(target) ?? []).slice(0, M3_LIMITS.annexUnits);
      for (const c of tc) add.push(hitOf(target, c, like));
      ctx.step('m3:annex', cue, tc.length);
    }
    if (add.length) extras.set(keyOf(g.ref.dome, g.ref.path), add);
  }
  return extras;
}

export const M3_STRUCTURE: RetrievalRoute = {
  id: 'M3',
  description: 'StructureIndex: secciones citadas, sección del hit y anexos hermanos (determinista, sin modelo)',
  contractVersion: ROUTE_CONTRACT_VERSION,
  supportsAsOf: false,
  requiresDeclaredBudget: false,
  async run(req, ctx) {
    // Mismo k que M0: con otro k la fusión RRF reordena y la línea base deja de ser la de M0.
    const cands = await ctx.candidates(req.query, { k: req.k, mode: req.mode });
    ctx.step('m3:candidates', req.mode, cands.length);
    if (!cands.length) return { hits: [] };
    if (!ctx.documentStructure) return { hits: cands, warnings: [STRUCTURE_UNAVAILABLE] };
    const groups: DocGroup[] = [];
    const index = new Map<string, DocGroup>();
    for (const h of cands) {
      const k = keyOf(h.dome, h.path);
      let g = index.get(k);
      if (!g) {
        g = { ref: { dome: h.dome, path: h.path, ...(h.source ? { documentId: h.source.documentId } : {}) }, hits: [] };
        index.set(k, g);
        groups.push(g);
      }
      g.hits.push(h);
    }
    const extras = await navigate(req, ctx as RouteContext & Required<Pick<RouteContext, 'documentStructure'>>, groups);
    const hits: RagHit[] = [];
    const seen = new Set<string>();
    const push = (h: RagHit): void => {
      const k = `${h.dome}\u0000${h.chunkId}`;
      if (!seen.has(k)) { seen.add(k); hits.push(h); }
    };
    for (const g of groups) {
      for (const h of g.hits) push(h);
      for (const h of extras.get(keyOf(g.ref.dome, g.ref.path)) ?? []) push(h);
    }
    return { hits };
  },
};

registerRoute(M3_STRUCTURE);
