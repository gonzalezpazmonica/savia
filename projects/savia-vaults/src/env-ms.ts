/** Milisegundos desde una variable de entorno: solo números finitos ≥ 0; si no, undefined (vale el valor por defecto). */
export function envMs(raw: string | undefined): number | undefined {
  if (raw === undefined || raw.trim() === '') return undefined;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : undefined;
}
