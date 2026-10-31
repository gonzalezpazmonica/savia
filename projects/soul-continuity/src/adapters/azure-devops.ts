/**
 * Adaptador de Azure DevOps, de solo lectura (SE-490).
 *
 * Reutiliza la consulta de los conectores de Savia (`scripts/azdevops-queries.sh`,
 * skill `azure-devops-queries`): WIQL con `@Me` y estados abiertos. WIQL es una
 * lectura que la API solo admite por POST; el transporte la tiene en su lista
 * cerrada y rechaza cualquier otro POST. Los elementos se piden en lotes de 200
 * (límite de la API) y solo con título, estado y vencimiento.
 * Revisiones: PR activas con revisión pedida a mí y voto 0.
 *
 * Base del transporte: `https://dev.azure.com/<organización>`; `params.project`
 * acota a un proyecto. Autenticación: token de Entra (Bearer) o PAT
 * (`params.auth: "pat"`, Basic con usuario vacío), siempre desde el almacén.
 */

import type { Claim } from "../contract/claims.ts";
import type { SourceAdapter } from "../contract/adapter.ts";
import { type J, Stop, adapter, authHeader, check, claim, safeRef, toIso, token } from "./common.ts";

export interface AzureDevOpsOptions {
  /** Máximo de elementos asignados que se leen (lotes de 200). */
  maxItems?: number;
}

const WIQL = "SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed', 'Done', 'Removed') ORDER BY [System.ChangedDate] DESC";
const FIELDS = "System.Title,System.State,Microsoft.VSTS.Scheduling.DueDate";
const V = "api-version=7.1";

export function makeAzureDevOpsAdapter(o: AzureDevOpsOptions = {}): SourceAdapter {
  const maxItems = o.maxItems ?? 2000;
  return adapter("azure-devops", async (ctx) => {
    const tok = await token(ctx, "ado", ["vso.work", "vso.code"]);
    const Authorization = ctx.params.auth === "pat" ? authHeader(Buffer.from(`:${tok}`).toString("base64"), "Basic") : authHeader(tok);
    const H = { Authorization };
    const project = typeof ctx.params.project === "string" && /^[^/?#:]+$/.test(ctx.params.project) ? `/${encodeURIComponent(ctx.params.project)}` : "";
    const get = async (url: string) => check(await ctx.transport.request({ service: "ado", method: "GET", url, headers: H }), "Azure DevOps");

    const w = check(await ctx.transport.request({ service: "ado", method: "POST", url: `${project}/_apis/wit/wiql?${V}`, headers: H, body: { query: WIQL } }), "Azure DevOps");
    const ids: number[] = (Array.isArray(w.workItems) ? w.workItems : []).map((x: J) => Number(x?.id)).filter((n: number) => Number.isInteger(n) && n > 0);
    if (ids.length > maxItems) throw new Stop("unavailable", `Azure DevOps: más de ${maxItems} elementos asignados; acota con params.project.`);
    const out: Claim[] = [];
    for (let i = 0; i < ids.length; i += 200) {
      const wi = await get(`/_apis/wit/workitems?ids=${ids.slice(i, i + 200).join(",")}&fields=${encodeURIComponent(FIELDS)}&${V}`);
      for (const x of Array.isArray(wi.value) ? wi.value : []) {
        const id = safeRef(x?.id);
        if (!id) continue;
        const due = toIso(x?.fields?.["Microsoft.VSTS.Scheduling.DueDate"]);
        out.push(claim(ctx, "azure-devops", "task_assigned", id, { title: x?.fields?.["System.Title"], due_at: due, awaiting_operator: true }));
      }
    }

    let me = ctx.operator.identities.ado_id;
    if (!me) me = String((await get(`/_apis/connectionData`))?.authenticatedUser?.id ?? "");
    if (!me) throw new Stop("error", "Azure DevOps: no se pudo determinar tu identidad.");
    const prs = await get(`${project}/_apis/git/pullrequests?searchCriteria.reviewerId=${encodeURIComponent(me)}&searchCriteria.status=active&$top=200&${V}`);
    for (const p of Array.isArray(prs.value) ? prs.value : []) {
      const repo = safeRef(p?.repository?.name);
      const n = safeRef(p?.pullRequestId);
      if (!repo || !n) continue;
      if ((Array.isArray(p?.reviewers) ? p.reviewers : []).some((r: J) => r?.id === me && Number(r?.vote) === 0)) {
        out.push(claim(ctx, "azure-devops", "review_request", `${repo}!${n}`, { title: p?.title, awaiting_operator: true }));
      }
    }
    return out;
  });
}
