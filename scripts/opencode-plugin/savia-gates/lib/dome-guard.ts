// dome-guard.ts — Guard de cúpulas en el motor (SE-436 S5, D30-4): regla nativa de savia-gates.
//
// Gemelo del hook de Claude Code `.claude/hooks/dome-guard.sh` (núcleo `.claude/hooks/lib/dome_guard.py`),
// ambos portados de `crates/space-orchestrator/src/dome_guard.rs` de Savia Space @ 9137d4f (ronda 5), más
// dos reglas propias: un cwd de sesión dentro de una cúpula la toca siempre y el registro no lo escribe el
// motor. Misma entrada, misma decisión y mismo motivo: tests/hooks/test-dome-guard-parity.bats. Cualquier cambio aquí va también allí.
//
// - Escritura (edit, write, patch, multiedit o un bash que escriba) dentro de una cúpula → ask.
// - Lectura de una cúpula N2+ no adjunta con proveedor de nube → ask; N3+ → deny.
// - Fuera de las cúpulas → pass. Registro ilegible → ask en todo lo que mira (falla cerrado).
//
// Principio (causa común de las variantes de las revisiones r1-r3): el guard no enumera formas peligrosas,
// enumera las seguras. Solo un lector conocido (READ_ONLY) con rutas literales se analiza con precisión;
// cualquier otra orden, con cualquier programa (también envoltorios, `sh -c`, `eval`, `$(...)`, comodines,
// llaves, `clave=valor`), alcanza una cúpula o el registro si alguna palabra cae en ellos o en un ancestro.
// Cualquier error que no sea un ENOENT real, cualquier tope que corte un análisis y cualquier herramienta
// desconocida con una ruta que los toque preguntan.
// El mismo principio aplica al directorio de trabajo (revisiones r4 y r5, rondas 7 y 8 de Space): bash se
// analiza con su directorio si se sabe dónde corre (entrada objeto con las claves del esquema de bash de los dos
// motores y `workdir` ausente o texto no vacío; en Claude Code, `cwd` del payload de texto). Si no, se analiza con
// la mejor base que se lee y con cada cúpula como directorio posible; gana el veredicto más estricto (deny > ask >
// pass) y como mínimo ask: lo desconocido nunca rebaja un deny ni da pass. Una llamada sin herramienta se evalúa
// como cada herramienta y gana la más estricta.
// Falsos positivos aceptados (preguntan sin tocar una cúpula): un programa desconocido con `.` o una variable
// (`prettier --write .`), `rm -rf $X`, `mv a ..` y un literal entre comillas de un guion `-c`/`-e` que nombra
// un ancestro de una cúpula o del registro.
//
// Límite conocido: es un guard léxico. Una ruta montada en tiempo de ejecución dentro de un guion
// (`python3 -c "open('gall'+'inero/a','w')"`, variables calculadas) no se ve. La defensa en profundidad es el
// sandbox del motor o el modo mediado de Savia Space (SE-434).

import { lstatSync, statSync, readdirSync, readFileSync, readlinkSync, realpathSync } from "node:fs"

export type DomeDecision = "pass" | "ask" | "deny"
export interface DomeVerdict {
  decision: DomeDecision
  reason: string
}
export interface DomeContext {
  cloud?: unknown
  attached?: unknown
  granted?: unknown
}
export interface DomeRequest {
  /** Raíz del workspace: de ella sale el registro por defecto. */
  root: string
  /** Directorio de la sesión: las rutas relativas de la herramienta se resuelven aquí. */
  project: string
  tool: string
  input: unknown
  /** `dome_context` de quien llama; sin él, nube y sin adjuntos. */
  context?: unknown
  /** El directorio de la llamada se conoce; si no, bash pregunta siempre. Por defecto, sí (el plugin lo sabe). */
  cwdKnown?: boolean
  env: Record<string, string | undefined>
}

export const WRITE_NOTICE =
  "Usa una propuesta: Guardar como nota. El motor no escribe en una cúpula; la propuesta la revisa la persona"
export const UNKNOWN_NOTICE =
  "la orden toca una cúpula y no es una lectura conocida; si escribe, usa una propuesta: Guardar como nota"
export const CLOUD_DENIED =
  "contenido N3 o superior no sale a la nube: esta cúpula no se lee con el motor. " +
  "Pide a la persona una tarea del carril local; el resultado lo ve ella y no vuelve a ti"
export const REGISTRY_NOTICE =
  "el registro de cúpulas no lo cambia el motor: lo cambia la persona desde Savia Space o con savia-vaults dome create"
export const PAYLOAD_NOTICE = "la llamada no se puede leer; no se sabe si toca una cúpula"
export const UNKNOWN_TOOL_NOTICE =
  "el guard no conoce esta herramienta y una de sus rutas toca una cúpula; si escribe, usa una propuesta: Guardar como nota"
/** Hooks bash de settings.json con gemelo nativo aquí: el puente no los vuelve a ejecutar. */
export const NATIVE_TWIN_HOOKS = ["dome-guard.sh"]
export const UNKNOWN_CWD_NOTICE =
  "no se sabe en qué directorio corre la orden, así que podría leer o escribir una cúpula: confirmar a mano"
export const GUARD_FAILED = "el guard falló; no se puede comprobar si la orden toca una cúpula"

const WRITERS = new Set(["cp", "mv", "rm", "touch", "tee", "sed", "dd", "install", "ln", "truncate", "chmod", "chown",
  "mkdir", "rmdir", "tar", "unzip", "rsync", "git", "python3", "python", "node", "bash", "sh", "perl", "ruby", "patch",
  "cpio", "zip", "7z", "scp", "curl", "wget", "eval", "rename", "unlink", "shred", "chgrp", "chattr", "setfacl"])
const WRITE_TOOLS = new Set(["edit", "write", "patch", "multiedit", "notebookedit", "apply_patch"])
const FILE_TOOLS = new Set(["read", "grep", "glob", "list"])
const READ_ONLY = new Set(["cat", "ls", "head", "tail", "grep", "wc", "stat", "du", "diff", "nl"])
const TRAVERSERS = new Set(["grep", "rg", "find", "tree", "du", "ls", "tar", "cp", "rsync", "zip", "cpio", "7z", "scp"])
const WRITE_PATH_KEYS = ["filePath", "file_path", "path", "notebook_path"]
// Esquema de la herramienta bash de los dos motores: OpenCode (command, workdir, timeout, description) y
// Claude Code (además run_in_background, dangerouslyDisableSandbox). Otra clave podría fijar el directorio.
const BASH_KEYS = new Set(["command", "workdir", "timeout", "description", "run_in_background", "dangerouslyDisableSandbox"])
// Profundidad con la que una búsqueda recursiva mira enlaces que entran en una cúpula.
const LINK_DEPTH = 3
// Tope de entradas por directorio al buscar enlaces; un directorio mayor cuenta como que tiene uno.
const MAX_ENTRIES = 5000
// Programas que mueven, borran o quitan permisos a lo que nombran (más `git mv/rm/clean/stash -u` y
// `find -delete/-exec`, ver `destroys`): sobre un ancestro de una cúpula o del registro, se los llevan.
const DESTROYERS = new Set(["mv", "rm", "rmdir", "unlink", "shred", "rename", "chmod", "chown", "chgrp", "chattr", "setfacl"])
// Programas que ejecutan otro programa con sus argumentos: lo que hagan no se ve, cuentan como destructivos.
const WRAPPERS = new Set(["env", "command", "builtin", "exec", "nice", "nohup", "timeout", "stdbuf", "time", "ionice",
  "setsid", "sudo", "doas", "xargs", "chronic", "unbuffer", "flock", "watch", "parallel", "strace", "ltrace", "nsenter",
  "unshare", "chroot", "fakeroot", "systemd-run", "busybox"])
// Sandboxes cuyo comando va tras `--` (las opciones de antes son monturas).
const SANDBOXES = new Set(["bwrap"])
// Intérpretes de shell cuyo `-c` es otra orden que se analiza como tal.
const SHELLS = new Set(["bash", "sh", "zsh", "dash", "ksh", "mksh"])
// Claves de una herramienta desconocida que pueden llevar una ruta.
const PATH_KEY = /path|file|dir|dest|target|source|^(src|from|to|old|new)$/i
// Profundidad máxima de órdenes anidadas (`sh -c`, `$(...)`, `eval`): más allá, no se analiza y pregunta.
const MAX_NESTING = 4
const DURATION = /^[0-9]+(\.[0-9]+)?[smhd]?$/
const GIT_VALUE_FLAGS = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace"])
const FIND_ACTIONS = new Set(["-delete", "-exec", "-execdir", "-ok", "-okdir"])
// Programas que el guard conoce: tras un envoltorio, uno que no esté aquí cuenta como que recorre lo que nombra.
// Linters y filtros habituales: no escriben salvo por redirección, así que `.` en ellos no es destructivo.
const KNOWN_PROGRAMS = new Set([...WRITERS, ...DESTROYERS, ...READ_ONLY, ...TRAVERSERS, "echo", "printf", "true", "false",
  "test", "cd", "pwd", "cargo", "npm", "make", "go", "pytest", "jq", "yq", "ruff", "eslint", "shellcheck", "sort", "uniq",
  "cut", "tr", "awk", "mypy", "tsc"])
// Intérpretes cuyo guion `-c`/`-e` se mira por las rutas literales entre comillas que nombra.
const INTERPRETERS = new Set(["python", "python3", "node", "perl", "ruby"])
const QUOTED = /'([^'\\]*)'|"([^"\\]*)"/g
const LEVELS: Record<string, number> = { N1: 1, N2: 2, "": 2, N3: 3, N4: 4, N4B: 4 }
// Espacio en blanco ASCII explícito, el mismo que el núcleo Python (los `\s` de JS y Python difieren).
const WS = " \t\n\r\x0b\x0c"
const WS_CLASS = "[ \\t\\n\\r\\x0b\\x0c"

const isStr = (v: unknown): v is string => typeof v === "string"
const levelName = (n: number) => `N${n}`

function stripWs(s: string): string {
  let a = 0
  let b = s.length
  while (a < b && WS.includes(s[a])) a++
  while (b > a && WS.includes(s[b - 1])) b--
  return s.slice(a, b)
}

export function parseLevel(s: string): number | null {
  return LEVELS[stripWs(s).toUpperCase()] ?? null
}

function toolPermission(tool: string): string {
  const t = (tool || "").toLowerCase()
  return t === "ls" ? "list" : t
}

// ── Rutas ─────────────────────────────────────────────────────────────────────

type Split = [boolean, string[]]

function splitPath(p: string): Split {
  return [p.startsWith("/"), p.split("/").filter((c) => c !== "" && c !== ".")]
}

function joinParts(absolute: boolean, parts: string[]): string {
  return (absolute ? "/" : "") + parts.join("/")
}

function join(base: string, raw: string): string {
  if (raw.startsWith("/")) return raw
  return base ? base.replace(/\/+$/, "") + "/" + raw : raw
}

function prefixOf(a: string[], b: string[]): boolean {
  return a.length >= b.length && b.every((x, i) => a[i] === x)
}

function under(path: string, root: string): boolean {
  const [pa, pp] = splitPath(path)
  const [ra, rp] = splitPath(root)
  return pa === ra && prefixOf(pp, rp)
}

function isLink(p: string): boolean {
  try {
    return p !== "" && lstatSync(p).isSymbolicLink()
  } catch {
    return false
  }
}

function realPath(p: string, depth = 40): string | null {
  if (depth === 0) return null
  const [absolute, parts] = splitPath(p)
  let curAbs = absolute
  let cur: string[] = []
  for (const c of parts) {
    if (c === "..") {
      cur.pop()
      continue
    }
    cur.push(c)
    const here = joinParts(curAbs, cur)
    if (isLink(here)) {
      let target: string
      try {
        target = readlinkSync(here, "utf-8")
      } catch {
        return null
      }
      const joined = target.startsWith("/") ? target : join(joinParts(curAbs, cur.slice(0, -1)), target)
      const resolved = realPath(joined, depth - 1)
      if (resolved === null) return null
      ;[curAbs, cur] = splitPath(resolved)
    }
  }
  return joinParts(curAbs, cur)
}

function touches(root: string, project: string, raw: string, recursive: boolean): boolean {
  let a = realPath(join(project, raw))
  let r = realPath(root)
  if (a === null || r === null) return true
  a = a.toLowerCase()
  r = r.toLowerCase()
  return under(a, r) || (recursive && under(r, a))
}

function lexical(p: string): string {
  const [absolute, parts] = splitPath(p)
  const out: string[] = []
  for (const c of parts) {
    if (c === "..") out.pop()
    else out.push(c)
  }
  return joinParts(absolute, out)
}

function canonical(p: string): string | null {
  if (!p) return null
  try {
    return realpathSync(p)
  } catch {
    return null
  }
}

function resolvePath(p: string): string {
  p = lexical(p)
  const [absolute, parts] = splitPath(p)
  for (let i = parts.length; i >= 0; i--) {
    const c = canonical(joinParts(absolute, parts.slice(0, i)))
    if (c !== null) {
      const rest = parts.slice(i)
      return rest.length === 0 ? c : c.replace(/\/+$/, "") + "/" + rest.join("/")
    }
  }
  return p
}

function fileName(p: string): string {
  const parts = splitPath(p)[1]
  return parts.length > 0 && parts[parts.length - 1] !== ".." ? parts[parts.length - 1] : ""
}

function stripPrefix(p: string, base: string): string | null {
  const [pa, pp] = splitPath(p)
  const [ba, bp] = splitPath(base)
  if (pa !== ba || !prefixOf(pp, bp)) return null
  return pp.slice(bp.length).join("/")
}

function wildcard(pattern: string, text: string): boolean {
  let pi = 0
  let ti = 0
  let mark = 0
  let star: number | null = null
  while (ti < text.length) {
    if (pi < pattern.length && (pattern[pi] === "?" || pattern[pi] === text[ti])) {
      pi++
      ti++
    } else if (pi < pattern.length && pattern[pi] === "*") {
      star = pi
      mark = ti
      pi++
    } else if (star !== null) {
      pi = star + 1
      mark++
      ti = mark
    } else {
      return false
    }
  }
  return [...pattern.slice(pi)].every((c) => c === "*")
}

function listDir(d: string): string[] {
  try {
    return readdirSync(d).sort()
  } catch {
    return []
  }
}

/** Expansión de un comodín con tope; `null` si el tope la corta (quien llama lo trata como que alcanza). */
function expandGlob(project: string, pattern: string): string[] | null {
  let cur: string[]
  let rest: string
  if (pattern.startsWith("/")) {
    cur = ["/"]
    rest = pattern.slice(1)
  } else {
    cur = [project]
    rest = pattern
  }
  let budget = 5000
  for (const seg of rest.split("/").filter((s) => s !== "" && s !== ".")) {
    const next: string[] = []
    for (const base of cur) {
      if (!seg.includes("*") && !seg.includes("?")) {
        next.push(join(base, seg))
        continue
      }
      for (const name of listDir(base)) {
        budget = Math.max(0, budget - 1)
        if ((!name.startsWith(".") || seg.startsWith(".")) && wildcard(seg, name)) next.push(join(base, name))
        if (budget === 0) return null
      }
    }
    cur = next
  }
  return cur
}

function isDir(p: string): boolean {
  try {
    return lstatSync(p).isDirectory()
  } catch {
    return false
  }
}

/** Enlaces bajo `root` cuyo destino cae en `target`; `null` si un directorio supera el tope (cuenta como que hay). */
function symlinksInto(root: string, target: string, depth: number): string[] | null {
  const out: string[] = []
  const names = listDir(root)
  if (names.length > MAX_ENTRIES) return null
  for (const name of names) {
    const p = join(root, name)
    if (isLink(p)) {
      const c = canonical(p)
      if (c !== null && under(c, target)) out.push(p)
    } else if (isDir(p) && depth > 1 && !name.startsWith(".")) {
      const inner = symlinksInto(p, target, depth - 1)
      if (inner === null) return null
      out.push(...inner)
    }
  }
  return out
}

const TOKEN_SPLIT = new RegExp(WS_CLASS + "'\"`;&|()<>=]+")
const COMPONENT_SPLIT = new RegExp(WS_CLASS + "/'\"`;&|()<>=:]+")
const LOWER_SPLIT = new RegExp(WS_CLASS + "/{},=@:]")

/** La orden menciona la cúpula: ruta, nombre como componente, enlace del workspace o comodín que la alcanza. */
function mentionsDome(root: string, project: string, command: string): boolean {
  const ws = resolvePath(project)
  const rd = resolvePath(root)
  const rel = stripPrefix(root, project) || null
  const tokens = command.split(TOKEN_SPLIT).filter((t) => t)
  const components = command.split(COMPONENT_SPLIT).filter((t) => t)
  const name = fileName(rd)
  if (command.includes(root) || command.includes(rd) || (name && components.includes(name))) return true
  if (rel !== null && command.includes(rel)) return true
  const links = symlinksInto(ws, rd, 2)
  if (links === null) return true
  for (const link of links) {
    const r = stripPrefix(link, ws)
    if (r !== null && command.includes(r)) return true
  }
  for (const t of tokens) {
    if (t.includes("*") || t.includes("?")) {
      const matches = expandGlob(project, t)
      if (matches === null || matches.some((m) => under(resolvePath(m), rd))) return true
    }
  }
  return false
}

// ── Análisis léxico de la orden (subconjunto de bash, como shell.rs) ─────────

type Part = [kind: "lit" | "var" | "sub" | "proc" | "dyn", text: string, quoted: boolean]
type Word = Part[]
interface Redir {
  kind: string
  target: Word
  body: string | null
  subs: string[]
}
export interface Cmd {
  assigns: [string, Word][]
  words: Word[]
  redirs: Redir[]
  control: boolean
}
type Tok = ["word", Word] | ["redir", Redir] | ["break"] | ["pipe"]

const MAX_LEN = 32 * 1024
const MAX_CMDS = 2000
const RESERVED = new Set(["if", "then", "else", "elif", "fi", "while", "until", "do", "done", "esac", "{", "}", "!", "function"])
const CONTROL = new Set(["for", "case", "select"])

export class ShellParseError extends Error {}

const validName = (s: string) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(s)
const isDigit = (ch: string | null) => ch !== null && ch >= "0" && ch <= "9"
const isAsciiAlpha = (ch: string) => /^[A-Za-z]$/.test(ch)
const isAsciiAlnum = (ch: string) => /^[A-Za-z0-9]$/.test(ch)

function literal(word: Word): string | null {
  let out = ""
  for (const [kind, text] of word) {
    if (kind !== "lit") return null
    out += text
  }
  return out
}

function pushLit(parts: Word, ch: string, quoted: boolean): void {
  const last = parts[parts.length - 1]
  if (last && last[0] === "lit" && last[2] === quoted) last[1] += ch
  else parts.push(["lit", ch, quoted])
}

function ensureQuoted(parts: Word): void {
  const last = parts[parts.length - 1]
  if (!(last && last[0] === "lit" && last[2])) parts.push(["lit", "", true])
}

function readBalanced(c: string, i: number, op: string, cl: string): [string, number] | null {
  const start = i
  let depth = 1
  while (i < c.length) {
    const ch = c[i]
    if (ch === "\\") {
      i++
    } else if (ch === "'") {
      i++
      while (i < c.length && c[i] !== "'") i++
    } else if (ch === '"') {
      i++
      while (i < c.length && c[i] !== '"') {
        if (c[i] === "\\") i++
        i++
      }
    } else if (ch === op) {
      depth++
    } else if (ch === cl) {
      depth--
      if (depth === 0) return [c.slice(start, i), i + 1]
    }
    i++
  }
  return null
}

function extractSubs(text: string): string[] {
  const out: string[] = []
  let i = 0
  while (i < text.length) {
    if (text[i] === "\\") {
      i += 2
      continue
    }
    if (text[i] === "$" && text[i + 1] === "(") {
      i += 2
      const r = readBalanced(text, i, "(", ")")
      if (r !== null) {
        out.push(r[0])
        i = r[1]
        continue
      }
    } else if (text[i] === "`") {
      let j = i + 1
      while (j < text.length && text[j] !== "`") j++
      if (j < text.length) {
        out.push(text.slice(i + 1, j))
        i = j
      }
    }
    i++
  }
  return out
}

interface PendingDoc {
  tok: number
  delim: string
  strip: boolean
  quoted: boolean
}

class Lexer {
  i = 0
  readonly c: string
  constructor(c: string) {
    this.c = c
  }

  peek(n = 0): string | null {
    const j = this.i + n
    return j < this.c.length ? this.c[j] : null
  }

  tokens(): Tok[] {
    const out: Tok[] = []
    const pending: PendingDoc[] = []
    let ch: string | null
    while ((ch = this.peek()) !== null) {
      if (ch === " " || ch === "\t") {
        this.i++
      } else if (ch === "\\" && this.peek(1) === "\n") {
        this.i += 2
      } else if (ch === "\n") {
        this.i++
        out.push(["break"])
        this.readHeredocs(pending, out)
      } else if (ch === "#") {
        while (this.peek() !== null && this.peek() !== "\n") this.i++
      } else if (";()".includes(ch)) {
        this.i++
        out.push(["break"])
      } else if (ch === "&") {
        if (this.peek(1) === ">") {
          this.i++
          this.redirect(out, pending, true)
        } else if (this.peek(1) === "&") {
          this.i += 2
          out.push(["break"])
        } else {
          this.i++
          out.push(["break"])
        }
      } else if (ch === "|") {
        this.i++
        if (this.peek() === "|") {
          this.i++
          out.push(["break"])
        } else if (this.peek() === "&") {
          this.i++
          out.push(["pipe"])
        } else {
          out.push(["pipe"])
        }
      } else if ((ch === "<" || ch === ">") && this.peek(1) !== "(") {
        this.redirect(out, pending, false)
      } else if (isDigit(ch) && this.digitsThenRedirect()) {
        while (isDigit(this.peek())) this.i++
        this.redirect(out, pending, false)
      } else {
        out.push(["word", this.word()])
      }
    }
    for (const p of pending) (out[p.tok] as ["redir", Redir])[1].body = ""
    return out
  }

  digitsThenRedirect(): boolean {
    let j = this.i
    while (j < this.c.length && isDigit(this.c[j])) j++
    return j < this.c.length && (this.c[j] === "<" || this.c[j] === ">") && this.c[j + 1] !== "("
  }

  redirect(out: Tok[], pending: PendingDoc[], amp: boolean): void {
    const op = this.peek() ?? ">"
    this.i++
    let kind = op === "<" ? "in" : "out"
    let heredoc: boolean | null = null
    let maybeDup = false
    const nxt = this.peek()
    if (op === "<") {
      if (nxt === "<") {
        this.i++
        if (this.peek() === "<") {
          this.i++
          kind = "herestring"
        } else {
          kind = "heredoc"
          const strip = this.peek() === "-"
          if (strip) this.i++
          heredoc = strip
        }
      } else if (nxt === "&") {
        this.i++
        maybeDup = true
      } else if (nxt === ">") {
        this.i++
      }
    } else if (nxt === ">") {
      this.i++
      kind = "append"
    } else if (nxt === "&" && !amp) {
      this.i++
      maybeDup = true
    } else if (nxt === "|") {
      this.i++
    }
    while (this.peek() === " " || this.peek() === "\t") this.i++
    const at = this.peek()
    const target: Word = at === null || "\n;&|()".includes(at) ? [] : this.word()
    if (maybeDup) {
      const t = literal(target) ?? ""
      if (t === "-" || (t !== "" && [...t].every((c) => isDigit(c)))) kind = "dup"
    }
    const redir: Redir = { kind, target, body: null, subs: [] }
    if (heredoc !== null) {
      const quoted = target.some(([k, , q]) => k === "lit" && q)
      const delim = target.filter(([k]) => k === "lit").map(([, t]) => t).join("")
      pending.push({ tok: out.length, delim, strip: heredoc, quoted })
    }
    out.push(["redir", redir])
  }

  readHeredocs(pending: PendingDoc[], out: Tok[]): void {
    for (const p of pending) {
      let body = ""
      while (this.i < this.c.length) {
        const start = this.i
        while (this.peek() !== null && this.peek() !== "\n") this.i++
        const line = this.c.slice(start, this.i)
        if (this.peek() === "\n") this.i++
        const cmp = p.strip ? line.replace(/^\t+/, "") : line
        if (cmp === p.delim) break
        body += (p.strip ? cmp : line) + "\n"
      }
      const r = (out[p.tok] as ["redir", Redir])[1]
      r.subs = p.quoted ? [] : extractSubs(body)
      r.body = body
    }
    pending.length = 0
  }

  word(): Word {
    const parts: Word = []
    const start = this.i
    let ch: string | null
    while ((ch = this.peek()) !== null) {
      if (" \t\n;&|()".includes(ch)) break
      if (ch === "<" || ch === ">") {
        if (this.peek(1) !== "(") break
        this.i += 2
        const r = readBalanced(this.c, this.i, "(", ")")
        if (r === null) throw new ShellParseError("sustitución de proceso sin cerrar")
        parts.push(["proc", r[0], false])
        this.i = r[1]
      } else if (ch === "\\") {
        this.i++
        const nxt = this.peek()
        if (nxt === null) {
          pushLit(parts, "\\", true)
        } else if (nxt === "\n") {
          this.i++
        } else {
          this.i++
          pushLit(parts, nxt, true)
        }
      } else if (ch === "'") {
        this.i++
        ensureQuoted(parts)
        for (;;) {
          const nxt = this.peek()
          if (nxt === null) throw new ShellParseError("comilla simple sin cerrar")
          this.i++
          if (nxt === "'") break
          pushLit(parts, nxt, true)
        }
      } else if (ch === '"') {
        this.i++
        this.doubleQuoted(parts)
      } else if (ch === "$") {
        this.dollar(parts, false)
      } else if (ch === "`") {
        this.backtick(parts, false)
      } else if (ch === "~" && (this.i === start || assignmentPrefix(parts))) {
        this.i++
        const nxt = this.peek()
        if (nxt === null || "/ \t\n;&|)".includes(nxt)) parts.push(["var", "HOME", false])
        else pushLit(parts, "~", false)
      } else {
        this.i++
        pushLit(parts, ch, false)
      }
    }
    return parts
  }

  doubleQuoted(parts: Word): void {
    ensureQuoted(parts)
    for (;;) {
      const ch = this.peek()
      if (ch === null) throw new ShellParseError("comilla doble sin cerrar")
      if (ch === '"') {
        this.i++
        return
      }
      if (ch === "\\") {
        this.i++
        const nxt = this.peek()
        if (nxt === null) throw new ShellParseError("comilla doble sin cerrar")
        this.i++
        if (nxt === "\n") continue
        if ("$`\"\\".includes(nxt)) {
          pushLit(parts, nxt, true)
        } else {
          pushLit(parts, "\\", true)
          pushLit(parts, nxt, true)
        }
      } else if (ch === "$") {
        this.dollar(parts, true)
      } else if (ch === "`") {
        this.backtick(parts, true)
      } else {
        this.i++
        pushLit(parts, ch, true)
      }
    }
  }

  backtick(parts: Word, quoted: boolean): void {
    this.i++
    let script = ""
    for (;;) {
      const ch = this.peek()
      if (ch === null) throw new ShellParseError("comillas invertidas sin cerrar")
      if (ch === "`") {
        this.i++
        break
      }
      const nxt = this.peek(1)
      if (ch === "\\" && nxt !== null && "`\\$".includes(nxt)) {
        script += nxt
        this.i += 2
      } else {
        script += ch
        this.i++
      }
    }
    parts.push(["sub", script, quoted])
  }

  dollar(parts: Word, quoted: boolean): void {
    const nxt = this.peek(1)
    if (nxt === "(") {
      const arithmetic = this.peek(2) === "("
      this.i += 2
      const r = readBalanced(this.c, this.i, "(", ")")
      if (r === null) throw new ShellParseError("sustitución sin cerrar")
      const inner = r[0]
      this.i = r[1]
      if (arithmetic) {
        parts.push(["dyn", "", quoted])
        for (const s of extractSubs(inner)) parts.push(["sub", s, quoted])
      } else {
        parts.push(["sub", inner, quoted])
      }
    } else if (nxt === "{") {
      this.i += 2
      const r = readBalanced(this.c, this.i, "{", "}")
      if (r === null) throw new ShellParseError("expansión ${ sin cerrar")
      const inner = r[0]
      this.i = r[1]
      if (validName(inner)) {
        parts.push(["var", inner, quoted])
      } else {
        parts.push(["dyn", "", quoted])
        for (const s of extractSubs(inner)) parts.push(["sub", s, quoted])
      }
    } else if (nxt !== null && (nxt === "_" || isAsciiAlpha(nxt))) {
      this.i++
      let name = ""
      let ch: string | null
      while ((ch = this.peek()) !== null && (ch === "_" || isAsciiAlnum(ch))) {
        name += ch
        this.i++
      }
      parts.push(["var", name, quoted])
    } else if (nxt !== null && (isDigit(nxt) || "@*#?$!-".includes(nxt))) {
      this.i += 2
      parts.push(["dyn", "", quoted])
    } else if (nxt === "'" && !quoted) {
      this.i += 2
      ensureQuoted(parts)
      this.ansiC(parts)
    } else if (nxt === '"' && !quoted) {
      this.i += 2
      this.doubleQuoted(parts)
    } else {
      this.i++
      pushLit(parts, "$", quoted)
    }
  }

  ansiC(parts: Word): void {
    const simple: Record<string, string> = { n: "\n", t: "\t", r: "\r", a: "\x07", b: "\x08", e: "\x1b", E: "\x1b", f: "\x0c", v: "\x0b" }
    const widths: Record<string, number> = { x: 2, u: 4, U: 8 }
    for (;;) {
      const ch = this.peek()
      if (ch === null) throw new ShellParseError("comilla $' sin cerrar")
      this.i++
      if (ch === "'") return
      if (ch !== "\\") {
        pushLit(parts, ch, true)
        continue
      }
      const e = this.peek()
      if (e === null) throw new ShellParseError("comilla $' sin cerrar")
      this.i++
      let out: string
      if (e in simple) {
        out = simple[e]
      } else if (e in widths) {
        out = this.numeric(16, widths[e]) ?? e
      } else if ("01234567".includes(e)) {
        this.i--
        out = this.numeric(8, 3) ?? "0"
      } else {
        out = e
      }
      pushLit(parts, out, true)
    }
  }

  numeric(radix: number, maximum: number): string | null {
    const digits = "0123456789abcdef".slice(0, radix)
    let v = 0
    let n = 0
    while (n < maximum) {
      const ch = this.peek()
      if (ch === null || !/^[\x00-\x7f]$/.test(ch) || !digits.includes(ch.toLowerCase())) break
      v = v * radix + digits.indexOf(ch.toLowerCase())
      this.i++
      n++
    }
    if (n === 0 || v > 0x10ffff || (v >= 0xd800 && v <= 0xdfff)) return null
    return String.fromCodePoint(v)
  }
}

function assignmentPrefix(parts: Word): boolean {
  return parts.length === 1 && parts[0][0] === "lit" && !parts[0][2] && parts[0][1].endsWith("=") &&
    validName(parts[0][1].slice(0, -1))
}

function splitAssignment(word: Word): [string, Word] | null {
  if (word.length === 0 || word[0][0] !== "lit" || word[0][2]) return null
  const text = word[0][1]
  const eq = text.indexOf("=")
  if (eq < 0) return null
  let name = text.slice(0, eq)
  if (name.endsWith("+")) name = name.slice(0, -1)
  if (!validName(name)) return null
  const parts: Word = eq + 1 < text.length ? [["lit", text.slice(eq + 1), false]] : []
  return [name, [...parts, ...word.slice(1)]]
}

const newCmd = (): Cmd => ({ assigns: [], words: [], redirs: [], control: false })

export function parseShell(src: string): Cmd[] {
  if (Buffer.byteLength(src, "utf8") > MAX_LEN) {
    throw new ShellParseError("orden demasiado larga")
  }
  const cmds: Cmd[] = []
  let cur = newCmd()
  let started = false
  for (const tok of new Lexer(src).tokens()) {
    if (tok[0] === "word") {
      const w = tok[1]
      const unq = w.length === 1 && w[0][0] === "lit" && !w[0][2] ? w[0][1] : null
      if (cur.control) {
        cur.words.push(w)
      } else if (cur.words.length === 0) {
        if (cur.assigns.length === 0 && unq !== null && RESERVED.has(unq)) continue
        if (cur.assigns.length === 0 && unq !== null && CONTROL.has(unq)) {
          cur.control = started = true
          continue
        }
        const a = splitAssignment(w)
        if (a !== null) cur.assigns.push(a)
        else cur.words.push(w)
      } else {
        cur.words.push(w)
      }
      started = true
    } else if (tok[0] === "redir") {
      cur.redirs.push(tok[1])
      started = true
    } else if (started) {
      cmds.push(cur)
      cur = newCmd()
      started = false
      if (cmds.length > MAX_CMDS) throw new ShellParseError("demasiados comandos")
    }
  }
  if (started) cmds.push(cur)
  return cmds
}

// ── Decisión ──────────────────────────────────────────────────────────────────

interface Dome {
  id: string
  root: string
  level: number
}
type Registry = { domes: Dome[]; files: string[] } | { error: string }
interface Ctx {
  cloud: boolean
  attached: string[]
  granted: string[]
}

function wordText(word: Word): string {
  return word.map(([kind, text]) => (kind === "lit" || kind === "sub" || kind === "proc" ? text : kind === "var" ? "$" + text : "$")).join("")
}

function unquoted(script: Cmd[]): string {
  return script.map((c) => [...c.words.map(wordText), ...c.redirs.map((r) => wordText(r.target))].join(" ")).join(" ; ")
}

const litOrDollar = (w: Word) => literal(w) ?? "$"
const baseName = (prog: string) => prog.slice(prog.lastIndexOf("/") + 1)
const outputs = (c: Cmd) => c.redirs.some((r) => (r.kind === "out" || r.kind === "append") && literal(r.target) !== "/dev/null")

function writes(script: Cmd[]): boolean {
  return script.some((c) => {
    const prog = c.words.length > 0 ? literal(c.words[0]) : null
    const dynamic = c.words.some((w) => literal(w) === null)
    return outputs(c) || dynamic || prog === null || WRITERS.has(baseName(prog)) || WRAPPERS.has(baseName(prog))
  })
}

export function bashReadsOnly(script: Cmd[]): boolean {
  if (script.length === 0) return false
  return script.every((c) => {
    const isLiteral = c.words.every((w) => literal(w) !== null)
    const prog = (c.words.length > 0 ? literal(c.words[0]) : null) || ""
    return !c.control && c.assigns.length === 0 && isLiteral && !outputs(c) && READ_ONLY.has(baseName(prog))
  })
}

function isRecursive(prog: string, flags: string[]): boolean {
  const short = (ch: string) => flags.some((f) => !f.startsWith("--") && f.includes(ch))
  if (["rg", "find", "tree", "du", "tar", "rsync", "cpio", "7z"].includes(prog)) return true
  if (prog === "grep") return short("r") || short("R") || flags.some((f) => f.startsWith("--recursive"))
  if (prog === "zip" || prog === "scp") return short("r") || short("R")
  if (prog === "ls") return short("R")
  if (prog === "cp") {
    return short("R") || short("r") || short("a") || flags.some((f) => f === "--archive" || f.startsWith("--recursive"))
  }
  return false
}

/**
 * El programa que ejecuta un envoltorio (`timeout 5 grep`, `env LANG=C cat`, `nice -n 5 mv`): se quitan el
 * envoltorio, sus opciones, asignaciones y duraciones. Lo que quede puede no ser un programa (el valor de una
 * opción con argumento): entonces cuenta como desconocido.
 */
function unwrap(words: string[]): string[] {
  while (words.length > 0 && WRAPPERS.has(baseName(words[0]))) {
    words = words.slice(1)
    while (words.length > 0 && (words[0].startsWith("-") || words[0].includes("=") || DURATION.test(words[0]))) words = words.slice(1)
  }
  return words
}

function traversalReaches(script: Cmd[], project: string, root: string): boolean {
  for (const c of script) {
    const words = unwrap(c.words.map(litOrDollar))
    if (words.length === 0) continue
    const prog = baseName(words[0])
    // Un programa que no se conoce (o que queda tras un envoltorio que no se sabe leer) recorre lo que nombre
    // cualquiera de sus palabras; uno conocido que no recorre, no.
    const wrapped = !KNOWN_PROGRAMS.has(prog)
    if (!wrapped && !TRAVERSERS.has(prog)) continue
    if (!wrapped && !isRecursive(prog, words.slice(1).filter((w) => w.startsWith("-") && [...w].length > 1))) continue
    const args = words.slice(1).filter((w) => !w.startsWith("-"))
    if ((prog === "grep" || prog === "rg") && args.length > 0) args.shift()
    if (wrapped) {
      // `.`, `..` o `/` como argumento de un desconocido (las monturas de un sandbox) no cuentan: si no, toda
      // orden envuelta por bwrap «recorrería» el disco entero.
      if (args.some((a) => a !== "$" && touches(root, project, a, true) && !containsBase(project, a))) return true
      continue
    }
    if (args.length === 0) {
      if (touches(root, project, ".", true)) return true
    } else if (args.some((a) => a === "$" || touches(root, project, a, true))) {
      return true
    }
  }
  return false
}

function readVerdict(ctx: Ctx, touched: Dome[]): DomeVerdict {
  if (!ctx.cloud) return { decision: "pass", reason: "" }
  for (const d of touched) {
    if (d.level >= 3) return { decision: "deny", reason: `la cúpula «${d.id}» es ${levelName(d.level)}: ${CLOUD_DENIED}` }
  }
  for (const d of touched) {
    if (d.level >= 2 && !ctx.attached.includes(d.id) && !ctx.granted.includes(d.id)) {
      return {
        decision: "ask",
        reason: `la cúpula «${d.id}» es ${levelName(d.level)} y no está adjunta: su contenido saldría al proveedor de nube`,
      }
    }
  }
  return { decision: "pass", reason: "" }
}

/**
 * Directorio de trabajo efectivo de una orden de bash y si difiere del proyecto (ronda 7 de dome_guard.rs).
 * `null` = no se sabe dónde corre: la llamada no es un objeto, lleva una clave fuera del esquema de bash de los
 * dos motores (podría fijar el directorio) o un `workdir` que no es texto.
 */
function effectiveCwd(project: string, input: unknown): [string, boolean] | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null
  const obj = input as Record<string, unknown>
  if (Object.keys(obj).some((k) => !BASH_KEYS.has(k))) return null
  const v = obj.workdir
  if (v === undefined || v === null) return [project, false]
  if (!isStr(v) || !v) return null
  const base = join(project, v)
  return [base, realPath(base) !== realPath(project)]
}

/** Subcomando de git y sus argumentos, saltando las opciones globales (`git -C dir rm`). */
function gitSubcommand(words: string[]): [string, string[]] {
  let rest = words.slice(1)
  while (rest.length > 0 && rest[0].startsWith("-")) rest = rest.slice(GIT_VALUE_FLAGS.has(rest[0]) ? 2 : 1)
  return rest.length > 0 ? [rest[0], rest.slice(1)] : ["", []]
}

/** `git clean` (sin -n) y `git stash -u/--all` borran lo no versionado del árbol, registro local incluido. */
function wipesTree(c: Cmd): boolean {
  const words = c.words.map(litOrDollar)
  if (words.length === 0 || baseName(words[0]) !== "git") return false
  const [sub, args] = gitSubcommand(words)
  if (sub === "clean") {
    return !args.some((a) => a === "-n" || a === "--dry-run" || (a.startsWith("-") && !a.startsWith("--") && a.includes("n")))
  }
  return sub === "stash" && args.some((a) => ["-u", "-a", "--all", "--include-untracked"].includes(a))
}

/** El comando mueve, borra o cambia permisos de lo que nombra, o ejecuta otro programa que podría hacerlo. */
function destroys(c: Cmd): boolean {
  const words = c.words.map(litOrDollar)
  if (words.length === 0) return false
  const prog = baseName(words[0])
  if (DESTROYERS.has(prog) || WRAPPERS.has(prog) || !KNOWN_PROGRAMS.has(prog)) return true
  if (prog === "git") return ["rm", "mv"].includes(gitSubcommand(words)[0]) || wipesTree(c)
  return prog === "find" && words.slice(1).some((w) => FIND_ACTIONS.has(w))
}

/**
 * Los comandos de la orden más los de sus órdenes anidadas: `$(...)`, `<(...)`, here-documents sin comillas,
 * el `-c` de un shell y `eval`. Una anidada que no se puede analizar es un ShellParseError.
 */
function flatten(script: Cmd[], depth = 0): Cmd[] {
  if (depth > MAX_NESTING) throw new ShellParseError("demasiado anidada")
  const out: Cmd[] = []
  for (const c of script) {
    const allWords = c.words.map(litOrDollar)
    if (allWords.length > 0 && SANDBOXES.has(baseName(allWords[0])) && allWords.includes("--")) {
      // Las opciones de un sandbox son monturas, no rutas que toque: cuenta lo que ejecuta tras `--`.
      const i = allWords.indexOf("--")
      out.push(...flatten([{ assigns: [], words: c.words.slice(i + 1), redirs: c.redirs, control: false }], depth + 1))
      continue
    }
    out.push(c)
    const inner: string[] = []
    for (const w of [...c.words, ...c.redirs.map((r) => r.target), ...c.assigns.map((a) => a[1])]) {
      for (const [kind, text] of w) if (kind === "sub" || kind === "proc") inner.push(text)
    }
    for (const r of c.redirs) inner.push(...r.subs)
    const words = unwrap(allWords)
    const prog = words.length > 0 ? baseName(words[0]) : ""
    if (SHELLS.has(prog)) {
      for (let i = 1; i < words.length - 1; i++) {
        const w = words[i]
        if (w.startsWith("-") && !w.startsWith("--") && w.includes("c")) {
          inner.push(words[i + 1])
          break
        }
      }
    }
    if (prog === "eval") inner.push(words.slice(1).join(" "))
    for (const text of inner) out.push(...flatten(parseShell(text), depth + 1))
  }
  return out
}

/** Un nivel de llaves con comas (`{vaults,src}`), como haría el shell. */
function expandBraces(word: string): string[] {
  const m = /\{([^{}]*,[^{}]*)\}/.exec(word)
  if (!m) return [word]
  return m[1].split(",").map((alt) => word.slice(0, m.index) + alt + word.slice(m.index + m[0].length))
}

/** Rutas que puede nombrar una palabra: ella, lo que va tras `=` o `@`, y sus llaves expandidas. */
function candidates(word: string): string[] {
  const out = [word]
  if (word.includes("=")) out.push(word.slice(word.indexOf("=") + 1))
  if (word.includes("@")) out.push(word.slice(word.indexOf("@") + 1))
  return out.flatMap(expandBraces).filter((x) => x && !x.startsWith("-"))
}

/** La palabra es el directorio de trabajo o un ancestro suyo (`.`, `..`, `/`). */
function containsBase(base: string, cand: string): boolean {
  const a = realPath(join(base, cand))
  const b = realPath(base)
  return a === null || b === null || under(b.toLowerCase(), a.toLowerCase())
}

/** Componentes (en minúsculas) de la ruta de la cúpula desde el directorio de trabajo. */
function chainOf(target: string, base: string): string[] {
  const rt = resolvePath(target)
  const rel = stripPrefix(rt, resolvePath(base))
  return (rel ? rel.split("/") : splitPath(rt)[1]).filter((c) => c).map((c) => c.toLowerCase())
}

/** Alguna parte de la orden cambia de directorio, así que las rutas relativas no se resuelven bien. */
function changesDir(cmds: Cmd[]): boolean {
  return cmds.some((c) => c.words.map(litOrDollar).some((w) =>
    w === "cd" || w === "pushd" || w === "popd" || w === "-C" || w.startsWith("--chdir") || w.startsWith("--directory")))
}

/** Literales entre comillas del guion `-c`/`-e` de un intérprete (tras un envoltorio, también). */
function scriptLiterals(c: Cmd): string[] {
  const words = unwrap(c.words.map(litOrDollar))
  if (words.length === 0 || !INTERPRETERS.has(baseName(words[0]))) return []
  for (let i = 1; i < words.length - 1; i++) {
    const w = words[i]
    if (w === "-c" || w === "-e" || w === "-E" || (w.startsWith("-") && !w.startsWith("--") && "ce".includes(w[w.length - 1]))) {
      return [...words[i + 1].matchAll(QUOTED)].map((m) => m[1] || m[2]).filter((q) => q)
    }
  }
  return []
}

/**
 * Un comando que no es de solo lectura alcanza la cúpula (o el registro) o un ancestro suyo con cualquiera de
 * sus palabras. Falla cerrado: no depende de qué programa sea, salvo para aflojar `.`/`..` en los que no
 * destruyen (`git add .`). Una palabra dinámica o un comodín en uno que destruye, pregunta.
 */
function writesReach(cmds: Cmd[], base: string, target: string): boolean {
  const moved = changesDir(cmds)
  const chain = moved ? chainOf(target, base) : []
  const pipedAny = cmds.some((c) => c.words.length > 0 && baseName(litOrDollar(c.words[0])) === "xargs")
  for (const c of cmds) {
    const first = c.words.length > 0 ? litOrDollar(c.words[0]) : ""
    if (bashReadsOnly([c]) || first === "cd" || first === "pushd" || first === "popd") continue
    const destructive = destroys(c) || pipedAny
    if (wipesTree(c) && touches(target, base, ".", true)) return true
    // El guion de un intérprete (`python3 -c "shutil.move('vaults', x)"`): sus literales entre comillas cuentan
    // como palabras del comando (con la regla de los que no destruyen: `.` no cuenta).
    const words = [...c.words.slice(1), ...c.redirs.filter((r) => r.kind === "out" || r.kind === "append").map((r) => r.target),
      ...c.assigns.map((a) => a[1]), ...scriptLiterals(c).map((q): Word => [["lit", q, true]])]
    for (const w of words) {
      const lit = literal(w)
      if (lit === null) {
        if (destructive) return true
        continue
      }
      for (const cand of candidates(lit)) {
        if ([..."*?["].some((ch) => cand.includes(ch))) {
          const matches = expandGlob(base, cand)
          if (matches === null || matches.some((m) => touches(target, base, m, true))) return true
          continue
        }
        if (touches(target, base, cand, true) && (destructive || !containsBase(base, cand))) return true
        if (moved && chain.includes(fileName(cand).toLowerCase())) return true
      }
    }
  }
  return false
}

/** La mejor base que se lee aunque el directorio no se conozca: el `workdir` si es texto, o el proyecto. */
function bestBase(project: string, input: Record<string, unknown>): string {
  const v = input.workdir
  return isStr(v) && v ? join(project, v) : project
}

function decideBash(domes: Dome[], files: string[], project: string, ctx: Ctx, rawInput: unknown, cwdKnown = true): DomeVerdict {
  // El directorio de trabajo decide contra qué se resuelven las rutas de la orden.
  const cwd = cwdKnown ? effectiveCwd(project, rawInput) : null
  if (cwd !== null) return analyseBash(domes, files, project, ctx, rawInput as Record<string, unknown>, cwd[0], cwd[1])
  // Sin saber dónde corre no se sabe qué lee ni qué escribe (ronda 8 de dome_guard.rs). Se hace el análisis
  // normal con la mejor base que se lee (el `workdir` o el proyecto) y con cada cúpula como directorio de
  // trabajo posible, siempre desplazado; gana el veredicto más estricto (deny > ask > pass) y como mínimo ask.
  // Lo desconocido nunca rebaja ni da pass. En un empate a ask vale el motivo del primer análisis que pregunta.
  const input = rawInput && typeof rawInput === "object" && !Array.isArray(rawInput) ? (rawInput as Record<string, unknown>) : {}
  let verdict: DomeVerdict = { decision: "ask", reason: UNKNOWN_CWD_NOTICE }
  for (const base of [bestBase(project, input), ...domes.map((d) => d.root)]) {
    const v = analyseBash(domes, files, project, ctx, input, base, true)
    if (v.decision === "deny") return v
    if (v.decision === "ask" && verdict.reason === UNKNOWN_CWD_NOTICE) verdict = v
  }
  return verdict
}

/** Análisis de la orden con `base` como directorio de trabajo (`shifted`: distinto del proyecto). */
function analyseBash(domes: Dome[], files: string[], project: string, ctx: Ctx, input: Record<string, unknown>, base: string,
  shifted: boolean): DomeVerdict {
  if (input.command !== undefined && input.command !== null && !isStr(input.command)) return { decision: "ask", reason: PAYLOAD_NOTICE }
  const command = isStr(input.command) ? input.command : ""
  let script: Cmd[]
  try {
    script = parseShell(command)
  } catch (e) {
    if (e instanceof ShellParseError) return { decision: "ask", reason: `la orden de shell no se puede analizar: ${WRITE_NOTICE}` }
    throw e
  }
  let cmds: Cmd[]
  try {
    cmds = flatten(script)
  } catch (e) {
    if (e instanceof ShellParseError) return { decision: "ask", reason: `la orden de shell no se puede analizar: ${WRITE_NOTICE}` }
    throw e
  }
  const plain = unquoted(script)
  const lowerTokens = plain.toLowerCase().split(LOWER_SPLIT)
  const words = script.flatMap((c) => [...c.words, ...c.redirs.map((r) => r.target)]).map(litOrDollar)
  const pathlike = words.filter((w) => w.includes("/") && ![..."*?$"].some((ch) => w.includes(ch)))
  const readsOnly = bashReadsOnly(script)
  // Solo un lector conocido con rutas literales y limpias puede aflojar el nombre (ronda 4 de dome_guard.rs).
  const nameOnlyOk = shifted || pathlike.length === 0 || !readsOnly ||
    words.some((w) => [..."*?=@{}" + WS].some((ch) => w.includes(ch)))
  const direct = (d: { root: string }) => {
    const name = fileName(d.root).toLowerCase()
    const named = (name !== "" && lowerTokens.includes(name)) || [command, plain].some((c) => mentionsDome(d.root, project, c))
    // Una ruta que cae en la cúpula la nombra, y un directorio de trabajo dentro de ella (el efectivo o el de
    // la sesión) hace que toda orden la toque.
    const byPath = pathlike.some((w) => touches(d.root, base, w, false)) || touches(d.root, base, ".", false)
    // Mover o borrar un ancestro se lleva la cúpula o el registro (y con él, todo el guard).
    return (named && nameOnlyOk) || byPath || (!readsOnly && writesReach(cmds, base, d.root))
  }
  const directHit = domes.filter(direct)
  if (directHit.length > 0 && !readsOnly) {
    // Una orden que además recorre una N3 hacia la nube se deniega: la pregunta de escritura no la afloja.
    const reached = domes.filter((d) => traversalReaches(cmds, base, d.root))
    if (reached.length > 0 && readVerdict(ctx, reached).decision === "deny") return readVerdict(ctx, reached)
    return { decision: "ask", reason: writes(cmds) ? WRITE_NOTICE : UNKNOWN_NOTICE }
  }
  if (!readsOnly && files.some((f) => direct({ root: f }))) return { decision: "ask", reason: REGISTRY_NOTICE }
  const touched = [...directHit]
  for (const d of domes) {
    if (!touched.some((t) => t.id === d.id) && traversalReaches(cmds, base, d.root)) touched.push(d)
  }
  if (touched.length === 0) return { decision: "pass", reason: "" }
  return readVerdict(ctx, touched)
}

export function patchPathsOf(text: string): string[] {
  return [...text.matchAll(/^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$/gm)].map((m) => m[1].trim())
}

function searchRoot(project: string, permission: string, input: Record<string, unknown>): string | null {
  const keys = permission === "read" ? ["filePath", "file_path"] : ["path"]
  for (const k of keys) {
    const v = input[k]
    if (isStr(v) && v) return v
  }
  if (permission === "read") return null
  const pattern = input.pattern
  if (permission === "glob" && isStr(pattern) && !pattern.startsWith("/")) {
    const segs: string[] = []
    for (const s of pattern.split("/")) {
      if (!s || [..."*?[{"].some((ch) => s.includes(ch))) break
      segs.push(s)
    }
    if (segs.length > 0) return join(project, segs.join("/"))
  }
  return project
}

/** Una búsqueda recursiva desde `root` entra en la cúpula por un enlace que hay debajo. */
function reachesByLink(project: string, root: string, domeRoot: string): boolean {
  const links = symlinksInto(resolvePath(join(project, root)), resolvePath(domeRoot), LINK_DEPTH)
  return links === null || links.length > 0
}

/** Cadenas bajo claves de ruta, también anidadas en objetos y listas (hasta 8 niveles). */
function pathValues(value: unknown, depth = 0): string[] {
  const out: string[] = []
  if (depth > 8) return out
  if (Array.isArray(value)) {
    for (const v of value) out.push(...pathValues(v, depth + 1))
  } else if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      if (isStr(v) && v && PATH_KEY.test(k)) out.push(v)
      else if (v && typeof v === "object") out.push(...pathValues(v, depth + 1))
    }
  }
  return out
}

/**
 * Herramienta que el guard no conoce (MCP, otras de edición): si alguna clave de ruta toca una cúpula, el
 * registro o un ancestro suyo, pregunta. Sin claves de ruta no decide nada.
 */
function decideUnknown(registry: Registry, project: string, input: Record<string, unknown>): DomeVerdict {
  const paths = pathValues(input)
  if (paths.length === 0) return { decision: "pass", reason: "" }
  if ("error" in registry) return { decision: "ask", reason: `registro de cúpulas ilegible (${registry.error}): ${WRITE_NOTICE}` }
  if (registry.domes.length === 0) return { decision: "pass", reason: "" }
  if (paths.some((p) => registry.domes.some((d) => touches(d.root, project, p, true)))) return { decision: "ask", reason: UNKNOWN_TOOL_NOTICE }
  if (paths.some((p) => registry.files.some((f) => touches(f, project, p, true)))) return { decision: "ask", reason: REGISTRY_NOTICE }
  return { decision: "pass", reason: "" }
}

/** `cwdKnown`: el directorio de la llamada se conoce (en Claude Code, el `cwd` del payload es texto). */
// Una llamada sin herramienta se evalúa como cada una de ellas y gana la más estricta: quitar la herramienta
// nunca da un veredicto menos estricto (monotonía). La desconocida va primero: su motivo es el que vale.
const ANY_TOOL = ["", "edit", "bash", "read", "grep", "glob", "list"]

function decide(registry: Registry, project: string, tool: string, rawInput: unknown, ctx: Ctx, cwdKnown = true): DomeVerdict {
  if (!tool) return strictest(ANY_TOOL.map((t) => decideTool(registry, project, t, rawInput, ctx, cwdKnown)))
  return decideTool(registry, project, tool, rawInput, ctx, cwdKnown)
}

function decideTool(registry: Registry, project: string, tool: string, rawInput: unknown, ctx: Ctx, cwdKnown: boolean): DomeVerdict {
  const input = rawInput && typeof rawInput === "object" && !Array.isArray(rawInput) ? (rawInput as Record<string, unknown>) : {}
  const permission = toolPermission(tool)
  if (!(permission === "bash" || FILE_TOOLS.has(permission) || WRITE_TOOLS.has(permission))) return decideUnknown(registry, project, input)
  if ("error" in registry) return { decision: "ask", reason: `registro de cúpulas ilegible (${registry.error}): ${WRITE_NOTICE}` }
  const { domes, files } = registry
  if (domes.length === 0) return { decision: "pass", reason: "" }
  if (WRITE_TOOLS.has(permission)) {
    const paths = WRITE_PATH_KEYS.map((k) => input[k]).filter(isStr)
    for (const k of ["patchText", "patch"]) {
      const v = input[k]
      if (isStr(v)) paths.push(...patchPathsOf(v))
    }
    if (paths.length === 0) return { decision: "ask", reason: `no se sabe qué ruta escribe el motor: ${WRITE_NOTICE}` }
    if (paths.some((p) => domes.some((d) => touches(d.root, project, p, false)))) return { decision: "ask", reason: WRITE_NOTICE }
    if (paths.some((p) => files.some((f) => touches(f, project, p, false)))) return { decision: "ask", reason: REGISTRY_NOTICE }
    return { decision: "pass", reason: "" }
  }
  if (permission === "bash") return decideBash(domes, files, project, ctx, rawInput, cwdKnown)
  const root = searchRoot(project, permission, input)
  if (root === null) return readVerdict(ctx, domes)
  const recursive = permission !== "read"
  const touched = domes.filter((d) => touches(d.root, project, root, recursive) || (recursive && reachesByLink(project, root, d.root)))
  return readVerdict(ctx, touched)
}

// ── Registro y contexto ──────────────────────────────────────────────────────

/** posixpath.split + splitext, para que el fichero local sea el mismo que calcula el núcleo Python. */
export function localRegistryPath(base: string): string {
  const i = base.lastIndexOf("/") + 1
  let head = base.slice(0, i)
  const name = base.slice(i)
  if (head && head !== "/".repeat(head.length)) head = head.replace(/\/+$/, "")
  const dot = name.lastIndexOf(".")
  let stem = name
  let ext = ""
  if (dot > 0 && [...name.slice(0, dot)].some((c) => c !== ".")) {
    stem = name.slice(0, dot)
    ext = name.slice(dot)
  }
  const file = `${stem}.local${ext}`
  return !head ? file : head.endsWith("/") ? head + file : `${head}/${file}`
}

const baseRegistryPath = (file: string) => (file.endsWith(".local.json") ? file.slice(0, -".local.json".length) + ".json" : file)

function dirName(p: string): string {
  const i = p.lastIndexOf("/") + 1
  let head = p.slice(0, i)
  if (head && head !== "/".repeat(head.length)) head = head.replace(/\/+$/, "")
  return head || "."
}

function readRegistryFile(file: string): Dome[] {
  let raw: string
  try {
    if (!statSync(file).isFile()) throw new Error(`${file}: no es un fichero`)
  } catch (e) {
    throw e instanceof Error && e.message.endsWith("no es un fichero") ? e : new Error(`${file}: no se puede leer`)
  }
  try {
    raw = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(readFileSync(file))
  } catch {
    throw new Error(`${file}: no se puede leer`)
  }
  let data: any
  try {
    data = JSON.parse(raw)
  } catch {
    throw new Error(`${file}: JSON no válido`)
  }
  if (!data || typeof data !== "object" || Array.isArray(data) || !data.domes || typeof data.domes !== "object" ||
      Array.isArray(data.domes)) {
    throw new Error(`${file}: sin objeto «domes»`)
  }
  const folder = dirName(file)
  const out: Dome[] = []
  for (const [id, e] of Object.entries<any>(data.domes)) {
    if (!e || typeof e !== "object" || Array.isArray(e) || !isStr(e.path)) throw new Error(`${file}: «${id}» sin ruta`)
    const conf = e.confidentiality
    if (conf !== undefined && conf !== null && !isStr(conf)) throw new Error(`${file}: nivel de «${id}» no válido`)
    const level = isStr(conf) ? parseLevel(conf) : 2
    if (level === null) throw new Error(`${file}: nivel «${conf}» de «${id}» no válido`)
    out.push({ id, root: join(folder, e.path), level })
  }
  return out
}

/**
 * Solo un ENOENT de verdad significa «no hay registro». Cualquier otro error (permisos, un componente que no es
 * directorio, un enlace roto) lanza: el guard falla cerrado.
 */
function registryEntryExists(file: string): boolean {
  const code = (e: unknown) => (e && typeof e === "object" && "code" in e ? (e as { code: unknown }).code : undefined)
  try {
    statSync(file)
    return true
  } catch (e) {
    if (code(e) !== "ENOENT") throw new Error(`${file}: no se puede comprobar`)
  }
  try {
    lstatSync(file)
  } catch (e) {
    if (code(e) === "ENOENT") return false
    throw new Error(`${file}: no se puede comprobar`)
  }
  throw new Error(`${file}: enlace roto`)
}

function loadRegistry(file: string, required: boolean): Registry {
  const base = baseRegistryPath(file)
  let merged: Dome[] = []
  let found = false
  try {
    for (const f of [base, localRegistryPath(base)]) {
      if (!registryEntryExists(f)) continue
      found = true
      for (const d of readRegistryFile(f)) merged = [...merged.filter((m) => m.id !== d.id), d]
    }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
  if (!found && required) return { error: `${base}: no existe` }
  // Orden fijo por id: decide qué cúpula nombra el aviso cuando la orden toca varias.
  // `files`: el registro base y el local, que el motor no puede escribir (si los vaciara, el guard dejaría de proteger).
  return { domes: merged.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)), files: [base, localRegistryPath(base)] }
}

function sessionContext(raw: unknown): Ctx {
  const o = raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as DomeContext) : {}
  const ids = (v: unknown) => (Array.isArray(v) ? v.filter(isStr) : [])
  return { cloud: o.cloud !== false, attached: ids(o.attached), granted: ids(o.granted) }
}

/** Decisión del guard sin mirar la delegación (la usan los tests de la tabla compartida). */
export function decideDome(req: DomeRequest): DomeVerdict {
  const env = req.env.SAVIA_SPACE_DOMES_FILE ?? ""
  const file = env || join(req.root, "projects/savia-vaults/savia-vaults.domes.json")
  return decide(loadRegistry(file, env !== ""), req.project, req.tool, req.input, sessionContext(req.context), req.cwdKnown ?? true)
}

/**
 * Lo que aplica savia-gates. Con `SAVIA_DOME_GUARD=space` decide el guard nativo de Savia Space (que conoce
 * proveedor, adjuntos y concesiones); con `SAVIA_GATES_PIN=1` (modo mediado) rige SE-434. Un fallo
 * inesperado pregunta, como el hook bash cuando su núcleo falla.
 */
export function domeGuardVerdict(req: DomeRequest): DomeVerdict {
  if (req.env.SAVIA_DOME_GUARD === "space" || req.env.SAVIA_GATES_PIN === "1") return { decision: "pass", reason: "" }
  try {
    // Lo mismo que decidePayload: un NUL o un sustituto suelto en la llamada no se decide.
    if (!cleanStrings(req.input) || !cleanStrings(req.context)) return { decision: "ask", reason: PAYLOAD_NOTICE }
    return decideDome(req)
  } catch {
    return { decision: "ask", reason: GUARD_FAILED }
  }
}

/** posixpath.abspath, como el núcleo Python: el proyecto es el `cwd` del payload, normalizado. */
function abspath(p: string): string {
  const full = p.startsWith("/") ? p : `${process.cwd()}/${p}`
  const initial = full.startsWith("//") && !full.startsWith("///") ? 2 : 1
  const out: string[] = []
  for (const c of full.split("/")) {
    if (c === "" || c === ".") continue
    if (c !== "..") out.push(c)
    else if (out.length > 0) out.pop()
  }
  return "/".repeat(initial) + out.join("/")
}

const LONE_SURROGATE = /[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/

/**
 * Ninguna cadena (ni clave) lleva un NUL o un sustituto UTF-16 suelto: el sistema de ficheros no los
 * interpretaría como el guard, así que una llamada así no se decide (pregunta).
 */
function cleanStrings(value: unknown, depth = 0): boolean {
  if (depth > 64) return false
  if (isStr(value)) return !value.includes("\0") && !LONE_SURROGATE.test(value)
  if (Array.isArray(value)) return value.every((v) => cleanStrings(v, depth + 1))
  if (value && typeof value === "object") {
    return Object.entries(value).every(([k, v]) => cleanStrings(k, depth + 1) && cleanStrings(v, depth + 1))
  }
  return true
}

/**
 * Decisión para un payload PreToolUse en texto (el que recibe el hook bash), con la delegación de
 * `domeGuardVerdict`. Un payload que no se puede leer, con cúpulas registradas, pregunta.
 */
export function decidePayload(raw: string, root: string, env: Record<string, string | undefined>): DomeVerdict {
  if (env.SAVIA_DOME_GUARD === "space" || env.SAVIA_GATES_PIN === "1") return { decision: "pass", reason: "" }
  let payload: any
  try {
    payload = JSON.parse(raw)
  } catch {
    payload = null
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload) || !cleanStrings(payload)) {
    const file = env.SAVIA_SPACE_DOMES_FILE || join(root, "projects/savia-vaults/savia-vaults.domes.json")
    const registry = loadRegistry(file, !!env.SAVIA_SPACE_DOMES_FILE)
    return "error" in registry || registry.domes.length > 0 ? { decision: "ask", reason: PAYLOAD_NOTICE } : { decision: "pass", reason: "" }
  }
  const cwdKnown = isStr(payload.cwd) && payload.cwd !== ""
  return domeGuardVerdict({
    root,
    project: abspath(cwdKnown ? payload.cwd : root),
    cwdKnown,
    tool: isStr(payload.tool_name) ? payload.tool_name : "",
    input: payload.tool_input,
    context: payload.dome_context,
    env,
  })
}

const RANK: Record<DomeDecision, number> = { pass: 0, ask: 1, deny: 2 }

/** El veredicto más estricto de varias formas de la misma llamada (la orden envuelta por un sandbox y la interior). */
export function strictest(verdicts: DomeVerdict[]): DomeVerdict {
  return verdicts.reduce((a, b) => (RANK[b.decision] > RANK[a.decision] ? b : a), { decision: "pass", reason: "" })
}
