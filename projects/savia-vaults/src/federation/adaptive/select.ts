// SE-395 R02 — selección determinista y pura de destinos. Orden obligatorio:
// 1) policy (allowedDomeIds) 2) salud 3) score 4) presupuesto. DENY nunca entra al score.
import type { FederatedDome } from '../types.js';
import { DEFAULT_FLAGS, parseGuidance, type AdaptiveFlags, type VaultCue } from './guidance.js';

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
  for (const d of [...i.domes].sort((a, b) => byIdAsc(a.id, b.id))) {
    if (!allowed.has(d.id)) { denied++; continue; }
    if (!d.enabled || (d.status !== 'healthy')) { skipped.push({ id: d.id, reason: 'UNHEALTHY' }); continue; }
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
  const empty = (mode: SelectionResult['mode'], termination: Termination, reasons: string[]): SelectionResult =>
    ({ mode, selected: [], skipped: base.skipped, deniedCount: base.denied, scores: {}, termination, reasons });

  if (!flags.adaptive) {
    return { mode: 'baseline', selected: [...head, ...base.ids], skipped: base.skipped, deniedCount: base.denied, scores: {}, termination: null, reasons: ['adaptive=false'] };
  }

  const remoteBudget = Math.max(0, Math.min(input.budget.maxRemoteCalls, input.budget.maxVaults - head.length));
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
  const scores: Record<string, number> = {};
  const ranked = base.ids.map(id => {
    const d = input.domes.find(x => x.id === id)!;
    const s = score(d.weight, cues.get(id), q);
    scores[id] = s;
    return { id, s };
  }).sort((a, b) => b.s - a.s || byIdAsc(a.id, b.id));
  const chosen = ranked.slice(0, remoteBudget);
  const skipped = [...base.skipped, ...ranked.slice(remoteBudget).map(r => ({ id: r.id, reason: 'BUDGET' as const }))];
  const selected = [...head, ...chosen.map(c => c.id)];
  const termination: Termination | null = selected.length === 0 ? (base.denied > 0 && base.ids.length === 0 ? 'POLICY_BLOCK' : 'NO_ROUTE') : null;
  if (selected.length === 0) return { ...empty('adaptive', termination!, ['sin destinos elegibles']), scores };
  return { mode: 'adaptive', selected, skipped, deniedCount: base.denied, scores, termination, reasons: [] };
}
