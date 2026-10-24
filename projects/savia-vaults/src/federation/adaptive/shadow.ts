// SE-395 R03 — modo shadow: ejecuta SOLO el baseline y calcula, sin red, qué habría elegido el challenger.
// Todo lo contrafactual es estimación: no demuestra ahorro ni latencia del challenger.
import { createHash } from 'node:crypto';
import type { FederatedSearchResponse } from '../types.js';
import { selectDestinations, type SelectionInput, type Termination } from './select.js';

export const SHADOW_RECEIPT_VERSION = 1;

export interface ShadowReceipt {
  receiptVersion: number;
  /** Id opaco aportado por el llamante; un hash de la consulta NO anonimiza y no se usa. */
  queryId: string;
  configHash: string;
  evidenceType: 'counterfactual-estimate';
  baseline: { remoteCalls: number; sources: string[] };
  challenger: { mode: string; selected: string[]; skipped: Array<{ id: string; reason: string }>; deniedCount: number; termination: Termination | null; estimatedRemoteCalls: number };
  estimate: { remoteCallsSaved: number; baselineResultsFromSkippedSources: number; baselineResultsTotal: number };
}

export interface ShadowOptions { queryId: string; selection: SelectionInput; baseline: () => Promise<FederatedSearchResponse>; }

const configHash = (s: SelectionInput): string => createHash('sha256').update(JSON.stringify({ b: s.budget, f: s.flags ?? {}, g: s.guidance })).digest('hex').slice(0, 16);

// `baseline` se invoca exactamente una vez; el challenger es una función pura sobre la misma entrada.
export async function runShadow(opts: ShadowOptions): Promise<{ response: FederatedSearchResponse; receipt: ShadowReceipt }> {
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(opts.queryId)) throw new Error('queryId debe ser un identificador opaco de 8-64 caracteres [A-Za-z0-9_-]');
  const response = await opts.baseline();
  // Shadow evalúa el challenger como si estuviera activo; el flag real del sistema no cambia.
  const chal = selectDestinations({ ...opts.selection, flags: { ...opts.selection.flags, adaptive: true } });
  const remoteSources = response.sources.filter(s => s.id !== 'local' && s.status !== 'skipped');
  const kept = new Set(chal.selected);
  const fromSkipped = response.results.filter(r => r.source !== 'local' && !kept.has(r.source)).length;
  const estimatedRemote = chal.selected.filter(id => id !== 'local').length;
  const receipt: ShadowReceipt = {
    receiptVersion: SHADOW_RECEIPT_VERSION, queryId: opts.queryId, configHash: configHash(opts.selection), evidenceType: 'counterfactual-estimate',
    baseline: { remoteCalls: remoteSources.length, sources: response.sources.map(s => s.id) },
    challenger: { mode: chal.mode, selected: chal.selected, skipped: chal.skipped, deniedCount: chal.deniedCount, termination: chal.termination, estimatedRemoteCalls: estimatedRemote },
    estimate: { remoteCallsSaved: remoteSources.length - estimatedRemote, baselineResultsFromSkippedSources: fromSkipped, baselineResultsTotal: response.results.length },
  };
  return { response, receipt };
}
