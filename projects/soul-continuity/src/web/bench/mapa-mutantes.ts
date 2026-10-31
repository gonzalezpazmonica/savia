// Qué comprobaciones prueban la defensa que quita cada mutante. Un mutante solo
// está MUERTO si falla alguna de SUS comprobaciones: un fallo ajeno (un Chrome
// inestable, otro escenario) no demuestra que su defensa esté probada.

import { MUTANTES, type Mutante } from "../cortafuegos/decision.ts";

const OPERACIONES = /:(mutaciones_servidor|peticiones_no_get_fuera_de_lista|operaciones_post_fuera_de_lista)$/;
const EXTERNO = /^contenido_hostil:[^:]+:(mutaciones_servidor|peticiones_a_externo)$/;

export const MAPA: Record<Exclude<Mutante, "ninguno">, RegExp> = {
  redireccion_directa: /^(sesion_caducada|redireccion):/,
  escritura_permitida: OPERACIONES,
  metodo_laxo: OPERACIONES,
  subrecurso_libre: OPERACIONES,
  graphql_sin_documento: /^graphql_disfrazada:/,
  ws_libre: /:envios_websocket_fuera_de_mantenimiento$/,
  ws_sin_lista: EXTERNO,
  patron_prefijo: /^(accion_secuestrada|contenido_hostil):/,
  sin_accion: /^accion_secuestrada:/,
  sin_descargas: /^descarga_(disfrazada|atributo):/,
  sin_login: /^(sesion_caducada|sesion_sso):/,
  sin_desactivar: /^(operacion_nueva|cambio_dom|operacion_en_url):[^:]+:(estado|aviso|persistente|desactivada)$/,
  perfil_personal: /^perfil_personal:/,
  sin_guardia: /^(sesion_caducada|redireccion):|:peticiones_sin_pasar_por_cortafuegos$/,
  workers_libres: /^ws_worker:/,
  sin_login_externo: /^sesion_sso:/,
  absoluto_navegable: EXTERNO,
  extraccion_mundo_principal: /^contenido_hostil:/,
  vigilancia_con_js: /^vigilancia[a-z_]*:[^:]+:sin_javascript$/,
  experimental_sin_recibo: /^experimental:/,
  post_lectura_por_get: /^operacion_en_url:/,
  operacion_url_sin_cotejar: /^operacion_en_url:/,
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
