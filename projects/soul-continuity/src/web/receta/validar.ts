// Validación fail-closed de recetas: una receta dudosa no se carga.

import { readFileSync } from "node:fs";
import { casa, compilarPatron, esAbsoluto, esOrigenLogin, partirAbsoluto } from "./patrones.ts";
import type { Condicion, Receta, Valor } from "./tipos.ts";

/** Segmentos que delatan un enlace de acción: nunca pueden entrar en la lista. */
export const ACCION = /(^|[/?&=_-])(approve|aprobar|reject|rechazar|logout|salir|signout|unsubscribe|baja|confirm\w*|delete|borrar|eliminar|cerrar|close|enviar|send|marcar|mark\w*|leido|read|ack)([/?&=_-]|$)/i;

export class RecetaInvalida extends Error {}

function exige(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new RecetaInvalida(msg);
}

function lista(x: unknown, msg: string, vacia = true): asserts x is string[] {
  exige(Array.isArray(x) && x.every((s) => typeof s === "string" && s.length > 0), msg);
  exige(vacia || (x as string[]).length > 0, `${msg} (vacía)`);
}

/** Esquemas admitidos en un patrón absoluto, según dónde aparece. */
type Esquemas = readonly string[];
const HTTP: Esquemas = ["http:", "https:"];
const WS: Esquemas = ["ws:", "wss:"];

function patron(p: string, donde: string, absolutos: Esquemas = []) {
  exige(!p.includes("{"), `${donde}: plantilla sin completar en ${p}`);
  try {
    compilarPatron(p);
    if (esAbsoluto(p)) {
      const { origen } = partirAbsoluto(p);
      exige(absolutos.includes(new URL(origen).protocol), `${donde}: ${p} no admite ese esquema aquí`);
    }
  } catch (e) {
    if (e instanceof RecetaInvalida) throw e;
    throw new RecetaInvalida(`${donde}: ${(e as Error).message}`);
  }
  const ruta = esAbsoluto(p) ? partirAbsoluto(p).ruta : p;
  exige(!ACCION.test(ruta), `${donde}: el patrón ${p} parece un enlace de acción`);
}

function valor(v: Valor, donde: string) {
  exige(v && typeof v === "object", `${donde}: valor sin definir`);
  exige(("attr" in v && typeof v.attr === "string") || ("sel" in v && typeof v.sel === "string"),
    `${donde}: valor sin attr ni sel`);
}

function condicion(c: Condicion, campos: Set<string>, donde: string) {
  if ("todas" in c || "alguna" in c) {
    const hijos = "todas" in c ? c.todas : c.alguna;
    exige(Array.isArray(hijos) && hijos.length > 0, `${donde}: grupo vacío`);
    hijos.forEach((h) => condicion(h, campos, donde));
    return;
  }
  exige(campos.has(c.campo), `${donde}: campo desconocido ${c.campo}`);
  const binarias = ["igual", "distinto", "contiene", "no_contiene"];
  const unarias = ["existe", "vacio", "verdadero", "falso"];
  exige(binarias.includes(c.op) || unarias.includes(c.op), `${donde}: op desconocida ${c.op}`);
  if (binarias.includes(c.op)) exige(typeof (c as { valor?: unknown }).valor === "string", `${donde}: falta valor`);
}

export function validarReceta(r: Receta): Receta {
  exige(r && r.formato === "soul-receta-web/1", "formato desconocido");
  exige(typeof r.id === "string" && /^[a-z0-9-]+$/.test(r.id), "id inválido");
  exige(typeof r.sitio === "string" && r.sitio.length > 0, "sitio vacío");
  exige(r.estado === "experimental" || r.estado === "estable", "estado debe ser experimental o estable");
  exige(r.notas === undefined || (Array.isArray(r.notas) && r.notas.every((n) => typeof n === "string")), "notas");
  exige(typeof r.origen === "string" && !r.origen.includes("{"), `plantilla sin completar en origen: ${r.origen}`);
  let origen: URL;
  try {
    origen = new URL(r.origen);
  } catch {
    throw new RecetaInvalida(`origen inválido: ${r.origen}`);
  }
  exige(["http:", "https:"].includes(origen.protocol), "origen sin http(s)");
  exige(origen.pathname === "/" && !origen.search && !origen.username, "origen con ruta o credenciales");
  exige(!r.origen.includes("*"), "origen con comodín");

  exige(typeof r.javascript === "boolean", "javascript debe declararse (true/false)");
  lista(r.urls, "urls", false);
  r.urls.forEach((p) => patron(p, "urls", HTTP));
  const enLista = (p: string, donde: string) => exige(r.urls.includes(p), `${donde}: ${p} no está en urls`);
  const visitable = (p: string, donde: string) =>
    exige(typeof p === "string" && p.startsWith("/") && !p.includes("*") && casa(r.origen + p, r.origen, r.urls),
      `${donde}: ${p} no casa con urls (o no es relativo al origen)`);

  lista(r.renovacion_sesion, "renovacion_sesion");
  r.renovacion_sesion.forEach((p) => patron(p, "renovacion_sesion"));
  lista(r.paginas, "paginas", false);
  r.paginas.forEach((p) => visitable(p, "paginas"));

  exige(Array.isArray(r.post_lectura), "post_lectura");
  for (const o of r.post_lectura) {
    enLista(o.url, "post_lectura");
    const f = o.operacion;
    exige(f && (("cabecera" in f && typeof f.cabecera === "string") || ("cuerpo_json" in f && typeof f.cuerpo_json === "string")),
      "post_lectura: falta dónde se declara la operación");
    lista(o.lectura, "post_lectura.lectura", false);
    lista(o.escritura_conocida, "post_lectura.escritura_conocida");
    const cruce = o.lectura.filter((x) => o.escritura_conocida.includes(x));
    exige(cruce.length === 0, `post_lectura: ${cruce.join(",")} es lectura y escritura a la vez`);
  }

  exige(r.websocket && Array.isArray(r.websocket.urls), "websocket");
  r.websocket.urls.forEach((p) => patron(p, "websocket.urls", WS));
  lista(r.websocket.mantenimiento, "websocket.mantenimiento");

  exige(Array.isArray(r.acciones), "acciones");
  for (const a of r.acciones) {
    exige(typeof a.id === "string" && typeof a.selector === "string" && a.selector.length > 0, "acción sin id o selector");
    lista(a.urls, `acción ${a.id}: urls`, false);
    a.urls.forEach((p) => enLista(p, `acción ${a.id}`));
    exige(Number.isInteger(a.max_repeticiones) && a.max_repeticiones >= 1 && a.max_repeticiones <= 20,
      `acción ${a.id}: max_repeticiones fuera de 1..20`);
  }

  const e = r.extraccion;
  exige(e && typeof e.elemento === "string", "extraccion.elemento");
  valor(e.id, "extraccion.id");
  exige(e.campos && typeof e.campos === "object", "extraccion.campos");
  Object.entries(e.campos).forEach(([k, v]) => valor(v, `campo ${k}`));
  const campos = new Set(Object.keys(e.campos));
  for (const [q, c] of Object.entries(r.preguntas ?? {})) {
    exige(["q1", "q2", "q4"].includes(q), `pregunta desconocida ${q}`);
    condicion(c as Condicion, campos, q);
  }
  exige(Object.keys(r.preguntas ?? {}).length > 0, "sin preguntas");

  lista(r.sesion?.login, "sesion.login", false);
  for (const p of r.sesion.login) {
    exige(!p.includes("{"), `sesion.login: plantilla sin completar en ${p}`);
    if (esOrigenLogin(p)) {
      // Login federado: un origen entero. Nunca el de la receta (todo sería «login»).
      const o = new URL(p);
      exige(!o.username && o.origin !== origen.origin, `sesion.login: ${p} no puede ser el origen de la receta`);
      exige(!r.urls.some((u) => esAbsoluto(u) && partirAbsoluto(u).origen === o.origin),
        `sesion.login: ${p} tiene URLs en la lista`);
      continue;
    }
    exige(!esAbsoluto(p), `sesion.login: ${p} absoluto con ruta; usa el origen entero`);
    try { compilarPatron(p); } catch (e) { throw new RecetaInvalida(`sesion.login: ${(e as Error).message}`); }
    exige(!r.urls.includes(p), `sesion.login: ${p} no puede estar en urls`);
  }

  exige(r.humo && r.paginas.includes(r.humo.pagina), "humo: la página no está en paginas");
  exige(Number.isInteger(r.humo.minimo) && r.humo.minimo >= 1, "humo.minimo < 1");
  lista(r.humo.campos_obligatorios, "humo.campos_obligatorios", false);
  r.humo.campos_obligatorios.forEach((c) => exige(campos.has(c), `humo: campo desconocido ${c}`));
  return r;
}

/** Completa las variables `{x}` de una plantilla (salvo `{yo}`, que es de las
 *  preguntas). Los valores son de host o de ruta: nada que pueda inyectar patrón. */
export function completarPlantilla(texto: string, variables: Record<string, string>): string {
  for (const [k, v] of Object.entries(variables)) {
    exige(/^[a-z_]+$/.test(k) && k !== "yo", `variable inválida: ${k}`);
    exige(/^[A-Za-z0-9.-]+$/.test(v), `valor inválido para {${k}}`);
  }
  return texto.replace(/\{([a-z_]+)\}/g, (m, k: string) => (k in variables ? variables[k] : m));
}

/** Carga una receta JSON. Variables sin completar en URLs = receta inválida. */
export function cargarReceta(ruta: string, opciones: { puerto?: number; variables?: Record<string, string> } = {}): Receta {
  const variables = { ...(opciones.variables ?? {}) };
  if (opciones.puerto !== undefined) variables.puerto = String(opciones.puerto);
  const r = JSON.parse(completarPlantilla(readFileSync(ruta, "utf8"), variables)) as Receta;
  return validarReceta(r);
}
