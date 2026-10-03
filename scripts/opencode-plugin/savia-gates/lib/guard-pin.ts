// guard-pin.ts — guards fijados por quien arranca (T1, SE-077)
//
// En modo mediado el motor crea una instancia por directorio y el plugin carga el registro y
// los scripts de `ctx.directory`: el worktree del agente. El registro queda en memoria, pero los
// scripts se ejecutan desde disco en cada llamada, así que un guard editado por el agente vale
// en la siguiente. Con SAVIA_GATES_PIN=1 el plugin fija un hash por fichero la primera vez que
// carga un directorio y lo verifica antes de cada decisión; cualquier cambio bloquea.
//
// Conjunto de guards: el registro; cada fichero que nombra un comando dentro del proyecto
// (también si aún no existe); y el árbol del directorio de cada script (librerías con `source`),
// salvo la raíz del proyecto o árboles de más de MAX_DIR_FILES ficheros.
// No cubre lo que un hook carga fuera de esos directorios (p. ej. scripts/savia-env.sh).

import { createHash } from "node:crypto"
import { readdir, readFile, realpath, stat } from "node:fs/promises"
import { realpathSync, statSync } from "node:fs"
import { dirname, isAbsolute, join, normalize, resolve, sep } from "node:path"
import type { HookMap } from "./shell-bridge"

export const MAX_DIR_FILES = 1000
const SKIP_DIRS = new Set([".git", "node_modules", "target"])

export interface GuardPin {
  /** Ruta canónica → sha256 (null: no existía al fijar). */
  files: Map<string, string | null>
  /** Directorio canónico → ficheros que contenía al fijar (ordenados). */
  dirs: Map<string, string[]>
}

async function sha(path: string): Promise<string | null> {
  try {
    return createHash("sha256").update(await readFile(path)).digest("hex")
  } catch {
    return null // ausente o ilegible: se compara como «no existe»
  }
}

/** Ruta canónica aunque no exista: canonicaliza el antepasado existente más largo. */
function canonical(path: string): string {
  let cur = normalize(path)
  const tail: string[] = []
  for (;;) {
    try {
      return join(realpathSync(cur), ...tail.reverse())
    } catch {
      const parent = dirname(cur)
      if (parent === cur) return normalize(path)
      tail.push(cur.slice(parent.length).replace(/^[/\\]/, ""))
      cur = parent
    }
  }
}

/** Ficheros bajo `dir`; null si pasa de MAX_DIR_FILES. */
async function walk(dir: string): Promise<string[] | null> {
  const out: string[] = []
  const stack = [dir]
  while (stack.length) {
    const d = stack.pop() as string
    let entries: import("node:fs").Dirent[] = []
    try {
      entries = await readdir(d, { withFileTypes: true })
    } catch {
      continue // directorio desaparecido: su ausencia se ve en la comparación de listados
    }
    for (const e of entries) {
      const p = join(d, e.name)
      const isDir = e.isDirectory() || (e.isSymbolicLink() && (await stat(p).then((s) => s.isDirectory(), () => false)))
      if (isDir) {
        if (!SKIP_DIRS.has(e.name)) stack.push(p)
        continue
      }
      out.push(await realpath(p).catch(() => p))
      if (out.length > MAX_DIR_FILES) return null
    }
  }
  return out.sort()
}

/** Rutas dentro del proyecto que nombra un comando (ya con $CLAUDE_PROJECT_DIR sustituido). */
function referenced(root: string, command: string): string[] {
  const canonRoot = canonical(root)
  const out: string[] = []
  for (const raw of command.split(/[\s|;&<>()`]+/)) {
    const t = raw.replace(/["']/g, "")
    if (!t || t.startsWith("-")) continue
    const named = isAbsolute(t) && t.startsWith(root)
    const c = canonical(isAbsolute(t) ? t : resolve(root, t))
    if (c === canonRoot || !c.startsWith(canonRoot + sep)) continue
    // statSync falla si no existe: solo cuenta si el comando lo nombra con la ruta del proyecto.
    const s = statSync(c, { throwIfNoEntry: false })
    if (s?.isDirectory()) continue
    if (named || s?.isFile()) out.push(c)
  }
  return out
}

export async function capturePin(root: string, hookMap: HookMap): Promise<GuardPin> {
  const files = new Map<string, string | null>()
  const dirs = new Map<string, string[]>()
  const registry = canonical(join(root, ".claude/settings.json"))
  files.set(registry, await sha(registry))
  const canonRoot = canonical(root)
  for (const entries of Object.values(hookMap)) {
    for (const h of entries) {
      if (h.type !== "command") continue
      for (const path of referenced(root, h.command)) {
        files.set(path, await sha(path))
        const dir = dirname(path)
        if (dir === canonRoot || [...dirs.keys()].some((d) => dir === d || dir.startsWith(d + sep))) continue
        const listing = await walk(dir)
        if (!listing) continue
        for (const d of [...dirs.keys()]) if (d.startsWith(dir + sep)) dirs.delete(d)
        dirs.set(dir, listing)
      }
    }
  }
  for (const listing of dirs.values()) {
    for (const f of listing) if (!files.has(f)) files.set(f, await sha(f))
  }
  return { files, dirs }
}

/** Rutas que cambiaron, aparecieron o desaparecieron desde que se fijó el pin. */
export async function verifyPin(pin: GuardPin): Promise<string[]> {
  const changed = new Set<string>()
  for (const [path, digest] of pin.files) if ((await sha(path)) !== digest) changed.add(path)
  for (const [dir, before] of pin.dirs) {
    const now = (await walk(dir)) ?? []
    const a = new Set(before)
    const b = new Set(now)
    for (const f of now) if (!a.has(f)) changed.add(f)
    for (const f of before) if (!b.has(f)) changed.add(f)
  }
  return [...changed].sort()
}

/** ¿La ruta (relativa al proyecto o absoluta) es un guard o cae en un directorio de guards? */
export function protectsPath(pin: GuardPin, root: string, path: string): boolean {
  if (!path.trim()) return false
  const c = canonical(isAbsolute(path) ? path : resolve(root, path))
  if (pin.files.has(c)) return true
  for (const d of pin.dirs.keys()) if (c === d || c.startsWith(d + sep)) return true
  return false
}

/** Ficheros que toca un parche de `apply_patch` (Add/Update/Delete File y Move to). */
export function patchPaths(text: string): string[] {
  const out: string[] = []
  for (const m of text.matchAll(/^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$/gm)) out.push(m[1].trim())
  return out
}

// Un pin por directorio y por proceso del motor: una instancia recargada (dispose) no re-fija
// desde un workspace ya modificado.
const PINS = new Map<string, Promise<GuardPin>>()

export function pinFor(root: string, hookMap: HookMap): Promise<GuardPin> {
  const key = canonical(root)
  let pin = PINS.get(key)
  if (!pin) {
    pin = capturePin(root, hookMap)
    PINS.set(key, pin)
  }
  return pin
}
