// SE-420 — nivel por nota: una nota cuyo `confidentiality` (frontmatter) supera el de su cúpula
// está «fuera de nivel» y no se sirve por ninguna vista (almacén, búsqueda, grafo, A2A, RAG).
// SE-481 — parser canónico único con cierre seguro: una clasificación explícita que no se puede
// interpretar (YAML roto, valor no textual, nivel desconocido, caracteres invisibles) deja la nota
// en cuarentena en cualquier cúpula. Todas las vistas y el indexador usan estas funciones.
import * as fs from 'node:fs';
import YAML from 'yaml';

export const LEVELS = ['N1', 'N2', 'N3', 'N4', 'N4B'] as const;
export type NoteLevel = typeof LEVELS[number];

export type ClassificationKind = 'ABSENT' | 'VALID' | 'INVALID' | 'UNPARSABLE' | 'UNKNOWN_LEVEL';
export interface ParsedClassification { kind: ClassificationKind; level?: NoteLevel; diagnostic?: string }

/** Códigos de diagnóstico estables (sin contenido de la nota). */
export type QuarantineCode =
  | 'yaml-unparsable' | 'yaml-not-map' | 'non-string' | 'empty-value'
  | 'forbidden-char' | 'duplicate-key' | 'unknown-level';

/** Sube si cambian las reglas de clasificación: el indexador reevalúa las notas reutilizadas. */
export const CLASSIFICATION_RULES = 2;

const KEY = 'confidentiality';
// Controles C0/C1 (salvo espacio), marcas bidi, anchura cero, BOM y guion blando.
const FORBIDDEN = /[\u0000-\u001F\u007F-\u009F\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]/u;
const FORBIDDEN_ALL = new RegExp(FORBIDDEN.source, 'gu');
/** Texto sin invisibles ni espacios, en minúsculas: para detectar la clave aunque esté camuflada. */
const bare = (s: string): string => s.normalize('NFKC').replace(FORBIDDEN_ALL, '').replace(/\s+/g, '').toLowerCase();
/** Tope del frontmatter que se intenta parsear (coste acotado ante notas grandes). */
const UNCLOSED_MAX = 64 * 1024;

/** Nivel canónico de una cadena (`n4b`, ` N2 `…) o undefined si no es N1..N4/N4B. */
export function canonicalLevel(value: string): NoteLevel | undefined {
  const v = value.trim().toUpperCase();
  return (LEVELS as readonly string[]).includes(v) ? v as NoteLevel : undefined;
}

const quarantine = (kind: ClassificationKind, diagnostic: QuarantineCode): ParsedClassification => ({ kind, diagnostic });

/** Bloque de frontmatter: cerrado, sin cerrar (todo el resto) o ausente. */
function frontmatterBlock(raw: string): string | undefined {
  const text = raw.startsWith('\uFEFF') ? raw.slice(1) : raw;
  if (!/^---[ \t]*\r?\n/.test(text)) return undefined;
  const closed = text.match(/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/);
  if (closed) return closed[1];
  if (/^---[ \t]*\r?\n---[ \t]*(?:\r?\n|$)/.test(text)) return '';
  return text.replace(/^---[ \t]*\r?\n/, ''); // sin cierre: todo cuenta como frontmatter
}

/**
 * R1 — Clasificación declarada en el frontmatter de un markdown.
 * ABSENT: sin frontmatter, sin la clave, o YAML roto que no la menciona (semántica heredada).
 * Cualquier otra cosa distinta de un nivel canónico es cuarentena con diagnóstico.
 */
export function parseClassification(_relPath: string, raw: string): ParsedClassification {
  const block = frontmatterBlock(raw);
  if (block === undefined) return { kind: 'ABSENT' };
  const mentions = bare(block).includes(KEY);
  // Coste acotado: un bloque enorme (frontmatter sin cerrar) no se parsea; si menciona la clave, cierra.
  if (block.length > UNCLOSED_MAX) return mentions ? quarantine('UNPARSABLE', 'yaml-unparsable') : { kind: 'ABSENT' };
  let parsed: unknown;
  try {
    parsed = YAML.parse(block, { logLevel: 'error' });
  } catch {
    return mentions ? quarantine('UNPARSABLE', 'yaml-unparsable') : { kind: 'ABSENT' };
  }
  if (parsed === null || parsed === undefined) {
    return mentions ? quarantine('UNPARSABLE', 'yaml-not-map') : { kind: 'ABSENT' };
  }
  if (typeof parsed !== 'object' || Array.isArray(parsed)) {
    return mentions ? quarantine('UNPARSABLE', 'yaml-not-map') : { kind: 'ABSENT' };
  }
  const keys = Object.keys(parsed).filter(k => k.trim().toLowerCase() === KEY);
  if (keys.length === 0) {
    // La clave aparece en el texto pero no como clave de primer nivel con ese nombre exacto
    // (p. ej. con caracteres invisibles): se trata como no interpretable.
    const hiddenKey = Object.keys(parsed).some(k => bare(k) === KEY);
    return hiddenKey ? quarantine('INVALID', 'forbidden-char') : { kind: 'ABSENT' };
  }
  if (keys.length > 1) return quarantine('INVALID', 'duplicate-key');
  const value = (parsed as Record<string, unknown>)[keys[0]];
  if (value === null || value === undefined) return quarantine('INVALID', 'empty-value');
  if (typeof value !== 'string') return quarantine('INVALID', 'non-string');
  if (FORBIDDEN.test(value)) return quarantine('INVALID', 'forbidden-char');
  if (!value.trim()) return quarantine('INVALID', 'empty-value');
  const level = canonicalLevel(value);
  if (!level) return quarantine('UNKNOWN_LEVEL', 'unknown-level');
  return { kind: 'VALID', level };
}

export const isQuarantined = (c: ParsedClassification): boolean =>
  c.kind === 'INVALID' || c.kind === 'UNPARSABLE' || c.kind === 'UNKNOWN_LEVEL';

/**
 * CRIT-001: true si el nivel supera el de la cúpula. Sin nivel, nunca; un nivel que no es
 * canónico, siempre (cierre seguro). Un nivel de cúpula desconocido cuenta como N2.
 */
export function exceedsDomeLevel(noteLevel: string | undefined, domeLevel: string): boolean {
  if (noteLevel === undefined || noteLevel === '') return false;
  const level = canonicalLevel(noteLevel);
  if (!level) return true;
  const d = (LEVELS as readonly string[]).indexOf(canonicalLevel(domeLevel) ?? 'N2');
  return LEVELS.indexOf(level) > d;
}

export type Verdict = 'serve' | 'out-of-level' | 'quarantine';

/** R2: cuarentena en cualquier cúpula; fuera de nivel solo si la cúpula declara nivel. */
export function verdictOf(c: ParsedClassification, domeLevel: string | undefined): Verdict {
  if (isQuarantined(c)) return 'quarantine';
  if (domeLevel && c.kind === 'VALID' && exceedsDomeLevel(c.level, domeLevel)) return 'out-of-level';
  return 'serve';
}

const MD = /\.(md|markdown)$/i;
export const isMarkdown = (p: string): boolean => MD.test(p);

/** true si el contenido no se puede servir ni escribir en esa cúpula (fuera de nivel o cuarentena). */
export function contentOutOfLevel(relPath: string, raw: string, domeLevel: string | undefined): boolean {
  return verdictOf(parseClassification(relPath, raw), domeLevel) !== 'serve';
}

// Caché acotada por ruta; la clave incluye mtime, ctime y tamaño (R3).
let cacheMax = 20_000;
const cache = new Map<string, { key: string; cls: ParsedClassification }>();

/** Clasificación de una nota en disco, o undefined si no existe o no es markdown. */
export function fileClassification(fullPath: string, relPath: string): ParsedClassification | undefined {
  if (!MD.test(fullPath)) return undefined;
  let st: fs.Stats;
  try { st = fs.statSync(fullPath); } catch { cache.delete(fullPath); return undefined; }
  if (!st.isFile()) return undefined;
  const key = `${st.mtimeMs}:${st.ctimeMs}:${st.size}`;
  const hit = cache.get(fullPath);
  if (hit && hit.key === key) return hit.cls;
  let cls: ParsedClassification;
  try { cls = parseClassification(relPath, fs.readFileSync(fullPath, 'utf-8')); } catch { cls = quarantine('UNPARSABLE', 'yaml-unparsable'); }
  cache.delete(fullPath);
  while (cache.size >= cacheMax) cache.delete(cache.keys().next().value as string);
  cache.set(fullPath, { key, cls });
  return cls;
}

/** Veredicto de una nota en disco; undefined si no existe (o no es markdown). */
export function fileVerdict(fullPath: string, relPath: string, domeLevel: string | undefined): Verdict | undefined {
  const cls = fileClassification(fullPath, relPath);
  return cls ? verdictOf(cls, domeLevel) : undefined;
}

/** Nota en disco que no se sirve: fuera de nivel o en cuarentena. Un fichero ausente no cuenta. */
export function fileOutOfLevel(fullPath: string, relPath: string, domeLevel: string | undefined): boolean {
  const v = fileVerdict(fullPath, relPath, domeLevel);
  return v !== undefined && v !== 'serve';
}

/** R3: la nota existe y se puede servir ahora mismo (revalidación de hits de RAG). */
export function fileServable(fullPath: string, relPath: string, domeLevel: string | undefined): boolean {
  return fileVerdict(fullPath, relPath, domeLevel) === 'serve';
}

/** Solo tests: fija la cota de la caché y la vacía. */
export function setClassificationCacheMax(n: number): void { cacheMax = Math.max(1, n); cache.clear(); }

/** Tamaño actual de la caché (tests de cota). */
export const classificationCacheSize = (): number => cache.size;
