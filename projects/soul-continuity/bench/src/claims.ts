/**
 * Contrato de afirmaciones de Soul Continuidad v1 (SE-490), portado del modelo
 * de la instantánea OCM F1 (labs/experiments/ocm-f1-snapshot/ocm/model.py).
 *
 * Una afirmación es una referencia con estado, procedencia, vigencia y nivel.
 * Nunca lleva cuerpos de mensajes: solo metadatos y referencias.
 *
 * Validación en runtime sin dependencias: `validateClaim` y `validateSnapshot`
 * devuelven la lista de problemas; una lista vacía es la única forma de PASS.
 */

export const STATES = [
  "DECLARED", "OBSERVED", "DERIVED", "PROPOSED", "CONFIRMED",
  "SUPERSEDED", "REVOKED", "EXPIRED",
] as const;
export type ClaimState = (typeof STATES)[number];

/** Solo estos estados sirven como hecho en una respuesta. */
export const USABLE: ReadonlySet<ClaimState> = new Set(["DECLARED", "OBSERVED", "CONFIRMED"]);

export const LEVELS = ["N1", "N2", "N3", "N4"] as const;
export type Level = (typeof LEVELS)[number];

/** Tipos heredados de OCM F1 (fuentes de desarrollo). */
export const DEV_CLAIM_TYPES = [
  "branch", "pull_request", "run", "spec", "handoff", "delegation", "conflict",
] as const;

/** Tipos de oficina de SE-490. */
export const OFFICE_CLAIM_TYPES = [
  "meeting",            // reunión
  "awaiting_reply",     // hilo esperando mi respuesta
  "mention",            // mención
  "task_assigned",      // tarea asignada
  "review_request",     // revisión pedida (compartido con OCM)
  "document_comments",  // documento con comentarios sin resolver
  "dated_commitment",   // compromiso estructurado con fecha
  "web_page_change",    // cambio de página web sin receta
] as const;

export const CLAIM_TYPES = [...DEV_CLAIM_TYPES, ...OFFICE_CLAIM_TYPES] as const;
export type ClaimType = (typeof CLAIM_TYPES)[number];

export const ROUTES = ["graph", "api", "web", "local"] as const;
export type Route = (typeof ROUTES)[number];

/** Identidad del remitente según la ruta (AC-4c). Nunca se deduce de `From`. */
export const SENDER_AUTH = ["tenant", "dkim_dmarc", "unauthenticated", "unknown"] as const;
export type SenderAuth = (typeof SENDER_AUTH)[number];

export const TITLE_MAX = 120;
/** TTL máximo de una instantánea (igual que OCM F1). */
export const TTL_MAX_S = 24 * 3600;

export interface SourceRef {
  adapter: string;
  route: Route;
  /** Identificador nativo estable en la fuente (id de hilo, de evento, clave de incidencia…). */
  ref: string;
  /** Enlace para abrir en la fuente; nunca se sigue desde Soul. */
  link?: string;
}

export interface Claim {
  /** Clave estable `<adaptador>:<tipo>:<ref>` (ver `claimKey`). */
  key: string;
  claim_type: ClaimType;
  state: ClaimState;
  source_refs: SourceRef[];
  sensitivity: Level;
  observed_at: string;
  valid_until: string;
  /** Instante del hecho en la fuente (último mensaje, actualización…). */
  event_at?: string | null;
  /** Inicio de la reunión o vencimiento de la tarea o compromiso. */
  due_at?: string | null;
  /** Texto de la fuente: dato no fiable, limpio y truncado. */
  title?: string | null;
  untrusted_text?: boolean;
  open: boolean;
  awaiting_operator: boolean;
  /** Atributos de metadatos, sin cuerpos. Valores escalares. */
  attrs: Record<string, string | number | boolean | null>;
  third_party?: boolean;
  /** Arrastrada de una instantánea anterior porque la fuente no respondió. */
  stale?: boolean;
}

export interface Snapshot {
  schema: typeof SNAPSHOT_SCHEMA;
  operator_ref: string;
  issued_at: string;
  expires_at: string;
  claims: Claim[];
  adapters: Record<string, AdapterStatusEntry>;
}

export interface AdapterStatusEntry {
  status: string;
  route?: Route;
  message?: string;
  fallback?: Route | "manual" | null;
  claims?: number;
}

export const SNAPSHOT_SCHEMA = "se490/continuity-snapshot/v1" as const;

// ---------------------------------------------------------------------------
// Utilidades

export function levelRank(level: string): number {
  const i = (LEVELS as readonly string[]).indexOf(level);
  return i >= 0 ? i + 1 : LEVELS.length; // desconocido = el más alto (fail-closed)
}

export function maxLevel(...levels: string[]): Level {
  return LEVELS[Math.max(...levels.map(levelRank)) - 1];
}

/** ISO 8601 → milisegundos. Sin zona se rechaza (null): no se adivina. */
export function parseTs(value: unknown): number | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/.test(value)) {
    return null;
  }
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

export function iso(ms: number): string {
  return new Date(ms).toISOString();
}

const CTRL = /[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g;

/** Texto de una fuente como dato: sin controles ni bidi, normalizado y truncado. */
export function cleanText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.normalize("NFKC").replace(CTRL, " ").replace(/\s+/g, " ").trim();
  return text ? text.slice(0, TITLE_MAX) : null;
}

/** Clave estable. Las partes no pueden contener `:` para que la clave se pueda partir. */
export function claimKey(adapter: string, type: ClaimType, ref: string): string {
  for (const p of [adapter, ref]) {
    if (!p || p.includes(":")) throw new Error(`parte de clave inválida: ${JSON.stringify(p)}`);
  }
  return `${adapter}:${type}:${ref}`;
}

export function parseKey(key: string): { adapter: string; type: string; ref: string } | null {
  const m = /^([^:]+):([a-z_]+):([^:]+)$/.exec(key);
  return m ? { adapter: m[1], type: m[2], ref: m[3] } : null;
}

export function isUsable(c: Pick<Claim, "state">): boolean {
  return USABLE.has(c.state);
}

/** Huella para Q3: lo que, si cambia, cuenta como «cambió». */
export function fingerprint(c: Claim): string {
  const attrs = Object.keys(c.attrs).sort().map((k) => [k, c.attrs[k]]);
  return JSON.stringify([c.state, c.open, c.awaiting_operator, c.event_at ?? null, c.due_at ?? null, attrs]);
}

// ---------------------------------------------------------------------------
// Validación en runtime

const KEY_RE = /^[a-z0-9-]+:[a-z_]+:[^:\s]+$/;

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function oneOf<T extends string>(list: readonly T[], v: unknown): v is T {
  return typeof v === "string" && (list as readonly string[]).includes(v);
}

/** Problemas de una afirmación. Vacío = válida. */
export function validateClaim(v: unknown): string[] {
  const p: string[] = [];
  if (!isObj(v)) return ["la afirmación no es un objeto"];
  const key = v.key;
  if (typeof key !== "string" || !KEY_RE.test(key)) p.push(`clave inválida: ${String(key).slice(0, 60)}`);
  if (!oneOf(CLAIM_TYPES, v.claim_type)) p.push(`tipo desconocido: ${String(v.claim_type)}`);
  if (typeof key === "string" && parseKey(key)?.type !== v.claim_type) p.push("la clave no casa con claim_type");
  if (!oneOf(STATES, v.state)) p.push(`estado desconocido: ${String(v.state)}`);
  if (!oneOf(LEVELS, v.sensitivity)) p.push(`nivel desconocido: ${String(v.sensitivity)}`);
  if (!Array.isArray(v.source_refs) || v.source_refs.length === 0) {
    p.push("una afirmación sin procedencia no es válida");
  } else {
    for (const r of v.source_refs) {
      if (!isObj(r) || typeof r.adapter !== "string" || typeof r.ref !== "string" || !oneOf(ROUTES, r.route)) {
        p.push("source_ref inválida");
      }
    }
  }
  const obs = parseTs(v.observed_at);
  const until = parseTs(v.valid_until);
  if (obs === null) p.push("observed_at inválido");
  if (until === null) p.push("valid_until obligatorio (TTL)");
  if (obs !== null && until !== null && until <= obs && v.state !== "EXPIRED") {
    p.push("valid_until debe ser posterior a observed_at");
  }
  for (const f of ["event_at", "due_at"] as const) {
    if (v[f] != null && parseTs(v[f]) === null) p.push(`${f} inválido`);
  }
  if (typeof v.open !== "boolean") p.push("open debe ser booleano");
  if (typeof v.awaiting_operator !== "boolean") p.push("awaiting_operator debe ser booleano");
  if (v.title != null) {
    if (typeof v.title !== "string" || v.title !== cleanText(v.title)) p.push("title sin limpiar");
    if (v.untrusted_text !== true) p.push("un title de la fuente va marcado untrusted_text");
  }
  if (!isObj(v.attrs)) {
    p.push("attrs debe ser un objeto");
  } else {
    for (const [k, a] of Object.entries(v.attrs)) {
      if (a !== null && !["string", "number", "boolean"].includes(typeof a)) p.push(`attr no escalar: ${k}`);
      if (/^(body|bodyPreview|content|snippet|text)$/i.test(k)) p.push(`attr prohibido (cuerpo): ${k}`);
    }
  }
  return p;
}

export function validateSnapshot(v: unknown): string[] {
  if (!isObj(v)) return ["la instantánea no es un objeto"];
  const p: string[] = [];
  if (v.schema !== SNAPSHOT_SCHEMA) p.push(`schema inesperado: ${String(v.schema)}`);
  if (typeof v.operator_ref !== "string" || !v.operator_ref) p.push("operator_ref obligatorio");
  const issued = parseTs(v.issued_at);
  const exp = parseTs(v.expires_at);
  if (issued === null || exp === null) p.push("issued_at/expires_at inválidos");
  else if (exp <= issued || exp - issued > TTL_MAX_S * 1000) p.push(`TTL obligatorio entre 1 y ${TTL_MAX_S} s`);
  if (!isObj(v.adapters)) p.push("adapters debe ser un objeto");
  if (!Array.isArray(v.claims)) return [...p, "claims debe ser una lista"];
  const seen = new Set<string>();
  v.claims.forEach((c, i) => {
    for (const e of validateClaim(c)) p.push(`claims[${i}]: ${e}`);
    const k = isObj(c) ? String(c.key) : "";
    if (seen.has(k)) p.push(`clave duplicada: ${k}`);
    seen.add(k);
    if (isObj(c) && exp !== null && parseTs(c.valid_until) !== null && (parseTs(c.valid_until) as number) > exp) {
      p.push(`claims[${i}]: valid_until supera la caducidad de la instantánea`);
    }
  });
  return p;
}

// ---------------------------------------------------------------------------
// Libro de correcciones del operador (revocación, sustitución, restauración)

export const LEDGER_ACTIONS = ["revoke", "supersede", "restore"] as const;
export type LedgerAction = (typeof LEDGER_ACTIONS)[number];

export interface LedgerRow {
  operator_ref: string;
  action: LedgerAction;
  key: string;
  at: string;
  reason?: string;
  superseded_by?: string | null;
}

/**
 * Última acción por clave, solo del operador indicado. Filas ajenas o
 * malformadas se ignoran: nunca pueden «des-revocar» nada por error.
 */
export function foldLedger(rows: unknown[], operatorRef: string): Map<string, LedgerRow> {
  const out = new Map<string, LedgerRow>();
  for (const r of rows) {
    if (!isObj(r) || r.operator_ref !== operatorRef || !oneOf(LEDGER_ACTIONS, r.action)) continue;
    if (typeof r.key !== "string" || !KEY_RE.test(r.key)) continue;
    if (r.action === "supersede" && typeof r.superseded_by !== "string") continue;
    out.set(r.key, r as unknown as LedgerRow);
  }
  return out;
}

/**
 * Aplica libro, caducidad propia y TTL de la instantánea. Devuelve copias.
 * Un hecho revocado o sustituido no reaparece aunque la fuente lo repita.
 */
export function applyLedgerAndTtl(claims: Claim[], ledger: Map<string, LedgerRow>, nowMs: number, expiresMs: number): Claim[] {
  return claims.map((orig) => {
    const c: Claim = { ...orig, attrs: { ...orig.attrs } };
    const act = ledger.get(c.key);
    if (act?.action === "revoke") c.state = "REVOKED";
    else if (act?.action === "supersede") {
      c.state = "SUPERSEDED";
      c.attrs.superseded_by = act.superseded_by ?? null;
    }
    const until = parseTs(c.valid_until);
    if (!["REVOKED", "SUPERSEDED", "EXPIRED"].includes(c.state) && until !== null && until <= nowMs) {
      c.state = "EXPIRED";
    }
    c.valid_until = iso(until === null ? expiresMs : Math.min(until, expiresMs));
    return c;
  });
}
