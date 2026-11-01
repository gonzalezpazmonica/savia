import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applyLedgerAndTtl, claimKey, cleanText, foldLedger, levelRank, maxLevel, parseKey, parseTs,
  validateClaim, validateSnapshot, SNAPSHOT_SCHEMA, type Claim,
} from "../../src/contract/claims.ts";
import { validateAdapterResult, validateAnswer } from "../../src/contract/adapter.ts";

const NOW = "2026-11-03T08:00:00Z";
function claim(over: Partial<Claim> = {}): Claim {
  return {
    key: "m365-mail:awaiting_reply:pm-th01@pm-m01",
    claim_type: "awaiting_reply",
    state: "OBSERVED",
    source_refs: [{ adapter: "m365-mail", route: "graph", ref: "pm-th01" }],
    sensitivity: "N4",
    observed_at: NOW,
    valid_until: "2026-11-03T09:00:00Z",
    open: true,
    awaiting_operator: true,
    attrs: {},
    ...over,
  };
}

test("una afirmación bien formada es válida", () => {
  assert.deepEqual(validateClaim(claim()), []);
});

test("sin procedencia, sin TTL o con estado desconocido no es válida", () => {
  assert.match(validateClaim(claim({ source_refs: [] })).join(), /procedencia/);
  assert.match(validateClaim(claim({ valid_until: "" })).join(), /TTL/);
  assert.match(validateClaim(claim({ state: "ACTIVE" as never })).join(), /estado desconocido/);
  assert.match(validateClaim(claim({ claim_type: "meeting" })).join(), /no casa/);
});

test("valid_until anterior a observed_at solo se admite si está EXPIRED", () => {
  const past = "2026-11-02T08:00:00Z";
  assert.match(validateClaim(claim({ valid_until: past })).join(), /posterior/);
  assert.deepEqual(validateClaim(claim({ valid_until: past, state: "EXPIRED" })), []);
});

test("un cuerpo en attrs se rechaza", () => {
  assert.match(validateClaim(claim({ attrs: { body: "x" } })).join(), /cuerpo/);
  assert.match(validateClaim(claim({ attrs: { bodyPreview: "x" } })).join(), /cuerpo/);
  assert.match(validateClaim(claim({ attrs: { nested: {} as never } })).join(), /no escalar/);
});

test("un title sin limpiar o sin marca de no fiable se rechaza", () => {
  assert.match(validateClaim(claim({ title: "a\u0007b", untrusted_text: true })).join(), /sin limpiar/);
  assert.match(validateClaim(claim({ title: "ok" })).join(), /untrusted_text/);
  assert.deepEqual(validateClaim(claim({ title: "ok", untrusted_text: true })), []);
});

test("cleanText quita controles y bidi, normaliza y trunca", () => {
  assert.equal(cleanText("a\u202eb\u0000c\n\nd"), "a b c d");
  assert.equal(cleanText("x".repeat(300))?.length, 120);
  assert.equal(cleanText("   "), null);
  assert.equal(cleanText(42), null);
});

test("parseTs exige zona; levelRank es fail-closed", () => {
  assert.equal(parseTs("2026-11-03T08:00:00"), null);
  assert.equal(parseTs("2026-11-03T08:00:00+01:00"), Date.parse("2026-11-03T07:00:00Z"));
  assert.equal(levelRank("N9"), 4);
  assert.equal(maxLevel("N1", "N3"), "N3");
});

test("claimKey rechaza partes con dos puntos; parseKey es su inversa", () => {
  assert.throws(() => claimKey("jira", "task_assigned", "a:b"));
  assert.deepEqual(parseKey(claimKey("jira", "task_assigned", "PMX-1")), { adapter: "jira", type: "task_assigned", ref: "PMX-1" });
  assert.equal(parseKey("sin-formato"), null);
});

test("el libro solo aplica filas del operador; revoke no vuelve aunque la fuente repita", () => {
  const k = claim().key;
  const ledger = foldLedger([
    { operator_ref: "op-pm", action: "revoke", key: k, at: NOW },
    { operator_ref: "op-dir", action: "restore", key: k, at: NOW },
    "basura",
    { operator_ref: "op-pm", action: "supersede", key: "jira:task_assigned:PMX-1", at: NOW },
  ], "op-pm");
  assert.equal(ledger.get(k)?.action, "revoke");
  assert.equal(ledger.has("jira:task_assigned:PMX-1"), false, "supersede sin superseded_by se ignora");
  const now = Date.parse(NOW);
  const [c] = applyLedgerAndTtl([claim()], ledger, now, now + 3600_000);
  assert.equal(c.state, "REVOKED");
  const [d] = applyLedgerAndTtl([claim()], foldLedger([], "op-pm"), now, now + 3600_000);
  assert.equal(d.state, "OBSERVED");
});

test("TTL: lo caducado pasa a EXPIRED y valid_until se recorta a la instantánea", () => {
  const now = Date.parse(NOW);
  const [c] = applyLedgerAndTtl([claim({ valid_until: "2026-11-03T07:00:00Z" })], new Map(), now, now + 60_000);
  assert.equal(c.state, "EXPIRED");
  const [d] = applyLedgerAndTtl([claim({ valid_until: "2026-12-01T00:00:00Z" })], new Map(), now, now + 60_000);
  assert.equal(d.valid_until, "2026-11-03T08:01:00.000Z");
});

test("validateSnapshot: TTL, duplicados y caducidad de las afirmaciones", () => {
  const snap = { schema: SNAPSHOT_SCHEMA, operator_ref: "op-pm", issued_at: NOW, expires_at: "2026-11-03T09:00:00Z", claims: [claim()], adapters: {} };
  assert.deepEqual(validateSnapshot(snap), []);
  assert.match(validateSnapshot({ ...snap, expires_at: "2026-11-05T09:00:00Z" }).join(), /TTL/);
  assert.match(validateSnapshot({ ...snap, claims: [claim(), claim()] }).join(), /duplicada/);
  assert.match(validateSnapshot({ ...snap, expires_at: "2026-11-03T08:30:00Z" }).join(), /supera la caducidad/);
});

test("validateAdapterResult: un fallo no aporta claims y lleva mensaje; claves del propio adaptador", () => {
  assert.deepEqual(validateAdapterResult({ status: "ok", route: "graph", claims: [claim()] }, "m365-mail"), []);
  assert.match(validateAdapterResult({ status: "ok", route: "graph", claims: [claim()] }, "jira").join(), /otro adaptador/);
  assert.match(validateAdapterResult({ status: "token_expired", route: "graph" }, "jira").join(), /mensaje/);
  assert.match(validateAdapterResult({ status: "token_expired", route: "graph", message: "x", claims: [] }, "jira").join(), /fail-closed/);
  assert.match(validateAdapterResult({ status: "vale", route: "graph", message: "x" }, "jira").join(), /desconocido/);
});

test("validateAnswer: recuentos sin elementos y attrs solo en completo", () => {
  const base = { q: "Q1", detail: "titulos", items: [], counts: {}, withheld: 0, adapters: {} };
  assert.deepEqual(validateAnswer(base), []);
  const item = { key: claim().key, claim_type: "awaiting_reply", source_refs: [], age_s: 1 };
  assert.match(validateAnswer({ ...base, detail: "recuentos", items: [item] }).join(), /recuentos/);
  assert.match(validateAnswer({ ...base, items: [{ ...item, attrs: {} }] }).join(), /attrs/);
  assert.deepEqual(validateAnswer({ ...base, detail: "completo", items: [{ ...item, attrs: {} }] }), []);
});
