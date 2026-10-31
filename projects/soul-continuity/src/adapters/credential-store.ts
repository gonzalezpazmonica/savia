/**
 * Almacén de credenciales del sistema para los adaptadores de API (SE-490).
 *
 * Los tokens van al almacén del sistema operativo y a ningún otro sitio:
 * Secret Service (`secret-tool`) en Linux, Llavero (`security`) en macOS y
 * Windows Credential Manager (`PasswordVault` vía PowerShell) en Windows. El
 * secreto siempre viaja por stdin, nunca en la línea de órdenes, en variables
 * de entorno, en ficheros ni en logs. Sin dependencias nativas.
 *
 * Una entrada por operador, servicio y conjunto de permisos (`entryKey`), así
 * que revocar un adaptador borra solo sus tokens. Si el inquilino exige
 * administración, se guarda una marca (sin secreto) y `acquire` falla cerrado.
 */

import { spawn } from "node:child_process";
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
const KEY_RE = /^[a-z0-9/-]+$/;

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
    let t: TokenSet;
    try {
      t = await this.refreshFn(service, s.refresh_token, scopes);
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

interface Run { code: number; stdout: string }

function run(cmd: string, args: string[], stdin: string): Promise<Run> {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawn(cmd, args, { stdio: ["pipe", "pipe", "ignore"], windowsHide: true });
    } catch (e) {
      reject(new Error(`almacén del sistema no disponible: ${(e as Error).name}`));
      return;
    }
    let out = "";
    child.stdout.on("data", (c) => (out += c));
    child.on("error", (e) => reject(new Error(`almacén del sistema no disponible (${(e as NodeJS.ErrnoException).code ?? e.name})`)));
    child.on("close", (code) => resolve({ code: code ?? 1, stdout: out }));
    child.stdin.end(stdin);
  });
}

function checkKey(k: string): string {
  if (!KEY_RE.test(k)) throw new Error("clave del almacén inválida");
  return k;
}

/** Linux: Secret Service por `secret-tool` (libsecret). El secreto entra por stdin. */
export class SecretToolBackend implements SecretBackend {
  private readonly cmd: string;
  constructor(o: { command?: string } = {}) {
    this.cmd = o.command ?? "secret-tool";
  }
  async get(k: string): Promise<string | null> {
    const r = await run(this.cmd, ["lookup", "service", SERVICE, "account", checkKey(k)], "");
    return r.code === 0 && r.stdout ? r.stdout : null;
  }
  async set(k: string, v: string): Promise<void> {
    const r = await run(this.cmd, ["store", `--label=Soul Continuidad`, "service", SERVICE, "account", checkKey(k)], v);
    if (r.code !== 0) throw new Error("secret-tool no guardó la credencial");
  }
  async delete(k: string): Promise<boolean> {
    const had = (await this.get(k)) !== null;
    const r = await run(this.cmd, ["clear", "service", SERVICE, "account", checkKey(k)], "");
    // Se comprueba el borrado releyendo: no se informa de un borrado que no ocurrió.
    if ((had && r.code !== 0) || (await this.get(k)) !== null) throw new Error("secret-tool no borró la credencial");
    return had;
  }
}

/** Órdenes del Llavero de macOS: `security -i` lee las órdenes de stdin; el valor va en base64. */
export const macosCommands = {
  get: (k: string) => ({ cmd: "/usr/bin/security", args: ["find-generic-password", "-s", SERVICE, "-a", checkKey(k), "-w"], stdin: "" }),
  set: (k: string, v: string) => ({
    cmd: "/usr/bin/security", args: ["-i"],
    stdin: `add-generic-password -U -s ${SERVICE} -a ${checkKey(k)} -w ${Buffer.from(v).toString("base64")}\n`,
  }),
  delete: (k: string) => ({ cmd: "/usr/bin/security", args: ["delete-generic-password", "-s", SERVICE, "-a", checkKey(k)], stdin: "" }),
};

const PS_VAULT = "[void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime];$v=New-Object Windows.Security.Credentials.PasswordVault;";

/** Órdenes de Windows Credential Manager (PasswordVault); el script entra por stdin, el valor en base64. */
export const windowsCommands = {
  get: (k: string) => ({
    cmd: "powershell.exe", args: ["-NoProfile", "-NonInteractive", "-Command", "-"],
    stdin: `${PS_VAULT}try{$c=$v.Retrieve('${SERVICE}','${checkKey(k)}');$c.RetrievePassword();[Console]::Out.Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($c.Password)))}catch{exit 1}\n`,
  }),
  set: (k: string, v: string) => ({
    cmd: "powershell.exe", args: ["-NoProfile", "-NonInteractive", "-Command", "-"],
    stdin: `${PS_VAULT}$v.Add((New-Object Windows.Security.Credentials.PasswordCredential('${SERVICE}','${checkKey(k)}','${Buffer.from(v).toString("base64")}')))\n`,
  }),
  delete: (k: string) => ({
    cmd: "powershell.exe", args: ["-NoProfile", "-NonInteractive", "-Command", "-"],
    stdin: `${PS_VAULT}try{$v.Remove($v.Retrieve('${SERVICE}','${checkKey(k)}'))}catch{exit 1}\n`,
  }),
};

/** Almacén por órdenes de sistema (Llavero de macOS, PasswordVault de Windows). */
export class CommandBackend implements SecretBackend {
  private readonly c: typeof macosCommands;
  private readonly decode: boolean;
  constructor(c: typeof macosCommands, decode: boolean) {
    this.c = c;
    this.decode = decode;
  }
  async get(k: string) {
    const x = this.c.get(k);
    const r = await run(x.cmd, x.args, x.stdin);
    if (r.code !== 0 || !r.stdout) return null;
    const v = r.stdout.replace(/\r?\n$/, "");
    return this.decode ? Buffer.from(v, "base64").toString("utf8") : v;
  }
  async set(k: string, v: string) {
    const x = this.c.set(k, v);
    const r = await run(x.cmd, x.args, x.stdin);
    if (r.code !== 0) throw new Error("el almacén del sistema no guardó la credencial");
  }
  async delete(k: string) {
    const x = this.c.delete(k);
    const ok = (await run(x.cmd, x.args, x.stdin)).code === 0;
    // Un código distinto de 0 puede ser «no había nada»; releer distingue ese caso de un fallo.
    if ((await this.get(k)) !== null) throw new Error("el almacén del sistema no borró la credencial");
    return ok;
  }
}

/** Backend del sistema según la plataforma. Sin almacén reconocido, falla cerrado. */
export function systemBackend(platform: NodeJS.Platform = process.platform): SecretBackend {
  if (platform === "linux") return new SecretToolBackend();
  if (platform === "darwin") return new CommandBackend(macosCommands, true);
  if (platform === "win32") return new CommandBackend(windowsCommands, false);
  throw new Error(`Sin almacén de credenciales reconocido para ${platform}: los adaptadores de API no se activan.`);
}
