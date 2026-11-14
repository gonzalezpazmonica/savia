// SE-528 S3 — integridad de la clave de firma de grants: solo se crea si no existe (ENOENT).
// Cualquier otro fallo de lectura o una clave de longitud inválida falla cerrado con
// KeyUnavailableError, se registra con el código del sistema y la clave no cambia.
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import * as os from 'node:os';
import * as path from 'node:path';

// Fallo de lectura simulado solo para el fichero de clave; el resto pasa al fs real.
const failing = vi.hoisted(() => ({ file: '', code: '' }));
vi.mock('node:fs', async (importOriginal) => {
  const real = await importOriginal<typeof import('node:fs')>();
  const readFileSync = ((p: unknown, ...rest: unknown[]) => {
    if (failing.code && String(p) === failing.file) {
      const e = new Error(`${failing.code}: simulado, open '${String(p)}'`) as NodeJS.ErrnoException;
      e.code = failing.code;
      throw e;
    }
    return (real.readFileSync as (...a: unknown[]) => unknown)(p, ...rest);
  }) as typeof real.readFileSync;
  return { ...real, default: { ...real, readFileSync }, readFileSync };
});

const fs = await vi.importActual<typeof import('node:fs')>('node:fs');
const { TokenSigner, TokenError, KeyUnavailableError } = await import('../../../src/server/grants.js');

describe('TokenSigner — clave de firma (SE-528 S3)', () => {
  let home: string;
  let keyFile: string;
  let errors: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    home = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-grants-key-'));
    keyFile = path.join(home, '_http', 'token.key');
    failing.file = keyFile;
    failing.code = '';
    errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => {
    failing.code = '';
    errors.mockRestore();
    fs.rmSync(home, { recursive: true, force: true });
  });

  it('AC-3.3: sin fichero de clave (ENOENT) la crea 0600 y firma', () => {
    expect(fs.existsSync(keyFile)).toBe(false);
    const t = new TokenSigner(home);
    const tok = t.sign({ kind: 'upload', dome: 'D', sub: 'eva' }, 60_000);
    expect(fs.readFileSync(keyFile).length).toBe(32);
    expect(fs.statSync(keyFile).mode & 0o777).toBe(0o600);
    expect(t.verify(tok).sub).toBe('eva');
    expect(errors).not.toHaveBeenCalled();
  });

  for (const code of ['EACCES', 'EBUSY']) {
    it(`AC-3.1/3.2/3.5: lectura con ${code} ⇒ KeyUnavailableError, registrado, clave y grants intactos`, () => {
      const t = new TokenSigner(home);
      const before = t.sign({ kind: 'download', dome: 'D', sub: 'eva', documentId: 'f_1' }, 60_000);
      const keyBefore = fs.readFileSync(keyFile);

      failing.code = code;
      let thrown: unknown;
      try { t.sign({ kind: 'upload', dome: 'D', sub: 'eva' }, 60_000); } catch (e) { thrown = e; }
      expect(thrown).toBeInstanceOf(KeyUnavailableError);
      expect((thrown as InstanceType<typeof KeyUnavailableError>).sysCode).toBe(code);
      expect(thrown).not.toBeInstanceOf(TokenError);
      // verificar también falla cerrado, nunca con una clave nueva
      expect(() => t.verify(before)).toThrow(KeyUnavailableError);
      // AC-3.5: registrado con el código del sistema
      expect(errors).toHaveBeenCalled();
      expect(errors.mock.calls.map((c) => String(c[0])).join('\n')).toMatch(new RegExp(`SECURITY.*${code}`));
      // AC-3.1: el fichero de clave no cambia
      failing.code = '';
      expect(fs.readFileSync(keyFile).equals(keyBefore)).toBe(true);
      // AC-3.2: el grant firmado antes sigue verificándose cuando desaparece el error
      expect(t.verify(before).sub).toBe('eva');
    });
  }

  for (const len of [0, 31, 33]) {
    it(`AC-3.4: clave de ${len} bytes ⇒ KeyUnavailableError y el fichero no cambia`, () => {
      fs.mkdirSync(path.dirname(keyFile), { recursive: true, mode: 0o700 });
      const bad = Buffer.alloc(len, 7);
      fs.writeFileSync(keyFile, bad, { mode: 0o600 });
      const t = new TokenSigner(home);
      expect(() => t.sign({ kind: 'upload', dome: 'D', sub: 'eva' }, 60_000)).toThrow(KeyUnavailableError);
      expect(() => t.verify('svt1.e30.AAAA')).toThrow(KeyUnavailableError);
      expect(fs.readFileSync(keyFile).equals(bad)).toBe(true);
      expect(errors.mock.calls.map((c) => String(c[0])).join('\n')).toMatch(/SECURITY.*regenera/i);
    });
  }

  it('el mensaje dice que la regeneración es una acción explícita de la persona', () => {
    new TokenSigner(home).sign({ kind: 'upload', dome: 'D', sub: 'eva' }, 60_000);
    failing.code = 'EACCES';
    expect(() => new TokenSigner(home).sign({ kind: 'upload', dome: 'D', sub: 'eva' }, 60_000)).toThrow(/regenera/i);
  });
});
