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
    assert.ok(ks.includes("github:review_request:org/api#1"));
    assert.ok(!ks.includes("github:mention:org/api#1"), "la mención de una revisión pedida no se duplica");
    assert.ok(ks.includes("github:mention:org/web#3"));
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

test("GitHub: mismo repositorio y número en dos propietarios son dos elementos distintos", async () => {
  const { mock, ctx } = await setup((d) => {
    d.github.items.push({ owner: "org1", repo: "app", number: 5, title: "Revisa", is_pr: true, assignees: [], requested: ["yo-gh"], mentions: [] });
    d.github.items.push({ owner: "org2", repo: "app", number: 5, title: "Asignada", is_pr: false, assignees: ["yo-gh"], requested: [], mentions: [] });
  });
  try {
    assert.deepEqual(keys(await makeGitHubAdapter().read(ctx())), ["github:review_request:org1/app#5", "github:task_assigned:org2/app#5"]);
  } finally {
    await mock.close();
  }
});

test("GitHub: un repository_url sin propietario no produce elemento", async () => {
  const fake = { async request() { return { status: 200, headers: {}, body: { items: [{ number: 5, title: "x", repository_url: "app" }] } }; } };
  assert.deepEqual(keys(await makeGitHubAdapter().read(ctxWith({ route: "api", transport: fake }))), []);
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

test("GitHub: 403 por límite de tasa es «unavailable»; un 403 sin señal de límite sigue siendo error", async () => {
  const read = (headers: Record<string, string>) => makeGitHubAdapter().read(ctxWith({
    route: "api", transport: { async request() { return { status: 403, headers, body: { message: "x" } }; } },
  }));
  assert.equal((await read({ "retry-after": "60" })).status, "unavailable");
  assert.equal((await read({ "x-ratelimit-remaining": "0" })).status, "unavailable");
  assert.equal((await read({ "x-ratelimit-remaining": "12" })).status, "error");
  assert.equal((await read({})).status, "error");
});
