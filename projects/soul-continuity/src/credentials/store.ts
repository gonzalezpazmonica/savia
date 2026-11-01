/**
 * Almacén de credenciales del sistema (SE-490), sin módulos nativos:
 *   - Windows: Credential Manager por PowerShell (CredRead/CredWrite/CredDelete de advapi32);
 *   - macOS: llavero con `security`;
 *   - Linux: Secret Service con `secret-tool`.
 *
 * Reglas: el secreto viaja siempre por stdin, nunca en la línea de órdenes, en variables
 * de entorno, en ficheros ni en logs. En disco solo queda un índice con nombres de
 * servicio (sin secretos) para poder revocar y desinstalar. Un fallo de la herramienta
 * es un error, nunca «no hay credencial».
 */

import { spawn } from "node:child_process";
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

/** Tipo C# sobre advapi32 (CredRead/CredWrite/CredDelete); también lo usa el almacén de los adaptadores. */
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

/** Script sin secretos: va como -EncodedCommand; los datos (y el secreto) llegan por stdin. */
const PS_SCRIPT = String.raw`$ErrorActionPreference='Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$d = [Console]::In.ReadToEnd() | ConvertFrom-Json
Add-Type -TypeDefinition @"
${SOUL_CRED_CS}
"@
switch ($d.op) {
  'get' { $v = [SoulCred]::Read($d.target); if ($null -eq $v) { exit 3 }; [Console]::Out.Write($v); exit 0 }
  'set' { if ([SoulCred]::Write($d.target, $d.secret)) { exit 0 } else { exit 4 } }
  'delete' { [void][SoulCred]::Delete($d.target); exit 0 }
}
exit 2`;

export const PS_ARGS = ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(PS_SCRIPT, "utf16le").toString("base64")];

export function windowsBackend(run: Run): SecretBackend {
  const target = (s: string, a: string) => `${APP}/${s}/${a}`;
  const call = (data: Record<string, string>) => run("powershell.exe", PS_ARGS, JSON.stringify(data) + "\n");
  return {
    name: "credential-manager",
    async get(s, a) {
      checkName(s, a);
      const r = await call({ op: "get", target: target(s, a) });
      if (r.code === 0) return r.stdout;
      if (r.code === 3) return null;
      throw unavailable("powershell", r);
    },
    async set(s, a, secret) {
      checkName(s, a);
      const r = await call({ op: "set", target: target(s, a), secret });
      if (r.code !== 0) throw unavailable("powershell", r);
    },
    async delete(s, a) {
      checkName(s, a);
      const r = await call({ op: "delete", target: target(s, a) });
      if (r.code !== 0) throw unavailable("powershell", r);
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

/** `CredentialStore` del contrato sobre el almacén del sistema, con índice de servicios (sin secretos). */
export class SystemCredentialStore implements CredentialStore {
  readonly backend: SecretBackend;
  readonly dataDir: string;
  constructor(backend: SecretBackend, dataDir: string) {
    this.backend = backend;
    this.dataDir = dataDir;
  }

  private index(): string[] {
    return readJson<{ services: string[] }>(join(this.dataDir, INDEX), { services: [] }).services;
  }

  private saveIndex(services: string[]): void {
    writeJson(join(this.dataDir, INDEX), { services: [...new Set(services)].sort() });
  }

  async acquire(service: string, _scopes: string[]): Promise<string> {
    const v = await this.backend.get(service, ACCOUNT);
    if (v === null || v === "") throw new CredentialError("no_credential", `sin credencial para ${service}: inicia sesión con «soul login ${service}»`);
    return v;
  }

  async put(service: string, secret: string): Promise<void> {
    await this.backend.set(service, ACCOUNT, secret);
    this.saveIndex([...this.index(), service]);
  }

  /** Borra la credencial del servicio. Devuelve lo borrado. */
  async forget(service: string): Promise<string[]> {
    await this.backend.delete(service, ACCOUNT);
    this.saveIndex(this.index().filter((s) => s !== service));
    return [service];
  }

  async forgetAll(): Promise<string[]> {
    const all = this.index();
    for (const s of all) await this.backend.delete(s, ACCOUNT);
    this.saveIndex([]);
    return all;
  }
}
