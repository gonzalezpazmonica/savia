/**
 * Adaptador de Jira Cloud, de solo lectura (SE-490).
 *
 * Misma consulta que los conectores de Savia (`/jira-sync`): JQL
 * `assignee = currentUser() AND statusCategory != Done`, solo los campos
 * `summary`, `status` y `duedate` (nunca descripción ni comentarios).
 * Usa `/rest/api/3/search/jql` con `nextPageToken`; si el sitio no lo tiene
 * (404), cae a `/rest/api/3/search` con `startAt`. Tope de páginas fail-closed.
 * Autenticación: OAuth (Bearer) o token de API (`params.auth: "basic"`, la
 * credencial guardada es `email:token`).
 */

import type { Claim } from "../contract/claims.ts";
import type { SourceAdapter } from "../contract/adapter.ts";
import { DEFAULT_MAX_PAGES, type J, Stop, adapter, authHeader, check, claim, safeRef, toIso, token } from "./common.ts";

export interface JiraOptions {
  maxPages?: number;
}

const JQL = "assignee = currentUser() AND statusCategory != Done ORDER BY duedate ASC";
const FIELDS = "summary,status,duedate";

export function makeJiraAdapter(o: JiraOptions = {}): SourceAdapter {
  const maxPages = o.maxPages ?? DEFAULT_MAX_PAGES;
  return adapter("jira", async (ctx) => {
    const tok = await token(ctx, "jira", ["read:jira-work"]);
    const basic = ctx.params.auth === "basic";
    const Authorization = basic ? authHeader(Buffer.from(tok).toString("base64"), "Basic") : authHeader(tok);
    const get = async (url: string) => ctx.transport.request({ service: "jira", method: "GET", url, headers: { Authorization, Accept: "application/json" } });
    const q = `jql=${encodeURIComponent(JQL)}&fields=${FIELDS}&maxResults=100`;
    const issues: J[] = [];
    let legacy = false;
    let next: string | undefined;
    let startAt = 0;
    for (let i = 0; ; i++) {
      if (i >= maxPages) throw new Stop("unavailable", `Jira: supera el tope de ${maxPages} páginas; no se dan datos incompletos.`);
      const url = legacy ? `/rest/api/3/search?${q}&startAt=${startAt}`
        : `/rest/api/3/search/jql?${q}${next ? `&nextPageToken=${encodeURIComponent(next)}` : ""}`;
      const r = await get(url);
      if (!legacy && i === 0 && r.status === 404) {
        legacy = true;
        i = -1;
        continue;
      }
      const b = check(r, "Jira");
      const page = Array.isArray(b.issues) ? b.issues : [];
      issues.push(...page);
      if (legacy) {
        // Sin `total` numérico no se sabe si quedan páginas: fail-closed, no truncado silencioso.
        if (typeof b.total !== "number" || !Number.isFinite(b.total)) throw new Stop("unavailable", "Jira: la búsqueda clásica no devuelve total; no se dan datos incompletos.");
        startAt += page.length;
        if (!page.length || startAt >= b.total) break;
      } else {
        next = typeof b.nextPageToken === "string" && b.nextPageToken ? b.nextPageToken : undefined;
        if (!next || b.isLast === true) break;
      }
    }
    const out: Claim[] = [];
    for (const it of issues) {
      const key = safeRef(it?.key);
      if (!key) continue;
      const due = typeof it?.fields?.duedate === "string" ? toIso(`${it.fields.duedate}T00:00:00Z`) : null;
      out.push(claim(ctx, "jira", "task_assigned", key, { title: it?.fields?.summary, due_at: due, awaiting_operator: true }));
    }
    return out;
  });
}
