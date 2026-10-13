// dome-guard.ts — Guard de cúpulas en el motor (SE-436 S5, D30-4): regla nativa de savia-gates.
//
// Gemelo del hook de Claude Code `.claude/hooks/dome-guard.sh` (núcleo `.claude/hooks/lib/dome_guard.py`),
// ambos portados de `crates/space-orchestrator/src/dome_guard.rs` de Savia Space. Misma entrada, misma
// decisión y mismo motivo: tests/hooks/test-dome-guard-parity.bats. Cualquier cambio aquí va también allí.
//
// - Escritura (edit, write, patch, multiedit o un bash que escriba) dentro de una cúpula → ask.
// - Lectura de una cúpula N2+ no adjunta con proveedor de nube → ask; N3+ → deny.
// - Fuera de las cúpulas → pass. Registro ilegible → ask en todo lo que mira (falla cerrado).

import { existsSync, lstatSync, readdirSync, readFileSync, readlinkSync, realpathSync } from "node:fs"

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
  env: Record<string, string | undefined>
}

export const WRITE_NOTICE =
  "Usa una propuesta: Guardar como nota. El motor no escribe en una cúpula; la propuesta la revisa la persona"
export const UNKNOWN_NOTICE =
  "la orden toca una cúpula y no es una lectura conocida; si escribe, usa una propuesta: Guardar como nota"
export const CLOUD_DENIED =
  "contenido N3 o superior no sale a la nube: esta cúpula no se lee con el motor. " +
  "Pide a la persona una tarea del carril local; el resultado lo ve ella y no vuelve a ti"
export const GUARD_FAILED = "el guard falló; no se puede comprobar si la orden toca una cúpula"

const WRITERS = new Set(["cp", "mv", "rm", "touch", "tee", "sed", "dd", "install", "ln", "truncate", "chmod", "chown",
  "mkdir", "rmdir", "tar", "unzip", "rsync", "git", "python3", "python", "node", "bash", "sh", "perl", "ruby", "patch",
  "cpio", "zip", "7z", "scp", "curl", "wget", "eval"])
const WRITE_TOOLS = new Set(["edit", "write", "patch", "multiedit", "notebookedit", "apply_patch"])
const FILE_TOOLS = new Set(["read", "grep", "glob", "list"])
const READ_ONLY = new Set(["cat", "ls", "head", "tail", "grep", "wc", "stat", "du", "diff", "nl"])
const TRAVERSERS = new Set(["grep", "rg", "find", "tree", "du", "ls", "tar", "cp", "rsync", "zip", "cpio", "7z", "scp"])
const WRITE_PATH_KEYS = ["filePath", "file_path", "path", "notebook_path"]
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

function expandGlob(project: string, pattern: string): string[] {
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
        if (budget === 0) return next
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

function symlinksInto(root: string, target: string, depth: number): string[] {
  const out: string[] = []
  for (const name of listDir(root).slice(0, 500)) {
    const p = join(root, name)
    if (isLink(p)) {
      const c = canonical(p)
      if (c !== null && under(c, target)) out.push(p)
    } else if (isDir(p) && depth > 1 && !name.startsWith(".")) {
      out.push(...symlinksInto(p, target, depth - 1))
    }
  }
  return out
}

const TOKEN_SPLIT = new RegExp(WS_CLASS + "'\"`;&|()<>=]+")
const COMPONENT_SPLIT = new RegExp(WS_CLASS + "/'\"`;&|()<>=:]+")
const LOWER_SPLIT = new RegExp(WS_CLASS + "/]")

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
  for (const link of symlinksInto(ws, rd, 2)) {
    const r = stripPrefix(link, ws)
    if (r !== null && command.includes(r)) return true
  }
  for (const t of tokens) {
    if ((t.includes("*") || t.includes("?")) && expandGlob(project, t).some((m) => under(resolvePath(m), rd))) return true
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
type Registry = { domes: Dome[] } | { error: string }
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
    return outputs(c) || dynamic || prog === null || WRITERS.has(baseName(prog))
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

function traversalReaches(script: Cmd[], project: string, root: string): boolean {
  for (const c of script) {
    const words = c.words.map(litOrDollar)
    if (words.length === 0 || !TRAVERSERS.has(baseName(words[0]))) continue
    const prog = baseName(words[0])
    if (!isRecursive(prog, words.slice(1).filter((w) => w.startsWith("-") && [...w].length > 1))) continue
    const args = words.slice(1).filter((w) => !w.startsWith("-"))
    if ((prog === "grep" || prog === "rg") && args.length > 0) args.shift()
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

function decideBash(domes: Dome[], project: string, ctx: Ctx, command: string): DomeVerdict {
  let script: Cmd[]
  try {
    script = parseShell(command)
  } catch (e) {
    if (e instanceof ShellParseError) return { decision: "ask", reason: `la orden de shell no se puede analizar: ${WRITE_NOTICE}` }
    throw e
  }
  const plain = unquoted(script)
  const lowerTokens = plain.toLowerCase().split(LOWER_SPLIT)
  const words = script.flatMap((c) => [...c.words, ...c.redirs.map((r) => r.target)]).map(litOrDollar)
  const pathlike = words.filter((w) => w.includes("/") && ![..."*?$"].some((ch) => w.includes(ch)))
  const nameOnlyOk = pathlike.length === 0 ||
    words.some((w) => w === "cd" || w === "pushd" || w === "$" || w.includes("*") || w.includes("?"))
  const direct = (d: Dome) => {
    const name = fileName(d.root).toLowerCase()
    const named = (name !== "" && lowerTokens.includes(name)) || [command, plain].some((c) => mentionsDome(d.root, project, c))
    return named && (nameOnlyOk || pathlike.some((w) => touches(d.root, project, w, false)))
  }
  const directHit = domes.filter(direct)
  if (directHit.length > 0 && !bashReadsOnly(script)) {
    return { decision: "ask", reason: writes(script) ? WRITE_NOTICE : UNKNOWN_NOTICE }
  }
  const touched = [...directHit]
  for (const d of domes) {
    if (!touched.some((t) => t.id === d.id) && traversalReaches(script, project, d.root)) touched.push(d)
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

function decide(registry: Registry, project: string, tool: string, input: Record<string, unknown>, ctx: Ctx): DomeVerdict {
  const permission = toolPermission(tool)
  if (!(permission === "bash" || FILE_TOOLS.has(permission) || WRITE_TOOLS.has(permission))) return { decision: "pass", reason: "" }
  if ("error" in registry) return { decision: "ask", reason: `registro de cúpulas ilegible (${registry.error}): ${WRITE_NOTICE}` }
  const domes = registry.domes
  if (domes.length === 0) return { decision: "pass", reason: "" }
  if (WRITE_TOOLS.has(permission)) {
    const paths = WRITE_PATH_KEYS.map((k) => input[k]).filter(isStr)
    for (const k of ["patchText", "patch"]) {
      const v = input[k]
      if (isStr(v)) paths.push(...patchPathsOf(v))
    }
    if (paths.length === 0) return { decision: "ask", reason: `no se sabe qué ruta escribe el motor: ${WRITE_NOTICE}` }
    const hit = paths.some((p) => domes.some((d) => touches(d.root, project, p, false)))
    return hit ? { decision: "ask", reason: WRITE_NOTICE } : { decision: "pass", reason: "" }
  }
  if (permission === "bash") return decideBash(domes, project, ctx, isStr(input.command) ? input.command : "")
  const root = searchRoot(project, permission, input)
  const touched = root === null ? domes : domes.filter((d) => touches(d.root, project, root, permission !== "read"))
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

function loadRegistry(file: string, required: boolean): Registry {
  const base = baseRegistryPath(file)
  let merged: Dome[] = []
  let found = false
  try {
    for (const f of [base, localRegistryPath(base)]) {
      if (!existsSync(f)) continue
      found = true
      for (const d of readRegistryFile(f)) merged = [...merged.filter((m) => m.id !== d.id), d]
    }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
  if (!found && required) return { error: `${base}: no existe` }
  // Orden fijo por id: decide qué cúpula nombra el aviso cuando la orden toca varias.
  return { domes: merged.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)) }
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
  const input = req.input && typeof req.input === "object" && !Array.isArray(req.input) ? (req.input as Record<string, unknown>) : {}
  return decide(loadRegistry(file, env !== ""), req.project, req.tool, input, sessionContext(req.context))
}

/**
 * Lo que aplica savia-gates. Con `SAVIA_DOME_GUARD=space` decide el guard nativo de Savia Space (que conoce
 * proveedor, adjuntos y concesiones); con `SAVIA_GATES_PIN=1` (modo mediado) rige SE-434. Un fallo
 * inesperado pregunta, como el hook bash cuando su núcleo falla.
 */
export function domeGuardVerdict(req: DomeRequest): DomeVerdict {
  if (req.env.SAVIA_DOME_GUARD === "space" || req.env.SAVIA_GATES_PIN === "1") return { decision: "pass", reason: "" }
  try {
    return decideDome(req)
  } catch {
    return { decision: "ask", reason: GUARD_FAILED }
  }
}

const RANK: Record<DomeDecision, number> = { pass: 0, ask: 1, deny: 2 }

/** El veredicto más estricto de varias formas de la misma llamada (la orden envuelta por un sandbox y la interior). */
export function strictest(verdicts: DomeVerdict[]): DomeVerdict {
  return verdicts.reduce((a, b) => (RANK[b.decision] > RANK[a.decision] ? b : a), { decision: "pass", reason: "" })
}
