/**
 * Contrato de adaptadores y de la implementación bajo prueba (SE-490, AC-2/AC-3).
 *
 * - `SourceAdapter`: un adaptador de fuente de solo lectura. Habla con la fuente
 *   solo a través de `Transport` y obtiene credenciales solo de `CredentialStore`
 *   (el almacén del sistema en producción; un doble en el banco).
 * - `ContinuityImpl`: lo que el runner ejerce. Cualquier núcleo que lo cumpla se
 *   puede medir con el banco, sin conocer sus adaptadores por dentro.
 *
 * La semántica de Q1–Q4 y de ALERT está en CONTRATO.md; aquí solo los tipos y
 * la validación en runtime de lo que cruza la frontera.
 */

import {
  CLAIM_TYPES, LEVELS, ROUTES, type Claim, type ClaimType, type Level, type Route,
  type Snapshot, validateClaim,
} from "./claims.ts";

export const ADAPTERS = [
  "m365-mail", "m365-calendar", "m365-teams", "m365-files",
  "google-workspace", "jira", "azure-devops", "github", "web",
] as const;
export type AdapterName = (typeof ADAPTERS)[number];

/** Nivel por defecto de cada adaptador. La configuración puede subirlo, nunca bajarlo. */
export const DEFAULT_SENSITIVITY: Record<AdapterName, Level> = {
  "m365-mail": "N4", "m365-calendar": "N4", "m365-teams": "N4", "m365-files": "N4",
  "google-workspace": "N4", jira: "N4", "azure-devops": "N4", github: "N2", web: "N4",
};

/** Estados de un adaptador tras una lectura. Solo `ok` aporta afirmaciones. */
export const ADAPTER_STATUS = [
  "ok",
  "not_configured",          // no está en la configuración
  "no_purpose",              // sin propósito declarado
  "no_consent",              // sin consentimiento vigente del operador
  "consent_revoked",         // el operador lo revocó
  "admin_consent_required",  // el inquilino exige consentimiento de administración (fail-closed)
  "token_expired",           // credencial caducada: volver a iniciar sesión
  "session_expired",         // ruta web: sesión del perfil dedicado caducada
  "recipe_disabled",         // ruta web: la prueba de humo de la receta falló
  "unavailable",             // fuente no alcanzable o limitada (429 persistente)
  "unknown_adapter",
  "duplicate_adapter",
  "error",
] as const;
export type AdapterStatus = (typeof ADAPTER_STATUS)[number];

// ---------------------------------------------------------------------------
// Instalación y operador

export interface OperatorProfile {
  /** Referencia opaca y estable del operador (no un nombre). */
  ref: string;
  /** Identidades del operador en cada fuente: correos, logins, ids de cuenta. */
  identities: {
    emails: string[];
    github?: string;
    jira_account?: string;
    ado_id?: string;
  };
}

export interface Consent {
  granted_at: string | null;
  revoked_at?: string | null;
  /** «Activo esta fuente bajo mi responsabilidad». */
  statement?: string;
}

export interface SourceConfig {
  adapter: string;
  /** Ruta pedida. Para Microsoft 365: graph y, si no se puede, web. */
  route?: Route;
  purpose: string;
  consent: Consent;
  sensitivity?: Level;
  params?: Record<string, unknown>;
}

export interface AlertRule {
  id: string;
  /** Dirección del remitente; se casa con identidad autenticada, nunca solo con `From`. */
  sender: string;
}

export interface InstallationConfig {
  id: string;
  operator: OperatorProfile;
  sources: SourceConfig[];
  alert_rules?: AlertRule[];
}

// ---------------------------------------------------------------------------
// Frontera con las fuentes

export interface TransportRequest {
  /** Destino lógico: graph, google, jira, ado, github, web, owa. */
  service: string;
  method: string;
  url: string;
  headers?: Record<string, string>;
  body?: unknown;
}

export interface TransportResponse {
  status: number;
  headers: Record<string, string>;
  body: unknown;
}

export interface Transport {
  request(req: TransportRequest): Promise<TransportResponse>;
}

export class CredentialError extends Error {
  readonly code: "admin_consent_required" | "no_credential" | "session_expired";
  constructor(code: CredentialError["code"], message: string) {
    super(message);
    this.code = code;
  }
}

/** Almacén de credenciales del sistema. El token nunca se escribe fuera de él. */
export interface CredentialStore {
  /** Token delegado para `service` con esos permisos, o `CredentialError`. */
  acquire(service: string, scopes: string[]): Promise<string>;
}

export interface AdapterContext {
  operator: OperatorProfile;
  now: string;
  sensitivity: Level;
  route: Route;
  params: Record<string, unknown>;
  transport: Transport;
  credentials: CredentialStore;
}

export type AdapterResult =
  | { status: "ok"; route: Route; claims: Claim[] }
  | { status: Exclude<AdapterStatus, "ok">; route: Route; message: string; fallback?: Route | "manual" | null };

export interface SourceAdapter {
  name: AdapterName;
  routes: Route[];
  purpose: string;
  read(ctx: AdapterContext): Promise<AdapterResult>;
}

export function validateAdapterResult(v: unknown, adapter: string): string[] {
  if (typeof v !== "object" || v === null) return ["el resultado no es un objeto"];
  const r = v as Record<string, unknown>;
  const p: string[] = [];
  if (!(ADAPTER_STATUS as readonly string[]).includes(String(r.status))) p.push(`estado desconocido: ${String(r.status)}`);
  if (!(ROUTES as readonly string[]).includes(String(r.route))) p.push(`ruta desconocida: ${String(r.route)}`);
  if (r.status === "ok") {
    if (!Array.isArray(r.claims)) return [...p, "ok sin lista de claims"];
    r.claims.forEach((c, i) => {
      for (const e of validateClaim(c)) p.push(`claims[${i}]: ${e}`);
      const key = (c as Claim)?.key;
      if (typeof key === "string" && !key.startsWith(`${adapter}:`)) p.push(`claims[${i}]: clave de otro adaptador`);
    });
  } else if (typeof r.message !== "string" || !r.message) {
    p.push("un fallo lleva mensaje para el operador");
  } else if ("claims" in r) {
    p.push("un fallo no aporta claims (fail-closed)");
  }
  return p;
}

// ---------------------------------------------------------------------------
// Preguntas y respuestas

export const QUESTIONS = ["Q1", "Q2", "Q3", "Q4", "ALERT"] as const;
export type QuestionId = (typeof QUESTIONS)[number];

export const DETAILS = ["completo", "titulos", "recuentos"] as const;
export type Detail = (typeof DETAILS)[number];

export interface Question {
  q: QuestionId;
  /** Q3: instantánea anterior del mismo operador (instante «desde»). */
  previous?: Snapshot;
  filter?: { types?: ClaimType[]; adapters?: string[]; ref_prefix?: string };
  /** Nivel máximo de sensibilidad de la vista (por defecto N4, local). */
  max_level?: Level;
  /** Nivel de detalle (por defecto `titulos`). */
  detail?: Detail;
}

export interface AnswerItem {
  key: string;
  claim_type: ClaimType;
  source_refs: { adapter: string; route: Route; ref: string }[];
  /** Antigüedad en segundos respecto a `now` (de event_at, o de observed_at). */
  age_s: number;
  title?: string | null;
  untrusted_text?: boolean;
  /** Q3: added | removed | changed. */
  change?: "added" | "removed" | "changed";
  /** Solo en `completo`. */
  attrs?: Record<string, string | number | boolean | null>;
}

export interface Answer {
  q: QuestionId;
  detail: Detail;
  /** Vacío en `recuentos`. */
  items: AnswerItem[];
  counts: Partial<Record<ClaimType, number>>;
  /** Elementos retenidos por superar `max_level` (solo se cuentan). */
  withheld: number;
  /** Estado por adaptador, para decir qué falta y por qué. */
  adapters: Record<string, { status: string; message?: string; fallback?: string | null }>;
  /** Solo ALERT. */
  alerts?: string[];
  notices?: string[];
}

export function validateAnswer(v: unknown): string[] {
  if (typeof v !== "object" || v === null) return ["la respuesta no es un objeto"];
  const a = v as Record<string, unknown>;
  const p: string[] = [];
  if (!(QUESTIONS as readonly string[]).includes(String(a.q))) p.push("q desconocida");
  if (!(DETAILS as readonly string[]).includes(String(a.detail))) p.push("detail desconocido");
  if (!Array.isArray(a.items)) p.push("items debe ser una lista");
  else {
    if (a.detail === "recuentos" && a.items.length) p.push("recuentos no lleva elementos");
    for (const it of a.items as AnswerItem[]) {
      if (typeof it?.key !== "string") p.push("item sin clave");
      if (!(CLAIM_TYPES as readonly string[]).includes(String(it?.claim_type))) p.push("item con tipo desconocido");
      if (a.detail !== "completo" && it && "attrs" in it) p.push("attrs solo en completo");
    }
  }
  if (typeof a.counts !== "object" || a.counts === null) p.push("counts obligatorio");
  if (typeof a.withheld !== "number") p.push("withheld obligatorio");
  if (typeof a.adapters !== "object" || a.adapters === null) p.push("adapters obligatorio");
  return p;
}

// ---------------------------------------------------------------------------
// Implementación bajo prueba

/** Entorno de fuentes que el runner entrega: los dobles detrás de transporte y credenciales. */
export interface SourceEnv {
  transport: Transport;
  credentials: CredentialStore;
}

export interface SnapshotRequest {
  install: InstallationConfig;
  now: string;
  /** Directorio de estado de la instalación. Compartido entre operadores de una instalación. */
  stateDir: string;
  env: SourceEnv;
  ttl_s?: number;
}

export interface CorrectionRequest {
  install: InstallationConfig;
  stateDir: string;
  now: string;
  key: string;
  action: "revoke" | "supersede" | "restore";
  superseded_by?: string;
  reason?: string;
}

export interface ContinuityImpl {
  name: string;
  snapshot(req: SnapshotRequest): Promise<Snapshot>;
  correct(req: CorrectionRequest): Promise<void>;
  answer(snap: Snapshot, q: Question, ctx: { install: InstallationConfig; now: string }): Answer;
}

export function isLevel(v: unknown): v is Level {
  return typeof v === "string" && (LEVELS as readonly string[]).includes(v);
}
