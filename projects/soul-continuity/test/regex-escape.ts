/** Escapa una cadena literal para incrustarla en una expresión regular (incluye la barra invertida). */
export function escapeRegExp(s: string): string {
  return s.replace(/[\\^$.*+?()[\]{}|/]/g, "\\$&");
}
