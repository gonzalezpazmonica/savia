#!/usr/bin/env python3
"""git_op_targets.py — destino de cada `git commit` / `git add` de una orden de
shell, con criterio FAIL-CLOSED.

Lo usan los guards de rama (block-commit-to-main en bash y su port TS, y
validate-bash-global) para mirar la rama del repo sobre el que actúa la orden
y no la del checkout de la sesión.

Uso:    git_op_targets.py <cwd-base>      (la orden llega por stdin)
Salida: una línea por operación, `<op>\\t<dir>`, op ∈ {commit, add}.
        `<dir>` = destino reconocido con certeza.
        `<dir>` vacío = veredicto BLOQUEAR: la orden contiene `git` y
        `commit|add` y alguna parte no se entiende con certeza. Forma
        admitida: `git -C <ruta> commit …`.

Solo se reconoce con certeza (lista blanca, no lista negra de rodeos):
  - `git [-C <ruta literal>]… [-c user.*=…] [--no-pager] <subcomando> …`
  - `cd <ruta literal>` (con o sin comillas, `~`, `$HOME`, `$PWD`) que existe,
    encadenado con `;`, `&&` o salto de línea; si no, el cwd de la orden.
  - Variables asignadas con un literal en la misma orden (`W=/x; git -C $W …`).
  - Órdenes inertes (echo, printf, cat, grep…), comentarios y heredocs: su
    texto no es una orden. `$( … )` y backticks se analizan con las mismas
    reglas (forma habitual `git commit -m "$(cat <<'EOF' … EOF)"`).
  - Elementos de una tubería o en segundo plano: su `cd` no persiste.

Alias de git y órdenes externas `git-<x>`: se resuelve el alias en el destino
(`git config --get alias.<x>`); si no es un subcomando integrado que no hace
commit, se emite `commit` en el destino (vacío si no se conoce) aunque el
texto no diga `commit`. Orden con `argv0` no resoluble y la palabra `commit`
en el texto → `commit` con destino vacío. `gh pr|issue|…` es texto inerte.

Todo lo demás es incierto: subshells, funciones, alias de shell, bucles, `eval`,
`source`, `bash|sh -c`, `env -S`, `xargs`, envoltorios (`sudo`, `env`,
`timeout`…), git o subcomando no literal, opciones globales de git no
reconocidas, `GIT_DIR`/`GIT_WORK_TREE`/`CDPATH`, `cd` no resoluble o a un
directorio que el hook no ve, `cd` en una lista con `||`, heredoc sin comillas
con sustituciones, stdin de una tubería o un heredoc hacia una orden no inerte,
y cualquier orden no inerte cuyo texto mencione git y commit/add. Si hay algo
incierto y el texto (sin comillas ni barras) contiene las palabras `git` y
`commit|commit-tree|add`, se emite la op con destino vacío (BLOQUEAR). Si el
texto no las contiene, la orden no hace commit: no se emite nada.

Sin dependencias externas; sin red.
"""
import os
import re
import subprocess
import sys

UNKNOWN = None
MAX_DEPTH = 6
OPS = {"commit": "commit", "commit-tree": "commit", "add": "add", "stage": "add"}
GIT_WORD = re.compile(r"(?<![\w])git(?![\w])", re.I)
COMMIT_WORD = re.compile(r"(?<![\w-])commit(-tree)?(?![\w-])", re.I)
ADD_WORD = re.compile(r"(?<![\w-])(add|stage)(?![\w-])", re.I)
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\+?=")
# Variables que cambian el repo o el cd sin que se vea en la orden.
UNSAFE_VARS = {"GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_CONFIG_PARAMETERS",
               "GIT_CONFIG_COUNT", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "CDPATH"}
# Órdenes que demostradamente no ejecutan sus argumentos ni su stdin.
INERT = {"echo", "printf", "cat", "grep", "egrep", "fgrep", "rg", "wc", "head", "tail",
         "cut", "tr", "jq", "tee", "test", "[", "true", "false", ":", "ls", "pwd",
         "mkdir", "touch", "sleep", "date", "basename", "dirname", "realpath"}
# Subcomandos de gh que solo hablan con GitHub (no ejecutan texto local).
GH_INERT = {"pr", "issue", "release", "label", "search", "gist", "run", "workflow", "api"}
DECLARE = {"export", "declare", "typeset", "readonly", "local"}
CD = {"cd"}
# Cambian el cwd o ejecutan texto de forma no visible: lo que venga es incierto.
OPAQUE_BUILTINS = {"pushd", "popd", "source", ".", "eval", "alias", "unalias",
                   "function", "trap", "enable", "exec", "builtin", "command"}
KEYWORDS = {"if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
            "case", "esac", "select", "{", "}", "!", "[[", "]]", "coproc", "time"}
GIT_SAFE_FLAGS = {"--no-pager", "-P", "--paginate", "-p", "--no-optional-locks",
                  "--literal-pathspecs", "--no-replace-objects", "--no-advice"}
GIT_SAFE_CONFIG = re.compile(r"^(user\.(name|email)|commit\.gpgsign|core\.quotepath|"
                             r"color\.[\w.]+|advice\.[\w.]+|init\.defaultbranch)=", re.I)
# Subcomandos integrados de git (no son alias: un alias puede ser `commit`).
GIT_BUILTINS = set("""
am apply archive bisect blame branch bundle cat-file check-attr check-ignore
check-ref-format checkout cherry cherry-pick clean clone commit-graph config
count-objects describe diff diff-files diff-index diff-tree difftool fetch
for-each-ref format-patch fsck gc grep hash-object help init log ls-files
ls-remote ls-tree maintenance merge merge-base mergetool mktree mv name-rev notes
prune pull push range-diff read-tree rebase reflog remote repack replace reset
restore rev-list rev-parse revert rm shortlog show show-branch show-ref
sparse-checkout stash status submodule switch symbolic-ref tag update-index
update-ref var verify-commit verify-tag version whatchanged worktree write-tree
""".split())


class ParseError(Exception):
    pass


# ── Lexer ────────────────────────────────────────────────────────────────────
# Palabra = lista de segmentos: ("lit", s) | ("var", nombre) | ("sub", texto)
# | ("tilde", usuario). Tokens: ("word", segs) | ("op", s) | ("redir", s)
# | ("heredoc", holder) | ("procsub",).

def _skip_squote(s, i):
    j = s.find("'", i)
    if j < 0:
        raise ParseError("comilla simple sin cerrar")
    return j + 1


def _skip_dquote(s, i):
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        if c == "$" and i + 1 < n and s[i + 1] == "(":
            i = _close_paren(s, i + 2) + 1
            continue
        i += 1
    raise ParseError("comilla doble sin cerrar")


HEREDOC_OPEN = re.compile(r"<<-?[ \t]*(?:'([^'\n]*)'|\"([^\"\n]*)\"|\\?([A-Za-z0-9_.-]+))")


def _close_paren(s, i):
    """i: índice justo después de '('. Devuelve el índice del ')' que cierra.
    Salta comillas y cuerpos de heredoc (`$(cat <<'EOF' … EOF)`)."""
    depth = 1
    n = len(s)
    pending = []  # delimitadores de heredoc cuyo cuerpo empieza en el próximo \n
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            i = _skip_squote(s, i + 1)
            continue
        if c == '"':
            i = _skip_dquote(s, i + 1)
            continue
        if c == "<" and s.startswith("<<", i) and not s.startswith("<<<", i):
            m = HEREDOC_OPEN.match(s, i)
            if m:
                pending.append((next(g for g in m.groups() if g is not None),
                                s.startswith("<<-", i)))
                i = m.end()
                continue
        if c == "\n" and pending:
            i += 1
            for delim, strip in pending:
                while i < n:
                    j = s.find("\n", i)
                    line = s[i:] if j < 0 else s[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if strip else line) == delim:
                        break
            pending = []
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ParseError("paréntesis sin cerrar")


def _read_dollar(s, i, segs):
    """s[i] == '$'. Añade el segmento y devuelve el índice siguiente."""
    n = len(s)
    if i + 1 >= n:
        segs.append(("lit", "$"))
        return i + 1
    c = s[i + 1]
    if c == "(":
        j = _close_paren(s, i + 2)
        if s[i + 2:i + 3] == "(":  # $(( aritmética )): valor desconocido
            segs.append(("var", "?arith"))
        else:
            segs.append(("sub", s[i + 2:j]))
        return j + 1
    if c == "{":
        j = s.find("}", i + 2)
        if j < 0:
            raise ParseError("llave sin cerrar")
        inner = s[i + 2:j]
        ok = re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", inner)
        segs.append(("var", inner if ok else "?complex"))
        return j + 1
    m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", s[i + 1:])
    if m:
        segs.append(("var", m.group(0)))
        return i + 1 + len(m.group(0))
    if c in "@*#?$!-0123456789":
        segs.append(("var", "?special"))
        return i + 2
    segs.append(("lit", "$"))
    return i + 1


def lex(s):
    tokens, segs = [], []
    has_word = quoted = False
    heredocs = []        # holders pendientes de cuerpo
    want_delim = None    # quitar_tabs si la próxima palabra es delimitador
    i, n = 0, len(s)

    def flush():
        nonlocal segs, has_word, want_delim, quoted
        if has_word:
            merged = []  # fundir literales contiguos: `W=/x` es un solo literal
            for seg in segs:
                if seg[0] == "lit" and merged and merged[-1][0] == "lit":
                    merged[-1] = ("lit", merged[-1][1] + seg[1])
                else:
                    merged.append(seg)
            if want_delim is not None:
                holder = {"delim": "".join(v for k, v in merged if k == "lit"),
                          "strip": want_delim, "quoted": quoted, "body": None}
                heredocs.append(holder)
                tokens.append(("heredoc", holder))
                want_delim = None
            else:
                tokens.append(("word", merged))
        segs, has_word, quoted = [], False, False

    while i < n:
        c = s[i]
        if c == "\\":
            if s[i + 1:i + 2] == "\n":
                i += 2
                continue
            quoted = True
            if i + 1 < n:
                segs.append(("lit", s[i + 1]))
                has_word = True
            i += 2
            continue
        if c == "'":
            j = _skip_squote(s, i + 1)
            segs.append(("lit", s[i + 1:j - 1]))
            has_word = quoted = True
            i = j
            continue
        if c == '"':
            has_word = quoted = True
            i += 1
            buf = []
            while True:
                if i >= n:
                    raise ParseError("comilla doble sin cerrar")
                d = s[i]
                if d == '"':
                    i += 1
                    break
                if d == "\\" and i + 1 < n and s[i + 1] in '$`"\\\n':
                    buf.append(s[i + 1])
                    i += 2
                    continue
                if d in "$`":
                    if buf:
                        segs.append(("lit", "".join(buf)))
                        buf = []
                    if d == "$":
                        i = _read_dollar(s, i, segs)
                    else:
                        j = s.find("`", i + 1)
                        if j < 0:
                            raise ParseError("backtick sin cerrar")
                        segs.append(("sub", s[i + 1:j]))
                        i = j + 1
                    continue
                buf.append(d)
                i += 1
            if buf:
                segs.append(("lit", "".join(buf)))
            continue
        if c == "$":
            has_word = True
            i = _read_dollar(s, i, segs)
            continue
        if c == "`":
            j = s.find("`", i + 1)
            if j < 0:
                raise ParseError("backtick sin cerrar")
            segs.append(("sub", s[i + 1:j]))
            has_word = True
            i = j + 1
            continue
        if c == "~" and not has_word:
            m = re.match(r"~([A-Za-z0-9_.-]*)", s[i:])
            segs.append(("tilde", m.group(1)))
            has_word = True
            i += len(m.group(0))
            continue
        if c == "#" and not has_word:
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if c in " \t":
            flush()
            i += 1
            continue
        if c == "\n":
            flush()
            i += 1
            for h in heredocs:
                body = []
                while i < n:
                    j = s.find("\n", i)
                    line = s[i:] if j < 0 else s[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if h["strip"] else line) == h["delim"]:
                        break
                    body.append(line)
                h["body"] = "\n".join(body)
            heredocs = []
            tokens.append(("op", "\n"))
            continue
        if c in "<>":
            if has_word and all(k == "lit" and v.isdigit() for k, v in segs):
                segs, has_word = [], False  # descriptor numérico (2>)
            flush()
            if s.startswith("<<<", i):
                tokens.append(("redir", "<<<"))
                i += 3
                continue
            if s.startswith("<<", i):
                i += 2
                want_delim = s[i:i + 1] == "-"
                if want_delim:
                    i += 1
                continue
            if s[i + 1:i + 2] == "(":  # <( … ) / >( … )
                i = _close_paren(s, i + 2) + 1
                tokens.append(("procsub",))
                continue
            m = re.match(r">>|>&|>\||<&|<>|>|<", s[i:])
            tokens.append(("redir", m.group(0)))
            i += len(m.group(0))
            continue
        if c == "&":
            flush()
            if s.startswith("&&", i):
                tokens.append(("op", "&&"))
                i += 2
            elif s.startswith("&>", i):
                tokens.append(("redir", "&>"))
                i += 3 if s.startswith("&>>", i) else 2
            else:
                tokens.append(("op", "&"))
                i += 1
            continue
        if c == "|":
            flush()
            op = "||" if s.startswith("||", i) else "|&" if s.startswith("|&", i) else "|"
            tokens.append(("op", op))
            i += len(op)
            continue
        if c == ";":
            flush()
            op = ";;" if s.startswith(";;", i) else ";"
            tokens.append(("op", op))
            i += len(op)
            continue
        if c in "()":
            flush()
            tokens.append(("op", c))
            i += 1
            continue
        segs.append(("lit", c))
        has_word = True
        i += 1
    flush()
    if want_delim is not None or any(h["body"] is None for h in heredocs):
        raise ParseError("heredoc sin cuerpo")
    return tokens


# ── Evaluación ───────────────────────────────────────────────────────────────

class Ctx:
    def __init__(self, cwd, home):
        self.cwd = cwd
        self.home = home
        self.vars = {}
        self.out = []
        self.uncertain = False
        self.cd_unknown = False  # lista con `||` y cd: cwd incierto


def expand(segs, ctx):
    parts = []
    for kind, val in segs:
        if kind == "lit":
            parts.append(val)
        elif kind == "tilde":
            if val or not ctx.home:
                return UNKNOWN
            parts.append(ctx.home)
        elif kind == "var":
            v = ctx.vars.get(val, ctx.home if val == "HOME" else ctx.cwd if val == "PWD" else UNKNOWN)
            if v is UNKNOWN:
                return UNKNOWN
            parts.append(v)
        else:
            return UNKNOWN
    return "".join(parts)


def words_text(words):
    return " ".join("".join(v for k, v in w if k in ("lit", "sub")) for w in words)


# `add` como acción de otro subcomando, no como `git add`: `git worktree add`
# crea otro checkout y `git remote add` escribe config; ninguno toca el índice
# ni la rama del repo. (`submodule add` sí indexa y `notes add` sí hace commit:
# siguen contando.) Solo se neutraliza la pareja literal; un `add` suelto en
# otra parte de la orden sigue contando. `worktree|remote` tiene que ser el
# subcomando de `git` (tras sus opciones globales, con el valor de `-C`,
# `--git-dir`, etc. consumido aparte): `git -C ../remote add .` es un
# `git add` real y sigue contando.
_GIT_GLOBAL_OPT = (r"(?:-[Cc]\s+\S+"
                   r"|--(?:git-dir|work-tree|namespace|super-prefix|config-env)(?:=\S+|\s+\S+)"
                   r"|--[\w-]+=\S+"
                   r"|--(?!git-dir\b|work-tree\b|namespace\b|super-prefix\b|config-env\b)[\w-]+"
                   r"|-(?![Cc]\b)\w+)")
SUBCMD_ADD = re.compile(r"((?<![\w./-])git(?:\s+%s)*\s+(?:worktree|remote)\s+)add(?![\w-])"
                        % _GIT_GLOBAL_OPT, re.I)


def plain(text):
    """Texto sin comillas ni barras y sin el `add` de `git worktree|remote add`."""
    return SUBCMD_ADD.sub(r"\1-", re.sub(r"[\"'\\]", "", text))


def mentions(text):
    """El texto (sin comillas ni barras) contiene `git` y `commit|add`."""
    t = plain(text)
    return bool(GIT_WORD.search(t)) and bool(COMMIT_WORD.search(t) or ADD_WORD.search(t))


def assign(segs, ctx):
    first = segs[0][1]
    m = ASSIGN_RE.match(first)
    rest, value = list(segs[1:]), first[m.end():]
    if value.startswith("~"):  # bash expande la tilde tras `=`
        tm = re.match(r"~([A-Za-z0-9_.-]*)", value)
        rest[:0] = [("tilde", tm.group(1)), ("lit", value[len(tm.group(0)):])]
    elif value:
        rest.insert(0, ("lit", value))
    return m.group(1), expand(rest, ctx)


def is_assign(segs):
    return bool(segs) and segs[0][0] == "lit" and ASSIGN_RE.match(segs[0][1]) is not None


def set_var(ctx, name, val):
    if name in UNSAFE_VARS:
        ctx.uncertain = True
    ctx.vars[name] = val


def run(command, ctx, depth=0):
    if depth > MAX_DEPTH:
        ctx.uncertain = True
        return
    try:
        tokens = lex(command)
    except ParseError:
        ctx.uncertain = True
        return
    # listas separadas por ; \n & → and-or (&&, ||) → tuberías (|, |&)
    lst, pipe, cur, prev = [], [], [], None
    for t in tokens + [("op", ";")]:
        if t[0] != "op":
            cur.append(t)
            continue
        op = t[1]
        if op in ("(", ")", ";;"):
            ctx.uncertain = True  # subshell, función, case
            return
        pipe.append(cur)
        cur = []
        if op in ("|", "|&"):
            continue
        lst.append((prev, pipe))
        pipe = []
        if op in ("&&", "||"):
            prev = op
            continue
        run_list([(o, p) for o, p in lst if any(p)], ctx, depth, background=op == "&")
        lst, prev = [], None


def argv0(toks, ctx):
    for kind, val in toks:
        if kind == "word" and not is_assign(val):
            return expand(val, ctx)
    return None


def run_list(lst, ctx, depth, background):
    saved = (ctx.cwd, dict(ctx.vars))
    moves = [k for k, (_, p) in enumerate(lst) if len(p) == 1
             and os.path.basename(argv0(p[0], ctx) or "") in CD | OPAQUE_BUILTINS]
    # `cd X || …`: qué elementos corren depende de un fallo; cwd incierto
    # durante la lista y después.
    if moves and any(o == "||" for o, _ in lst):
        ctx.cwd, ctx.cd_unknown = UNKNOWN, True
    # `false && cd X; git commit`: un cd que no es el primero puede no correr.
    # Dentro de la cadena `&&` lo siguiente solo corre si corrió; tras ella, no.
    after_unknown = any(k > 0 for k in moves)
    for _, pipe in lst:
        if len(pipe) > 1:
            stdin = ""
            for toks in pipe:
                snap = (ctx.cwd, dict(ctx.vars))
                stdin += " " + simple(toks, ctx, depth, stdin)
                ctx.cwd, ctx.vars = snap
        elif pipe[0]:
            simple(pipe[0], ctx, depth, None)
    if ctx.cd_unknown or after_unknown:
        ctx.cwd, ctx.cd_unknown = UNKNOWN, False
    if background:  # segundo plano: subshell
        ctx.cwd, ctx.vars = saved


def run_subs(segs, ctx, depth):
    for kind, val in segs:
        if kind == "sub":
            inner = Ctx(ctx.cwd, ctx.home)
            inner.vars = dict(ctx.vars)
            run(val, inner, depth + 1)
            ctx.out.extend(inner.out)
            ctx.uncertain |= inner.uncertain


def simple(toks, ctx, depth, piped):
    """Ejecuta una orden simple. `piped`: texto que llega por la tubería (None
    si no hay). Devuelve su texto, para la orden siguiente de la tubería."""
    words, stdin, stdin_known, redir = [], piped, True, None
    for kind, *val in toks:
        if kind == "procsub":
            ctx.uncertain = True
        elif kind == "heredoc":
            h = val[0]
            if not h["quoted"]:  # bash expande $( … ), `…` y $VAR del cuerpo
                if "$(" in h["body"] or "`" in h["body"]:
                    ctx.uncertain = True
                stdin_known = "$" not in h["body"]
            stdin = h["body"]
        elif kind == "redir":
            redir = val[0]
        elif redir is not None:
            run_subs(val[0], ctx, depth)
            if redir == "<<<":
                v = expand(val[0], ctx)
                stdin, stdin_known = words_text([val[0]]), v is not UNKNOWN
            redir = None
        else:
            words.append(val[0])
    for w in words:
        run_subs(w, ctx, depth)
    text = words_text(words) + ("\n" + stdin if stdin else "")
    assigns = []
    while words and is_assign(words[0]):
        assigns.append(assign(words[0], ctx))
        words = words[1:]
    if not words:
        for name, val in assigns:
            set_var(ctx, name, val)
        return text
    if any(name in UNSAFE_VARS for name, _ in assigns):
        ctx.uncertain = True
    argv = [expand(w, ctx) for w in words]
    if argv[0] is UNKNOWN:
        ctx.uncertain = True  # `$SUDO git commit`, `$(which git) …`
        # `$x commit` con x=git ofuscado: el texto no dice `git`, pero la orden
        # puede serlo. Con `commit` en el texto → BLOQUEAR sin exigir la mención.
        if COMMIT_WORD.search(re.sub(r"[\"'\\]", "", text)):
            ctx.out.append(("commit", ""))
        return text
    base = os.path.basename(argv[0])
    if base in KEYWORDS or base in OPAQUE_BUILTINS:
        ctx.uncertain = True
    elif base in CD:
        do_cd(argv, ctx)
    elif base in DECLARE:
        for w in words[1:]:
            if is_assign(w):
                set_var(ctx, *assign(w, ctx))
    elif base == "git":
        do_git(argv, ctx)
    elif base in INERT and not (base == "rg" and any(
            a is UNKNOWN or a.startswith("--pre") for a in argv[1:])):
        pass
    elif base == "gh" and len(argv) > 1 and argv[1] in GH_INERT:
        pass  # `gh pr create --body "… git commit …"`: texto hacia GitHub
    elif UNKNOWN in argv or not stdin_known or mentions(text):
        # orden no inerte: puede ejecutar sus argumentos o su stdin
        ctx.uncertain = True
    return text


def do_cd(argv, ctx):
    args = [a for a in argv[1:] if a is UNKNOWN or a == "-" or not a.startswith("-")]
    if args and args[0] == "--":
        args = args[1:]
    if not args:
        target = ctx.home or UNKNOWN
    elif args[0] is UNKNOWN or args[0] == "-":
        target = UNKNOWN
    elif os.path.isabs(args[0]):
        target = os.path.normpath(args[0])
    elif ctx.cwd is UNKNOWN or (os.environ.get("CDPATH") and args[0] not in (".", "..")
                                and not args[0].startswith(("./", "../"))):
        target = UNKNOWN
    else:
        target = os.path.normpath(os.path.join(ctx.cwd, args[0]))
    if target is not UNKNOWN and not os.path.isdir(target):
        target = UNKNOWN  # el hook no lo ve: nunca se deduce que el cd falla
    ctx.cwd = UNKNOWN if ctx.cd_unknown else target


def do_git(argv, ctx):
    target = ctx.cwd
    k = 1
    while k < len(argv):
        a = argv[k]
        if a is UNKNOWN:
            ctx.uncertain = True
            return
        if a == "-C":
            nxt = argv[k + 1] if k + 1 < len(argv) else UNKNOWN
            if nxt is UNKNOWN or (target is UNKNOWN and not os.path.isabs(nxt)):
                target = UNKNOWN
            elif nxt:
                target = os.path.realpath(os.path.join(target or "/", nxt))
            k += 2
            continue
        if a == "-c":
            nxt = argv[k + 1] if k + 1 < len(argv) else UNKNOWN
            if nxt is UNKNOWN or not GIT_SAFE_CONFIG.match(nxt):
                ctx.uncertain = True  # alias.*, core.worktree, *.editor…
            k += 2
            continue
        if a in GIT_SAFE_FLAGS:
            k += 1
            continue
        if a.startswith("-"):
            ctx.uncertain = True  # --git-dir, --work-tree, --exec-path…
            return
        if a in OPS:
            if target is UNKNOWN:
                ctx.uncertain = True
            else:
                ctx.out.append((OPS[a], target))
        elif a not in GIT_BUILTINS and not alias_is_safe(a, target):
            # alias (`git ci` con alias.ci=commit, también global) u orden
            # externa git-<a>: puede hacer commit → se trata como commit en el
            # destino, sin exigir que el texto diga `commit`.
            ctx.out.append(("commit", "" if target is UNKNOWN else target))
        return


def alias_is_safe(name, target):
    """True si `name` es un alias de git cuyo subcomando es integrado y no hace
    commit (p. ej. alias.st=status). Alias de shell (`!…`), alias de alias,
    órdenes externas, destino desconocido o cualquier error → False."""
    if target is UNKNOWN or not os.path.isdir(target):
        return False
    try:
        res = subprocess.run(["git", "-C", target, "config", "--get", "alias." + name],
                             capture_output=True, text=True, timeout=2)
    except Exception:
        return False
    if res.returncode != 0:
        return False
    words = res.stdout.split()
    return bool(words) and words[0] in GIT_BUILTINS and words[0] not in OPS


def main():
    base = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else os.getcwd()
    command = sys.stdin.read()
    ctx = Ctx(os.path.normpath(base), os.environ.get("HOME") or UNKNOWN)
    try:
        run(command, ctx)
    except Exception:  # RecursionError incluido: fail-closed
        ctx.uncertain = True
    out = list(dict.fromkeys(ctx.out))
    if ctx.uncertain and mentions(command):
        t = plain(command)
        if COMMIT_WORD.search(t):
            out.append(("commit", ""))
        if ADD_WORD.search(t):
            out.append(("add", ""))
    for op, d in out:
        sys.stdout.write("%s\t%s\n" % (op, d))
    return 0


if __name__ == "__main__":
    sys.exit(main())
