import { test } from "node:test";
import assert from "node:assert/strict";
import type { AdapterContext, AdapterResult } from "../../src/contract/adapter.ts";
import { makeJiraAdapter } from "../../src/adapters/jira.ts";
import { HttpTransport } from "../../src/adapters/http-transport.ts";
import { BODY, type MockData, emptyData, startMock } from "./mock-apis.ts";
import { ctxWith } from "./support.ts";

async function setup(fill: (d: MockData) => void) {
  const d = emptyData();
  d.tokens["tok-j"] = ["read:jira-work"];
  d.pageSize = 2;
  fill(d);
  const mock = await startMock(d);
  const ctx = (over: Partial<AdapterContext> = {}) => ctxWith({
    route: "api", transport: new HttpTransport({ bases: mock.bases, sleep: async () => {} }),
    credentials: { async acquire() { return "tok-j"; } }, ...over,
  });
  return { d, mock, ctx };
}
const keys = (r: AdapterResult) => (r.status === "ok" ? r.claims.map((c) => c.key).sort() : [`<${r.status}>`]);

function issues(d: MockData) {
  d.jira.issues.push({ key: "PRJ-1", summary: "Mía abierta", assignee: "acc-yo", status: "In Progress", duedate: "2026-11-04" });
  d.jira.issues.push({ key: "PRJ-2", summary: "Mía terminada", assignee: "acc-yo", status: "Done" });
  d.jira.issues.push({ key: "PRJ-3", summary: "De otra persona", assignee: "acc-otra", status: "To Do" });
  for (let i = 4; i < 9; i++) d.jira.issues.push({ key: `PRJ-${i}`, summary: `Mía ${i}`, assignee: "acc-yo", status: "To Do" });
}

test("Jira: solo lo asignado a mí y no terminado, con paginación por nextPageToken", async () => {
  const { mock, ctx } = await setup(issues);
  try {
    const r = await makeJiraAdapter().read(ctx());
    assert.deepEqual(keys(r), ["jira:task_assigned:PRJ-1", "jira:task_assigned:PRJ-4", "jira:task_assigned:PRJ-5", "jira:task_assigned:PRJ-6", "jira:task_assigned:PRJ-7", "jira:task_assigned:PRJ-8"]);
    const c = r.status === "ok" ? r.claims.find((x) => x.key.endsWith("PRJ-1"))! : null;
    assert.equal(c!.due_at, "2026-11-04T00:00:00.000Z");
    assert.equal(c!.awaiting_operator, true);
    assert.ok(!JSON.stringify(r).includes(BODY), "sin descripciones");
    assert.ok(mock.log.some((l) => /nextPageToken=/.test(l.url)));
    assert.ok(mock.log.every((l) => /fields=summary/.test(decodeURIComponent(l.url))));
  } finally {
    await mock.close();
  }
});

test("Jira: sin /search/jql cae a la búsqueda clásica con startAt", async () => {
  const { mock, ctx } = await setup((d) => { issues(d); d.jira.legacyOnly = true; });
  try {
    const r = await makeJiraAdapter().read(ctx());
    assert.equal(keys(r).length, 6);
    assert.ok(mock.log.some((l) => /startAt=2/.test(l.url)));
  } finally {
    await mock.close();
  }
});

test("Jira: el tope de páginas falla cerrado", async () => {
  const { mock, ctx } = await setup(issues);
  try {
    assert.equal((await makeJiraAdapter({ maxPages: 1 }).read(ctx())).status, "unavailable");
  } finally {
    await mock.close();
  }
});

test("Jira: autenticación básica con token de API (email:token) si se configura", async () => {
  const seen: string[] = [];
  const fake = { async request(req: { headers?: Record<string, string> }) { seen.push(req.headers?.Authorization ?? ""); return { status: 200, headers: {}, body: { issues: [], isLast: true } }; } };
  await makeJiraAdapter().read(ctxWith({ route: "api", transport: fake, params: { auth: "basic" }, credentials: { async acquire() { return "yo@alfa.example:api-token"; } } }));
  assert.equal(seen[0], `Basic ${Buffer.from("yo@alfa.example:api-token").toString("base64")}`);
});

test("Jira: credencial caducada", async () => {
  const { mock, ctx } = await setup(issues);
  try {
    assert.equal((await makeJiraAdapter().read(ctx({ credentials: { async acquire() { return "x"; } } }))).status, "token_expired");
  } finally {
    await mock.close();
  }
});
