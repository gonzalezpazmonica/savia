// SE-287 AC-4.5 retirado (2026-11-20): el hash de 32 bits calculado por el propio remoto no protegía nada.
import { describe, it, expect } from 'vitest';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const SRC = join(__dirname, '../../../src');

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap(f => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

describe('hash de integridad débil retirado', () => {
  it('no existe src/federation/hash-verify.ts', () => {
    expect(existsSync(join(SRC, 'federation/hash-verify.ts'))).toBe(false);
  });

  it('ningún fuente referencia hash-verify ni sus funciones', () => {
    const offenders = walk(SRC).filter(f => /\.ts$/.test(f)
      && /hash-verify|verifyContentHash|filterTamperedResults/.test(readFileSync(f, 'utf8')));
    expect(offenders).toEqual([]);
  });

  it('contentHash sigue siendo la clave de deduplicación (no se retira el campo)', () => {
    expect(readFileSync(join(SRC, 'federation/types.ts'), 'utf8')).toMatch(/contentHash/);
  });
});
