// SE-395 R02 — selección determinista y pura de destinos. Orden obligatorio:
// 1) policy (allowedDomeIds) 2) salud 3) score 4) presupuesto. DENY nunca entra al score.
import type { FederatedDome } from '../types.js';
import { DEFAULT_FLAGS, parseGuidance, type AdaptiveFlags, type VaultCue } from './guidance.js';

// Presupuesto finito obligatorio: NaN o Infinity se tratan como 0 (fail-closed), nunca como «sin tope».
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

// Baseline de la federación actual: todo destino autorizado y sano, sin tope propio.
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
    // Igual que registry.getHealthy(): 'degraded' sigue siendo consultable por el baseline real.
    if (!d.enabled || d.status === 'unhealthy') { skipped.push({ id: d.id, reason: 'UNHEALTHY' }); continue; }
    ids.push(d.id);
  }
  return { ids, denied, skipped };
}

export function selectDestinations(input: SelectionInput): SelectionResult {
  const flags = { ...DEFAULT_FLAGS, ...input.flags };
  const allowed = new Set(input.allowedDomeIds);
  const localAllowed = allowed.has('local');
  const base = baselineIds(input);
  const head = localAllowed ? ['local'] : [];
  if (!flags.adaptive) {
    return { mode: 'baseline', selected: [...head, ...base.ids], skipped: base.skipped, deniedCount: base.denied, scores: {}, termination: null, reasons: ['adaptive=false'] };
  }

  const rawBudget = Math.min(input.budget.maxRemoteCalls, input.budget.maxVaults - head.length);
  const remoteBudget = Number.isFinite(rawBudget) ? Math.max(0, rawBudget) : 0;
  const parsed = parseGuidance(input.guidance);
  if (!parsed.ok) {
    // Fallo adaptativo -> federación existente con policy y presupuesto restante, nunca broadcast ilimitado.
    const capped = [...base.ids].sort((a, b) => {
      const w = (id: string): number => input.domes.find(d => d.id === id)!.weight;
      return w(b) - w(a) || byIdAsc(a, b);
    }).slice(0, remoteBudget);
    const skipped = [...base.skipped, ...base.ids.filter(id => !capped.includes(id)).map(id => ({ id, reason: 'BUDGET' as const }))];
    const r = { mode: 'fallback' as const, selected: [...head, ...capped], skipped, deniedCount: base.denied, scores: {}, termination: null, reasons: ['guidance inválida', ...parsed.errors.slice(0, 5)] };
    return remoteBudget === 0 && base.ids.length > 0 ? { ...r, termination: 'BUDGET_EXHAUSTED' } : r;
  }

  const q = tokens(input.query);
  const cues = new Map(parsed.guidance.cues.map(c => [c.vaultId, c]));
  // La policy ya filtró: solo destinos autorizados y sanos llegan al score.
  // Sin prototipo: un id como '__proto__' es una clave más, no reasigna el prototipo.
  const scores: Record<string, number> = Object.create(null) as Record<string, number>;
  const ranked = base.ids.map(id => {
    const d = input.domes.find(x => x.id === id)!;
    const s = score(d.weight, cues.get(id), q);
    scores[id] = s;
    return { id, s };
  }).sort((a, b) => b.s - a.s || byIdAsc(a.id, b.id));
  const chosen = ranked.slice(0, remoteBudget);
  const skipped = [...base.skipped, ...ranked.slice(remoteBudget).map(r => ({ id: r.id, reason: 'BUDGET' as const }))];
  const selected = [...head, ...chosen.map(c => c.id)];
  // POLICY_BLOCK: la policy deja fuera todo y no hay nada autorizado; BUDGET_EXHAUSTED: hay sanos pero el presupuesto remoto es 0.
  const authorized = base.ids.length + base.skipped.length + head.length;
  const termination: Termination | null = selected.length === 0
    ? (base.denied > 0 && authorized === 0 ? 'POLICY_BLOCK' : remoteBudget === 0 && base.ids.length > 0 ? 'BUDGET_EXHAUSTED' : 'NO_ROUTE')
    : remoteBudget === 0 && base.ids.length > 0 ? 'BUDGET_EXHAUSTED' : null;
  // Mismo `skipped` en ambas ramas: con presupuesto 0 los sanos recortados figuran como BUDGET, igual que en fallback.
  return { mode: 'adaptive', selected, skipped, deniedCount: base.denied, scores, termination, reasons: selected.length === 0 ? ['sin destinos elegibles'] : [] };
}
