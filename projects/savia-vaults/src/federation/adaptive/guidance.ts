// SE-395 R02 — schema versionado de cues (attracts/repels/specialties). Solo datos: sin red ni E/S.
// La metadata remota es no confiable: schema cerrado, tamaños acotados, scores finitos.
export const GUIDANCE_SCHEMA_VERSION = 1;
export const GUIDANCE_LIMITS = { maxCues: 64, maxTermsPerList: 32, maxTermLength: 64, maxIdLength: 128 } as const;

export interface DomeCue { dome: string; attracts: string[]; repels: string[]; specialties: string[]; weight?: number; }
export interface Guidance { version: typeof GUIDANCE_SCHEMA_VERSION; cues: DomeCue[]; }
export type GuidanceResult = { ok: true; guidance: Guidance } | { ok: false; errors: string[] };

const TOP_KEYS = new Set(['version', 'cues']);
const CUE_KEYS = new Set(['dome', 'attracts', 'repels', 'specialties', 'weight']);
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

function terms(v: unknown, field: string, at: string, errors: string[]): string[] {
  if (!Array.isArray(v)) { errors.push(`${at}.${field} debe ser una lista`); return []; }
  if (v.length > GUIDANCE_LIMITS.maxTermsPerList) { errors.push(`${at}.${field} excede ${GUIDANCE_LIMITS.maxTermsPerList} términos`); return []; }
  const out: string[] = [];
  for (const t of v) {
    if (typeof t !== 'string' || t.trim() === '' || t.length > GUIDANCE_LIMITS.maxTermLength) { errors.push(`${at}.${field} contiene un término inválido`); continue; }
    out.push(t.trim().toLowerCase());
  }
  return out;
}

export function parseGuidance(input: unknown): GuidanceResult {
  const errors: string[] = [];
  if (!isObj(input)) return { ok: false, errors: ['guidance debe ser un objeto'] };
  for (const k of Object.keys(input)) if (!TOP_KEYS.has(k)) errors.push(`campo desconocido: ${k}`);
  if (input.version !== GUIDANCE_SCHEMA_VERSION) errors.push(`version no soportada: ${String(input.version)}`);
  if (!Array.isArray(input.cues)) errors.push('cues debe ser una lista');
  else if (input.cues.length > GUIDANCE_LIMITS.maxCues) errors.push(`cues excede ${GUIDANCE_LIMITS.maxCues}`);
  if (errors.length) return { ok: false, errors };
  const seen = new Set<string>(); const cues: DomeCue[] = [];
  (input.cues as unknown[]).forEach((c, i) => {
    const at = `cues[${i}]`;
    if (!isObj(c)) { errors.push(`${at} debe ser un objeto`); return; }
    for (const k of Object.keys(c)) if (!CUE_KEYS.has(k)) errors.push(`${at}: campo desconocido ${k}`);
    if (typeof c.dome !== 'string' || c.dome.trim() === '' || c.dome.length > GUIDANCE_LIMITS.maxIdLength) { errors.push(`${at}.dome inválido`); return; }
    if (seen.has(c.dome)) errors.push(`${at}.dome duplicado: ${c.dome}`);
    seen.add(c.dome);
    let weight: number | undefined;
    if (c.weight !== undefined) {
      if (typeof c.weight !== 'number' || !Number.isFinite(c.weight) || c.weight < 0 || c.weight > 1) errors.push(`${at}.weight debe ser finito en [0,1]`);
      else weight = c.weight;
    }
    cues.push({ dome: c.dome, attracts: terms(c.attracts ?? [], 'attracts', at, errors), repels: terms(c.repels ?? [], 'repels', at, errors), specialties: terms(c.specialties ?? [], 'specialties', at, errors), ...(weight === undefined ? {} : { weight }) });
  });
  return errors.length ? { ok: false, errors } : { ok: true, guidance: { version: GUIDANCE_SCHEMA_VERSION, cues } };
}
