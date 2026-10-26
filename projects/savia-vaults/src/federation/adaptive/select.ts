// SE-395 R02 — selección determinista y pura de destinos. Orden obligatorio:
// 1) policy (allowedDomeIds) 2) salud 3) score 4) presupuesto. DENY nunca entra al score.
import type { FederatedDome } from '../types.js';
import { DEFAULT_FLAGS, parseGuidance, type AdaptiveFlags, type VaultCue } from './guidance.js';

// Presupuesto finito obligatorio: cada tope NaN, Infinity o negativo se trata como 0 (fail-closed), nunca como «sin tope».
export interface SelectionBudget { maxVaults: number; maxRemoteCalls: number; }
export type Termination = 'ANSWER_SUFFICIENT' | 'BUDGET_EXHAUSTED' | 'POLICY_BLOCK' | 'NO_ROUTE' | 'CONFLICT' | 'TIMEOUT' | 'UNKNOWN';
export type SkipReason = 'UNHEALTHY' | 'BUDGET';

export interface SelectionInput {
  query: string;
  allowedDomeIds: string[];
  /** Destinos remotos registrados (cualquier estado); 'local' no figura aquí. */
  domes: Array<Pick<FederatedDome, 'id' | 'weight' | 'status' | 'enabled'>>;
  guidance: unknown;
  budget: SelectionBudget;
  flags?: Partial<AdaptiveFlags>;
}
export interface SelectionResult {
  mode: 'baseline' | 'adaptive' | 'fallback';
  /** Orden de consulta: 'local' primero si está autorizado, después remotos por score. */
  selected: string[];
  /** Solo destinos autorizados: nunca se nombra un destino denegado por policy. */
  skipped: Array<{ id: string; reason: SkipReason }>;
  deniedCount: number;
  scores: Record<string, number>;
  termination: Termination | null;
  reasons: string[];
}

const tokens = (s: string): Set<string> => new Set(s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean));
const byIdAsc = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);

// Score = peso configurado * (1 + atracción + especialidad - repulsión), acotado a >= 0.
// La repulsión baja prioridad pero no deniega: si el presupuesto sobra el destino sigue elegible.
function score(weight: number, cue: VaultCue | undefined, q: Set<string>): number {
  if (!cue) return weight;
  const sum = (l: Array<{ term: string; score: number }>): number => l.reduce((s, t) => s + (q.has(t.term) ? t.score : 0), 0);
  const spec = cue.specialties.filter(t => q.has(t)).length * 0.5;
  return Math.max(0, weight * (1 + sum(cue.attracts) + spec - sum(cue.repels)));
}

// Elegible = habilitado y 'healthy' | 'degraded', exactamente registry.getHealthy(): 'unknown' tampoco lo consulta el motor real.
const eligible = (d: Pick<FederatedDome, 'status' | 'enabled'>): boolean => d.enabled && (d.status === 'healthy' || d.status === 'degraded');
// Peso de configuración local: no finito o negativo cuenta como 0 para que el orden sea total y determinista.
const safeWeight = (w: number): number => (Number.isFinite(w) && w > 0 ? w : 0);
// Cada tope por separado: no finito (NaN, Infinity) o negativo es 0. Fail-closed, nunca «sin tope».
const cap = (n: number): number => (Number.isFinite(n) ? Math.max(0, Math.floor(n)) : 0);

// Baseline de la federación actual: todo destino autorizado y elegible, sin tope propio.
function baselineIds(i: SelectionInput): { ids: string[]; denied: number; skipped: SelectionResult['skipped'] } {
  const allowed = new Set(i.allowedDomeIds);
  const skipped: SelectionResult['skipped'] = [];
  const ids: string[] = [];
  let denied = 0;
  const seen = new Set<string>();
  for (const d of [...i.domes].sort((a, b) => byIdAsc(a.id, b.id))) {
    // Un id repetido se cuenta una sola vez: no puede gastar presupuesto doble ni seleccionarse dos veces.
    if (seen.has(d.id)) continue;
    seen.add(d.id);
    if (!allowed.has(d.id)) { denied++; continue; }
    if (!eligible(d)) { skipped.push({ id: d.id, reason: 'UNHEALTHY' }); continue; }
    ids.push(d.id);
  }
  return { ids, denied, skipped };
}

// Misma terminación para adaptive y fallback. POLICY_BLOCK: la policy deja fuera todo y no hay nada autorizado;
// BUDGET_EXHAUSTED: había destinos elegibles (o local) y el presupuesto los recortó todos; NO_ROUTE: nada elegible.
function terminate(selected: string[], base: ReturnType<typeof baselineIds>, remoteBudget: number, localAllowed: boolean, localKept: boolean): Termination | null {
  const remoteCut = remoteBudget === 0 && base.ids.length > 0;
  if (selected.length > 0) return remoteCut ? 'BUDGET_EXHAUSTED' : null;
  const authorized = base.ids.length + base.skipped.length + (localAllowed ? 1 : 0);
  if (base.denied > 0 && authorized === 0) return 'POLICY_BLOCK';
  return remoteCut || (localAllowed && !localKept) ? 'BUDGET_EXHAUSTED' : 'NO_ROUTE';
}

export function selectDestinations(input: SelectionInput): SelectionResult {
  const flags = { ...DEFAULT_FLAGS, ...input.flags };
  const allowed = new Set(input.allowedDomeIds);
  const localAllowed = allowed.has('local');
  const base = baselineIds(input);
  if (!flags.adaptive) {
    return { mode: 'baseline', selected: [...(localAllowed ? ['local'] : []), ...base.ids], skipped: base.skipped, deniedCount: base.denied, scores: {}, termination: null, reasons: ['adaptive=false'] };
  }

  const maxVaults = cap(input.budget.maxVaults);
  // 'local' cuenta en maxVaults: con maxVaults 0 tampoco entra (se informa como BUDGET).
  const localKept = localAllowed && maxVaults >= 1;
  const head = localKept ? ['local'] : [];
  const localSkip = localAllowed && !localKept ? [{ id: 'local', reason: 'BUDGET' as const }] : [];
  const remoteBudget = Math.min(cap(input.budget.maxRemoteCalls), maxVaults - head.length);
  const weightOf = (id: string): number => safeWeight(input.domes.find(d => d.id === id)!.weight);
  const parsed = parseGuidance(input.guidance);
  if (!parsed.ok) {
    // Fallo adaptativo -> federación existente con policy y presupuesto restante, nunca broadcast ilimitado.
    const capped = [...base.ids].sort((a, b) => weightOf(b) - weightOf(a) || byIdAsc(a, b)).slice(0, remoteBudget);
    const skipped = [...localSkip, ...base.skipped, ...base.ids.filter(id => !capped.includes(id)).map(id => ({ id, reason: 'BUDGET' as const }))];
    const selected = [...head, ...capped];
    return { mode: 'fallback', selected, skipped, deniedCount: base.denied, scores: {}, termination: terminate(selected, base, remoteBudget, localAllowed, localKept), reasons: ['guidance inválida', ...parsed.errors.slice(0, 5)] };
  }

  const q = tokens(input.query);
  const cues = new Map(parsed.guidance.cues.map(c => [c.vaultId, c]));
  // La policy ya filtró: solo destinos autorizados y sanos llegan al score.
  // Sin prototipo: un id como '__proto__' es una clave más, no reasigna el prototipo.
  const scores: Record<string, number> = Object.create(null) as Record<string, number>;
  const ranked = base.ids.map(id => {
    const s = score(weightOf(id), cues.get(id), q);
    scores[id] = s;
    return { id, s };
  }).sort((a, b) => b.s - a.s || byIdAsc(a.id, b.id));
  const chosen = ranked.slice(0, remoteBudget);
  const skipped = [...localSkip, ...base.skipped, ...ranked.slice(remoteBudget).map(r => ({ id: r.id, reason: 'BUDGET' as const }))];
  const selected = [...head, ...chosen.map(c => c.id)];
  const termination = terminate(selected, base, remoteBudget, localAllowed, localKept);
  // Mismo `skipped` en ambas ramas: con presupuesto 0 los sanos recortados figuran como BUDGET, igual que en fallback.
  return { mode: 'adaptive', selected, skipped, deniedCount: base.denied, scores, termination, reasons: selected.length === 0 ? ['sin destinos elegibles'] : [] };
}
