// SE-424 H5 — contención en el almacenamiento: ninguna operación de VaultStorage toca disco fuera
// de la raíz real de su cúpula (rutas con `..`, absolutas, codificadas, con barra invertida,
// enlaces simbólicos que salen, opciones de git disfrazadas de ruta, metadatos internos).
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { VaultStorage } from '../../../src/storage/index.js';
import { VaultSecurity, SecurityError } from '../../../src/security/index.js';
import type { VaultConfig } from '../../../src/types.js';

describe('SE-424 H5: contención del almacenamiento', () => {
  let tmp: string;
  let root: string;
  let storage: VaultStorage;

  beforeEach(async () => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-contain-'));
    root = path.join(tmp, 'A');
    fs.mkdirSync(path.join(tmp, 'B'));
    fs.writeFileSync(path.join(tmp, 'B', 'secreto.md'), '# Secreto\ncontenido-de-B\n');
    fs.writeFileSync(path.join(tmp, 'fuera.md'), '# Fuera\ncontenido-fuera\n');
    const config: VaultConfig = { name: 'A', path: root, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024, confidentiality: 'N1' };
    storage = new VaultStorage(config);
    await storage.init();
    fs.writeFileSync(path.join(root, 'nota.md'), '# Nota\ndentro\n');
  });
  afterEach(() => {
    vi.restoreAllMocks();
    fs.rmSync(tmp, { recursive: true, force: true });
  });

  const escapes = () => [
    '../fuera.md',
    '../B/secreto.md',
    'sub/../../fuera.md',
    path.join(tmp, 'fuera.md'),
    '/etc/hostname',
    '..\\fuera.md',
    'sub\\..\\..\\fuera.md',
    '%2e%2e/fuera.md',
    '%2E%2E%2Ffuera.md',
    '..%2ffuera.md',
    'C:\\Windows\\win.ini',
    'nota.md\0.txt',
    '',
  ];

  it('read: ninguna ruta que sale de la cúpula se lee', async () => {
    for (const p of escapes()) {
      await expect(storage.read(p), p).rejects.toThrow();
    }
  });

  it('write: ninguna ruta que sale de la cúpula se escribe', async () => {
    const before = fs.readFileSync(path.join(tmp, 'fuera.md'), 'utf-8');
    for (const p of escapes()) {
      await expect(storage.write(p, '# pisado\n'), p).rejects.toThrow();
    }
    expect(fs.readFileSync(path.join(tmp, 'fuera.md'), 'utf-8')).toBe(before);
    await expect(storage.write('../nuevo-fuera.md', 'x')).rejects.toThrow(SecurityError);
    expect(fs.existsSync(path.join(tmp, 'nuevo-fuera.md'))).toBe(false);
  });

  it('diff y log: no comparan ni listan rutas de fuera, ni aceptan opciones de git como ruta', async () => {
    for (const p of escapes()) {
      await expect(storage.diff(p), p).rejects.toThrow();
      await expect(storage.log(p), p).rejects.toThrow();
    }
    const out = path.join(tmp, 'escrito-por-git.txt');
    await expect(storage.diff(`--output=${out}`)).rejects.toThrow();
    expect(fs.existsSync(out)).toBe(false);
    // Una nota legítima cuyo nombre empieza por guion no se interpreta como opción.
    await storage.write('-raro.md', '# raro\n');
    await expect(storage.diff('-raro.md')).resolves.toBe('');
  });

  it('delete: no borra ni mueve nada de fuera', async () => {
    for (const p of escapes()) {
      await expect(storage.delete(p), p).rejects.toThrow();
    }
    expect(fs.existsSync(path.join(tmp, 'fuera.md'))).toBe(true);
    expect(fs.existsSync(path.join(tmp, 'B', 'secreto.md'))).toBe(true);
  });

  it('enlaces simbólicos que salen: ni lectura ni escritura (fichero, directorio y enlace roto)', async () => {
    fs.symlinkSync(path.join(tmp, 'fuera.md'), path.join(root, 'enlace.md'));
    fs.symlinkSync(path.join(tmp, 'B'), path.join(root, 'dir-enlace'));
    fs.symlinkSync(path.join(tmp, 'aun-no-existe.md'), path.join(root, 'roto.md'));
    await expect(storage.read('enlace.md')).rejects.toThrow(SecurityError);
    await expect(storage.read('dir-enlace/secreto.md')).rejects.toThrow(SecurityError);
    await expect(storage.write('enlace.md', '# pisado\n')).rejects.toThrow(SecurityError);
    await expect(storage.write('dir-enlace/nuevo.md', '# x\n')).rejects.toThrow(SecurityError);
    await expect(storage.write('roto.md', '# x\n')).rejects.toThrow(SecurityError);
    expect(fs.readFileSync(path.join(tmp, 'fuera.md'), 'utf-8')).toContain('contenido-fuera');
    expect(fs.existsSync(path.join(tmp, 'B', 'nuevo.md'))).toBe(false);
    expect(fs.existsSync(path.join(tmp, 'aun-no-existe.md'))).toBe(false);
  });

  it('la raíz de la cúpula puede ser ella misma un enlace: lo que queda dentro de su destino real vale', async () => {
    const alias = path.join(tmp, 'alias-de-A');
    fs.symlinkSync(root, alias);
    const viaAlias = new VaultStorage({ name: 'A', path: alias, allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1024 * 1024 });
    expect((await viaAlias.read('nota.md')).content).toContain('dentro');
    await expect(viaAlias.read('../fuera.md')).rejects.toThrow(SecurityError);
  });

  it('metadatos internos (.git, .savia-vault, .trash) no se escriben por la API de notas', async () => {
    for (const p of ['.git/hooks/pre-commit', '.git/config', '.savia-vault/x.json', '.trash/x.md', 'sub/.git/config']) {
      await expect(storage.write(p, '#!/bin/sh\n'), p).rejects.toThrow(SecurityError);
    }
    expect(fs.existsSync(path.join(root, '.git', 'hooks', 'pre-commit'))).toBe(false);
  });

  it('caso positivo: rutas normales dentro (subcarpetas, nombres con puntos) siguen funcionando', async () => {
    await storage.write('sub/dir/nueva.md', '# Nueva\nhola\n');
    expect((await storage.read('sub/dir/nueva.md')).content).toContain('hola');
    await storage.write('a..b.md', '# dos puntos en el nombre\n');
    expect((await storage.read('a..b.md')).content).toContain('dos puntos');
    expect((await storage.read('./nota.md')).content).toContain('dentro');
    expect(await storage.log('sub/dir/nueva.md')).toHaveLength(1);
    await storage.delete('sub/dir/nueva.md');
    expect(fs.existsSync(path.join(root, 'sub', 'dir', 'nueva.md'))).toBe(false);
  });

  it('toda operación que toca disco con una ruta pedida pasa por VaultSecurity.contain', async () => {
    const spy = vi.spyOn(VaultSecurity.prototype, 'contain');
    const ops: [string, () => Promise<unknown>][] = [
      ['read', () => storage.read('nota.md')],
      ['write', () => storage.write('w.md', '# w\n')],
      ['diff', () => storage.diff('nota.md')],
      ['log', () => storage.log('nota.md')],
      ['delete', () => storage.delete('w.md')],
    ];
    for (const [name, op] of ops) {
      spy.mockClear();
      await op();
      expect(spy, name).toHaveBeenCalled();
    }
  });
});
