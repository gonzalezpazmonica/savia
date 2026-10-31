/**
 * CLI del banco:
 *   node --experimental-strip-types src/cli.ts bench   [--impl <módulo>]  → results/bench.json y .md
 *   node --experimental-strip-types src/cli.ts mutants                    → results/mutants.json
 * `--impl` carga un módulo cuyo export `default` (o `impl`) es un ContinuityImpl
 * o una función que lo devuelve: así se mide el núcleo del producto sin tocar el banco.
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { ContinuityImpl } from "../../src/contract/adapter.ts";
import { MUTANTS, makeEmpty } from "./mutants.ts";
import { makeReference } from "./reference/engine.ts";
import { type Report, runBench } from "./runner.ts";
import { ROOT } from "./world.ts";

const RESULTS = join(ROOT, "results");

function markdown(r: Report): string {
  const m = r.metrics;
  const rows = Object.entries(m.per_question).map(([q, v]) =>
    `| ${q} | ${v.passed}/${v.total} | ${(v.precision * 100).toFixed(1)} % | ${(v.item_precision * 100).toFixed(1)} % | ${(v.item_recall * 100).toFixed(1)} % |`);
  const zeros = ["revoked_used", "cross_operator_leaks", "unknown_refs", "level_leaks", "bodies_persisted", "bodies_in_snapshot",
    "tokens_on_disk", "source_mutations", "contract_violations", "unclean_titles", "unexpected_errors", "critical_failed"] as const;
  return [
    `# Banco de continuidad SE-490 — ${r.impl}`, "",
    `Gate: **${r.gate.pass ? "PASS" : "FAIL"}**${r.gate.failures.length ? ` (${r.gate.failures.join("; ")})` : ""}`, "",
    "| Pregunta | Escenarios exactos | Precisión | P por elemento | R por elemento |", "|---|---|---|---|---|", ...rows, "",
    "| Garantía | Valor |", "|---|---|", ...zeros.map((k) => `| ${k} | ${m[k]} |`), `| p95 Q1 (ms) | ${m.p95_q1_ms} |`, "",
    "Escenarios fallidos:", "", ...(r.scenarios.filter((s) => !s.pass).map((s) => `- ${s.id}: ${s.reasons.join("; ")}`)), "",
  ].join("\n");
}

async function loadImpl(spec?: string): Promise<ContinuityImpl> {
  if (!spec) return makeReference();
  const mod = await import(pathToFileURL(resolve(spec)).href);
  const x = mod.default ?? mod.impl;
  return typeof x === "function" ? await x() : x;
}

const [cmd, ...rest] = process.argv.slice(2);
mkdirSync(RESULTS, { recursive: true });
if (cmd === "bench") {
  const i = rest.indexOf("--impl");
  const impl = await loadImpl(i >= 0 ? rest[i + 1] : undefined);
  const r = await runBench(impl);
  const tag = impl.name === "referencia" ? "bench" : `bench-${impl.name}`;
  writeFileSync(join(RESULTS, `${tag}.json`), JSON.stringify(r, null, 1) + "\n");
  writeFileSync(join(RESULTS, `${tag}.md`), markdown(r));
  console.log(markdown(r).split("\n").slice(0, 30).join("\n"));
  process.exit(r.gate.pass ? 0 : 1);
} else if (cmd === "mutants") {
  const out = [];
  let ok = true;
  for (const mu of [...MUTANTS.map((x) => ({ ...x, only: undefined, thresholds: x.thresholds })), { name: "vacia", why: "no responde nada", expect: "precisión", mutations: {}, thresholds: undefined }]) {
    const impl = mu.name === "vacia" ? makeEmpty() : makeReference(mu.mutations, mu.name);
    const r = await runBench(impl, { thresholds: mu.thresholds });
    const caught = !r.gate.pass && r.gate.failures.some((f) => f.includes(mu.expect));
    ok &&= caught;
    out.push({ mutant: mu.name, why: mu.why, expect: mu.expect, caught, failures: r.gate.failures });
    console.log(`${caught ? "DETECTADO" : "NO DETECTADO"}  ${mu.name}: ${r.gate.failures.join("; ")}`);
  }
  writeFileSync(join(RESULTS, "mutants.json"), JSON.stringify(out, null, 1) + "\n");
  process.exit(ok ? 0 : 1);
} else {
  console.error("uso: cli.ts bench [--impl <módulo>] | mutants");
  process.exit(2);
}
