/**
 * Arnés de prueba: mide los adaptadores de API de este paquete con el banco de
 * continuidad de Labs (bench/), sin tocar el banco.
 *
 * Es el núcleo de referencia del banco con los adaptadores sustituidos por los
 * de `src/adapters` para las rutas de API. Las rutas web (receta de Outlook en
 * la web y adaptador `web`) son otra pieza de SE-490 y usan aquí la referencia.
 * No es el producto: el núcleo real lo publica su propia pieza.
 *
 * Dos modos:
 * - `memory`: los adaptadores hablan con los dobles en memoria del banco.
 * - `http`: los adaptadores usan `HttpTransport` contra un servidor HTTP local que
 *   reenvía a los dobles y, encima, sirve delta queries del correo (rondas con
 *   `$skiptoken`/`$deltatoken` y `@removed`), para que la caché delta se ejerza
 *   entre los dos instantes del banco.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import {
  type Claim, SNAPSHOT_SCHEMA, type Snapshot, TTL_MAX_S, applyLedgerAndTtl, foldLedger, iso, maxLevel, parseTs,
} from "../../src/contract/claims.ts";
import {
  ADAPTERS, type ContinuityImpl, type CorrectionRequest, DEFAULT_SENSITIVITY, type InstallationConfig, type SnapshotRequest,
  type SourceAdapter, type Transport, isLevel,
} from "../../src/contract/adapter.ts";
import { makeReference } from "../../bench/src/reference/engine.ts";
import { makeAdapters as referenceAdapters } from "../../bench/src/reference/adapters.ts";
import { makeApiAdapters } from "../../src/adapters/index.ts";
import { FileDeltaCache, operatorDir } from "../../src/adapters/delta-cache.ts";
import { HttpTransport } from "../../src/adapters/http-transport.ts";

const LEDGER = "ledger.jsonl";

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

function readLedger(dir: string): unknown[] {
  const p = join(dir, LEDGER);
  if (!existsSync(p)) return [];
  return readFileSync(p, "utf8").split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } });
}

// ---------------------------------------------------------------------------
// Servidor HTTP que reenvía a los dobles del banco y sirve delta del correo

class Proxy {
  srv: Server | null = null;
  base = "";
  current: Transport | null = null;
  /** deltatoken → foto (id → JSON) del final de la ronda. */
  private snaps = new Map<string, { snap: Map<string, string>; select: string }>();
  /** skiptoken → resto de la ronda en curso. */
  private rounds = new Map<string, { rest: unknown[]; snap: Map<string, string>; select: string }>();

  async start(): Promise<string> {
    if (this.srv) return this.base;
    this.srv = createServer((req, res) => {
      let raw = "";
      req.on("data", (c) => (raw += c));
      req.on("end", () => {
        this.handle(req.method ?? "GET", req.url ?? "/", req.headers as Record<string, string>, raw)
          .then((r) => { res.writeHead(r.status, { "content-type": "application/json", ...r.headers }); res.end(JSON.stringify(r.body)); })
          .catch(() => { res.writeHead(500); res.end("{}"); });
      });
    });
    await new Promise<void>((r) => this.srv!.listen(0, "127.0.0.1", r));
    this.base = `http://127.0.0.1:${(this.srv.address() as AddressInfo).port}`;
    this.srv.unref();
    return this.base;
  }

  private async handle(method: string, rawUrl: string, h: Record<string, string>, raw: string) {
    const m = /^\/svc\/([a-z]+)(\/.*)$/.exec(rawUrl);
    if (!m || !this.current) return { status: 404, headers: {}, body: {} };
    const [, service, url] = m;
    const headers: Record<string, string> = {};
    if (h.authorization) headers.Authorization = h.authorization;
    if (h.action) headers.Action = h.action;
    const body = raw ? JSON.parse(raw) : undefined;
    const delta = /^(\/v1\.0\/me\/mailFolders\/(inbox|sentitems)\/messages)\/delta(\?.*)?$/.exec(url);
    if (service === "graph" && delta) return this.delta(delta[1], new URLSearchParams(delta[3]?.slice(1) ?? ""), headers, h.prefer ?? "");
    const r = await this.current.request({ service, method, url, headers, body });
    return { status: r.status, headers: Object.fromEntries(Object.entries(r.headers).map(([k, v]) => [k, String(v)])), body: r.body };
  }

  private async delta(path: string, q: URLSearchParams, headers: Record<string, string>, prefer: string) {
    const size = Number(/odata\.maxpagesize=(\d+)/.exec(prefer)?.[1] ?? 10);
    const link = (k: string, v: string) => `https://graph.example${path}/delta?${k}=${v}`;
    // Como en Graph, el $select de la ronda inicial viaja dentro de los tokens.
    const page = (items: unknown[], snap: Map<string, string>, select: string) => {
      const body: Record<string, unknown> = { value: items.slice(0, size) };
      if (items.length > size) {
        const sk = randomUUID();
        this.rounds.set(sk, { rest: items.slice(size), snap, select });
        body["@odata.nextLink"] = link("$skiptoken", sk);
      } else {
        const dt = randomUUID();
        this.snaps.set(dt, { snap, select });
        body["@odata.deltaLink"] = link("$deltatoken", dt);
      }
      return { status: 200, headers: {}, body };
    };
    const sk = q.get("$skiptoken");
    if (sk) {
      const r = this.rounds.get(sk);
      if (!r) return { status: 410, headers: {}, body: { error: { code: "SyncStateNotFound" } } };
      return page(r.rest, r.snap, r.select);
    }
    const dt = q.get("$deltatoken");
    const prev = dt === null ? null : this.snaps.get(dt);
    if (dt !== null && !prev) return { status: 410, headers: {}, body: { error: { code: "SyncStateNotFound" } } };
    const select = prev ? prev.select : (q.get("$select") ?? "");
    // Foto actual de la carpeta a través del doble (con el mismo $select y el token del adaptador).
    const now = new Map<string, string>();
    let next: string | undefined = `${path}?$top=1000&$select=${select}`;
    while (next) {
      const r = await this.current!.request({ service: "graph", method: "GET", url: next, headers });
      if (r.status !== 200) return { status: r.status, headers: r.headers, body: r.body };
      const b = r.body as { value?: { id: string }[]; "@odata.nextLink"?: string };
      for (const x of b.value ?? []) now.set(x.id, JSON.stringify(x));
      next = b["@odata.nextLink"];
    }
    if (!prev) return page([...now.values()].map((s) => JSON.parse(s)), now, select);
    const before = prev.snap;
    const changes: unknown[] = [];
    for (const [id, s] of now) if (before.get(id) !== s) changes.push(JSON.parse(s));
    for (const id of before.keys()) if (!now.has(id)) changes.push({ id, "@removed": { reason: "deleted" } });
    return page(changes, now, select);
  }
}

const proxy = new Proxy();

export interface HarnessOptions {
  mode: "memory" | "http";
  /** Caché delta en el directorio de estado (solo con sentido en modo http). */
  delta?: boolean;
  /** Envuelve el transporte que ven los adaptadores de API (para sabotajes en tests). */
  wrapTransport?: (t: Transport) => Transport;
  name?: string;
}

export function makeHarness(o: HarnessOptions): ContinuityImpl {
  const ref = makeReference({}, o.name ?? "adaptadores-api");
  const web = referenceAdapters({});

  return {
    name: o.name ?? `adaptadores-api-${o.mode}${o.delta ? "-delta" : ""}`,
    correct: (req: CorrectionRequest) => ref.correct(req),
    answer: (snap, q, ctx) => ref.answer(snap, q, ctx),

    async snapshot(req: SnapshotRequest): Promise<Snapshot> {
      const now = parseTs(req.now);
      const ttl = req.ttl_s ?? 3600;
      if (now === null) throw new Error("instante inválido");
      if (!Number.isInteger(ttl) || ttl < 1 || ttl > TTL_MAX_S) throw new Error("TTL obligatorio");
      let transport: Transport = req.env.transport;
      if (o.mode === "http") {
        const base = await proxy.start();
        proxy.current = req.env.transport;
        transport = new HttpTransport({
          bases: Object.fromEntries(["graph", "google", "jira", "ado", "github"].map((s) => [s, `${base}/svc/${s}`])),
          sleep: async () => {},
        });
      }
      if (o.wrapTransport) transport = o.wrapTransport(transport);
      // Los dobles del banco firman como `mx.google.example` (dominio reservado de pruebas).
      const mine = makeApiAdapters({ cache: o.delta ? new FileDeltaCache(req.stateDir) : undefined, gmailAuthservIds: ["mx.google.example"] });
      const pick = (name: string, route: string): SourceAdapter | undefined => {
        if (name === "web" || route === "web") return web[name];
        return (mine as Record<string, SourceAdapter>)[name];
      };
      const op = req.install.operator;
      const status: Snapshot["adapters"] = {};
      const entries = new Map<string, InstallationConfig["sources"][number] | null>();
      for (const s of req.install.sources) {
        if (!(ADAPTERS as readonly string[]).includes(s.adapter)) { status[String(s.adapter).slice(0, 40)] = { status: "unknown_adapter" }; continue; }
        if (entries.has(s.adapter)) { entries.set(s.adapter, null); status[s.adapter] = { status: "duplicate_adapter" }; continue; }
        entries.set(s.adapter, s);
      }
      const claims: Claim[] = [];
      for (const name of ADAPTERS) {
        if (!entries.has(name)) { status[name] = { status: "not_configured" }; continue; }
        const s = entries.get(name);
        if (!s) continue;
        const problem = consentProblem(s, now);
        if (problem) { status[name] = { status: problem }; continue; }
        const route = s.route ?? (name === "web" ? "web" : (mine as Record<string, SourceAdapter>)[name].routes[0]);
        const a = pick(name, route);
        if (!a || !a.routes.includes(route)) { status[name] = { status: "error", message: "ruta no admitida" }; continue; }
        const level = maxLevel(isLevel(s.sensitivity) ? s.sensitivity : DEFAULT_SENSITIVITY[name], DEFAULT_SENSITIVITY[name]);
        const isWeb = name === "web" || route === "web";
        // Los dobles del banco no sirven `/me` y en ellos el id de Teams es el correo:
        // se da como `m365_user_id`, igual que lo configuraría el operador. El banco no se toca.
        const params: Record<string, unknown> = { ...(s.params ?? {}) };
        if (name === "m365-teams" && params.m365_user_id === undefined && op.identities.emails[0]) params.m365_user_id = op.identities.emails[0];
        const r = await a.read({
          operator: op, now: req.now, sensitivity: level, route, params,
          transport: isWeb ? req.env.transport : transport, credentials: req.env.credentials,
        });
        if (r.status === "ok") {
          status[name] = { status: "ok", route: r.route, claims: r.claims.length };
          claims.push(...r.claims);
        } else {
          status[name] = { status: r.status, route: r.route, message: r.message, fallback: r.fallback ?? null };
        }
      }
      const dir = operatorDir(req.stateDir, op.ref);
      mkdirSync(dir, { recursive: true });
      const expires = now + ttl * 1000;
      const final = applyLedgerAndTtl(claims, foldLedger(readLedger(dir), op.ref), now, expires);
      const snap: Snapshot = { schema: SNAPSHOT_SCHEMA, operator_ref: op.ref, issued_at: req.now, expires_at: iso(expires), claims: final, adapters: status };
      writeFileSync(join(dir, "snapshot.json"), JSON.stringify(snap));
      return snap;
    },
  };
}

