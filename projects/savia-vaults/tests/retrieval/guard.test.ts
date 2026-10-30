// SE-489 — guard de recuperación: nivel de cúpula, nivel de nota y cuarentena (SE-481),
// ACL de Savia Files (SE-419), borrado y reclasificación, y rutas fuera de la cúpula.
import { describe, it, expect, beforeAll, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { RetrievalGuard, formatLocator, type GuardDome } from '../../src/retrieval/guard.js';
import { FileStore } from '../../src/files/store.js';
import { sodiumReady } from '../../src/files/crypto.js';
import { Journal } from '../../src/files/journal.js';
import type { RagHit } from '../../src/rag/types.js';

const note = (title: string, body: string, level?: string) =>
  `---\ntitle: ${title}\n${level ? `confidentiality: ${level}\n` : ''}---\n# ${title}\n\n${body}\n`;

describe('SE-489 RetrievalGuard', () => {
  let root: string;
  let a: GuardDome;
  let files: FileStore;

  beforeAll(async () => { await sodiumReady(); });

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-se489-guard-'));
    const vault = path.join(root, 'A');
    fs.mkdirSync(path.join(vault, 'sub'), { recursive: true });
    fs.writeFileSync(path.join(vault, 'ok.md'), note('Ok', 'contenido servible'));
    fs.writeFileSync(path.join(vault, 'alta.md'), note('Alta', 'contenido N4', 'N4'));
    fs.writeFileSync(path.join(vault, 'rota.md'), note('Rota', 'nivel inventado', 'N9'));
    fs.writeFileSync(path.join(vault, 'sub', 'dentro.md'), note('Dentro', 'anidada'));
    fs.writeFileSync(path.join(vault, 'datos.txt'), 'no es markdown');
    fs.mkdirSync(path.join(root, 'S'));
    fs.writeFileSync(path.join(root, 'S', 'secreto.md'), note('Secreto', 'fuera'));
    files = new FileStore({ home: path.join(root, 'files'), dome: 'A', domeLevel: 'N2', keysHome: path.join(root, 'keys') });
    a = { name: 'A', path: vault, confidentiality: 'N2', files };
  });
  afterEach(() => { Journal.closeAll(); fs.rmSync(root, { recursive: true, force: true }); });

  const guard = (principal?: GuardDome['principal'], extra: Partial<GuardDome> = {}) =>
    new RetrievalGuard([{ ...a, principal, ...extra }]);

  it('admite una nota servible y calcula su revisión por hash de bytes', () => {
    const g = guard();
    const r = g.admit({ dome: 'A', path: 'ok.md' });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.revision).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(g.admit({ dome: 'A', path: 'sub/dentro.md' }).ok).toBe(true);
    expect(g.denied).toBe(0);
  });

  it('cúpula no autorizada ⇒ not-found, igual que un nodo inexistente', () => {
    const g = guard();
    const secret = g.admit({ dome: 'S', path: 'secreto.md' });
    const missing = g.admit({ dome: 'A', path: 'no-existe.md' });
    expect(secret).toEqual({ ok: false, reason: 'not-found' });
    expect(missing).toEqual({ ok: false, reason: 'not-found' });
    expect(g.denied).toBe(2);
  });

  it('nota por encima del nivel de la cúpula ⇒ out-of-level; nivel inválido ⇒ quarantine', () => {
    const g = guard();
    expect(g.admit({ dome: 'A', path: 'alta.md' })).toEqual({ ok: false, reason: 'out-of-level' });
    expect(g.admit({ dome: 'A', path: 'rota.md' })).toEqual({ ok: false, reason: 'quarantine' });
    expect(g.deniedBy).toMatchObject({ 'out-of-level': 1, quarantine: 1 });
  });

  it.each(['../S/secreto.md', '/etc/passwd', 'sub/../../S/secreto.md', 'ok.md\u0000', '', 'datos.txt'])(
    'ruta %j fuera de contrato ⇒ denegada', (p) => {
      const r = guard().admit({ dome: 'A', path: p });
      expect(r.ok).toBe(false);
    });

  it('un enlace simbólico que sale de la cúpula ⇒ denegado', () => {
    fs.symlinkSync(path.join(root, 'S', 'secreto.md'), path.join(a.path, 'enlace.md'));
    expect(guard().admit({ dome: 'A', path: 'enlace.md' }).ok).toBe(false);
  });

  it('borrado y reclasificación se ven al momento, sin caché obsoleta', () => {
    const g = guard();
    expect(g.admit({ dome: 'A', path: 'ok.md' }).ok).toBe(true);
    const file = path.join(a.path, 'ok.md');
    fs.writeFileSync(file, note('Ok', 'ahora es N4 y más largo para cambiar el tamaño', 'N4'));
    const t = new Date(Date.now() + 5000);
    fs.utimesSync(file, t, t);
    expect(g.admit({ dome: 'A', path: 'ok.md' })).toEqual({ ok: false, reason: 'out-of-level' });
    fs.rmSync(file);
    expect(g.admit({ dome: 'A', path: 'ok.md' })).toEqual({ ok: false, reason: 'not-found' });
  });

  it('readNote solo devuelve contenido admitido', () => {
    const g = guard();
    expect(g.readNote({ dome: 'A', path: 'ok.md' })?.text).toContain('contenido servible');
    expect(g.readNote({ dome: 'A', path: 'alta.md' })).toBeUndefined();
    expect(g.readNote({ dome: 'S', path: 'secreto.md' })).toBeUndefined();
  });

  describe('Savia Files', () => {
    it('ACL del documento: un reader fuera de la lista no lo ve; uno dentro sí', () => {
      const { document } = files.add({ name: 'x.txt', bytes: Buffer.from('dato reservado') });
      files.setPolicy(document.id, { readers: ['ana'] });
      const ref = { dome: 'A', path: `files/${document.id}`, documentId: document.id };
      expect(guard({ username: 'luis', role: 'reader' }).admit(ref)).toEqual({ ok: false, reason: 'acl' });
      expect(guard({ username: 'ana', role: 'reader' }).admit(ref).ok).toBe(true);
    });

    it('documento borrado ⇒ not-found; cúpula sin Files ⇒ not-found', () => {
      const { document } = files.add({ name: 'y.txt', bytes: Buffer.from('y') });
      const ref = { dome: 'A', path: `files/${document.id}`, documentId: document.id };
      expect(guard(undefined, { files: undefined }).admit(ref)).toEqual({ ok: false, reason: 'not-found' });
      files.delete(document.id);
      expect(guard().admit(ref)).toEqual({ ok: false, reason: 'not-found' });
    });

    it('un documentId que no casa con la ruta ⇒ denegado', () => {
      const { document } = files.add({ name: 'z.txt', bytes: Buffer.from('z') });
      expect(guard().admit({ dome: 'A', path: 'files/otro', documentId: document.id }).ok).toBe(false);
    });
  });

  it('evidence: documento, revisión, localizador y hash del texto servido', () => {
    const g = guard();
    const hit = { dome: 'A', path: 'ok.md', chunkId: 'ok.md#0', heading: 'Ok', text: 'contenido servible' } as RagHit;
    const ev = g.evidence(hit)!;
    expect(ev).toMatchObject({ dome: 'A', document: 'ok.md', chunkId: 'ok.md#0', locator: '#0 Ok' });
    expect(ev.revision).toMatch(/^sha256:/);
    expect(ev.contentHash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(g.evidence({ ...hit, dome: 'S', path: 'secreto.md' })).toBeUndefined();
  });

  it('formatLocator da formas canónicas', () => {
    expect(formatLocator({ type: 'page', page: 3 })).toBe('page:3');
    expect(formatLocator({ type: 'cell', sheet: 'Hoja', cell: 'B2' })).toBe('cell:Hoja!B2');
    expect(formatLocator({ type: 'lines', from: 1, to: 4 })).toBe('lines:1-4');
  });

  it('authorizedDomes expone solo nombre y nivel', () => {
    expect(guard().authorizedDomes()).toEqual([{ name: 'A', confidentiality: 'N2' }]);
  });
});
