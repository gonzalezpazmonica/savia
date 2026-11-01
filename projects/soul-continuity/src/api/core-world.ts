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
import type { CtxMundo, Elemento, Mundo, Op, SemillaOperador, VistaAdaptadorSemilla } from "./server.ts";

const TIPO: Partial<Record<string, string>> = {
  meeting: "reunion", task_assigned: "tarea", review_request: "revision", awaiting_reply: "hilo_espera",
  document_comments: "documento", mention: "mencion", dated_commitment: "compromiso", web_page_change: "cambio",
};
const CATEGORIA: Record<string, string> = { reunion: "reunion_proxima", tarea: "vencimiento", documento: "documento_sin_leer", hilo_espera: "espera_respuesta" };
const MIN = 60_000;

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
  conectar(s: { alCorregir(f: (o: Op, id: string, tipo: string, t: number) => void): void }): void;
}

export function coreWorld(opts: { cfg: SoulConfig; engine: Engine; stateDir: string }): CoreWorld {
  const { cfg, engine, stateDir } = opts;
  const keys = new Map<string, Map<string, string>>(); // operador → id opaco → clave
  const seen = new Map<string, string>(); // operador → versión (lectura + libro) ya aplicada

  /** Versión de lo que ve el operador: cambia con una lectura nueva o con una corrección (p. ej. `soul correct`). */
  function version(ref: string, snap: Snapshot): string {
    const libro = createHash("sha256").update(JSON.stringify(engine.ledger(stateDir, ref))).digest("hex");
    return `${snap.issued_at}|${libro}`;
  }

  function elemento(ref: string, c: Claim): Elemento | null {
    const tipo = TIPO[c.claim_type];
    if (!tipo || !isUsable(c)) return null;
    const id = elementId(ref, c.key);
    keys.get(ref)?.set(id, c.key);
    const observado = parseTs(c.observed_at) ?? 0;
    return {
      id, tipo, titulo: c.title ?? tipo, proyecto: null, personas: [], detalle: null,
      adaptador: c.source_refs[0].adapter, ruta: c.source_refs[0].route, dep: c.open && c.awaiting_operator,
      fecha: parseTs(c.due_at), nace: parseTs(c.event_at) ?? observado, observado, estado: c.state, sens: c.sensitivity,
      refs: c.source_refs.map((r) => r.ref), mio: false, noMio: false, fijo: true, validoHasta: parseTs(c.valid_until),
    };
  }

  function aplicar(ctx: CtxMundo | null, o: Op, snap: Snapshot, t: number) {
    const nuevos: Elemento[] = [];
    const vivos = new Set<string>();
    for (const c of snap.claims) {
      const e = elemento(o.ref, c);
      if (!e) continue;
      vivos.add(e.id);
      const prev = o.elementos.get(e.id);
      if (!prev) nuevos.push(e);
      o.elementos.set(e.id, { ...e, mio: prev?.mio ?? false, noMio: prev?.noMio ?? false });
    }
    for (const id of [...o.elementos.keys()]) if (!vivos.has(id)) o.elementos.delete(id);
    o.d.adaptadores = Object.entries(snap.adapters).filter(([, s]) => s.status !== "not_configured").map(([k, s]) => adapterView(k, s));
    if (ctx) {
      for (const e of nuevos) {
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
          alertas: [],
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

    seleccion(o: Op, pregunta: string, t: number) {
      // TTL de cada afirmación evaluado en el instante de la petición, no en el de la lectura.
      const snap = engine.cachedSnapshot(stateDir, o.ref, new Date(t).toISOString());
      if (!snap || (parseTs(snap.expires_at) ?? 0) <= t) return new Set<string>();
      const install = { id: cfg.installation_id, operator: { ref: o.ref, identities: { emails: [] } }, sources: [] };
      const q = pregunta.toUpperCase() as "Q1" | "Q2" | "Q4";
      const a = engine.answer(snap, { q, detail: "titulos" }, { install, now: new Date(t).toISOString() });
      return new Set(a.items.map((it) => elementId(o.ref, it.key)));
    },

    frescura(o: Op, t: number) {
      const snap = engine.lastSnapshot(stateDir, o.ref);
      if (!snap) return { ultimaLectura: null, obsoleto: true };
      const NO_RESPONDE = new Set(["unavailable", "error", "token_expired", "session_expired", "recipe_disabled"]);
      const failed = Object.values(snap.adapters).some((a) => NO_RESPONDE.has(a.status));
      return { ultimaLectura: parseTs(snap.issued_at), obsoleto: (parseTs(snap.expires_at) ?? 0) <= t || failed };
    },

    conectar(s) {
      s.alCorregir((o, id, tipo, t) => {
        const key = keys.get(o.ref)?.get(id);
        if (!key) return;
        const install = { id: cfg.installation_id, operator: { ref: o.ref, identities: { emails: [] } }, sources: [] };
        // Fallo al escribir el libro: se informa sin tumbar el servicio (y sin datos de trabajo en el log).
        engine.correct({ install, stateDir, now: new Date(t).toISOString(), key, action: tipo === "es_mio" ? "restore" : "revoke", reason: tipo })
          .catch((e: Error) => process.stderr.write(`soul api: corrección no persistida (${e.name})\n`));
      });
    },
  };
}
