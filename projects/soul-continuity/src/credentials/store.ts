/**
 * Almacén de credenciales del sistema (SE-490), sin módulos nativos:
 *   - Windows: Credential Manager por PowerShell (CredRead/CredWrite/CredDelete de advapi32),
 *     con el valor repartido en entradas de 2560 bytes como máximo;
 *   - macOS: llavero con `security`;
 *   - Linux: Secret Service con `secret-tool`.
 *
 * Reglas: el secreto viaja siempre por stdin, nunca en la línea de órdenes, en variables
 * de entorno, en ficheros ni en logs. En disco solo queda un índice con nombres de
 * servicio (sin secretos) para poder revocar y desinstalar. Un fallo de la herramienta
 * es un error, nunca «no hay credencial».
 */

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { CredentialError, type CredentialStore } from "../contract/adapter.ts";
import { readJson, writeJson } from "../core/store.ts";

export interface RunResult { code: number; stdout: string; stderr: string }
export type Run = (cmd: string, args: string[], input?: string) => Promise<RunResult>;

export interface SecretBackend {
  name: string;
  get(service: string, account: string): Promise<string | null>;
  set(service: string, account: string, secret: string): Promise<void>;
  delete(service: string, account: string): Promise<void>;
}

const APP = "soul-continuity";

export const hostRun: Run = (cmd, args, input = "") => new Promise((resolve) => {
  const p = spawn(cmd, args, { stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
  let stdout = "";
  let stderr = "";
  p.stdout.on("data", (b) => { stdout += b; });
  p.stderr.on("data", (b) => { stderr += b; });
  p.on("error", (e) => resolve({ code: 127, stdout: "", stderr: String(e.message) }));
  p.on("close", (code) => resolve({ code: code ?? 1, stdout, stderr }));
  // Si la herramienta sale sin leer stdin, escribir da EPIPE: no es un fallo del proceso de Soul,
  // el resultado lo dice el código de salida.
  p.stdin.on("error", () => {});
  p.stdin.end(input);
});

function unavailable(tool: string, r: RunResult): Error {
  return new Error(`almacén de credenciales no disponible (${tool}, código ${r.code})`);
}

function checkName(...parts: string[]): void {
  for (const p of parts) if (!/^[A-Za-z0-9._-]{1,64}$/.test(p)) throw new Error(`nombre no admitido: ${JSON.stringify(p)}`);
}

// ---------------------------------------------------------------------------- Linux

export function linuxBackend(run: Run): SecretBackend {
  const attrs = (s: string, a: string) => ["app", APP, "service", s, "account", a];
  return {
    name: "secret-service",
    async get(s, a) {
      checkName(s, a);
      const r = await run("secret-tool", ["lookup", ...attrs(s, a)]);
      if (r.code === 0) return r.stdout;
      if (r.code === 1 && !r.stderr.trim()) return null; // no encontrado
      throw unavailable("secret-tool", r);
    },
    async set(s, a, secret) {
      checkName(s, a);
      const r = await run("secret-tool", ["store", `--label=Savia Soul ${s}`, ...attrs(s, a)], secret);
      if (r.code !== 0) throw unavailable("secret-tool", r);
    },
    async delete(s, a) {
      checkName(s, a);
      const r = await run("secret-tool", ["clear", ...attrs(s, a)]);
      if (r.code !== 0) throw unavailable("secret-tool", r);
    },
  };
}

// ---------------------------------------------------------------------------- macOS

export function macBackend(run: Run): SecretBackend {
  const svc = (s: string) => `${APP}.${s}`;
  return {
    name: "keychain",
    async get(s, a) {
      checkName(s, a);
      const r = await run("security", ["find-generic-password", "-a", a, "-s", svc(s), "-w"]);
      if (r.code === 0) return r.stdout.replace(/\n$/, "");
      if (r.code === 44) return null; // errSecItemNotFound
      throw unavailable("security", r);
    },
    async set(s, a, secret) {
      checkName(s, a);
      if (/["\\\n\r]/.test(secret)) throw new Error("carácter no admitido en el secreto");
      // `security -i` lee la orden por stdin: el secreto no aparece en la lista de procesos.
      const r = await run("security", ["-i"], `add-generic-password -U -a "${a}" -s "${svc(s)}" -w "${secret}"\n`);
      if (r.code !== 0 || /error/i.test(r.stderr)) throw unavailable("security", r);
    },
    async delete(s, a) {
      checkName(s, a);
      const r = await run("security", ["delete-generic-password", "-a", a, "-s", svc(s)]);
      if (r.code !== 0 && r.code !== 44) throw unavailable("security", r);
    },
  };
}

// ---------------------------------------------------------------------------- Windows

/** Tipo C# sobre advapi32 (CredRead/CredWrite/CredDelete). */
export const SOUL_CRED_CS = String.raw`using System; using System.Runtime.InteropServices; using System.Text;
public static class SoulCred {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
    public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredReadW(string t, int type, int flags, out IntPtr cred);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredWriteW(ref CREDENTIAL c, int flags);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredDeleteW(string t, int type, int flags);
  [DllImport("advapi32.dll")] static extern void CredFree(IntPtr p);
  public static string Read(string t) { IntPtr p;
    if (!CredReadW(t, 1, 0, out p)) { if (Marshal.GetLastWin32Error() == 1168) return null; throw new Exception("CredRead"); }
    try { var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL)); return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2); } finally { CredFree(p); } }
  public static bool Write(string t, string s) { var b = Encoding.Unicode.GetBytes(s); var c = new CREDENTIAL(); c.Type = 1; c.TargetName = t;
    c.UserName = "soul-continuity"; c.Persist = 2; c.CredentialBlobSize = b.Length; c.CredentialBlob = Marshal.AllocHGlobal(b.Length);
    try { Marshal.Copy(b, 0, c.CredentialBlob, b.Length); return CredWriteW(ref c, 0); } finally { Marshal.FreeHGlobal(c.CredentialBlob); } }
  public static bool Delete(string t) { return CredDeleteW(t, 1, 0); }
}`;

/**
 * Cada entrada de Credential Manager admite 2560 bytes de blob (en UTF-16) y el JSON con los
 * tokens de Entra pasa de 5 KB, así que el valor se guarda en base64 repartido en varias
 * entradas: `<destino>` lleva «N:hash:» y el primer trozo; `<destino>/part-i`, el resto. El hash
 * (16 hex de SHA-256 del base64 completo) descarta una mezcla de dos valores si un `set` se corta
 * a medias o compite con otro: se lee como sin credencial, nunca como un token corrupto.
 * Tamaño máximo: `WIN_MAX_PARTS × WIN_PART` caracteres de base64 (unos 28 KB de valor).
 */
export const WIN_PART = 1200; // caracteres por entrada: 2400 de 2560 bytes
export const WIN_MAX_PARTS = 32;
const PART_RE = /^[A-Za-z0-9+/=]+$/;
const h16 = (s: string) => createHash("sha256").update(s).digest("hex").slice(0, 16);

/** Reparte el valor en trozos para Credential Manager. El primero lleva el número de trozos y el hash. */
export function splitParts(v: string): string[] {
  const b = Buffer.from(v, "utf8").toString("base64");
  const n = Math.max(1, Math.ceil(b.length / WIN_PART));
  if (n > WIN_MAX_PARTS) throw new Error("credencial demasiado grande para Credential Manager");
  const parts = Array.from({ length: n }, (_, i) => b.slice(i * WIN_PART, (i + 1) * WIN_PART));
  parts[0] = `${n}:${h16(b)}:${parts[0]}`;
  return parts;
}

/** Reconstruye el valor; null si falta la cabecera o algún trozo, o si el hash no cuadra. */
export function joinParts(found: (string | null)[]): string | null {
  const m = /^(\d{1,2}):([0-9a-f]{16}):([A-Za-z0-9+/=]*)$/.exec(found[0] ?? "");
  if (!m) return null;
  const n = Number(m[1]);
  if (n < 1 || n > WIN_MAX_PARTS) return null;
  const rest = found.slice(1, n);
  if (rest.length !== n - 1 || rest.some((x) => x === null || !PART_RE.test(x))) return null;
  const b = m[3] + rest.join("");
  if (h16(b) !== m[2]) return null;
  return Buffer.from(b, "base64").toString("utf8");
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

/**
 * Ruta absoluta de Windows PowerShell. Por nombre, Windows busca antes en el directorio de
 * trabajo que en PATH: un `powershell.exe` plantado ahí recibiría los secretos por stdin.
 */
export function powershellPath(env: Record<string, string | undefined> = process.env): string {
  const root = env.SystemRoot ?? env.windir ?? "C:\\Windows";
  if (!/^[A-Za-z]:\\[^"<>|?*]*$/.test(root)) throw new Error("SystemRoot no es una ruta absoluta de Windows");
  return `${root.replace(/\\+$/, "")}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe`;
}

type WinOp = { op: "r"; t: string } | { op: "w"; t: string; v: string } | { op: "d"; t: string };

/**
 * Windows Credential Manager con el valor repartido en entradas (ver `splitParts`). Los nombres
 * pasan `checkName` (sin «/»), así que un servicio o cuenta no puede pisar el trozo de otro.
 */
export function windowsBackend(run: Run): SecretBackend {
  const part = (s: string, a: string, i: number) => (i === 0 ? `${APP}/${s}/${a}` : `${APP}/${s}/${a}/part-${i}`);
  const call = async (ops: WinOp[]): Promise<string[]> => {
    const r = await run(powershellPath(), WIN_PS_ARGS, JSON.stringify({ ops }));
    const lines = r.stdout.split(/\r?\n/);
    if (lines.at(-1) === "") lines.pop();
    // Un código distinto de 0 o una respuesta que no cuadra es un fallo, nunca «no hay credencial».
    if (r.code !== 0 || lines.length !== ops.length) throw unavailable("powershell", r);
    return lines;
  };
  const range = <T>(f: (i: number) => T) => Array.from({ length: WIN_MAX_PARTS }, (_, i) => f(i));
  return {
    name: "credential-manager",
    async get(s, a) {
      checkName(s, a);
      const lines = await call(range((i) => ({ op: "r" as const, t: part(s, a, i) })));
      return joinParts(lines.map((l) => (l.startsWith("+") ? l.slice(1) : null)));
    },
    async set(s, a, secret) {
      checkName(s, a);
      const parts = splitParts(secret);
      // Los trozos antes que la cabecera; después se borran los sobrantes de un valor anterior más largo.
      const ops: WinOp[] = [];
      for (let i = parts.length - 1; i >= 0; i--) ops.push({ op: "w", t: part(s, a, i), v: parts[i] });
      for (let i = parts.length; i < WIN_MAX_PARTS; i++) ops.push({ op: "d", t: part(s, a, i) });
      await call(ops);
    },
    async delete(s, a) {
      checkName(s, a);
      // La cabecera, la última: si se corta a medias, lo que queda no se lee como credencial.
      await call(range((i) => ({ op: "d" as const, t: part(s, a, WIN_MAX_PARTS - 1 - i) })));
    },
  };
}

export function backendFor(platform: string, run: Run = hostRun): SecretBackend {
  if (platform === "linux") return linuxBackend(run);
  if (platform === "darwin") return macBackend(run);
  if (platform === "win32") return windowsBackend(run);
  throw new Error(`sin almacén de credenciales para ${platform}`);
}

// ---------------------------------------------------------------------------- contrato

const INDEX = "credentials-index.json";
const ACCOUNT = "default";

/** Entrada del índice: dónde está un secreto en el almacén del sistema (nunca el secreto). */
export interface IndexEntry { service: string; account: string }

/** Claves de los tokens de los adaptadores de API (`src/adapters/credential-store.ts`, `entryKey`). */
const API_KEY = /^soul-continuity\/([0-9a-f]{16})\/([a-z0-9-]{1,40})\/([0-9a-f]{16})$/;

/** Interfaz de clave única que usan los adaptadores de API para guardar sus tokens. */
export interface KeyedSecrets {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  delete(key: string): Promise<boolean>;
}

/**
 * El único almacén de credenciales de Soul (SE-490, H-2): el del sistema, con un índice en disco
 * sin secretos. Todo lo que guarda Soul pasa por aquí y queda en el índice, también los tokens de
 * los adaptadores de API (`keyed()`), así que `forgetAll` (desinstalar) no deja ninguno atrás.
 */
export class SystemCredentialStore implements CredentialStore {
  readonly backend: SecretBackend;
  readonly dataDir: string;
  constructor(backend: SecretBackend, dataDir: string) {
    this.backend = backend;
    this.dataDir = dataDir;
  }

  /** Entradas registradas. Lee también el formato anterior (`services`, cuenta `default`). */
  index(): IndexEntry[] {
    const raw = readJson<{ services?: unknown; entries?: unknown }>(join(this.dataDir, INDEX), {});
    const out: IndexEntry[] = [];
    if (Array.isArray(raw.services)) for (const s of raw.services) if (typeof s === "string") out.push({ service: s, account: ACCOUNT });
    if (Array.isArray(raw.entries)) {
      for (const e of raw.entries as Partial<IndexEntry>[]) {
        if (typeof e?.service === "string" && typeof e?.account === "string") out.push({ service: e.service, account: e.account });
      }
    }
    return out;
  }

  private saveIndex(entries: IndexEntry[]): void {
    const seen = new Map(entries.map((e) => [`${e.service}\u0000${e.account}`, e]));
    const list = [...seen.values()].sort((a, b) => `${a.service}/${a.account}`.localeCompare(`${b.service}/${b.account}`));
    writeJson(join(this.dataDir, INDEX), { entries: list });
  }

  /** Se anota antes de guardar: si el guardado falla, desinstalar borra una entrada vacía; nunca queda un secreto sin índice. */
  private async store(service: string, account: string, secret: string): Promise<void> {
    checkName(service, account);
    this.saveIndex([...this.index(), { service, account }]);
    await this.backend.set(service, account, secret);
    // Se relee: un almacén que trunca o no guarda (y sale con 0) no deja un login roto en silencio.
    if ((await this.backend.get(service, account)) !== secret) throw new Error("el almacén del sistema no guardó la credencial completa");
  }

  /** Borra y relee: no se informa de un borrado que no ocurrió (Credential Manager sale con 0 aunque falle). */
  private async deleteVerified(service: string, account: string): Promise<void> {
    await this.backend.delete(service, account);
    if ((await this.backend.get(service, account)) !== null) throw new Error("el almacén del sistema no borró la credencial");
  }

  private async remove(service: string, account: string): Promise<void> {
    await this.deleteVerified(service, account);
    this.saveIndex(this.index().filter((e) => !(e.service === service && e.account === account)));
  }

  async acquire(service: string, _scopes: string[]): Promise<string> {
    const v = await this.backend.get(service, ACCOUNT);
    if (v === null || v === "") throw new CredentialError("no_credential", `sin credencial para ${service}: inicia sesión con «soul login»`);
    return v;
  }

  async put(service: string, secret: string): Promise<void> {
    await this.store(service, ACCOUNT, secret);
  }

  /** Borra la credencial del servicio. Devuelve lo borrado. */
  async forget(service: string): Promise<string[]> {
    await this.remove(service, ACCOUNT);
    return [service];
  }

  /**
   * Borra todas las credenciales del índice. Si alguna no se puede borrar, sigue con las demás,
   * deja en el índice solo las que fallaron y lanza: no se informa de un borrado que no ocurrió.
   */
  async forgetAll(): Promise<string[]> {
    const all = this.index();
    const failed: IndexEntry[] = [];
    for (const e of all) {
      try { await this.deleteVerified(e.service, e.account); } catch { failed.push(e); }
    }
    this.saveIndex(failed);
    if (failed.length) throw new Error(`no se pudieron borrar ${failed.length} credencial(es) del almacén del sistema`);
    return all.map((e) => (e.account === ACCOUNT ? e.service : `${e.service}/${e.account}`));
  }

  /**
   * Vista de clave única para los tokens de los adaptadores de API. Cada clave se traduce a
   * servicio `api-<servicio>` y cuenta `<operador>.<permisos>` (hashes), y queda en el índice.
   * El valor va en base64: el JSON del token lleva comillas que el llavero de macOS no admite.
   */
  keyed(): KeyedSecrets {
    const split = (key: string): IndexEntry => {
      const m = API_KEY.exec(key);
      if (!m) throw new Error("clave de credencial no admitida");
      return { service: `api-${m[2]}`, account: `${m[1]}.${m[3]}` };
    };
    return {
      get: async (key) => {
        const e = split(key);
        const v = await this.backend.get(e.service, e.account);
        return v === null || v === "" ? null : Buffer.from(v, "base64").toString("utf8");
      },
      set: async (key, value) => {
        const e = split(key);
        await this.store(e.service, e.account, Buffer.from(value, "utf8").toString("base64"));
      },
      delete: async (key) => {
        const e = split(key);
        const had = (await this.backend.get(e.service, e.account)) !== null;
        await this.remove(e.service, e.account);
        return had;
      },
    };
  }
}
