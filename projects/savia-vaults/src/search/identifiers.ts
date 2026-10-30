// SE-485 R4 — identificadores con forma de código (CT-2026-047, E-1047) y su presencia literal.

/** `[A-Z]{1,5}-\d[\d-]*`, delimitado para no cortar palabras ni identificadores más largos. */
const ID_RE = /(?<![A-Za-z0-9-])[A-Z]{1,5}-\d[\d-]*(?![A-Za-z0-9])/g;

/** Aviso estable que acompaña a los resultados cuando el identificador consultado no existe. */
export const IDENTIFIER_NOT_FOUND = 'identificador no encontrado literalmente';

/** Identificadores de una consulta, sin guion final y sin repetidos. */
export function queryIdentifiers(query: string): string[] {
  const found = (query.match(ID_RE) ?? []).map(id => id.replace(/-+$/, ''));
  return [...new Set(found)];
}

/** ¿El texto contiene `id` literal (sin ser prefijo de otro identificador, p. ej. CT-2026-04 en CT-2026-047)? */
export function containsIdentifier(text: string, id: string): boolean {
  const esc = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(?<![A-Za-z0-9-])${esc}(?![A-Za-z0-9]|-\\d)`, 'i').test(text);
}

