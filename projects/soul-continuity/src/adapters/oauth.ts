/**
 * Autenticación delegada del propio usuario para los adaptadores de API (SE-490).
 *
 * - Flujo de dispositivo (RFC 8628) y flujo de navegador con PKCE (RFC 7636) y
 *   redirección a `127.0.0.1` en un puerto aleatorio (RFC 8252). Google no admite
 *   Gmail en el flujo de dispositivo: para Google, navegador.
 * - Solo identificadores de aplicación **propios** del operador o de su
 *   organización, declarados en la configuración (`owner`). Los de aplicaciones
 *   de Microsoft o Google conocidas se rechazan antes de ninguna petición: nunca
 *   se usan para sortear el consentimiento.
 * - Si el inquilino exige consentimiento de administración, el error se traduce a
 *   `admin_consent_required` (fail-closed): el adaptador ofrece la ruta web.
 * - Endpoints HTTPS (salvo loopback, para los tests). Los tokens solo se devuelven
 *   al llamante, que los guarda en el almacén del sistema; nunca se escriben ni se
 *   registran aquí.
 */

import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";

export interface OAuthProvider {
  id: "microsoft" | "google";
  deviceEndpoint?: string;
  authorizeEndpoint: string;
  tokenEndpoint: string;
  /** Permiso que pide el refresh token (Microsoft: `offline_access`). */
  offlineScope: string | null;
  /** Parámetros extra de la autorización por navegador. */
  authorizeExtra: Record<string, string>;
  /** Identificadores de aplicaciones ajenas conocidas (en minúsculas). */
  foreignClients: ReadonlySet<string>;
}

export interface ClientConfig {
  client_id: string;
  /** Quién registró la aplicación: el propio operador o su organización. */
  owner: "operator" | "organization";
  /** Aplicaciones instaladas de Google: su «secreto» no es secreto, pero lo exige el canje. */
  client_secret?: string;
}

export interface TokenSet {
  access_token: string;
  refresh_token?: string;
  /** Milisegundos epoch. */
  expires_at: number;
  scopes: string[];
}

export class ForeignClientError extends Error {}

export class OAuthError extends Error {
  readonly code: "admin_consent_required" | "no_credential";
  constructor(code: OAuthError["code"], message: string) {
    super(message);
    this.code = code;
  }
}

/** Aplicaciones de primera parte de Microsoft que nunca se usan como cliente de Soul. */
const MICROSOFT_FIRST_PARTY = [
  "04b07795-8ddb-461a-bbee-02f9e1bf7b46", // Azure CLI
  "1950a258-227b-4e31-a9cf-717495945fc2", // Azure PowerShell
  "14d82eec-204b-4c2f-b7e8-296a70dab67e", // Microsoft Graph Command Line Tools
  "de8bc8b5-d9f9-48b1-a8ad-b748da725064", // Graph Explorer
  "d3590ed6-52b3-4102-aeff-aad2292ab01c", // Microsoft Office
  "1fec8e78-bce4-4aaf-ab1b-5451cc387264", // Microsoft Teams
  "5e3ce6c0-2b1f-4285-8d4b-75ee78787346", // Teams web
  "27922004-5251-4030-b22d-91ecd9a37ea4", // Outlook móvil
  "00000002-0000-0ff1-ce00-000000000000", // Exchange Online
  "872cd9fa-d31f-45e0-9eab-6e460a02d1f1", // Visual Studio
  "9bc3ab49-b65d-410a-85ad-de819febfddc", // SharePoint Online Management Shell
  "ab9b8c07-8f02-4f72-87fa-80105867a763", // OneDrive SyncEngine
  "4813382a-8fa7-425e-ab75-3b753aab3abb", // Microsoft Authenticator
  "29d9ed98-a469-4536-ade2-f981bc1d605e", // Microsoft Authentication Broker
  "1b730954-1685-4b74-9bfd-dac224a7b894", // Azure AD PowerShell
  "0ec893e0-5785-4de6-99da-4ed124e5296c", // Office UWP PWA
];
const GOOGLE_FOREIGN = [
  "32555940559.apps.googleusercontent.com", // Google Cloud SDK
  "764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com", // credenciales por defecto de gcloud
];

export function microsoftProvider(tenant: string): OAuthProvider {
  if (!/^[A-Za-z0-9.-]+$/.test(tenant)) throw new Error("inquilino inválido");
  const b = `https://login.microsoftonline.com/${tenant}/oauth2/v2.0`;
  return {
    id: "microsoft", deviceEndpoint: `${b}/devicecode`, authorizeEndpoint: `${b}/authorize`, tokenEndpoint: `${b}/token`,
    offlineScope: "offline_access", authorizeExtra: {}, foreignClients: new Set(MICROSOFT_FIRST_PARTY),
  };
}

export const googleProvider: OAuthProvider = {
  id: "google",
  deviceEndpoint: "https://oauth2.googleapis.com/device/code",
  authorizeEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
  tokenEndpoint: "https://oauth2.googleapis.com/token",
  offlineScope: null,
  authorizeExtra: { access_type: "offline", prompt: "consent" },
  foreignClients: new Set(GOOGLE_FOREIGN),
};

export function assertOwnClient(p: OAuthProvider, c: ClientConfig): void {
  const id = String(c?.client_id ?? "").trim().toLowerCase();
  if (!id) throw new ForeignClientError("Falta el identificador de aplicación propio (client_id) en la configuración.");
  if (c.owner !== "operator" && c.owner !== "organization") {
    throw new ForeignClientError("Declara quién registró la aplicación (owner: operator u organization).");
  }
  if (p.foreignClients.has(id)) {
    throw new ForeignClientError("Ese identificador es de una aplicación ajena; Soul no lo usa para sortear el consentimiento. Registra una aplicación propia o usa la ruta web.");
  }
}

function assertHttps(url: string): void {
  const u = new URL(url);
  const loopback = u.hostname === "127.0.0.1" || u.hostname === "::1" || u.hostname === "localhost";
  if (u.protocol !== "https:" && !(loopback && u.protocol === "http:")) throw new Error(`El endpoint de identidad debe ser HTTPS: ${u.origin}`);
}

const ADMIN = /AADSTS(65001|65004|90094|90095|900941|90099)\b/;

export function classifyOAuthError(b: unknown): "admin_consent_required" | "pending" | "slow_down" | "no_credential" {
  const e = (typeof b === "object" && b !== null ? b : {}) as { error?: unknown; error_description?: unknown; error_codes?: unknown };
  const err = String(e.error ?? "");
  const desc = String(e.error_description ?? "");
  const codes = Array.isArray(e.error_codes) ? e.error_codes.map(Number) : [];
  if (err === "authorization_pending") return "pending";
  if (err === "slow_down") return "slow_down";
  if (err === "consent_required" || err === "admin_policy_enforced" || ADMIN.test(desc) || codes.some((c) => [65001, 65004, 90094, 90095, 900941, 90099].includes(c))) {
    return "admin_consent_required";
  }
  return "no_credential";
}

function scopeList(p: OAuthProvider, scopes: string[]): string {
  return [...scopes, ...(p.offlineScope ? [p.offlineScope] : [])].join(" ");
}

async function post(url: string, form: Record<string, string>, fetchFn: typeof fetch): Promise<{ status: number; body: unknown }> {
  assertHttps(url);
  let res: Response;
  try {
    res = await fetchFn(url, {
      method: "POST", redirect: "error", headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
      body: new URLSearchParams(form).toString(), signal: AbortSignal.timeout(30_000),
    });
  } catch (e) {
    throw new OAuthError("no_credential", `No se pudo contactar con el proveedor de identidad (${(e as Error).name}).`);
  }
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { status: res.status, body };
}

function tokenSet(b: unknown, scopes: string[], now: number, keepRefresh?: string): TokenSet {
  const t = (b ?? {}) as { access_token?: unknown; refresh_token?: unknown; expires_in?: unknown };
  if (typeof t.access_token !== "string" || !t.access_token) throw new OAuthError("no_credential", "El proveedor no devolvió un token.");
  const exp = Number(t.expires_in);
  return {
    access_token: t.access_token,
    refresh_token: typeof t.refresh_token === "string" && t.refresh_token ? t.refresh_token : keepRefresh,
    expires_at: now + (Number.isFinite(exp) && exp > 0 ? exp : 3600) * 1000,
    scopes: [...scopes],
  };
}

function fail(b: unknown): never {
  const k = classifyOAuthError(b);
  if (k === "admin_consent_required") {
    throw new OAuthError("admin_consent_required", "El inquilino exige consentimiento de administración para estos permisos. La ruta por API no se activa; puedes usar la ruta web.");
  }
  throw new OAuthError("no_credential", "No se obtuvo credencial: vuelve a iniciar sesión.");
}

function clientForm(c: ClientConfig): Record<string, string> {
  return c.client_secret ? { client_id: c.client_id, client_secret: c.client_secret } : { client_id: c.client_id };
}

export interface DevicePrompt {
  user_code: string;
  verification_uri: string;
  expires_in: number;
}

export async function deviceFlow(o: {
  provider: OAuthProvider; client: ClientConfig; scopes: string[];
  onPrompt: (p: DevicePrompt) => void; sleep?: (ms: number) => Promise<void>; now?: () => number; fetch?: typeof fetch;
}): Promise<TokenSet> {
  assertOwnClient(o.provider, o.client);
  if (!o.provider.deviceEndpoint) throw new OAuthError("no_credential", "Este proveedor no admite el flujo de dispositivo; usa el navegador.");
  const f = o.fetch ?? fetch;
  const sleep = o.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));
  const now = o.now ?? Date.now;
  const d = await post(o.provider.deviceEndpoint, { ...clientForm(o.client), scope: scopeList(o.provider, o.scopes) }, f);
  const dc = (d.body ?? {}) as { device_code?: string; user_code?: string; verification_uri?: string; verification_url?: string; interval?: number; expires_in?: number };
  if (d.status !== 200 || !dc.device_code || !dc.user_code) fail(d.body);
  const expiresIn = Number(dc.expires_in) > 0 ? Number(dc.expires_in) : 900;
  o.onPrompt({ user_code: dc.user_code, verification_uri: String(dc.verification_uri ?? dc.verification_url ?? ""), expires_in: expiresIn });
  let interval = (Number(dc.interval) > 0 ? Number(dc.interval) : 5) * 1000;
  const deadline = now() + expiresIn * 1000;
  while (now() <= deadline) {
    await sleep(interval);
    const r = await post(o.provider.tokenEndpoint, {
      ...clientForm(o.client), grant_type: "urn:ietf:params:oauth:grant-type:device_code", device_code: dc.device_code,
    }, f);
    if (r.status === 200) return tokenSet(r.body, o.scopes, now());
    const k = classifyOAuthError(r.body);
    if (k === "pending") continue;
    if (k === "slow_down") {
      interval += 5000;
      continue;
    }
    fail(r.body);
  }
  throw new OAuthError("no_credential", "El código de dispositivo caducó: vuelve a iniciar sesión.");
}

export async function browserFlow(o: {
  provider: OAuthProvider; client: ClientConfig; scopes: string[];
  /** Abre (o muestra) la URL de autorización en el navegador del operador. */
  openUrl: (url: string) => Promise<void> | void;
  timeoutMs?: number; now?: () => number; fetch?: typeof fetch;
}): Promise<TokenSet> {
  assertOwnClient(o.provider, o.client);
  assertHttps(o.provider.authorizeEndpoint);
  const verifier = randomBytes(48).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  const state = randomBytes(24).toString("base64url");
  let settle: (v: { code?: string; error?: unknown }) => void = () => {};
  const result = new Promise<{ code?: string; error?: unknown }>((r) => (settle = r));
  const srv = createServer((req, res) => {
    const u = new URL(req.url ?? "/", "http://127.0.0.1");
    if (u.pathname !== "/callback" || u.searchParams.get("state") !== state) {
      res.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
      res.end("Petición no reconocida.");
      return;
    }
    res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
    res.end("Listo. Puedes cerrar esta pestaña y volver a Soul.");
    if (u.searchParams.get("error")) settle({ error: { error: u.searchParams.get("error"), error_description: u.searchParams.get("error_description") } });
    else settle({ code: u.searchParams.get("code") ?? undefined });
  });
  await new Promise<void>((r) => srv.listen(0, "127.0.0.1", r));
  const redirect = `http://127.0.0.1:${(srv.address() as AddressInfo).port}/callback`;
  const timer = setTimeout(() => settle({ error: { error: "timeout" } }), o.timeoutMs ?? 300_000);
  try {
    const q = new URLSearchParams({
      client_id: o.client.client_id, response_type: "code", redirect_uri: redirect, scope: scopeList(o.provider, o.scopes),
      state, code_challenge: challenge, code_challenge_method: "S256", ...o.provider.authorizeExtra,
    });
    await o.openUrl(`${o.provider.authorizeEndpoint}?${q}`);
    const r = await result;
    if (!r.code) fail(r.error);
    const t = await post(o.provider.tokenEndpoint, {
      ...clientForm(o.client), grant_type: "authorization_code", code: r.code, redirect_uri: redirect, code_verifier: verifier,
    }, o.fetch ?? fetch);
    if (t.status !== 200) fail(t.body);
    return tokenSet(t.body, o.scopes, (o.now ?? Date.now)());
  } finally {
    clearTimeout(timer);
    srv.close();
  }
}

export async function refreshToken(o: {
  provider: OAuthProvider; client: ClientConfig; refresh_token: string; scopes: string[]; now?: () => number; fetch?: typeof fetch;
}): Promise<TokenSet> {
  assertOwnClient(o.provider, o.client);
  const r = await post(o.provider.tokenEndpoint, {
    ...clientForm(o.client), grant_type: "refresh_token", refresh_token: o.refresh_token, scope: scopeList(o.provider, o.scopes),
  }, o.fetch ?? fetch);
  if (r.status !== 200) fail(r.body);
  return tokenSet(r.body, o.scopes, (o.now ?? Date.now)(), o.refresh_token);
}
