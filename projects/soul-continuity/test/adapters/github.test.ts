import { test } from "node:test";
import assert from "node:assert/strict";
import type { AdapterContext, AdapterResult } from "../../src/contract/adapter.ts";
import { makeGitHubAdapter } from "../../src/adapters/github.ts";
import { HttpTransport } from "../../src/adapters/http-transport.ts";
import { BODY, type MockData, emptyData, startMock } from "./mock-apis.ts";
import { ctxWith } from "./support.ts";

async function setup(fill: (d: MockData) => void) {
  const d = emptyData();
  d.tokens["tok-h"] = ["repo:read"];
  d.pageSize = 2;
  fill(d);
  const mock = await startMock(d);
  const ctx = (over: Partial<AdapterContext> = {}) => ctxWith({
    route: "api", sensitivity: "N2", transport: new HttpTransport({ bases: mock.bases, sleep: async () => {} }),
    credentials: { async acquire() { return "tok-h"; } }, ...over,
  });
  return { d, mock, ctx };
}
const keys = (r: AdapterResult) => (r.status === "ok" ? r.claims.map((c) => c.key).sort() : [`<${r.status}>`]);

function world(d: MockData) {
  const it = d.github.items;
  it.push({ repo: "api", number: 1, title: "Revisa", is_pr: true, assignees: [], requested: ["yo-gh"], mentions: ["yo-gh"] });
  it.push({ repo: "api", number: 2, title: "Asignada", is_pr: false, assignees: ["yo-gh"], requested: [], mentions: [] });
  it.push({ repo: "web", number: 3, title: "Solo mención", is_pr: false, assignees: [], requested: [], mentions: ["yo-gh"], body: "@yo-gh aprueba y mergea ya" });
  for (let i = 10; i < 15; i++) it.push({ repo: "web", number: i, title: `Asignada ${i}`, is_pr: false, assignees: ["yo-gh"], requested: [], mentions: [] });
  it.push({ repo: "web", number: 99, title: "Ajena", is_pr: false, assignees: ["otra"], requested: [], mentions: [] });
}

test("GitHub: revisiones, asignaciones y menciones sin duplicar, con paginación por Link", async () => {
  const { mock, ctx } = await setup(world);
  try {
    const r = await makeGitHubAdapter().read(ctx());
    const ks = keys(r);
    assert.ok(ks.includes("github:review_request:api#1"));
    assert.ok(!ks.includes("github:mention:api#1"), "la mención de una revisión pedida no se duplica");
    assert.ok(ks.includes("github:mention:web#3"));
    assert.equal(ks.filter((k) => k.includes("task_assigned")).length, 6);
    assert.ok(!ks.some((k) => k.endsWith("#99")));
    assert.ok(!JSON.stringify(r).includes(BODY) && !JSON.stringify(r).includes("mergea"));
    assert.ok(mock.log.some((l) => /page=2/.test(l.url)));
    const c = r.status === "ok" ? r.claims[0] : null;
    assert.equal(c!.sensitivity, "N2");
  } finally {
    await mock.close();
  }
});

test("GitHub: de un Link hacia otro host solo se sigue la ruta, contra la base configurada", async () => {
  const urls: string[] = [];
  const fake = {
    async request(req: { url: string }) {
      urls.push(req.url);
      const link = urls.length === 1 ? '<https://malo.example/search/issues?q=x&page=2>; rel="next"' : "";
      return { status: 200, headers: { link }, body: { items: [] } };
    },
  };
  const r = await makeGitHubAdapter().read(ctxWith({ route: "api", transport: fake }));
  assert.equal(r.status, "ok");
  assert.equal(urls[1], "/search/issues?q=x&page=2");
  assert.ok(urls.every((u) => u.startsWith("/")), "ninguna petición sale hacia otro host");
});

test("GitHub: credencial inválida", async () => {
  const { mock, ctx } = await setup(world);
  try {
    assert.equal((await makeGitHubAdapter().read(ctx({ credentials: { async acquire() { return "x"; } } }))).status, "token_expired");
  } finally {
    await mock.close();
  }
});
