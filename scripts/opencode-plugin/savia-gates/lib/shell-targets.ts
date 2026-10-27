// shell-targets.ts — files a shell command writes, as far as its text tells (SE-392 S3).
//
// Port line by line of scripts/dual-cli/shell_targets.py; both cores replay the same corpus
// (tests/dual-cli/fixtures/shell_targets_corpus.json) to the same answers. `write`/`edit`/`apply_patch`
// on gate files were denied already; the same rewrite through `bash` (`> .claude/settings.json`,
// recursive `rm` of `.claude`, `sed -i`, `git checkout -- .codex`) went through. The text is read, never
// run. `cd`/`pushd` move the base of the relative paths that follow; `git -C`/`--work-tree` too. Code of
// other interpreters (`python -c`) is not analysed: that gap is stated, not hidden.
// A text the tokenizer cannot close throws INVALID_EVENT, never "no targets".

import { lstatSync, readdirSync, realpathSync } from "node:fs"
import { basename, dirname, normalize, sep } from "node:path"

const MAX_DEPTH = 8
const MAX_BRACE = 64
const MAX_WALK = 5000
const GENERATED = new Set(["__pycache__", "node_modules"])
const OPERATORS = [";;", "&&", "||", "|&", ";", "|", "&", "(", ")", "\n"]
const WRAPPERS = new Set(["sudo", "command", "builtin", "nohup", "time", "nice", "exec", "doas", "stdbuf", "ionice",
  "timeout", "env"])
const WRAPPER_VALUED: Record<string, Set<string>> = {
  sudo: new Set(["-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "--user", "--group", "--host",
    "--prompt", "--close-from", "--chdir", "--chroot", "--command-timeout", "--other-user"]),
  doas: new Set(["-u", "-C"]), nice: new Set(["-n", "--adjustment"]),
  ionice: new Set(["-c", "-n", "-p", "-P", "-u", "--class", "--classdata", "--pid", "--pgid", "--uid"]),
  timeout: new Set(["-s", "-k", "--signal", "--kill-after"]),
  stdbuf: new Set(["-i", "-o", "-e", "--input", "--output", "--error"]),
  env: new Set(["-u", "-C", "-S", "--unset", "--chdir", "--split-string"]),
}
const CHDIR_OPTIONS: Record<string, Set<string>> = { env: new Set(["-C", "--chdir"]), sudo: new Set(["-D", "--chdir"]) }
const KEYWORDS = new Set(["{", "}", "!", "if", "then", "do", "else", "elif", "while", "until"])
const ALL_ARGS = new Set(["rm", "rmdir", "unlink", "shred", "touch", "truncate", "mkdir", "chmod", "chown",
  "chgrp", "tee", "mv", "patch", "setfacl", "chattr"])
const LAST_ARG = new Set(["cp", "install", "ln", "rsync", "scp"])
const DESTRUCTIVE = new Set(["rm", "rmdir", "unlink", "shred"])
const RECURSIVE_ONLY = new Set(["chmod", "chown", "chgrp", "setfacl"])
const GIT_WRITERS = new Set(["checkout", "restore", "rm", "mv", "apply", "clean", "reset", "stash", "am",
  "switch", "merge", "pull", "rebase", "cherry-pick", "revert"])
const GIT_PATHSPEC_TREE = new Set(["checkout", "restore", "rm", "clean", "reset", "stash"])
// Subcommand -> [options that make it touch only the index, options that bring the worktree back];
// an empty first set means "index only unless a second-set option is given" (`git reset .`).
const GIT_INDEX_ONLY: Record<string, [Set<string>, Set<string>]> = {
  restore: [new Set(["--staged", "-S"]), new Set(["--worktree", "-W"])],
  rm: [new Set(["--cached"]), new Set()],
  reset: [new Set(), new Set(["--hard", "--merge", "--keep"])],
}
const GIT_BRANCH_VALUED = new Set(["-b", "-B", "--orphan", "-c", "-C"])
const SHELLS = new Set(["bash", "sh", "zsh", "dash", "ksh"])
const SHELL_VALUED = new Set(["-o", "+o", "-O", "+O", "--rcfile", "--init-file"])
const RECURSIVE_COPY = /^(?:-[a-zA-Z]*[rRa][a-zA-Z]*|--recursive|--archive)$/
const XARGS_VALUED = new Set(["-I", "-n", "-L", "-P", "-d", "-s", "-E", "-a", "--max-args", "--max-lines",
  "--max-procs", "--delimiter", "--max-chars", "--arg-file", "--eof", "--process-slot-var"])
const FIND_NAME = new Set(["-name", "-iname"])
const FIND_VALUED = new Set(["-type", "-maxdepth", "-mindepth"])
const FIND_PLAIN = new Set(["(", ")", "-a", "-and", "-print", "-print0", "-delete", "-depth"])
const FIND_EXEC = new Set(["-exec", "-execdir", "-ok", "-okdir"])

/** `base`: directory the relative path starts from (`cd`, `git -C`). `loose`: that directory is unknown.
 * `names`: `find -name` patterns narrowing what a start path reaches, as [pattern, caseInsensitive]. */
export interface Word {
  text: string
  dynamic: boolean
  glob: boolean
  base: string
  loose: boolean
  names: [string, boolean][] | null
}

type Token = ["word", Word] | ["op", string] | ["redir", string] | ["body", string[]]
type Heredoc = [string, boolean, string[]?]

function invalid(): never {
  throw new Error("INVALID_EVENT")
}

const newWord = (): Word => ({ text: "", dynamic: false, glob: false, base: "", loose: false, names: null })
const copy = (w: Word, changes: Partial<Word> = {}): Word => ({ ...w, ...changes })

/** os.path.basename */
const pyBasename = (p: string) => p.slice(p.lastIndexOf("/") + 1)

/** posixpath.join */
function pjoin(...parts: string[]): string {
  let out = parts[0]
  for (const b of parts.slice(1)) {
    if (b.startsWith("/")) out = b
    else if (out === "" || out.endsWith("/")) out += b
    else out += "/" + b
  }
  return out
}

function heredocStart(text: string, i: number): [string, boolean, number] {
  const strip = text.startsWith("-", i)
  if (strip) i += 1
  const m = /^[ \t]*(?:'([^']*)'|"([^"]*)"|\\?([^\s;&|()<>]+))/.exec(text.slice(i))
  if (!m) invalid()
  return [(m[1] ?? m[2] ?? m[3]) as string, strip, i + m[0].length]
}

function skipHeredocs(text: string, i: number, heredocs: Heredoc[]): number {
  const n = text.length
  for (const doc of heredocs) {
    const [delim, strip] = doc
    const start = i
    let bodyEnd = n
    while (i < n) {
      const end = text.indexOf("\n", i)
      const line = end < 0 ? text.slice(i) : text.slice(i, end)
      const lineStart = i
      i = end < 0 ? n : end + 1
      if ((strip ? line.replace(/^\t+/, "") : line) === delim) {
        bodyEnd = lineStart
        break
      }
    }
    if (doc[2]) doc[2].push(text.slice(start, bodyEnd))
  }
  return i
}

const ANSI_ESCAPES: Record<string, string> = { a: "\x07", b: "\b", e: "\x1b", E: "\x1b", f: "\f", n: "\n", r: "\r",
  t: "\t", v: "\v", "\\": "\\", "'": "'", '"': '"', "?": "?" }

function ansiDecode(body: string): string {
  return body.replace(/\\(x[0-9a-fA-F]{1,2}|u[0-9a-fA-F]{1,4}|U[0-9a-fA-F]{1,8}|[0-7]{1,3}|c[\s\S]|[\s\S])/g,
    (all, e: string) => {
      let code: number
      if ("xuU".includes(e[0])) code = parseInt(e.slice(1), 16)
      else if ("01234567".includes(e[0])) code = parseInt(e, 8) & 0xff
      else if (e[0] === "c") code = (e.codePointAt(1) as number) & 0x1f
      else return ANSI_ESCAPES[e] ?? all
      if (code > 0x10ffff) invalid()
      return String.fromCodePoint(code)
    })
}

function arithEnd(text: string, i: number): number | null {
  let depth = 2
  const n = text.length
  for (; i < n; i++) {
    const c = text[i]
    if (c === "(") depth += 1
    else if (c === ")") {
      if (depth === 2) return text.startsWith("))", i) ? i + 2 : null
      depth -= 1
    }
  }
  return null
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
  let heredocs: Heredoc[] = []
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

/** Command and process substitutions go to `nested` as [index of the token they belong to, raw text]. */
export function tokenize(text: string, nested: [number, string][]): Token[] {
  const tokens: Token[] = []
  const n = text.length
  let i = 0
  let word: Word | null = null
  let heredocs: Heredoc[] = []
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
      word.text += ansiDecode(text.slice(i + 2, end - 1))
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
    if (word === null && text.startsWith("((", i)) {
      const end = arithEnd(text, i + 2)
      if (end !== null) {
        i = end
        continue
      }
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
          nested.push([tokens.length, text.slice(i + 2, end - 1)])
          w.text += "$(...)"
          w.dynamic = true
          i = end
          continue
        }
        if (d === "`") {
          const j = text.indexOf("`", i + 1)
          if (j < 0) invalid()
          nested.push([tokens.length, text.slice(i + 1, j)])
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
      nested.push([tokens.length, text.slice(i + 2, end - 1)])
      word ??= newWord()
      word.text += "$(...)"
      word.dynamic = true
      i = end
      continue
    }
    if (c === "`") {
      const j = text.indexOf("`", i + 1)
      if (j < 0) invalid()
      nested.push([tokens.length, text.slice(i + 1, j)])
      word ??= newWord()
      word.text += "$(...)"
      word.dynamic = true
      i = j + 1
      continue
    }
    if (text.startsWith("<(", i) || text.startsWith(">(", i)) {
      // Process substitution: a /dev/fd name; its commands run.
      const end = closing(text, i + 2, "(", ")")
      nested.push([tokens.length, text.slice(i + 2, end - 1)])
      word ??= newWord()
      word.text += "$(...)"
      word.dynamic = true
      i = end
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
        const body: string[] = []
        heredocs.push([delim, strip, body])
        tokens.push(["body", body])
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

const plain = (text: string, like: Word): Word => copy(like, { text })
const isAssignment = (text: string) => /^[A-Za-z_][A-Za-z0-9_]*=[\s\S]*$/.test(text)

type Target = [Word, boolean]

function rebase(w: Word, base: string, loose = false): Word {
  if (base) w = copy(w, { base: w.base ? pjoin(base, w.base) : base })
  return loose && !w.loose ? copy(w, { loose: true }) : w
}

const joined = (dest: Word, src: Word): Word =>
  copy(dest, { text: pjoin(dest.text, pyBasename(src.text)), dynamic: dest.dynamic || src.dynamic,
    glob: dest.glob || src.glob })

const into = (dest: Word, sources: Word[], reach: boolean): Target[] =>
  [[dest, false] as Target].concat(sources.map((s) => [joined(dest, s), reach] as Target))

function commandTargets(words: Word[], depth: number, bodies: string[] = []): Target[] {
  let i = 0
  let base = ""
  let loose = false
  outer: while (i < words.length) {
    const name = pyBasename(words[i].text)
    if (isAssignment(words[i].text) || KEYWORDS.has(name)) {
      i += 1
      continue
    }
    if (!WRAPPERS.has(name)) break
    const valued = WRAPPER_VALUED[name] ?? new Set<string>()
    const chdir = CHDIR_OPTIONS[name] ?? new Set<string>()
    i += 1
    while (i < words.length) {
      const t = words[i].text
      if (t === "--") {
        i += 1
        continue outer
      }
      if (name === "env" && isAssignment(t)) i += 1
      else if (t.startsWith("-")) {
        const eqAt = t.indexOf("=")
        const opt = eqAt < 0 ? t : t.slice(0, eqAt)
        const eq = eqAt >= 0
        const value = eq ? plain(t.slice(eqAt + 1), words[i]) : (i + 1 < words.length ? words[i + 1] : null)
        if (name === "env" && (opt === "-S" || opt === "--split-string") && value !== null) {
          const rest = words.slice(i + (eq ? 1 : 2))
          const inner = analyse([value.text, ...rest.map((w) => w.text)].join(" "), depth + 1)
          return inner.map(([w, d]) => [rebase(w, base, loose), d])
        }
        if (chdir.has(opt) && value !== null) {
          if (value.dynamic || value.text.startsWith("~")) loose = true
          else base = pjoin(base, value.text)
        }
        i += valued.has(opt) && !eq ? 2 : 1
      } else if (/^[0-9.]+[smhd]?$/.test(t)) i += 1
      else break
    }
  }
  if (i >= words.length) return []
  return targetsOf(pyBasename(words[i].text), words.slice(i + 1), depth, bodies)
    .map(([w, d]) => [rebase(w, base, loose), d])
}

function targetsOf(name: string, args: Word[], depth: number, bodies: string[]): Target[] {
  if (SHELLS.has(name)) {
    let k = 0
    while (k < args.length) {
      const t = args[k].text
      if (/^-[a-zA-Z]*c[a-zA-Z]*$/.test(t)) return k + 1 < args.length ? analyse(args[k + 1].text, depth + 1) : []
      if (SHELL_VALUED.has(t)) k += 2
      else if (t.startsWith("-") || t.startsWith("+")) k += 1
      else return []
    }
    return bodies.flatMap((body) => analyse(body, depth + 1))
  }
  if (name === "eval") return analyse(args.map((w) => w.text).join(" "), depth + 1)
  if (name === "xargs") {
    let k = 0
    while (k < args.length && args[k].text.startsWith("-")) k += XARGS_VALUED.has(args[k].text) ? 2 : 1
    return commandTargets(args.slice(k), depth)
  }
  if (name === "find") return findTargets(args, depth)
  if (ALL_ARGS.has(name)) {
    const rest = nonOptions(args)
    if (name === "mv") {
      if (rest.length < 2) return rest.map((w) => [w, false])
      const sources = rest.slice(0, -1)
      return sources.map((w) => [w, true] as Target).concat(into(rest[rest.length - 1], sources, true))
    }
    if (RECURSIVE_ONLY.has(name)) {
      const recursive = args.some((w) => w.text === "--recursive" || /^-[a-zA-Z]*R[a-zA-Z]*$/.test(w.text))
      return rest.map((w) => [w, recursive])
    }
    return rest.map((w) => [w, DESTRUCTIVE.has(name)])
  }
  if (name === "install" && args.some((w) => w.text === "-d" || w.text === "--directory")) {
    return nonOptions(args).map((w) => [w, false])  // every argument is a directory to create
  }
  if (LAST_ARG.has(name)) {
    const recursive = args.some((w) => RECURSIVE_COPY.test(w.text))
    for (let k = 0; k < args.length; k++) {
      const w = args[k]
      if ((w.text === "-t" || w.text === "--target-directory") && k + 1 < args.length) {
        return into(args[k + 1], nonOptions([...args.slice(0, k), ...args.slice(k + 2)]), recursive)
      }
      if (w.text.startsWith("--target-directory=")) {
        return into(plain(w.text.slice(w.text.indexOf("=") + 1), w),
          nonOptions([...args.slice(0, k), ...args.slice(k + 1)]), recursive)
      }
    }
    const rest = nonOptions(args)
    return rest.length >= 2 ? into(rest[rest.length - 1], rest.slice(0, -1), recursive) : []
  }
  if ((name === "sed" || name === "perl") &&
      args.some((w) => w.text.startsWith("--in-place") || /^-[a-zA-Z]*i[\s\S]*$/.test(w.text))) {
    return nonOptions(args).map((w) => [w, false])
  }
  if (name === "dd") return args.filter((w) => w.text.startsWith("of=")).map((w) => [plain(w.text.slice(3), w), false])
  if (name === "git") {
    let k = 0
    let base = ""
    let loose = false
    while (k < args.length && args[k].text.startsWith("-")) {
      const t = args[k].text
      const eqAt = t.indexOf("=")
      const opt = eqAt < 0 ? t : t.slice(0, eqAt)
      if ((opt === "-C" || opt === "--work-tree") && (eqAt >= 0 || k + 1 < args.length)) {
        const value = eqAt >= 0 ? plain(t.slice(eqAt + 1), args[k]) : args[k + 1]
        if (value.dynamic || value.text.startsWith("~")) loose = true
        else base = pjoin(base, value.text)
        k += eqAt >= 0 ? 1 : 2
        continue
      }
      k += ["-c", "--git-dir", "--namespace"].includes(t) ? 2 : 1
    }
    if (k < args.length && GIT_WRITERS.has(args[k].text)) {
      const sub = args[k].text
      let rest = args.slice(k + 1)
      const opts = new Set(rest.map((w) => w.text))
      const only = GIT_INDEX_ONLY[sub]
      if (only && ![...only[1]].some((o) => opts.has(o)) && (only[0].size === 0 || [...only[0]].some((o) => opts.has(o)))) {
        return []  // only the index changes: `git restore --staged .`, `git reset .`, `git rm --cached`
      }
      // The value of `checkout -b NAME` is a branch, not a pathspec.
      rest = rest.filter((_, j) => !(j > 0 && GIT_BRANCH_VALUED.has(rest[j - 1].text)))
      const reach = GIT_PATHSPEC_TREE.has(sub)
      return nonOptions(rest).map((w) => [rebase(w, base, loose), reach])
    }
  }
  return []
}

function findTargets(args: Word[], depth: number): Target[] {
  let k = 0
  let starts: Word[] = []
  while (k < args.length && !(args[k].text.startsWith("-") || args[k].text === "(" || args[k].text === "!")) {
    starts.push(args[k])
    k += 1
  }
  let writes = false
  let narrow = true
  const names: [string, boolean][] = []
  const literal: Target[] = []
  while (k < args.length) {
    const t = args[k].text
    if (FIND_EXEC.has(t)) {
      let end = args.length
      for (let j = k + 1; j < args.length; j++) {
        if (args[j].text === ";" || args[j].text === "+") {
          end = j
          break
        }
      }
      const inner = args.slice(k + 1, end)
      // A target that starts with `{}` is the found file; any other one is a literal path written once per
      // match (`-exec cp {} /tmp/ \;` reads the tree, `-exec cp {} .claude/x \;` writes x).
      for (const [w, d] of inner.length > 0 ? commandTargets(inner, depth) : []) {
        if (w.text.startsWith("{}")) writes = true
        else literal.push([t === "-execdir" || t === "-okdir" ? copy(w, { loose: true }) : w, d])
      }
      if (inner.length > 0 && SHELLS.has(pyBasename(inner[0].text))) writes = true
      k = end + 1
      continue
    }
    if (FIND_NAME.has(t) && k + 1 < args.length) {
      names.push([args[k + 1].text, t === "-iname"])
      k += 2
      continue
    }
    if (FIND_VALUED.has(t)) {
      k += 2
      continue
    }
    if (t === "-delete") writes = true
    else if (!FIND_PLAIN.has(t)) narrow = false
    k += 1
  }
  if (!writes) return literal
  if (starts.length === 0) starts = [plain(".", newWord())]
  const keep = names.length > 0 && narrow ? names : null
  return starts.map((w) => [copy(w, { names: keep }), true] as Target).concat(literal)
}

function cd(words: Word[], base: string, loose: boolean, dirs: [string, boolean][]): [string, boolean] {
  let k = 0
  while (k < words.length && (isAssignment(words[k].text) || KEYWORDS.has(words[k].text))) k += 1
  if (k >= words.length) return [base, loose]
  const name = words[k].text
  if (name === "popd") return dirs.pop() ?? [base, true]
  if (name !== "cd" && name !== "pushd") return [base, loose]
  if (name === "pushd") dirs.push([base, loose])
  const args = words.slice(k + 1).filter((w) => !["-L", "-P", "-e", "-@", "--"].includes(w.text))
  if (args.length === 0 || args[0].dynamic || args[0].glob || /^[~+-]/.test(args[0].text)) return [base, true]
  const target = args[0].text
  return [pjoin(base, target), loose && !target.startsWith("/")]
}

/** [word, destructive] for every write target the command text shows. Throws INVALID_EVENT. */
export function analyse(text: unknown, depth = 0): Target[] {
  if (depth > MAX_DEPTH || typeof text !== "string") invalid()
  const nested: [number, string][] = []
  const tokens = tokenize(text, nested)
  let targets: Target[] = []
  let words: Word[] = []
  let bodies: string[] = []
  let pending: string | null = null
  let base = ""
  let loose = false
  const scopes: [string, boolean][] = []
  const dirs: [string, boolean][] = []
  let done = 0
  const all = [...tokens, ["op", ";"] as Token]
  for (let at = 0; at < all.length; at++) {
    const [kind, value] = all[at]
    if (pending !== null) {
      if (kind !== "word") invalid()
      if (pending === "<<<") bodies.push((value as Word).text)
      else if (pending !== "<") targets.push([rebase(value as Word, base, loose), false])
      pending = null
      continue
    }
    if (kind === "redir") pending = value as string
    else if (kind === "body") bodies = bodies.concat(value as string[])
    else if (kind === "word") words.push(value as Word)
    else {
      // The substitutions inside this command run from where it runs (`cd .claude && echo $(rm x)`).
      for (; done < nested.length && nested[done][0] < at; done++) {
        targets = targets.concat(analyse(nested[done][1], depth + 1).map(([w, d]) => [rebase(w, base, loose), d]))
      }
      targets = targets.concat(commandTargets(words, depth, bodies).map(([w, d]) => [rebase(w, base, loose), d]))
      ;[base, loose] = cd(words, base, loose, dirs)
      if (value === "(") scopes.push([base, loose])
      else if (value === ")" && scopes.length > 0) [base, loose] = scopes.pop() as [string, boolean]
      words = []
      bodies = []
    }
  }
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

/** Port of _rx: a glob that is no valid pattern (`[z-a]`) is INVALID_EVENT, as re.error is in Python. */
function rx(pattern: string, ci = false): RegExp {
  try {
    return new RegExp(`^(?:${globRegex(pattern)})$`, ci ? "si" : "s")
  } catch {
    invalid()
  }
}

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
    return parent === p ? p : pjoin(realPath(parent), basename(p))
  }
}

function lexists(p: string): boolean {
  try {
    lstatSync(p)
    return true
  } catch {
    return false
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
    const r = rx(comps.slice(0, k).join("/"))
    if (bases.some((b) => r.test(b))) return true
  }
  const r = rx(path)
  return destructive && bases.some((b) => ancestors(b).some((a) => r.test(a)))
}

function splitTop(body: string): string[] {
  const parts: string[] = []
  let depth = 0
  let start = 0
  for (let i = 0; i < body.length; i++) {
    const c = body[i]
    if (c === "{") depth += 1
    else if (c === "}") depth -= 1
    else if (c === "," && depth === 0) {
      parts.push(body.slice(start, i))
      start = i + 1
    }
  }
  return [...parts, body.slice(start)]
}

/** Brace expansion: `{.claude,tmp}` -> `.claude`, `tmp`. */
function braces(text: string): string[] {
  let depth = 0
  let start = -1
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === "{") {
      if (depth === 0) start = i
      depth += 1
    } else if (c === "}" && depth > 0) {
      depth -= 1
      const parts = depth === 0 ? splitTop(text.slice(start + 1, i)) : []
      if (parts.length > 1) {
        let out: string[] = []
        for (const part of parts) {
          out = out.concat(braces(text.slice(0, start) + part + text.slice(i + 1)))
          if (out.length > MAX_BRACE) invalid()
        }
        return out
      }
    }
  }
  return [text]
}

function gateNames(bases: string[], protectedRel: readonly string[]): Set<string> | null {
  const names = new Set(protectedRel.flatMap((rel) => rel.split("/")))
  let seen = 0
  const walk = (dir: string): boolean => {
    let entries
    try {
      entries = readdirSync(dir, { withFileTypes: true })
    } catch {
      return true
    }
    entries = entries.filter((e) => !(e.isDirectory() && GENERATED.has(e.name)))
    seen += entries.length
    if (seen > MAX_WALK) return false
    for (const e of entries) names.add(e.name)
    return entries.every((e) => !e.isDirectory() || walk(pjoin(dir, e.name)))
  }
  return bases.every(walk) ? names : null
}

/** First write target of `command` that is gate code, or null. Throws INVALID_EVENT. */
export function protectedTarget(command: unknown, cwd: string, root: string, protectedRel: readonly string[]): string | null {
  root = normPath(root)
  const bases = protectedRel.map((rel) => normPath(pjoin(root, rel)))
  const realBases = [...bases, ...bases.map(realPath)]
  const home = process.env.HOME ?? ""
  const anchors = [...new Set([...bases.flatMap((b) => ancestors(dirname(b))
    .filter((a) => a === root || a.startsWith(root + sep))), ...bases])]
  let names: Set<string> | null | undefined

  const reaches = (word: Word): boolean => {
    if (word.names === null) return true
    if (names === undefined) names = gateNames(bases, protectedRel)
    const known = names
    return known === null || (word.names as [string, boolean][]).some(([p, ci]) => {
      const r = rx(p, ci)
      return [...known].some((n) => r.test(n))
    })
  }

  const inside = (path: string, destructive: boolean): boolean => {
    for (const cand of [path, realPath(path)]) {
      for (const base of realBases) {
        if (cand === base || cand.startsWith(base + sep)) return true
        if (destructive && base.startsWith(cand.replace(/\/+$/, "") + sep)) return true
      }
    }
    return false
  }

  const hits = (word: Word, text: string, destructive: boolean): boolean => {
    if (text === "~+" || text === "~-" || text.startsWith("~+/") || text.startsWith("~-/")) {
      // `~+` is $PWD, `~-` is $OLDPWD: the rest is relative to the current or an unknown directory.
      if (text[1] === "-") word = copy(word, { loose: true })
      text = "." + text.slice(2)
    }
    const here = normPath(pjoin(cwd, word.base))
    for (const v of ["${CLAUDE_PROJECT_DIR}", "$CLAUDE_PROJECT_DIR"]) text = text.split(v).join(root)
    if (home) {
      for (const v of ["${HOME}", "$HOME"]) text = text.split(v).join(home)
      if (text === "~" || text.startsWith("~/")) text = home + text.slice(1)
    }
    if (!word.loose) for (const v of ["${PWD}", "$PWD"]) text = text.split(v).join(here)
    if (text.startsWith("~")) return false
    if (word.dynamic && text.includes("$")) {
      const tail = "/" + text.replace(/^\/+/, "")
      if (protectedRel.some((rel) => tail.endsWith("/" + rel) || tail.includes("/" + rel + "/"))) return true
      // Removing `"$R"/scripts` removes scripts/dual-cli when $R is the root: the literal part after the last
      // variable is a parent of a gate.
      const comps = text.split("/")
      let last = 0
      comps.forEach((c, k) => {
        if (c.includes("$")) last = k
      })
      const lit = comps.slice(last + 1).filter((c) => c !== "" && c !== ".").join("/")
      return destructive && lit !== "" && protectedRel.some((rel) => rel.startsWith(lit + "/"))
    }
    const rel = pjoin(word.base, text)
    if (word.loose && !rel.startsWith("/")) {
      return !word.glob && anchors.some((a) => {
        const cand = normPath(pjoin(a, rel))
        return inside(cand, false) && (!bases.includes(a) || lexists(cand))
      })
    }
    const path = normPath(pjoin(here, text))
    if (!reaches(word)) {
      // No name in the gates matches the patterns: the walk touches none of them, even when it starts inside
      // one. The names come from the files on disk, so a start path that is not there is judged as a plain write.
      if (lexists(path)) return false
      destructive = false
    }
    if (word.glob) return globHits(path, bases, destructive)
    return inside(path, destructive)
  }

  for (const [word, destructive] of analyse(command)) {
    if (braces(word.text).some((text) => hits(word, text, destructive))) return word.text
  }
  return null
}
