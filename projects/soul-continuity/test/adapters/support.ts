/** Contexto mínimo de adaptador para tests unitarios. */

import type { AdapterContext } from "../../src/contract/adapter.ts";

export function ctxWith(over: Partial<AdapterContext> = {}): AdapterContext {
  return {
    operator: { ref: "op-test", identities: { emails: ["yo@alfa.example"], github: "yo-gh", jira_account: "acc-yo", ado_id: "ado-yo" } },
    now: "2026-11-02T08:00:00Z",
    sensitivity: "N4",
    route: "graph",
    params: {},
    transport: { async request() { return { status: 404, headers: {}, body: {} }; } },
    credentials: { async acquire() { return "tok-test"; } },
    ...over,
  };
}
