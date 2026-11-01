/**
 * Núcleo de referencia trivial de Soul Continuidad para el banco.
 *
 * Cumple CONTRATO.md y nada más. Cada interruptor de `Mutations` rompe una
 * garantía concreta; el runner tiene que suspender a cada mutante (ver
 * src/mutants.ts). Sin dependencias: solo `node:fs`, `node:path` y `node:crypto`.
 */

import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import {
  type Claim, LEVELS, SNAPSHOT_SCHEMA, type Snapshot, TTL_MAX_S, applyLedgerAndTtl, fingerprint, foldLedger,
  isUsable, iso, levelRank, maxLevel, parseKey, parseTs,
} from "../../../src/contract/claims.ts";
import {
  ADAPTERS, type Answer, type AnswerItem, type ContinuityImpl, type CorrectionRequest, DEFAULT_SENSITIVITY,
  type InstallationConfig, type Question, type SnapshotRequest, isLevel,
} from "../../../src/contract/adapter.ts";
import { makeAdapters } from "./adapters.ts";

export interface Mutations {
  ignoreLedger?: boolean;        // el libro no se aplica: lo revocado vuelve
  persistBodies?: boolean;       // guarda respuestas crudas con cuerpos
  persistToken?: boolean;        // escribe el token en disco
  sharedCache?: boolean;         // la caché de otro operador se mezcla en la respuesta
  ignoreLevel?: boolean;         // no retiene lo que supera max_level
  countsLeak?: boolean;          // en `recuentos` devuelve elementos con título
  fromHeaderAlerts?: boolean;    // identidad del remitente por `From`
  noSentItems?: boolean;         // «esperando» sin mirar enviados
  ccCounts?: boolean;            // CC cuenta como destinatario directo
  readsThirdParty?: boolean;     // lee calendario delegado y buzón compartido
  noJqlFilter?: boolean;         // Jira sin filtro de asignación ni estado
  consentAsEmpty?: boolean;      // consentimiento de administración tratado como «ok, vacío»
  followsMutatingLinks?: boolean;// la receta web visita un enlace que aprueba
  obeysInjection?: boolean;      // un texto de la fuente puede revocar hechos
  noTtl?: boolean;               // responde con instantáneas caducadas
  staleAsRemoved?: boolean;      // Q3 da por desaparecido lo de un adaptador caído
  slowMs?: number;               // latencia añadida en cada instantánea
}

const DAY = 86_400_000;
const LEDGER = "ledger.jsonl";
const CACHE = "snapshot.json";

function opDir(stateDir: string, ref: string, m: Mutations): string {
  const d = m.sharedCache ? stateDir : join(stateDir, "op-" + createHash("sha256").update(ref).digest("hex").slice(0, 16));
  mkdirSync(d, { recursive: true });
  return d;
}

function readLedgerRows(dir: string): unknown[] {
  const p = join(dir, LEDGER);
  if (!existsSync(p)) return [];
  return readFileSync(p, "utf8").split("\n").filter(Boolean).map((l) => {
    try { return JSON.parse(l); } catch { return null; }
  });
}

function consentProblem(s: InstallationConfig["sources"][number], now: number): string | null {
  if (typeof s.purpose !== "string" || !s.purpose.trim()) return "no_purpose";
  const g = parseTs(s.consent?.granted_at);
  if (g === null || g > now) return "no_consent";
  if (s.consent?.revoked_at != null) {
    const r = parseTs(s.consent.revoked_at);
    if (r === null || r <= now) return "consent_revoked";
  }
  return null;
}

export function makeReference(m: Mutations = {}, name = "referencia"): ContinuityImpl {
  const adapters = makeAdapters(m);

  return {
    name,

    async snapshot(req: SnapshotRequest): Promise<Snapshot> {
      if (m.slowMs) await new Promise((r) => setTimeout(r, m.slowMs));
      const now = parseTs(req.now);
      const ttl = req.ttl_s ?? 3600;
      if (now === null) throw new Error("instante inválido");
      if (!Number.isInteger(ttl) || ttl < 1 || ttl > TTL_MAX_S) throw new Error("TTL obligatorio");
      const op = req.install.operator;
      const expires = now + ttl * 1000;
      const status: Snapshot["adapters"] = {};
      const entries = new Map<string, InstallationConfig["sources"][number] | null>();
      for (const s of req.install.sources) {
        if (!(ADAPTERS as readonly string[]).includes(s.adapter)) { status[String(s.adapter).slice(0, 40)] = { status: "unknown_adapter" }; continue; }
        if (entries.has(s.adapter)) { entries.set(s.adapter, null); status[s.adapter] = { status: "duplicate_adapter" }; continue; }
        entries.set(s.adapter, s);
      }
      const claims: Claim[] = [];
      const params: Record<string, unknown> = {};
      for (const name of ADAPTERS) {
        if (!entries.has(name)) { status[name] = { status: "not_configured" }; continue; }
        const s = entries.get(name);
        if (!s) continue;
        const problem = consentProblem(s, now);
        if (problem) { status[name] = { status: problem }; continue; }
        const route = s.route ?? adapters[name].routes[0];
        if (!adapters[name].routes.includes(route)) { status[name] = { status: "error", message: "ruta no admitida" }; continue; }
        const level = maxLevel(isLevel(s.sensitivity) ? s.sensitivity : DEFAULT_SENSITIVITY[name], DEFAULT_SENSITIVITY[name]);
        const p = { ...(s.params ?? {}) };
        const r = await adapters[name].read({
          operator: op, now: req.now, sensitivity: level, route, params: p,
          transport: req.env.transport, credentials: req.env.credentials,
        });
        Object.assign(params, p);
        if (r.status === "ok") {
          status[name] = { status: "ok", route: r.route, claims: r.claims.length };
          claims.push(...r.claims);
        } else if (m.consentAsEmpty && r.status === "admin_consent_required") {
          status[name] = { status: "ok", route: r.route, claims: 0 };
        } else {
          status[name] = { status: r.status, route: r.route, message: r.message, fallback: r.fallback ?? null };
        }
      }
      const dir = opDir(req.stateDir, op.ref, m);
      if (m.obeysInjection) {
        for (const k of (params.__injected as string[] | undefined) ?? []) {
          appendFileSync(join(dir, LEDGER), JSON.stringify({ operator_ref: op.ref, action: "revoke", key: k, at: req.now }) + "\n");
        }
      }
      const ledger = m.ignoreLedger ? new Map() : foldLedger(readLedgerRows(dir), op.ref);
      const final = applyLedgerAndTtl(claims, ledger, now, expires);
      const snap: Snapshot = { schema: SNAPSHOT_SCHEMA, operator_ref: op.ref, issued_at: req.now, expires_at: iso(expires), claims: final, adapters: status };
      // Caché propia del operador: solo la instantánea (metadatos y referencias).
      writeFileSync(join(dir, m.sharedCache ? `${CACHE}.${op.ref}` : CACHE), JSON.stringify(snap));
      if (m.persistBodies) writeFileSync(join(dir, "raw.json"), JSON.stringify(params.__raw ?? []));
      if (m.persistToken) {
        const tok = await req.env.credentials.acquire("github", []);
        writeFileSync(join(dir, "token.txt"), tok);
      }
      if (m.sharedCache) {
        for (const f of readdirSync(dir).filter((x) => x.startsWith(`${CACHE}.`) && x !== `${CACHE}.${op.ref}`)) {
          const other = JSON.parse(readFileSync(join(dir, f), "utf8")) as Snapshot;
          snap.claims.push(...other.claims.filter((c) => !snap.claims.some((x) => x.key === c.key)));
        }
      }
      return snap;
    },

    async correct(req: CorrectionRequest): Promise<void> {
      if (!parseKey(req.key)) throw new Error("clave inválida");
      if (req.action === "supersede" && !req.superseded_by) throw new Error("supersede necesita superseded_by");
      const dir = opDir(req.stateDir, req.install.operator.ref, m);
      const row = { operator_ref: req.install.operator.ref, action: req.action, key: req.key, at: req.now, reason: req.reason ?? "", superseded_by: req.superseded_by ?? null };
      appendFileSync(join(dir, LEDGER), JSON.stringify(row) + "\n");
    },

    answer(snap: Snapshot, q: Question, ctx: { install: InstallationConfig; now: string }): Answer {
      const now = parseTs(ctx.now) as number;
      if (!m.noTtl && (parseTs(snap.expires_at) as number) <= now) throw new Error("instantánea caducada");
      if (snap.operator_ref !== ctx.install.operator.ref) throw new Error("instantánea de otro operador");
      const detail = q.detail ?? "titulos";
      const maxLv = q.max_level ?? "N4";
      if (!(LEVELS as readonly string[]).includes(maxLv)) throw new Error("nivel desconocido");
      const f = q.filter ?? {};
      const pass = (c: Claim) => (!f.types || f.types.includes(c.claim_type))
        && (!f.adapters || f.adapters.includes(c.source_refs[0].adapter))
        && (!f.ref_prefix || c.source_refs[0].ref.startsWith(f.ref_prefix));
      const usable = (s: Snapshot) => s.claims.filter((c) => isUsable(c) && pass(c));
      const adapters = Object.fromEntries(Object.entries(snap.adapters).map(([k, v]) => [k, { status: v.status, message: v.message, fallback: v.fallback ?? null }]));

      let picked: { c: Claim; change?: AnswerItem["change"] }[] = [];
      const sod = Math.floor(now / DAY) * DAY;
      const inWin = (v: string | null | undefined, a: number, b: number, closed = false) => {
        const t = parseTs(v);
        return t !== null && t >= a && (closed ? t <= b : t < b);
      };
      if (q.q === "Q1") {
        picked = usable(snap).filter((c) => (c.claim_type === "meeting" && c.open && inWin(c.due_at, sod, sod + 2 * DAY))
          || (["task_assigned", "review_request", "awaiting_reply"].includes(c.claim_type) && c.open)
          || c.claim_type === "document_comments").map((c) => ({ c }));
      } else if (q.q === "Q2") {
        picked = usable(snap).filter((c) => c.open && c.awaiting_operator
          && ["awaiting_reply", "mention", "task_assigned", "review_request"].includes(c.claim_type)).map((c) => ({ c }));
      } else if (q.q === "Q4") {
        picked = usable(snap).filter((c) => c.open && (
          (["task_assigned", "dated_commitment", "review_request"].includes(c.claim_type) && inWin(c.due_at, now - 7 * DAY, now + 14 * DAY, true))
          || (c.claim_type === "meeting" && inWin(c.due_at, now, now + 14 * DAY, true)))).map((c) => ({ c }));
      } else if (q.q === "Q3") {
        const prev = q.previous;
        if (!prev) throw new Error("Q3 necesita la instantánea anterior");
        if (prev.operator_ref !== snap.operator_ref) throw new Error("no se comparan instantáneas de operadores distintos");
        const before = new Map(usable(prev).map((c) => [c.key, c]));
        const nowMap = new Map(usable(snap).map((c) => [c.key, c]));
        const corrected = new Set(snap.claims.filter((c) => c.state === "REVOKED" || c.state === "SUPERSEDED").map((c) => c.key));
        const failed = new Set(Object.entries(snap.adapters).filter(([, v]) => v.status !== "ok").map(([k]) => k));
        for (const [k, c] of nowMap) {
          if (!before.has(k)) picked.push({ c, change: "added" });
          else if (fingerprint(before.get(k) as Claim) !== fingerprint(c)) picked.push({ c, change: "changed" });
        }
        for (const [k, c] of before) {
          if (nowMap.has(k) || corrected.has(k)) continue;
          if (!m.staleAsRemoved && failed.has(c.source_refs[0].adapter)) continue;
          picked.push({ c, change: "removed" });
        }
      } else if (q.q === "ALERT") {
        const rules = new Set((ctx.install.alert_rules ?? []).map((r) => r.sender.toLowerCase()));
        const alerts: string[] = [];
        const notices: string[] = [];
        for (const c of usable(snap).filter((x) => x.claim_type === "awaiting_reply")) {
          if (!rules.has(String(c.attrs.last_from))) continue;
          if (c.source_refs[0].route === "web") notices.push(c.key);
          else if (c.attrs.sender_auth === "tenant" || c.attrs.sender_auth === "dkim_dmarc") alerts.push(c.key);
        }
        return { q: q.q, detail, items: [], counts: {}, withheld: 0, adapters, alerts: alerts.sort(), notices: notices.sort() };
      }

      let withheld = 0;
      const items: AnswerItem[] = [];
      const counts: Answer["counts"] = {};
      for (const { c, change } of picked) {
        if (!m.ignoreLevel && levelRank(c.sensitivity) > levelRank(maxLv)) { withheld++; continue; }
        counts[c.claim_type] = (counts[c.claim_type] ?? 0) + 1;
        if (detail === "recuentos" && !m.countsLeak) continue;
        const it: AnswerItem = {
          key: c.key, claim_type: c.claim_type,
          source_refs: c.source_refs.map((r) => ({ adapter: r.adapter, route: r.route, ref: r.ref })),
          age_s: Math.max(0, Math.round((now - (parseTs(c.event_at) ?? parseTs(c.observed_at) ?? now)) / 1000)),
          title: c.title ?? null, untrusted_text: c.title != null,
        };
        if (change) it.change = change;
        if (detail === "completo") it.attrs = { ...c.attrs };
        items.push(it);
      }
      items.sort((a, b) => a.key.localeCompare(b.key));
      return { q: q.q, detail, items, counts, withheld, adapters };
    },
  };
}
