/**
 * Mundo sintético del banco: carga world/*.json y lo proyecta a un instante.
 *
 * Campos temporales de cualquier elemento (también anidados):
 *   since: "t1"  → existe desde t1;   gone: "t1" → deja de existir en t1;
 *   t1: {...}     → parche que se aplica desde t1.
 * También construye el índice de propiedad (ref nativo → operador) que el
 * runner usa para detectar fugas entre operadores y hacia terceros.
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
export const INSTANT_ORDER = ["t0", "t1"] as const;
export type Instant = (typeof INSTANT_ORDER)[number];

export type Json = any;

export function readJson(rel: string): Json {
  return JSON.parse(readFileSync(join(ROOT, rel), "utf8"));
}

export function loadTenants(): Json {
  return readJson("world/tenants.json");
}

export function loadInstalls(): Record<string, Json> {
  return readJson("world/installs.json").installs;
}

export function loadWorld(name: string): Json {
  return readJson(`world/${name}.json`);
}

const rank = (i: string) => INSTANT_ORDER.indexOf(i as Instant);

/** Proyección del mundo al instante: filtra since/gone y aplica parches. */
export function worldAt(value: Json, instant: Instant): Json {
  if (Array.isArray(value)) {
    return value.filter((v) => !isObj(v) || exists(v, instant)).map((v) => worldAt(v, instant));
  }
  if (!isObj(value)) return value;
  let out: Json = {};
  for (const [k, v] of Object.entries(value)) {
    if (k === "since" || k === "gone" || INSTANT_ORDER.includes(k as Instant)) continue;
    out[k] = worldAt(v, instant);
  }
  for (const inst of INSTANT_ORDER) {
    if (isObj(value[inst]) && rank(inst) <= rank(instant)) out = { ...out, ...worldAt(value[inst], instant) };
  }
  return out;
}

function exists(v: Json, instant: Instant): boolean {
  if (typeof v.since === "string" && rank(instant) < rank(v.since)) return false;
  if (typeof v.gone === "string" && rank(instant) >= rank(v.gone)) return false;
  return true;
}

function isObj(v: unknown): v is Record<string, Json> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/**
 * Propiedad de cada ref nativo, en cualquier instante. Lo que está bajo
 * `third_party` pertenece a «tercero».
 */
export function ownership(worldNames: string[]): Map<string, string> {
  const own = new Map<string, string>();
  for (const name of worldNames) {
    const w = loadWorld(name);
    const op: string = w.operator;
    const put = (ref: unknown, owner = op) => {
      if (ref !== undefined && ref !== null) own.set(String(ref), owner);
    };
    const m = w.m365 ?? {};
    for (const x of m.messages ?? []) { put(x.conv); put(x.id); }
    for (const x of m.events ?? []) put(x.id);
    for (const c of m.chats ?? []) for (const x of c.messages ?? []) put(x.id);
    for (const x of m.files ?? []) put(x.id);
    const tp = m.third_party ?? {};
    for (const x of tp.delegated_events ?? []) put(x.id, "tercero");
    for (const x of tp.shared_messages ?? []) { put(x.conv, "tercero"); put(x.id, "tercero"); }
    const g = w.google ?? {};
    for (const x of g.messages ?? []) { put(x.thread); put(x.id); }
    for (const x of g.events ?? []) put(x.id);
    for (const x of g.files ?? []) put(x.id);
    for (const x of w.jira?.issues ?? []) put(x.key, x.assignee === w.jira.me ? op : "tercero");
    for (const x of w.ado?.workitems ?? []) put(x.id, x.assignedTo === w.ado.me ? op : "tercero");
    for (const x of w.ado?.prs ?? []) put(`${x.repo}!${x.id}`);
    for (const x of w.github?.items ?? []) put(`${x.repo}#${x.number}`);
    for (const s of w.web?.sites ?? []) {
      for (const x of s.rows ?? []) put(`${s.id}~${x.id}`);
      for (const x of s.pages ?? []) put(`${s.id}~${x.id}`);
    }
  }
  return own;
}

/** Textos sensibles del mundo (asuntos, nombres, direcciones): no pueden salir en `recuentos`. */
export function sensitiveStrings(worldName: string): string[] {
  const out = new Set<string>();
  const walk = (v: Json, key = "") => {
    if (Array.isArray(v)) v.forEach((x) => walk(x, key));
    else if (isObj(v)) for (const [k, x] of Object.entries(v)) walk(x, k);
    else if (typeof v === "string" && ["subject", "from", "to", "cc", "title", "summary", "name", "text", "author", "organizer"].includes(key)) {
      if (v.length >= 6) out.add(v);
    }
  };
  walk(loadWorld(worldName));
  return [...out];
}

/** Marcador de cuerpo que los dobles insertan en cada cuerpo de mensaje. */
export const BODY_CANARY = "CUERPO-CANARIO";
export const TOKEN_CANARY = "TOKEN-CANARIO";
