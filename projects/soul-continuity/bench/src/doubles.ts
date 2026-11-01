/**
 * Dobles en memoria de las fuentes de SE-490, con la forma de sus APIs de lectura.
 *
 * Amplía el doble de Graph de labs/experiments/se490-viabilidad (Python, HTTP)
 * con lo que el banco de continuidad necesita: enviados, cabeceras de
 * autenticación, consentimiento por inquilino, calendarios delegados y buzones
 * compartidos (terceros), chats con menciones y comentarios de documentos.
 * Añade Outlook en la web (ruta web, lectura por POST en lista cerrada), Google
 * (Gmail metadata, Calendar, Drive), Jira, Azure DevOps, GitHub y sitios web con
 * enlaces GET que mutan.
 *
 * Simplificaciones declaradas (no son copia del servicio):
 * - `from.user.id` de los chats es la dirección de correo, no un id de Entra.
 * - `/drives/{d}/items/{i}/comments` no existe en Graph v1.0 tal cual; aproxima
 *   los comentarios de documentos de Word/SharePoint.
 * - JQL, WIQL y la búsqueda de GitHub solo entienden los filtros que usa el contrato;
 *   un filtro ausente devuelve también lo de otras personas (tentación para mutantes).
 * - Sin red, sin latencia ni throttling (lo mide la viabilidad, no este banco).
 */

import type { TransportRequest, TransportResponse } from "../../src/contract/adapter.ts";
import { CredentialError } from "../../src/contract/adapter.ts";
import { BODY_CANARY, TOKEN_CANARY, type Instant, type Json, worldAt } from "./world.ts";

export interface RequestLog {
  service: string;
  method: string;
  url: string;
  status: number;
  /** La petición habría cambiado estado en la fuente (comprobado en el doble, no por el método). */
  mutation: boolean;
}

interface TokenInfo { service: string; scopes: string[] }

export interface EnvOptions {
  installId: string;
  world: Json;          // mundo completo (sin proyectar)
  tenants: Json;
  instant: Instant;
  installEnv: { expired?: Record<string, string[]>; web_session_expired?: string[] };
}

/** Entorno de fuentes: transporte + almacén de credenciales + registro de peticiones. */
export function makeEnv(opts: EnvOptions) {
  const w = worldAt(opts.world, opts.instant);
  const log: RequestLog[] = [];
  const tokens = new Map<string, TokenInfo>();
  let n = 0;

  const expired = (service: string) => (opts.installEnv.expired?.[service] ?? []).includes(opts.instant);

  const credentials = {
    async acquire(service: string, scopes: string[]): Promise<string> {
      if (service === "graph") {
        const tenant = opts.tenants.m365[w.m365?.tenant];
        if (!tenant) throw new CredentialError("no_credential", "sin inquilino M365");
        const denied = scopes.filter((s) => !tenant.user_consent.includes(s));
        if (denied.length) {
          throw new CredentialError("admin_consent_required",
            `AADSTS90094 (sintético): el inquilino exige consentimiento de administración para ${denied.join(", ")}`);
        }
      }
      if (service === "google") {
        const dom = opts.tenants.google[w.google?.domain];
        if (!dom) throw new CredentialError("no_credential", "sin dominio Google");
        if (scopes.some((s) => !dom.user_consent.includes(s))) {
          throw new CredentialError("admin_consent_required", "admin_policy_enforced (sintético)");
        }
      }
      const tok = `${TOKEN_CANARY}-${opts.installId}-${service}-${++n}`;
      tokens.set(tok, { service, scopes: [...scopes] });
      return tok;
    },
  };

  const auth = (service: string, headers: Record<string, string> = {}): TokenInfo | number => {
    const h = headers.Authorization ?? headers.authorization ?? "";
    const tok = h.startsWith("Bearer ") ? h.slice(7) : "";
    const info = tokens.get(tok);
    if (!info || info.service !== service) return 401;
    if (expired(service)) return 401;
    return info;
  };

  const transport = {
    async request(req: TransportRequest): Promise<TransportResponse> {
      let res: TransportResponse & { mutation?: boolean };
      try {
        res = route(req, w, auth, opts);
      } catch {
        res = { status: 400, headers: {}, body: { error: "petición mal formada" } };
      }
      log.push({ service: req.service, method: req.method, url: req.url, status: res.status, mutation: !!res.mutation });
      // Copia profunda: la implementación no puede tocar el mundo por referencia.
      return { status: res.status, headers: res.headers, body: JSON.parse(JSON.stringify(res.body ?? null)) };
    },
  };

  return { transport, credentials, log };
}

type Auth = (service: string, headers?: Record<string, string>) => TokenInfo | number;
type Res = TransportResponse & { mutation?: boolean };

const ok = (body: unknown): Res => ({ status: 200, headers: {}, body });
const fail = (status: number, code: string, mutation = false): Res => ({ status, headers: {}, body: { error: { code } }, mutation });

function route(req: TransportRequest, w: Json, auth: Auth, opts: EnvOptions): Res {
  const u = new URL(req.url, "https://doble.local");
  switch (req.service) {
    case "graph": return graph(req, u, w, auth);
    case "owa": return owa(req, u, w, auth, opts);
    case "google": return google(req, u, w, auth);
    case "jira": return jira(req, u, w, auth);
    case "ado": return ado(req, u, w, auth);
    case "github": return github(req, u, w, auth);
    case "web": return web(req, u, w, auth, opts);
    default: return fail(404, "servicio desconocido");
  }
}

// ---------------------------------------------------------------------------
// Microsoft Graph v1.0

const addr = (a: string) => ({ emailAddress: { name: a.split("@")[0], address: a } });

function graphMessage(m: Json, scopes: string[], select: string[] | null) {
  const full = scopes.includes("Mail.Read");
  const headers: Json[] = [];
  if (m.auth?.as) headers.push({ name: "X-MS-Exchange-Organization-AuthAs", value: m.auth.as });
  if (m.auth?.dkim || m.auth?.dmarc) {
    const from = String(m.from).split("@")[1];
    headers.push({
      name: "Authentication-Results",
      value: `spf=none; dkim=${m.auth.dkim ?? "none"} header.d=${m.auth.d ?? from}; dmarc=${m.auth.dmarc ?? "none"} action=none header.from=${m.auth.d ?? from}`,
    });
  }
  const out: Json = {
    id: m.id,
    conversationId: m.conv,
    subject: m.subject,
    from: addr(m.from),
    sender: addr(m.from),
    toRecipients: (m.to ?? []).map(addr),
    ccRecipients: (m.cc ?? []).map(addr),
    receivedDateTime: m.at,
    sentDateTime: m.at,
    parentFolderId: m.folder,
    flag: m.flag ? { flagStatus: m.flag.status, dueDateTime: { dateTime: m.flag.due.replace("Z", ""), timeZone: "UTC" } } : { flagStatus: "notFlagged" },
    webLink: `https://outlook.office.example/owa/?ItemID=${m.id}`,
  };
  if (full) {
    out.internetMessageHeaders = headers;
    out.bodyPreview = `${BODY_CANARY}-${m.id} vista previa`;
    out.body = { contentType: "html", content: `<p>${BODY_CANARY}-${m.id} cuerpo completo</p>` };
  }
  if (select) for (const k of Object.keys(out)) if (k !== "id" && !select.includes(k)) delete out[k];
  return out;
}

function page(items: Json[], u: URL, def = 10): Json {
  const top = Math.min(Number(u.searchParams.get("$top") ?? def), 1000);
  const skip = Number(u.searchParams.get("$skip") ?? 0);
  const body: Json = { value: items.slice(skip, skip + top) };
  if (skip + top < items.length) {
    const q = [...u.searchParams.entries()].filter(([k]) => k !== "$skip").map(([k, v]) => `${k}=${encodeURIComponent(v)}`);
    body["@odata.nextLink"] = `${u.pathname}?${[...q, `$skip=${skip + top}`].join("&")}`;
  }
  return body;
}

function graphEvent(e: Json, withBody: boolean) {
  const end = new Date(Date.parse(e.start) + (e.minutes ?? 30) * 60_000).toISOString();
  const out: Json = {
    id: e.id, subject: e.subject,
    start: { dateTime: e.start.replace("Z", ""), timeZone: "UTC" },
    end: { dateTime: end.replace(".000Z", ""), timeZone: "UTC" },
    isCancelled: !!e.cancelled,
    responseStatus: { response: e.response },
    organizer: addr(e.organizer),
    webLink: `https://outlook.office.example/calendar/item/${e.id}`,
  };
  if (withBody) out.body = { contentType: "html", content: `<p>${BODY_CANARY}-${e.id}</p>` };
  return out;
}

function inRange(start: string, u: URL): boolean | null {
  const a = Date.parse(u.searchParams.get("startDateTime") ?? "");
  const b = Date.parse(u.searchParams.get("endDateTime") ?? "");
  if (!Number.isFinite(a) || !Number.isFinite(b)) return null;
  const s = Date.parse(start);
  return s >= a && s < b;
}

function graph(req: TransportRequest, u: URL, w: Json, auth: Auth): Res {
  const a = auth("graph", req.headers);
  if (typeof a === "number") return fail(a, "InvalidAuthenticationToken");
  if (req.method !== "GET") return fail(405, "ErrorInvalidRequest", true);
  const m365 = w.m365 ?? {};
  const has = (...s: string[]) => s.some((x) => a.scopes.includes(x));
  const select = u.searchParams.get("$select")?.split(",").map((s) => s.trim()) ?? null;
  const p = u.pathname.replace(/^\/v1\.0/, "");
  const folder = /^\/me\/mailFolders\/(inbox|sentitems)\/messages$/.exec(p);
  if (folder) {
    if (!has("Mail.Read", "Mail.ReadBasic")) return fail(403, "ErrorAccessDenied");
    const items = (m365.messages ?? []).filter((m: Json) => m.folder === folder[1])
      .sort((x: Json, y: Json) => y.at.localeCompare(x.at))
      .map((m: Json) => graphMessage(m, a.scopes, select));
    return ok(page(items, u));
  }
  if (p === "/me/calendarView" || /^\/users\/[^/]+\/calendarView$/.test(p)) {
    if (!has("Calendars.Read", "Calendars.ReadBasic")) return fail(403, "ErrorAccessDenied");
    const tp = m365.third_party ?? {};
    let events: Json[];
    if (p === "/me/calendarView") events = m365.events ?? [];
    else if (decodeURIComponent(p.split("/")[2]) === tp.delegated_user) events = tp.delegated_events ?? [];
    else return fail(404, "ErrorItemNotFound");
    if (events.some((e) => inRange(e.start, u) === null)) return fail(400, "ErrorInvalidParameter");
    const items = events.filter((e) => inRange(e.start, u)).map((e) => graphEvent(e, has("Calendars.Read")));
    return ok(page(items, u, 50));
  }
  const shared = /^\/users\/([^/]+)\/messages$/.exec(p);
  if (shared) {
    const tp = m365.third_party ?? {};
    if (decodeURIComponent(shared[1]) !== tp.shared_mailbox) return fail(404, "ErrorItemNotFound");
    return ok(page((tp.shared_messages ?? []).map((m: Json) => graphMessage(m, a.scopes, select)), u));
  }
  if (p === "/me/chats") {
    if (!has("Chat.Read")) return fail(403, "Forbidden");
    return ok({ value: (m365.chats ?? []).map((c: Json) => ({ id: c.id, topic: c.topic })) });
  }
  const chat = /^\/me\/chats\/([^/]+)\/messages$/.exec(p);
  if (chat) {
    if (!has("Chat.Read")) return fail(403, "Forbidden");
    const c = (m365.chats ?? []).find((x: Json) => x.id === decodeURIComponent(chat[1]));
    if (!c) return fail(404, "NotFound");
    const items = [...c.messages].sort((x: Json, y: Json) => y.at.localeCompare(x.at)).map((m: Json) => ({
      id: m.id, chatId: c.id, createdDateTime: m.at, lastModifiedDateTime: m.at,
      from: { user: { id: m.from, displayName: m.from.split("@")[0] } },
      mentions: (m.mentions ?? []).map((x: string, i: number) => ({ id: i, mentionText: x.split("@")[0], mentioned: { user: { id: x } } })),
      body: { contentType: "html", content: `<p>${BODY_CANARY}-${m.id} ${m.text}</p>` },
    }));
    return ok(page(items, u, 50));
  }
  if (p === "/me/drive/sharedWithMe") {
    if (!has("Files.Read.All")) return fail(403, "accessDenied");
    return ok({ value: (m365.files ?? []).map((f: Json) => ({ id: f.id, name: f.name, remoteItem: { id: f.id, parentReference: { driveId: "drv-1" } } })) });
  }
  const comments = /^\/drives\/[^/]+\/items\/([^/]+)\/comments$/.exec(p);
  if (comments) {
    if (!has("Files.Read.All")) return fail(403, "accessDenied");
    const f = (m365.files ?? []).find((x: Json) => x.id === decodeURIComponent(comments[1]));
    if (!f) return fail(404, "itemNotFound");
    return ok({ value: f.comments.map((c: Json) => ({ id: c.id, createdDateTime: c.at, resolved: !!c.resolved, author: addr(c.author), content: `${BODY_CANARY}-${c.id} ${c.text}` })) });
  }
  return fail(404, "Request_ResourceNotFound");
}

// ---------------------------------------------------------------------------
// Outlook en la web: lectura por POST en lista cerrada (FindItem), escritura por POST a la misma URL

const OWA_READ = new Set(["FindItem", "FindConversation"]);
const OWA_WRITE = new Set(["UpdateItem", "MarkAsRead", "SendItem", "DeleteItem", "CreateItem"]);

function owa(req: TransportRequest, u: URL, w: Json, auth: Auth, opts: EnvOptions): Res {
  const a = auth("owa", req.headers);
  if (typeof a === "number") return { status: 440, headers: { Location: "/owa/auth/logon.aspx" }, body: null };
  if (u.pathname !== "/owa/service.svc") return fail(404, "NotFound");
  const action = req.headers?.Action ?? u.searchParams.get("action") ?? "";
  if (req.method !== "POST") return fail(405, "MethodNotAllowed");
  if (OWA_WRITE.has(action)) return { status: 200, headers: {}, body: { ResponseCode: "NoError" }, mutation: true };
  if (!OWA_READ.has(action)) return fail(400, "ErrorInvalidRequest");
  void opts;
  const folder = (req.body as Json)?.folder;
  if (folder !== "inbox" && folder !== "sentitems") return fail(400, "ErrorInvalidFolder");
  const rows = (w.m365?.messages ?? []).filter((m: Json) => m.folder === folder)
    .sort((x: Json, y: Json) => y.at.localeCompare(x.at))
    .map((m: Json) => ({
      ItemId: m.id, ConversationId: m.conv, Subject: m.subject,
      From: { Name: m.from.split("@")[0], EmailAddress: m.from },
      ToRecipients: (m.to ?? []).map((x: string) => ({ EmailAddress: x })),
      CcRecipients: (m.cc ?? []).map((x: string) => ({ EmailAddress: x })),
      DateTimeReceived: m.at,
    }));
  return ok({ Items: rows });
}

// ---------------------------------------------------------------------------
// Google: Gmail (metadata), Calendar, Drive

const G_META = "https://www.googleapis.com/auth/gmail.metadata";
const G_CAL = "https://www.googleapis.com/auth/calendar.readonly";
const G_DRIVE = "https://www.googleapis.com/auth/drive.readonly";

function google(req: TransportRequest, u: URL, w: Json, auth: Auth): Res {
  const a = auth("google", req.headers);
  if (typeof a === "number") return fail(a, "UNAUTHENTICATED");
  if (req.method !== "GET") return fail(405, "METHOD_NOT_ALLOWED", true);
  const g = w.google ?? {};
  const has = (s: string) => a.scopes.includes(s);
  const p = u.pathname;
  if (p === "/gmail/v1/users/me/threads") {
    if (!has(G_META)) return fail(403, "PERMISSION_DENIED");
    const ids = [...new Set((g.messages ?? []).map((m: Json) => m.thread))];
    return ok({ threads: ids.map((id) => ({ id })) });
  }
  const th = /^\/gmail\/v1\/users\/me\/threads\/([^/]+)$/.exec(p);
  if (th) {
    if (!has(G_META)) return fail(403, "PERMISSION_DENIED");
    const format = u.searchParams.get("format") ?? "full";
    if (format !== "metadata") return fail(403, "Metadata scope does not support format FULL");
    const msgs = (g.messages ?? []).filter((m: Json) => m.thread === th[1]);
    if (!msgs.length) return fail(404, "NOT_FOUND");
    return ok({
      id: th[1],
      messages: msgs.map((m: Json) => {
        const headers = [
          { name: "From", value: `${m.from.split("@")[0]} <${m.from}>` },
          { name: "To", value: (m.to ?? []).join(", ") },
          { name: "Cc", value: (m.cc ?? []).join(", ") },
          { name: "Subject", value: m.subject },
          { name: "Date", value: new Date(m.at).toUTCString() },
        ];
        if (m.auth) {
          headers.push({ name: "Authentication-Results", value: `mx.google.example; dkim=${m.auth.dkim} header.i=@${m.auth.d}; dmarc=${m.auth.dmarc} header.from=${m.auth.d}` });
        }
        return { id: m.id, threadId: m.thread, labelIds: m.labels, internalDate: String(Date.parse(m.at)), payload: { headers } };
      }),
    });
  }
  if (p === "/calendar/v3/calendars/primary/events") {
    if (!has(G_CAL)) return fail(403, "PERMISSION_DENIED");
    const a0 = Date.parse(u.searchParams.get("timeMin") ?? "");
    const b0 = Date.parse(u.searchParams.get("timeMax") ?? "");
    const me = `${w.operator}@${g.domain}`;
    const items = (g.events ?? []).filter((e: Json) => !Number.isFinite(a0) || (Date.parse(e.start) >= a0 && Date.parse(e.start) < b0))
      .map((e: Json) => ({
        id: e.id, summary: e.subject, status: e.cancelled ? "cancelled" : "confirmed",
        start: { dateTime: e.start }, organizer: { email: e.organizer, self: e.organizer === me },
        attendees: [{ email: me, self: true, responseStatus: ({ accepted: "accepted", declined: "declined", tentativelyAccepted: "tentative", none: "needsAction", organizer: "accepted" } as Json)[e.response] }],
        htmlLink: `https://calendar.google.example/event?eid=${e.id}`,
        description: `${BODY_CANARY}-${e.id}`,
      }));
    return ok({ items });
  }
  if (p === "/drive/v3/files") {
    if (!has(G_DRIVE)) return fail(403, "PERMISSION_DENIED");
    return ok({ files: (g.files ?? []).map((f: Json) => ({ id: f.id, name: f.name })) });
  }
  const cm = /^\/drive\/v3\/files\/([^/]+)\/comments$/.exec(p);
  if (cm) {
    if (!has(G_DRIVE)) return fail(403, "PERMISSION_DENIED");
    const f = (g.files ?? []).find((x: Json) => x.id === cm[1]);
    if (!f) return fail(404, "NOT_FOUND");
    return ok({ comments: f.comments.map((c: Json) => ({ id: c.id, createdTime: c.at, resolved: !!c.resolved, author: { displayName: c.author.split("@")[0] }, content: `${BODY_CANARY}-${c.id} ${c.text}` })) });
  }
  return fail(404, "NOT_FOUND");
}

// ---------------------------------------------------------------------------
// Jira Cloud REST v3

function jira(req: TransportRequest, u: URL, w: Json, auth: Auth): Res {
  const a = auth("jira", req.headers);
  if (typeof a === "number") return fail(401, "Unauthorized");
  if (req.method !== "GET") return fail(405, "MethodNotAllowed", true);
  const j = w.jira ?? { issues: [] };
  if (u.pathname === "/rest/api/3/myself") return ok({ accountId: j.me });
  if (u.pathname !== "/rest/api/3/search") return fail(404, "NotFound");
  const jql = (u.searchParams.get("jql") ?? "").replace(/\s+/g, " ");
  let issues: Json[] = j.issues;
  if (/assignee ?= ?currentUser\(\)/i.test(jql)) issues = issues.filter((i) => i.assignee === j.me);
  if (/statusCategory ?!= ?Done/i.test(jql)) issues = issues.filter((i) => i.status !== "Done");
  const cat = (s: string) => (s === "Done" ? "done" : s === "To Do" ? "new" : "indeterminate");
  const startAt = Number(u.searchParams.get("startAt") ?? 0);
  const max = Math.min(Number(u.searchParams.get("maxResults") ?? 50), 100);
  return ok({
    startAt, maxResults: max, total: issues.length,
    issues: issues.slice(startAt, startAt + max).map((i) => ({
      key: i.key,
      fields: { summary: i.summary, duedate: i.duedate, status: { name: i.status, statusCategory: { key: cat(i.status) } }, assignee: { accountId: i.assignee } },
    })),
  });
}

// ---------------------------------------------------------------------------
// Azure DevOps REST 7.1 (WIQL es una lectura por POST, en lista cerrada)

function ado(req: TransportRequest, u: URL, w: Json, auth: Auth): Res {
  const a = auth("ado", req.headers);
  if (typeof a === "number") return { status: 203, headers: {}, body: "<html>login</html>" };
  const d = w.ado ?? { workitems: [], prs: [] };
  const p = u.pathname;
  if (/\/_apis\/wit\/wiql$/.test(p)) {
    if (req.method !== "POST") return fail(405, "MethodNotAllowed");
    const q = String((req.body as Json)?.query ?? "");
    let items: Json[] = d.workitems;
    if (/\[System\.AssignedTo\] = @Me/i.test(q)) items = items.filter((i) => i.assignedTo === d.me);
    if (/\[System\.State\] NOT IN \('Closed', 'Done', 'Removed'\)/i.test(q)) items = items.filter((i) => !["Closed", "Done", "Removed"].includes(i.state));
    return ok({ workItems: items.map((i) => ({ id: i.id })) });
  }
  if (req.method !== "GET") return fail(405, "MethodNotAllowed", true);
  if (/\/_apis\/wit\/workitems$/.test(p)) {
    const ids = (u.searchParams.get("ids") ?? "").split(",").map(Number);
    return ok({
      value: d.workitems.filter((i: Json) => ids.includes(i.id)).map((i: Json) => ({
        id: i.id,
        fields: { "System.Title": i.title, "System.State": i.state, "System.AssignedTo": { id: i.assignedTo, uniqueName: i.assignedTo }, "Microsoft.VSTS.Scheduling.DueDate": i.dueDate ?? null },
      })),
    });
  }
  if (/\/_apis\/git\/pullrequests$/.test(p)) {
    const reviewer = u.searchParams.get("searchCriteria.reviewerId");
    const status = u.searchParams.get("searchCriteria.status") ?? "active";
    const prs = d.prs.filter((x: Json) => x.status === status && (!reviewer || x.reviewers.some((r: Json) => r.id === reviewer)));
    return ok({ value: prs.map((x: Json) => ({ pullRequestId: x.id, title: x.title, status: x.status, repository: { name: x.repo }, reviewers: x.reviewers })) });
  }
  if (/\/_apis\/connectionData$/.test(p)) return ok({ authenticatedUser: { id: d.me } });
  return fail(404, "NotFound");
}

// ---------------------------------------------------------------------------
// GitHub REST

function github(req: TransportRequest, u: URL, w: Json, auth: Auth): Res {
  const a = auth("github", req.headers);
  if (typeof a === "number") return fail(401, "Bad credentials");
  if (req.method !== "GET") return fail(405, "MethodNotAllowed", true);
  const g = w.github ?? { items: [] };
  if (u.pathname === "/user") return ok({ login: g.me });
  if (u.pathname !== "/search/issues") return fail(404, "Not Found");
  const q = (u.searchParams.get("q") ?? "").split(/\s+/).filter(Boolean);
  const me = (v: string) => (v === "@me" ? g.me : v);
  let items: Json[] = g.items;
  for (const t of q) {
    const [k, v] = t.includes(":") ? [t.slice(0, t.indexOf(":")), t.slice(t.indexOf(":") + 1)] : [t, ""];
    if (k === "is" && v === "open") items = items.filter((i) => i.state === "open");
    else if (k === "is" && v === "pr") items = items.filter((i) => i.is_pr);
    else if (k === "is" && v === "issue") items = items.filter((i) => !i.is_pr);
    else if (k === "review-requested") items = items.filter((i) => i.requested_reviewers.includes(me(v)));
    else if (k === "assignee") items = items.filter((i) => i.assignees.includes(me(v)));
    else if (k === "mentions") items = items.filter((i) => i.mentions.includes(me(v)));
    else return fail(422, "Validation Failed");
  }
  return ok({
    total_count: items.length,
    items: items.map((i) => ({
      number: i.number, title: i.title, state: i.state,
      repository_url: `https://api.github.example/repos/org/${i.repo}`,
      html_url: `https://github.example/org/${i.repo}/${i.is_pr ? "pull" : "issues"}/${i.number}`,
      assignees: i.assignees.map((l: string) => ({ login: l })),
      ...(i.is_pr ? { pull_request: { url: "…" } } : {}),
    })),
  });
}

// ---------------------------------------------------------------------------
// Sitios web con receta: vistas de lista de solo lectura y enlaces GET que mutan

function web(req: TransportRequest, u: URL, w: Json, auth: Auth, opts: EnvOptions): Res {
  const a = auth("web", req.headers);
  if (typeof a === "number") return fail(401, "sin sesión");
  const sites: Json[] = w.web?.sites ?? [];
  const m = /^\/sites\/([^/]+)\/(.+)$/.exec(u.pathname);
  const site = m ? sites.find((s) => s.id === m[1]) : undefined;
  if (!m || !site) return fail(404, "no existe");
  // Enlaces GET que cambian estado en el servidor (aprobar, cerrar sesión, marcar como leído).
  const mutating = (site.mutating_links ?? []).map((l: string) => l.split("?")[0].split("/").pop());
  if (mutating.includes(m[2]) || m[2] === "logout") return { status: 302, headers: { Location: "/" }, body: null, mutation: true };
  if (req.method !== "GET" && req.method !== "HEAD") return fail(405, "solo lectura", true);
  if ((opts.installEnv.web_session_expired ?? []).includes(opts.instant)) {
    return { status: 302, headers: { Location: `/sites/${site.id}/login` }, body: null };
  }
  if (m[2] === "list") return ok({ rows: site.rows ?? [] });
  if (m[2] === "pages") return ok({ pages: site.pages ?? [] });
  return fail(404, "no existe");
}
