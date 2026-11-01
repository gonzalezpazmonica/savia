// Puerta de las recetas `experimental`: no se ejecutan sin un recibo local de
// validación contra una grabación del tráfico real del propio operador
// (grabacion.ts). El recibo vive en el directorio de datos, fuera de cualquier
// repo, y queda ligado al contenido exacto de la receta: si la receta cambia,
// el recibo deja de valer.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Receta } from "../receta/tipos.ts";

export interface Recibo {
  formato: "soul-recibo-web/1";
  receta: string;
  huella_receta: string;
  validado_en: string;
  resultado: "PASA";
  resumen: { peticiones: number; permitidas: number; operaciones_lectura: number };
}

/** JSON con las claves ordenadas: la huella no depende del orden en que se
 *  escribió la receta (la CLI la lee del fichero; el adaptador, de su configuración). */
function canonico(x: unknown): string {
  if (Array.isArray(x)) return `[${x.map(canonico).join(",")}]`;
  if (x && typeof x === "object") {
    const o = x as Record<string, unknown>;
    return `{${Object.keys(o).filter((k) => o[k] !== undefined).sort()
      .map((k) => `${JSON.stringify(k)}:${canonico(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(x) ?? "null";
}

/** Huella del contenido de la receta ya completada (variables sustituidas). */
export function huellaReceta(r: Receta): string {
  return createHash("sha256").update(canonico(r)).digest("hex");
}

export function rutaRecibo(dir: string, id: string) {
  // El id forma parte de la ruta: nada de `../` ni separadores.
  if (!/^[a-z0-9-]+$/.test(id)) throw new Error(`id de receta inválido para un recibo: ${id}`);
  return join(dir, `${id}.json`);
}

/** Directorio de recibos de la CLI. El adaptador no lo supone: usa `params.validaciones`. */
export function dirValidacionesPorDefecto(datos: string): string {
  return join(datos, "web", "validaciones");
}

/** ¿Origen del banco sintético (bucle local)? Solo ahí vale `estable` sin recibo. */
export function origenLocal(origen: string): boolean {
  let h: string;
  try { h = new URL(origen).hostname; } catch { return false; }
  return h === "localhost" || h === "[::1]" || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(h);
}

export function guardarRecibo(dir: string, r: Receta, resumen: Recibo["resumen"]): string {
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const recibo: Recibo = {
    formato: "soul-recibo-web/1", receta: r.id, huella_receta: huellaReceta(r),
    validado_en: new Date().toISOString(), resultado: "PASA", resumen,
  };
  const ruta = rutaRecibo(dir, r.id);
  writeFileSync(ruta, JSON.stringify(recibo, null, 2) + "\n", { mode: 0o600 });
  return ruta;
}

/** ¿Puede ejecutarse? Sin recibo, solo las `estable` del banco sintético (origen
 *  local): el campo `estado` lo escribe la propia receta, así que una receta de
 *  un sitio real que se declare `estable` necesita recibo igual que una
 *  `experimental`. Las demás, solo con recibo válido para ESTA receta.
 *  Fail-closed: sin directorio, id inválido o recibo ilegible, no. */
export function comprobarActivacion(r: Receta, dirValidaciones: string | undefined): { activa: boolean; aviso: string | null } {
  if (r.estado === "estable" && origenLocal(r.origen)) return { activa: true, aviso: null };
  const clase = r.estado === "estable" ? "se declara estable, pero es de un sitio real," : "es experimental";
  const no = (porque: string) => ({
    activa: false,
    aviso: `La receta de ${r.sitio} ${clase} y ${porque}: graba tu tráfico en el perfil de Soul y valídala ` +
      `(validar-grabacion) antes de activarla. No se ha abierto el navegador.`,
  });
  if (!dirValidaciones) return no("no hay directorio de validaciones");
  let ruta: string;
  try { ruta = rutaRecibo(dirValidaciones, r.id); } catch { return no("su id no es válido"); }
  if (!existsSync(ruta)) return no("no está validada en esta instalación");
  let recibo: Partial<Recibo>;
  try { recibo = JSON.parse(readFileSync(ruta, "utf8")); } catch { return no("su recibo de validación es ilegible"); }
  if (recibo.formato !== "soul-recibo-web/1" || recibo.receta !== r.id || recibo.resultado !== "PASA") {
    return no("su recibo de validación no es válido");
  }
  if (recibo.huella_receta !== huellaReceta(r)) return no("cambió desde que se validó");
  return { activa: true, aviso: null };
}
