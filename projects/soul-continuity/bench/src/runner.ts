/**
 * Runner del banco de continuidad (SE-490, AC-2/AC-3).
 *
 * Ejerce cualquier `ContinuityImpl` contra los dobles y la verdad de
 * truth/scenarios.json, y mide:
 *   - precisión por pregunta (escenarios exactos / escenarios) y P/R por elemento;
 *   - uso de hechos revocados o sustituidos;
 *   - fugas entre operadores (y hacia terceros) y entre niveles;
 *   - cuerpos y tokens en el directorio de estado; mutaciones en las fuentes;
 *   - violaciones del contrato (instantánea y respuesta);
 *   - p95 de Q1 (instantánea + respuesta) con fuentes en memoria.
 * El gate es fail-closed: cualquier excepción inesperada cuenta como fallo.
 */

import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import { type Snapshot, cleanText, levelRank, parseKey, validateSnapshot } from "../../src/contract/claims.ts";
import { type Answer, type ContinuityImpl, type Question, validateAnswer } from "../../src/contract/adapter.ts";
import { makeEnv } from "./doubles.ts";
import {
  BODY_CANARY, type Instant, type Json, TOKEN_CANARY, loadInstalls, loadTenants, loadWorld, ownership,
  readJson, sensitiveStrings,
} from "./world.ts";

export const THRESHOLDS = { precision: 0.9, p95_q1_ms: 2000 };

/**
 * Escenarios de garantía: además del 90 % por pregunta, cada uno tiene que pasar.
 * Sin esta regla, un solo fallo de revocación, TTL o consentimiento quedaría
 * absorbido por el umbral de precisión (lo demostraron los mutantes sin-ttl y
 * consentimiento-como-vacio).
 */
export const CRITICAL_TAGS = ["revocacion", "perfil", "terceros", "inyeccion", "consentimiento-admin", "consentimiento",
  "token-caducado", "ttl", "configuracion", "ac4c", "niveles", "recuentos"];

export interface ScenarioResult {
  id: string;
  q: string;
  tags: string[];
  pass: boolean;
  reasons: string[];
  expected?: string[];
  got?: string[];
  ms?: number;
}

export interface Metrics {
  scenarios: number;
  per_question: Record<string, { total: number; passed: number; precision: number; item_precision: number; item_recall: number }>;
  revoked_used: number;
  cross_operator_leaks: number;
  unknown_refs: number;
  level_leaks: number;
  bodies_persisted: number;
  bodies_in_snapshot: number;
  tokens_on_disk: number;
  source_mutations: number;
  contract_violations: number;
  unclean_titles: number;
  unexpected_errors: number;
  critical_failed: number;
  p95_q1_ms: number;
}

export interface Report {
  impl: string;
  metrics: Metrics;
  gate: { pass: boolean; failures: string[] };
  scenarios: ScenarioResult[];
}

function filesUnder(dir: string): string[] {
  const out: string[] = [];
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) out.push(...filesUnder(p));
    else out.push(p);
  }
  return out;
}

function p95(xs: number[]): number {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil(0.95 * s.length) - 1)];
}

const eqSet = (a: string[], b: string[]) => a.length === b.length && [...a].sort().every((x, i) => x === [...b].sort()[i]);

export async function runBench(impl: ContinuityImpl, opts: { only?: string[]; thresholds?: Partial<typeof THRESHOLDS> } = {}): Promise<Report> {
  const th = { ...THRESHOLDS, ...opts.thresholds };
  const truth = readJson("truth/scenarios.json");
  const instants: Record<Instant, string> = truth.instants;
  const installs = loadInstalls();
  const tenants = loadTenants();
  const worlds = new Map<string, Json>();
  const world = (n: string) => worlds.get(n) ?? (worlds.set(n, loadWorld(n)), worlds.get(n));
  const own = ownership(["pm", "dir", "inv", "doc", "min"]);
  const secrets = new Map<string, string[]>();

  const m: Metrics = {
    scenarios: 0, per_question: {}, revoked_used: 0, cross_operator_leaks: 0, unknown_refs: 0, level_leaks: 0,
    bodies_persisted: 0, bodies_in_snapshot: 0, tokens_on_disk: 0, source_mutations: 0, contract_violations: 0,
    unclean_titles: 0, unexpected_errors: 0, critical_failed: 0, p95_q1_ms: 0,
  };
  const itemStats: Record<string, { tp: number; fp: number; fn: number }> = {};
  const q1ms: number[] = [];
  const results: ScenarioResult[] = [];

  for (const sc of truth.scenarios as Json[]) {
    if (opts.only && !opts.only.includes(sc.id)) continue;
    m.scenarios++;
    const reasons: string[] = [];
    const stateDir = mkdtempSync(join(tmpdir(), "se490-banco-"));
    const corrections = new Map<string, Map<string, string>>(); // operador → clave → acción
    const envLogs: Json[] = [];
    const inst = installs[sc.install];
    const asking = world(inst.world).operator as string;
    const snap = async (installId: string, at: Instant): Promise<Snapshot> => {
      const i = installs[installId];
      const env = makeEnv({ installId, world: world(i.world), tenants, instant: at, installEnv: i.env ?? {} });
      const s = await impl.snapshot({ install: i.config, now: instants[at], stateDir, env, ttl_s: 3600 });
      envLogs.push(...env.log);
      for (const p of validateSnapshot(s)) { m.contract_violations++; reasons.push(`instantánea: ${p}`); }
      if (JSON.stringify(s).includes(BODY_CANARY)) { m.bodies_in_snapshot++; reasons.push("cuerpo en la instantánea"); }
      return s;
    };
    let answer: Answer | null = null;
    let threw: unknown = null;
    let current: Snapshot | null = null;
    let ms = 0;
    try {
      let previous: Snapshot | undefined;
      if (sc.ask.since) previous = await snap(sc.ask.previous_install ?? sc.install, sc.ask.since);
      for (const st of sc.steps ?? []) {
        const sid = st.install ?? sc.install;
        if (st.do === "snapshot") await snap(sid, st.at);
        else if (st.do === "correct") {
          await impl.correct({ install: installs[sid].config, stateDir, now: instants[st.at as Instant], key: st.key, action: st.action, superseded_by: st.superseded_by });
          const ref = installs[sid].config.operator.ref;
          if (!corrections.has(ref)) corrections.set(ref, new Map());
          corrections.get(ref)?.set(st.key, st.action);
        }
      }
      const t0 = performance.now();
      current = await snap(sc.install, (sc.reuse_snapshot ?? sc.at) as Instant);
      const q: Question = { q: sc.ask.q, previous, filter: sc.ask.filter, max_level: sc.ask.max_level, detail: sc.ask.detail };
      try {
        answer = impl.answer(current, q, { install: inst.config, now: instants[sc.at as Instant] });
      } catch (e) {
        threw = e;
      }
      ms = performance.now() - t0;
    } catch (e) {
      m.unexpected_errors++;
      reasons.push(`error inesperado: ${(e as Error).message}`);
    }

    // --- garantías que se miden en todos los escenarios ---------------------
    const files = filesUnder(stateDir);
    for (const f of files) {
      const text = readFileSync(f, "utf8");
      if (text.includes(BODY_CANARY)) { m.bodies_persisted++; reasons.push(`cuerpo persistido: ${f.slice(stateDir.length)}`); }
      if (text.includes(TOKEN_CANARY)) { m.tokens_on_disk++; reasons.push(`token en disco: ${f.slice(stateDir.length)}`); }
    }
    rmSync(stateDir, { recursive: true, force: true });
    const muts = envLogs.filter((l) => l.mutation).length;
    if (muts) { m.source_mutations += muts; reasons.push(`${muts} mutaciones en la fuente`); }

    if (sc.expect_error) {
      if (!threw) reasons.push("se esperaba rechazo y respondió");
      if (answer) answer = null;
    } else if (threw) {
      m.unexpected_errors++;
      reasons.push(`rechazo inesperado: ${(threw as Error).message}`);
    }

    let got: string[] | undefined;
    if (answer) {
      for (const p of validateAnswer(answer)) { m.contract_violations++; reasons.push(`respuesta: ${p}`); }
      const keys = [...answer.items.map((i) => i.key), ...(answer.alerts ?? []), ...(answer.notices ?? [])];
      got = answer.items.map((i) => i.key).sort();
      // Revocados: la última corrección del operador que pregunta.
      const mine = corrections.get(inst.config.operator.ref) ?? new Map();
      for (const k of keys) {
        const a = mine.get(k);
        if (a === "revoke" || a === "supersede") { m.revoked_used++; reasons.push(`usa revocado: ${k}`); }
      }
      // Fugas entre operadores y hacia terceros.
      for (const k of keys) {
        const ref = parseKey(k)?.ref.split("@")[0];
        const owner = ref ? own.get(ref) : undefined;
        if (owner === undefined) { m.unknown_refs++; reasons.push(`referencia desconocida: ${k}`); }
        else if (owner !== asking) { m.cross_operator_leaks++; reasons.push(`fuga (${owner}): ${k}`); }
      }
      // Fugas entre niveles.
      const maxLv = sc.ask.max_level ?? "N4";
      const byKey = new Map((current?.claims ?? []).map((c) => [c.key, c]));
      for (const it of answer.items) {
        const c = byKey.get(it.key);
        if (c && levelRank(c.sensitivity) > levelRank(maxLv)) { m.level_leaks++; reasons.push(`nivel ${c.sensitivity} > ${maxLv}: ${it.key}`); }
        if (it.title != null && cleanText(it.title) !== it.title) { m.unclean_titles++; reasons.push(`título sin limpiar: ${it.key}`); }
      }
      const detail = sc.ask.detail ?? "titulos";
      if (detail === "recuentos") {
        if (!secrets.has(inst.world)) secrets.set(inst.world, sensitiveStrings(inst.world));
        const wire = JSON.stringify(answer);
        const leaked = (secrets.get(inst.world) ?? []).filter((s) => wire.includes(s));
        if (answer.items.length || leaked.length) { m.level_leaks++; reasons.push(`recuentos con contenido (${leaked.length} textos)`); }
      }
      if (detail !== "completo" && answer.items.some((i) => "attrs" in i)) { m.level_leaks++; reasons.push("atributos fuera de completo"); }

      // --- verdad ----------------------------------------------------------
      if (sc.expect) {
        if (!eqSet(got, sc.expect)) reasons.push("conjunto distinto de la verdad");
        const s = (itemStats[sc.ask.q] ??= { tp: 0, fp: 0, fn: 0 });
        s.tp += got.filter((k) => sc.expect.includes(k)).length;
        s.fp += got.filter((k) => !sc.expect.includes(k)).length;
        s.fn += sc.expect.filter((k: string) => !got?.includes(k)).length;
      }
      if (sc.expect_counts) {
        const c = Object.fromEntries(Object.entries(answer.counts).filter(([, v]) => v));
        if (JSON.stringify(Object.entries(c).sort()) !== JSON.stringify(Object.entries(sc.expect_counts).sort())) reasons.push(`recuentos ${JSON.stringify(c)}`);
      }
      if (sc.expect_withheld !== undefined && answer.withheld !== sc.expect_withheld) reasons.push(`retenidos ${answer.withheld} ≠ ${sc.expect_withheld}`);
      for (const [ad, st] of Object.entries(sc.expect_adapters ?? {})) {
        if (answer.adapters[ad]?.status !== st) reasons.push(`${ad}: ${answer.adapters[ad]?.status} ≠ ${st}`);
      }
      for (const [ad, fb] of Object.entries(sc.expect_fallback ?? {})) {
        if (answer.adapters[ad]?.fallback !== fb) reasons.push(`${ad}: alternativa ${answer.adapters[ad]?.fallback} ≠ ${fb}`);
      }
      if (sc.expect_alerts && !eqSet(answer.alerts ?? [], sc.expect_alerts)) reasons.push(`alertas ${JSON.stringify(answer.alerts)}`);
      if (sc.expect_notices && !eqSet(answer.notices ?? [], sc.expect_notices)) reasons.push(`avisos ${JSON.stringify(answer.notices)}`);
    }
    if (sc.ask.q === "Q1" && !sc.expect_error && ms) q1ms.push(ms);
    const pq = (m.per_question[sc.ask.q] ??= { total: 0, passed: 0, precision: 0, item_precision: 1, item_recall: 1 });
    pq.total++;
    const pass = reasons.length === 0;
    if (pass) pq.passed++;
    else if ((sc.tags as string[]).some((t) => CRITICAL_TAGS.includes(t))) m.critical_failed++;
    results.push({ id: sc.id, q: sc.ask.q, tags: sc.tags, pass, reasons, expected: sc.expect, got, ms: Math.round(ms * 10) / 10 });
  }

  for (const [q, v] of Object.entries(m.per_question)) {
    v.precision = v.total ? v.passed / v.total : 0;
    const s = itemStats[q];
    if (s) {
      v.item_precision = s.tp + s.fp ? s.tp / (s.tp + s.fp) : 1;
      v.item_recall = s.tp + s.fn ? s.tp / (s.tp + s.fn) : 1;
    }
  }
  m.p95_q1_ms = Math.round(p95(q1ms) * 10) / 10;

  const failures: string[] = [];
  for (const q of ["Q1", "Q2", "Q3", "Q4"]) {
    const v = m.per_question[q];
    if (!v) { if (!opts.only) failures.push(`${q}: sin escenarios`); }
    else if (v.precision < th.precision) failures.push(`${q}: precisión ${v.precision.toFixed(3)} < ${th.precision}`);
  }
  const alert = m.per_question.ALERT;
  if (alert && alert.passed !== alert.total) failures.push(`ALERT (AC-4c): ${alert.passed}/${alert.total}`);
  for (const k of ["revoked_used", "cross_operator_leaks", "unknown_refs", "level_leaks", "bodies_persisted", "bodies_in_snapshot",
    "tokens_on_disk", "source_mutations", "contract_violations", "unclean_titles", "unexpected_errors"] as const) {
    if (m[k] !== 0) failures.push(`${k} = ${m[k]}`);
  }
  if (m.critical_failed) {
    failures.push(`críticos: ${m.critical_failed} escenarios de garantía fallidos (${results.filter((r) => !r.pass && r.tags.some((t) => CRITICAL_TAGS.includes(t))).map((r) => r.id).join(", ")})`);
  }
  if (!q1ms.length && !opts.only) failures.push("sin medidas de Q1");
  if (m.p95_q1_ms >= th.p95_q1_ms) failures.push(`p95 Q1 ${m.p95_q1_ms} ms ≥ ${th.p95_q1_ms} ms`);
  return { impl: impl.name, metrics: m, gate: { pass: failures.length === 0, failures }, scenarios: results };
}
