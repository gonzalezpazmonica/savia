import { RAG_DEFAULTS, type ChunkMeta, type RagDomeConfig, type ResolvedRagConfig } from './types.js';

/**
 * SE-410 — Política dinámica de embeddings (canónica en docs/rules/domain/rag-embedding-policy.md).
 * Funciones puras: frescura (P6), promoción (P5) y SLO (P7).
 */

const DAY_MS = 24 * 60 * 60 * 1000;
export const MRR_TOLERANCE = 0.02;
export const STALE_RATIO_ALERT = 0.1;
/** SE-410 P7: «lagHours < 24 con cron activo». */
export const LAG_HOURS_ALERT = 24;

export function resolveRagConfig(
  dome: RagDomeConfig | undefined,
  env: NodeJS.ProcessEnv = process.env,
  override: Partial<RagDomeConfig> = {},
): ResolvedRagConfig {
  const merged = { ...RAG_DEFAULTS, ...(env.SAVIA_RAG_MODEL ? { model: env.SAVIA_RAG_MODEL } : {}), ...(dome ?? {}), ...override };
  return {
    enabled: Boolean(merged.enabled),
    model: merged.model,
    chunkChars: Math.max(200, Math.min(4000, Math.round(merged.chunkChars))),
    overlap: Math.max(0, Math.min(0.5, merged.overlap)),
    halfLifeDays: Math.max(0, merged.halfLifeDays),
    excludeStatuses: (merged.excludeStatuses ?? []).map(s => s.toLowerCase()),
    evalSet: merged.evalSet,
    inlineSyncBudget: Math.max(0, Math.round(merged.inlineSyncBudget)),
  };
}

/** Motivo de exclusión por frescura, o undefined si el chunk es vigente. */
export function excludedReason(meta: ChunkMeta, cfg: Pick<ResolvedRagConfig, 'excludeStatuses'>, now = new Date()): string | undefined {
  if (meta.status && cfg.excludeStatuses.includes(meta.status.toLowerCase())) return `status:${meta.status}`;
  if (meta.validUntil) {
    const t = Date.parse(meta.validUntil);
    if (!Number.isNaN(t) && t < now.getTime()) return `valid_until:${meta.validUntil}`;
  }
  return undefined;
}

/** decay = 0.5^(edad/halfLife); 1 si no hay vida media o la fecha no es válida. */
export function decayFactor(modified: string, halfLifeDays: number, now = new Date()): number {
  if (!halfLifeDays) return 1;
  const t = Date.parse(modified);
  if (Number.isNaN(t)) return 1;
  const ageDays = (now.getTime() - t) / DAY_MS;
  if (ageDays <= 0) return 1;
  return Math.pow(0.5, ageDays / halfLifeDays);
}

export interface EvalMetrics { recallAt10: number; mrr: number }

export interface PromotionInput {
  active?: EvalMetrics;
  candidate?: EvalMetrics;
  coverage: number;
  hasActive?: boolean;
  force?: boolean;
}

export function promotionDecision(input: PromotionInput): { promote: boolean; reason: string } {
  if (input.coverage < 1) return { promote: false, reason: `cobertura ${(input.coverage * 100).toFixed(1)} % < 100 %` };
  if (!input.hasActive) return { promote: true, reason: 'primera generación de la cúpula' };
  if (input.force) return { promote: true, reason: 'promoción forzada por decisión humana' };
  if (!input.active || !input.candidate) return { promote: false, reason: 'sin banco de eval: requiere --force' };
  if (input.candidate.recallAt10 < input.active.recallAt10) {
    return { promote: false, reason: `recall@10 ${input.candidate.recallAt10.toFixed(3)} < activa ${input.active.recallAt10.toFixed(3)}` };
  }
  if (input.candidate.mrr < input.active.mrr - MRR_TOLERANCE) {
    return { promote: false, reason: `MRR ${input.candidate.mrr.toFixed(3)} < activa ${input.active.mrr.toFixed(3)} − ${MRR_TOLERANCE}` };
  }
  return { promote: true, reason: 'gate de eval superado' };
}

export interface SloInput {
  enabled: boolean;
  hasGeneration: boolean;
  /** Existe algún índice en disco (activa, sombra o anterior), aunque la cúpula esté deshabilitada. */
  indexed?: boolean;
  totalDocs: number;
  pendingDocs: number;
  lagHours?: number;
  digestMatch: boolean;
}

export function sloStatus(s: SloInput): { ok: boolean; staleRatio: number; alerts: string[] } {
  const staleRatio = s.totalDocs ? s.pendingDocs / s.totalDocs : 0;
  const alerts: string[] = [];
  const indexed = s.hasGeneration || Boolean(s.indexed);
  if (!s.enabled && !indexed) return { ok: true, staleRatio, alerts };
  // Una cúpula con índice y rag.enabled=false queda fuera del cron: el índice envejece sin aviso.
  if (!s.enabled) alerts.push('cúpula con índice y rag.enabled=false: el cron la ignora y el índice envejece');
  if (s.enabled && !s.hasGeneration) alerts.push('cúpula habilitada sin generación activa');
  else if (s.hasGeneration) {
    if (staleRatio > STALE_RATIO_ALERT) alerts.push(`staleRatio ${staleRatio.toFixed(2)} > ${STALE_RATIO_ALERT}`);
    if ((s.lagHours ?? 0) >= LAG_HOURS_ALERT) alerts.push(`lagHours ${(s.lagHours ?? 0).toFixed(1)} >= ${LAG_HOURS_ALERT}`);
    if (s.enabled && !s.digestMatch) alerts.push('digest del modelo distinto del contrato activo (P4)');
  }
  return { ok: alerts.length === 0, staleRatio, alerts };
}
