// Arranque del navegador instalado sobre el perfil dedicado de Soul, común al
// ejecutor de recetas y a la vigilancia de páginas sin receta. Nunca el perfil
// personal; el proceso del navegador vive con HOME y XDG_* dentro del perfil.

import { mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { chromium, type BrowserContext, type Page } from "playwright-core";
import type { Mutante } from "../cortafuegos/decision.ts";
import { almacenClaves, canalDepuracion, comprobarPerfilDedicado, crearPerfilDedicado, rutasPerfilPersonal } from "../cortafuegos/perfil.ts";

export interface OpcionesNavegador {
  ejecutable: string;
  /** Perfil dedicado persistente; sin él, uno temporal que se borra al cerrar. */
  perfil?: string;
  /** HOME del operador: para rechazar su perfil personal (en el banco, un HOME canario). */
  hogar?: string;
  javascript: boolean;
  mutante?: Mutante;
  /** Solo para el mutante `perfil_personal`. */
  perfilPersonal?: string;
}

export interface Navegador {
  ctx: BrowserContext;
  perfil: string;
  canal: ReturnType<typeof canalDepuracion>;
  /** Descargas que llegaron a guardarse (un intento cortado no cuenta). */
  descargas(): number;
  esperarDescargas(ms?: number): Promise<void>;
  cerrar(): Promise<void>;
}

function entornoNavegador(hogar: string): Record<string, string> {
  for (const d of [".config", ".cache", ".local/share"]) mkdirSync(join(hogar, d), { recursive: true });
  const env: Record<string, string> = {};
  // DBUS_SESSION_BUS_ADDRESS: el perfil persistente guarda la clave de sus cookies en el llavero (H-5).
  for (const k of ["PATH", "LANG", "TZ", "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "TMPDIR"]) {
    const v = process.env[k];
    if (v) env[k] = v;
  }
  return { ...env, HOME: hogar, XDG_CONFIG_HOME: join(hogar, ".config"), XDG_CACHE_HOME: join(hogar, ".cache"),
    XDG_DATA_HOME: join(hogar, ".local/share") };
}

export async function abrirNavegador(o: OpcionesNavegador): Promise<Navegador> {
  const mutante = o.mutante ?? "ninguno";
  const hogar = o.hogar ?? process.env.HOME ?? "";
  const temporal = !o.perfil;
  const perfil = mutante === "perfil_personal" && o.perfilPersonal ? o.perfilPersonal : o.perfil ?? crearPerfilDedicado();
  if (mutante !== "perfil_personal") comprobarPerfilDedicado(perfil, rutasPerfilPersonal(hogar));
  const claves = almacenClaves({ persistente: !temporal });
  let ctx: BrowserContext;
  try {
    ctx = await chromium.launchPersistentContext(perfil, {
      executablePath: o.ejecutable,
      timeout: 15_000,
      headless: true,
      acceptDownloads: mutante === "sin_descargas",
      javaScriptEnabled: o.javascript,
      serviceWorkers: "block",
      // Chrome escribe `Crash Reports` bajo $XDG_CONFIG_HOME/google-chrome aunque se le dé
      // --user-data-dir, y la base NSS en $HOME/.pki: todo va dentro del perfil dedicado.
      env: entornoNavegador(mutante === "perfil_personal" ? hogar : join(perfil, "hogar")),
      args: ["--no-first-run", "--no-default-browser-check", "--disable-sync", ...claves,
        "--disable-features=AutofillServerCommunication,PasswordManagerOnboarding",
        // Un SharedWorker cuelga del navegador y otro cliente CDP lo reanuda: fuera del todo.
        ...(mutante === "workers_libres" ? [] : ["--disable-shared-workers"])],
    });
  } catch (e) {
    if (temporal && mutante !== "perfil_personal") rmSync(perfil, { recursive: true, force: true });
    throw e;
  }
  const pendientes: Promise<void>[] = [];
  let descargas = 0;
  const vigilar = (p: Page) => p.on("download", (d) => {
    pendientes.push(d.failure().then((f) => { if (f === null) descargas++; }).catch(() => {}));
  });
  ctx.on("page", vigilar);
  ctx.pages().forEach(vigilar);
  return {
    ctx, perfil, canal: canalDepuracion(perfil),
    descargas: () => descargas,
    esperarDescargas: async (ms = 2000) => {
      await Promise.race([Promise.all(pendientes), new Promise((ok) => setTimeout(ok, ms))]);
    },
    cerrar: async () => {
      await ctx.close().catch(() => {});
      if (mutante !== "perfil_personal" && temporal) rmSync(perfil, { recursive: true, force: true });
    },
  };
}

/** Evalúa `expresion` en un mundo aislado de la página (CDP): el JavaScript de
 *  la página comparte el DOM pero no los prototipos, así que no puede falsear
 *  lo que Soul lee parcheando `getAttribute` o `textContent`. `principal` solo
 *  lo usa el mutante (el `$$eval` de Labs, en el mundo de la página). */
export async function evaluarAislado(page: Page, expresion: string, principal = false): Promise<unknown> {
  if (principal) return page.evaluate(expresion);
  const s = await page.context().newCDPSession(page);
  try {
    const { frameTree } = await s.send("Page.getFrameTree");
    const { executionContextId } = await s.send("Page.createIsolatedWorld",
      { frameId: frameTree.frame.id, worldName: "soul-lectura" });
    const r = await s.send("Runtime.evaluate", { expression: expresion, contextId: executionContextId, returnByValue: true });
    if (r.exceptionDetails) throw new Error(`lectura aislada: ${r.exceptionDetails.text}`);
    return r.result.value;
  } finally {
    await s.detach().catch(() => {});
  }
}
