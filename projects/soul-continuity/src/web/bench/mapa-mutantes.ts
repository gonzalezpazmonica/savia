// Qué comprobaciones prueban la defensa que quita cada mutante. Un mutante solo
// está MUERTO si falla alguna de SUS comprobaciones: un fallo ajeno (un Chrome
// inestable, otro escenario) no demuestra que su defensa esté probada. Dos
// mutantes nunca comparten comprobaciones: si no, un solo fallo los mataría a ambos.

import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { MUTANTES, type Mutante } from "../cortafuegos/decision.ts";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
const FUENTES = ["adaptador", "banco", "bench", "cortafuegos", "receta", "recetas/sinteticas", "verdad"];

/** Huella del código y los datos que decide la batería. Un informe con otra huella
 *  es de otro código: no cuenta (revisión #1443, P2-3 de corrección). */
export function huellaCodigo(raiz = RAIZ): string {
  const h = createHash("sha256");
  for (const d of FUENTES) {
    for (const f of readdirSync(join(raiz, d)).filter((x) => /\.(ts|json)$/.test(x)).sort()) {
      h.update(`${d}/${f}\0`).update(readFileSync(join(raiz, d, f))).update("\0");
    }
  }
  return h.digest("hex").slice(0, 16);
}

// Cada regex casa solo comprobaciones de SU defensa (un corte con su motivo, o la
// métrica que solo esa defensa controla) y ninguna casa con las de otra: lo
// comprueba `test/mapa-mutantes.test.ts` contra los ids reales de la batería.
export const MAPA: Record<Exclude<Mutante, "ninguno">, RegExp> = {
  redireccion_directa: /^redireccion:[^:]+:corte_en_salto$/,
  escritura_permitida: /^base:correo:escritura_cortada$/,
  metodo_laxo: /^contenido_hostil:[^:]+:metodo_cortado$/,
  subrecurso_libre: /^base:correo:subrecurso_cortado$/,
  graphql_sin_documento: /^graphql_disfrazada:[^:]+:graphql_cortado$/,
  ws_libre: /:envios_websocket_fuera_de_mantenimiento$/,
  ws_sin_lista: /^contenido_hostil:[^:]+:ws_cortado$/,
  patron_prefijo: /^contenido_hostil:[^:]+:extension_cortada$/,
  sin_accion: /^accion_secuestrada:[^:]+:corte_registrado$/,
  sin_descargas: /^descarga_(disfrazada|atributo):[^:]+:descargas$/,
  sin_login: /^sesion_caducada:[^:]+:corte_login$/,
  sin_desactivar: /^(operacion_nueva|cambio_dom):[^:]+:(estado|aviso|persistente)$/,
  perfil_personal: /^perfil_personal:/,
  sin_guardia: /:peticiones_sin_pasar_por_cortafuegos$/,
  workers_libres: /^ws_worker:[^:]+:worker_bloqueado$/,
  sin_login_externo: /^sesion_sso:[^:]+:corte_login_externo$/,
  absoluto_navegable: /^contenido_hostil:[^:]+:navegacion_externa_cortada$/,
  extraccion_mundo_principal: /^contenido_hostil:[^:]+:extraccion_aislada$/,
  vigilancia_con_js: /^vigilancia[a-z_]*:[^:]+:sin_javascript$/,
  experimental_sin_recibo: /^experimental:[^:]+:sin_recibo_(desactivada|sin_peticiones)$/,
  post_lectura_por_get: /^operacion_en_url:[^:]+:get_cortado$/,
  operacion_url_sin_cotejar: /^operacion_en_url:[^:]+:(post_cortado|desactivada)$/,
};

export type EstadoMutante = "MUERTO" | "VIVO" | "SIN_INFORME" | "SIN_MAPA";

/** Fail-closed: sin informe o sin mapa, el mutante no cuenta como muerto. */
export function clasificarMutante(m: string, fallos: string[] | null): { estado: EstadoMutante; muertoPor: string[]; ajenos: number } {
  if (fallos === null) return { estado: "SIN_INFORME", muertoPor: [], ajenos: 0 };
  const re = (MAPA as Record<string, RegExp | undefined>)[m];
  if (!re || !(MUTANTES as readonly string[]).includes(m)) return { estado: "SIN_MAPA", muertoPor: [], ajenos: fallos.length };
  const suyos = fallos.filter((f) => re.test(f));
  return { estado: suyos.length ? "MUERTO" : "VIVO", muertoPor: suyos, ajenos: fallos.length - suyos.length };
}

/** Fallos de un informe, o `null` si no hay informe o es de otro código (otra huella). */
export function fallosVigentes(inf: { huella_codigo?: string; comprobaciones: { id: string; ok: boolean }[] } | null, huella: string): string[] | null {
  if (!inf || inf.huella_codigo !== huella) return null;
  return inf.comprobaciones.filter((c) => !c.ok).map((c) => c.id);
}
