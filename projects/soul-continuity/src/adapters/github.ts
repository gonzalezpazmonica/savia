/**
 * Adaptador de GitHub, de solo lectura (SE-490).
 *
 * Tres búsquedas sobre `/search/issues` (como el conector de Savia):
 * revisiones pedidas, asignaciones y menciones abiertas. Una mención de algo que
 * ya está asignado o con revisión pedida no se duplica. Solo número, repositorio
 * y título; nunca el cuerpo. Paginación por cabecera `Link` (solo su ruta) con
 * tope fail-closed. GitHub Enterprise: otra base en el transporte.
 */

import type { Claim } from "../contract/claims.ts";
import type { SourceAdapter } from "../contract/adapter.ts";
import { DEFAULT_MAX_PAGES, type J, Stop, adapter, check, claim, safeRef, sameOrigin, token } from "./common.ts";

export interface GitHubOptions {
  maxPages?: number;
}

function nextLink(link: string | undefined): string | undefined {
  if (!link) return undefined;
  return /<([^>]+)>\s*;\s*rel="next"/.exec(link)?.[1];
}

export function makeGitHubAdapter(o: GitHubOptions = {}): SourceAdapter {
  const maxPages = o.maxPages ?? DEFAULT_MAX_PAGES;
  return adapter("github", async (ctx) => {
    const tok = await token(ctx, "github", ["repo:read"]);
    const H = { Authorization: `Bearer ${tok}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };
    const search = async (q: string): Promise<J[]> => {
      const first = `/search/issues?q=${encodeURIComponent(q)}&per_page=100`;
      const out: J[] = [];
      let url: string | undefined = first;
      for (let i = 0; url; i++) {
        if (i >= maxPages) throw new Stop("unavailable", `GitHub: supera el tope de ${maxPages} páginas; no se dan datos incompletos.`);
        const r = await ctx.transport.request({ service: "github", method: "GET", url, headers: H });
        // GitHub responde 403 (no 429) al límite de tasa, primario o secundario: es esperar, no un error.
        if (r.status === 403 && (r.headers["retry-after"] !== undefined || r.headers["x-ratelimit-remaining"] === "0")) {
          throw new Stop("unavailable", "GitHub limita las peticiones; se reintentará en la próxima lectura.");
        }
        const b = check(r, "GitHub");
        if (Array.isArray(b.items)) out.push(...b.items);
        // Del enlace solo se toma la ruta: el transporte la manda a la base configurada,
        // así que un `Link` manipulado no puede llevarse el token a otro host.
        const n = nextLink(r.headers.link ?? r.headers.Link);
        url = n ? sameOrigin(n, first, "GitHub") : undefined;
      }
      return out;
    };
    const ref = (i: J): string | null => {
      const repo = safeRef(String(i?.repository_url ?? "").split("/").pop());
      const n = safeRef(i?.number);
      return repo && n ? `${repo}#${n}` : null;
    };
    const out: Claim[] = [];
    const seen = new Set<string>();
    for (const i of await search("is:open is:pr review-requested:@me")) {
      const r = ref(i);
      if (!r || seen.has(r)) continue;
      seen.add(r);
      out.push(claim(ctx, "github", "review_request", r, { title: i?.title, awaiting_operator: true }));
    }
    for (const i of await search("is:open assignee:@me")) {
      const r = ref(i);
      if (!r || seen.has(r)) continue;
      seen.add(r);
      out.push(claim(ctx, "github", "task_assigned", r, { title: i?.title, awaiting_operator: true }));
    }
    for (const i of await search("is:open mentions:@me")) {
      const r = ref(i);
      if (!r || seen.has(r)) continue;
      seen.add(r);
      out.push(claim(ctx, "github", "mention", r, { title: i?.title, awaiting_operator: true }));
    }
    return out;
  });
}
