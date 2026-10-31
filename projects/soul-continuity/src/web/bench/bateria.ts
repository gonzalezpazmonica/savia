// Batería AC-4e del adaptador `web` (SE-490). Compara contra la verdad
// escrita antes (`verdad/ac4e.json`) y mide en el SERVIDOR, no por el método
// HTTP: cada petición y cada mutación que llega a los sitios sintéticos.
//
// Uso: node --experimental-strip-types bench/bateria.ts [--mutante <id>] [--salida <dir>]

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { guardarRecibo } from "../adaptador/activacion.ts";
import { AlmacenRecetas, diferenciasQ1, ejecutarReceta, type Resultado } from "../adaptador/ejecutor.ts";
import { AlmacenHuellas, recetaDeVigilancia, vigilarPagina, type ResultadoVigilancia } from "../adaptador/vigilancia.ts";
import type { Mutante } from "../cortafuegos/decision.ts";
import { buscarNavegador, crearHogarCanario, diferenciasHuella, huella } from "../cortafuegos/perfil.ts";
import { casa } from "../receta/patrones.ts";
import type { Receta } from "../receta/tipos.ts";
import { cargarReceta, validarReceta } from "../receta/validar.ts";
import { Banco, type Escenario, type Sitio } from "../banco/servidor.ts";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
const VERDAD = JSON.parse(readFileSync(join(RAIZ, "verdad", "ac4e.json"), "utf8"));
const YO: string = VERDAD.yo;
const UMBRAL: number = VERDAD.umbral_precision;

export interface Comprobacion { id: string; ok: boolean; detalle: string }
export interface Informe {
  mutante: Mutante; navegador: string; aviso_navegador: string | null;
  comprobaciones: Comprobacion[]; aprobadas: number; fallidas: number;
  metricas: Record<string, Record<string, number>>;
  precision: Record<string, Record<string, { precision: number | null; recall: number | null }>>;
}

type Metricas = ReturnType<typeof medir>;

/** Métricas de una ejecución, a partir del registro del servidor. */
function medir(b: Banco, r: Receta, sitio: Sitio, res: Pick<Resultado, "registro" | "ventanasAccion" | "descargas" | "alertas">) {
  const http = b.peticiones.filter((p) => !p.ws);
  const url = (p: { sitio: Sitio; ruta: string }) => b.origen(p.sitio) + p.ruta;
  const esLecturaPost = (p: (typeof http)[number]) =>
    p.sitio === sitio && p.metodo === "POST" &&
    (casa(url(p), r.origen, r.renovacion_sesion) ||
      r.post_lectura.some((o) => casa(url(p), r.origen, [o.url]) && p.op !== null && o.lectura.includes(p.op)));
  const permitidas = new Set(res.registro.filter((x) => x.permitida).map((x) => x.url));
  const accionDe = new Map(r.acciones.map((a) => [a.id, a]));
  return {
    mutaciones_servidor: b.mutaciones.length,
    peticiones_no_get_fuera_de_lista: http.filter((p) => !["GET", "HEAD"].includes(p.metodo) && !esLecturaPost(p)).length,
    operaciones_post_fuera_de_lista: http.filter((p) => p.metodo === "POST" && p.sitio === sitio &&
      !casa(url(p), r.origen, r.renovacion_sesion) && !esLecturaPost(p)).length,
    envios_websocket_fuera_de_mantenimiento: b.peticiones.filter((p) => p.metodo === "WS-ENVIO" &&
      !r.websocket.mantenimiento.includes(p.ruta)).length,
    navegaciones_fuera_de_lista: http.filter((p) => ["GET", "HEAD"].includes(p.metodo) && !casa(url(p), r.origen, r.urls)).length,
    envios_formulario: http.filter((p) => p.formulario).length,
    peticiones_a_externo: b.peticiones.filter((p) => p.sitio === "externo").length,
    descargas: res.descargas,
    alertas_producidas: res.alertas.length,
    intentos_login: http.filter((p) => p.ruta.startsWith("/login") && p.metodo === "POST").length,
    peticiones_sin_pasar_por_cortafuegos: http.filter((p) => !permitidas.has(url(p))).length,
    peticiones_fuera_de_accion: http.filter((p) => res.ventanasAccion.some((v) =>
      p.t >= v.desde && p.t <= v.hasta && !casa(url(p), r.origen, accionDe.get(v.accion)!.urls))).length,
  };
}

function pr(obtenido: string[], esperado: string[]) {
  const e = new Set(esperado);
  const aciertos = obtenido.filter((x) => e.has(x)).length;
  return {
    precision: obtenido.length ? aciertos / obtenido.length : null,
    recall: esperado.length ? aciertos / esperado.length : null,
  };
}

export async function ejecutarBateria(mutante: Mutante = "ninguno"): Promise<Informe> {
  const nav = buscarNavegador();
  const b = await new Banco().arrancar();
  const canario = crearHogarCanario();
  // Se vigila el HOME canario entero, no solo el perfil: ni ~/.config ni ~/.pki.
  const huellaAntes = huella(canario.hogar);
  const tmp = mkdtempSync(join(tmpdir(), "soul-banco-"));
  const comprobaciones: Comprobacion[] = [];
  const metricas: Informe["metricas"] = {};
  const precision: Informe["precision"] = {};
  const traza = process.env.SOUL_BANCO_TRAZA === "1";
  const ok = (id: string, cond: boolean, detalle = "") => {
    comprobaciones.push({ id, ok: cond, detalle });
    if (traza) console.error(`${cond ? "ok" : "FALLA"} ${id}`);
  };

  const receta = (s: Sitio, cambios: Partial<Receta> = {}) =>
    ({ ...cargarReceta(join(RAIZ, "recetas", "sinteticas", `${s}.json`), { puerto: b.puerto }), ...cambios }) as Receta;
  const correr = async (s: Sitio, r: Receta, extra: { almacen?: AlmacenRecetas; esperaMs?: number; validaciones?: string } = {}) => {
    let res: Resultado;
    try {
      res = await ejecutarReceta({
        receta: r, yo: YO, ejecutable: nav.ruta, cookies: [b.cookieSesion(s)], mutante,
        hogar: canario.hogar, perfilPersonal: canario.perfilPersonal,
        esperaMs: extra.esperaMs ?? (s === "correo" ? 1500 : 450), almacen: extra.almacen, validaciones: extra.validaciones,
      });
    } catch (e) {
      // Una ejecución que revienta es una comprobación fallida, no el fin de la batería.
      ok(`ejecucion:${s}:sin_excepcion`, false, (e as Error).message.split("\n")[0]);
      res = { receta: r.id, estado: "ERROR", aviso: "excepción", elementos: [], preguntas: { q1: [], q2: [], q4: [] },
        alertas: [], registro: [], ventanasAccion: [], descargas: 0, canal: null };
    }
    return { res, m: medir(b, r, s, res) };
  };
  /** Los invariantes de cero efectos se exigen en TODAS las ejecuciones. */
  const invariantes = (nombre: string, m: Metricas) => {
    metricas[nombre] = m;
    for (const k of Object.keys(VERDAD.invariantes)) {
      if (k === "cambios_perfil_personal") continue;
      const v = (m as Record<string, number>)[k];
      ok(`${nombre}:${k}`, v === 0, `${v}`);
    }
    ok(`${nombre}:peticiones_sin_pasar_por_cortafuegos`, m.peticiones_sin_pasar_por_cortafuegos === 0, `${m.peticiones_sin_pasar_por_cortafuegos}`);
    ok(`${nombre}:peticiones_fuera_de_accion`, m.peticiones_fuera_de_accion === 0, `${m.peticiones_fuera_de_accion}`);
  };
  const precisionDe = (nombre: string, s: Sitio, res: Resultado, qs: string[]) => {
    precision[nombre] = {};
    for (const q of qs) {
      const v = pr(res.preguntas[q as "q1"], VERDAD.sitios[s][q]);
      precision[nombre][q] = v;
      // Fail-closed: sin elementos no hay precisión que dar por buena.
      ok(`${nombre}:${q}:precision>=${UMBRAL}`, v.precision !== null && v.precision >= UMBRAL, JSON.stringify(v));
    }
  };

  try {
    // 1) Base + Q3 en los tres sitios de tipos distintos.
    for (const s of ["tareas", "aprobaciones", "noticias"] as Sitio[]) {
      b.reiniciar();
      const r = receta(s);
      const a = await correr(s, r);
      ok(`base:${s}:estado`, a.res.estado === "OK", `${a.res.estado} ${a.res.aviso ?? ""}`);
      invariantes(`base:${s}`, a.m);
      precisionDe(`base:${s}`, s, a.res, ["q1", "q2", "q4"]);
      if (a.res.canal) ok(`base:${s}:canal_depuracion_por_tuberia`, a.res.canal.tuberia && !a.res.canal.puerto, JSON.stringify(a.res.canal));
      b.cambioQ3();
      b.limpiarRegistros();
      const d = await correr(s, r);
      invariantes(`q3:${s}`, d.m);
      const q3 = diferenciasQ1(a.res, d.res);
      ok(`q3:${s}:diferencias`, JSON.stringify(q3) === JSON.stringify(VERDAD.sitios[s].q3), JSON.stringify(q3));
    }
    {
      b.reiniciar();
      const r = receta("tareas");
      const a = await correr("tareas", r);
      const t105 = a.res.elementos.find((e) => e.id === "T-105");
      ok("inyeccion:tareas:prioridad_no_alterada", t105?.campos.prioridad === VERDAD.sitios.tareas.prioridad_no_alterada["T-105"],
        String(t105?.campos.prioridad));
    }
    // 2) Cliente que lee por POST: Q1–Q2.
    b.reiniciar();
    {
      const r = receta("correo");
      const a = await correr("correo", r);
      ok("base:correo:estado", a.res.estado === "OK", `${a.res.estado} ${a.res.aviso ?? ""}`);
      invariantes("base:correo", a.m);
      precisionDe("base:correo", "correo", a.res, ["q1", "q2"]);
      ok("base:correo:websocket_abierto_y_mantenimiento", b.peticiones.some((p) => p.metodo === "WS-ENVIO"),
        "el banco necesita ver el ping para que «0 envíos» signifique algo");
    }

    const escenario = async (s: Sitio, e: Escenario, cambios: Partial<Receta> = {}, extra: { almacen?: AlmacenRecetas } = {}) => {
      b.reiniciar();
      b.activar(s, e);
      const r = receta(s, cambios);
      const x = await correr(s, r, extra);
      invariantes(`${e}:${s}`, x.m);
      return x;
    };
    const esperado = VERDAD.escenarios;

    // 3) Sesión caducada: parada limpia en un sitio HTML y en el cliente POST.
    for (const s of ["tareas", "correo"] as Sitio[]) {
      const x = await escenario(s, "sesion_caducada");
      ok(`sesion_caducada:${s}:estado`, x.res.estado === esperado.sesion_caducada.estado, `${x.res.estado}`);
      ok(`sesion_caducada:${s}:aviso`, (x.res.aviso ?? "").toLowerCase().includes(esperado.sesion_caducada.aviso_contiene), `${x.res.aviso}`);
      ok(`sesion_caducada:${s}:sin_elementos`, x.res.elementos.length === 0, `${x.res.elementos.length}`);
      ok(`sesion_caducada:${s}:sin_intentos_login`, x.m.intentos_login === 0, `${x.m.intentos_login}`);
    }
    // 4) Operación nueva del cliente: se aborta y desactiva la receta, con aviso que persiste.
    {
      const almacen = new AlmacenRecetas(join(tmp, "recetas-estado.json"));
      const x = await escenario("correo", "operacion_nueva", {}, { almacen });
      ok("operacion_nueva:correo:estado", x.res.estado === "DESACTIVADA", `${x.res.estado}`);
      ok("operacion_nueva:correo:aviso", (x.res.aviso ?? "").includes(esperado.operacion_nueva.aviso_contiene), `${x.res.aviso}`);
      ok("operacion_nueva:correo:sin_elementos", x.res.elementos.length === 0, `${x.res.elementos.length}`);
      b.limpiarRegistros();
      const y = await correr("correo", receta("correo"), { almacen });
      ok("operacion_nueva:correo:persistente", y.res.estado === "DESACTIVADA" && b.peticiones.length === 0,
        `${y.res.estado}, ${b.peticiones.length} peticiones`);
    }
    // 5) La prueba de humo detecta el cambio del sitio y desactiva.
    {
      const x = await escenario("tareas", "cambio_dom");
      ok("cambio_dom:tareas:estado", x.res.estado === "DESACTIVADA", `${x.res.estado}`);
      ok("cambio_dom:tareas:aviso", (x.res.aviso ?? "").includes(esperado.cambio_dom.aviso_contiene), `${x.res.aviso}`);
      ok("cambio_dom:tareas:sin_elementos", x.res.elementos.length === 0, `${x.res.elementos.length}`);
    }
    // 6) Redirección en dos saltos hacia un GET que muta.
    {
      const x = await escenario("aprobaciones", "redireccion");
      ok("redireccion:aprobaciones:salto_cortado", x.res.registro.some((g) => !g.permitida && g.url.includes("/approve")),
        "el registro debe mostrar el corte del segundo salto");
    }
    // 7) GraphQL con operationName de lectura y documento mutation.
    await escenario("correo", "graphql_disfrazada");
    // 8) Acción secuestrada por JavaScript (receta forzada con JS para probar el ligado).
    {
      const x = await escenario("tareas", "accion_secuestrada", { javascript: true });
      ok("accion_secuestrada:tareas:corte_registrado", x.res.registro.some((g) => g.motivo === "accion_no_ligada"), "");
    }
    // 9) Página permitida que responde con un adjunto.
    await escenario("tareas", "descarga_disfrazada");
    // 10) Contenido hostil con JS: el script de la intranet intenta todo lo prohibido,
    // falsea los prototipos de la página (la extracción va en un mundo aislado) y abre
    // una ventana hacia una URL de otro origen que la receta admite solo como subrecurso.
    {
      b.reiniciar();
      const r0 = receta("noticias");
      const r = validarReceta({ ...r0, javascript: true, urls: [...r0.urls, `${b.origen("externo")}/recoger?popup=1`] });
      const x = await correr("noticias", r);
      invariantes("contenido_hostil:noticias", x.m);
      precisionDe("contenido_hostil:noticias", "noticias", x.res, ["q1", "q2", "q4"]);
      ok("contenido_hostil:noticias:ataque_ejecutado", x.res.registro.filter((g) => !g.permitida).length >= 5,
        "el script hostil debe haber intentado salir (si no, la prueba no prueba nada)");
    }
    // 11) WebSocket desde workers y 12) descarga por atributo `download` hacia un GET que muta.
    await escenario("correo", "ws_worker");
    await escenario("correo", "descarga_atributo");
    // 17) Operación en la URL: GET al endpoint de operaciones y POST con la consulta
    // distinta de la cabecera (el servidor del banco ejecuta la de la consulta).
    {
      const x = await escenario("correo", "operacion_en_url");
      ok("operacion_en_url:correo:get_cortado", x.res.registro.some((g) => !g.permitida && g.motivo === "metodo" && g.url.includes("x-accion=")), "");
      ok("operacion_en_url:correo:post_cortado", x.res.registro.some((g) => !g.permitida && g.motivo === "operacion_url_distinta"), "");
      ok("operacion_en_url:correo:desactivada", x.res.estado === "DESACTIVADA", `${x.res.estado}`);
    }

    // 14) Login federado: la sesión caducada salta a otro origen (SSO).
    {
      const x = await escenario("tareas", "sesion_sso", { sesion: { login: ["/login", "/login?vuelta=*", b.origen("externo")] } });
      ok("sesion_sso:tareas:estado", x.res.estado === esperado.sesion_caducada.estado, `${x.res.estado}`);
      ok("sesion_sso:tareas:aviso", (x.res.aviso ?? "").toLowerCase().includes(esperado.sesion_caducada.aviso_contiene), `${x.res.aviso}`);
      ok("sesion_sso:tareas:sin_elementos", x.res.elementos.length === 0, `${x.res.elementos.length}`);
    }
    // 15) Receta experimental: sin recibo no abre el navegador; con recibo de ESA receta, sí.
    {
      b.reiniciar();
      const dirVal = join(tmp, "validaciones");
      const r = { ...receta("tareas"), estado: "experimental" as const };
      const x = await correr("tareas", r, { validaciones: dirVal });
      ok("experimental:tareas:sin_recibo_desactivada", x.res.estado === "DESACTIVADA" && /experimental/.test(x.res.aviso ?? ""), `${x.res.estado}`);
      ok("experimental:tareas:sin_recibo_sin_peticiones", b.peticiones.length === 0, `${b.peticiones.length}`);
      guardarRecibo(dirVal, r, { peticiones: 1, permitidas: 1, operaciones_lectura: 0 });
      b.limpiarRegistros();
      const y = await correr("tareas", r, { validaciones: dirVal });
      invariantes("experimental:tareas", y.m);
      ok("experimental:tareas:con_recibo_ok", y.res.estado === "OK", `${y.res.estado} ${y.res.aviso ?? ""}`);
    }
    // 16) Sin receta: solo «esta página cambió», por el mismo cortafuegos y sin JavaScript.
    {
      const huellas = new AlmacenHuellas(join(tmp, "huellas.json"));
      const vigilar = async (s: Sitio, ruta: string) => {
        const vigilada = { id: `${s}${ruta}`, sitio: s, url: b.origen(s) + ruta };
        let res: ResultadoVigilancia;
        try {
          res = await vigilarPagina({ vigilada, ejecutable: nav.ruta, almacen: huellas, cookies: [b.cookieSesion(s)], mutante,
            hogar: canario.hogar, perfilPersonal: canario.perfilPersonal });
        } catch (e) {
          ok(`vigilancia:${s}:sin_excepcion`, false, (e as Error).message.split("\n")[0]);
          res = { id: vigilada.id, estado: "ERROR", aviso: "excepción", enlace: vigilada.url, alertas: [], registro: [], ventanasAccion: [], descargas: 0 };
        }
        return { res, m: medir(b, recetaDeVigilancia(vigilada), s, res) };
      };
      b.reiniciar();
      const estados: string[] = [];
      for (const paso of ["primera", "igual", "cambio"]) {
        if (paso === "cambio") b.cambioQ3();
        b.limpiarRegistros();
        const x = await vigilar("aprobaciones", "/aprobaciones");
        invariantes(`vigilancia_${paso}:aprobaciones`, x.m);
        estados.push(x.res.estado);
      }
      ok("vigilancia:aprobaciones:estados", estados.join(",") === "PRIMERA_VISITA,SIN_CAMBIOS,CAMBIADA", estados.join(","));
      b.reiniciar();
      const h = await vigilar("noticias", "/noticias?seccion=portada");
      invariantes("vigilancia:noticias", h.m);
      ok("vigilancia:noticias:sin_javascript", h.res.registro.filter((g) => !g.permitida).length === 0,
        `${h.res.registro.filter((g) => !g.permitida).length} intentos cortados: la página hostil no debe ejecutar nada`);
      b.reiniciar();
      b.activar("tareas", "sesion_caducada");
      const c = await vigilar("tareas", "/tareas?pagina=1");
      invariantes("vigilancia_sesion:tareas", c.m);
      ok("vigilancia_sesion:tareas:redirigida", c.res.estado === "REDIRIGIDA" && /iniciar sesión/.test(c.res.aviso ?? ""), `${c.res.estado}`);
    }

    // 13) Perfil personal intacto en todo el banco.
    const cambios = diferenciasHuella(huellaAntes, huella(canario.hogar));
    ok("perfil_personal:sin_cambios", cambios.length === 0, cambios.slice(0, 5).join(", "));
  } finally {
    await b.parar();
    rmSync(tmp, { recursive: true, force: true });
    rmSync(canario.hogar, { recursive: true, force: true });
  }
  const fallidas = comprobaciones.filter((c) => !c.ok).length;
  return {
    mutante, navegador: nav.nombre, aviso_navegador: nav.aviso ?? null, comprobaciones,
    aprobadas: comprobaciones.length - fallidas, fallidas, metricas, precision,
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const i = process.argv.indexOf("--mutante");
  const mutante = (i > 0 ? process.argv[i + 1] : "ninguno") as Mutante;
  const j = process.argv.indexOf("--salida");
  const inf = await ejecutarBateria(mutante);
  if (j > 0) writeFileSync(join(process.argv[j + 1], `bateria-${mutante}.json`), JSON.stringify(inf, null, 2) + "\n");
  for (const c of inf.comprobaciones.filter((c) => !c.ok)) console.log(`FALLA ${c.id} ${c.detalle}`);
  console.log(`navegador=${inf.navegador}${inf.aviso_navegador ? ` (${inf.aviso_navegador})` : ""} mutante=${mutante} ` +
    `aprobadas=${inf.aprobadas} fallidas=${inf.fallidas}`);
  process.exitCode = inf.fallidas === 0 ? 0 : 1;
}
