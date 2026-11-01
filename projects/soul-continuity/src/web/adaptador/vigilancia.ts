// Vigilancia de páginas SIN receta (SE-490): solo detecta «esta página cambió
// desde la última visita» y da el enlace. No extrae nada ni lo interpreta.
// Va por el mismo cortafuegos con una receta mínima sintetizada: esa URL
// exacta, sin JavaScript, sin POST, sin WebSocket y sin acciones. Guarda la
// huella del texto, nunca el texto.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { Cortafuegos, type Registro } from "../cortafuegos/cortafuegos.ts";
import type { Mutante } from "../cortafuegos/decision.ts";
import type { Receta } from "../receta/tipos.ts";
import { pareceAccion } from "../receta/validar.ts";
import { abrirNavegador, evaluarAislado } from "./navegador.ts";

export class VigilanciaInvalida extends Error {}
export class HuellasIlegibles extends Error {}

export interface Vigilada {
  id: string;
  sitio: string;
  /** URL absoluta exacta (vista de lista o panel de solo lectura). */
  url: string;
}

export interface ResultadoVigilancia {
  id: string;
  estado: "PRIMERA_VISITA" | "SIN_CAMBIOS" | "CAMBIADA" | "REDIRIGIDA" | "ERROR";
  aviso: string | null;
  enlace: string;
  /** Mismos campos que el ejecutor de recetas, para medir con la misma batería. */
  alertas: never[];
  registro: Registro[];
  ventanasAccion: { accion: string; desde: number; hasta: number }[];
  descargas: number;
  /** Huella leída en esta visita (si se leyó). Con `diferirHuella`, la guarda quien llama. */
  huella?: string;
}

export function recetaDeVigilancia(v: Vigilada): Receta {
  let u: URL;
  try { u = new URL(v.url); } catch { throw new VigilanciaInvalida(`URL inválida: ${v.url}`); }
  if (u.protocol !== "http:" && u.protocol !== "https:") throw new VigilanciaInvalida(`esquema no admitido: ${u.protocol}`);
  if (u.username || u.password) throw new VigilanciaInvalida("URL con credenciales");
  if (u.hash || v.url.includes("#")) throw new VigilanciaInvalida("URL con fragmento");
  const ruta = u.pathname + u.search;
  if (ruta.includes("*")) throw new VigilanciaInvalida("URL con comodín");
  if (pareceAccion(ruta)) throw new VigilanciaInvalida(`la URL parece un enlace de acción: ${ruta}`);
  return {
    formato: "soul-receta-web/1", id: `vigilancia-${v.id}`, sitio: v.sitio, estado: "estable",
    origen: u.origin, javascript: false, urls: [ruta], renovacion_sesion: [], post_lectura: [],
    websocket: { urls: [], mantenimiento: [] }, paginas: [ruta], acciones: [],
    extraccion: { elemento: "body", id: { attr: "id" }, campos: {} }, preguntas: {},
    sesion: { login: [] }, humo: { pagina: ruta, minimo: 1, campos_obligatorios: [] },
  };
}

export function huellaTexto(texto: string): string {
  return createHash("sha256").update(texto.replace(/\s+/g, " ").trim()).digest("hex");
}

/** Huellas por página vigilada: huella, URL y fecha. Nunca el contenido. */
export class AlmacenHuellas {
  readonly ruta: string;
  constructor(ruta: string) { this.ruta = ruta; }
  private leer(): Record<string, { huella: string; url: string; visto_en: string }> {
    if (!existsSync(this.ruta)) return {};
    // Fail-closed: un fichero ilegible no es «nunca visto» (eso callaría los
    // cambios y el siguiente guardado borraría las demás huellas).
    let d: unknown;
    try { d = JSON.parse(readFileSync(this.ruta, "utf8")); } catch { d = null; }
    if (!d || typeof d !== "object" || Array.isArray(d)) throw new HuellasIlegibles(`fichero de huellas ilegible: ${this.ruta}`);
    return d as Record<string, { huella: string; url: string; visto_en: string }>;
  }
  anterior(id: string): string | null { return this.leer()[id]?.huella ?? null; }
  guardar(id: string, url: string, huella: string) {
    const d = this.leer();
    d[id] = { huella, url, visto_en: new Date().toISOString() };
    mkdirSync(dirname(this.ruta), { recursive: true, mode: 0o700 });
    writeFileSync(this.ruta, JSON.stringify(d, null, 2), { mode: 0o600 });
  }
}

export interface OpcionesVigilancia {
  vigilada: Vigilada;
  ejecutable: string;
  almacen: AlmacenHuellas;
  perfil?: string;
  /** Solo el banco. */
  cookies?: Parameters<import("playwright-core").BrowserContext["addCookies"]>[0];
  hogar?: string;
  mutante?: Mutante;
  perfilPersonal?: string;
  /** No guardar la huella: quien llama la confirma solo si entrega el resultado. */
  diferirHuella?: boolean;
}

export async function vigilarPagina(o: OpcionesVigilancia): Promise<ResultadoVigilancia> {
  const v = o.vigilada;
  const r = recetaDeVigilancia(v);
  const mutante = o.mutante ?? "ninguno";
  const fw = new Cortafuegos(r, mutante);
  const base = { id: v.id, enlace: v.url, alertas: [] as never[], ventanasAccion: [], registro: fw.registro };
  const nav = await abrirNavegador({ ejecutable: o.ejecutable, perfil: o.perfil, hogar: o.hogar,
    javascript: mutante === "vigilancia_con_js", mutante, perfilPersonal: o.perfilPersonal });
  let texto: string | null = null;
  let fallo: string | null = null;
  let final = "";
  try {
    await fw.instalar(nav.ctx);
    if (o.cookies?.length) await nav.ctx.addCookies(o.cookies);
    const page = nav.ctx.pages()[0] ?? (await nav.ctx.newPage());
    const resp = await page.goto(v.url, { waitUntil: "domcontentloaded" }).catch((e: Error) => e);
    // Fallo de red sin corte del cortafuegos: no es una redirección ni una sesión caducada.
    if (resp instanceof Error && !fw.sesionCaducada && !fw.registro.some((g) => !g.permitida)) {
      throw new Error(`no se pudo cargar: ${resp.message.split("\n")[0]}`);
    }
    // Una página de error (404, 5xx) no es contenido: huellarla daría dos «cambió» falsos.
    if (resp && !(resp instanceof Error) && !resp.ok()) throw new Error(`HTTP ${resp.status()}`);
    await page.waitForTimeout(450);
    final = page.url();
    const t = await evaluarAislado(page, "document.body ? document.body.textContent : ''");
    texto = typeof t === "string" ? t : null;
    await nav.esperarDescargas(500);
  } catch (e) {
    fallo = (e as Error).message.split("\n")[0];
  } finally {
    await nav.cerrar();
  }
  const comun = { ...base, descargas: nav.descargas() };
  const redirigida = fw.sesionCaducada || fw.registro.some((g) => g.motivo === "redireccion_fuera") || (final !== "" && final !== new URL(v.url).href);
  if (redirigida) {
    return { ...comun, estado: "REDIRIGIDA",
      aviso: `La página de ${v.sitio} redirige fuera de la URL vigilada. Si es el inicio de sesión, vuelve a iniciar sesión en ${v.sitio} en el perfil de Soul.` };
  }
  if (fallo !== null || texto === null) {
    return { ...comun, estado: "ERROR", aviso: `No se pudo leer ${v.sitio} (${fallo ?? "sin texto"}).` };
  }
  const huella = huellaTexto(texto);
  const previa = o.almacen.anterior(v.id);
  if (!o.diferirHuella) o.almacen.guardar(v.id, v.url, huella);
  if (previa === null) return { ...comun, huella, estado: "PRIMERA_VISITA", aviso: null };
  if (previa === huella) return { ...comun, huella, estado: "SIN_CAMBIOS", aviso: null };
  return { ...comun, huella, estado: "CAMBIADA", aviso: `La página de ${v.sitio} cambió desde la última visita: ${v.url}` };
}
