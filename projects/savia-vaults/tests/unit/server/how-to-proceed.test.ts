// how_to_proceed: una frase accionable por tipo de error, sin revelar qué hay detrás.
import { describe, expect, it } from 'vitest';
import { howToProceed } from '../../../src/server/how-to-proceed.js';
import { AuthError } from '../../../src/auth/index.js';
import { NoteNotFoundError } from '../../../src/storage/index.js';
import { SecurityError, VaultSecurity } from '../../../src/security/index.js';
import { VaultStorage } from '../../../src/storage/index.js';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { RagError } from '../../../src/rag/types.js';
import { FilesError } from '../../../src/files/types.js';

describe('howToProceed', () => {
  it('nota no encontrada: sugiere buscar antes de leer', () => {
    expect(howToProceed(new NoteNotFoundError())).toMatch(/vault_search/);
  });
  it('cúpula desconocida (servidor y RAG): sugiere vault_domes', () => {
    expect(howToProceed(new Error('Dome "x" not found. Available: a, b'))).toMatch(/vault_domes/);
    expect(howToProceed(new RagError('UNKNOWN_DOME', 'x'))).toMatch(/vault_domes/);
  });
  it('permiso insuficiente: no revela si la nota o la cúpula existen ni su nivel', () => {
    for (const code of ['forbidden', 'unauthorized', 'dome_not_found'] as const) {
      const h = howToProceed(new AuthError(code, 'detalle interno N4 secreto'))!;
      expect(h).toMatch(/permiso/);
      expect(h).not.toMatch(/N4|secreto|existe/i);
    }
  });
  it('entrada inválida: ruta fuera de la cúpula, clasificación, RAG y ficheros', () => {
    expect(howToProceed(new SecurityError('PATH_OUTSIDE_DOME: ruta absoluta'))).toMatch(/ruta relativa/);
    expect(howToProceed(new Error('INVALID_CLASSIFICATION: x'))).toMatch(/N1, N2, N3, N4 o N4b/);
    expect(howToProceed(new Error('POLICY_DENIED: x'))).toMatch(/nivel/);
    expect(howToProceed(new RagError('INVALID_INPUT', 'x'))).toMatch(/parámetros/);
    expect(howToProceed(new FilesError('INVALID_INPUT', 'x'))).toMatch(/parámetros/);
  });
  it('conflicto de versión: vuelve a leer y reintenta', () => {
    expect(howToProceed(new FilesError('CONFLICT', 'x'))).toMatch(/vuelve a leer/);
  });
  it('error desconocido: sin frase (no se inventa orientación)', () => {
    expect(howToProceed(new Error('algo raro'))).toBeUndefined();
  });

  // Las ramas por texto dependen de los mensajes reales: se fijan con los lanzadores de verdad.
  describe('con los errores reales del almacén y de la seguridad', () => {
    const cfg = (dir: string) => ({ name: 'D', path: dir, allowedExtensions: [], deniedPaths: [], maxDepth: 3, maxFileSize: 1_000_000, confidentiality: 'N2' });
    const thrown = async (fn: () => unknown): Promise<unknown> => { try { await fn(); } catch (e) { return e; } throw new Error('no lanzó'); };
    it('SecurityError: extensión, profundidad y ruta fuera tienen frases distintas y correctas', async () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'htp-sec-'));
      try {
        const sec = new VaultSecurity(cfg(dir));
        const ext = howToProceed(await thrown(() => sec.checkExtension(path.join(dir, 'a.exe'))))!;
        const depth = howToProceed(await thrown(() => sec.checkDepth('a/b/c/d/e.md')))!;
        const out = howToProceed(await thrown(() => sec.contain('../fuera.md')))!;
        expect(ext).toMatch(/extensión/);
        expect(depth).toMatch(/carpetas anidadas/);
        expect(out).toMatch(/ruta relativa/);
        expect(new Set([ext, depth, out]).size).toBe(3);
      } finally { fs.rmSync(dir, { recursive: true, force: true }); }
    });
    it('VaultStorage.write real: POLICY_DENIED e INVALID_CLASSIFICATION reciben su frase', async () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'htp-st-'));
      try {
        const st = new VaultStorage(cfg(dir));
        const pol = await thrown(() => st.write('a.md', '---\nconfidentiality: N4\n---\nx\n'));
        expect(howToProceed(pol)).toMatch(/nivel de confidencialidad que la cúpula admita/);
        const inv = await thrown(() => st.write('b.md', '---\nconfidentiality: zzz\n---\nx\n'));
        expect(howToProceed(inv)).toMatch(/N1, N2, N3, N4 o N4b/);
      } finally { fs.rmSync(dir, { recursive: true, force: true }); }
    });
  });
});
