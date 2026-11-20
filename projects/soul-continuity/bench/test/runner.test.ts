import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { runBench } from "../src/runner.ts";
import { makeReference } from "../src/reference/engine.ts";
import { MUTANTS, makeEmpty } from "../src/mutants.ts";
import { ROOT } from "../src/world.ts";

const truth = JSON.parse(readFileSync(join(ROOT, "truth/scenarios.json"), "utf8"));

test("la verdad cubre AC-2: ≥ 60 escenarios Q1–Q4 y todas las categorías obligatorias", () => {
  const s = truth.scenarios as { tags: string[]; ask: { q: string } }[];
  assert.ok(s.filter((x) => x.ask.q !== "ALERT").length >= 60);
  const tag = (t: string) => s.filter((x) => x.tags.includes(t)).length;
  for (const t of ["revocacion", "dos-instantes", "perfil", "terceros", "inyeccion", "consentimiento-admin", "token-caducado", "ac4c"]) {
    assert.ok(tag(t) >= 1, `falta la categoría ${t}`);
  }
  assert.ok(tag("esperando") >= 8);
  for (const t of ["otro-cliente", "responder-a-todos", "reenvio"]) assert.ok(tag(t) >= 2, `falta ${t}`);
  for (const q of ["Q1", "Q2", "Q3", "Q4"]) assert.ok(s.some((x) => x.ask.q === q));
  // AC-4c: el mismo remitente por las dos rutas.
  const s1 = truth.scenarios.find((x: { id: string }) => x.id === "S01");
  const s2 = truth.scenarios.find((x: { id: string }) => x.id === "S02");
  assert.ok(s1.expect_alerts.some((k: string) => s2.expect_notices.includes(k)));
});

test("la implementación de referencia pasa el gate completo", async () => {
  const r = await runBench(makeReference());
  assert.deepEqual(r.gate.failures, []);
  assert.equal(r.metrics.scenarios, truth.scenarios.length);
  for (const q of ["Q1", "Q2", "Q3", "Q4"]) assert.ok(r.metrics.per_question[q].precision >= 0.9);
});

test("la implementación vacía suspende por precisión", async () => {
  const r = await runBench(makeEmpty());
  assert.equal(r.gate.pass, false);
  assert.ok(r.gate.failures.some((f) => f.startsWith("Q1: precisión")));
});

for (const mu of MUTANTS) {
  test(`mutante ${mu.name} (${mu.why}) suspende por ${mu.expect}`, async () => {
    const r = await runBench(makeReference(mu.mutations, mu.name), { only: mu.only, thresholds: mu.thresholds });
    assert.equal(r.gate.pass, false, "el gate no puede dar PASS");
    assert.ok(r.gate.failures.some((f) => f.includes(mu.expect)), `fallos: ${r.gate.failures.join("; ")}`);
    // Y la referencia, en los mismos escenarios y umbrales, pasa: el fallo es del mutante.
    const ok = await runBench(makeReference(), { only: mu.only, thresholds: mu.thresholds && { p95_q1_ms: 2000 } });
    assert.deepEqual(ok.gate.failures, []);
  });
}

test("una implementación que lanza en snapshot no da PASS (fail-closed)", async () => {
  const ref = makeReference();
  const broken = { ...ref, name: "rota", snapshot: async () => { throw new Error("boom"); } };
  const r = await runBench(broken, { only: ["B01"] });
  assert.equal(r.gate.pass, false);
  assert.ok(r.gate.failures.some((f) => f.includes("unexpected_errors")));
});

test("una instantánea que no cumple el contrato cuenta como violación", async () => {
  const ref = makeReference();
  const bad = { ...ref, name: "sin-ttl-en-claims", snapshot: async (req: Parameters<typeof ref.snapshot>[0]) => {
    const s = await ref.snapshot(req);
    return { ...s, claims: s.claims.map((c) => ({ ...c, valid_until: "" })) };
  } };
  const r = await runBench(bad, { only: ["B18"] });
  assert.ok(r.metrics.contract_violations > 0);
  assert.equal(r.gate.pass, false);
});

test("un título con controles en la respuesta cuenta como texto no inerte", async () => {
  const ref = makeReference();
  const dirty = { ...ref, name: "titulo-sucio", answer: (...a: Parameters<typeof ref.answer>) => {
    const r = ref.answer(...a);
    return { ...r, items: r.items.map((i) => ({ ...i, title: `${i.title}\u0007` })) };
  } };
  const r = await runBench(dirty, { only: ["I01"] });
  assert.ok(r.metrics.unclean_titles > 0);
  assert.equal(r.gate.pass, false);
});

// --- Latencia p95 de Q1: una parada puntual del equipo no suspende, una lentitud sostenida sí ----------
// Fallo real de main (windows-latest): p95 3620,9 ms con ~20-80 ms en las otras ejecuciones. Con 18
// escenarios Q1, el p95 es el máximo: UNA medida con una parada de reloj de pared bastaba para suspender.
const LATENCY = { only: ["B01", "B02", "T01"], thresholds: { p95_q1_ms: 400 } };
const stallFirst = (calls: number, ms: number) => {
  const ref = makeReference();
  let n = 0;
  return {
    ...ref,
    name: `parada-${calls}`,
    answer: ((...a: Parameters<typeof ref.answer>) => {
      if (++n <= calls) { const t = performance.now(); while (performance.now() - t < ms) { /* parada del equipo */ } }
      return ref.answer(...a);
    }) as typeof ref.answer,
  };
};

test("p95 Q1: una parada puntual de 600 ms en una medida no suspende el gate (la mediana la absorbe)", async () => {
  const r = await runBench(stallFirst(1, 600), LATENCY);
  assert.deepEqual(r.gate.failures, []);
  assert.ok(r.metrics.p95_q1_ms < 400, `p95 ${r.metrics.p95_q1_ms}`);
});

test("p95 Q1: una lentitud sostenida (3 de 5 medidas de un escenario) sigue suspendiendo", async () => {
  const r = await runBench(stallFirst(3, 600), LATENCY);
  assert.equal(r.gate.pass, false);
  assert.ok(r.gate.failures.some((f) => f.includes("p95 Q1")), r.gate.failures.join("; "));
});

test("p95 Q1: un fallo del equipo no oculta un fallo real: 1 sola medida (reps=1) vuelve a suspender por la parada", async () => {
  const r = await runBench(stallFirst(1, 600), { ...LATENCY, q1_reps: 1 });
  assert.equal(r.gate.pass, false);
});

test("p95 Q1: el informe dice qué escenarios fueron los más lentos y sus medidas", async () => {
  const r = await runBench(stallFirst(3, 600), LATENCY);
  const f = r.gate.failures.find((x) => x.includes("p95 Q1")) ?? "";
  assert.match(f, /mediana de 5/);
  assert.match(f, /B01/);
  assert.ok(r.scenarios.find((s) => s.id === "B01")?.samples_ms?.length === 5);
});
