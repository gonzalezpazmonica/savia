/**
 * El instalador de usuario de `docs/instalar.md`, paso a paso por `bin/soul.mjs`, con un HOME
 * falso en los tres sistemas (AC-1 de SE-490): no se toca el llavero ni el arranque reales.
 *   - Linux: dobles de `secret-tool` y `systemctl` en el PATH; datos en `~/.local/share`.
 *   - macOS: dobles de `security` y `launchctl` en el PATH; datos en `~/Library/Application Support`.
 *   - Windows: USERPROFILE, LOCALAPPDATA y APPDATA falsos (HOME no cuenta allí). Soul llama a
 *     PowerShell por ruta absoluta y a schtasks como .exe, así que no admiten dobles de script: el
 *     token va al Credential Manager real con una cuenta derivada del operador (única por
 *     instalación) y `uninstall` ejecuta schtasks sobre la tarea de usuario. Por eso en Windows solo
 *     corre en CI (runner efímero): en un equipo con Soul instalado retiraría su arranque automático.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";
import { hostRun, windowsBackend } from "../src/credentials/store.ts";

const BIN = fileURLToPath(new URL("../bin/soul.mjs", import.meta.url));
const TOKEN = "github-pat-canario-instalar-1c9";
const OS = process.platform;
const SKIP = OS === "win32" && !process.env.CI ? "en Windows toca Credential Manager y schtasks reales: solo en CI" : false;

function files(dir: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((f) => { const p = join(dir, f); return statSync(p).isDirectory() ? files(p) : [p]; });
}

const SECRET_TOOL = `#!/bin/sh
op="$1"; shift
case "$1" in --label=*) shift;; esac
k=$(printf '%s|' "$@" | sha256sum | cut -c1-32)
d="$HOME/.llavero-falso"; mkdir -p "$d"
case "$op" in
  store) cat > "$d/$k";;
  lookup) [ -f "$d/$k" ] && cat "$d/$k" || exit 1;;
  clear) rm -f "$d/$k";;
esac
`;

/** `security` de macOS: lo justo de find / add (con -i, por stdin) / delete-generic-password; 44 = no encontrado. */
const SECURITY = String.raw`#!/bin/sh
d="$HOME/.llavero-falso"; mkdir -p "$d"
parse() { a=; s=; while [ $# -gt 0 ]; do case "$1" in -a) a="$2"; shift;; -s) s="$2"; shift;; esac; shift; done; }
case "$1" in
  find-generic-password) shift; parse "$@"; [ -f "$d/$s.$a" ] || exit 44; cat "$d/$s.$a"; echo;;
  delete-generic-password) shift; parse "$@"; [ -f "$d/$s.$a" ] || exit 44; rm -f "$d/$s.$a";;
  -i) read -r l
      case "$l" in add-generic-password\ *) ;; *) exit 2;; esac
      a=$(printf '%s' "$l" | sed -n 's/.* -a "\([^"]*\)".*/\1/p')
      s=$(printf '%s' "$l" | sed -n 's/.* -s "\([^"]*\)".*/\1/p')
      w=$(printf '%s' "$l" | sed -n 's/.* -w "\([^"]*\)".*/\1/p')
      [ -n "$a" ] && [ -n "$s" ] && [ -n "$w" ] || exit 2
      printf '%s' "$w" > "$d/$s.$a";;
  *) exit 2;;
esac
`;

const LOG = `#!/bin/sh\necho "$0 $@" >> "$HOME/.arranque-falso.log"\n`;

function sandbox() {
  const home = mkdtempSync(join(tmpdir(), "soul-home-falso-"));
  const bin = join(home, ".dobles");
  mkdirSync(bin);
  const dobles: Record<string, string> = OS === "darwin" ? { security: SECURITY, launchctl: LOG } : { "secret-tool": SECRET_TOOL, systemctl: LOG };
  for (const [n, c] of Object.entries(dobles)) { writeFileSync(join(bin, n), c); chmodSync(join(bin, n), 0o755); }
  // Entorno mínimo de una persona en su terminal: sin variables de frontends de agente.
  const env: Record<string, string> = { PATH: `${bin}${delimiter}${process.env.PATH}`, HOME: home, LANG: "C.UTF-8" };
  const local = join(home, "AppData", "Local");
  if (OS === "win32") {
    // En Windows el perfil es USERPROFILE (os.homedir) y los datos van a LOCALAPPDATA.
    Object.assign(env, { USERPROFILE: home, LOCALAPPDATA: local, APPDATA: join(home, "AppData", "Roaming") });
    // Lo que Node, PowerShell y Add-Type necesitan para arrancar; ninguna apunta al perfil del usuario.
    for (const k of ["SystemRoot", "windir", "SystemDrive", "ComSpec", "PATHEXT", "TEMP", "TMP"]) if (process.env[k]) env[k] = process.env[k]!;
  }
  const data = OS === "win32" ? join(local, "Savia", "soul-continuity")
    : OS === "darwin" ? join(home, "Library", "Application Support", "Savia", "soul-continuity")
    : join(home, ".local", "share", "savia", "soul-continuity");
  const autostart = OS === "win32" ? join(data, "autostart-task.xml")
    : OS === "darwin" ? join(home, "Library", "LaunchAgents", "org.savia.soul-continuity.plist")
    : join(home, ".config", "systemd", "user", "soul-continuity.service");
  const soul = (args: string[], input?: string, extra: Record<string, string> = {}) =>
    spawnSync(process.execPath, [BIN, ...args], { env: { ...env, ...extra }, input, encoding: "utf8", timeout: 60_000 });
  return { home, soul, data, autostart };
}

type Entry = { service: string; account: string };
const indexOf = (data: string): Entry[] => {
  const f = join(data, "credentials-index.json");
  return existsSync(f) ? (JSON.parse(readFileSync(f, "utf8")).entries ?? []) : [];
};

/** Secretos que guarda el almacén del sistema: el doble en Linux y macOS; en Windows, las entradas indicadas. */
async function secrets(home: string, entries: Entry[]): Promise<string[]> {
  if (OS !== "win32") {
    const d = join(home, ".llavero-falso");
    return existsSync(d) ? readdirSync(d).map((f) => readFileSync(join(d, f), "utf8")) : [];
  }
  const cm = windowsBackend(hostRun);
  const out: string[] = [];
  for (const e of entries) { const v = await cm.get(e.service, e.account); if (v !== null) out.push(v); }
  return out;
}
/** El valor tal cual y decodificado de base64 (así lo guarda Soul para los adaptadores de API). */
const plain = (vs: string[]) => vs.map((v) => `${v}\n${Buffer.from(v, "base64").toString("utf8")}`).join("\n");

test("instalar.md: init, status, login, pair, autostart y uninstall con HOME falso, sin dejar estado", { skip: SKIP }, async () => {
  const s = sandbox();
  let r = s.soul(["init", "trabajo", "--email", "yo@example.test"]);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(existsSync(join(s.data, "config.json")), `la configuración va al directorio de datos del usuario (${s.data})`);

  r = s.soul(["status", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(r.stdout).profile, "trabajo");

  r = s.soul(["login", "github", "--token-stdin"], `${TOKEN}\n`);
  assert.equal(r.status, 0, r.stderr);
  const entries = indexOf(s.data);
  assert.equal(entries.length, 1, "una entrada en el índice, sin secreto");
  const stored = await secrets(s.home, entries);
  assert.equal(stored.length, 1, "el token va al almacén del sistema");
  assert.ok(plain(stored).includes(TOKEN), "lo guardado es el token pegado");
  assert.ok(!files(s.data).some((f) => readFileSync(f, "utf8").includes(TOKEN)), "0 tokens en el directorio de datos");

  const cfg = JSON.parse(readFileSync(join(s.data, "config.json"), "utf8"));
  cfg.api.listen = ["127.0.0.1"];
  writeFileSync(join(s.data, "config.json"), JSON.stringify(cfg));
  r = s.soul(["pair", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(JSON.parse(r.stdout).pin, /^sha256\//);
  assert.match(JSON.parse(r.stdout).clave, /^soulpk_[0-9A-Za-z]{30}_[0-9A-Za-z]{6}$/);

  r = s.soul(["autostart", "install", "--dry-run"]);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(r.stdout.includes(s.autostart), `el arranque es del usuario, dentro de su perfil (${s.autostart})`);
  assert.equal(existsSync(s.autostart), false, "--dry-run no escribe nada");

  r = s.soul(["uninstall", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(existsSync(s.data), false, "no queda el directorio de datos");
  assert.deepEqual(await secrets(s.home, entries), [], "no queda ningún token");
  const left = files(s.home).filter((f) => !f.includes(".dobles") && !f.endsWith(".arranque-falso.log"));
  assert.deepEqual(left, [], "nada de Soul en el HOME");
  assert.ok(![r.stdout, r.stderr].join("").includes(TOKEN));
});

test("instalar.md: desde un frontend de agente, init y login se rechazan (código 4)", { skip: SKIP }, async () => {
  const s = sandbox();
  const r = s.soul(["init", "trabajo"], undefined, { CLAUDECODE: "1" });
  assert.equal(r.status, 4);
  assert.equal(existsSync(join(s.data, "config.json")), false, "no crea la instalación (solo queda la auditoría de la llamada)");
  const l = s.soul(["login", "github", "--token-stdin"], `${TOKEN}\n`, { CLAUDECODE: "1" });
  assert.equal(l.status, 4);
  assert.deepEqual(await secrets(s.home, indexOf(s.data)), [], "no llega al almacén del sistema");
  assert.deepEqual(indexOf(s.data), [], "ni al índice");
});
