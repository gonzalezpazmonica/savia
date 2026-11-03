import { test } from "node:test";
import assert from "node:assert/strict";
import { runBench } from "../bench/src/runner.ts";
import impl, { benchRegistry } from "../src/core/bench-impl.ts";
import { makeApiAdapters } from "../src/adapters/index.ts";

const ZERO = ["revoked_used", "cross_operator_leaks", "level_leaks", "bodies_persisted", "bodies_in_snapshot", "tokens_on_disk",
  "source_mutations", "contract_violations", "unexpected_errors", "critical_failed"] as const;

const summary = (r: Awaited<ReturnType<typeof runBench>>) =>
  `${r.gate.failures.join(" | ")} :: ${r.scenarios.filter((s) => !s.pass).map((s) => `${s.id}: ${s.reasons.slice(0, 2).join("; ")}`).join(" || ")}`;

test("banco SE-490: el núcleo con los adaptadores reales de API contra los dobles pasa el gate (AC-3)", async () => {
  const r = await runBench(impl());
  assert.equal(r.metrics.scenarios, 80);
  assert.deepEqual(r.gate.failures, [], summary(r));
  assert.equal(r.gate.pass, true);
  for (const [q, v] of Object.entries(r.metrics.per_question)) assert.ok(v.precision >= 0.9, `${q} ${v.precision}`);
  for (const k of ZERO) assert.equal(r.metrics[k], 0, k);
});

test("el banco del núcleo usa de verdad los adaptadores de API del producto en sus rutas", async () => {
  const reg = benchRegistry();
  const real = makeApiAdapters();
  for (const name of Object.keys(real)) {
    const a = reg[name];
    assert.ok(a, name);
    for (const r of real[name as keyof typeof real].routes) assert.ok(a.routes.includes(r), `${name}:${r}`);
  }
  // Control: si un adaptador real falla, el banco lo nota (no lo tapa la referencia).
  const roto = benchRegistry();
  const gh = roto.github;
  assert.ok(gh);
  roto.github = { ...gh, read: async (ctx) => ({ status: "ok", route: ctx.route, claims: [] }) };
  const { makeEngine } = await import("../src/core/engine.ts");
  const r = await runBench(makeEngine(roto, "github-vacio"));
  assert.equal(r.gate.pass, false, "un GitHub que no devuelve nada suspende el banco");
});

test("control: el núcleo con solo los adaptadores de referencia también pasa", async () => {
  const r = await runBench(impl({ reference: true }));
  assert.equal(r.gate.pass, true, summary(r));
});
