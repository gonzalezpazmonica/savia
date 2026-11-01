// Validación de una receta contra una GRABACIÓN (HAR) del tráfico real del
// operador, hecha en su perfil de Soul y guardada fuera de cualquier repo.
// Reproduce cada petición grabada por la misma decisión pura del cortafuegos
// (`decidirHttp`) y exige que la receta distinga lectura de escritura en ese
// cliente. Si pasa, `cli-grabacion.ts` emite el recibo que activa una receta
// experimental (activacion.ts).
//
// El informe es seguro de enseñar: rutas enmascaradas, sin valores de
// consulta, sin cuerpos y sin identificadores largos. La grabación sí lleva
// datos N4: el procedimiento (README) dice dónde guardarla y cuándo borrarla.

import { decidirHttp, type PeticionHttp } from "../cortafuegos/decision.ts";
import { casa } from "../receta/patrones.ts";
import type { Receta } from "../receta/tipos.ts";

export interface InformeGrabacion {
  receta: string;
  peticiones: number;
  permitidas: number;
  cortadas: Record<string, number>;
  operaciones: { url: string; op: string; clase: "lectura" | "escritura_conocida" | "desconocida"; veces: number }[];
  fallos: string[];
  avisos: string[];
  /** Muestra de peticiones cortadas, enmascaradas (para ampliar la receta a mano). */
  muestras_cortadas: string[];
  pasa: boolean;
}

/** Nombres de operación que delatan una escritura aunque la receta los llame lectura. */
const VERBOS = "update|set|mark|create|delete|remove|send|move|patch|add|edit|save|upsert|archive|flag|dismiss|accept|decline|approve|reject|ack|marcar|actualizar|enviar|borrar|crear|mover|aprobar";
const ESCRITURA = new RegExp(`(^|[^a-z])(${VERBOS})`, "i");
const VERBO = new RegExp(`^(${VERBOS})$`, "i");

/** ¿El nombre delata una escritura? Al inicio o tras un separador (`mark_read`),
 *  o como palabra entera dentro de un camelCase (`GetAndUpdateItem`, `itemMarkRead`).
 *  Palabra entera para no confundir `GetSettings` con `set`. Heurística secundaria. */
export function pareceEscritura(op: string): boolean {
  if (ESCRITURA.test(op)) return true;
  return op.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/([A-Z])([A-Z][a-z])/g, "$1 $2").split(/[^A-Za-z]+/).some((w) => VERBO.test(w));
}

/** Origen + ruta con segmentos largos ocultos + solo las claves de la consulta. */
export function enmascarar(url: string): string {
  let u: URL;
  try { u = new URL(url); } catch { return "<url inválida>"; }
  const ruta = u.pathname.split("/").map((s) => (s.length > 24 || /@/.test(s) || (/\d/.test(s) && s.length > 16) ? "…" : s)).join("/");
  const claves = [...u.searchParams.keys()];
  return u.origin + ruta + (claves.length ? "?" + claves.map((k) => `${k}=…`).join("&") : "");
}

interface EntradaHar {
  request?: { method?: unknown; url?: unknown; headers?: unknown; postData?: { text?: unknown } };
  response?: { status?: unknown };
  _resourceType?: unknown;
}

function peticionDe(e: EntradaHar): PeticionHttp | null {
  const q = e.request;
  if (!q || typeof q.method !== "string" || typeof q.url !== "string") return null;
  const cabeceras: Record<string, string> = {};
  if (Array.isArray(q.headers)) {
    for (const h of q.headers as { name?: unknown; value?: unknown }[]) {
      if (typeof h?.name === "string" && typeof h.value === "string") cabeceras[h.name.toLowerCase()] = h.value;
    }
  }
  const tipo = typeof e._resourceType === "string" ? e._resourceType : "";
  const navegacion = tipo ? tipo === "document" : q.method === "GET" && (cabeceras.accept ?? "").includes("text/html");
  const cuerpo = typeof q.postData?.text === "string" ? q.postData.text : null;
  return { url: q.url, metodo: q.method, cabeceras, cuerpo, navegacion };
}

export function validarGrabacion(r: Receta, har: unknown): InformeGrabacion {
  const inf: InformeGrabacion = {
    receta: r.id, peticiones: 0, permitidas: 0, cortadas: {}, operaciones: [], fallos: [], avisos: [], muestras_cortadas: [], pasa: false,
  };
  const entradas = (har as { log?: { entries?: unknown } } | null)?.log?.entries;
  if (!Array.isArray(entradas) || entradas.length === 0) {
    inf.fallos.push("la grabación no es un HAR con entradas");
    return inf;
  }
  const ops = new Map<string, InformeGrabacion["operaciones"][number]>();
  const anotarOp = (url: string, op: string, clase: InformeGrabacion["operaciones"][number]["clase"]) => {
    const k = `${url}|${op}`;
    const x = ops.get(k) ?? { url, op, clase, veces: 0 };
    x.veces++;
    ops.set(k, x);
  };
  const cubiertas = new Set<string>();
  for (const e of entradas as EntradaHar[]) {
    const p = peticionDe(e);
    if (!p) { inf.fallos.push("entrada del HAR sin método o URL"); continue; }
    inf.peticiones++;
    const d = decidirHttp(r, { accion: null }, p);
    const sitio = enmascarar(p.url);
    if (d.permitir) {
      inf.permitidas++;
      if (p.navegacion && e.response?.status === 200) {
        for (const pg of r.paginas) if (casa(p.url, r.origen, [pg])) cubiertas.add(pg);
      }
    } else {
      inf.cortadas[d.motivo] = (inf.cortadas[d.motivo] ?? 0) + 1;
      if (inf.muestras_cortadas.length < 20 && !inf.muestras_cortadas.includes(`${p.metodo} ${sitio}`)) {
        inf.muestras_cortadas.push(`${p.metodo} ${sitio}`);
      }
    }
    if (p.metodo.toUpperCase() !== "POST" || d.motivo === "renovacion") continue;
    const decl = r.post_lectura.filter((o) => casa(p.url, r.origen, [o.url]));
    if (decl.length === 0) continue;
    if (d.motivo === "operacion_desconocida" && !d.op) {
      inf.fallos.push(`no se distingue la operación de un POST a ${sitio}: con esas señales no se separa lectura de escritura y la receta no se puede publicar`);
      continue;
    }
    if (!d.op) continue;
    if (d.motivo === "graphql_no_consulta") {
      inf.fallos.push(`${d.op} en ${sitio} se declara lectura pero su documento no es solo consulta (mutation/subscription)`);
      anotarOp(sitio, d.op, "lectura");
    } else if (d.motivo === "operacion_desconocida") {
      inf.fallos.push(`operación desconocida ${d.op} en ${sitio}: clasifícala como lectura o escritura_conocida`);
      anotarOp(sitio, d.op, "desconocida");
    } else {
      anotarOp(sitio, d.op, d.motivo === "escritura_conocida" ? "escritura_conocida" : "lectura");
    }
  }
  for (const o of r.post_lectura) {
    for (const op of o.lectura) {
      if (pareceEscritura(op)) inf.fallos.push(`${op} figura como lectura pero su nombre es de escritura`);
      if (![...ops.values()].some((x) => x.op === op)) inf.avisos.push(`la lectura ${op} no aparece en la grabación`);
    }
  }
  for (const pg of r.paginas) if (!cubiertas.has(pg)) inf.fallos.push(`la grabación no cubre la página ${pg} (navegación con 200)`);
  const datosCortados = inf.cortadas.fuera_de_lista ?? 0;
  if (datosCortados > 0) inf.avisos.push(`${datosCortados} peticiones fuera de la lista se cortarían; si la vista las necesita, la prueba de humo fallará`);
  inf.operaciones = [...ops.values()].sort((a, b) => a.op.localeCompare(b.op));
  inf.fallos = [...new Set(inf.fallos)];
  inf.pasa = inf.fallos.length === 0;
  return inf;
}
