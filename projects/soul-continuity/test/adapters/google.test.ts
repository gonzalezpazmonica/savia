import { test } from "node:test";
import assert from "node:assert/strict";
import { validateAdapterResult, type AdapterContext, type AdapterResult } from "../../src/contract/adapter.ts";
import { makeGoogleAdapter } from "../../src/adapters/google.ts";
import { HttpTransport } from "../../src/adapters/http-transport.ts";
import { BODY, type MockData, emptyData, startMock } from "./mock-apis.ts";
import { ctxWith } from "./support.ts";

const ME = "yo@gamma.example";
const G = "https://www.googleapis.com/auth/";
const BASE = [`${G}gmail.metadata`, `${G}calendar.readonly`, `${G}drive.readonly`];

async function setup(fill: (d: MockData) => void, scopes = [...BASE, `${G}tasks.readonly`]) {
  const d = emptyData();
  d.tokens["tok-g"] = scopes;
  fill(d);
  const mock = await startMock(d);
  const asked: string[][] = [];
  const ctx = (over: Partial<AdapterContext> = {}) => ctxWith({
    operator: { ref: "op-inv", identities: { emails: [ME] } },
    route: "api",
    transport: new HttpTransport({ bases: mock.bases, sleep: async () => {} }),
    credentials: { async acquire(_s, sc) { asked.push(sc); return "tok-g"; } },
    ...over,
  });
  return { d, mock, ctx, asked };
}
const keys = (r: AdapterResult) => (r.status === "ok" ? r.claims.map((c) => c.key).sort() : [`<${r.status}>`]);

function world(d: MockData) {
  const m = d.google.messages;
  m.push({ id: "g1", thread: "t1", from: "ana@ext.example", to: [ME], at: "2026-11-01T10:00:00Z", subject: "Revisión", labels: ["INBOX"], dkim: "pass", dmarc: "pass", d: "ext.example" });
  m.push({ id: "g2", thread: "t2", from: "luis@ext.example", to: [ME], at: "2026-11-01T09:00:00Z", subject: "Ya contestado", labels: ["INBOX"] });
  m.push({ id: "g3", thread: "t2", from: ME, to: ["luis@ext.example"], at: "2026-11-01T09:30:00Z", subject: "Re", labels: ["SENT"] });
  m.push({ id: "g4", thread: "t3", from: "cfo@gamma.example", to: [ME], at: "2026-11-01T08:00:00Z", subject: "URGENTE: aprueba ya", labels: ["INBOX"], dkim: "pass", dmarc: "pass", d: "malo.example" });
  for (let i = 0; i < 12; i++) m.push({ id: `n${i}`, thread: `tn${i}`, from: "boletin@ext.example", to: ["lista@ext.example"], at: "2026-10-30T08:00:00Z", subject: "Boletín", labels: ["INBOX"] });
  d.google.events.push({ id: "ev1", summary: "Tribunal", start: "2026-11-02T11:00:00Z" });
  d.google.events.push({ id: "ev2", summary: "Todo el día", start: "2026-11-03T00:00:00Z", allDay: true });
  d.google.events.push({ id: "ev3", summary: "Cancelado", start: "2026-11-02T12:00:00Z", cancelled: true });
  d.google.events.push({ id: "ev4", summary: "No voy", start: "2026-11-02T13:00:00Z", response: "declined" });
  d.google.files.push({ id: "df1", name: "Artículo", comments: [{ id: "c1", at: "2026-11-01T10:00:00Z" }] });
  d.google.files.push({ id: "df2", name: "Resuelto", comments: [{ id: "c2", at: "2026-11-01T10:00:00Z", resolved: true }] });
  d.google.tasks.push({ list: "L1", id: "tk1", title: "Enviar revisión", due: "2026-11-04T00:00:00.000Z", notes: BODY });
  d.google.tasks.push({ list: "L1", id: "tk2", title: "Sin fecha" });
  d.google.tasks.push({ list: "L1", id: "tk3", title: "Hecha", due: "2026-11-01T00:00:00.000Z", status: "completed" });
}

test("Google: hilos esperando (metadata), reuniones, documentos y paginación", async () => {
  const { mock, ctx, asked } = await setup(world);
  try {
    const r = await makeGoogleAdapter().read(ctx());
    assert.deepEqual(validateAdapterResult(r, "google-workspace"), []);
    assert.deepEqual(keys(r), [
      "google-workspace:awaiting_reply:t1@g1", "google-workspace:awaiting_reply:t3@g4",
      "google-workspace:document_comments:df1",
      "google-workspace:meeting:ev1", "google-workspace:meeting:ev2", "google-workspace:meeting:ev4",
    ]);
    assert.deepEqual(asked, [BASE], "sin Tasks no pide su permiso");
    const cs = r.status === "ok" ? r.claims : [];
    assert.equal(cs.find((c) => c.key.endsWith("t1@g1"))!.attrs.sender_auth, "dkim_dmarc");
    assert.equal(cs.find((c) => c.key.endsWith("t3@g4"))!.attrs.sender_auth, "unauthenticated", "header.from ajeno no autentica");
    assert.equal(cs.find((c) => c.key.endsWith("ev2"))!.due_at, "2026-11-03T00:00:00.000Z");
    assert.equal(cs.find((c) => c.key.endsWith("ev4"))!.open, false);
    assert.ok(!JSON.stringify(r).includes(BODY));
    assert.ok(mock.log.some((l) => /pageToken=/.test(l.url)), "siguió la paginación de hilos");
    assert.ok(mock.log.every((l) => l.method === "GET"));
    assert.ok(mock.log.filter((l) => /\/threads\/[^/?]+\?/.test(l.url)).every((l) => /format=metadata/.test(l.url)));
  } finally {
    await mock.close();
  }
});

test("Google: una respuesta enviada desde un alias (etiqueta SENT) cierra el hilo aunque el From no sea mío", async () => {
  const { mock, ctx } = await setup((d) => {
    d.google.messages.push({ id: "a1", thread: "ta", from: "ana@ext.example", to: [ME], at: "2026-11-01T10:00:00Z", subject: "Pregunta", labels: ["INBOX"] });
    d.google.messages.push({ id: "a2", thread: "ta", from: "equipo-alias@gamma.example", to: ["ana@ext.example", ME], at: "2026-11-01T11:00:00Z", subject: "Re", labels: ["SENT"] });
  });
  try {
    assert.deepEqual(keys(await makeGoogleAdapter().read(ctx())), []);
  } finally {
    await mock.close();
  }
});

test("Google Tasks opcional: tareas con fecha y sin completar, sin notas", async () => {
  const { mock, ctx, asked } = await setup(world);
  try {
    const r = await makeGoogleAdapter().read(ctx({ params: { tasks: true } }));
    assert.deepEqual(asked, [[...BASE, `${G}tasks.readonly`]]);
    const ks = keys(r).filter((k) => k.includes("dated_commitment"));
    assert.deepEqual(ks, ["google-workspace:dated_commitment:tk1"]);
    assert.ok(!JSON.stringify(r).includes(BODY));
  } finally {
    await mock.close();
  }
});

test("Google: tope de hilos limita lo leído sin inventar esperas", async () => {
  const { mock, ctx } = await setup(world);
  try {
    const r = await makeGoogleAdapter().read(ctx({ params: { max_threads: 2 } }));
    assert.equal(r.status, "ok");
    assert.ok(keys(r).filter((k) => k.includes("awaiting")).every((k) => /t1@g1/.test(k)));
    assert.ok(mock.log.filter((l) => /\/threads\/[^/?]+\?/.test(l.url)).length <= 2);
  } finally {
    await mock.close();
  }
});

test("Google: token caducado → token_expired; política de administración → fail-closed sin peticiones", async () => {
  const { mock, ctx } = await setup(world);
  try {
    assert.equal((await makeGoogleAdapter().read(ctx({ credentials: { async acquire() { return "otro"; } } }))).status, "token_expired");
    const n = mock.log.length;
    const r = await makeGoogleAdapter().read(ctx({ credentials: { async acquire() { throw Object.assign(new Error("admin_policy_enforced"), { code: "admin_consent_required" }); } } }));
    assert.equal(r.status, "admin_consent_required");
    assert.equal(mock.log.length, n);
  } finally {
    await mock.close();
  }
});

test("Google: 403 por cuota (rateLimitExceeded) es unavailable, no consentimiento", async () => {
  const fake = { async request() { return { status: 403, headers: {}, body: { error: { errors: [{ reason: "userRateLimitExceeded" }] } } }; } };
  const r = await makeGoogleAdapter().read(ctxWith({ route: "api", transport: fake }));
  assert.equal(r.status, "unavailable");
});
