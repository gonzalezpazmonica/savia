import { test } from "node:test";
import assert from "node:assert/strict";
import type { AdapterContext, AdapterResult } from "../../src/contract/adapter.ts";
import { makeAzureDevOpsAdapter } from "../../src/adapters/azure-devops.ts";
import { HttpTransport } from "../../src/adapters/http-transport.ts";
import { BODY, type MockData, emptyData, startMock } from "./mock-apis.ts";
import { ctxWith } from "./support.ts";

async function setup(fill: (d: MockData) => void) {
  const d = emptyData();
  d.tokens["tok-a"] = ["vso.work", "vso.code"];
  fill(d);
  const mock = await startMock(d);
  const ctx = (over: Partial<AdapterContext> = {}) => ctxWith({
    route: "api", transport: new HttpTransport({ bases: mock.bases, sleep: async () => {} }),
    credentials: { async acquire() { return "tok-a"; } }, ...over,
  });
  return { d, mock, ctx };
}
const keys = (r: AdapterResult) => (r.status === "ok" ? r.claims.map((c) => c.key).sort() : [`<${r.status}>`]);

function world(d: MockData) {
  d.ado.workitems.push({ id: 11, title: "Mío activo", assignedTo: "ado-yo", state: "Active", due: "2026-11-05T00:00:00Z" });
  d.ado.workitems.push({ id: 12, title: "Mío cerrado", assignedTo: "ado-yo", state: "Closed" });
  d.ado.workitems.push({ id: 13, title: "Ajeno", assignedTo: "ado-otra", state: "Active" });
  for (let i = 0; i < 230; i++) d.ado.workitems.push({ id: 1000 + i, title: `Lote ${i}`, assignedTo: "ado-yo", state: "New" });
  d.ado.prs.push({ id: 7, repo: "api", title: "Pide mi voto", status: "active", reviewers: [{ id: "ado-yo", vote: 0 }] });
  d.ado.prs.push({ id: 8, repo: "api", title: "Ya voté", status: "active", reviewers: [{ id: "ado-yo", vote: 10 }] });
  d.ado.prs.push({ id: 9, repo: "web", title: "Sin mí", status: "active", reviewers: [{ id: "ado-otra", vote: 0 }] });
}

test("Azure DevOps: WIQL asignado a mí y abierto, lotes de 200 ids y revisiones sin voto", async () => {
  const { mock, ctx } = await setup(world);
  try {
    const r = await makeAzureDevOpsAdapter().read(ctx({ params: { project: "proj" } }));
    const ks = keys(r);
    assert.equal(ks.filter((k) => k.includes("task_assigned")).length, 231);
    assert.ok(ks.includes("azure-devops:task_assigned:11"));
    assert.ok(!ks.includes("azure-devops:task_assigned:12") && !ks.includes("azure-devops:task_assigned:13"));
    assert.deepEqual(ks.filter((k) => k.includes("review_request")), ["azure-devops:review_request:api!7"]);
    assert.ok(!JSON.stringify(r).includes(BODY));
    const posts = mock.log.filter((l) => l.method === "POST");
    assert.equal(posts.length, 1);
    assert.match(posts[0].url, /^\/proj\/_apis\/wit\/wiql/);
    assert.equal(mock.log.filter((l) => /workitems\?/.test(l.url)).length, 2, "dos lotes (≤200)");
  } finally {
    await mock.close();
  }
});

test("Azure DevOps: sin ado_id lo obtiene de connectionData", async () => {
  const { mock, ctx } = await setup(world);
  try {
    const r = await makeAzureDevOpsAdapter().read(ctx({ operator: { ref: "op", identities: { emails: [] } } }));
    assert.ok(keys(r).includes("azure-devops:review_request:api!7"));
    assert.ok(mock.log.some((l) => /connectionData/.test(l.url)));
  } finally {
    await mock.close();
  }
});

test("Azure DevOps: 203 de la página de login es credencial caducada", async () => {
  const fake = { async request() { return { status: 203, headers: {}, body: "<html>login</html>" }; } };
  assert.equal((await makeAzureDevOpsAdapter().read(ctxWith({ route: "api", transport: fake }))).status, "token_expired");
});

test("Azure DevOps: PAT por autenticación básica si se configura", async () => {
  const seen: string[] = [];
  const fake = { async request(req: { headers?: Record<string, string> }) { seen.push(req.headers?.Authorization ?? ""); return { status: 200, headers: {}, body: { workItems: [], value: [] } }; } };
  await makeAzureDevOpsAdapter().read(ctxWith({ route: "api", transport: fake, params: { auth: "pat" } }));
  assert.equal(seen[0], `Basic ${Buffer.from(":tok-test").toString("base64")}`);
});
