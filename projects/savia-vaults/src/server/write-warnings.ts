// Avisos al escribir una nota (vault_write). NO detectan nada nuevo: componen lo que ya existe en
// src/knowledge (wikilink-validator, conflicts, graph, communities). Nunca bloquean la escritura.
// Fail-open SOLO aquí: si el cálculo falla o tarda más de WARNINGS_TIMEOUT_MS, se devuelve
// `warnings_unavailable: true`; la escritura y sus controles de seguridad no pasan por este módulo.

import { extractWikiLinks, resolveBacklinks, resolveWikiTarget, noteTargetOf } from '../knowledge/wikilink-validator.js';
import { detectConflicts } from '../knowledge/conflicts.js';
import { CommunityDetector } from '../knowledge/communities.js';
import type { GraphNode } from '../knowledge/graph.js';
import { exceedsDomeLevel } from '../storage/note-level.js';

export const WARNINGS_TIMEOUT_MS = 2000;
const MAX_NEIGHBORS = 5;
const MAX_NOTES = 500;

export interface WriteWarning { code: string; message: string; target?: string }
export interface NoteSource {
  list(): Promise<string[]>;
  read(p: string): Promise<{ path: string; name: string; frontmatter: Record<string, unknown>; content: string }>;
}
export type WarningsResult = { warnings: WriteWarning[] } | { warnings_unavailable: true };

interface Loaded { path: string; name: string; frontmatter: Record<string, unknown>; content: string }

const normTitle = (s: string): string =>
  s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim();

function titleOf(n: Loaded): string {
  const fm = typeof n.frontmatter.title === 'string' ? n.frontmatter.title : '';
  if (fm.trim()) return fm;
  const h1 = n.content.match(/^#\s+(.+)$/m);
  return h1 ? h1[1].trim() : n.name;
}

/** Solo notas que la sesión podría leer: se descarta toda nota cuyo nivel supere el de la cúpula (o no sea válido). */
async function loadReadable(src: NoteSource, domeLevel: string): Promise<Loaded[]> {
  const out: Loaded[] = [];
  for (const p of (await src.list()).slice(0, MAX_NOTES)) {
    try {
      const n = await src.read(p);
      const level = n.frontmatter?.confidentiality;
      if (level !== undefined && level !== null && exceedsDomeLevel(String(level), domeLevel)) continue;
      out.push({ path: n.path, name: n.name, frontmatter: n.frontmatter ?? {}, content: n.content });
    } catch { /* nota ilegible o en cuarentena: no cuenta */ }
  }
  return out;
}

export async function computeWriteWarnings(src: NoteSource, notePath: string, domeLevel: string): Promise<WriteWarning[]> {
  const notes = await loadReadable(src, domeLevel);
  const self = notes.find(n => n.path === notePath);
  if (!self) return [];
  const warnings: WriteWarning[] = [];

  // Título duplicado.
  const key = normTitle(titleOf(self));
  for (const o of notes) {
    if (o.path !== self.path && normTitle(titleOf(o)) === key) {
      warnings.push({ code: 'DUPLICATE_TITLE', target: o.path, message: `Otra nota de esta cúpula tiene un título equivalente: «${titleOf(o)}». Comprueba si es la misma y unifícalas.` });
    }
  }

  // Wikilinks rotos y destinos resueltos.
  const resolved = new Set<string>();
  for (const l of extractWikiLinks(self.content)) {
    const t = resolveWikiTarget(l.target, notes);
    if (t) { if (t !== self.path) resolved.add(t); }
    else warnings.push({ code: 'BROKEN_WIKILINK', target: l.target, message: `El enlace [[${l.target}]] no apunta a ninguna nota de la cúpula. Créala o corrige el enlace.` });
  }

  // Huérfana: sin enlaces salientes ni entrantes.
  const back = resolveBacklinks(noteTargetOf(self), notes);
  if (extractWikiLinks(self.content).length === 0 && back.length === 0) {
    warnings.push({ code: 'ORPHAN_NOTE', message: 'Esta nota no enlaza con ninguna otra ni nadie la enlaza. Añade al menos un enlace para que se pueda encontrar.' });
  }

  // Conflictos abiertos que la afectan.
  for (const c of detectConflicts(notes)) {
    if (c.status !== 'open' || (c.sourceA !== self.path && c.sourceB !== self.path)) continue;
    const other = c.sourceA === self.path ? c.sourceB : c.sourceA;
    warnings.push({ code: 'OPEN_CONFLICT', target: other, message: `Contradice a otra nota sobre «${c.property}» de la entidad ${c.entityId} («${c.valueA}» frente a «${c.valueB}»). Decide cuál vale.` });
  }

  // Vecinas: enlazadas (salientes o entrantes) y, después, de la misma comunidad.
  const ordered: string[] = [...resolved, ...back.map(b => b.source)];
  const nodes = new Map<string, GraphNode>();
  for (const n of notes) {
    const outgoing = extractWikiLinks(n.content)
      .map(l => resolveWikiTarget(l.target, notes))
      .filter((t): t is string => !!t && t !== n.path)
      .map(t => ({ type: 'MENTIONS', target: t }));
    nodes.set(n.path, { id: n.path, type: 'document', path: n.path, outgoing, incoming: [] });
  }
  const community = new CommunityDetector().detect({ nodes }).find(c => c.memberIds.includes(self.path));
  ordered.push(...(community?.memberIds ?? []));
  const readable = new Map(notes.map(n => [n.path, n]));
  const seen = new Set<string>([self.path]);
  for (const p of ordered) {
    if (seen.has(p) || !readable.has(p)) continue;
    seen.add(p);
    if (seen.size - 1 > MAX_NEIGHBORS) break;
    warnings.push({ code: 'NEIGHBOR_NOTE', target: p, message: `Nota cercana a revisar por si se contradicen: «${titleOf(readable.get(p)!)}».` });
  }
  return warnings;
}

export async function writeWarningsResult(src: NoteSource, notePath: string, domeLevel: string, opts: { timeoutMs?: number } = {}): Promise<WarningsResult> {
  let timer: NodeJS.Timeout | undefined;
  try {
    const timeout = new Promise<never>((_, rej) => { timer = setTimeout(() => rej(new Error('timeout')), opts.timeoutMs ?? WARNINGS_TIMEOUT_MS); });
    const warnings = await Promise.race([computeWriteWarnings(src, notePath, domeLevel), timeout]);
    return { warnings };
  } catch {
    return { warnings_unavailable: true };
  } finally {
    if (timer) clearTimeout(timer);
  }
}
