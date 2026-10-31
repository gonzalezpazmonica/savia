// Adaptador `web` del contrato compartido (src/contract/adapter.ts).
// Traduce lo que devuelven el ejecutor de recetas y la vigilancia de páginas a
// afirmaciones `web:*` y a un estado de adaptador (CONTRATO.md §1–§3).
//
// - No usa `ctx.transport` ni `ctx.credentials`: navega con el navegador
//   instalado en el perfil dedicado de Soul, donde el operador inició sesión.
//   Soul no guarda ni pide credenciales web.
// - Fail-closed: si una receta o página falla, el adaptador entero informa el
//   fallo y no aporta afirmaciones.

import { claimKey, cleanText, iso, parseTs, type Claim, type ClaimType } from "../../contract/claims.ts";
import type { AdapterContext, AdapterResult, AdapterStatus, SourceAdapter } from "../../contract/adapter.ts";
import { comprobarActivacion } from "./activacion.ts";
import { AlmacenRecetas, ejecutarReceta, type Campo, type Opciones, type Resultado } from "./ejecutor.ts";
import { AlmacenHuellas, vigilarPagina, type OpcionesVigilancia, type ResultadoVigilancia, type Vigilada } from "./vigilancia.ts";
import type { Receta } from "../receta/tipos.ts";
import { validarReceta } from "../receta/validar.ts";

/** Parámetros del adaptador en la configuración de la fuente (`params`). */
export interface ParametrosWeb {
  /** Chrome o Edge instalado (`buscarNavegador`). */
  ejecutable: string;
  /** Perfil dedicado de Soul (`prepararPerfilSoul`). Obligatorio en producto. */
  perfil: string;
  recetas?: Receta[];
  vigiladas?: Vigilada[];
  /** Recibos locales de validación de recetas experimentales. */
  validaciones?: string;
  /** Fichero de recetas desactivadas por la prueba de humo. */
  desactivadas?: string;
  /** Fichero de huellas de páginas vigiladas (obligatorio si hay vigiladas). */
  huellas?: string;
}

export interface Dependencias {
  ejecutar: (o: Opciones) => Promise<Resultado>;
  vigilar: (o: OpcionesVigilancia) => Promise<ResultadoVigilancia>;
}

/** Vida de una afirmación web: la misma que el resto de adaptadores del banco. */
const VIDA_MS = 3600_000;
/** Campos que dan título, en orden de preferencia. */
const CAMPOS_TITULO = ["titulo", "asunto", "nombre", "concepto", "resumen"];
/** Campos que dan vencimiento (`AAAA-MM-DD`), en orden de preferencia. */
const CAMPOS_VENCE = ["vence", "limite", "fecha"];

/** Parte de la referencia sin `:`, espacios ni `~` (separador sitio~id). */
const parte = (s: string) => encodeURIComponent(s).replace(/~/g, "%7E");

function primero(campos: Record<string, Campo>, nombres: string[]): string | null {
  for (const n of nombres) { const v = campos[n]; if (typeof v === "string" && v) return v; }
  return null;
}

function vencimiento(campos: Record<string, Campo>): string | null {
  const v = primero(campos, CAMPOS_VENCE);
  return v && /^\d{4}-\d{2}-\d{2}$/.test(v) && parseTs(`${v}T00:00:00Z`) !== null ? `${v}T00:00:00Z` : null;
}

function afirmacion(ctx: AdapterContext, tipo: ClaimType, sitio: string, id: string, link: string,
  over: Pick<Claim, "open" | "awaiting_operator"> & Partial<Claim>): Claim {
  const ahora = parseTs(ctx.now) as number;
  const ref = `${parte(sitio)}~${parte(id)}`;
  const title = cleanText(over.title);
  return {
    key: claimKey("web", tipo, ref),
    claim_type: tipo,
    state: "OBSERVED",
    source_refs: [{ adapter: "web", route: "web", ref, link }],
    sensitivity: ctx.sensitivity,
    observed_at: iso(ahora),
    valid_until: iso(ahora + VIDA_MS),
    event_at: over.event_at ?? null,
    due_at: over.due_at ?? null,
    title,
    ...(title ? { untrusted_text: true } : {}),
    open: over.open,
    awaiting_operator: over.awaiting_operator,
    attrs: over.attrs ?? {},
  };
}

/** Elementos de una receta → afirmaciones. Q1/Q2 son tareas (`task_assigned`;
 *  Q2 = espera al operador); lo que solo entra en Q4 es `dated_commitment`.
 *  Lo que no entra en ninguna pregunta no se afirma. */
export function afirmacionesDeReceta(ctx: AdapterContext, r: Receta, res: Resultado): Claim[] {
  const q1 = new Set(res.preguntas.q1), q2 = new Set(res.preguntas.q2), q4 = new Set(res.preguntas.q4);
  const out: Claim[] = [];
  for (const e of res.elementos) {
    const comun = { title: primero(e.campos, CAMPOS_TITULO), due_at: vencimiento(e.campos), attrs: { receta: r.id, sender_auth: "unknown" } };
    if (q1.has(e.id) || q2.has(e.id)) {
      out.push(afirmacion(ctx, "task_assigned", r.id, e.id, e.url, { ...comun, open: true, awaiting_operator: q2.has(e.id) }));
    } else if (q4.has(e.id)) {
      out.push(afirmacion(ctx, "dated_commitment", r.id, e.id, e.url, { ...comun, open: true, awaiting_operator: false }));
    }
  }
  return out;
}

type Fallo = { status: Exclude<AdapterStatus, "ok">; message: string };
/** Si fallan varias cosas, manda la sesión caducada (el operador puede actuar). */
const GRAVEDAD: Fallo["status"][] = ["session_expired", "error", "recipe_disabled"];

function peor(fallos: Fallo[]): Fallo {
  const status = [...fallos].sort((a, b) => GRAVEDAD.indexOf(a.status) - GRAVEDAD.indexOf(b.status))[0].status;
  return { status, message: fallos.filter((x) => x.status === status).map((x) => x.message).join(" ") };
}

function falloDe(r: Resultado): Fallo | null {
  switch (r.estado) {
    case "OK": return null;
    case "SESION_CADUCADA": return { status: "session_expired", message: r.aviso ?? `Sesión caducada en ${r.receta}.` };
    case "DESACTIVADA": return { status: "recipe_disabled", message: r.aviso ?? `Receta ${r.receta} desactivada.` };
    default: return { status: "error", message: r.aviso ?? `La receta ${r.receta} falló.` };
  }
}

function falloDeVigilancia(v: Vigilada, r: ResultadoVigilancia): Fallo | null {
  if (r.estado === "REDIRIGIDA") return { status: "session_expired", message: r.aviso ?? `Sesión caducada en ${v.sitio}.` };
  if (r.estado === "ERROR") return { status: "error", message: r.aviso ?? `No se pudo leer ${v.sitio}.` };
  return null;
}

const primeraLinea = (e: unknown) => (e as Error).message.split("\n")[0];

function leerParametros(p: Record<string, unknown>): ParametrosWeb | string {
  if (typeof p.ejecutable !== "string" || !p.ejecutable) return "falta el navegador instalado (params.ejecutable)";
  if (typeof p.perfil !== "string" || !p.perfil) return "falta el perfil dedicado de Soul (params.perfil)";
  for (const k of ["recetas", "vigiladas"] as const) {
    if (p[k] !== undefined && !Array.isArray(p[k])) return `params.${k} debe ser una lista`;
  }
  // Las recetas pasan siempre por el validador: una inválida no llega al navegador.
  for (const r of (p.recetas ?? []) as unknown[]) {
    try { validarReceta(r as Receta); } catch (e) { return `receta inválida (${primeraLinea(e)})`; }
  }
  if (Array.isArray(p.vigiladas) && p.vigiladas.length && typeof p.huellas !== "string") {
    return "páginas vigiladas sin fichero de huellas (params.huellas)";
  }
  return p as unknown as ParametrosWeb;
}

export function crearAdaptadorWeb(dep: Dependencias = { ejecutar: ejecutarReceta, vigilar: vigilarPagina }): SourceAdapter {
  return {
    name: "web",
    routes: ["web"],
    purpose: "Webs sin API, solo lectura con recetas y cortafuegos",
    async read(ctx: AdapterContext): Promise<AdapterResult> {
      const fallo = (f: Fallo): AdapterResult => ({ ...f, route: "web", fallback: "manual" });
      if (ctx.route !== "web") return fallo({ status: "error", message: `El adaptador web no tiene la ruta ${ctx.route}.` });
      const p = leerParametros(ctx.params);
      if (typeof p === "string") return fallo({ status: "not_configured", message: `Ruta web sin configurar: ${p}.` });
      const yo = ctx.operator.identities.emails[0];
      if (!yo) return fallo({ status: "not_configured", message: "El perfil del operador no tiene identidad de correo." });

      // Las experimentales sin recibo no son un fallo: simplemente no se ejecutan.
      const activas = (p.recetas ?? []).filter((r) => comprobarActivacion(r, p.validaciones).activa);
      const vigiladas = p.vigiladas ?? [];
      if (!activas.length && !vigiladas.length) {
        return fallo({ status: "recipe_disabled",
          message: "No hay recetas activas ni páginas vigiladas. Las recetas experimentales necesitan un recibo de validación local." });
      }
      const fallos: Fallo[] = [];
      const claims: Claim[] = [];
      const almacen = p.desactivadas ? new AlmacenRecetas(p.desactivadas) : undefined;
      for (const r of activas) {
        try {
          const res = await dep.ejecutar({ receta: r, yo, ejecutable: p.ejecutable, perfil: p.perfil, validaciones: p.validaciones, almacen });
          const f = falloDe(res);
          if (f) fallos.push(f); else claims.push(...afirmacionesDeReceta(ctx, r, res));
        } catch (e) {
          fallos.push({ status: "error", message: `La receta ${r.id} falló (${primeraLinea(e)}).` });
        }
      }
      const huellas = new AlmacenHuellas(p.huellas ?? "");
      // Las huellas se confirman solo si el adaptador entrega: si se descartan las
      // afirmaciones (fail-closed), el cambio tiene que volver a verse.
      const pendientes: { v: Vigilada; huella: string }[] = [];
      for (const v of vigiladas) {
        try {
          const res = await dep.vigilar({ vigilada: v, ejecutable: p.ejecutable, perfil: p.perfil, almacen: huellas, diferirHuella: true });
          const f = falloDeVigilancia(v, res);
          if (f) { fallos.push(f); continue; }
          if (res.huella) pendientes.push({ v, huella: res.huella });
          if (res.estado === "CAMBIADA") {
            claims.push(afirmacion(ctx, "web_page_change", v.sitio, v.id, v.url,
              { open: false, awaiting_operator: false, event_at: iso(parseTs(ctx.now) as number), attrs: { sender_auth: "unknown" } }));
          }
        } catch (e) {
          fallos.push({ status: "error", message: `La vigilancia ${v.id} falló (${primeraLinea(e)}).` });
        }
      }
      if (fallos.length) return fallo(peor(fallos));
      for (const x of pendientes) huellas.guardar(x.v.id, x.v.url, x.huella);
      return { status: "ok", route: "web", claims };
    },
  };
}
