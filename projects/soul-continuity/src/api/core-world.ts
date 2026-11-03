/**
 * Mundo de producción de la API: la instantánea del núcleo traducida al contrato de la app.
 *
 * - Cada perfil de la instalación es un operador de la API.
 * - En cada petición se toma la última instantánea del operador (la refresca `serve` cada
 *   5 min); solo afirmaciones utilizables; id opaco por operador (`elementId`).
 * - Un elemento nuevo genera su evento (aviso) por la política de atención.
 * - Las correcciones de la app van al libro del núcleo: no vuelven aunque la fuente repita.
 */

import { createHash } from "node:crypto";
import { type Claim, isUsable, parseTs } from "../contract/claims.ts";
import type { AdapterStatusEntry, Snapshot } from "../contract/claims.ts";
import { type SoulConfig, elementId } from "../core/config.ts";
import type { Engine } from "../core/engine.ts";
import { type CtxMundo, type Elemento, ErrorApi, type Mundo, type Op, type SemillaOperador, type VistaAdaptadorSemilla } from "./server.ts";

const TIPO: Partial<Record<string, string>> = {
  meeting: "reunion", task_assigned: "tarea", review_request: "revision", awaiting_reply: "hilo_espera",
  document_comments: "documento", mention: "mencion", dated_commitment: "compromiso", web_page_change: "cambio",
};
const CATEGORIA: Record<string, string> = { reunion: "reunion_proxima", tarea: "vencimiento", documento: "documento_sin_leer", hilo_espera: "espera_respuesta" };
const MIN = 60_000;

/** D8: proyecto de una afirmación, por su referencia nativa (clave de Jira, repositorio de GitHub o Azure DevOps). */
export function proyectoDe(c: Claim): string | null {
  const r = c.source_refs[0];
  if (!r) return null;
  if (r.adapter === "jira") return /^([A-Z][A-Z0-9_]{0,19})-\d+$/.exec(r.ref)?.[1] ?? null;
  if (r.adapter === "github") return /^([^#]{1,100})#\d+$/.exec(r.ref)?.[1] ?? null;
  if (r.adapter === "azure-devops") return /^([^!]{1,100})!\d+$/.exec(r.ref)?.[1] ?? null;
  return null;
}
/** D8: personas de una afirmación (hoy, el remitente del último mensaje), con el correo en minúsculas. */
export function personasDe(c: Claim): string[] {
  const f = c.attrs?.last_from;
  return typeof f === "string" && f.includes("@") && f.length <= 254 ? [f.trim().toLowerCase()] : [];
}
const idDe = (pre: string, ref: string, v: string) => pre + createHash("sha256").update(`${ref}\u0000${v}`).digest("hex").slice(0, 16);
/** Solo el remitente con identidad autenticada (tenant o DKIM/DMARC, fuera de la web) dispara una alerta de persona. */
const autenticado = (c: Claim) => c.source_refs[0]?.route !== "web" && (c.attrs?.sender_auth === "tenant" || c.attrs?.sender_auth === "dkim_dmarc");

export function adapterView(id: string, s: AdapterStatusEntry): VistaAdaptadorSemilla {
  const ruta = s.route ?? (id.startsWith("m365-") ? "graph" : id === "web" ? "web" : "api");
  const v = (estado: string, motivo: string | null, alt: string | null = null) => ({ id, ruta, estado, motivo, alt });
  switch (s.status) {
    case "ok": return v("ok", null);
    case "no_consent": case "no_purpose": return v("sin_consentimiento", null);
    case "consent_revoked": return v("revocado", null);
    case "admin_consent_required": return v("desactivado", "requiere_consentimiento_admin", "web");
    case "token_expired": case "session_expired": return v("detenido", "sesion_caducada");
    case "recipe_disabled": return v("desactivado", "receta_desactivada");
    case "unavailable": return v("detenido", "sin_conexion", s.fallback === "web" || s.fallback === "manual" ? s.fallback : null);
    default: return v("detenido", "error");
  }
}

export interface CoreWorld extends Mundo {
  /** Conecta el servidor: las correcciones de la app pasan al libro del núcleo. */
  conectar(s: { alCorregir(f: (o: Op, id: string, tipo: string, t: number, dispositivo: string | null) => void | Promise<void>): void }): void;
}

export function coreWorld(opts: { cfg: SoulConfig; engine: Engine; stateDir: string }): CoreWorld {
  const { cfg, engine, stateDir } = opts;
  const keys = new Map<string, Map<string, string>>(); // operador → id opaco → clave
  const seen = new Map<string, string>(); // operador → versión (lectura + libro) ya aplicada

  /**
   * Versión de lo que ve el operador: cambia con una lectura nueva, con una corrección (p. ej.
   * `soul correct`) o con una purga de la caché sin lectura nueva (`soul revoke`).
   */
  function version(ref: string, snap: Snapshot): string {
    const libro = createHash("sha256").update(JSON.stringify(engine.ledger(stateDir, ref))).digest("hex");
    const contenido = createHash("sha256").update(JSON.stringify([snap.adapters, snap.claims.map((c) => [c.key, c.state])])).digest("hex");
    return `${snap.issued_at}|${libro}|${contenido}`;
  }

  function elemento(ref: string, c: Claim): Elemento | null {
    const tipo = TIPO[c.claim_type];
    if (!tipo || !isUsable(c)) return null;
    const id = elementId(ref, c.key);
    keys.get(ref)?.set(id, c.key);
    const observado = parseTs(c.observed_at) ?? 0;
    const proyecto = proyectoDe(c);
    return {
      id, tipo, titulo: c.title ?? tipo, proyecto: proyecto ? idDe("p", ref, proyecto) : null, personas: personasDe(c).map((x) => idDe("h", ref, x)), detalle: null,
      adaptador: c.source_refs[0].adapter, ruta: c.source_refs[0].route, dep: c.open && c.awaiting_operator,
      fecha: parseTs(c.due_at), nace: parseTs(c.event_at) ?? observado, observado, estado: c.state, sens: c.sensitivity,
      refs: c.source_refs.map((r) => r.ref), mio: false, noMio: false, fijo: true, validoHasta: parseTs(c.valid_until),
    };
  }

  function aplicar(ctx: CtxMundo | null, o: Op, snap: Snapshot, t: number) {
    const nuevos: Elemento[] = [];
    const vivos = new Set<string>();
    // «es mío» vive en el libro (restore con motivo es_mio): sobrevive a reiniciar el servicio.
    const mioLibro = new Set((engine.ledger(stateDir, o.ref) as { action?: string; reason?: string; key?: string }[])
      .filter((r) => r.action === "restore" && r.reason === "es_mio").map((r) => r.key));
    const autenticados = new Set<string>();
    const proyectos = new Map(o.d.proyectos.map((p) => [p.id, p.nombre]));
    const personas = new Map(o.d.personas.map((p) => [p.id, p.nombre]));
    for (const c of snap.claims) {
      const e = elemento(o.ref, c);
      if (!e) continue;
      vivos.add(e.id);
      const pr = proyectoDe(c);
      if (pr && e.proyecto) proyectos.set(e.proyecto, pr);
      personasDe(c).forEach((x, i) => personas.set(e.personas[i], x));
      if (autenticado(c)) autenticados.add(e.id);
      const prev = o.elementos.get(e.id);
      if (!prev) nuevos.push(e);
      o.elementos.set(e.id, { ...e, mio: prev?.mio ?? mioLibro.has(c.key), noMio: prev?.noMio ?? false });
    }
    for (const id of [...o.elementos.keys()]) if (!vivos.has(id)) o.elementos.delete(id);
    // Las listas de filtros solo crecen con lo leído (acotadas): un id que ya vio la app sigue resolviendo.
    o.d.proyectos = [...proyectos].slice(-200).map(([id, nombre]) => ({ id, nombre }));
    o.d.personas = [...personas].slice(-500).map(([id, nombre]) => ({ id, nombre }));
    o.d.adaptadores = Object.entries(snap.adapters).filter(([, s]) => s.status !== "not_configured").map(([k, s]) => adapterView(k, s));
    if (ctx) {
      for (const e of nuevos) {
        // Regla del perfil por remitente: alerta si el remitente está autenticado; si no, aviso (nunca alerta por `From`).
        const regla = o.alertas.find((r) => (r.tipo === "persona" && e.personas.includes(r.objetivo)) || (r.tipo === "proyecto" && e.proyecto === r.objetivo));
        if (regla) { ctx.evento(o, { tipo: "alerta", regla, efectiva: autenticados.has(e.id) || regla.tipo === "proyecto" ? "alerta" : "aviso", ids: [e.id] }, t); continue; }
        const cat = CATEGORIA[e.tipo];
        if (cat) ctx.evento(o, { tipo: "aviso", categoria: cat, ids: [e.id], programar: cat === "reunion_proxima" && e.fecha && e.fecha - 15 * MIN > t ? e.fecha - 15 * MIN : null }, t);
      }
    }
  }

  return {
    semillas(): SemillaOperador[] {
      return Object.values(cfg.profiles).map((p) => {
        const ref = p.operator.ref;
        keys.set(ref, new Map());
        const semilla: SemillaOperador = {
          ref, nivel: cfg.detail.level, nivelMax: cfg.detail.max, proyectos: [], personas: [], elementos: [], adaptadores: [],
          avisos: { activos: ["reunion_proxima", "vencimiento", "documento_sin_leer", "espera_respuesta"], resumenInicio: null, resumenCierre: null, max: 5, ventanaMin: 60, tope: 3 },
          // D8: las reglas del perfil (`alert_rules`, por remitente) llegan a la API como reglas de persona.
          alertas: (p.alert_rules ?? []).filter((r) => typeof r.sender === "string" && r.sender.includes("@")).map((r) => ({
            id: /^[A-Za-z0-9_.-]{1,64}$/.test(r.id) ? r.id : idDe("r", ref, r.id), tipo: "persona", objetivo: idDe("h", ref, r.sender.trim().toLowerCase()),
            palabra: null, modos: ["DISPONIBLE", "FOCO", "DESCANSO", "FUERA"],
          })),
        };
        const snap = engine.lastSnapshot(stateDir, ref);
        if (snap) {
          const fake = { ref, d: semilla, elementos: new Map<string, Elemento>() } as unknown as Op;
          aplicar(null, fake, snap, parseTs(snap.issued_at) ?? 0);
          semilla.elementos = [...fake.elementos.values()];
          seen.set(ref, version(ref, snap));
        }
        return semilla;
      });
    },

    refrescar(ctx: CtxMundo, o: Op, t: number) {
      const snap = engine.lastSnapshot(stateDir, o.ref);
      if (!snap) return;
      const v = version(o.ref, snap);
      if (seen.get(o.ref) === v) return;
      seen.set(o.ref, v);
      aplicar(ctx, o, snap, t);
    },

    seleccion(o: Op, pregunta: string, t: number, rango) {
      // TTL de cada afirmación evaluado en el instante de la petición, no en el de la lectura.
      const snap = engine.cachedSnapshot(stateDir, o.ref, new Date(t).toISOString());
      if (!snap || (parseTs(snap.expires_at) ?? 0) <= t) return new Set<string>();
      const install = { id: cfg.installation_id, operator: { ref: o.ref, identities: { emails: [] } }, sources: [] };
      const q = pregunta.toUpperCase() as "Q1" | "Q2" | "Q3" | "Q4";
      let previous: Snapshot | undefined;
      let actual = snap;
      if (q === "Q3") {
        // Como `soul q3 --since`: diferencia entre la lectura vigente en `desde` y la actual (o la
        // vigente en `hasta`). D6: sin ninguna lectura anterior a `desde`, la base es la primera
        // guardada («qué cambió desde que Soul empezó a leer»), no un 400 indistinguible de un error.
        if (rango?.desde == null) throw new ErrorApi(400, "INVALID_INPUT");
        previous = engine.snapshotAt(stateDir, o.ref, new Date(rango.desde).toISOString())
          ?? engine.firstSnapshot(stateDir, o.ref) ?? snap;
        if (rango.hasta != null && rango.hasta < t) {
          const h = engine.snapshotAt(stateDir, o.ref, new Date(rango.hasta).toISOString());
          if (h) actual = h;
        }
      }
      const a = engine.answer(actual, { q, detail: "titulos", previous }, { install, now: new Date(t).toISOString() });
      // `removed` no tiene elemento vivo que servir (el contrato de la app no lo representa todavía).
      return new Set(a.items.filter((it) => it.change !== "removed").map((it) => elementId(o.ref, it.key)));
    },

    frescura(o: Op, t: number) {
      const snap = engine.lastSnapshot(stateDir, o.ref);
      if (!snap) return { ultimaLectura: null, obsoleto: true };
      const NO_RESPONDE = new Set(["unavailable", "error", "token_expired", "session_expired", "recipe_disabled"]);
      const failed = Object.values(snap.adapters).some((a) => NO_RESPONDE.has(a.status));
      return { ultimaLectura: parseTs(snap.issued_at), obsoleto: (parseTs(snap.expires_at) ?? 0) <= t || failed };
    },

    conectar(s) {
      s.alCorregir(async (o, id, tipo, t, dispositivo) => {
        const key = keys.get(o.ref)?.get(id);
        // Sin clave no hay a qué apuntar en el libro: no se confirma una corrección que no se guardaría.
        if (!key) throw new ErrorApi(503, "UNAVAILABLE");
        const install = { id: cfg.installation_id, operator: { ref: o.ref, identities: { emails: [] } }, sources: [] };
        // Fallo al escribir el libro: 503 a la app y aviso sin datos de trabajo; el servicio sigue.
        await engine.correct({ install, stateDir, now: new Date(t).toISOString(), key, action: tipo === "es_mio" ? "restore" : "revoke", reason: tipo, device: dispositivo })
          .catch((e: Error) => { process.stderr.write(`soul api: corrección no persistida (${e.name})\n`); throw new ErrorApi(503, "UNAVAILABLE"); });
      });
    },
  };
}
