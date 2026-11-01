// Perfil dedicado a Soul y navegador ya instalado. Nunca se toca el perfil
// personal; nunca se descargan navegadores.

import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, realpathSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join, relative, sep } from "node:path";
import { dataDir } from "../../core/store.ts";

export const MARCA = ".perfil-soul";

/** Raíces de perfiles personales conocidas (Linux, macOS, Windows). */
export function rutasPerfilPersonal(hogar: string, localAppData = process.env.LOCALAPPDATA ?? ""): string[] {
  const r = [
    join(hogar, ".config", "google-chrome"), join(hogar, ".config", "google-chrome-beta"),
    join(hogar, ".config", "microsoft-edge"), join(hogar, ".config", "chromium"),
    join(hogar, "snap", "chromium"), join(hogar, ".mozilla"),
    join(hogar, "Library", "Application Support", "Google", "Chrome"),
    join(hogar, "Library", "Application Support", "Microsoft Edge"),
  ];
  if (localAppData) r.push(join(localAppData, "Google", "Chrome", "User Data"), join(localAppData, "Microsoft", "Edge", "User Data"));
  return r;
}

/** Directorio de datos de Soul del usuario del sistema: el mismo que el del núcleo
 *  (`src/core/store.ts`), así `soul uninstall` borra también `<datos>/web` (H-4). `SOUL_DATA_DIR` manda. */
export function directorioDatos(env: NodeJS.ProcessEnv = process.env, plataforma = process.platform, hogar = homedir()): string {
  return dataDir({ platform: plataforma, env, home: hogar });
}

/**
 * Almacén de las claves de cookies del navegador en Linux (H-5). Un perfil **persistente** (el del
 * producto, con sesiones del operador) cifra sus cookies con una clave guardada en el llavero del
 * sistema (`gnome-libsecret`), como los tokens de Soul. Sin bus de sesión no hay llavero: no se abre
 * (fail-closed), en vez de caer a la clave fija de Chromium. Un perfil **temporal** (banco y
 * vigilancia de prueba) se borra al cerrar y usa `basic`: no deja sesiones. En macOS y Windows el
 * navegador usa el Llavero y DPAPI por defecto y no hace falta indicador.
 */
export function almacenClaves(o: { persistente: boolean; plataforma?: NodeJS.Platform; env?: NodeJS.ProcessEnv }): string[] {
  const plataforma = o.plataforma ?? process.platform;
  const env = o.env ?? process.env;
  if (plataforma !== "linux") return [];
  if (!o.persistente) return ["--password-store=basic"];
  // XDG_RUNTIME_DIR existe en casi cualquier sesión systemd (también por SSH sin llavero): solo cuenta si tiene el socket del bus.
  if (!env.DBUS_SESSION_BUS_ADDRESS && !(env.XDG_RUNTIME_DIR && existsSync(join(env.XDG_RUNTIME_DIR, "bus")))) {
    throw new Error("sin bus de sesión no hay llavero del sistema: el perfil persistente de Soul no se abre (sus cookies quedarían con la clave fija de Chromium)");
  }
  return ["--password-store=gnome-libsecret"];
}

/** Preferencias que el perfil de Soul fija en cada arranque: el navegador no
 *  ofrece guardar contraseñas ni autorrellena. Soul nunca guarda credenciales. */
export const PREFERENCIAS_SOUL = {
  credentials_enable_service: false,
  credentials_enable_autosignin: false,
  profile: { password_manager_enabled: false },
  autofill: { profile_enabled: false, credit_card_enabled: false },
} as const;

function fundir(a: Record<string, unknown>, b: Record<string, unknown>): Record<string, unknown> {
  const out = { ...a };
  for (const [k, v] of Object.entries(b)) {
    const previo = out[k];
    out[k] = v && typeof v === "object" && previo && typeof previo === "object" && !Array.isArray(previo)
      ? fundir(previo as Record<string, unknown>, v as Record<string, unknown>) : v;
  }
  return out;
}

/** Fija `PREFERENCIAS_SOUL` en `Default/Preferences` sin perder lo demás. */
export function fijarPreferencias(perfil: string) {
  const def = join(perfil, "Default");
  mkdirSync(def, { recursive: true });
  const ruta = join(def, "Preferences");
  let previas: Record<string, unknown> = {};
  try { previas = JSON.parse(readFileSync(ruta, "utf8")); } catch { previas = {}; }
  writeFileSync(ruta, JSON.stringify(fundir(previas, PREFERENCIAS_SOUL as unknown as Record<string, unknown>)));
}

function marcar(dir: string, texto: string) {
  if (!existsSync(join(dir, MARCA))) writeFileSync(join(dir, MARCA), texto);
  fijarPreferencias(dir);
  return dir;
}

/** Perfil temporal (banco y pruebas): se borra al terminar. */
export function crearPerfilDedicado(): string {
  return marcar(mkdtempSync(join(tmpdir(), "soul-perfil-")), "perfil dedicado a Soul; temporal\n");
}

/** Perfil persistente del producto, en el directorio de datos: el operador
 *  inicia sesión en él una vez, solo en las webs que da a Soul. Se rechaza si
 *  cae dentro de un perfil personal. */
export function prepararPerfilSoul(datos: string, hogar = homedir()): string {
  const dir = join(datos, "web", "perfil");
  comprobarFueraDePersonal(dir, rutasPerfilPersonal(hogar));
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  return marcar(dir, "perfil dedicado a Soul\n");
}

function real(p: string) {
  try { return realpathSync(p); } catch { return p; }
}

function comprobarFueraDePersonal(dir: string, personales: string[]) {
  const d = real(dir);
  for (const p of personales.map(real)) {
    const rel = relative(p, d);
    if (rel === "" || (!rel.startsWith("..") && !rel.startsWith(sep) && !/^[A-Za-z]:/.test(rel))) {
      throw new Error(`perfil rechazado: ${dir} está dentro de un perfil personal`);
    }
  }
}

/** Fail-closed: lanza si `dir` es o está dentro de un perfil personal, o no lleva la marca. */
export function comprobarPerfilDedicado(dir: string, personales: string[]) {
  comprobarFueraDePersonal(dir, personales);
  const d = real(dir);
  if (!existsSync(join(d, MARCA))) throw new Error(`perfil rechazado: ${dir} no es un perfil dedicado de Soul`);
}

/** Huella de un árbol de ficheros: ruta, tamaño, mtime y sha256. */
export function huella(dir: string): Record<string, string> {
  const out: Record<string, string> = {};
  const rec = (d: string) => {
    for (const n of readdirSync(d)) {
      const p = join(d, n);
      // lstat: Chrome deja enlaces simbólicos colgantes (SingletonCookie…); se anotan, no se siguen.
      const s = lstatSync(p);
      if (s.isSymbolicLink()) out[relative(dir, p)] = `enlace:${readlinkSync(p)}`;
      else if (s.isDirectory()) rec(p);
      else out[relative(dir, p)] = `${s.size}:${s.mtimeMs}:${createHash("sha256").update(readFileSync(p)).digest("hex")}`;
    }
  };
  if (existsSync(dir)) rec(dir);
  return out;
}

export function diferenciasHuella(a: Record<string, string>, b: Record<string, string>): string[] {
  const claves = new Set([...Object.keys(a), ...Object.keys(b)]);
  return [...claves].filter((k) => a[k] !== b[k]).sort();
}

/** HOME sintético con un perfil personal «canario» que nadie debe tocar. */
export function crearHogarCanario(): { hogar: string; perfilPersonal: string } {
  const hogar = mkdtempSync(join(tmpdir(), "soul-hogar-"));
  const perfilPersonal = join(hogar, ".config", "google-chrome");
  const def = join(perfilPersonal, "Default");
  mkdirSync(def, { recursive: true });
  writeFileSync(join(perfilPersonal, "Local State"), '{"canario":true}');
  // JSON válido: con un `Cookies` que no es SQLite, Chrome se cuelga al arrancar (lo usa el mutante).
  writeFileSync(join(def, "Bookmarks"), '{"canario":"marcadores-personales"}');
  writeFileSync(join(def, "Preferences"), '{"canario":true}');
  return { hogar, perfilPersonal };
}

/** Navegador instalado: Chrome o Edge; Chromium del sistema como último recurso, avisándolo. */
export function buscarNavegador(): { ruta: string; nombre: string; aviso?: string } {
  const env = process.env.SOUL_NAVEGADOR;
  if (env && existsSync(env)) return { ruta: env, nombre: "configurado" };
  const candidatos: [string, string][] = [
    ["/usr/bin/google-chrome-stable", "Chrome"], ["/usr/bin/google-chrome", "Chrome"],
    ["/usr/bin/microsoft-edge-stable", "Edge"], ["/usr/bin/microsoft-edge", "Edge"],
    ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "Chrome"],
    ["/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge", "Edge"],
    ["C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "Chrome"],
    ["C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "Edge"],
  ];
  for (const [ruta, nombre] of candidatos) if (existsSync(ruta)) return { ruta, nombre };
  for (const ruta of ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/snap/bin/chromium"]) {
    if (existsSync(ruta)) return { ruta, nombre: "Chromium", aviso: "Sin Chrome ni Edge: se usa Chromium del sistema." };
  }
  throw new Error("No hay Chrome, Edge ni Chromium instalados; no se descargan navegadores.");
}

/** Linux: procesos del navegador de este perfil y su canal de depuración. */
export function canalDepuracion(perfil: string): { procesos: number; tuberia: boolean; puerto: boolean } | null {
  if (process.platform !== "linux") return null;
  let procesos = 0, tuberia = false, puerto = false;
  for (const pid of readdirSync("/proc").filter((x) => /^\d+$/.test(x))) {
    let cmd = "";
    try { cmd = readFileSync(`/proc/${pid}/cmdline`, "utf8").split("\0").join(" "); } catch { continue; }
    if (!cmd.includes(`--user-data-dir=${perfil}`)) continue;
    procesos++;
    if (cmd.includes("--remote-debugging-pipe")) tuberia = true;
    if (/--remote-debugging-port=\d+/.test(cmd)) puerto = true;
  }
  return { procesos, tuberia, puerto };
}
