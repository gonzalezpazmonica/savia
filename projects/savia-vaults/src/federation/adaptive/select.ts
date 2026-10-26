// SE-395 R02 — selección pura y determinista de destinos. No abre red, no usa reloj ni azar.
// Orden obligatorio: policy -> salud -> score -> subconjunto. DENY nunca es un peso negativo:
// un destino no autorizado no entra en el scoring ni deja rastro en la decisión.
import { parseGuidance, type DomeCue } from './guidance.js';

export interface AdaptiveFlags { adaptive: boolean; pioneer: boolean; plasticity: boolean; exploration: boolean; }
export const ADAPTIVE_FLAGS_DEFAULT: Readonly<AdaptiveFlags> = Object.freeze({ adaptive: false, pioneer: false, plasticity: false, exploration: false });

export type Termination = 'ANSWER_SUFFICIENT' | 'BUDGET_EXHAUSTED' | 'POLICY_BLOCK' | 'NO_ROUTE' | 'CONFLICT' | 'TIMEOUT' | 'UNKNOWN';
export interface Candidate { id: string; weight: number; local: boolean; healthy: boolean; tags?: string[]; }
export interface SelectionBudget { maxVaults: number; maxRemoteCalls: number; remoteCallsUsed?: number; }
export interface SelectionInput {
  query: string;
  candidates: Candidate[];
  allowedIds: string[];
  guidance?: unknown;
  budget: SelectionBudget;
  flags?: Partial<AdaptiveFlags>;
}
export interface ScoredCandidate { id: string; score: number; matched: { attracts: number; repels: number; specialties: number }; }
export interface Selection {
  mode: 'adaptive' | 'baseline';
  fallbackReason: 'flag_off' | 'no_guidance' | 'invalid_guidance' | 'no_signal' | null;
  selected: string[];
  scored: ScoredCandidate[];
  termination: Termination | null;
}

// Constantes del score, fijadas antes de cualquier holdout.
export const SCORE = { attract: 1, specialty: 2, repel: 1.5 } as const;

export const tokenize = (s: string): string[] => s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
const byScoreThenId = (a: { id: string; score: number }, b: { id: string; score: number }): number => b.score - a.score || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

function matches(termsList: string[], tokens: Set<string>): number {
  let n = 0;
  for (const t of termsList) if (tokenize(t).some(x => tokens.has(x))) n++;
  return n;
}

// Capacidad restante: local no consume llamadas remotas; los remotos se cortan a lo que queda.
function applyBudget(ordered: Candidate[], b: SelectionBudget): { ids: string[]; exhausted: boolean } {
  const remoteLeft = Math.max(0, b.maxRemoteCalls - (b.remoteCallsUsed ?? 0));
  const ids: string[] = []; let remote = 0; let exhausted = false;
  for (const c of ordered) {
    if (ids.length >= b.maxVaults) break;
    if (!c.local) { if (remote >= remoteLeft) { exhausted = true; continue; } remote++; }
    ids.push(c.id);
  }
  return { ids, exhausted };
}

export function selectRoute(input: SelectionInput): Selection {
  const flags: AdaptiveFlags = { ...ADAPTIVE_FLAGS_DEFAULT, ...input.flags };
  // 1) Policy antes de cualquier observación del contenido de los candidatos.
  const allowed = new Set(input.allowedIds);
  const authorised = input.candidates.filter(c => allowed.has(c.id));
  // 2) Salud.
  const usable = authorised.filter(c => c.healthy);
  const base = [...usable].sort((a, b) => b.weight - a.weight || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const baseline = (reason: Selection['fallbackReason']): Selection => {
    const { ids, exhausted } = applyBudget(base, input.budget);
    // Fallback: federación existente con la policy y el presupuesto restantes; sin garantía -> sin expansión.
    const termination: Termination | null = usable.length === 0 ? (authorised.length === 0 && input.candidates.length > 0 ? 'POLICY_BLOCK' : 'NO_ROUTE') : ids.length === 0 && exhausted ? 'BUDGET_EXHAUSTED' : null;
    return { mode: 'baseline', fallbackReason: reason, selected: ids, scored: [], termination };
  };

  if (!flags.adaptive) return baseline('flag_off');
  if (input.guidance === undefined) return baseline('no_guidance');
  const parsed = parseGuidance(input.guidance);
  if (!parsed.ok) return baseline('invalid_guidance');

  // 3) Score solo sobre autorizados y sanos.
  const cues = new Map<string, DomeCue>(parsed.guidance.cues.map(c => [c.dome, c]));
  const tokens = new Set(tokenize(input.query));
  const scored: ScoredCandidate[] = usable.map(c => {
    const cue = cues.get(c.id);
    const matched = cue ? { attracts: matches(cue.attracts, tokens), repels: matches(cue.repels, tokens), specialties: matches(cue.specialties, tokens) } : { attracts: 0, repels: 0, specialties: 0 };
    const signal = matched.attracts * SCORE.attract + matched.specialties * SCORE.specialty - matched.repels * SCORE.repel;
    const score = c.weight + (cue?.weight ?? 1) * signal;
    return { id: c.id, score: Number.isFinite(score) ? score : c.weight, matched };
  }).sort(byScoreThenId);
  if (scored.every(s => s.matched.attracts + s.matched.repels + s.matched.specialties === 0)) return baseline('no_signal');

  // 4) Subconjunto bajo presupuesto. Repeler baja el score, nunca excluye por sí solo.
  const order = scored.map(s => usable.find(c => c.id === s.id)!);
  const { ids, exhausted } = applyBudget(order, input.budget);
  return { mode: 'adaptive', fallbackReason: null, selected: ids, scored, termination: ids.length === 0 ? (exhausted ? 'BUDGET_EXHAUSTED' : 'NO_ROUTE') : null };
}
