import { createHash } from 'node:crypto';

// JSON canónico: claves ordenadas, sin espacios; base de todos los hashes congelados.
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  const obj = value as Record<string, unknown>;
  return `{${Object.keys(obj).sort().filter(k => obj[k] !== undefined).map(k => `${JSON.stringify(k)}:${canonicalJson(obj[k])}`).join(',')}}`;
}

export function sha256(text: string): string { return createHash('sha256').update(text).digest('hex'); }
export function sha256Json(value: unknown): string { return sha256(canonicalJson(value)); }
