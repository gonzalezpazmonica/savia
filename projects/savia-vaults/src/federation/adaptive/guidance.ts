// SE-395 R02 — schema versionado de cues de guidance (atrae/repele/especialidad). Solo datos, sin red.
// Metadata remota es no confiable: cualquier campo desconocido, valor no finito o límite excedido rechaza TODO el documento.
export const GUIDANCE_SCHEMA_VERSION = 1;

export const GUIDANCE_LIMITS = { maxCues: 32, maxTermsPerList: 16, maxTermLength: 64, maxVaultIdLength: 128 } as const;

// Flags de SE-395: nunca true por defecto; ningún camino los activa al merge.
export interface AdaptiveFlags { adaptive: boolean; pioneer: boolean; plasticity: boolean; exploration: boolean; }
export const DEFAULT_FLAGS: Readonly<AdaptiveFlags> = Object.freeze({ adaptive: false, pioneer: false, plasticity: false, exploration: false });

export interface WeightedTerm { term: string; score: number; }
export interface VaultCue { vaultId: string; attracts: WeightedTerm[]; repels: WeightedTerm[]; specialties: string[]; }
export interface Guidance { version: number; cues: VaultCue[]; }

export type GuidanceResult = { ok: true; guidance: Guidance } | { ok: false; errors: string[] };

const isObj = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);
const unknownKeys = (o: Record<string, unknown>, allowed: string[], where: string, errs: string[]): void => {
  for (const k of Object.keys(o)) if (!allowed.includes(k)) errs.push(`${where}: campo desconocido '${k}'`);
};
// Un término válido es un único token como los que produce el tokenizador de la consulta; otro no podría coincidir nunca.
const TOKEN = /^[\p{L}\p{N}]+$/u;
const validTerm = (t: unknown): t is string => typeof t === 'string' && t.length <= GUIDANCE_LIMITS.maxTermLength && TOKEN.test(t.trim());

function parseWeighted(v: unknown, where: string, errs: string[]): WeightedTerm[] {
  if (!Array.isArray(v)) { errs.push(`${where}: debe ser array`); return []; }
  if (v.length > GUIDANCE_LIMITS.maxTermsPerList) { errs.push(`${where}: máximo ${GUIDANCE_LIMITS.maxTermsPerList} términos`); return []; }
  const out: WeightedTerm[] = [];
  const seenTerms = new Set<string>();
  v.forEach((e, i) => {
    if (!isObj(e)) { errs.push(`${where}[${i}]: debe ser objeto`); return; }
    unknownKeys(e, ['term', 'score'], `${where}[${i}]`, errs);
    if (!validTerm(e.term)) { errs.push(`${where}[${i}].term inválido`); return; }
    if (typeof e.score !== 'number' || !Number.isFinite(e.score) || e.score < 0 || e.score > 1) { errs.push(`${where}[${i}].score debe ser finito en [0,1]`); return; }
    const term = e.term.trim().toLowerCase();
    if (seenTerms.has(term)) { errs.push(`${where}[${i}].term duplicado`); return; }
    seenTerms.add(term);
    out.push({ term, score: e.score });
  });
  return out;
}

export function parseGuidance(raw: unknown): GuidanceResult {
  const errs: string[] = [];
  if (!isObj(raw)) return { ok: false, errors: ['guidance: debe ser objeto'] };
  unknownKeys(raw, ['version', 'cues'], 'guidance', errs);
  if (raw.version !== GUIDANCE_SCHEMA_VERSION) errs.push(`guidance.version: se esperaba ${GUIDANCE_SCHEMA_VERSION}`);
  if (!Array.isArray(raw.cues)) errs.push('guidance.cues: debe ser array');
  else if (raw.cues.length > GUIDANCE_LIMITS.maxCues) errs.push(`guidance.cues: máximo ${GUIDANCE_LIMITS.maxCues}`);
  const cues: VaultCue[] = [];
  if (Array.isArray(raw.cues) && raw.cues.length <= GUIDANCE_LIMITS.maxCues) {
    const seen = new Set<string>();
    raw.cues.forEach((c, i) => {
      const w = `cues[${i}]`;
      if (!isObj(c)) { errs.push(`${w}: debe ser objeto`); return; }
      unknownKeys(c, ['vaultId', 'attracts', 'repels', 'specialties'], w, errs);
      if (typeof c.vaultId !== 'string' || c.vaultId.trim() === '' || c.vaultId.length > GUIDANCE_LIMITS.maxVaultIdLength) { errs.push(`${w}.vaultId inválido`); return; }
      if (seen.has(c.vaultId)) errs.push(`${w}.vaultId duplicado`);
      seen.add(c.vaultId);
      const attracts = parseWeighted(c.attracts ?? [], `${w}.attracts`, errs);
      const repels = parseWeighted(c.repels ?? [], `${w}.repels`, errs);
      let specialties: string[] = [];
      const sp = c.specialties ?? [];
      if (!Array.isArray(sp) || sp.length > GUIDANCE_LIMITS.maxTermsPerList || !sp.every(validTerm)) errs.push(`${w}.specialties inválido`);
      else {
        specialties = (sp as string[]).map(s => s.trim().toLowerCase());
        // Igual que attracts/repels: un duplicado rechaza el documento, no se deduplica en silencio.
        if (new Set(specialties).size !== specialties.length) errs.push(`${w}.specialties: término duplicado`);
      }
      cues.push({ vaultId: c.vaultId, attracts, repels, specialties });
    });
  }
  return errs.length > 0 ? { ok: false, errors: errs } : { ok: true, guidance: { version: GUIDANCE_SCHEMA_VERSION, cues } };
}
