// shell-targets.ts — files a shell command writes, as far as its text tells (SE-392 S3).
//
// Port line by line of scripts/dual-cli/shell_targets.py; both cores replay the same corpus
// (tests/dual-cli/fixtures/shell_targets_corpus.json) to the same answers. `write`/`edit`/`apply_patch`
// on gate files were denied already; the same rewrite through `bash` (`> .claude/settings.json`,
// recursive `rm` of `.claude`, `sed -i`, `git checkout -- .codex`) went through. The text is read, never
// run. Code of other interpreters (`python -c`) is not analysed: that gap is stated, not hidden.
// A text the tokenizer cannot close throws INVALID_EVENT, never "no targets".

import { realpathSync } from "node:fs"
import { basename, dirname, isAbsolute, join, normalize, sep } from "node:path"

const MAX_DEPTH = 8
const OPERATORS = [";;", "&&", "||", "|&", ";", "|", "&", "(", ")", "\n"]
const WRAPPERS = new Set(["sudo", "command", "builtin", "nohup", "time", "nice", "exec", "doas", "stdbuf", "ionice",
  "timeout"])
const KEYWORDS = new Set(["{", "}", "!", "if", "then", "do", "else", "elif", "while", "until"])
const ALL_ARGS = new Set(["rm", "rmdir", "unlink", "shred", "touch", "truncate", "mkdir", "chmod", "chown",
  "chgrp", "tee", "mv", "patch", "setfacl", "chattr"])
const LAST_ARG = new Set(["cp", "install", "ln", "rsync", "scp"])
const DESTRUCTIVE = new Set(["rm", "rmdir", "unlink", "shred"])
const RECURSIVE_ONLY = new Set(["chmod", "chown", "chgrp", "setfacl"])
const GIT_WRITERS = new Set(["checkout", "restore", "rm", "mv", "apply", "clean", "reset", "stash", "am",
  "switch", "merge", "pull", "rebase", "cherry-pick", "revert"])
const SHELLS = new Set(["bash", "sh", "zsh", "dash", "ksh"])
const XARGS_VALUED = new Set(["-I", "-n", "-L", "-P", "-d", "-s", "-E", "-a"])
const FIND_ACTIONS = new Set(["-delete", "-exec", "-execdir", "-ok", "-okdir"])

export interface Word {
  text: string
  dynamic: boolean
  glob: boolean
}

type Token = ["word", Word] | ["op", string] | ["redir", string]

function invalid(): never {
  throw new Error("INVALID_EVENT")
}

const newWord = (): Word => ({ text: "", dynamic: false, glob: false })

/** os.path.basename */
const pyBasename = (p: string) => p.slice(p.lastIndexOf("/") + 1)

function heredocStart(text: string, i: number): [string, boolean, number] {
  const strip = text.startsWith("-", i)
  if (strip) i += 1
  const m = /^[ \t]*(?:'([^']*)'|"([^"]*)"|\\?([^\s;&|()<>]+))/.exec(text.slice(i))
  if (!m) invalid()
  return [(m[1] ?? m[2] ?? m[3]) as string, strip, i + m[0].length]
}

function skipHeredocs(text: string, i: number, heredocs: [string, boolean][]): number {
  const n = text.length
  for (const [delim, strip] of heredocs) {
    while (i < n) {
      const end = text.indexOf("\n", i)
      const line = end < 0 ? text.slice(i) : text.slice(i, end)
      i = end < 0 ? n : end + 1
      if ((strip ? line.replace(/^\t+/, "") : line) === delim) break
    }
  }
  return i
}

function ansiEnd(text: string, i: number): number {
  const n = text.length
  while (i < n) {
    if (text[i] === "\\") {
      i += 2
      continue
    }
    if (text[i] === "'") return i + 1
    i += 1
  }
  invalid()
}

function closing(text: string, i: number, opener: string, closer: string): number {
  let depth = 1
  let heredocs: [string, boolean][] = []
  const n = text.length
  while (i < n) {
    const c = text[i]
    if (c === "\\") {
      i += 2
      continue
    }
    if (c === "\n" && heredocs.length > 0) {
      i = skipHeredocs(text, i + 1, heredocs)
      heredocs = []
      continue
    }
    if (text.startsWith("<<", i) && !text.startsWith("<<<", i)) {
      const [delim, strip, next] = heredocStart(text, i + 2)
      heredocs.push([delim, strip])
      i = next
      continue
    }
    if (text.startsWith("$'", i)) {
      i = ansiEnd(text, i + 2)
      continue
    }
    if (c === "'") {
      const j = text.indexOf("'", i + 1)
      if (j < 0) invalid()
      i = j + 1
      continue
    }
    if (c === '"') {
      i = skipDouble(text, i + 1)
      continue
    }
    if (c === opener) depth += 1
    else if (c === closer) {
      depth -= 1
      if (depth === 0) return i + 1
    }
    i += 1
  }
  invalid()
}

function skipDouble(text: string, i: number): number {
  const n = text.length
  while (i < n) {
    const c = text[i]
    if (c === "\\") {
      i += 2
      continue
    }
    if (c === '"') return i + 1
    if (text.startsWith("$(", i)) {
      i = closing(text, i + 2, "(", ")")
      continue
    }
    if (c === "`") {
      const j = text.indexOf("`", i + 1)
      if (j < 0) invalid()
      i = j + 1
      continue
    }
    i += 1
  }
  invalid()
}

export function tokenize(text: string, nested: string[]): Token[] {
  const tokens: Token[] = []
  const n = text.length
  let i = 0
  let word: Word | null = null
  let heredocs: [string, boolean][] = []
  const flush = () => {
    if (word !== null) {
      tokens.push(["word", word])
      word = null
    }
  }
  while (i < n) {
    const c = text[i]
    if (c === "\n" && heredocs.length > 0) {
      flush()
      tokens.push(["op", "\n"])
      i = skipHeredocs(text, i + 1, heredocs)
      heredocs = []
      continue
    }
    if (c === " " || c === "\t") {
      flush()
      i += 1
      continue
    }
    if (c === "#" && word === null) {
      const end = text.indexOf("\n", i)
      i = end < 0 ? n : end
      continue
    }
    if (c === "\\") {
      if (i + 1 < n && text[i + 1] === "\n") {
        i += 2
        continue
      }
      word ??= newWord()
      word.text += text.slice(i + 1, i + 2)
      i += 2
      continue
    }
    if (text.startsWith("$'", i)) {
      const end = ansiEnd(text, i + 2)
      word ??= newWord()
      word.text += text.slice(i + 2, end - 1)
      i = end
      continue
    }
    if (c === "'") {
      const j = text.indexOf("'", i + 1)
      if (j < 0) invalid()
      word ??= newWord()
      word.text += text.slice(i + 1, j)
      i = j + 1
      continue
    }
    if (c === '"') {
      const w: Word = (word ??= newWord())
      i += 1
      while (true) {
        if (i >= n) invalid()
        const d = text[i]
        if (d === '"') {
          i += 1
          break
        }
        if (d === "\\" && i + 1 < n && '"\\$`\n'.includes(text[i + 1])) {
          w.text += text[i + 1]
          i += 2
          continue
        }
        if (text.startsWith("$(", i)) {
          const end = closing(text, i + 2, "(", ")")
          nested.push(text.slice(i + 2, end - 1))
          w.text += "$(...)"
          w.dynamic = true
          i = end
          continue
        }
        if (d === "`") {
          const j = text.indexOf("`", i + 1)
          if (j < 0) invalid()
          nested.push(text.slice(i + 1, j))
          w.text += "$(...)"
          w.dynamic = true
          i = j + 1
          continue
        }
        if (d === "$") w.dynamic = true
        w.text += d
        i += 1
      }
      continue
    }
    if (text.startsWith("$(", i)) {
      const end = closing(text, i + 2, "(", ")")
      nested.push(text.slice(i + 2, end - 1))
      word ??= newWord()
      word.text += "$(...)"
      word.dynamic = true
      i = end
      continue
    }
    if (c === "`") {
      const j = text.indexOf("`", i + 1)
      if (j < 0) invalid()
      nested.push(text.slice(i + 1, j))
      word ??= newWord()
      word.text += "$(...)"
      word.dynamic = true
      i = j + 1
      continue
    }
    if (c === "<" || c === ">" || (c === "&" && text.startsWith("&>", i))) {
      const current = word as Word | null
      const fd = current !== null && /^[0-9]+$/.test(current.text) && !current.dynamic
      if (current !== null && !fd) flush()
      word = null
      let op = (/^(?:&>>|&>|>>|>\||>&|<<<|<<-|<<|<>|<&|>|<)/.exec(text.slice(i)) as RegExpExecArray)[0]
      i += op.length
      if (op === ">&" || op === "<&") {
        const m2 = /^[ \t]*([0-9]+-?|-)(?=[\s;&|()<>]|$)/.exec(text.slice(i))
        if (m2) {
          i += m2[0].length
          continue
        }
        op = op === ">&" ? ">" : "<"
      }
      if (op === "<<" || op === "<<-") {
        const [delim, strip, next] = heredocStart(text, i - op.length + 2)
        heredocs.push([delim, strip])
        i = next
        continue
      }
      tokens.push(["redir", op])
      continue
    }
    const op = OPERATORS.find((o) => text.startsWith(o, i))
    if (op !== undefined) {
      flush()
      tokens.push(["op", op])
      i += op.length
      continue
    }
    word ??= newWord()
    if (c === "$") word.dynamic = true
    else if (c === "*" || c === "?" || c === "[") word.glob = true
    word.text += c
    i += 1
  }
  flush()
  return tokens
}

function nonOptions(args: Word[]): Word[] {
  const out: Word[] = []
  let ended = false
  for (const w of args) {
    if (!ended && w.text === "--") {
      ended = true
      continue
    }
    if (!ended && w.text.startsWith("-") && w.text !== "-") continue
    out.push(w)
  }
  return out
}

const plain = (text: string, like: Word): Word => ({ text, dynamic: like.dynamic, glob: like.glob })

type Target = [Word, boolean]

function commandTargets(words: Word[], depth: number): Target[] {
  let i = 0
  while (i < words.length) {
    const name = pyBasename(words[i].text)
    if (/^[A-Za-z_][A-Za-z0-9_]*=[\s\S]*$/.test(words[i].text) || KEYWORDS.has(name)) {
      i += 1
    } else if (WRAPPERS.has(name)) {
      i += 1
      while (i < words.length && (words[i].text.startsWith("-") || /^[0-9.]+[smhd]?$/.test(words[i].text))) i += 1
    } else if (name === "env") {
      i += 1
      while (i < words.length && (words[i].text.startsWith("-") || words[i].text.includes("="))) i += 1
    } else {
      break
    }
  }
  if (i >= words.length) return []
  const name = pyBasename(words[i].text)
  const args = words.slice(i + 1)
  if (SHELLS.has(name)) {
    for (let k = 0; k < args.length; k++) {
      if (args[k].text === "-c" && k + 1 < args.length) return analyse(args[k + 1].text, depth + 1)
    }
    return []
  }
  if (name === "eval") return analyse(args.map((w) => w.text).join(" "), depth + 1)
  if (name === "xargs") {
    let k = 0
    while (k < args.length && args[k].text.startsWith("-")) k += XARGS_VALUED.has(args[k].text) ? 2 : 1
    return commandTargets(args.slice(k), depth)
  }
  if (name === "find") {
    if (!args.some((w) => FIND_ACTIONS.has(w.text))) return []
    const starts: Target[] = []
    for (const w of args) {
      if (w.text.startsWith("-") || w.text === "(" || w.text === "!") break
      starts.push([w, false])
    }
    return starts
  }
  if (ALL_ARGS.has(name)) {
    const rest = nonOptions(args)
    if (name === "mv") return rest.map((w, k) => [w, k < rest.length - 1])
    if (RECURSIVE_ONLY.has(name)) {
      const recursive = args.some((w) => w.text === "--recursive" || /^-[a-zA-Z]*R[a-zA-Z]*$/.test(w.text))
      return rest.map((w) => [w, recursive])
    }
    return rest.map((w) => [w, DESTRUCTIVE.has(name)])
  }
  if (LAST_ARG.has(name)) {
    for (let k = 0; k < args.length; k++) {
      const w = args[k]
      if ((w.text === "-t" || w.text === "--target-directory") && k + 1 < args.length) return [[args[k + 1], false]]
      if (w.text.startsWith("--target-directory=")) return [[plain(w.text.slice(w.text.indexOf("=") + 1), w), false]]
    }
    const rest = nonOptions(args)
    return rest.length >= 2 ? [[rest[rest.length - 1], false]] : []
  }
  if ((name === "sed" || name === "perl") && args.some((w) => w.text.startsWith("-i") ||
      w.text.startsWith("--in-place") || (name === "perl" && /^-[a-zA-Z]*i.*$/.test(w.text)))) {
    return nonOptions(args).map((w) => [w, false])
  }
  if (name === "dd") return args.filter((w) => w.text.startsWith("of=")).map((w) => [plain(w.text.slice(3), w), false])
  if (name === "git") {
    let k = 0
    while (k < args.length && args[k].text.startsWith("-")) {
      k += ["-C", "-c", "--git-dir", "--work-tree"].includes(args[k].text) ? 2 : 1
    }
    if (k < args.length && GIT_WRITERS.has(args[k].text)) return nonOptions(args.slice(k + 1)).map((w) => [w, false])
  }
  return []
}

/** [word, destructive] for every write target the command text shows. Throws INVALID_EVENT. */
export function analyse(text: unknown, depth = 0): Target[] {
  if (depth > MAX_DEPTH || typeof text !== "string") invalid()
  const nested: string[] = []
  const tokens = tokenize(text, nested)
  let targets: Target[] = []
  let words: Word[] = []
  let pending: string | null = null
  for (const [kind, value] of [...tokens, ["op", ";"] as Token]) {
    if (pending !== null) {
      if (kind !== "word") invalid()
      if (pending !== "<" && pending !== "<<<") targets.push([value as Word, false])
      pending = null
      continue
    }
    if (kind === "redir") pending = value as string
    else if (kind === "word") words.push(value as Word)
    else {
      targets = targets.concat(commandTargets(words, depth))
      words = []
    }
  }
  for (const inner of nested) targets = targets.concat(analyse(inner, depth + 1))
  return targets
}

const escapeRegex = (c: string) => c.replace(/[.*+?^${}()|[\]\\/-]/g, "\\$&")

function globRegex(pattern: string): string {
  let out = ""
  const n = pattern.length
  for (let i = 0; i < n; i++) {
    const c = pattern[i]
    if (c === "*") out += "[^/]*"
    else if (c === "?") out += "[^/]"
    else if (c === "[") {
      const j = pattern.indexOf("]", i + 1 < n && "!^".includes(pattern[i + 1]) ? i + 2 : i + 1)
      if (j < 0) out += "\\["
      else {
        let body = pattern.slice(i + 1, j)
        const neg = body.startsWith("!") || body.startsWith("^")
        if (neg) body = body.slice(1)
        out += "[" + (neg ? "^" : "") + body.replace(/([\\\]\[^])/g, "\\$1") + "]"
        i = j
      }
    } else out += escapeRegex(c)
  }
  return out
}

const fullmatch = (rx: string, s: string) => new RegExp(`^(?:${rx})$`).test(s)

/** os.path.normpath for absolute paths. */
function normPath(p: string): string {
  const out = normalize(p)
  return out.length > 1 && out.endsWith("/") ? out.slice(0, -1) : out
}

/** os.path.realpath: resolves the symlinks of the part that exists, keeps the rest as written. */
function realPath(p: string): string {
  try {
    return realpathSync(p)
  } catch {
    const parent = dirname(p)
    return parent === p ? p : join(realPath(parent), basename(p))
  }
}

function ancestors(path: string): string[] {
  const out = [path]
  while (path !== dirname(path)) {
    path = dirname(path)
    out.push(path)
  }
  return out
}

function globHits(path: string, bases: string[], destructive: boolean): boolean {
  const comps = path.split("/")
  for (let k = 2; k <= comps.length; k++) {
    const rx = globRegex(comps.slice(0, k).join("/"))
    if (bases.some((b) => fullmatch(rx, b))) return true
  }
  const rx = globRegex(path)
  return destructive && bases.some((b) => ancestors(b).some((a) => fullmatch(rx, a)))
}

/** First write target of `command` that is gate code, or null. Throws INVALID_EVENT. */
export function protectedTarget(command: unknown, cwd: string, root: string, protectedRel: readonly string[]): string | null {
  root = normPath(root)
  const bases = protectedRel.map((rel) => normPath(join(root, rel)))
  const realBases = [...bases, ...bases.map(realPath)]
  for (const [word, destructive] of analyse(command)) {
    let text = word.text
    for (const v of ["${CLAUDE_PROJECT_DIR}", "$CLAUDE_PROJECT_DIR"]) text = text.split(v).join(root)
    for (const v of ["${PWD}", "$PWD"]) text = text.split(v).join(cwd)
    if (text.startsWith("~")) continue
    if (word.dynamic && text.includes("$")) {
      const tail = "/" + text.replace(/^\/+/, "")
      if (protectedRel.some((rel) => tail.endsWith("/" + rel) || tail.includes("/" + rel + "/"))) return word.text
      continue
    }
    const path = normPath(isAbsolute(text) ? text : join(cwd, text))
    if (word.glob) {
      if (globHits(path, bases, destructive)) return word.text
      continue
    }
    for (const cand of [path, realPath(path)]) {
      for (const base of realBases) {
        if (cand === base || cand.startsWith(base + sep)) return word.text
        if (destructive && base.startsWith(cand.replace(/\/+$/, "") + sep)) return word.text
      }
    }
  }
  return null
}
