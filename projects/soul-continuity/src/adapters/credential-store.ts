/**
 * Almacén de credenciales del sistema para los adaptadores de API (SE-490).
 *
 * Los tokens van al almacén del sistema operativo y a ningún otro sitio. El
 * backend en producción es la vista `keyed()` del almacén único del núcleo
 * (`src/credentials/store.ts`): Secret Service, Llavero o Credential Manager,
 * con el secreto por stdin y cada entrada anotada en su índice sin secretos,
 * así que desinstalar borra también estos tokens (H-2). Sin dependencias nativas.
 *
 * Una entrada por operador, servicio y conjunto de permisos (`entryKey`), así
 * que revocar un adaptador borra solo sus tokens. Si el inquilino exige
 * administración, se guarda una marca (sin secreto) y `acquire` falla cerrado.
 */

import { createHash } from "node:crypto";
import type { CredentialStore } from "../contract/adapter.ts";
import type { TokenSet } from "./oauth.ts";

export interface SecretBackend {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  delete(key: string): Promise<boolean>;
}

export class CredentialStoreError extends Error {
  readonly code: "admin_consent_required" | "no_credential";
  constructor(code: CredentialStoreError["code"], message: string) {
    super(message);
    this.code = code;
  }
}

const h16 = (s: string) => createHash("sha256").update(s).digest("hex").slice(0, 16);
const SERVICE = "soul-continuity";

export function entryKey(operatorRef: string, service: string, scopes: string[]): string {
  if (!/^[a-z0-9-]+$/.test(service)) throw new Error("servicio inválido");
  return `${SERVICE}/${h16(operatorRef)}/${service}/${h16([...scopes].sort().join(" "))}`;
}

interface Stored extends Partial<TokenSet> {
  admin_consent_required?: boolean;
}

export type RefreshFn = (service: string, refreshToken: string, scopes: string[]) => Promise<TokenSet>;

export class SystemCredentialStore implements CredentialStore {
  private readonly backend: SecretBackend;
  private readonly operatorRef: string;
  private readonly refreshFn?: RefreshFn;
  /** Renovaciones en curso por entrada: dos lecturas a la vez no rotan el refresh token dos veces. */
  private readonly inflight = new Map<string, Promise<string>>();
  private readonly now: () => number;

  constructor(o: { backend: SecretBackend; operatorRef: string; refresh?: RefreshFn; now?: () => number }) {
    this.backend = o.backend;
    this.operatorRef = o.operatorRef;
    this.refreshFn = o.refresh;
    this.now = o.now ?? Date.now;
  }

  async acquire(service: string, scopes: string[]): Promise<string> {
    const key = entryKey(this.operatorRef, service, scopes);
    const raw = await this.backend.get(key);
    let s: Stored | null = null;
    try {
      s = raw ? (JSON.parse(raw) as Stored) : null;
    } catch {
      s = null;
    }
    if (!s) throw new CredentialStoreError("no_credential", "No hay credencial para esta fuente: inicia sesión.");
    if (s.admin_consent_required) throw new CredentialStoreError("admin_consent_required", "El inquilino exige consentimiento de administración.");
    if (typeof s.access_token === "string" && typeof s.expires_at === "number" && s.expires_at - 60_000 > this.now()) return s.access_token;
    if (!s.refresh_token || !this.refreshFn) throw new CredentialStoreError("no_credential", "La credencial caducó: vuelve a iniciar sesión.");
    const running = this.inflight.get(key);
    if (running) return running;
    const p = this.renew(service, scopes, s.refresh_token, this.refreshFn);
    this.inflight.set(key, p);
    try {
      return await p;
    } finally {
      this.inflight.delete(key);
    }
  }

  private async renew(service: string, scopes: string[], refreshToken: string, refreshFn: RefreshFn): Promise<string> {
    let t: TokenSet;
    try {
      t = await refreshFn(service, refreshToken, scopes);
    } catch (e) {
      const code = (e as { code?: unknown })?.code;
      if (code === "admin_consent_required") {
        await this.markAdminRequired(service, scopes);
        throw new CredentialStoreError("admin_consent_required", "El inquilino exige consentimiento de administración.");
      }
      throw new CredentialStoreError("no_credential", "No se pudo renovar la credencial: vuelve a iniciar sesión.");
    }
    await this.put(service, scopes, t);
    return t.access_token;
  }

  /** Guarda el resultado de un inicio de sesión. */
  async put(service: string, scopes: string[], t: TokenSet): Promise<void> {
    const v: Stored = { access_token: t.access_token, refresh_token: t.refresh_token, expires_at: t.expires_at, scopes: [...scopes] };
    await this.backend.set(entryKey(this.operatorRef, service, scopes), JSON.stringify(v));
  }

  async markAdminRequired(service: string, scopes: string[]): Promise<void> {
    await this.backend.set(entryKey(this.operatorRef, service, scopes), JSON.stringify({ admin_consent_required: true }));
  }

  /** Borra los tokens de ese servicio y permisos. true si había algo. */
  async revoke(service: string, scopes: string[]): Promise<boolean> {
    return this.backend.delete(entryKey(this.operatorRef, service, scopes));
  }
}

// ---------------------------------------------------------------------------
// Backends

export class MemoryBackend implements SecretBackend {
  private readonly m = new Map<string, string>();
  async get(k: string) { return this.m.get(k) ?? null; }
  async set(k: string, v: string) { this.m.set(k, v); }
  async delete(k: string) { return this.m.delete(k); }
}
