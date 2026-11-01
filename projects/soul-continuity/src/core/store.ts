/**
 * Almacén de estado de Soul Continuidad (SE-490).
 *
 * - Directorio de datos del usuario del sistema; `SOUL_DATA_DIR` lo sustituye (tests, portable).
 * - Escritura atómica: fichero temporal en el mismo directorio, fsync y rename.
 * - Un subdirectorio por operador (hash de su referencia): cada operador solo ve su libro y su caché.
 * - Sin módulos nativos. Se usa JSON atómico y JSONL en todas las plataformas: `node:sqlite`
 *   sigue experimental en Node 22 y no aporta nada a estos volúmenes (decenas de KB).
 * - Nunca se escriben cuerpos de mensajes ni tokens: lo garantiza quien llama y lo mide el banco.
 */

import { createHash, randomBytes } from "node:crypto";
import {
  closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, rmSync, rmdirSync, statSync,
  writeSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export interface PathEnv {
  platform: NodeJS.Platform;
  env: Record<string, string | undefined>;
  home: string;
}

const APP = "soul-continuity";

export function hostPathEnv(): PathEnv {
  return { platform: process.platform, env: process.env, home: homedir() };
}

/** Directorio de datos del usuario según el sistema. No requiere privilegios. */
export function dataDir(p: PathEnv = hostPathEnv()): string {
  if (p.env.SOUL_DATA_DIR) return p.env.SOUL_DATA_DIR;
  if (p.platform === "win32") return join(p.env.LOCALAPPDATA || join(p.home, "AppData", "Local"), "Savia", APP);
  if (p.platform === "darwin") return join(p.home, "Library", "Application Support", "Savia", APP);
  return join(p.env.XDG_DATA_HOME || join(p.home, ".local", "share"), "savia", APP);
}

export function ensureDir(dir: string): string {
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  return dir;
}

/** Escritura atómica: o queda el fichero anterior entero o el nuevo entero. */
export function writeAtomic(path: string, data: string): void {
  ensureDir(dirname(path));
  const tmp = `${path}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`;
  const fd = openSync(tmp, "w", 0o600);
  try {
    writeSync(fd, data);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  renameSync(tmp, path);
}

export function writeJson(path: string, value: unknown): void {
  writeAtomic(path, JSON.stringify(value, null, 1) + "\n");
}

/** JSON o `fallback` si no existe. Un fichero corrupto lanza: no se adivina estado. */
export function readJson<T>(path: string, fallback: T): T {
  if (!existsSync(path)) return fallback;
  return JSON.parse(readFileSync(path, "utf8")) as T;
}

export function appendJsonl(path: string, row: unknown): void {
  ensureDir(dirname(path));
  // Si la última escritura quedó cortada (sin salto final), la fila nueva empieza en línea propia.
  const torn = existsSync(path) && statSync(path).size > 0 && !readFileSync(path, "utf8").endsWith("\n");
  const fd = openSync(path, "a", 0o600);
  try {
    writeSync(fd, (torn ? "\n" : "") + JSON.stringify(row) + "\n");
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}

/** Filas JSONL; una línea corrupta (corte a mitad de escritura) se descarta. */
export function readJsonl(path: string): unknown[] {
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf8").split("\n").filter(Boolean).map((l) => {
    try { return JSON.parse(l); } catch { return null; }
  });
}

export function operatorDirName(ref: string): string {
  return "op-" + createHash("sha256").update(ref).digest("hex").slice(0, 16);
}

export function operatorDir(stateDir: string, ref: string): string {
  return ensureDir(join(stateDir, operatorDirName(ref)));
}

/** Todos los ficheros bajo `dir` (para exportar y para comprobar que no queda nada). */
export function filesUnder(dir: string): string[] {
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) out.push(...filesUnder(p));
    else out.push(p);
  }
  return out;
}

/** Lo que Soul crea en su directorio de datos. Nada más se borra al desinstalar. */
const OWN = /^(config\.json|STOP|failsafe\.jsonl|audit\.jsonl|devices\.json|pairing\.json|credentials-index\.json|autostart-task\.xml|tls|web|op-[0-9a-f]{16}|.+\.\d+\.[0-9a-f]{8}\.tmp)$/;

/**
 * Borra solo el estado de Soul en `dir` y, si queda vacío, el directorio. Lo ajeno se conserva
 * (con `SOUL_DATA_DIR` apuntando a una carpeta compartida no se pierde nada que no sea de Soul).
 * Devuelve lo ajeno que quedó.
 */
export function removeSoulState(dir: string): string[] {
  if (!existsSync(dir)) return [];
  for (const f of readdirSync(dir)) if (OWN.test(f)) rmSync(join(dir, f), { recursive: true, force: true });
  const left = readdirSync(dir);
  if (!left.length) rmdirSync(dir);
  return left;
}
