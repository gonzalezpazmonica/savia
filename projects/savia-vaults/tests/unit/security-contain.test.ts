// SE-424 H5: probar la puerta de disco directamente, con rutas y enlaces reales aislados.
// Los controles positivos evitan un rechazo universal; `notes/../note.md` detecta el mutante
// que elimina el rechazo de `..`, aunque la ruta normalizada siga dentro de la cúpula.
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { SecurityError, VaultSecurity } from '../../src/security/index.js';
import type { VaultConfig } from '../../src/types.js';

describe('VaultSecurity.contain: puerta única de contención', () => {
  let tmp: string;
  let root: string;
  let outside: string;
  let config: VaultConfig;
  let security: VaultSecurity;

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-contain-unit-'));
    root = path.join(tmp, 'root');
    outside = path.join(tmp, 'outside');
    fs.mkdirSync(path.join(root, 'notes'), { recursive: true });
    fs.mkdirSync(outside);
    fs.writeFileSync(path.join(root, 'note.md'), 'dentro');
    fs.writeFileSync(path.join(outside, 'note.md'), 'fuera');
    config = { name: 'test-vault', path: root, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 };
    security = new VaultSecurity(config);
  });

  afterEach(() => fs.rmSync(tmp, { recursive: true, force: true }));

  it.each(['note.md', 'notes/new.md', 'a..b.md', 'notes/.hidden.md'])(
    'devuelve las dos rutas de una nota válida: %s', (requested) => {
      expect(security.contain(requested)).toEqual({ abs: path.join(root, requested), rel: requested });
    },
  );

  it('normaliza puntos y separadores repetidos, conservando la ruta relativa POSIX', () => {
    expect(security.contain('./notes//./new.md')).toEqual({
      abs: path.join(root, 'notes', 'new.md'), rel: 'notes/new.md',
    });
  });

  it('acepta una futura nota sin crear sus directorios ni el fichero', () => {
    expect(security.contain('new/sub/note.md')).toEqual({
      abs: path.join(root, 'new', 'sub', 'note.md'), rel: 'new/sub/note.md',
    });
    expect(fs.existsSync(path.join(root, 'new'))).toBe(false);
  });

  it('acepta una raíz aún inexistente sin crearla', () => {
    const futureRoot = path.join(tmp, 'future');
    const future = new VaultSecurity({ ...config, path: futureRoot });
    expect(future.contain('note.md')).toEqual({ abs: path.join(futureRoot, 'note.md'), rel: 'note.md' });
    expect(fs.existsSync(futureRoot)).toBe(false);
  });

  it.each([
    '../../../etc/passwd', '../outside/note.md', 'missing/../../outside/note.md',
    'notes/../note.md', 'notes/..', '%2e%2e/note.md', 'notes/%2E%2E/note.md',
    '..%2fnote.md', '%2e%2e%5cnote.md', '..\\outside\\note.md', 'notes\\note.md',
    '', '.', './', 'note.md\0.txt', 'notes/\0/note.md',
    '/etc/passwd', 'C:/Windows/win.ini', 'C:\\Windows\\win.ini', 'C:note.md',
    '\\\\server\\share\\note.md',
  ])('rechaza una ruta no válida con SecurityError: %j', (requested) => {
    expect(() => security.contain(requested)).toThrow(SecurityError);
  });

  it('rechaza una ruta absoluta incluso cuando apunta dentro de la raíz', () => {
    expect(() => security.contain(path.join(root, 'note.md'))).toThrow(SecurityError);
  });

  it('acepta exactamente maxDepth segmentos y rechaza uno más', () => {
    const shallow = new VaultSecurity({ ...config, maxDepth: 3 });
    expect(shallow.contain('a/b/note.md')).toEqual({
      abs: path.join(root, 'a', 'b', 'note.md'), rel: 'a/b/note.md',
    });
    expect(() => shallow.contain('a/b/c/note.md')).toThrow(SecurityError);
    expect(fs.existsSync(path.join(root, 'a'))).toBe(false);
  });

  it.each(['.git/config', '.savia-vault/config.json', '.trash/note.md', 'notes/.GIT/config'])(
    'rechaza metadatos internos: %s', (requested) => {
      expect(() => security.contain(requested)).toThrow(SecurityError);
    },
  );

  it('rechaza una carpeta denegada configurada, también si viene codificada', () => {
    const restricted = new VaultSecurity({ ...config, deniedPaths: ['private'] });
    expect(() => restricted.contain('PRIVATE/note.md')).toThrow(SecurityError);
    expect(() => restricted.contain('%70rivate/note.md')).toThrow(SecurityError);
    expect(restricted.contain('private-notes/note.md').rel).toBe('private-notes/note.md');
  });

  it('permite enlaces a ficheros y directorios dentro de la raíz', () => {
    fs.symlinkSync(path.join(root, 'note.md'), path.join(root, 'link.md'), 'file');
    fs.symlinkSync(path.join(root, 'notes'), path.join(root, 'linked-notes'), 'dir');
    expect(security.contain('link.md')).toEqual({ abs: path.join(root, 'link.md'), rel: 'link.md' });
    expect(security.contain('linked-notes/new.md')).toEqual({
      abs: path.join(root, 'linked-notes', 'new.md'), rel: 'linked-notes/new.md',
    });
  });

  it('resuelve una raíz enlazada contra su destino real', () => {
    const alias = path.join(tmp, 'alias');
    fs.symlinkSync(root, alias, 'dir');
    const linkedRoot = new VaultSecurity({ ...config, path: alias });
    expect(linkedRoot.contain('note.md')).toEqual({ abs: path.join(root, 'note.md'), rel: 'note.md' });
    expect(() => linkedRoot.contain('../outside/note.md')).toThrow(SecurityError);
  });

  it('rechaza un enlace de fichero que sale sin modificar el destino', () => {
    const target = path.join(outside, 'note.md');
    fs.symlinkSync(target, path.join(root, 'escape.md'), 'file');
    expect(() => security.contain('escape.md')).toThrow(SecurityError);
    expect(fs.readFileSync(target, 'utf8')).toBe('fuera');
  });

  it.each(['note.md', 'new/note.md'])(
    'rechaza directorios enlazados fuera, también para destinos inexistentes: %s', (requested) => {
      fs.symlinkSync(outside, path.join(root, 'escape'), 'dir');
      expect(() => security.contain(`escape/${requested}`)).toThrow(SecurityError);
      expect(fs.existsSync(path.join(outside, 'new'))).toBe(false);
    },
  );

  it('rechaza un enlace roto sin crear su destino', () => {
    const target = path.join(outside, 'missing.md');
    fs.symlinkSync(target, path.join(root, 'broken.md'), 'file');
    expect(() => security.contain('broken.md')).toThrow(SecurityError);
    expect(fs.existsSync(target)).toBe(false);
  });

  it.each(['file', 'dir'] as const)('rechaza un enlace %s a root-mala que comparte el prefijo de root', (type) => {
    const sibling = `${root}-mala`;
    fs.mkdirSync(sibling);
    fs.writeFileSync(path.join(sibling, 'note.md'), 'vecina');
    const target = type === 'file' ? path.join(sibling, 'note.md') : sibling;
    fs.symlinkSync(target, path.join(root, 'prefix-link'), type);
    const requested = type === 'file' ? 'prefix-link' : 'prefix-link/new.md';
    expect(() => security.contain(requested)).toThrow(SecurityError);
    expect(fs.readFileSync(path.join(sibling, 'note.md'), 'utf8')).toBe('vecina');
    expect(fs.existsSync(path.join(sibling, 'new.md'))).toBe(false);
  });
});
