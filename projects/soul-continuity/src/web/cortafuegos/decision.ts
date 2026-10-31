// Decisión pura del cortafuegos: dada una receta y una petición, ¿pasa?
// Sin navegador, para poder probarla en aislamiento. Todo lo no previsto se
// aborta (fail-closed).

import { casa, casaLogin } from "../receta/patrones.ts";
import type { AccionNavegacion, OperacionesPost, Receta } from "../receta/tipos.ts";

/** Mutantes del banco: cada uno quita UNA defensa. `ninguno` es el cortafuegos real. */
export const MUTANTES = [
  "redireccion_directa", "metodo_laxo", "escritura_permitida", "graphql_sin_documento",
  "ws_libre", "ws_sin_lista", "patron_prefijo", "sin_accion", "sin_descargas",
  "sin_desactivar", "sin_login", "perfil_personal", "subrecurso_libre",
  "sin_guardia", "workers_libres",
  // Defensas añadidas en el producto (no estaban en Labs):
  "sin_login_externo", "absoluto_navegable", "extraccion_mundo_principal", "vigilancia_con_js",
  "experimental_sin_recibo", "post_lectura_por_get", "operacion_url_sin_cotejar",
] as const;
export type Mutante = "ninguno" | (typeof MUTANTES)[number];

export interface PeticionHttp {
  url: string;
  metodo: string;
  cabeceras: Record<string, string>;
  cuerpo: string | null;
  navegacion: boolean;
}

export type Motivo =
  | "lista" | "renovacion" | "post_lectura"
  | "fuera_de_lista" | "login" | "accion_no_ligada" | "metodo" | "escritura_conocida"
  | "operacion_desconocida" | "graphql_no_consulta" | "esquema" | "otro_origen" | "operacion_url_distinta";

export interface Decision {
  permitir: boolean;
  motivo: Motivo;
  op?: string | null;
  /** La receta deja de ser fiable: el cliente usa una operación que no conoce. */
  desactivar?: boolean;
  /** La página pide iniciar sesión: parada limpia. */
  sesion?: boolean;
}

/** ¿El documento GraphQL contiene solo operaciones `query`? Fail-closed si está vacío. */
export function soloConsultas(doc: string): boolean {
  const limpio = doc
    .replace(/"""[\s\S]*?"""/g, '""')
    .replace(/"(?:[^"\\]|\\.)*"/g, '""')
    .replace(/#[^\n]*/g, "");
  if (!limpio.trim()) return false;
  let prof = 0;
  const fichas = limpio.match(/[{}]|[_A-Za-z][_0-9A-Za-z]*/g) ?? [];
  let operaciones = 0;
  for (const f of fichas) {
    if (f === "{") { if (prof === 0) operaciones++; prof++; continue; }
    if (f === "}") { prof--; continue; }
    if (prof === 0 && (f === "mutation" || f === "subscription")) return false;
  }
  return operaciones > 0 && prof === 0;
}

function leerRuta(obj: unknown, ruta: string): unknown {
  let x: unknown = obj;
  for (const k of ruta.split(".")) {
    if (!x || typeof x !== "object" || Array.isArray(x)) return undefined;
    x = (x as Record<string, unknown>)[k];
  }
  return x;
}

/** Extrae la operación declarada por el cliente según la receta. `null` = no se puede saber. */
export function operacionDe(o: OperacionesPost, p: PeticionHttp): { op: string | null; json: unknown } {
  const f = o.operacion;
  if ("cabecera" in f) {
    const v = p.cabeceras[f.cabecera.toLowerCase()];
    return { op: typeof v === "string" && v.length > 0 && !v.includes(",") ? v : null, json: null };
  }
  let json: unknown;
  try {
    json = JSON.parse(p.cuerpo ?? "");
  } catch {
    return { op: null, json: null };
  }
  if (!json || typeof json !== "object" || Array.isArray(json)) return { op: null, json: null };
  const v = leerRuta(json, f.cuerpo_json);
  return { op: typeof v === "string" && v.length > 0 ? v : null, json };
}

/** ¿La consulta repite la operación con otro valor? El servidor podría ejecutar
 *  la de la URL y no la declarada: se coteja el parámetro con el mismo nombre
 *  que la cabecera (o que la última clave de `cuerpo_json`). */
export function operacionEnConsultaCasa(o: OperacionesPost, u: URL, op: string): boolean {
  const f = o.operacion;
  const nombre = ("cabecera" in f ? f.cabecera : f.cuerpo_json.split(".").at(-1) ?? "").toLowerCase();
  for (const [k, v] of u.searchParams) {
    if (k.toLowerCase() === nombre && v !== op) return false;
  }
  return true;
}

export interface EstadoCortafuegos {
  accion: AccionNavegacion | null;
}

export function decidirHttp(r: Receta, est: EstadoCortafuegos, p: PeticionHttp, mutante: Mutante = "ninguno"): Decision {
  let u: URL;
  try {
    u = new URL(p.url);
  } catch {
    return { permitir: false, motivo: "esquema" };
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return { permitir: false, motivo: "esquema" };
  if (mutante === "subrecurso_libre" && !p.navegacion) return { permitir: true, motivo: "lista" };

  const prefijo = mutante === "patron_prefijo";
  if (mutante !== "sin_login" &&
    casaLogin(p.url, r.origen, r.sesion.login, prefijo, mutante === "sin_login_externo")) {
    return { permitir: false, motivo: "login", sesion: true };
  }
  const metodo = p.metodo.toUpperCase();
  if (metodo === "POST" && casa(p.url, r.origen, r.renovacion_sesion)) {
    return { permitir: true, motivo: "renovacion" };
  }
  if (!casa(p.url, r.origen, r.urls, prefijo)) return { permitir: false, motivo: "fuera_de_lista" };
  // Los patrones absolutos (otro origen) son solo para subrecursos: la página nunca sale del origen.
  if (p.navegacion && u.origin !== new URL(r.origen).origin && mutante !== "absoluto_navegable") {
    return { permitir: false, motivo: "otro_origen" };
  }
  if (est.accion && p.navegacion && mutante !== "sin_accion" && !casa(p.url, r.origen, est.accion.urls, prefijo)) {
    return { permitir: false, motivo: "accion_no_ligada" };
  }
  const ops = r.post_lectura.filter((o) => casa(p.url, r.origen, [o.url]));
  // Un endpoint de operaciones solo se usa por POST: por GET la operación no se
  // clasificaría (iría en la URL, sin cabecera ni cuerpo que mirar).
  if (ops.length && metodo !== "POST" && mutante !== "post_lectura_por_get" && mutante !== "metodo_laxo") {
    return { permitir: false, motivo: "metodo" };
  }
  if (metodo === "GET" || metodo === "HEAD" || mutante === "metodo_laxo") return { permitir: true, motivo: "lista" };
  if (metodo !== "POST") return { permitir: false, motivo: "metodo" };

  if (ops.length === 0) return { permitir: false, motivo: "metodo" };
  for (const o of ops) {
    const { op, json } = operacionDe(o, p);
    if (op === null) continue;
    if (mutante !== "operacion_url_sin_cotejar" && !operacionEnConsultaCasa(o, u, op)) {
      return { permitir: false, motivo: "operacion_url_distinta", op, desactivar: true };
    }
    if (o.lectura.includes(op)) {
      const f = o.operacion;
      if ("cuerpo_json" in f && f.graphql && mutante !== "graphql_sin_documento") {
        const doc = leerRuta(json, "query");
        if (typeof doc !== "string" || !soloConsultas(doc)) {
          return { permitir: false, motivo: "graphql_no_consulta", op, desactivar: true };
        }
      }
      return { permitir: true, motivo: "post_lectura", op };
    }
    if (o.escritura_conocida.includes(op)) {
      if (mutante === "escritura_permitida") return { permitir: true, motivo: "post_lectura", op };
      return { permitir: false, motivo: "escritura_conocida", op };
    }
    return { permitir: false, motivo: "operacion_desconocida", op, desactivar: true };
  }
  return { permitir: false, motivo: "operacion_desconocida", op: null, desactivar: true };
}

/** Envío por WebSocket: solo los mensajes exactos de mantenimiento de la receta. */
export function decidirEnvioWs(r: Receta, mensaje: string, mutante: Mutante = "ninguno"): boolean {
  if (mutante === "ws_libre") return true;
  return r.websocket.mantenimiento.includes(mensaje);
}
