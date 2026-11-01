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

/** Script sin secretos: va como -EncodedCommand; los datos (y el secreto) llegan por stdin. */
const PS_SCRIPT = String.raw`$ErrorActionPreference='Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$d = [Console]::In.ReadToEnd() | ConvertFrom-Json
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Text;
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
}
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
