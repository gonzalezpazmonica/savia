/**
 * Adaptadores de referencia: lo mínimo para cumplir CONTRATO.md contra los dobles.
 * No son el producto: sirven para demostrar que el runner distingue una
 * implementación correcta de sus mutantes.
 */

import { type Claim, type ClaimType, type Route, type SenderAuth, claimKey, cleanText, iso, parseTs } from "../../../src/contract/claims.ts";
import {
  type AdapterContext, type AdapterResult, type AdapterStatus, CredentialError, type SourceAdapter,
  type TransportResponse,
} from "../../../src/contract/adapter.ts";
import type { Mutations } from "./engine.ts";

type J = any; // respuestas JSON de las fuentes
const DAY = 86_400_000;

class Stop extends Error {
  readonly status: Exclude<AdapterStatus, "ok">;
  readonly fallback: Route | "manual" | null;
  constructor(status: Exclude<AdapterStatus, "ok">, msg: string, fallback: Route | "manual" | null = null) {
    super(msg);
    this.status = status;
    this.fallback = fallback;
  }
}

function base(ctx: AdapterContext, adapter: string, type: ClaimType, ref: string, over: Partial<Claim>): Claim {
  const now = parseTs(ctx.now) as number;
  const title = cleanText(over.title);
  return {
    key: claimKey(adapter, type, ref),
    claim_type: type,
    state: "OBSERVED",
    source_refs: [{ adapter, route: ctx.route, ref }],
    sensitivity: ctx.sensitivity,
    observed_at: ctx.now,
    valid_until: iso(now + 3600_000),
    event_at: null,
    due_at: null,
    open: true,
    awaiting_operator: false,
    attrs: {},
    ...over,
    title,
    untrusted_text: title !== null ? true : undefined,
  };
}

async function token(ctx: AdapterContext, service: string, scopes: string[], route: Route): Promise<string> {
  try {
    return await ctx.credentials.acquire(service, scopes);
  } catch (e) {
    if (e instanceof CredentialError && e.code === "admin_consent_required") {
      throw new Stop("admin_consent_required",
        "El inquilino exige consentimiento de administración para estos permisos. No se activa la ruta Graph; puedes activar la ruta web.",
        route === "graph" ? "web" : "manual");
    }
    if (e instanceof CredentialError && e.code === "session_expired") throw new Stop("session_expired", "Vuelve a iniciar sesión en el perfil de Soul.");
    throw new Stop("token_expired", "No hay credencial: vuelve a iniciar sesión.");
  }
}

function check(r: TransportResponse, service: string): J {
  if (r.status === 401 || r.status === 203) throw new Stop("token_expired", `Credencial de ${service} caducada: vuelve a iniciar sesión.`);
  if (r.status === 440 || (r.status === 302 && /login|logon/.test(String(r.headers.Location)))) {
    throw new Stop("session_expired", `La sesión de ${service} en el perfil de Soul caducó: vuelve a iniciar sesión.`);
  }
  if (r.status === 429) throw new Stop("unavailable", `${service} limita las peticiones; se reintentará.`);
  if (r.status !== 200) throw new Stop("error", `${service} respondió ${r.status}.`);
  return r.body;
}

async function getAll(ctx: AdapterContext, service: string, tok: string, url: string): Promise<J[]> {
  const out: J[] = [];
  let next: string | undefined = url;
  for (let i = 0; next && i < 50; i++) {
    const b = check(await ctx.transport.request({ service, method: "GET", url: next, headers: { Authorization: `Bearer ${tok}` } }), service);
    out.push(...(b.value ?? []));
    next = b["@odata.nextLink"];
  }
  return out;
}

function run(name: SourceAdapter["name"], routes: Route[], purpose: string, fn: (ctx: AdapterContext) => Promise<Claim[]>): SourceAdapter {
  return {
    name, routes, purpose,
    async read(ctx): Promise<AdapterResult> {
      try {
        return { status: "ok", route: ctx.route, claims: await fn(ctx) };
      } catch (e) {
        if (e instanceof Stop) return { status: e.status, route: ctx.route, message: e.message, fallback: e.fallback };
        return { status: "error", route: ctx.route, message: "Error interno del adaptador." };
      }
    },
  };
}

// ---------------------------------------------------------------------------
// «Esperando mi respuesta», común a Graph, Outlook web y Gmail

export interface Msg { id: string; conv: string; from: string; to: string[]; cc: string[]; at: string; sent: boolean; subject: string; auth: SenderAuth }

export function awaitingReply(msgs: Msg[], mine: string[], m: Mutations): Msg[] {
  const me = new Set(mine.map((x) => x.toLowerCase()));
  const isMe = (a: string) => me.has(a.toLowerCase());
  const byConv = new Map<string, Msg[]>();
  for (const x of msgs) byConv.set(x.conv, [...(byConv.get(x.conv) ?? []), x]);
  const out: Msg[] = [];
  for (const list of byConv.values()) {
    const pool = m.noSentItems ? list.filter((x) => !x.sent) : list;
    if (!pool.length) continue;
    // Último mensaje del hilo; a igual fecha, el enviado va después (lo mío cierra).
    const sorted = [...pool].sort((a, b) => a.at.localeCompare(b.at) || Number(a.sent) - Number(b.sent));
    const last = sorted[sorted.length - 1];
    if (last.sent || isMe(last.from)) continue;
    const direct = last.to.some(isMe) || (m.ccCounts && last.cc.some(isMe));
    if (!direct) continue;
    if (pool.some((x) => x.sent && x.at > last.at)) continue;
    out.push(last);
  }
  return out;
}

function threadClaims(ctx: AdapterContext, adapter: string, msgs: Msg[], m: Mutations): Claim[] {
  return awaitingReply(msgs, ctx.operator.identities.emails, m).map((last) =>
    base(ctx, adapter, "awaiting_reply", `${last.conv}@${last.id}`, {
      title: last.subject, event_at: last.at, awaiting_operator: true,
      attrs: { last_from: last.from.toLowerCase(), sender_auth: last.auth },
    }));
}

/** Identidad del remitente por cabeceras (AC-4c). Nunca por `From` solo. */
export function senderAuth(from: string, headers: { name: string; value: string }[] | undefined, myDomain: string, m: Mutations): SenderAuth {
  if (m.fromHeaderAlerts) return "tenant";
  if (!headers) return "unknown";
  const dom = from.split("@")[1]?.toLowerCase() ?? "";
  const h = (n: string) => headers.filter((x) => x.name.toLowerCase() === n.toLowerCase()).map((x) => x.value).join(";");
  if (h("X-MS-Exchange-Organization-AuthAs") === "Internal" && dom === myDomain) return "tenant";
  const ar = h("Authentication-Results");
  const hf = /header\.from=([^\s;]+)/.exec(ar)?.[1]?.toLowerCase();
  if (/dkim=pass/.test(ar) && /dmarc=pass/.test(ar) && hf === dom) return "dkim_dmarc";
  return "unauthenticated";
}

// ---------------------------------------------------------------------------

export function makeAdapters(m: Mutations): Record<string, SourceAdapter> {
  const myDomain = (ctx: AdapterContext) => ctx.operator.identities.emails[0]?.split("@")[1] ?? "";

  const m365Mail = run("m365-mail", ["graph", "web"], "Hilos que esperan mi respuesta y correos marcados", async (ctx) => {
    const msgs: Msg[] = [];
    const flagged: Claim[] = [];
    if (ctx.route === "web") {
      const tok = await token(ctx, "owa", [], "web");
      for (const folder of ["inbox", "sentitems"]) {
        const b = check(await ctx.transport.request({ service: "owa", method: "POST", url: "/owa/service.svc", headers: { Authorization: `Bearer ${tok}`, Action: "FindItem" }, body: { folder } }), "Outlook web");
        for (const r of b.Items ?? []) {
          msgs.push({ id: r.ItemId, conv: r.ConversationId, from: r.From?.EmailAddress ?? "", to: (r.ToRecipients ?? []).map((x: J) => x.EmailAddress), cc: (r.CcRecipients ?? []).map((x: J) => x.EmailAddress), at: r.DateTimeReceived, sent: folder === "sentitems", subject: r.Subject, auth: "unknown" });
        }
      }
      return threadClaims(ctx, "m365-mail", msgs, m);
    }
    const tok = await token(ctx, "graph", ["Mail.Read"], "graph");
    const select = m.persistBodies ? "" : "&$select=id,conversationId,subject,from,toRecipients,ccRecipients,receivedDateTime,flag,internetMessageHeaders,webLink";
    for (const folder of ["inbox", "sentitems"]) {
      const items = await getAll(ctx, "graph", tok, `/v1.0/me/mailFolders/${folder}/messages?$top=50${select}`);
      if (m.persistBodies) (ctx.params as J).__raw = [...((ctx.params as J).__raw ?? []), ...items];
      for (const x of items) {
        const from = x.from?.emailAddress?.address ?? "";
        msgs.push({ id: x.id, conv: x.conversationId, from, to: (x.toRecipients ?? []).map((r: J) => r.emailAddress.address), cc: (x.ccRecipients ?? []).map((r: J) => r.emailAddress.address), at: x.receivedDateTime, sent: folder === "sentitems", subject: x.subject, auth: senderAuth(from, x.internetMessageHeaders, myDomain(ctx), m) });
        if (folder === "inbox" && x.flag?.flagStatus === "flagged" && x.flag?.dueDateTime?.dateTime) {
          flagged.push(base(ctx, "m365-mail", "dated_commitment", x.id, { title: x.subject, due_at: iso(Date.parse(`${x.flag.dueDateTime.dateTime}Z`)) }));
        }
      }
    }
    if (m.readsThirdParty) {
      const extra = await getAll(ctx, "graph", tok, `/v1.0/users/compartido@alfa.example/messages?$top=50${select}`).catch(() => []);
      for (const x of extra) msgs.push({ id: x.id, conv: x.conversationId, from: x.from.emailAddress.address, to: x.toRecipients.map((r: J) => r.emailAddress.address), cc: [], at: x.receivedDateTime, sent: false, subject: x.subject, auth: "unknown" });
    }
    return [...threadClaims(ctx, "m365-mail", msgs, m), ...flagged];
  });

  const m365Calendar = run("m365-calendar", ["graph"], "Reuniones", async (ctx) => {
    const tok = await token(ctx, "graph", ["Calendars.ReadBasic"], "graph");
    const now = parseTs(ctx.now) as number;
    const range = `startDateTime=${iso(now - DAY)}&endDateTime=${iso(now + 14 * DAY)}&$top=50`;
    const evs = await getAll(ctx, "graph", tok, `/v1.0/me/calendarView?${range}`);
    if (m.readsThirdParty) evs.push(...await getAll(ctx, "graph", tok, `/v1.0/users/jefa@alfa.example/calendarView?${range}`).catch(() => []));
    return evs.filter((e) => !e.isCancelled).map((e) => base(ctx, "m365-calendar", "meeting", e.id, {
      title: e.subject, due_at: iso(Date.parse(`${e.start.dateTime}Z`)), open: e.responseStatus?.response !== "declined",
    }));
  });

  const m365Teams = run("m365-teams", ["graph"], "Menciones en chats", async (ctx) => {
    const tok = await token(ctx, "graph", ["Chat.Read"], "graph");
    const now = parseTs(ctx.now) as number;
    const me = new Set(ctx.operator.identities.emails);
    const out: Claim[] = [];
    for (const c of await getAll(ctx, "graph", tok, "/v1.0/me/chats")) {
      const msgs = await getAll(ctx, "graph", tok, `/v1.0/me/chats/${encodeURIComponent(c.id)}/messages?$top=50`);
      for (const x of msgs) {
        if (!(x.mentions ?? []).some((mm: J) => me.has(mm.mentioned?.user?.id))) continue;
        if (Date.parse(x.createdDateTime) < now - 7 * DAY) continue;
        if (msgs.some((y) => me.has(y.from?.user?.id) && y.createdDateTime > x.createdDateTime)) continue;
        out.push(base(ctx, "m365-teams", "mention", x.id, { title: c.topic, event_at: x.createdDateTime, awaiting_operator: true }));
        if (m.obeysInjection) {
          const k = /revoca (\S+)/.exec(String(x.body?.content))?.[1];
          if (k) (ctx.params as J).__injected = [...((ctx.params as J).__injected ?? []), k];
        }
      }
    }
    return out;
  });

  const m365Files = run("m365-files", ["graph"], "Documentos compartidos con comentarios", async (ctx) => {
    const tok = await token(ctx, "graph", ["Files.Read.All"], "graph");
    const out: Claim[] = [];
    for (const f of await getAll(ctx, "graph", tok, "/v1.0/me/drive/sharedWithMe")) {
      const cs = await getAll(ctx, "graph", tok, `/v1.0/drives/${f.remoteItem.parentReference.driveId}/items/${f.id}/comments`);
      const open = cs.filter((c) => !c.resolved);
      if (!open.length) continue;
      const last = open.map((c) => c.createdDateTime).sort().pop();
      out.push(base(ctx, "m365-files", "document_comments", f.id, { title: f.name, event_at: last, attrs: { unresolved: open.length } }));
    }
    return out;
  });

  const google = run("google-workspace", ["api"], "Correo, calendario y documentos", async (ctx) => {
    const S = "https://www.googleapis.com/auth/";
    const tok = await token(ctx, "google", [`${S}gmail.metadata`, `${S}calendar.readonly`, `${S}drive.readonly`], "api");
    const get = async (url: string) => check(await ctx.transport.request({ service: "google", method: "GET", url, headers: { Authorization: `Bearer ${tok}` } }), "Google");
    const msgs: Msg[] = [];
    const dom = myDomain(ctx);
    for (const t of (await get("/gmail/v1/users/me/threads")).threads ?? []) {
      const th = await get(`/gmail/v1/users/me/threads/${t.id}?format=metadata`);
      for (const x of th.messages ?? []) {
        const h = (n: string) => x.payload.headers.find((y: J) => y.name === n)?.value ?? "";
        const addrs = (v: string) => v.split(",").map((s) => (/<([^>]+)>/.exec(s)?.[1] ?? s).trim()).filter(Boolean);
        const from = addrs(h("From"))[0] ?? "";
        msgs.push({ id: x.id, conv: th.id, from, to: addrs(h("To")), cc: addrs(h("Cc")), at: iso(Number(x.internalDate)), sent: (x.labelIds ?? []).includes("SENT"), subject: h("Subject"), auth: senderAuth(from, x.payload.headers.filter((y: J) => y.name === "Authentication-Results"), dom, m) });
      }
    }
    const out = threadClaims(ctx, "google-workspace", msgs, m);
    const now = parseTs(ctx.now) as number;
    const evs = (await get(`/calendar/v3/calendars/primary/events?singleEvents=true&timeMin=${iso(now - DAY)}&timeMax=${iso(now + 14 * DAY)}`)).items ?? [];
    for (const e of evs) {
      if (e.status === "cancelled") continue;
      const self = (e.attendees ?? []).find((a: J) => a.self);
      out.push(base(ctx, "google-workspace", "meeting", e.id, { title: e.summary, due_at: iso(Date.parse(e.start.dateTime)), open: self?.responseStatus !== "declined" }));
    }
    for (const f of (await get("/drive/v3/files?q=sharedWithMe")).files ?? []) {
      const open = ((await get(`/drive/v3/files/${f.id}/comments`)).comments ?? []).filter((c: J) => !c.resolved);
      if (!open.length) continue;
      out.push(base(ctx, "google-workspace", "document_comments", f.id, { title: f.name, event_at: open.map((c: J) => c.createdTime).sort().pop(), attrs: { unresolved: open.length } }));
    }
    return out;
  });

  const jira = run("jira", ["api"], "Tareas asignadas", async (ctx) => {
    const tok = await token(ctx, "jira", ["read:jira-work"], "api");
    const jql = m.noJqlFilter ? "" : "assignee = currentUser() AND statusCategory != Done";
    const b = check(await ctx.transport.request({ service: "jira", method: "GET", url: `/rest/api/3/search?maxResults=100&fields=summary,status,duedate,assignee&jql=${encodeURIComponent(jql)}`, headers: { Authorization: `Bearer ${tok}` } }), "Jira");
    return (b.issues ?? []).map((i: J) => base(ctx, "jira", "task_assigned", i.key, {
      title: i.fields.summary, due_at: i.fields.duedate ? `${i.fields.duedate}T00:00:00Z` : null, awaiting_operator: true,
    }));
  });

  const ado = run("azure-devops", ["api"], "Elementos asignados y revisiones", async (ctx) => {
    const tok = await token(ctx, "ado", ["vso.work", "vso.code"], "api");
    const H = { Authorization: `Bearer ${tok}` };
    const me = ctx.operator.identities.ado_id ?? "";
    const q = "SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed', 'Done', 'Removed')";
    const ids = (check(await ctx.transport.request({ service: "ado", method: "POST", url: "/org/proj/_apis/wit/wiql?api-version=7.1", headers: H, body: { query: q } }), "Azure DevOps").workItems ?? []).map((x: J) => x.id);
    const out: Claim[] = [];
    if (ids.length) {
      const wi = check(await ctx.transport.request({ service: "ado", method: "GET", url: `/org/_apis/wit/workitems?ids=${ids.join(",")}&api-version=7.1`, headers: H }), "Azure DevOps");
      for (const x of wi.value ?? []) {
        const due = x.fields["Microsoft.VSTS.Scheduling.DueDate"];
        out.push(base(ctx, "azure-devops", "task_assigned", String(x.id), { title: x.fields["System.Title"], due_at: due ? iso(Date.parse(due)) : null, awaiting_operator: true }));
      }
    }
    const prs = check(await ctx.transport.request({ service: "ado", method: "GET", url: `/org/proj/_apis/git/pullrequests?searchCriteria.reviewerId=${encodeURIComponent(me)}&searchCriteria.status=active&api-version=7.1`, headers: H }), "Azure DevOps");
    for (const p of prs.value ?? []) {
      if ((p.reviewers ?? []).some((r: J) => r.id === me && r.vote === 0)) {
        out.push(base(ctx, "azure-devops", "review_request", `${p.repository.name}!${p.pullRequestId}`, { title: p.title, awaiting_operator: true }));
      }
    }
    return out;
  });

  const github = run("github", ["api"], "Revisiones, asignaciones y menciones", async (ctx) => {
    const tok = await token(ctx, "github", ["repo:read"], "api");
    const search = async (q: string) => (check(await ctx.transport.request({ service: "github", method: "GET", url: `/search/issues?q=${encodeURIComponent(q)}`, headers: { Authorization: `Bearer ${tok}` } }), "GitHub").items ?? []) as J[];
    const ref = (i: J) => `${String(i.repository_url).split("/").pop()}#${i.number}`;
    const out: Claim[] = [];
    const seen = new Set<string>();
    for (const i of await search("is:open is:pr review-requested:@me")) { seen.add(ref(i)); out.push(base(ctx, "github", "review_request", ref(i), { title: i.title, awaiting_operator: true })); }
    for (const i of await search("is:open assignee:@me")) { seen.add(ref(i)); out.push(base(ctx, "github", "task_assigned", ref(i), { title: i.title, awaiting_operator: true })); }
    for (const i of await search("is:open mentions:@me")) {
      if (!seen.has(ref(i))) out.push(base(ctx, "github", "mention", ref(i), { title: i.title, awaiting_operator: true }));
    }
    return out;
  });

  const web = run("web", ["web"], "Webs sin API, solo lectura", async (ctx) => {
    const tok = await token(ctx, "web", [], "web");
    const H = { Authorization: `Bearer ${tok}` };
    const out: Claim[] = [];
    for (const site of (ctx.params.sites as string[] | undefined) ?? []) {
      if (m.followsMutatingLinks) await ctx.transport.request({ service: "web", method: "GET", url: `/sites/${site}/approve?id=todo`, headers: H });
      const rows = check(await ctx.transport.request({ service: "web", method: "GET", url: `/sites/${site}/list`, headers: H }), site).rows ?? [];
      for (const r of rows) {
        if (r.kind === "task" && r.assigned_to_me) out.push(base(ctx, "web", "task_assigned", `${site}~${r.id}`, { title: r.title, due_at: r.due, awaiting_operator: true }));
        if (r.kind === "deadline") out.push(base(ctx, "web", "dated_commitment", `${site}~${r.id}`, { title: r.title, due_at: r.due }));
      }
      const pages = check(await ctx.transport.request({ service: "web", method: "GET", url: `/sites/${site}/pages`, headers: H }), site).pages ?? [];
      for (const p of pages) out.push(base(ctx, "web", "web_page_change", `${site}~${p.id}`, { event_at: p.modified, open: false }));
    }
    return out;
  });

  return {
    "m365-mail": m365Mail, "m365-calendar": m365Calendar, "m365-teams": m365Teams, "m365-files": m365Files,
    "google-workspace": google, jira, "azure-devops": ado, github, web,
  };
}
