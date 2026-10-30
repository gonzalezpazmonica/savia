// wikilink-validator.ts — WikiLink extraction, validation, and backlink resolution

export interface WikiLinkValidation {
  source: string;
  target: string;
  displayText: string;
  exists: boolean;
  line?: number;
}

export interface BacklinkInfo {
  source: string;
  context: string;
}

const WIKILINK_RE = /\[\[([^\]]+)\]\]/g;

export function extractWikiLinks(content: string): { target: string; displayText: string }[] {
  const links: { target: string; displayText: string }[] = [];
  const matches = content.matchAll(WIKILINK_RE);
  for (const match of matches) {
    const inner = match[1];
    const pipeIdx = inner.indexOf('|');
    const target = pipeIdx > -1 ? inner.slice(0, pipeIdx).trim() : inner.trim();
    const displayText = pipeIdx > -1 ? inner.slice(pipeIdx + 1).trim() : target;
    links.push({ target, displayText });
  }
  return links;
}

export function validateWikiLinks(
  sourcePath: string,
  content: string,
  knownEntities: Set<string>,
): WikiLinkValidation[] {
  const links = extractWikiLinks(content);
  return links.map((link, i) => ({
    source: sourcePath,
    target: link.target,
    displayText: link.displayText,
    exists: knownEntities.has(link.target),
    line: i + 1,
  }));
}

/** Nota destino de un backlink: ruta y, si existen, entidad y alias del frontmatter. */
export interface BacklinkTarget {
  path: string;
  entityId?: string;
  aliases?: string[];
}

export interface WikiNote {
  path: string;
  content: string;
  frontmatter?: Record<string, unknown>;
}

const stripMd = (s: string): string => s.replace(/\.md$/i, '');

/** Destino de un enlace sin ancla (`#sección`, `^bloque`) ni extensión, en minúsculas. */
function linkKey(target: string): string {
  return stripMd(target.split(/[#^]/)[0].trim()).toLowerCase();
}

/** Alias y entidad de una nota del frontmatter. */
export function noteTargetOf(note: { path: string; frontmatter?: Record<string, unknown> }): BacklinkTarget {
  const fm = note.frontmatter ?? {};
  const entity = fm.entity as Record<string, unknown> | undefined;
  const raw = fm.aliases ?? fm.alias;
  const aliases = (Array.isArray(raw) ? raw : typeof raw === 'string' ? [raw] : []).map(String);
  return { path: note.path, ...(entity?.id ? { entityId: String(entity.id) } : {}), ...(aliases.length ? { aliases } : {}) };
}

/**
 * Resuelve el destino de un wikilink a la ruta de una nota (SE-485 R1): ruta relativa con o sin
 * extensión, entidad, alias y nombre sin extensión. Con varias notas del mismo nombre gana la
 * de ruta más corta (como Obsidian), y a igualdad la primera por orden alfabético.
 */
export function resolveWikiTarget(target: string, notes: Array<{ path: string; frontmatter?: Record<string, unknown> }>): string | undefined {
  const key = linkKey(target);
  if (!key) return undefined;
  const byRank = (a: string, b: string) => a.length - b.length || (a < b ? -1 : a > b ? 1 : 0);
  const exact = notes.find(n => stripMd(n.path).toLowerCase() === key);
  if (exact) return exact.path;
  const named = notes.map(noteTargetOf).filter(t =>
    t.entityId?.toLowerCase() === key || t.aliases?.some(a => a.toLowerCase() === key));
  if (named.length) return named.map(t => t.path).sort(byRank)[0];
  const base = notes.filter(n => (stripMd(n.path).split('/').pop() ?? '').toLowerCase() === key.split('/').pop() && stripMd(n.path).toLowerCase().endsWith(key));
  return base.length ? base.map(n => n.path).sort(byRank)[0] : undefined;
}

export function resolveBacklinks(
  target: string | BacklinkTarget,
  allNotes: WikiNote[],
  maxResults = 50,
  contextChars = 200,
): BacklinkInfo[] {
  const t: BacklinkTarget = typeof target === 'string' ? { path: target } : target;
  // Si el destino no está entre las notas (cadena suelta), se añade para que pueda resolverse.
  const universe = allNotes.some(n => n.path === t.path) ? allNotes : [...allNotes, { path: t.path, content: '', frontmatter: {} }];
  const known = universe.map(n => n.path === t.path ? { ...n, frontmatter: { ...(n.frontmatter ?? {}), ...(t.entityId ? { entity: { id: t.entityId } } : {}), ...(t.aliases ? { aliases: t.aliases } : {}) } } : n);
  const backlinks: BacklinkInfo[] = [];

  for (const note of allNotes) {
    if (note.path === t.path) continue;
    for (const m of note.content.matchAll(WIKILINK_RE)) {
      const inner = m[1];
      const link = inner.includes('|') ? inner.slice(0, inner.indexOf('|')) : inner;
      if (resolveWikiTarget(link, known) !== t.path) continue;
      const idx = m.index ?? 0;
      const start = Math.max(0, idx - contextChars / 2);
      const context = note.content.slice(start, start + contextChars).replace(/\n/g, ' ').trim();
      backlinks.push({ source: note.path, context: `...${context}...` });
      break;
    }
    if (backlinks.length >= maxResults) break;
  }

  return backlinks;
}

export function buildEntityIndex(
  notes: Array<{ path: string; frontmatter: Record<string, unknown> }>,
): Set<string> {
  const entities = new Set<string>();
  for (const note of notes) {
    const fm = note.frontmatter || {};
    const entity = fm.entity as Record<string, unknown> | undefined;
    if (entity?.id) entities.add(String(entity.id));
    // Also index by note name without extension
    const name = note.path.replace(/\.md$/, '').split('/').pop() || note.path;
    entities.add(name);
  }
  return entities;
}

export function computeWikiLinkHealth(
  notes: Array<{ path: string; content: string }>,
  knownEntities: Set<string>,
): {
  total_links: number;
  valid_links: number;
  broken_links: number;
  broken_details: Array<{ source: string; target: string }>;
  most_linked: Array<{ entity: string; count: number }>;
} {
  let total = 0;
  let valid = 0;
  const broken: Array<{ source: string; target: string }> = [];
  const linkCounts = new Map<string, number>();

  for (const note of notes) {
    const links = extractWikiLinks(note.content);
    for (const link of links) {
      total++;
      if (knownEntities.has(link.target)) {
        valid++;
      } else {
        broken.push({ source: note.path, target: link.target });
      }
      linkCounts.set(link.target, (linkCounts.get(link.target) || 0) + 1);
    }
  }

  const most_linked = Array.from(linkCounts.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([entity, count]) => ({ entity, count }));

  return {
    total_links: total,
    valid_links: valid,
    broken_links: broken.length,
    broken_details: broken.slice(0, 20),
    most_linked,
  };
}
