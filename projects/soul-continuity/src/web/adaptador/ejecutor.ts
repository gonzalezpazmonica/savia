/// <reference lib="dom" />
// (DOM: `leerLista` se ejecuta dentro de la página.)
// Ejecutor determinista de recetas (sin modelo). Lee vistas de lista,
// extrae elementos con identificador estable y los clasifica en Q1, Q2 y Q4.
// Guarda referencias y metadatos, nunca páginas completas. El texto de la
// web es dato: nada de lo extraído decide acciones ni eleva avisos.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import type { Page } from "playwright-core";
import { abrirNavegador, evaluarAislado } from "./navegador.ts";
import { comprobarActivacion } from "./activacion.ts";
import { Cortafuegos, type Registro } from "../cortafuegos/cortafuegos.ts";
import type { Mutante } from "../cortafuegos/decision.ts";
import type { canalDepuracion } from "../cortafuegos/perfil.ts";
import { casa } from "../receta/patrones.ts";
import type { Condicion, Extraccion, Receta, Valor } from "../receta/tipos.ts";

export type Campo = string | string[] | boolean;
export interface Elemento { id: string; fuente: string; url: string; observado_en: string; campos: Record<string, Campo> }
export interface Resultado {
  receta: string;
  estado: "OK" | "SESION_CADUCADA" | "DESACTIVADA" | "ERROR";
  aviso: string | null;
  elementos: Elemento[];
  preguntas: { q1: string[]; q2: string[]; q4: string[] };
  /** El adaptador web nunca produce alertas: como mucho, avisos (SE-490). */
  alertas: never[];
  registro: Registro[];
  ventanasAccion: { accion: string; desde: number; hasta: number }[];
  descargas: number;
  canal: ReturnType<typeof canalDepuracion>;
}

/** Recetas desactivadas por la prueba de humo o por operación desconocida (persiste). */
export class AlmacenRecetas {
  readonly ruta: string;
  constructor(ruta: string) { this.ruta = ruta; }
  private leer(): Record<string, { aviso: string; en: string }> {
    return existsSync(this.ruta) ? JSON.parse(readFileSync(this.ruta, "utf8")) : {};
  }
  aviso(id: string): string | null { return this.leer()[id]?.aviso ?? null; }
  desactivar(id: string, aviso: string) {
    const d = this.leer();
    d[id] = { aviso, en: new Date().toISOString() };
    writeFileSync(this.ruta, JSON.stringify(d, null, 2));
  }
}

export interface Opciones {
  receta: Receta;
  yo: string;
  ejecutable: string;
  /** Perfil dedicado persistente (`prepararPerfilSoul`): la sesión la inició el
   *  operador en él. Sin perfil, uno temporal que se borra (banco y pruebas). */
  perfil?: string;
  /** Solo el banco: la sesión simulada. El producto nunca inyecta cookies. */
  cookies?: Parameters<import("playwright-core").BrowserContext["addCookies"]>[0];
  /** Directorio de recibos de validación de recetas experimentales. */
  validaciones?: string;
  mutante?: Mutante;
  almacen?: AlmacenRecetas;
  /** HOME del operador: para rechazar su perfil personal (en el banco, un HOME canario). */
  hogar?: string;
  /** Solo para el mutante `perfil_personal`. */
  perfilPersonal?: string;
  esperaMs?: number;
}

const vacio = (r: Receta, estado: Resultado["estado"], aviso: string | null): Resultado => ({
  receta: r.id, estado, aviso, elementos: [], preguntas: { q1: [], q2: [], q4: [] }, alertas: [],
  registro: [], ventanasAccion: [], descargas: 0, canal: null,
});

interface Extraido { id: string; campos: Record<string, Campo> }

/** Se ejecuta DENTRO de la página, en un mundo aislado: solo lee atributos y
 *  texto. Autocontenida (se serializa con `toString`). */
function leerLista(e: Extraccion): Extraido[] {
  const leer = (n: Element, v: Valor) => {
    const el = "sel" in v ? n.querySelector(v.sel) : n;
    if (!el) return "";
    const crudo = "attr" in v && v.attr ? el.getAttribute(v.attr) ?? "" : el.textContent ?? "";
    return crudo.replace(/\s+/g, " ").trim();
  };
  const tipar = (s: string, v: Valor): Campo => {
    const t = v.tipo ?? "texto";
    if (t === "lista") return s.split(",").map((x) => x.trim()).filter(Boolean);
    if (t === "booleano") return s === "true";
    if (t === "fecha") return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : "";
    return s;
  };
  return Array.from(document.querySelectorAll(e.elemento)).map((n) => ({
    id: String(leer(n, e.id)),
    campos: Object.fromEntries(Object.entries(e.campos).map(([k, v]) => [k, tipar(leer(n, v), v)])),
  }));
}

async function extraer(page: Page, e: Extraccion, principal = false): Promise<Extraido[]> {
  const v = await evaluarAislado(page, `(${leerLista.toString()})(${JSON.stringify(e)})`, principal);
  if (!Array.isArray(v)) throw new Error("extracción: resultado no es una lista");
  return v as Extraido[];
}

export function cumple(c: Condicion, campos: Record<string, Campo>, yo: string): boolean {
  if ("todas" in c) return c.todas.every((h) => cumple(h, campos, yo));
  if ("alguna" in c) return c.alguna.some((h) => cumple(h, campos, yo));
  const v = campos[c.campo];
  const objetivo = "valor" in c ? c.valor.replace("{yo}", yo) : "";
  switch (c.op) {
    case "igual": return v === objetivo;
    case "distinto": return v !== objetivo;
    case "contiene": return Array.isArray(v) ? v.includes(objetivo) : typeof v === "string" && v.includes(objetivo);
    case "no_contiene": return Array.isArray(v) ? !v.includes(objetivo) : typeof v === "string" && !v.includes(objetivo);
    case "existe": return Array.isArray(v) ? v.length > 0 : typeof v === "string" ? v.length > 0 : v === true;
    case "vacio": return Array.isArray(v) ? v.length === 0 : v === "" || v === undefined;
    case "verdadero": return v === true;
    case "falso": return v === false;
  }
}

export function clasificar(r: Receta, elementos: Elemento[], yo: string) {
  const q = (k: "q1" | "q2" | "q4") => {
    const c = r.preguntas[k];
    return c ? elementos.filter((e) => cumple(c, e.campos, yo)).map((e) => e.id) : [];
  };
  return { q1: q("q1"), q2: q("q2"), q4: q("q4") };
}

/** Q3: qué entra y qué sale de Q1 entre dos instantes de la misma fuente. */
export function diferenciasQ1(antes: Resultado, despues: Resultado) {
  const a = new Set(antes.preguntas.q1), b = new Set(despues.preguntas.q1);
  return { entran: [...b].filter((x) => !a.has(x)).sort(), salen: [...a].filter((x) => !b.has(x)).sort() };
}

export async function ejecutarReceta(o: Opciones): Promise<Resultado> {
  const r = o.receta;
  const mutante = o.mutante ?? "ninguno";
  const previo = o.almacen?.aviso(r.id);
  if (previo) return vacio(r, "DESACTIVADA", previo);
  const activacion = comprobarActivacion(r, o.validaciones);
  if (!activacion.activa && mutante !== "experimental_sin_recibo") return vacio(r, "DESACTIVADA", activacion.aviso);

  const espera = o.esperaMs ?? 450;
  const fw = new Cortafuegos(r, mutante);
  const nav = await abrirNavegador({ ejecutable: o.ejecutable, perfil: o.perfil, hogar: o.hogar, javascript: r.javascript,
    mutante, perfilPersonal: o.perfilPersonal });
  const ctx = nav.ctx;
  const ventanasAccion: Resultado["ventanasAccion"] = [];
  const porId = new Map<string, Elemento>();
  const canal = nav.canal;
  let fallo: string | null = null;
  try {
    await fw.instalar(ctx);
    if (o.cookies?.length) await ctx.addCookies(o.cookies);
    const page = ctx.pages()[0] ?? (await ctx.newPage());
    const parar = () => fw.bloqueoTotal;

    const recoger = async () => {
      const ahora = new Date().toISOString();
      for (const x of await extraer(page, r.extraccion, mutante === "extraccion_mundo_principal")) {
        if (!x.id) continue;
        porId.set(x.id, { id: x.id, fuente: r.id, url: page.url(), observado_en: ahora, campos: x.campos });
      }
    };
    const asentar = async () => {
      await page.waitForLoadState("domcontentloaded").catch(() => {});
      await page.waitForSelector(r.extraccion.elemento, { timeout: 2500 }).catch(() => {});
      await page.waitForTimeout(espera);
    };

    for (const pagina of r.paginas) {
      if (parar()) break;
      await page.goto(r.origen + pagina, { waitUntil: "domcontentloaded" }).catch(() => {});
      await asentar();
      if (parar()) break;
      if (pagina === r.humo.pagina) {
        const muestra = await extraer(page, r.extraccion, mutante === "extraccion_mundo_principal");
        const sano = muestra.length >= r.humo.minimo && muestra.every((m) => m.id &&
          r.humo.campos_obligatorios.every((c) => { const v = m.campos[c]; return Array.isArray(v) ? true : v !== "" && v !== undefined; }));
        if (!sano) { fw.desactivar(`la prueba de humo falló en ${pagina}`); break; }
      }
      await recoger();
      for (const a of r.acciones) {
        for (let i = 0; i < a.max_repeticiones && !parar(); i++) {
          const el = await page.$(a.selector);
          if (!el) break;
          const href = await el.getAttribute("href");
          if (href !== null && !casa(new URL(href, page.url()).href, r.origen, a.urls)) break;
          const desde = Date.now();
          fw.accion = a;
          await el.click({ timeout: 2000 }).catch(() => {});
          await page.waitForTimeout(150);
          await asentar();
          fw.accion = null;
          ventanasAccion.push({ accion: a.id, desde, hasta: Date.now() });
          if (parar()) break;
          await recoger();
        }
      }
    }
    await nav.esperarDescargas();
  } catch (e) {
    // Fail-closed: una lectura a medias no devuelve datos dudosos.
    fallo = (e as Error).message.split("\n")[0];
  } finally {
    await nav.cerrar();
  }

  const base = { registro: fw.registro, ventanasAccion, descargas: nav.descargas(), canal };
  if (fw.sesionCaducada) {
    return { ...vacio(r, "SESION_CADUCADA", `Vuelve a iniciar sesión en ${r.sitio} en el perfil de Soul. Soul no guarda contraseñas ni rellena credenciales.`), ...base };
  }
  if (fallo !== null) {
    return { ...vacio(r, "ERROR", `La lectura de ${r.sitio} falló (${fallo}); no se devuelven datos.`), ...base };
  }
  if (fw.desactivada) {
    o.almacen?.desactivar(r.id, fw.desactivada);
    return { ...vacio(r, "DESACTIVADA", fw.desactivada), ...base };
  }
  const elementos = [...porId.values()];
  return { ...vacio(r, "OK", null), ...base, elementos, preguntas: clasificar(r, elementos, o.yo) };
}
