/**
 * Adaptadores de Microsoft 365 por Graph delegado, de solo lectura (SE-490).
 *
 * - `m365-mail`: «esperando mi respuesta» solo con metadatos (bandeja de entrada y
 *   enviados del mismo buzón) y correos marcados con fecha. Con caché, usa delta
 *   queries por carpeta con tope de páginas por lectura: si la ronda no termina,
 *   guarda el enlace de continuación y no responde (unavailable) hasta completarla;
 *   un deltatoken caducado (410) resincroniza desde cero una vez. Sin caché, lista
 *   con paginación y el mismo tope.
 * - `m365-calendar`: `calendarView` del calendario propio, de ayer a 14 días, en UTC.
 * - `m365-teams`: menciones de los últimos 7 días sin mensaje mío posterior en el chat.
 * - `m365-files`: documentos compartidos conmigo con comentarios sin resolver.
 *
 * Siempre `$select` de metadatos; los cuerpos que la API devuelva igualmente se
 * descartan campo a campo. Nunca lee buzones ni calendarios de otras personas.
 * Un 403 se trata como permiso no concedido: fail-closed y ruta web.
 */

import { type Claim, iso } from "../contract/claims.ts";
import type { AdapterContext, SourceAdapter } from "../contract/adapter.ts";
import { type Msg, awaitingReply, senderAuth } from "./awaiting.ts";
import {
  DAY, DEFAULT_MAX_PAGES, type J, Stop, adapter, check, claim, domainOf, emailsOf, nowMs, odataAll, safeRef,
  sameOrigin, toIso, token,
} from "./common.ts";
import type { DeltaCache, DeltaState, Meta } from "./delta-cache.ts";

export interface M365Options {
  /** Caché de sincronización; sin ella, cada lectura lista completo. */
  cache?: DeltaCache;
  /** Tope de páginas por colección y lectura. */
  maxPages?: number;
  /** Elementos por página pedidos con `Prefer: odata.maxpagesize`. */
  pageSize?: number;
}

const G = { forbiddenIsConsent: true };
const MAIL_FIELDS = "id,conversationId,subject,from,toRecipients,ccRecipients,receivedDateTime,sentDateTime,flag,webLink";
const FOLDERS = ["inbox", "sentitems"] as const;

function addrs(list: unknown): string[] {
  return Array.isArray(list) ? list.map((r: J) => String(r?.emailAddress?.address ?? "")).filter(Boolean) : [];
}

/** Metadatos mínimos de un mensaje: lo único que se guarda en caché. */
function mailMeta(x: J, myDomain: string, headers: boolean, authserv: string[] | undefined, sent: boolean): Meta | null {
  const id = safeRef(x?.id);
  const conv = typeof x?.conversationId === "string" ? x.conversationId : null;
  if (!id || !conv) return null;
  // Un enviado mío sin fecha no puede cerrar su hilo: descartarlo dejaría la espera
  // abierta (error en la dirección peligrosa). Se falla cerrado.
  const at = sent ? toIso(x?.sentDateTime) ?? toIso(x?.receivedDateTime) : toIso(x?.receivedDateTime);
  if (sent && !at) throw new Stop("error", "Graph (correo): un mensaje enviado no trae fecha legible; no se da una espera que podría estar cerrada.");
  const from = String(x?.from?.emailAddress?.address ?? "");
  const flagged = x?.flag?.flagStatus === "flagged" ? toIso(x?.flag?.dueDateTime?.dateTime, x?.flag?.dueDateTime?.timeZone === "UTC") : null;
  return {
    id, conv, from,
    to: addrs(x?.toRecipients),
    cc: addrs(x?.ccRecipients),
    at: at ?? "",
    subject: typeof x?.subject === "string" ? x.subject : "",
    auth: headers ? senderAuth(from, x?.internetMessageHeaders, myDomain, authserv) : "unknown",
    flag_due: flagged,
  };
}

function isResync(status: number, body: J): boolean {
  if (status === 410) return true;
  const code = String(body?.error?.code ?? "");
  return status === 400 && /syncStateNotFound|resyncRequired|syncStateInvalid/i.test(code);
}

async function deltaFolder(ctx: AdapterContext, tok: string, folder: string, select: string, toMeta: (x: J) => Meta | null,
  cache: DeltaCache, maxPages: number, pageSize: number, variant: string): Promise<Record<string, Meta>> {
  // La identidad del remitente se calcula al guardar: cambiar su configuración es otra caché.
  const key = `${folder}|${select}|${variant}`;
  const initial = `/v1.0/me/mailFolders/${folder}/messages/delta?$select=${select}`;
  const saved = await cache.load(ctx.operator.ref, "m365-mail", key);
  let state: DeltaState = saved ?? { link: null, complete: false, items: {} };
  let url = initial;
  if (state.link) {
    // El enlace guardado se revalida: una caché manipulada no puede llevarse el token.
    try {
      url = sameOrigin(state.link, initial, "Graph (correo)");
    } catch {
      state = { link: null, complete: false, items: {} };
    }
  }
  let resynced = false;
  for (let pages = 0; ; ) {
    if (pages >= maxPages) {
      await cache.save(ctx.operator.ref, "m365-mail", key, { ...state, link: url, complete: false });
      throw new Stop("unavailable", `Sincronización del correo (${folder}) en curso: supera ${maxPages} páginas por lectura; continúa en la siguiente.`);
    }
    const r = await ctx.transport.request({
      service: "graph", method: "GET", url,
      headers: { Authorization: `Bearer ${tok}`, Prefer: `odata.maxpagesize=${pageSize}` },
    });
    if (isResync(r.status, r.body)) {
      if (resynced) throw new Stop("unavailable", "Graph pide resincronizar el correo otra vez; se reintentará.");
      resynced = true;
      state = { link: null, complete: false, items: {} };
      url = initial;
      continue;
    }
    const b = check(r, "Graph (correo)", G);
    pages++;
    for (const x of Array.isArray(b.value) ? b.value : []) {
      const id = safeRef(x?.id);
      if (!id) continue;
      const m = x["@removed"] ? null : toMeta(x);
      // Un cambio que no se puede leer no deja los metadatos viejos: se retira.
      if (m) state.items[id] = m;
      else delete state.items[id];
    }
    const next = b["@odata.nextLink"];
    const delta = b["@odata.deltaLink"];
    if (typeof next === "string") {
      url = sameOrigin(next, initial, "Graph (correo)");
      continue;
    }
    if (typeof delta !== "string") throw new Stop("error", "Graph (correo): respuesta delta sin enlace de continuación.");
    state = { link: sameOrigin(delta, initial, "Graph (correo)"), complete: true, items: state.items };
    await cache.save(ctx.operator.ref, "m365-mail", key, state);
    return state.items;
  }
}

export function makeM365Adapters(o: M365Options = {}): Record<"m365-mail" | "m365-calendar" | "m365-teams" | "m365-files", SourceAdapter> {
  const maxPages = o.maxPages ?? DEFAULT_MAX_PAGES;
  const pageSize = o.pageSize ?? 50;

  const mail = adapter("m365-mail", async (ctx) => {
    const headers = ctx.params.sender_identity !== false;
    const tok = await token(ctx, "graph", [headers ? "Mail.Read" : "Mail.ReadBasic"]);
    const select = headers ? `${MAIL_FIELDS},internetMessageHeaders` : MAIL_FIELDS;
    // Dominio del inquilino: explícito si se configura; si no, el de la primera identidad.
    const td = ctx.params.tenant_domain;
    if (td !== undefined && (typeof td !== "string" || !/^[a-z0-9-]+(\.[a-z0-9-]+)+$/i.test(td))) throw new Stop("error", "params.tenant_domain inválido.");
    const dom = typeof td === "string" ? td.toLowerCase() : domainOf(ctx.operator.identities.emails[0] ?? "");
    // `authserv-id` aceptados (pasarela de terceros o híbrido delante de Exchange Online).
    const as = ctx.params.authserv_ids;
    if (as !== undefined && (!Array.isArray(as) || !as.length || !as.every((v) => typeof v === "string" && /^[a-z0-9.-]+$/i.test(v)))) {
      throw new Stop("error", "params.authserv_ids inválido.");
    }
    const authserv = as as string[] | undefined;
    const toMeta = (folder: string) => (x: J) => mailMeta(x, dom, headers, authserv, folder === "sentitems");
    const variant = `${dom}|${(authserv ?? []).map((v) => v.toLowerCase()).sort().join(",")}`;
    const msgs: Msg[] = [];
    const out: Claim[] = [];
    for (const folder of FOLDERS) {
      let metas: Meta[];
      if (o.cache) metas = Object.values(await deltaFolder(ctx, tok, folder, select, toMeta(folder), o.cache, maxPages, pageSize, variant));
      else {
        const items = await odataAll(ctx, "graph", tok, `/v1.0/me/mailFolders/${folder}/messages?$top=${pageSize}&$select=${select}`, "Graph (correo)", { ...G, maxPages });
        metas = items.map(toMeta(folder)).filter((m): m is Meta => m !== null);
      }
      for (const m of metas) {
        msgs.push({
          id: String(m.id), conv: String(m.conv), from: String(m.from), to: m.to as string[], cc: m.cc as string[],
          at: String(m.at), sent: folder === "sentitems", subject: String(m.subject), auth: m.auth as Msg["auth"],
        });
        if (folder === "inbox" && typeof m.flag_due === "string") {
          out.push(claim(ctx, "m365-mail", "dated_commitment", String(m.id), { title: String(m.subject), due_at: m.flag_due }));
        }
      }
    }
    for (const last of awaitingReply(msgs, ctx.operator.identities.emails)) {
      const ref = `${last.conv}@${last.id}`;
      if (!safeRef(ref)) continue;
      out.push(claim(ctx, "m365-mail", "awaiting_reply", ref, {
        title: last.subject, event_at: last.at, awaiting_operator: true,
        attrs: { last_from: last.from.toLowerCase(), sender_auth: last.auth },
      }));
    }
    return out;
  });

  const calendar = adapter("m365-calendar", async (ctx) => {
    const tok = await token(ctx, "graph", ["Calendars.ReadBasic"]);
    const now = nowMs(ctx);
    const url = `/v1.0/me/calendarView?startDateTime=${iso(now - DAY)}&endDateTime=${iso(now + 14 * DAY)}`
      + `&$top=${pageSize}&$select=id,subject,start,isCancelled,responseStatus,webLink`;
    const evs = await odataAll(ctx, "graph", tok, url, "Graph (calendario)", { ...G, maxPages, headers: { Prefer: 'outlook.timezone="UTC"' } });
    const out: Claim[] = [];
    for (const e of evs) {
      const id = safeRef(e?.id);
      const start = toIso(e?.start?.dateTime, e?.start?.timeZone === "UTC");
      if (!id || !start || e?.isCancelled === true) continue;
      out.push(claim(ctx, "m365-calendar", "meeting", id, {
        title: e?.subject, due_at: start, open: e?.responseStatus?.response !== "declined",
      }));
    }
    return out;
  });

  const teams = adapter("m365-teams", async (ctx) => {
    const tok = await token(ctx, "graph", ["Chat.Read", "User.Read"]);
    const now = nowMs(ctx);
    // Graph identifica a las personas en Teams por su id de Entra, no por el correo.
    // Sin `m365_user_id` se resuelve con `/me`; si tampoco se puede, se falla cerrado:
    // comparar solo correos daría «ok» con cero menciones contra Graph real.
    const me = emailsOf(ctx);
    let uid = typeof ctx.params.m365_user_id === "string" && ctx.params.m365_user_id ? ctx.params.m365_user_id : null;
    if (!uid) {
      const r = await ctx.transport.request({ service: "graph", method: "GET", url: "/v1.0/me?$select=id", headers: { Authorization: `Bearer ${tok}` } });
      const id = r.status === 200 ? (r.body as J)?.id : undefined;
      if (typeof id !== "string" || !id) {
        if (r.status === 401) check(r, "Graph (Teams)", G);
        throw new Stop("error", "Graph (Teams): no se pudo obtener el id de Entra con /me (hace falta User.Read) y no hay params.m365_user_id; sin él no se detectan menciones.");
      }
      uid = id;
    }
    me.add(uid.toLowerCase());
    const isMe = (v: unknown) => typeof v === "string" && me.has(v.toLowerCase());
    const out: Claim[] = [];
    for (const c of await odataAll(ctx, "graph", tok, `/v1.0/me/chats?$top=50`, "Graph (Teams)", { ...G, maxPages })) {
      const chatId = typeof c?.id === "string" ? c.id : null;
      if (!chatId) continue;
      // Mensajes por fecha de creación, del más reciente al más antiguo (por defecto Graph
      // ordena por última modificación y un mensaje viejo editado cortaría la lectura):
      // se para al salir de la ventana de 7 días. Superar el tope de páginas dentro de la
      // ventana falla cerrado, como el resto de colecciones.
      let url: string | undefined = `/v1.0/me/chats/${encodeURIComponent(chatId)}/messages?$top=50&$orderby=${encodeURIComponent("createdDateTime desc")}`;
      const first = url;
      let mineAfter: number | null = null;
      for (let pg = 0; url; pg++) {
        if (pg >= maxPages) throw new Stop("unavailable", `Graph (Teams): supera el tope de ${maxPages} páginas en un chat; no se dan datos incompletos.`);
        const b = check(await ctx.transport.request({ service: "graph", method: "GET", url, headers: { Authorization: `Bearer ${tok}` } }), "Graph (Teams)", G);
        const items = (Array.isArray(b.value) ? b.value : []).map((x: J) => ({ x, t: Date.parse(String(x?.createdDateTime)) }))
          .filter((y: { t: number }) => Number.isFinite(y.t)).sort((a: { t: number }, z: { t: number }) => z.t - a.t);
        let old = false;
        for (const { x, t } of items) {
          if (t < now - 7 * DAY) { old = true; break; }
          // Un mensaje borrado ni pide respuesta ni cuenta como respuesta mía.
          if (x?.deletedDateTime != null) continue;
          if (isMe(x?.from?.user?.id)) { mineAfter = Math.max(mineAfter ?? t, t); continue; }
          const mentioned = (Array.isArray(x?.mentions) ? x.mentions : []).some((m: J) => isMe(m?.mentioned?.user?.id));
          const id = safeRef(x?.id);
          if (!mentioned || !id || (mineAfter !== null && mineAfter > t)) continue;
          out.push(claim(ctx, "m365-teams", "mention", id, { title: c?.topic, event_at: iso(t), awaiting_operator: true }));
        }
        const next = b["@odata.nextLink"];
        url = !old && typeof next === "string" ? sameOrigin(next, first, "Graph (Teams)") : undefined;
      }
    }
    return out;
  });

  const files = adapter("m365-files", async (ctx) => {
    const tok = await token(ctx, "graph", ["Files.Read.All"]);
    const out: Claim[] = [];
    for (const f of await odataAll(ctx, "graph", tok, "/v1.0/me/drive/sharedWithMe", "Graph (ficheros)", { ...G, maxPages })) {
      const id = safeRef(f?.id);
      const drive = safeRef(f?.remoteItem?.parentReference?.driveId);
      if (!id || !drive) continue;
      const cs = await odataAll(ctx, "graph", tok, `/v1.0/drives/${encodeURIComponent(drive)}/items/${encodeURIComponent(id)}/comments`, "Graph (comentarios)", { ...G, maxPages });
      const open = cs.filter((c) => c?.resolved !== true).map((c) => toIso(c?.createdDateTime)).filter((t): t is string => t !== null);
      if (!open.length) continue;
      out.push(claim(ctx, "m365-files", "document_comments", id, { title: f?.name, event_at: open.sort().at(-1) ?? null, attrs: { unresolved: open.length } }));
    }
    return out;
  });

  return { "m365-mail": mail, "m365-calendar": calendar, "m365-teams": teams, "m365-files": files };
}
