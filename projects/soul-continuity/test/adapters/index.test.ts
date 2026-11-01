/**
 * Banco de continuidad de Labs (80 escenarios con verdad escrita antes) contra
 * los adaptadores de API de este paquete. El gate es el de AC-3 sin rebajas.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { runBench } from "../../bench/src/runner.ts";
import type { Transport } from "../../src/contract/adapter.ts";
import { DESCRIPTORS } from "../../src/adapters/descriptors.ts";
import { makeApiAdapters } from "../../src/adapters/index.ts";
import { BODY_CANARY } from "../../bench/src/world.ts";
import { makeHarness } from "./bench-harness.ts";

const ZERO = ["revoked_used", "cross_operator_leaks", "level_leaks", "bodies_persisted", "bodies_in_snapshot", "tokens_on_disk", "source_mutations", "contract_violations", "unexpected_errors", "critical_failed"] as const;

const summary = (r: Awaited<ReturnType<typeof runBench>>) =>
  `${r.gate.failures.join(" | ")} :: ${r.scenarios.filter((s) => !s.pass).map((s) => `${s.id}: ${s.reasons.slice(0, 2).join("; ")}`).join(" || ")}`;

test("registro: un adaptador por cada descriptor de API, con su propósito", () => {
  const a = makeApiAdapters();
  assert.deepEqual(Object.keys(a).sort(), Object.keys(DESCRIPTORS).sort());
  for (const [n, ad] of Object.entries(a)) {
    assert.equal(ad.name, n);
    assert.equal(ad.purpose, DESCRIPTORS[n as keyof typeof DESCRIPTORS].purpose);
  }
});

test("banco (dobles en memoria): gate AC-3 PASS con los adaptadores de API", async () => {
  const r = await runBench(makeHarness({ mode: "memory" }));
  assert.equal(r.metrics.scenarios, 80);
  assert.ok(r.gate.pass, summary(r));
  for (const k of ZERO) assert.equal(r.metrics[k], 0, k);
  for (const [q, v] of Object.entries(r.metrics.per_question)) assert.equal(v.precision, 1, `${q}: ${v.passed}/${v.total}`);
});

test("banco por HTTP local con delta del correo entre instantes: gate PASS", async () => {
  const r = await runBench(makeHarness({ mode: "http", delta: true }));
  assert.equal(r.metrics.scenarios, 80);
  assert.ok(r.gate.pass, summary(r));
  for (const k of ZERO) assert.equal(r.metrics[k], 0, k);
  for (const [q, v] of Object.entries(r.metrics.per_question)) assert.equal(v.precision, 1, `${q}: ${v.passed}/${v.total}`);
  assert.ok(r.metrics.p95_q1_ms < 2000);
});

test("sensibilidad: si se pierden los enviados, el banco suspende Q2 (el gate puede fallar)", async () => {
  const dropSent = (t: Transport): Transport => ({
    async request(req) {
      const r = await t.request(req);
      if (/sentitems/.test(req.url) && r.status === 200) return { ...r, body: { value: [] } };
      return r;
    },
  });
  const r = await runBench(makeHarness({ mode: "memory", wrapTransport: dropSent, name: "sin-enviados" }));
  assert.equal(r.gate.pass, false);
  assert.ok(r.gate.failures.some((f) => /Q2/.test(f)), r.gate.failures.join(" | "));
});

test("sensibilidad: un 403 en Graph tratado como vacío por un adaptador sí se detectaría (consentimiento)", async () => {
  const forbid = (t: Transport): Transport => ({
    async request(req) {
      if (req.service === "graph") return { status: 403, headers: {}, body: { error: { code: "ErrorAccessDenied" } } };
      return t.request(req);
    },
  });
  const r = await runBench(makeHarness({ mode: "memory", wrapTransport: forbid, name: "graph-403" }), { only: ["B01", "B03", "A01"] });
  // Con 403 los adaptadores fallan cerrado (admin_consent_required): no inventan nada, pero tampoco aciertan B01/B03.
  assert.equal(r.gate.pass, false);
  assert.equal(r.metrics.unexpected_errors, 0);
  // El fallo tiene que ser el cierre por consentimiento, no cualquier otro.
  const a01 = r.scenarios.find((s) => s.id === "A01");
  assert.ok(a01?.reasons.includes("m365-calendar: admin_consent_required ≠ ok"), a01?.reasons.join(" | "));
});

test("robustez: aunque la API ignore $select y mande cuerpos, no llegan al disco ni a la instantánea", async () => {
  const withBodies = (t: Transport): Transport => ({
    async request(req) {
      const r = await t.request(req);
      const b = r.body as { value?: Record<string, unknown>[] } | null;
      if (r.status === 200 && b && Array.isArray(b.value)) {
        return { ...r, body: { ...b, value: b.value.map((x) => ({ ...x, body: { content: BODY_CANARY }, bodyPreview: BODY_CANARY })) } };
      }
      return r;
    },
  });
  const r = await runBench(makeHarness({ mode: "memory", wrapTransport: withBodies, name: "api-con-cuerpos" }));
  assert.ok(r.gate.pass, summary(r));
  assert.equal(r.metrics.bodies_persisted + r.metrics.bodies_in_snapshot, 0);
});
