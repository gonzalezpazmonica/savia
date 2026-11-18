// Unit tests: SaviaVaults security layer
// Copyright (c) 2026 Savia. MIT License.

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { VaultSecurity, SecurityError } from '../../src/security/index.js';
import type { VaultConfig } from '../../src/types.js';

const supportsSymlinks = (() => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-symlink-probe-'));
  const target = path.join(dir, 'target');
  const link = path.join(dir, 'link');
  try {
    fs.writeFileSync(target, 'probe');
    fs.symlinkSync(target, link);
    return true;
  } catch {
    return false;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
})();

function makeConfig(overrides: Partial<VaultConfig> = {}): VaultConfig {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-vault-test-'));
  return {
    name: 'test-vault',
    path: tmpDir,
    allowedExtensions: [],
    deniedPaths: [],
    maxDepth: 10,
    maxFileSize: 1024 * 1024, // 1MB
    ...overrides,
  };
}

describe('VaultSecurity', () => {
  let config: VaultConfig;
  let security: VaultSecurity;

  beforeEach(() => {
    config = makeConfig();
    security = new VaultSecurity(config);
  });

  afterEach(() => {
    if (fs.existsSync(config.path)) {
      fs.rmSync(config.path, { recursive: true, force: true });
    }
  });

  describe('resolve', () => {
    it('resolves relative paths within vault', () => {
      const result = security.resolve('notes/test.md');
      expect(result).toBe(path.join(config.path, 'notes/test.md'));
    });

    it('blocks path traversal with ..', () => {
      expect(() => security.resolve('../escape.md')).toThrow(SecurityError);
      expect(() => security.resolve('notes/../../../etc/passwd')).toThrow(SecurityError);
      expect(() => security.resolve('notes\\..\\..\\escape.md')).toThrow(SecurityError);
    });

    it('blocks absolute path outside vault', () => {
      expect(() => security.resolve('/etc/passwd')).toThrow(SecurityError);
    });

    it('allows vault root access', () => {
      expect(() => security.resolve('.')).not.toThrow();
    });
  });

  describe('checkDenied', () => {
    it('blocks .git directory', () => {
      const absPath = path.join(config.path, '.git', 'config');
      expect(() => security.checkDenied(absPath)).toThrow(SecurityError);
    });

    it('blocks node_modules', () => {
      const absPath = path.join(config.path, 'project', 'node_modules', 'pkg');
      expect(() => security.checkDenied(absPath)).toThrow(SecurityError);
    });

    it('allows normal paths', () => {
      const absPath = path.join(config.path, 'notes', 'meeting.md');
      expect(() => security.checkDenied(absPath)).not.toThrow();
    });

    it('blocks custom denied paths', () => {
      const cfg = makeConfig({ deniedPaths: ['secrets'] });
      const sec = new VaultSecurity(cfg);
      const absPath = path.join(cfg.path, 'secrets', 'keys.md');
      expect(() => sec.checkDenied(absPath)).toThrow(SecurityError);
    });
  });

  describe('checkSymlink', () => {
    it.skipIf(!supportsSymlinks)('allows symlinks within vault', () => {
      const src = path.join(config.path, 'notes', 'real.md');
      const link = path.join(config.path, 'notes', 'link.md');
      fs.mkdirSync(path.dirname(src), { recursive: true });
      fs.writeFileSync(src, 'real content');
      fs.symlinkSync(src, link);
      expect(() => security.checkSymlink(link)).not.toThrow();
      fs.unlinkSync(link);
      fs.unlinkSync(src);
    });

    it.skipIf(!supportsSymlinks)('blocks symlinks outside vault boundary', () => {
      const link = path.join(config.path, 'notes', 'escape.md');
      const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-symlink-outside-'));
      const target = path.join(outside, 'target.md');
      fs.mkdirSync(path.dirname(link), { recursive: true });
      fs.writeFileSync(target, 'outside');
      fs.symlinkSync(target, link);

      try {
        expect(() => security.checkSymlink(link)).toThrow(SecurityError);
      } finally {
        fs.unlinkSync(link);
        fs.rmSync(outside, { recursive: true, force: true });
      }
    });

    // SE-424 H5: `<raíz>-otra` empieza por `<raíz>` como texto pero no está dentro.
    it.skipIf(!supportsSymlinks)('blocks symlinks to a sibling whose name shares the vault prefix', () => {
      const sibling = `${config.path}-otra`;
      const link = path.join(config.path, 'notes', 'prefijo.md');
      fs.mkdirSync(sibling, { recursive: true });
      fs.mkdirSync(path.dirname(link), { recursive: true });
      fs.writeFileSync(path.join(sibling, 't.md'), 'vecina');
      fs.symlinkSync(path.join(sibling, 't.md'), link);
      try {
        expect(() => security.checkSymlink(link)).toThrow(SecurityError);
      } finally {
        fs.unlinkSync(link);
        fs.rmSync(sibling, { recursive: true, force: true });
      }
    });
  });

  describe('checkExtension', () => {
    it('allows .md files', () => {
      expect(() =>
        security.checkExtension(path.join(config.path, 'notes/test.md'))
      ).not.toThrow();
    });

    it('blocks .exe files', () => {
      expect(() =>
        security.checkExtension(path.join(config.path, 'malware.exe'))
      ).toThrow(SecurityError);
    });

    it('allows custom extensions', () => {
      const cfg = makeConfig({ allowedExtensions: ['.log'] });
      const sec = new VaultSecurity(cfg);
      expect(() =>
        sec.checkExtension(path.join(cfg.path, 'app.log'))
      ).not.toThrow();
    });
  });

  describe('checkDepth', () => {
    it('allows path within max depth', () => {
      expect(() => security.checkDepth('a/b/c/d.md')).not.toThrow();
    });

    it('blocks path exceeding max depth', () => {
      const deep = 'a/b/c/d/e/f/g/h/i/j/k/l/m.md';
      expect(() => security.checkDepth(deep)).toThrow(SecurityError);
    });
  });

  describe('guardRead full chain', () => {
    it('returns absolute path for valid input', () => {
      const notePath = path.join(config.path, 'notes', 'readme.md');
      fs.mkdirSync(path.dirname(notePath), { recursive: true });
      fs.writeFileSync(notePath, '# Hello');

      try {
        const result = security.guardRead('notes/readme.md');
        expect(result).toBe(notePath);
      } finally {
        fs.unlinkSync(notePath);
      }
    });

    it('throws on traversal attempt', () => {
      expect(() => security.guardRead('../../../etc/passwd')).toThrow(SecurityError);
    });

    it('throws on excessive file size', () => {
      const cfg = makeConfig({ maxFileSize: 10 });
      const sec = new VaultSecurity(cfg);
      const bigPath = path.join(cfg.path, 'big.md');
      fs.writeFileSync(bigPath, 'x'.repeat(100));

      try {
        expect(() => sec.guardRead('big.md')).toThrow(SecurityError);
      } finally {
        fs.unlinkSync(bigPath);
      }
    });
  });

  describe('guardWrite full chain', () => {
    it('returns absolute path for valid input', () => {
      const result = security.guardWrite('new-note.md');
      expect(result).toBe(path.join(config.path, 'new-note.md'));
    });

    it('blocks write to denied path', () => {
      expect(() => security.guardWrite('.git/config')).toThrow(SecurityError);
    });
  });
});
