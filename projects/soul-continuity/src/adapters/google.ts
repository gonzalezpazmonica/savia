/**
 * Adaptador de Google Workspace por API, de solo lectura (SE-490).
 *
 * - Gmail con `gmail.metadata`: hilos con cabeceras From/To/Cc/Subject y
 *   Authentication-Results; nunca cuerpos ni `snippet`. Regla de «esperando»
 *   común con Microsoft 365. Ese permiso no admite `q`: se recorren los hilos más
 *   recientes hasta `max_threads` (por defecto 300). Leer menos hilos solo omite
 *   esperas antiguas; cada hilo leído se lee entero, así que no inventa ninguna.
 * - Calendar (`calendar.readonly`): calendario `primary`, de ayer a 14 días.
 * - Drive (`drive.readonly`): ficheros compartidos conmigo con comentarios sin resolver.
 * - Tasks (`tasks.readonly`, opcional con `params.tasks: true`): mis tareas con fecha
 *   y sin completar como compromisos con fecha; nunca sus notas.
 *
 * Paginación con `pageToken` y el mismo tope de páginas. Un 403 por cuota se trata
 * como limitación (`unavailable`), no como permiso.
 */

import { type Claim, iso } from "../contract/claims.ts";
import type { AdapterContext, SourceAdapter, TransportResponse } from "../contract/adapter.ts";
import { type Msg, awaitingReply, senderAuth } from "./awaiting.ts";
import { DAY, DEFAULT_MAX_PAGES, type J, Stop, adapter, check, claim, nowMs, safeRef, toIso, token } from "./common.ts";
import { DESCRIPTORS } from "./descriptors.ts";

export interface GoogleOptions {
  maxPages?: number;
}

const META_HEADERS = ["From", "To", "Cc", "Subject", "Authentication-Results"];

function addrList(v: string): string[] {
  return v.split(",").map((s) => (/<([^>]+)>/.exec(s)?.[1] ?? s).trim().toLowerCase()).filter((s) => s.includes("@"));
}

function googleCheck(r: TransportResponse, label: string): J {
  if (r.status === 403) {
    const reasons = JSON.stringify((r.body as J)?.error?.errors ?? (r.body as J)?.error ?? "");
    if (/rateLimitExceeded|userRateLimitExceeded|quotaExceeded/i.test(reasons)) {
      throw new Stop("unavailable", `${label} limita las peticiones; se reintentará en la próxima lectura.`);
    }
  }
  return check(r, label, { forbiddenIsConsent: true });
}

export function makeGoogleAdapter(o: GoogleOptions = {}): SourceAdapter {
  const maxPages = o.maxPages ?? DEFAULT_MAX_PAGES;

  return adapter("google-workspace", async (ctx: AdapterContext) => {
    const withTasks = ctx.params.tasks === true;
    const [base, plusTasks] = DESCRIPTORS["google-workspace"].scopes;
    const tok = await token(ctx, "google", withTasks ? plusTasks : base);
    const get = async (url: string, label: string) =>
      googleCheck(await ctx.transport.request({ service: "google", method: "GET", url, headers: { Authorization: `Bearer ${tok}` } }), label);
    /** Recorre `pageToken` hasta el tope; falla cerrado si quedan páginas. */
    const all = async (url: string, key: string, label: string, cap = Number.POSITIVE_INFINITY): Promise<J[]> => {
      const out: J[] = [];
      let pageToken: string | undefined;
      for (let i = 0; ; i++) {
        if (i >= maxPages) throw new Stop("unavailable", `${label}: supera el tope de ${maxPages} páginas; no se dan datos incompletos.`);
        const sep = url.includes("?") ? "&" : "?";
        const b = await get(pageToken ? `${url}${sep}pageToken=${encodeURIComponent(pageToken)}` : url, label);
        if (Array.isArray(b[key])) out.push(...b[key]);
        if (out.length >= cap) return out.slice(0, cap);
        pageToken = typeof b.nextPageToken === "string" && b.nextPageToken ? b.nextPageToken : undefined;
        if (!pageToken) return out;
      }
    };

    const now = nowMs(ctx);
    const out: Claim[] = [];

    // --- Gmail (metadatos)
    const maxThreads = Number.isInteger(ctx.params.max_threads) && (ctx.params.max_threads as number) > 0 ? (ctx.params.max_threads as number) : 300;
    const threads = await all("/gmail/v1/users/me/threads?maxResults=100", "threads", "Gmail", maxThreads);
    const hdrs = META_HEADERS.map((h) => `metadataHeaders=${encodeURIComponent(h)}`).join("&");
    const msgs: Msg[] = [];
    for (const t of threads) {
      const tid = safeRef(t?.id);
      if (!tid) continue;
      const th = await get(`/gmail/v1/users/me/threads/${encodeURIComponent(tid)}?format=metadata&${hdrs}`, "Gmail");
      for (const x of Array.isArray(th.messages) ? th.messages : []) {
        const headers: { name: string; value: string }[] = Array.isArray(x?.payload?.headers) ? x.payload.headers : [];
        const h = (n: string) => headers.filter((y) => String(y?.name).toLowerCase() === n.toLowerCase()).map((y) => String(y.value)).join(", ");
        const from = addrList(h("From"))[0] ?? "";
        const id = safeRef(x?.id);
        const at = Number(x?.internalDate);
        if (!id || !Number.isFinite(at)) continue;
        msgs.push({
          id, conv: tid, from, to: addrList(h("To")), cc: addrList(h("Cc")), at: iso(at),
          sent: Array.isArray(x?.labelIds) && x.labelIds.includes("SENT"), subject: h("Subject"),
          // En Google no hay «mismo inquilino» verificable: solo DKIM/DMARC.
          auth: senderAuth(from, headers.filter((y) => String(y?.name).toLowerCase() === "authentication-results"), ""),
        });
      }
    }
    for (const last of awaitingReply(msgs, ctx.operator.identities.emails)) {
      out.push(claim(ctx, "google-workspace", "awaiting_reply", `${last.conv}@${last.id}`, {
        title: last.subject, event_at: last.at, awaiting_operator: true,
        attrs: { last_from: last.from, sender_auth: last.auth },
      }));
    }

    // --- Calendar
    const win = `timeMin=${encodeURIComponent(iso(now - DAY))}&timeMax=${encodeURIComponent(iso(now + 14 * DAY))}`;
    for (const e of await all(`/calendar/v3/calendars/primary/events?singleEvents=true&orderBy=startTime&maxResults=250&${win}`, "items", "Google Calendar")) {
      const id = safeRef(e?.id);
      const start = toIso(e?.start?.dateTime) ?? (typeof e?.start?.date === "string" ? toIso(`${e.start.date}T00:00:00Z`) : null);
      if (!id || !start || e?.status === "cancelled") continue;
      const self = (Array.isArray(e?.attendees) ? e.attendees : []).find((a: J) => a?.self === true);
      out.push(claim(ctx, "google-workspace", "meeting", id, { title: e?.summary, due_at: start, open: self?.responseStatus !== "declined" }));
    }

    // --- Drive
    const q = encodeURIComponent("sharedWithMe = true and trashed = false");
    for (const f of await all(`/drive/v3/files?q=${q}&pageSize=100&fields=nextPageToken,files(id,name)`, "files", "Google Drive")) {
      const id = safeRef(f?.id);
      if (!id) continue;
      const cs = await all(`/drive/v3/files/${encodeURIComponent(id)}/comments?pageSize=100&fields=nextPageToken,comments(id,createdTime,resolved)`, "comments", "Google Drive");
      const open = cs.filter((c) => c?.resolved !== true).map((c) => toIso(c?.createdTime)).filter((t): t is string => t !== null);
      if (!open.length) continue;
      out.push(claim(ctx, "google-workspace", "document_comments", id, { title: f?.name, event_at: open.sort().at(-1) ?? null, attrs: { unresolved: open.length } }));
    }

    // --- Tasks (opcional)
    if (withTasks) {
      for (const l of await all("/tasks/v1/users/@me/lists?maxResults=100", "items", "Google Tasks")) {
        const lid = safeRef(l?.id);
        if (!lid) continue;
        const ts = await all(`/tasks/v1/lists/${encodeURIComponent(lid)}/tasks?showCompleted=false&showHidden=false&maxResults=100`, "items", "Google Tasks");
        for (const t of ts) {
          const id = safeRef(t?.id);
          const due = toIso(t?.due);
          if (!id || !due || t?.status === "completed") continue;
          out.push(claim(ctx, "google-workspace", "dated_commitment", id, { title: t?.title, due_at: due }));
        }
      }
    }
    return out;
  });
}
