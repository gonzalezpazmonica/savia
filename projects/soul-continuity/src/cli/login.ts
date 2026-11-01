/**
 * Alta de la instalación (`soul init`) e inicio de sesión de los adaptadores (`soul login`).
 *
 * - `init`: perfil del operador con una referencia opaca, sin fuentes, sin adaptadores activos y
 *   sin direcciones de escucha. No pisa una instalación existente.
 * - `login <adaptador>`: Microsoft 365 y Google por flujo de dispositivo (RFC 8628) con la
 *   aplicación propia del operador o de su organización (`connectors.oauth`); GitHub, Jira y
 *   Azure DevOps con un token de solo lectura pegado por stdin (`--token-stdin`). El token va
 *   solo al almacén del sistema; nunca a disco, a argv ni a la salida.
 */

import { randomBytes } from "node:crypto";
import { type ApiAdapterName, DESCRIPTORS, isApiAdapter } from "../adapters/descriptors.ts";
import { type ClientConfig, type OAuthProvider, type TokenSet, deviceFlow, googleProvider, microsoftProvider, refreshToken } from "../adapters/oauth.ts";
import type { RefreshFn } from "../adapters/credential-store.ts";
import type { ConnectorsConfig } from "../core/connectors.ts";
import { type SoulConfig, emptyConfig } from "../core/config.ts";

export const PROFILE_NAME = /^[a-z0-9][a-z0-9_-]{0,31}$/;

export function initConfig(name: string, emails: string[], installationId: string): SoulConfig {
  if (!PROFILE_NAME.test(name)) throw new Error("nombre de perfil: minúsculas, cifras, - y _ (hasta 32)");
  for (const e of emails) if (!/^[^\s@]{1,64}@[^\s@]{1,190}$/.test(e)) throw new Error("correo no válido");
  const c = emptyConfig(installationId);
  c.active_profile = name;
  c.profiles[name] = { operator: { ref: `op-${randomBytes(8).toString("hex")}`, identities: { emails } }, sources: [] };
  c.connectors = { enabled: [] };
  return c;
}

export type LoginPlan =
  | { kind: "oauth"; provider: "microsoft" | "google"; service: string; scopes: string[] }
  | { kind: "token"; service: string; scopes: string[] }
  | { kind: "none" };

/** Cómo se inicia sesión en cada adaptador. Se guarda la variante de permisos habitual (la primera). */
export function loginPlan(adapter: string): LoginPlan {
  if (!isApiAdapter(adapter)) return { kind: "none" };
  const d = DESCRIPTORS[adapter as ApiAdapterName];
  const scopes = d.scopes[0];
  if (d.service === "graph") return { kind: "oauth", provider: "microsoft", service: d.service, scopes };
  if (d.service === "google") return { kind: "oauth", provider: "google", service: d.service, scopes };
  return { kind: "token", service: d.service, scopes };
}

export interface OAuthClients {
  microsoft?: { client_id: string; tenant: string; owner: ClientConfig["owner"] };
  google?: { client_id: string; client_secret?: string; owner: ClientConfig["owner"] };
}

function client(c: ConnectorsConfig | undefined, p: "microsoft" | "google"): { provider: OAuthProvider; client: ClientConfig } | null {
  const o = (c as { oauth?: OAuthClients } | undefined)?.oauth;
  if (p === "microsoft" && o?.microsoft?.client_id && o.microsoft.tenant) {
    return { provider: microsoftProvider(o.microsoft.tenant), client: { client_id: o.microsoft.client_id, owner: o.microsoft.owner } };
  }
  if (p === "google" && o?.google?.client_id) {
    return { provider: googleProvider, client: { client_id: o.google.client_id, owner: o.google.owner, client_secret: o.google.client_secret } };
  }
  return null;
}

/** Renovación de tokens OAuth con la aplicación configurada. Sin ella, falla cerrado (hay que volver a iniciar sesión). */
export function oauthRefresher(c: ConnectorsConfig | undefined, f?: typeof fetch): RefreshFn {
  return async (service, rt, scopes) => {
    const p = service === "graph" ? "microsoft" : service === "google" ? "google" : null;
    const cl = p ? client(c, p) : null;
    if (!cl) throw new Error("sin aplicación OAuth configurada para renovar");
    return refreshToken({ provider: cl.provider, client: cl.client, refresh_token: rt, scopes, fetch: f });
  };
}

export interface LoginDeps {
  connectors: ConnectorsConfig | undefined;
  store: { put(service: string, scopes: string[], t: TokenSet): Promise<void> };
  readSecret: () => Promise<string>;
  say: (s: string) => void;
  now: () => number;
  fetch?: typeof fetch;
}

export class LoginUsage extends Error {}

export async function runLogin(adapter: string, o: { tokenStdin: boolean; days?: number }, d: LoginDeps): Promise<string> {
  const plan = loginPlan(adapter);
  if (plan.kind === "none") {
    throw new LoginUsage(adapter === "web"
      ? "web no usa tokens: inicia sesión a mano en el perfil de Soul (ver docs/instalar.md)"
      : `adaptador desconocido: ${adapter.slice(0, 40)}`);
  }
  if (o.tokenStdin || plan.kind === "token") {
    if (!o.tokenStdin) throw new LoginUsage(`${adapter}: pega un token de solo lectura por stdin con --token-stdin`);
    const days = o.days ?? 90;
    if (!Number.isInteger(days) || days < 1 || days > 397) throw new LoginUsage("--days entre 1 y 397");
    const tok = (await d.readSecret()).trim();
    if (!tok || /\s/.test(tok) || tok.length > 4096) throw new LoginUsage("token vacío o con espacios");
    await d.store.put(plan.service, plan.scopes, { access_token: tok, expires_at: d.now() + days * 86_400_000, scopes: plan.scopes });
    return `Token de ${adapter} guardado en el almacén del sistema (caduca para Soul en ${days} días).`;
  }
  const cl = client(d.connectors, plan.provider);
  if (!cl) throw new Error(`falta la aplicación propia en connectors.oauth.${plan.provider} (client_id${plan.provider === "microsoft" ? " y tenant" : ""})`);
  const t = await deviceFlow({
    provider: cl.provider, client: cl.client, scopes: plan.scopes, fetch: d.fetch, now: d.now,
    onPrompt: (p) => d.say(`Abre ${p.verification_uri} e introduce el código ${p.user_code} (caduca en ${Math.round(p.expires_in / 60)} min).`),
  });
  await d.store.put(plan.service, plan.scopes, t);
  return `Sesión de ${adapter} iniciada; el token está en el almacén del sistema.`;
}
