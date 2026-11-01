/**
 * Servidor HTTP local que imita las APIs de lectura que usan los adaptadores:
 * Microsoft Graph (correo con delta, calendario, chats, ficheros), Google (Gmail
 * metadata, Calendar, Drive, Tasks), Jira, Azure DevOps y GitHub.
 *
 * Programable desde el test: paginación, rondas delta con `@removed`, delta
 * caducado (410), 429 con `Retry-After`, 401, 403 por permiso y registro de
 * peticiones con su método. Sin red real. Datos sintéticos (*.example).
 * Los cuerpos llevan el canario BODY para detectar si un adaptador los guarda.
 */

import { createServer, type IncomingMessage } from "node:http";
import type { AddressInfo } from "node:net";

export const BODY = "CANARIO-CUERPO";

export interface GMsg {
  id: string; conv: string; from: string; to: string[]; cc?: string[]; at: string; subject: string;
  folder: "inbox" | "sentitems"; flagDue?: string; internal?: boolean; dkim?: "pass" | "fail"; dmarc?: "pass" | "fail"; d?: string;
  /** `authserv-id` de la cabecera Authentication-Results (Exchange Online no pone ninguno). */
  authserv?: string;
  seq?: number;
}

export interface MockData {
  /** token → permisos */
  tokens: Record<string, string[]>;
  messages: GMsg[];
  removed: { id: string; folder: string; seq: number }[];
  seq: number;
  /** deltatokens por debajo de esta secuencia devuelven 410. */
  minDeltaSeq: number;
  events: { id: string; subject: string; start: string; cancelled?: boolean; response?: string }[];
  chats: { id: string; topic: string; messages: { id: string; from: string; at: string; mentions?: string[]; text?: string; deleted?: string }[] }[];
  files: { id: string; name: string; comments: { id: string; at: string; resolved?: boolean; text?: string }[] }[];
  google: {
    messages: { id: string; thread: string; from: string; to: string[]; cc?: string[]; at: string; subject: string; labels: string[]; dkim?: string; dmarc?: string; d?: string }[];
    events: { id: string; summary: string; start: string; allDay?: boolean; cancelled?: boolean; response?: string }[];
    files: { id: string; name: string; comments: { id: string; at: string; resolved?: boolean }[] }[];
    tasks: { list: string; id: string; title: string; due?: string; status?: string; notes?: string }[];
  };
  jira: { me: string; legacyOnly?: boolean; issues: { key: string; summary: string; assignee: string; status: string; duedate?: string | null; description?: string }[] };
  ado: { me: string; workitems: { id: number; title: string; assignedTo: string; state: string; due?: string }[]; prs: { id: number; repo: string; title: string; status: string; reviewers: { id: string; vote: number }[] }[] };
  github: { me: string; items: { owner?: string; repo: string; number: number; title: string; is_pr: boolean; assignees: string[]; requested: string[]; mentions: string[]; body?: string }[] };
  /** Id de Entra que devuelve `/v1.0/me` (exige User.Read); `null` = 403. */
  meId: string | null;
  /** Paginación por defecto (elementos por página). */
  pageSize: number;
  /** 429 en cada N-ésima petición (0 = nunca), con este Retry-After. */
  throttleEvery: number;
  retryAfter: string;
  /** 429 permanente en rutas que casan con este patrón. */
  throttlePath?: RegExp;
}

export interface LogRow { method: string; url: string; status: number; auth: string }

export function emptyData(): MockData {
  return {
    tokens: {}, messages: [], removed: [], seq: 0, minDeltaSeq: 0, events: [], chats: [], files: [],
    google: { messages: [], events: [], files: [], tasks: [] },
    jira: { me: "acc-yo", issues: [] }, ado: { me: "ado-yo", workitems: [], prs: [] }, github: { me: "yo-gh", items: [] },
    meId: "yo@alfa.example", pageSize: 10, throttleEvery: 0, retryAfter: "1",
  };
}

export function addMessage(d: MockData, m: GMsg): void {
  d.seq++;
  const i = d.messages.findIndex((x) => x.id === m.id);
  const v = { ...m, seq: d.seq };
  if (i >= 0) d.messages[i] = v;
  else d.messages.push(v);
}

export function removeMessage(d: MockData, id: string): void {
  const m = d.messages.find((x) => x.id === id);
  if (!m) return;
  d.seq++;
  d.messages = d.messages.filter((x) => x.id !== id);
  d.removed.push({ id, folder: m.folder, seq: d.seq });
}

const addr = (a: string) => ({ emailAddress: { name: a.split("@")[0], address: a } });

function graphMsg(m: GMsg, scopes: string[], select: string[] | null) {
  const full = scopes.includes("Mail.Read");
  const out: Record<string, unknown> = {
    id: m.id, conversationId: m.conv, subject: m.subject, from: addr(m.from), toRecipients: m.to.map(addr),
    ccRecipients: (m.cc ?? []).map(addr), receivedDateTime: m.at, sentDateTime: m.at, parentFolderId: m.folder,
    flag: m.flagDue ? { flagStatus: "flagged", dueDateTime: { dateTime: m.flagDue.replace("Z", ".0000000"), timeZone: "UTC" } } : { flagStatus: "notFlagged" },
    webLink: `https://outlook.office.example/owa/?ItemID=${m.id}`,
    bodyPreview: `${BODY} vista previa`, body: { contentType: "html", content: `<p>${BODY}</p>` },
  };
  if (full) {
    const h: { name: string; value: string }[] = [];
    if (m.internal) h.push({ name: "X-MS-Exchange-Organization-AuthAs", value: "Internal" });
    if (m.dkim || m.dmarc) {
      const dom = m.d ?? m.from.split("@")[1];
      h.push({ name: "Authentication-Results", value: `${m.authserv ? `${m.authserv}; ` : ""}dkim=${m.dkim ?? "none"} header.d=${dom}; dmarc=${m.dmarc ?? "none"} header.from=${dom}` });
    }
    out.internetMessageHeaders = h;
  }
  if (select) for (const k of Object.keys(out)) if (k !== "id" && !select.includes(k)) delete out[k];
  return out;
}

export async function startMock(d: MockData) {
  const log: LogRow[] = [];
  let count = 0;
  const srv = createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", () => {
      const u = new URL(req.url ?? "/", "http://mock");
      const auth = String(req.headers.authorization ?? "");
      const reply = (status: number, body: unknown, headers: Record<string, string> = {}) => {
        log.push({ method: req.method ?? "", url: u.pathname + u.search, status, auth });
        res.writeHead(status, { "content-type": "application/json", ...headers });
        res.end(body === undefined ? "" : JSON.stringify(body));
      };
      count++;
      if ((d.throttleEvery && count % d.throttleEvery === 0) || d.throttlePath?.test(u.pathname)) {
        return reply(429, { error: { code: "TooManyRequests" } }, { "Retry-After": d.retryAfter });
      }
      try {
        route(d, req, u, auth, raw, reply);
      } catch (e) {
        reply(500, { error: String(e) });
      }
    });
  });
  await new Promise<void>((r) => srv.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${(srv.address() as AddressInfo).port}`;
  return {
    base, log,
    bases: { graph: base, google: base, jira: base, ado: base, github: base },
    close: () => new Promise<void>((r) => srv.close(() => r())),
  };
}

type Reply = (status: number, body: unknown, headers?: Record<string, string>) => void;

function page<T>(items: T[], u: URL, size: number, path: string): { value: T[]; "@odata.nextLink"?: string } {
  const skip = Number(u.searchParams.get("$skip") ?? 0);
  const out: { value: T[]; "@odata.nextLink"?: string } = { value: items.slice(skip, skip + size) };
  if (skip + size < items.length) {
    const q = new URLSearchParams(u.searchParams);
    q.set("$skip", String(skip + size));
    out["@odata.nextLink"] = `https://graph.example${path}?${q}`;
  }
  return out;
}

function route(d: MockData, req: IncomingMessage, u: URL, auth: string, raw: string, reply: Reply): void {
  const p = u.pathname;
  const method = req.method ?? "GET";
  const tok = auth.replace(/^(Bearer|Basic) /, "");
  const scopes = d.tokens[tok];
  if (!scopes) return reply(401, { error: { code: "InvalidAuthenticationToken" } });
  const has = (...s: string[]) => s.some((x) => scopes.includes(x));
  const isRead = method === "GET" || (method === "POST" && /\/_apis\/wit\/wiql$/.test(p));
  if (!isRead) return reply(405, { error: { code: "MethodNotAllowed" } });
  const prefer = String(req.headers.prefer ?? "");
  const size = Number(/odata\.maxpagesize=(\d+)/.exec(prefer)?.[1] ?? d.pageSize);

  // --- Graph: correo
  const folder = /^\/v1\.0\/me\/mailFolders\/(inbox|sentitems)\/messages(\/delta)?$/.exec(p);
  if (folder) {
    if (!has("Mail.Read", "Mail.ReadBasic")) return reply(403, { error: { code: "ErrorAccessDenied" } });
    const select = u.searchParams.get("$select")?.split(",") ?? null;
    const f = folder[1];
    if (!folder[2]) {
      const items = d.messages.filter((m) => m.folder === f).sort((a, b) => b.at.localeCompare(a.at)).map((m) => graphMsg(m, scopes, select));
      return reply(200, page(items, u, Number(u.searchParams.get("$top") ?? d.pageSize), p));
    }
    // delta: $deltatoken=S (desde S) o $skiptoken=S.offset (ronda en curso contra la foto S)
    const dt = u.searchParams.get("$deltatoken");
    const sk = u.searchParams.get("$skiptoken");
    let since = -1;
    let offset = 0;
    let snap = d.seq;
    if (dt !== null) since = Number(dt);
    if (sk !== null) [since, snap, offset] = sk.split(".").map(Number);
    if (since >= 0 && since < d.minDeltaSeq) return reply(410, { error: { code: "SyncStateNotFound", message: "resync required" } });
    const changed = d.messages.filter((m) => m.folder === f && (m.seq ?? 0) > since && (m.seq ?? 0) <= snap).map((m) => graphMsg(m, scopes, select));
    const gone = since < 0 ? [] : d.removed.filter((r) => r.folder === f && r.seq > since && r.seq <= snap).map((r) => ({ id: r.id, "@removed": { reason: "deleted" } }));
    const all = [...changed, ...gone];
    const body: Record<string, unknown> = { value: all.slice(offset, offset + size) };
    if (offset + size < all.length) body["@odata.nextLink"] = `https://graph.example${p}?$skiptoken=${since}.${snap}.${offset + size}`;
    else body["@odata.deltaLink"] = `https://graph.example${p}?$deltatoken=${snap}`;
    return reply(200, body);
  }
  if (p === "/v1.0/me/calendarView") {
    if (!has("Calendars.ReadBasic", "Calendars.Read")) return reply(403, { error: { code: "ErrorAccessDenied" } });
    const a = Date.parse(u.searchParams.get("startDateTime") ?? "");
    const b = Date.parse(u.searchParams.get("endDateTime") ?? "");
    if (!Number.isFinite(a) || !Number.isFinite(b)) return reply(400, { error: { code: "ErrorInvalidParameter" } });
    const utc = /outlook\.timezone="UTC"/.test(prefer);
    const items = d.events.filter((e) => Date.parse(e.start) >= a && Date.parse(e.start) < b).map((e) => ({
      id: e.id, subject: e.subject, isCancelled: !!e.cancelled, responseStatus: { response: e.response ?? "accepted" },
      start: { dateTime: utc ? e.start.replace("Z", ".0000000") : e.start.replace("Z", "+00:00"), timeZone: utc ? "UTC" : "W. Europe Standard Time" },
      body: { content: BODY },
    }));
    return reply(200, page(items, u, Number(u.searchParams.get("$top") ?? d.pageSize), p));
  }
  if (p === "/v1.0/me") {
    if (d.meId === null || !has("User.Read")) return reply(403, { error: { code: "Authorization_RequestDenied" } });
    return reply(200, { id: d.meId });
  }
  if (p === "/v1.0/me/chats") {
    if (!has("Chat.Read")) return reply(403, { error: { code: "Forbidden" } });
    return reply(200, page(d.chats.map((c) => ({ id: c.id, topic: c.topic })), u, d.pageSize, p));
  }
  const chat = /^\/v1\.0\/me\/chats\/([^/]+)\/messages$/.exec(p);
  if (chat) {
    if (!has("Chat.Read")) return reply(403, { error: { code: "Forbidden" } });
    const c = d.chats.find((x) => x.id === decodeURIComponent(chat[1]));
    if (!c) return reply(404, { error: { code: "NotFound" } });
    const items = [...c.messages].sort((a, b) => b.at.localeCompare(a.at)).map((m) => ({
      id: m.id, createdDateTime: m.at, deletedDateTime: m.deleted ?? null, from: { user: { id: m.from } },
      mentions: (m.mentions ?? []).map((x, i) => ({ id: i, mentioned: { user: { id: x } } })),
      body: { content: `${BODY} ${m.text ?? ""}` },
    }));
    return reply(200, page(items, u, Number(u.searchParams.get("$top") ?? d.pageSize), p));
  }
  if (p === "/v1.0/me/drive/sharedWithMe") {
    if (!has("Files.Read.All")) return reply(403, { error: { code: "accessDenied" } });
    return reply(200, page(d.files.map((f) => ({ id: f.id, name: f.name, remoteItem: { id: f.id, parentReference: { driveId: "drv-1" } } })), u, d.pageSize, p));
  }
  const cm = /^\/v1\.0\/drives\/([^/]+)\/items\/([^/]+)\/comments$/.exec(p);
  if (cm) {
    const f = d.files.find((x) => x.id === decodeURIComponent(cm[2]));
    if (!f) return reply(404, { error: { code: "itemNotFound" } });
    return reply(200, { value: f.comments.map((c) => ({ id: c.id, createdDateTime: c.at, resolved: !!c.resolved, content: `${BODY} ${c.text ?? ""}` })) });
  }

  // --- Google
  const gpage = <T>(items: T[], key: string) => {
    const at = Number(u.searchParams.get("pageToken") ?? 0);
    const n = Number(u.searchParams.get("maxResults") ?? d.pageSize);
    const size = Math.min(n, d.pageSize);
    const out: Record<string, unknown> = { [key]: items.slice(at, at + size) };
    if (at + size < items.length) out.nextPageToken = String(at + size);
    return out;
  };
  if (p === "/gmail/v1/users/me/threads") {
    if (u.searchParams.has("q")) return reply(403, { error: { message: "Metadata scope does not support 'q' parameter" } });
    const ids = [...new Set([...d.google.messages].sort((a, b) => b.at.localeCompare(a.at)).map((m) => m.thread))];
    return reply(200, gpage(ids.map((id) => ({ id })), "threads"));
  }
  const th = /^\/gmail\/v1\/users\/me\/threads\/([^/]+)$/.exec(p);
  if (th) {
    if (u.searchParams.get("format") !== "metadata") return reply(403, { error: { message: "Metadata scope does not support format FULL" } });
    const msgs = d.google.messages.filter((m) => m.thread === th[1]);
    return reply(200, {
      id: th[1],
      messages: msgs.map((m) => {
        const headers = [
          { name: "From", value: `Nombre <${m.from}>` }, { name: "To", value: m.to.join(", ") },
          { name: "Cc", value: (m.cc ?? []).join(", ") }, { name: "Subject", value: m.subject },
        ];
        if (m.dkim) headers.push({ name: "Authentication-Results", value: `mx.google.com; dkim=${m.dkim} header.i=@${m.d}; dmarc=${m.dmarc} header.from=${m.d}` });
        return { id: m.id, threadId: m.thread, labelIds: m.labels, internalDate: String(Date.parse(m.at)), snippet: BODY, payload: { headers } };
      }),
    });
  }
  if (p === "/calendar/v3/calendars/primary/events") {
    const a = Date.parse(u.searchParams.get("timeMin") ?? "");
    const b = Date.parse(u.searchParams.get("timeMax") ?? "");
    const items = d.google.events.filter((e) => Date.parse(e.start) >= a && Date.parse(e.start) < b).map((e) => ({
      id: e.id, summary: e.summary, status: e.cancelled ? "cancelled" : "confirmed", description: BODY,
      start: e.allDay ? { date: e.start.slice(0, 10) } : { dateTime: e.start },
      attendees: [{ email: "yo@gamma.example", self: true, responseStatus: e.response ?? "accepted" }],
    }));
    return reply(200, gpage(items, "items"));
  }
  if (p === "/drive/v3/files") return reply(200, gpage(d.google.files.map((f) => ({ id: f.id, name: f.name })), "files"));
  const gc = /^\/drive\/v3\/files\/([^/]+)\/comments$/.exec(p);
  if (gc) {
    const f = d.google.files.find((x) => x.id === gc[1]);
    if (!f) return reply(404, {});
    return reply(200, gpage(f.comments.map((c) => ({ id: c.id, createdTime: c.at, resolved: !!c.resolved, content: BODY })), "comments"));
  }
  if (p === "/tasks/v1/users/@me/lists") {
    if (!has("https://www.googleapis.com/auth/tasks.readonly")) return reply(403, { error: { message: "insufficientPermissions" } });
    return reply(200, { items: [...new Set(d.google.tasks.map((t) => t.list))].map((id) => ({ id, title: id })) });
  }
  const tl = /^\/tasks\/v1\/lists\/([^/]+)\/tasks$/.exec(p);
  if (tl) {
    const items = d.google.tasks.filter((t) => t.list === tl[1] && (u.searchParams.get("showCompleted") !== "false" || t.status !== "completed"));
    return reply(200, gpage(items.map((t) => ({ id: t.id, title: t.title, due: t.due, status: t.status ?? "needsAction", notes: t.notes })), "items"));
  }

  // --- Jira
  if (p === "/rest/api/3/search/jql" || p === "/rest/api/3/search") {
    if (p === "/rest/api/3/search/jql" && d.jira.legacyOnly) return reply(404, { errorMessages: ["not found"] });
    const jql = u.searchParams.get("jql") ?? "";
    let issues = d.jira.issues;
    if (/assignee = currentUser\(\)/.test(jql)) issues = issues.filter((i) => i.assignee === d.jira.me);
    if (/statusCategory != Done/.test(jql)) issues = issues.filter((i) => i.status !== "Done");
    const mk = (i: (typeof issues)[number]) => ({ key: i.key, fields: { summary: i.summary, duedate: i.duedate ?? null, status: { name: i.status }, description: i.description ?? BODY } });
    if (p === "/rest/api/3/search/jql") {
      const at = Number(u.searchParams.get("nextPageToken") ?? 0);
      const out: Record<string, unknown> = { issues: issues.slice(at, at + d.pageSize).map(mk) };
      if (at + d.pageSize < issues.length) out.nextPageToken = String(at + d.pageSize);
      else out.isLast = true;
      return reply(200, out);
    }
    const startAt = Number(u.searchParams.get("startAt") ?? 0);
    return reply(200, { startAt, maxResults: d.pageSize, total: issues.length, issues: issues.slice(startAt, startAt + d.pageSize).map(mk) });
  }

  // --- Azure DevOps
  if (/\/_apis\/wit\/wiql$/.test(p)) {
    const q = String(JSON.parse(raw || "{}").query ?? "");
    let items = d.ado.workitems;
    if (/\[System\.AssignedTo\] = @Me/.test(q)) items = items.filter((i) => i.assignedTo === d.ado.me);
    if (/NOT IN \('Closed', 'Done', 'Removed'\)/.test(q)) items = items.filter((i) => !["Closed", "Done", "Removed"].includes(i.state));
    return reply(200, { workItems: items.map((i) => ({ id: i.id })) });
  }
  if (/\/_apis\/wit\/workitems$/.test(p)) {
    const ids = (u.searchParams.get("ids") ?? "").split(",").map(Number);
    if (ids.length > 200) return reply(400, { message: "VS402337: más de 200 ids" });
    return reply(200, { value: d.ado.workitems.filter((i) => ids.includes(i.id)).map((i) => ({ id: i.id, fields: { "System.Title": i.title, "System.State": i.state, "Microsoft.VSTS.Scheduling.DueDate": i.due ?? null, "System.Description": BODY } })) });
  }
  if (/\/_apis\/git\/pullrequests$/.test(p)) {
    const r = u.searchParams.get("searchCriteria.reviewerId");
    return reply(200, { value: d.ado.prs.filter((x) => x.status === "active" && (!r || x.reviewers.some((y) => y.id === r))).map((x) => ({ pullRequestId: x.id, title: x.title, repository: { name: x.repo }, reviewers: x.reviewers, description: BODY })) });
  }
  if (/\/_apis\/connectionData$/.test(p)) return reply(200, { authenticatedUser: { id: d.ado.me } });

  // --- GitHub
  if (p === "/search/issues") {
    const q = (u.searchParams.get("q") ?? "").split(/\s+/).filter(Boolean);
    let items = d.github.items;
    for (const t of q) {
      const [k, v] = [t.slice(0, t.indexOf(":")), t.slice(t.indexOf(":") + 1)];
      const me = v === "@me" ? d.github.me : v;
      if (k === "is" && v === "pr") items = items.filter((i) => i.is_pr);
      else if (k === "review-requested") items = items.filter((i) => i.requested.includes(me));
      else if (k === "assignee") items = items.filter((i) => i.assignees.includes(me));
      else if (k === "mentions") items = items.filter((i) => i.mentions.includes(me));
    }
    const per = Math.min(Number(u.searchParams.get("per_page") ?? 30), d.pageSize);
    const pg = Number(u.searchParams.get("page") ?? 1);
    const headers: Record<string, string> = {};
    if (pg * per < items.length) {
      const q2 = new URLSearchParams(u.searchParams);
      q2.set("page", String(pg + 1));
      headers.Link = `<https://api.github.example/search/issues?${q2}>; rel="next"`;
    }
    return reply(200, {
      total_count: items.length,
      items: items.slice((pg - 1) * per, pg * per).map((i) => ({ number: i.number, title: i.title, repository_url: `https://api.github.example/repos/${i.owner ?? "org"}/${i.repo}`, body: i.body ?? BODY })),
    }, headers);
  }
  reply(404, { error: { code: "NotFound" } });
}
