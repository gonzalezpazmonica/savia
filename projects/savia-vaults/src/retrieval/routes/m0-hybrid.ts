// SE-489 M0 — adaptador del pipeline actual (BM25 + denso + RRF de RagService) al contrato
// común, sin cambiar su resultado: los mismos hits, en el mismo orden, con los mismos avisos.
// Es la línea base de todas las comparaciones (rag eval --route M0).
import { ROUTE_CONTRACT_VERSION, registerRoute, type RetrievalRoute } from '../route.js';

export const M0_HYBRID: RetrievalRoute = {
  id: 'M0',
  description: 'Híbrido actual (BM25 + denso + RRF), sin cambios',
  contractVersion: ROUTE_CONTRACT_VERSION,
  supportsAsOf: false,
  requiresDeclaredBudget: false,
  async run(req, ctx) {
    const hits = await ctx.candidates(req.query, { k: req.k, mode: req.mode });
    ctx.step('m0:candidates', req.mode, hits.length);
    return { hits };
  },
};

registerRoute(M0_HYBRID);
