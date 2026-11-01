import { test } from "node:test";
import assert from "node:assert/strict";
import { runBench } from "../bench/src/runner.ts";
import impl from "../src/core/bench-impl.ts";

test("banco SE-490: el núcleo con los adaptadores de referencia pasa el gate (AC-3)", async () => {
  const r = await runBench(await impl());
  assert.deepEqual(r.gate.failures, []);
  assert.equal(r.gate.pass, true);
  for (const [q, v] of Object.entries(r.metrics.per_question)) assert.ok(v.precision >= 0.9, `${q} ${v.precision}`);
  assert.equal(r.metrics.critical_failed, 0);
});
