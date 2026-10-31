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

/** Huella del contenido de la receta ya completada (variables sustituidas). */
export function huellaReceta(r: Receta): string {
  return createHash("sha256").update(JSON.stringify(r)).digest("hex");
}

export function rutaRecibo(dir: string, id: string) {
  return join(dir, `${id}.json`);
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

/** ¿Puede ejecutarse? Las `estable` sí. Las `experimental`, solo con recibo
 *  válido para ESTA receta. Fail-closed: sin directorio o recibo ilegible, no. */
export function comprobarActivacion(r: Receta, dirValidaciones: string | undefined): { activa: boolean; aviso: string | null } {
  if (r.estado === "estable") return { activa: true, aviso: null };
  const no = (porque: string) => ({
    activa: false,
    aviso: `La receta de ${r.sitio} es experimental y ${porque}: graba tu tráfico en el perfil de Soul y valídala ` +
      `(validar-grabacion) antes de activarla. No se ha abierto el navegador.`,
  });
  if (!dirValidaciones) return no("no hay directorio de validaciones");
  const ruta = rutaRecibo(dirValidaciones, r.id);
  if (!existsSync(ruta)) return no("no está validada en esta instalación");
  let recibo: Partial<Recibo>;
  try { recibo = JSON.parse(readFileSync(ruta, "utf8")); } catch { return no("su recibo de validación es ilegible"); }
  if (recibo.formato !== "soul-recibo-web/1" || recibo.receta !== r.id || recibo.resultado !== "PASA") {
    return no("su recibo de validación no es válido");
  }
  if (recibo.huella_receta !== huellaReceta(r)) return no("cambió desde que se validó");
  return { activa: true, aviso: null };
}
