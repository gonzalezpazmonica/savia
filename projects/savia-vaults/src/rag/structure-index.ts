import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { chunkOrderHash, openProjectionSource, type ProjectionSource } from './binary-store.js';
import { ensureSafeHome, writeAtomic } from './store.js';
import { RagError, type Chunk, type IndexCipher, type Manifest } from './types.js';
import type { Locator } from '../files/types.js';

/**
 * SE-489 M3 — StructureIndex: árbol documento → sección → unidad de una generación.
 * Se construye en el sync a partir de los chunks de la generación (Markdown: encabezados del
 * chunker; Savia Files: localizadores). Es una proyección derivada, como las de M7:
 *   - vive en el directorio de la generación (`structure-<seq>.{json,bin}`): rollback y retirada la siguen;
 *   - lleva un `binding` (hash) a generación, seq, orden y contenido de los chunks y clasificación;
 *     si algo no casa se rechaza (nunca se sirve una estructura que no corresponde);
 *   - se cifra si la fuente está sellada y nunca se escribe dentro de un repo git.
 * No guarda texto: las unidades apuntan a `chunkId` y el texto se lee del índice activo a través
 * del guard. `nodeId` es estable: depende de la ruta estructural, no del contenido (eso es `contentHash`).
 */

export const STRUCTURE_VERSION = 'structure-v1';
const HEADER_VERSION = 1;

export type StructureKind = 'document' | 'section' | 'unit';

export interface StructureNode {
  nodeId: string;
  kind: StructureKind;
  /** Ruta relativa del documento (o `files/<id>`). */
  document: string;
  parent?: string;
  children: string[];
  /** Título (documento), último tramo del encabezado (sección) o encabezado completo (unidad). */
  title: string;
  /** Documento: `doc`; sección: `section:<h2 › h3>[@n]` o contenedor de Files; unidad: el de su evidencia. */
  locator: string;
  depth: number;
  /** Solo unidades: chunk del índice. */
  chunkId?: string;
  ordinal?: number;
  /** Unidad: `sha256:` del texto del chunk; sección y documento: hash de los hijos (Merkle). */
  contentHash: string;
}

/** Documentos de una generación, cada uno con sus nodos en pre-orden (el primero es el documento). */
export type StructureDocs = Record<string, StructureNode[]>;

export interface StructureHeader {
  headerVersion: number;
  builder: string;
  dome: string;
  generation: string;
  seq: number;
  chunkCount: number;
  chunkOrder: string;
  classification: string;
  sealed: boolean;
  nodeCount: number;
  payloadHash: string;
  binding: string;
}

type Binding = Omit<StructureHeader, 'payloadHash' | 'binding' | 'nodeCount'>;

const hex = (data: string | Uint8Array): string => createHash('sha256').update(data).digest('hex');
const sha = (data: string): string => `sha256:${hex(data)}`;
const SEP = ' › ';

function fileLocator(l: Locator): string {
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

/** Contenedor de Savia Files: página, diapositiva u hoja; el resto cuelga del documento. */
function fileSection(l: Locator): { key: string; title: string } | undefined {
  if (l.type === 'page') return { key: `page:${l.page}`, title: `p. ${l.page}` };
  if (l.type === 'slide') return { key: `slide:${l.slide}`, title: `diapositiva ${l.slide}` };
  if (l.type === 'cell') return { key: `sheet:${l.sheet}`, title: l.sheet };
  return undefined;
}

const nodeIdOf = (dome: string, document: string, kind: StructureKind, key: string): string =>
  `n_${hex(`${dome}\u0000${document}\u0000${kind}\u0000${key}`).slice(0, 20)}`;

type TreeChunk = Pick<Chunk, 'id' | 'ordinal' | 'heading' | 'text' | 'meta' | 'source'>;

/** Árbol de un documento a partir de sus chunks. Función pura y determinista. */
export function buildDocumentTree(dome: string, document: string, chunks: readonly TreeChunk[]): StructureNode[] {
  const sorted = [...chunks].sort((a, b) => a.ordinal - b.ordinal);
  const root: StructureNode = {
    nodeId: nodeIdOf(dome, document, 'document', ''), kind: 'document', document, children: [],
    title: sorted[0]?.meta.title ?? path.posix.basename(document), locator: 'doc', depth: 0, contentHash: '',
  };
  const byId = new Map<string, StructureNode>([[root.nodeId, root]]);
  const occurrences = new Map<string, number>();
  const unitsIn = new Map<string, number>();
  /** Secciones abiertas del chunk anterior: un mismo encabezado consecutivo es la misma sección. */
  let open: { key: string; node: StructureNode }[] = [];

  const section = (parent: StructureNode, key: string, title: string, locator: string, depth: number): StructureNode => {
    const occ = occurrences.get(key) ?? 0;
    occurrences.set(key, occ + 1);
    const node: StructureNode = {
      nodeId: nodeIdOf(dome, document, 'section', `${key}\u001e${occ}`), kind: 'section', document,
      parent: parent.nodeId, children: [], title, locator: occ ? `${locator}@${occ}` : locator, depth, contentHash: '',
    };
    parent.children.push(node.nodeId);
    byId.set(node.nodeId, node);
    return node;
  };

  for (const c of sorted) {
    let segs: { key: string; title: string; locator: string }[];
    if (c.source) {
      const s = fileSection(c.source.locator);
      segs = s ? [{ key: s.key, title: s.title, locator: s.key }] : [];
    } else {
      // «título › h2 › h3»: el primer tramo es el documento.
      const parts = c.heading.split(SEP).slice(1).filter(Boolean);
      segs = parts.map((_, i) => {
        const p = parts.slice(0, i + 1).join(SEP);
        return { key: p, title: parts[i], locator: `section:${p}` };
      });
    }
    let shared = 0;
    while (shared < open.length && shared < segs.length && open[shared].key === segs[shared].key) shared++;
    const next = open.slice(0, shared);
    for (let i = shared; i < segs.length; i++) {
      const parent = i === 0 ? root : next[i - 1].node;
      next.push({ key: segs[i].key, node: section(parent, segs[i].key, segs[i].title, segs[i].locator, i + 1) });
    }
    open = next;
    const parent = open.length ? open[open.length - 1].node : root;
    const n = unitsIn.get(parent.nodeId) ?? 0;
    unitsIn.set(parent.nodeId, n + 1);
    const locator = c.source
      ? `${fileLocator(c.source.locator)}${c.source.locatorEnd ? `..${fileLocator(c.source.locatorEnd)}` : ''}`
      : `#${c.ordinal} ${c.heading}`.trim();
    const unit: StructureNode = {
      nodeId: nodeIdOf(dome, document, 'unit', `${parent.nodeId}\u001e${n}`), kind: 'unit', document,
      parent: parent.nodeId, children: [], title: c.heading, locator, depth: parent.depth + 1,
      chunkId: c.id, ordinal: c.ordinal, contentHash: sha(c.text),
    };
    parent.children.push(unit.nodeId);
    byId.set(unit.nodeId, unit);
  }

  // Merkle de abajo arriba: un cambio en una unidad cambia el hash de su sección y del documento.
  const hashOf = (n: StructureNode): string => {
    if (n.kind !== 'unit') n.contentHash = sha(n.children.map(id => hashOf(byId.get(id)!)).join('\n'));
    return n.contentHash;
  };
  hashOf(root);
  const ordered: StructureNode[] = [];
  const walk = (n: StructureNode): void => { ordered.push(n); for (const id of n.children) walk(byId.get(id)!); };
  walk(root);
  return ordered;
}

/** Estructura de todos los documentos de una generación. */
export function buildStructure(dome: string, chunks: readonly (TreeChunk & { path: string })[]): StructureDocs {
  const byDoc = new Map<string, TreeChunk[]>();
  for (const c of chunks) {
    const list = byDoc.get(c.path);
    if (list) list.push(c); else byDoc.set(c.path, [c]);
  }
  const out: StructureDocs = {};
  for (const doc of [...byDoc.keys()].sort()) out[doc] = buildDocumentTree(dome, doc, byDoc.get(doc)!);
  return out;
}

export const structurePath = (dir: string, seq: number): { header: string; payload: string } => ({
  header: path.join(dir, `structure-${seq}.json`),
  payload: path.join(dir, `structure-${seq}.bin`),
});

function expectedBinding(src: ProjectionSource, classification: string): Binding {
  const m = src.manifest;
  return {
    headerVersion: HEADER_VERSION, builder: STRUCTURE_VERSION, dome: m.dome, generation: m.generation, seq: m.seq,
    chunkCount: src.size, chunkOrder: chunkOrderHash(src), classification, sealed: Boolean(m.sealed),
  };
}

const bindingOf = (b: Binding): string => hex(JSON.stringify(Object.entries(b).sort(([x], [y]) => (x < y ? -1 : 1))));
const sealPart = (seq: number, binding: string): string => `structure-${seq}|${binding}`;

/** Navegación determinista sobre la estructura cargada. */
export class StructureIndex {
  private readonly byId = new Map<string, StructureNode>();
  private readonly byChunk = new Map<string, StructureNode>();

  constructor(public readonly header: StructureHeader, public readonly docs: StructureDocs) {
    for (const nodes of Object.values(docs)) {
      for (const n of nodes) {
        this.byId.set(n.nodeId, n);
        if (n.chunkId) this.byChunk.set(n.chunkId, n);
      }
    }
  }

  get nodeCount(): number { return this.byId.size; }
  documents(): string[] { return Object.keys(this.docs); }
  document(doc: string): StructureNode[] | undefined { return Object.hasOwn(this.docs, doc) ? this.docs[doc] : undefined; }
  node(id: string): StructureNode | undefined { return this.byId.get(id); }
  unitOf(chunkId: string): StructureNode | undefined { return this.byChunk.get(chunkId); }
  parent(id: string): StructureNode | undefined { const p = this.byId.get(id)?.parent; return p ? this.byId.get(p) : undefined; }
  children(id: string): StructureNode[] { return (this.byId.get(id)?.children ?? []).map(c => this.byId.get(c)!); }
  /** Hermanos en orden de documento, sin el propio nodo. */
  siblings(id: string): StructureNode[] {
    const p = this.parent(id);
    return p ? this.children(p.nodeId).filter(n => n.nodeId !== id) : [];
  }
  /** Sección (o documento) que contiene una unidad. */
  sectionOf(chunkId: string): StructureNode | undefined { const u = this.byChunk.get(chunkId); return u ? this.parent(u.nodeId) : undefined; }
  /** Documentos del mismo directorio (orden alfabético), sin el propio. */
  siblingDocuments(doc: string): string[] {
    const dir = path.posix.dirname(doc);
    return this.documents().filter(d => d !== doc && path.posix.dirname(d) === dir);
  }

  /** Construye y persiste la estructura de una generación (sustituye la de su seq). */
  static build(src: ProjectionSource, classification: string, cipher?: IndexCipher): StructureIndex {
    const m = src.manifest;
    if (m.sealed && !cipher) throw new RagError('PROJECTION_MISMATCH', 'la fuente está cifrada: la estructura exige el mismo cifrador');
    ensureSafeHome(src.dir);
    const docs = buildStructure(m.dome, src.chunks);
    const b = expectedBinding(src, classification);
    const binding = bindingOf(b);
    const plain = Buffer.from(JSON.stringify(docs));
    const onDisk = m.sealed ? cipher!.seal(plain, sealPart(m.seq, binding)) : plain;
    const nodeCount = Object.values(docs).reduce((n, d) => n + d.length, 0);
    const header: StructureHeader = { ...b, nodeCount, payloadHash: hex(onDisk), binding };
    const p = structurePath(src.dir, m.seq);
    // Payload primero, cabecera después: sin cabecera válida la estructura no existe.
    writeAtomic(p.payload, onDisk);
    writeAtomic(p.header, JSON.stringify(header, null, 2));
    return new StructureIndex(header, docs);
  }

  /** Carga la estructura de la seq vigente; si no casa con la generación, PROJECTION_MISMATCH. */
  static load(src: ProjectionSource, classification: string, cipher?: IndexCipher): StructureIndex {
    const m = src.manifest;
    const p = structurePath(src.dir, m.seq);
    let header: StructureHeader;
    let raw: Buffer;
    try {
      header = JSON.parse(fs.readFileSync(p.header, 'utf-8')) as StructureHeader;
      raw = fs.readFileSync(p.payload);
    } catch {
      throw new RagError('PROJECTION_MISMATCH', `sin estructura para ${m.generation} seq ${m.seq}`);
    }
    if (!header || typeof header !== 'object') throw new RagError('PROJECTION_MISMATCH', 'cabecera de la estructura no válida');
    const want = expectedBinding(src, classification);
    for (const k of Object.keys(want) as (keyof Binding)[]) {
      if (header[k] !== want[k]) throw new RagError('PROJECTION_MISMATCH', `estructura obsoleta o ajena: difiere ${k}`);
    }
    if (header.binding !== bindingOf(want)) throw new RagError('PROJECTION_MISMATCH', 'binding de la estructura no válido');
    if (hex(raw) !== header.payloadHash) throw new RagError('PROJECTION_MISMATCH', 'contenido de la estructura alterado');
    if (m.sealed && !cipher) throw new RagError('PROJECTION_MISMATCH', 'estructura cifrada sin cifrador');
    let docs: StructureDocs;
    try {
      docs = JSON.parse((m.sealed ? cipher!.open(raw, sealPart(m.seq, header.binding)) : raw).toString('utf-8')) as StructureDocs;
    } catch {
      throw new RagError('PROJECTION_MISMATCH', 'no se pudo abrir la estructura');
    }
    const idx = new StructureIndex(header, docs);
    if (idx.nodeCount !== header.nodeCount) throw new RagError('PROJECTION_MISMATCH', 'número de nodos de la estructura inconsistente');
    // Cada unidad apunta a un chunk de la generación con ese mismo contenido.
    const chunks = new Map(src.chunks.map(c => [c.id, c]));
    for (const nodes of Object.values(docs)) {
      for (const n of nodes) {
        if (n.kind !== 'unit') continue;
        const c = n.chunkId ? chunks.get(n.chunkId) : undefined;
        if (!c || c.path !== n.document || sha(c.text) !== n.contentHash) throw new RagError('PROJECTION_MISMATCH', 'unidad de la estructura sin chunk vigente');
      }
    }
    return idx;
  }
}

/** Carga la estructura de una generación o la construye si falta o no casa. */
export function ensureStructure(dir: string, classification: string, cipher?: IndexCipher): { index: StructureIndex; built: boolean } {
  const src = openProjectionSource(dir, cipher);
  try {
    return { index: StructureIndex.load(src, classification, cipher), built: false };
  } catch (e) {
    if (!(e instanceof RagError) || e.code !== 'PROJECTION_MISMATCH') throw e;
  }
  const index = StructureIndex.build(src, classification, cipher);
  // Fuente cifrada: no se esperan lectores de seq antiguas (como gcGeneration(genDir, 0) en el indexer).
  if (src.manifest.sealed) gcStructure(dir, src.manifest, 0);
  return { index, built: true };
}

const STRUCT_FILE = /^structure-(\d+)\.(json|bin)$/;

/**
 * Borra estructuras de una generación que no son de la seq de su manifest, y temporales huérfanos,
 * con periodo de gracia (lectores abiertos). Sin manifest legible no borra nada.
 */
export function gcStructure(dir: string, manifest: Manifest | undefined, graceMs = 10 * 60 * 1000): number {
  if (!manifest) return 0;
  let removed = 0;
  for (const f of fs.existsSync(dir) ? fs.readdirSync(dir) : []) {
    const m = f.match(STRUCT_FILE);
    const tmp = !m && /^structure-.*\.tmp-/.test(f);
    if (!m && !tmp) continue;
    if (m && Number(m[1]) === manifest.seq) continue;
    const full = path.join(dir, f);
    if (graceMs > 0 && Date.now() - fs.statSync(full).mtimeMs < graceMs) continue;
    fs.rmSync(full, { force: true });
    removed++;
  }
  return removed;
}
