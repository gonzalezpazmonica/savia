// SE-489 — guard de recuperación: la autorización centralizada y obligatoria de todas las rutas.
// Se aplica a cada nodo ANTES de abrirlo:
//   1. nivel de cúpula: solo cúpulas autorizadas por el plano de control;
//   2. nivel de nota y cuarentena (SE-481, `storage/note-level.ts`);
//   3. ACL de Savia Files (SE-419, `files/policy.ts`);
//   4. nota o documento borrado o reclasificado: se mira el estado ACTUAL, no el del índice.
// Una cúpula no autorizada responde igual que un nodo inexistente (`not-found`): no se revela
// título, árbol ni existencia. Las rutas no reciben rutas en disco; solo nombre y nivel.
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { exceedsDomeLevel, fileVerdict, isMarkdown, contentOutOfLevel } from '../storage/note-level.js';
import { canRead, type Principal } from '../files/policy.js';
import { FILES_PATH_PREFIX } from '../files/rag-source.js';
import type { FileStore } from '../files/store.js';
import type { Locator } from '../files/types.js';
import type { RagHit } from '../rag/types.js';
import type { AuthorizedDome, Evidence, NodeRef } from './route.js';

/** Cúpula autorizada con lo necesario para comprobar (solo lo ve el guard). */
export interface GuardDome {
  name: string;
  path: string;
  confidentiality: string;
  /** Principal del plano de control (SE-419); sin él, modo local sin usuarios. */
  principal?: Principal;
  /** Almacén de Savia Files si la cúpula lo tiene habilitado. */
  files?: FileStore;
}

export type GuardReason = 'not-found' | 'out-of-level' | 'quarantine' | 'acl' | 'invalid-ref';

export type Admission =
  | { ok: true; kind: 'note' | 'file'; dome: string; path: string; revision: string }
  | { ok: false; reason: GuardReason };

export const sha256 = (data: string | Uint8Array): string => `sha256:${crypto.createHash('sha256').update(data).digest('hex')}`;

/** Forma canónica de un localizador de Savia Files. */
export function formatLocator(l: Locator): string {
  switch (l.type) {
    case 'page': return `page:${l.page}`;
    case 'slide': return `slide:${l.slide}`;
    case 'element': return `element:${l.index}`;
    case 'cell': return `cell:${l.sheet}!${l.cell}`;
    case 'lines': return `lines:${l.from}-${l.to}`;
    case 'row': return `row:${l.row}`;
    case 'key': return `key:${l.path}`;
  }
}

const DOC_ID = /^[A-Za-z0-9_-]{1,128}$/;

/** Ruta relativa POSIX dentro de la cúpula, sin `..`, sin absolutas ni caracteres de control. */
function safeRelPath(p: unknown): string | undefined {
  if (typeof p !== 'string' || !p || p.length > 1024) return undefined;
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001F\\]/.test(p) || p.startsWith('/') || /^[A-Za-z]:/.test(p)) return undefined;
  const norm = path.posix.normalize(p);
  if (norm !== p || norm === '.' || norm.startsWith('../') || norm === '..' || norm.split('/').includes('..')) return undefined;
  return norm;
}

export class RetrievalGuard {
  private readonly domes = new Map<string, GuardDome>();
  private readonly roots = new Map<string, string | undefined>();
  private readonly revisions = new Map<string, { key: string; revision: string }>();
  /** Nodos denegados (todas las razones); la traza solo publica este número. */
  denied = 0;
  readonly deniedBy: Partial<Record<GuardReason, number>> = {};

  constructor(domes: readonly GuardDome[]) {
    for (const d of domes) this.domes.set(d.name, d);
  }

  /** Lo que una ruta puede saber de las cúpulas: nombre y nivel. */
  authorizedDomes(): AuthorizedDome[] {
    return [...this.domes.values()].map(d => ({ name: d.name, confidentiality: d.confidentiality }));
  }

  private deny(reason: GuardReason): Admission {
    this.denied++;
    this.deniedBy[reason] = (this.deniedBy[reason] ?? 0) + 1;
    return { ok: false, reason };
  }

  private root(d: GuardDome): string | undefined {
    if (!this.roots.has(d.name)) {
      let r: string | undefined;
      try { r = fs.realpathSync(d.path); } catch { r = undefined; }
      this.roots.set(d.name, r);
    }
    return this.roots.get(d.name);
  }

  /** Comprueba un nodo con su estado actual. No lee contenido de lo que deniega. */
  admit(ref: NodeRef): Admission {
    const d = typeof ref?.dome === 'string' ? this.domes.get(ref.dome) : undefined;
    if (!d) return this.deny('not-found');
    if (ref.documentId !== undefined) return this.admitFile(d, ref);
    const rel = safeRelPath(ref.path);
    if (!rel || !isMarkdown(rel)) return this.deny('invalid-ref');
    const root = this.root(d);
    if (!root) return this.deny('not-found');
    const full = path.join(d.path, rel);
    let real: string;
    try { real = fs.realpathSync(full); } catch { return this.deny('not-found'); }
    if (!real.startsWith(root + path.sep)) return this.deny('invalid-ref');
    const verdict = fileVerdict(full, rel, d.confidentiality);
    if (verdict === undefined) return this.deny('not-found');
    if (verdict === 'quarantine') return this.deny('quarantine');
    if (verdict === 'out-of-level') return this.deny('out-of-level');
    const revision = this.noteRevision(full);
    if (!revision) return this.deny('not-found');
    return { ok: true, kind: 'note', dome: d.name, path: rel, revision };
  }

  private admitFile(d: GuardDome, ref: NodeRef): Admission {
    const id = ref.documentId;
    if (typeof id !== 'string' || !DOC_ID.test(id) || ref.path !== `${FILES_PATH_PREFIX}${id}`) return this.deny('invalid-ref');
    if (!d.files) return this.deny('not-found');
    let doc;
    try { doc = d.files.get(id); } catch { return this.deny('not-found'); }
    if (doc.confidentiality && exceedsDomeLevel(doc.confidentiality, d.confidentiality)) return this.deny('out-of-level');
    let ok = false;
    try { ok = canRead(d.principal, doc, d.confidentiality); } catch { ok = false; }
    if (!ok) return this.deny('acl');
    return { ok: true, kind: 'file', dome: d.name, path: ref.path, revision: doc.currentRevision };
  }

  /** Hash de los bytes actuales, con caché por mtime/ctime/tamaño. */
  private noteRevision(full: string): string | undefined {
    let st: fs.Stats;
    try { st = fs.statSync(full); } catch { return undefined; }
    const key = `${st.mtimeMs}:${st.ctimeMs}:${st.size}`;
    const hit = this.revisions.get(full);
    if (hit?.key === key) return hit.revision;
    let revision: string;
    try { revision = sha256(fs.readFileSync(full)); } catch { return undefined; }
    this.revisions.set(full, { key, revision });
    return revision;
  }

  /**
   * Abre una nota admitida. Revalida la clasificación sobre los bytes leídos (cierre ante una
   * reclasificación entre la comprobación y la lectura).
   */
  readNote(ref: NodeRef): { dome: string; path: string; revision: string; text: string } | undefined {
    const a = this.admit({ dome: ref.dome, path: ref.path });
    if (!a.ok || a.kind !== 'note') return undefined;
    const d = this.domes.get(a.dome)!;
    let bytes: Buffer;
    try { bytes = fs.readFileSync(path.join(d.path, a.path)); } catch { this.deny('not-found'); return undefined; }
    const text = bytes.toString('utf-8');
    if (contentOutOfLevel(a.path, text, d.confidentiality)) { this.deny('out-of-level'); return undefined; }
    return { dome: a.dome, path: a.path, revision: sha256(bytes), text };
  }

  /** Evidencia de un hit con el estado actual; undefined si ya no es servible. */
  evidence(hit: RagHit): Evidence | undefined {
    const documentId = hit.source?.documentId;
    const a = this.admit({ dome: hit.dome, path: hit.path, ...(documentId !== undefined ? { documentId } : {}) });
    if (!a.ok) return undefined;
    const ordinal = hit.chunkId.slice(hit.chunkId.lastIndexOf('#') + 1);
    const locator = hit.source
      ? `${formatLocator(hit.source.locator)}${hit.source.locatorEnd ? `..${formatLocator(hit.source.locatorEnd)}` : ''}`
      : `#${ordinal} ${hit.heading}`.trim();
    return {
      chunkId: hit.chunkId, dome: a.dome, document: a.path,
      revision: hit.source ? hit.source.revisionId : a.revision,
      locator, contentHash: sha256(hit.text),
    };
  }
}
