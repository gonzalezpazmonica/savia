/**
 * Núcleo de Soul Continuidad v1 (SE-490): instantánea Q1–Q4 sobre afirmaciones con TTL,
 * revocación y sustitución, con libro de correcciones por operador.
 *
 * Semántica: `src/contract/CONTRATO.md`. Portado del núcleo de referencia del banco de Labs
 * sin sus interruptores de mutación, con los adaptadores inyectados (el núcleo no conoce
 * ninguna fuente por dentro) y con el fail-safe durable.
 *
 * Estado por operador en `<stateDir>/op-<hash>/`:
 *   ledger.jsonl     libro de correcciones (solo filas del operador)
 *   snapshot.json    última instantánea (metadatos y referencias, nunca cuerpos ni tokens)
 *   history/<ts>.json instantáneas anteriores para Q3 (las últimas HISTORY_MAX)
 */

import { readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import {
  type Claim, LEVELS, SNAPSHOT_SCHEMA, type Snapshot, TTL_MAX_S, applyLedgerAndTtl, fingerprint, foldLedger, isUsable,
  iso, levelRank, maxLevel, parseKey, parseTs,
} from "../contract/claims.ts";
import {
  ADAPTERS, type Answer, type AnswerItem, type ContinuityImpl, type CorrectionRequest, DEFAULT_SENSITIVITY,
  type InstallationConfig, type Question, type SnapshotRequest, type SourceAdapter, isLevel,
} from "../contract/adapter.ts";
import { assertRunning } from "./failsafe.ts";
import { appendJsonl, ensureDir, operatorDir, readJson, readJsonl, writeJson } from "./store.ts";

export type AdapterRegistry = Partial<Record<string, SourceAdapter>>;

export interface Engine extends ContinuityImpl {
  lastSnapshot(stateDir: string, operatorRef: string): Snapshot | null;
  /** Instantánea más reciente con `issued_at` ≤ `at` (para Q3 «desde»). */
  snapshotAt(stateDir: string, operatorRef: string, at: string): Snapshot | null;
  ledger(stateDir: string, operatorRef: string): unknown[];
  /** Instantánea guardada con el libro actual aplicado (correcciones hechas después de leerla). */
  applyCorrections(snap: Snapshot, stateDir: string, now: string): Snapshot;
  /** AC-5: borra las afirmaciones de un adaptador de la caché y del historial. Devuelve ficheros tocados. */
  purgeAdapter(stateDir: string, operatorRef: string, adapter: string): number;
}

const DAY = 86_400_000;
const LEDGER = "ledger.jsonl";
const CACHE = "snapshot.json";
const HISTORY = "history";
export const HISTORY_MAX = 50;

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

function saveHistory(dir: string, snap: Snapshot): void {
  const h = ensureDir(join(dir, HISTORY));
  writeJson(join(h, `${snap.issued_at.replace(/[:.]/g, "-")}.json`), snap);
  const files = readdirSync(h).filter((f) => f.endsWith(".json")).sort();
  for (const f of files.slice(0, Math.max(0, files.length - HISTORY_MAX))) rmSync(join(h, f), { force: true });
}

export function makeEngine(adapters: AdapterRegistry, name = "soul-core"): Engine {
  const engine: Engine = {
    name,

    async snapshot(req: SnapshotRequest): Promise<Snapshot> {
      assertRunning(req.stateDir);
      const now = parseTs(req.now);
      const ttl = req.ttl_s ?? 3600;
      if (now === null) throw new Error("instante inválido");
      if (!Number.isInteger(ttl) || ttl < 1 || ttl > TTL_MAX_S) throw new Error("TTL obligatorio");
      const op = req.install.operator;
      const expires = now + ttl * 1000;
      const status: Snapshot["adapters"] = {};
      const entries = new Map<string, InstallationConfig["sources"][number] | null>();
      for (const s of req.install.sources) {
        if (!(ADAPTERS as readonly string[]).includes(s.adapter)) {
          status[String(s.adapter).slice(0, 40)] = { status: "unknown_adapter" };
          continue;
        }
        if (entries.has(s.adapter)) { entries.set(s.adapter, null); status[s.adapter] = { status: "duplicate_adapter" }; continue; }
        entries.set(s.adapter, s);
      }
      const claims: Claim[] = [];
      for (const an of ADAPTERS) {
        if (!entries.has(an)) { status[an] = { status: "not_configured" }; continue; }
        const s = entries.get(an);
        if (!s) continue;
        const problem = consentProblem(s, now);
        if (problem) { status[an] = { status: problem }; continue; }
        const ad = adapters[an];
        if (!ad) {
          status[an] = { status: "unavailable", message: "adaptador no instalado en esta versión", fallback: "manual" };
          continue;
        }
        const route = s.route ?? ad.routes[0];
        if (!ad.routes.includes(route)) { status[an] = { status: "error", message: "ruta no admitida" }; continue; }
        const level = maxLevel(isLevel(s.sensitivity) ? s.sensitivity : DEFAULT_SENSITIVITY[an], DEFAULT_SENSITIVITY[an]);
        let r;
        try {
          r = await ad.read({
            operator: op, now: req.now, sensitivity: level, route, params: { ...(s.params ?? {}) },
            transport: req.env.transport, credentials: req.env.credentials,
          });
        } catch {
          // Fail-closed: un adaptador que revienta no aporta nada y no tumba a los demás.
          status[an] = { status: "error", route, message: "el adaptador falló al leer" };
          continue;
        }
        if (r.status === "ok") {
          const own = r.claims.filter((c) => c.key.startsWith(`${an}:`));
          status[an] = { status: "ok", route: r.route, claims: own.length };
          claims.push(...own);
        } else {
          status[an] = { status: r.status, route: r.route, message: r.message, fallback: r.fallback ?? null };
        }
      }
      const dir = operatorDir(req.stateDir, op.ref);
      const ledger = foldLedger(readJsonl(join(dir, LEDGER)), op.ref);
      const final = applyLedgerAndTtl(claims, ledger, now, expires);
      const snap: Snapshot = {
        schema: SNAPSHOT_SCHEMA, operator_ref: op.ref, issued_at: req.now, expires_at: iso(expires), claims: final, adapters: status,
      };
      writeJson(join(dir, CACHE), snap);
      saveHistory(dir, snap);
      return snap;
    },

    async correct(req: CorrectionRequest): Promise<void> {
      if (!parseKey(req.key)) throw new Error("clave inválida");
      if (parseTs(req.now) === null) throw new Error("instante inválido");
      if (req.action === "supersede" && !req.superseded_by) throw new Error("supersede necesita superseded_by");
      const dir = operatorDir(req.stateDir, req.install.operator.ref);
      appendJsonl(join(dir, LEDGER), {
        operator_ref: req.install.operator.ref, action: req.action, key: req.key, at: req.now,
        reason: req.reason ?? "", superseded_by: req.superseded_by ?? null,
      });
    },

    answer(snap: Snapshot, q: Question, ctx: { install: InstallationConfig; now: string }): Answer {
      const now = parseTs(ctx.now);
      if (now === null) throw new Error("instante inválido");
      if ((parseTs(snap.expires_at) ?? 0) <= now) throw new Error("instantánea caducada");
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
          if (failed.has(c.source_refs[0].adapter)) continue;
          picked.push({ c, change: "removed" });
        }
      } else if (q.q === "ALERT") {
        const rules = new Set((ctx.install.alert_rules ?? []).map((r) => r.sender.toLowerCase()));
        const alerts: string[] = [];
        const notices: string[] = [];
        for (const c of usable(snap).filter((x) => x.claim_type === "awaiting_reply")) {
          if (!rules.has(String(c.attrs.last_from).toLowerCase())) continue;
          if (c.source_refs[0].route === "web") notices.push(c.key);
          else if (c.attrs.sender_auth === "tenant" || c.attrs.sender_auth === "dkim_dmarc") alerts.push(c.key);
        }
        return { q: q.q, detail, items: [], counts: {}, withheld: 0, adapters, alerts: alerts.sort(), notices: notices.sort() };
      } else {
        throw new Error("pregunta desconocida");
      }

      let withheld = 0;
      const items: AnswerItem[] = [];
      const counts: Answer["counts"] = {};
      for (const { c, change } of picked) {
        if (levelRank(c.sensitivity) > levelRank(maxLv)) { withheld++; continue; }
        counts[c.claim_type] = (counts[c.claim_type] ?? 0) + 1;
        if (detail === "recuentos") continue;
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

    lastSnapshot(stateDir: string, operatorRef: string): Snapshot | null {
      const s = readJson<Snapshot | null>(join(operatorDir(stateDir, operatorRef), CACHE), null);
      return s && s.operator_ref === operatorRef ? s : null;
    },

    snapshotAt(stateDir: string, operatorRef: string, at: string): Snapshot | null {
      const t = parseTs(at);
      if (t === null) throw new Error("instante inválido");
      const h = join(operatorDir(stateDir, operatorRef), HISTORY);
      let best: Snapshot | null = null;
      for (const f of (() => { try { return readdirSync(h); } catch { return []; } })()) {
        const s = readJson<Snapshot | null>(join(h, f), null);
        const it = s ? parseTs(s.issued_at) : null;
        if (!s || s.operator_ref !== operatorRef || it === null || it > t) continue;
        if (!best || it > (parseTs(best.issued_at) as number)) best = s;
      }
      return best;
    },

    ledger(stateDir: string, operatorRef: string): unknown[] {
      return [...foldLedger(readJsonl(join(operatorDir(stateDir, operatorRef), LEDGER)), operatorRef).values()];
    },

    applyCorrections(snap: Snapshot, stateDir: string, now: string): Snapshot {
      const t = parseTs(now);
      const exp = parseTs(snap.expires_at);
      if (t === null || exp === null) throw new Error("instante inválido");
      const ledger = foldLedger(readJsonl(join(operatorDir(stateDir, snap.operator_ref), LEDGER)), snap.operator_ref);
      return { ...snap, claims: applyLedgerAndTtl(snap.claims, ledger, t, exp) };
    },

    purgeAdapter(stateDir: string, operatorRef: string, adapter: string): number {
      const dir = operatorDir(stateDir, operatorRef);
      const h = join(dir, HISTORY);
      const files = [join(dir, CACHE), ...(() => { try { return readdirSync(h).map((f) => join(h, f)); } catch { return []; } })()];
      let n = 0;
      for (const f of files) {
        const s = readJson<Snapshot | null>(f, null);
        if (!s) continue;
        s.claims = s.claims.filter((c) => c.source_refs[0]?.adapter !== adapter && !c.key.startsWith(`${adapter}:`));
        s.adapters[adapter] = { status: "consent_revoked" };
        writeJson(f, s);
        n++;
      }
      return n;
    },
  };
  return engine;
}
