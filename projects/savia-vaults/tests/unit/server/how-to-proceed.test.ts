// how_to_proceed: una frase accionable por tipo de error, sin revelar qué hay detrás.
import { describe, expect, it } from 'vitest';
import { howToProceed } from '../../../src/server/how-to-proceed.js';
import { AuthError } from '../../../src/auth/index.js';
import { NoteNotFoundError } from '../../../src/storage/index.js';
import { SecurityError } from '../../../src/security/index.js';
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
});
