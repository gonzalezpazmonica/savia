/**
 * Almacén de credenciales del sistema para los adaptadores de API (SE-490).
 *
 * Los tokens van al almacén del sistema operativo y a ningún otro sitio:
 * Secret Service (`secret-tool`) en Linux, Llavero (`security`) en macOS y
 * Windows Credential Manager (advapi32 vía PowerShell) en Windows. El
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
import { SOUL_CRED_CS } from "../credentials/store.ts";
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
  private readonly pre: string[];
  /** `commandArgs` va delante de los argumentos de secret-tool (p. ej. un intérprete y su script). */
  constructor(o: { command?: string; commandArgs?: string[] } = {}) {
    this.cmd = o.command ?? "secret-tool";
    this.pre = o.commandArgs ?? [];
  }
  async get(k: string): Promise<string | null> {
    const r = await run(this.cmd, [...this.pre, "lookup", "service", SERVICE, "account", checkKey(k)], "");
    return r.code === 0 && r.stdout ? r.stdout : null;
  }
  async set(k: string, v: string): Promise<void> {
    const r = await run(this.cmd, [...this.pre, "store", `--label=Soul Continuidad`, "service", SERVICE, "account", checkKey(k)], v);
    if (r.code !== 0) throw new Error("secret-tool no guardó la credencial");
  }
  async delete(k: string): Promise<boolean> {
    const had = (await this.get(k)) !== null;
    const r = await run(this.cmd, [...this.pre, "clear", "service", SERVICE, "account", checkKey(k)], "");
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

/**
 * Windows: Credential Manager (CredRead/CredWrite/CredDelete de advapi32) por PowerShell, sin
 * módulos nativos. Cada entrada admite 2560 bytes de valor y el JSON con los tokens de Entra
 * suele pasar de 5 KB, así que el valor se guarda en base64 repartido en varias entradas:
 * `<clave>` lleva «N:» y el primer trozo; `<clave>/part-i`, el resto. Tamaño máximo:
 * `WIN_MAX_PARTS × WIN_PART` caracteres de base64 (unos 28 KB de valor).
 */
export const WIN_PART = 1200; // caracteres por entrada: el blob va en UTF-16, 2400 de 2560 bytes
export const WIN_MAX_PARTS = 32;
const partTarget = (k: string, i: number) => (i === 0 ? k : `${k}/part-${i}`);

/** Reparte el valor en trozos para Credential Manager. El primero lleva el número de trozos. */
export function splitParts(v: string): string[] {
  const b = Buffer.from(v, "utf8").toString("base64");
  const n = Math.max(1, Math.ceil(b.length / WIN_PART));
  if (n > WIN_MAX_PARTS) throw new Error("credencial demasiado grande para Credential Manager");
  const parts = Array.from({ length: n }, (_, i) => b.slice(i * WIN_PART, (i + 1) * WIN_PART));
  parts[0] = `${n}:${parts[0]}`;
  return parts;
}

/** Reconstruye el valor; null si falta la cabecera o algún trozo (entrada incompleta = sin credencial). */
export function joinParts(found: (string | null)[]): string | null {
  const m = /^(\d{1,2}):([A-Za-z0-9+/=]*)$/.exec(found[0] ?? "");
  if (!m) return null;
  const n = Number(m[1]);
  if (n < 1 || n > WIN_MAX_PARTS) return null;
  const rest = found.slice(1, n);
  if (rest.length !== n - 1 || rest.some((x) => x === null || !/^[A-Za-z0-9+/=]+$/.test(x))) return null;
  return Buffer.from(m[2] + rest.join(""), "base64").toString("utf8");
}

/**
 * Script sin secretos: va como -EncodedCommand. Las operaciones (y los trozos del secreto) llegan
 * por stdin en JSON; responde una línea por operación: «+valor» o «-» al leer, «+» o «-» al borrar.
 */
const WIN_SCRIPT = String.raw`$ErrorActionPreference='Stop'
try {
[Console]::InputEncoding = [Text.Encoding]::UTF8
$d = [Console]::In.ReadToEnd() | ConvertFrom-Json
Add-Type -TypeDefinition @"
${SOUL_CRED_CS}
"@
$out = New-Object System.Text.StringBuilder
foreach ($o in $d.ops) {
  switch ($o.op) {
    'r' { $v = [SoulCred]::Read($o.t); if ($null -eq $v) { [void]$out.AppendLine('-') } else { [void]$out.AppendLine('+' + $v) } }
    'w' { if (-not [SoulCred]::Write($o.t, $o.v)) { exit 4 }; [void]$out.AppendLine('+') }
    'd' { if ([SoulCred]::Delete($o.t)) { [void]$out.AppendLine('+') } else { [void]$out.AppendLine('-') } }
    default { exit 2 }
  }
}
[Console]::Out.Write($out.ToString())
exit 0
} catch { exit 1 }`;

export const WIN_PS_ARGS = ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(WIN_SCRIPT, "utf16le").toString("base64")];

type WinOp = { op: "r"; t: string } | { op: "w"; t: string; v: string } | { op: "d"; t: string };
export type RunFn = (cmd: string, args: string[], stdin: string) => Promise<Run>;

/** Windows Credential Manager con el valor repartido en entradas (ver `splitParts`). */
export class WindowsCredentialBackend implements SecretBackend {
  private readonly run: RunFn;
  /** `run` se sustituye en los tests por un doble del almacén. */
  constructor(o: { run?: RunFn } = {}) {
    this.run = o.run ?? run;
  }
  private async call(ops: WinOp[]): Promise<string[]> {
    const r = await this.run("powershell.exe", WIN_PS_ARGS, JSON.stringify({ ops }));
    const lines = r.stdout.split(/\r?\n/);
    if (lines.at(-1) === "") lines.pop();
    // Un código distinto de 0 o una respuesta que no cuadra es un fallo, nunca «no hay credencial».
    if (r.code !== 0 || lines.length !== ops.length) throw new Error(`Credential Manager no disponible (código ${r.code})`);
    return lines;
  }
  private readAll(k: string): WinOp[] {
    return Array.from({ length: WIN_MAX_PARTS }, (_, i) => ({ op: "r" as const, t: partTarget(k, i) }));
  }
  async get(k: string): Promise<string | null> {
    const lines = await this.call(this.readAll(checkKey(k)));
    return joinParts(lines.map((l) => (l.startsWith("+") ? l.slice(1) : null)));
  }
  async set(k: string, v: string): Promise<void> {
    checkKey(k);
    const parts = splitParts(v);
    // Los trozos antes que la cabecera; después se borran los sobrantes de un valor anterior más largo.
    const ops: WinOp[] = [];
    for (let i = parts.length - 1; i >= 0; i--) ops.push({ op: "w", t: partTarget(k, i), v: parts[i] });
    for (let i = parts.length; i < WIN_MAX_PARTS; i++) ops.push({ op: "d", t: partTarget(k, i) });
    await this.call(ops);
    if ((await this.get(k)) !== v) throw new Error("el almacén del sistema no guardó la credencial íntegra");
  }
  async delete(k: string): Promise<boolean> {
    const had = (await this.get(k)) !== null;
    // La cabecera, la última: si se corta a medias, lo que queda no se lee como credencial.
    await this.call(Array.from({ length: WIN_MAX_PARTS }, (_, i) => ({ op: "d" as const, t: partTarget(k, WIN_MAX_PARTS - 1 - i) })));
    if ((await this.get(k)) !== null) throw new Error("el almacén del sistema no borró la credencial");
    return had;
  }
}

/** Almacén por órdenes de sistema (Llavero de macOS). */
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
    // El Llavero puede rechazar o truncar valores: releer detecta un valor truncado
    // o rechazado en silencio en vez de dar por guardado un token que no sirve.
    if ((await this.get(k)) !== v) throw new Error("el almacén del sistema no guardó la credencial íntegra (¿supera su tamaño máximo?)");
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
  if (platform === "win32") return new WindowsCredentialBackend();
  throw new Error(`Sin almacén de credenciales reconocido para ${platform}: los adaptadores de API no se activan.`);
}
