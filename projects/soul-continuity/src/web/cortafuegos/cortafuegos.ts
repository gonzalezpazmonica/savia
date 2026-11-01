// Cortafuegos de red del adaptador `web` sobre playwright-core. Aplica la
// receta FUERA del modelo y fuera de la página. Todas las capas usan la misma
// decisión pura (`decidirHttp`); lo no previsto se corta.
//
// Capas, y por qué hacen falta (hallazgos del prototipo):
//  A. Guardia del navegador: sesión CDP a nivel de navegador con `Fetch`, en
//     fase de petición y de respuesta. Ve lo que `context.route` no ve:
//     descargas por `<a download>`, favicon, scripts de workers y CADA salto
//     de una redirección (`context.route` solo ve la primera URL). En la fase
//     de respuesta corta adjuntos y detecta 401. Sin ella no se ejecuta.
//  B. `context.route`: misma decisión, y 204 para que una navegación cortada
//     deje la página donde estaba. Solo `continue`: servir la página con
//     `route.fetch` + `fulfill` rompe el WebSocket enrutado (no conecta).
//  C. WebSocket por `routeWebSocket` (solo salen los mensajes de
//     mantenimiento) y workers bloqueados: un WebSocket abierto desde un
//     worker esquiva `routeWebSocket`, así que en v1 los workers no arrancan
//     (los dedicados se adjuntan en espera del depurador y no se reanudan; los
//     compartidos se desactivan con --disable-shared-workers, porque el
//     auto-adjunto no basta: otro cliente CDP los reanuda).

import type { BrowserContext, Page, Route } from "playwright-core";
import { casa, origenWs } from "../receta/patrones.ts";
import type { AccionNavegacion, Receta } from "../receta/tipos.ts";
import { decidirEnvioWs, decidirHttp, type Motivo, type Mutante } from "./decision.ts";

export interface Registro {
  t: number;
  tipo: "guardia" | "http" | "redireccion" | "respuesta" | "ws" | "ws-envio" | "worker";
  url: string;
  metodo?: string;
  op?: string | null;
  /** Solo en las decisiones HTTP: navegación del documento o subrecurso. */
  navegacion?: boolean;
  permitida: boolean;
  motivo: Motivo | "redireccion_fuera" | "descarga" | "no_autorizado" | "ws_fuera" | "ws_mantenimiento"
    | "ws_envio" | "bloqueo_total" | "worker_bloqueado";
}

/** Bloqueo de formularios en la página: defensa en profundidad, la red manda. */
const SCRIPT_FORMULARIOS = `(() => {
  const no = function () { return undefined; };
  try { HTMLFormElement.prototype.submit = no; HTMLFormElement.prototype.requestSubmit = no; } catch (e) {}
  addEventListener('submit', (e) => { e.preventDefault(); e.stopImmediatePropagation(); }, true);
})();`;

interface Pausa {
  requestId: string;
  resourceType: string;
  redirectedRequestId?: string;
  responseStatusCode?: number;
  responseHeaders?: { name: string; value: string }[];
  request: { url: string; method: string; headers: Record<string, string>; postData?: string; postDataEntries?: { bytes?: string }[] };
}

export class Cortafuegos {
  registro: Registro[] = [];
  /** Aviso de desactivación de la receta; `null` mientras es fiable. */
  desactivada: string | null = null;
  sesionCaducada = false;
  accion: AccionNavegacion | null = null;
  readonly receta: Receta;
  readonly mutante: Mutante;

  constructor(receta: Receta, mutante: Mutante = "ninguno") {
    this.receta = receta;
    this.mutante = mutante;
  }

  /** Tras desactivar o detectar sesión caducada, no sale nada más. */
  get bloqueoTotal() {
    return this.sesionCaducada || this.desactivada !== null;
  }

  private anotar(r: Omit<Registro, "t">) {
    this.registro.push({ t: Date.now(), ...r });
  }

  desactivar(motivo: string) {
    if (this.mutante === "sin_desactivar") return;
    this.desactivada ??= `La receta de ${this.receta.sitio} dejó de ser fiable (${motivo}); se ha desactivado y no devuelve datos.`;
  }

  async instalar(ctx: BrowserContext) {
    await this.guardiaNavegador(ctx);
    if (this.mutante !== "workers_libres") {
      for (const p of ctx.pages()) await this.bloquearWorkers(ctx, p);
      ctx.on("page", (p) => void this.bloquearWorkers(ctx, p).catch(() => {}));
    }
    await ctx.addInitScript(SCRIPT_FORMULARIOS);
    await ctx.route("**/*", (route) => this.manejar(route));
    await ctx.routeWebSocket(/.*/, (ws) => {
      const url = ws.url();
      const permitido = this.mutante === "ws_sin_lista" ||
        (!this.bloqueoTotal && casa(url, origenWs(this.receta.origen), this.receta.websocket.urls));
      this.anotar({ tipo: "ws", url, permitida: permitido, motivo: permitido ? "lista" : "ws_fuera" });
      if (!permitido) return void ws.close({ code: 1008, reason: "soul: fuera de la receta" });
      const servidor = ws.connectToServer();
      ws.onMessage((m) => {
        // Un mensaje binario nunca es de mantenimiento: la lista solo casa texto.
        const ok = !this.bloqueoTotal && typeof m === "string" && decidirEnvioWs(this.receta, m, this.mutante);
        this.anotar({ tipo: "ws-envio", url, permitida: ok, motivo: ok ? "ws_mantenimiento" : "ws_envio" });
        if (ok) servidor.send(m);
      });
      // Recibir sí: lo que llega del servidor se entrega a la página.
      servidor.onMessage((m) => ws.send(m));
    });
  }

  /** Capa A: toda petición HTTP del navegador, incluidas las que no ve `route`. */
  private async guardiaNavegador(ctx: BrowserContext) {
    if (this.mutante === "sin_guardia") return;
    const navegador = ctx.browser();
    if (!navegador) throw new Error("sin sesión de navegador: no hay guardia de red y no se ejecuta");
    const cdp = await navegador.newBrowserCDPSession();
    cdp.on("Fetch.requestPaused", (e: Pausa) => {
      const url = e.request.url;
      const metodo = e.request.method;
      const navegacion = e.resourceType === "Document";
      const seguir = () => cdp.send("Fetch.continueRequest", { requestId: e.requestId }).catch(() => {});
      const cortar = () => (navegacion
        ? cdp.send("Fetch.fulfillRequest", { requestId: e.requestId, responseCode: 204, body: "" })
        : cdp.send("Fetch.failRequest", { requestId: e.requestId, errorReason: "BlockedByClient" })).catch(() => {});

      if (e.responseStatusCode !== undefined) return void this.respuesta(e, url, seguir, cortar);
      if (this.bloqueoTotal) {
        this.anotar({ tipo: "guardia", url, metodo, permitida: false, motivo: "bloqueo_total" });
        return void cortar();
      }
      if (e.redirectedRequestId && this.mutante === "redireccion_directa") return void seguir();
      const cabeceras: Record<string, string> = {};
      for (const [k, v] of Object.entries(e.request.headers ?? {})) cabeceras[k.toLowerCase()] = v;
      const cuerpo = e.request.postData ??
        (e.request.postDataEntries?.map((x) => Buffer.from(x.bytes ?? "", "base64").toString("utf8")).join("") || null);
      const d = decidirHttp(this.receta, { accion: this.accion }, { url, metodo, cabeceras, cuerpo, navegacion }, this.mutante);
      const salto = e.redirectedRequestId !== undefined;
      this.anotar({ tipo: salto ? "redireccion" : "guardia", url, metodo, op: d.op, navegacion, permitida: d.permitir,
        motivo: !d.permitir && salto && !d.sesion ? "redireccion_fuera" : d.motivo });
      if (d.sesion) this.sesionCaducada = true;
      if (d.desactivar) this.desactivar(`operación ${d.op ?? "sin declarar"} en ${new URL(url).pathname}`);
      void (d.permitir ? seguir() : cortar());
    });
    if (this.mutante !== "workers_libres") {
      // Workers compartidos y de servicio cuelgan del navegador, no de la página.
      cdp.on("Target.attachedToTarget", (e: { targetInfo: { type: string; url: string } }) => {
        this.anotar({ tipo: "worker", url: e.targetInfo.url, permitida: false, motivo: "worker_bloqueado" });
      });
      await cdp.send("Target.setAutoAttach", {
        autoAttach: true, waitForDebuggerOnStart: true, flatten: true,
        filter: [{ type: "shared_worker" }, { type: "service_worker" }, { exclude: true }],
      });
    }
    await cdp.send("Fetch.enable", {
      patterns: [{ urlPattern: "*", requestStage: "Request" }, { urlPattern: "*", requestStage: "Response" }],
    });
  }

  /** Capa A, fase de respuesta: adjuntos fuera, 401 = sesión caducada. */
  private respuesta(e: Pausa, url: string, seguir: () => unknown, cortar: () => unknown) {
    const cab = new Map((e.responseHeaders ?? []).map((h) => [h.name.toLowerCase(), h.value]));
    if (e.responseStatusCode === 401) {
      this.sesionCaducada = true;
      this.anotar({ tipo: "respuesta", url, permitida: false, motivo: "no_autorizado" });
      return cortar();
    }
    if (this.mutante !== "sin_descargas" && /^\s*attachment/i.test(cab.get("content-disposition") ?? "")) {
      this.anotar({ tipo: "respuesta", url, permitida: false, motivo: "descarga" });
      return cortar();
    }
    return seguir();
  }

  /** Capa C: los workers de la página se adjuntan en pausa y no se reanudan. */
  private async bloquearWorkers(ctx: BrowserContext, page: Page) {
    const s = await ctx.newCDPSession(page);
    s.on("Target.attachedToTarget", (e: { targetInfo: { type: string; url: string } }) => {
      this.anotar({ tipo: "worker", url: e.targetInfo.url, permitida: false, motivo: "worker_bloqueado" });
    });
    await s.send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
  }

  /** Capa B. Navegación cortada → 204 (la página se queda donde estaba); subrecurso → abortado. */
  private async manejar(route: Route) {
    const req = route.request();
    const url = req.url();
    const metodo = req.method();
    const navegacion = req.isNavigationRequest();
    const cortar = () => (navegacion ? route.fulfill({ status: 204, body: "" }) : route.abort("blockedbyclient"));
    if (this.bloqueoTotal) {
      this.anotar({ tipo: "http", url, metodo, permitida: false, motivo: "bloqueo_total" });
      return cortar();
    }
    const d = decidirHttp(this.receta, { accion: this.accion }, {
      url, metodo, navegacion, cabeceras: await req.allHeaders(), cuerpo: req.postData(),
    }, this.mutante);
    this.anotar({ tipo: "http", url, metodo, op: d.op, navegacion, permitida: d.permitir, motivo: d.motivo });
    if (d.sesion) this.sesionCaducada = true;
    if (d.desactivar) this.desactivar(`operación ${d.op ?? "sin declarar"} en ${new URL(url).pathname}`);
    return d.permitir ? route.continue() : cortar();
  }
}
