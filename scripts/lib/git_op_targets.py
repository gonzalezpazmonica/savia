#!/usr/bin/env python3
"""git_op_targets.py — directorio destino de cada `git commit` / `git add` REAL
de una orden de shell.

Lo usan los guards de rama (block-commit-to-main en bash y su port TS, y
validate-bash-global) para mirar la rama del repo sobre el que actúa la orden
y no la del checkout de la sesión.

Uso:    git_op_targets.py <cwd-base>      (la orden llega por stdin)
Salida: una línea por operación, `<op>\\t<dir>`, op ∈ {commit, add}.
        `<dir>` vacío = destino no resoluble: el llamante aplica el criterio
        conservador. Si la orden no se puede analizar (comillas sin cerrar…)
        y el texto contiene `git commit|add`, se emite la op sin destino.

Qué entiende:
  - `git -C <ruta>` con o sin comillas, varios -C acumulados, relativos.
  - `cd`/`pushd <ruta>` con o sin comillas y con `~`, encadenados con `&&`,
    `||`, `;` o salto de línea. `( … )` no filtra el cd al exterior; un cd en
    una tubería o en segundo plano no cambia el cwd siguiente; un cd a un
    directorio inexistente falla y no cambia el cwd (lo mismo que el shell).
  - Variables asignadas con literal en la misma orden (`W=/x; git -C $W …`),
    `$HOME` y `$PWD`. Cualquier otra variable deja el destino sin resolver.
  - Heredocs, comentarios y cadenas son texto, no órdenes.
  - Envoltorios (env, command, nohup, exec, time, nice, timeout, sudo,
    setsid, stdbuf); `bash|sh|zsh -c '…'`, `eval …`, `$( … )` y backticks se
    analizan recursivamente. `xargs … git` y `git` como argumento de otra
    orden (find -exec, watch…) → sin resolver.
  - `--git-dir`, `--work-tree`, `GIT_DIR=`, `GIT_WORK_TREE=` → sin resolver.

Sin dependencias externas; sin red.
"""
import os
import re
import sys

OPS = ("commit", "add")
LEGACY_RE = re.compile(r"git\s+(commit|add)\b", re.I)
SEPARATORS = {";", "&&", "||", "|", "|&", "&", "\n"}
GIT_ENV = ("GIT_DIR", "GIT_WORK_TREE")
UNKNOWN = None  # valor o cwd no resoluble
MAX_DEPTH = 6


class ParseError(Exception):
    pass


# ── Lexer ────────────────────────────────────────────────────────────────────
# Palabra = lista de segmentos: ("lit", s) | ("var", nombre) | ("sub", texto)
# | ("tilde", usuario). Tokens: ("word", segs) | ("op", s) | ("redir", s)
# | ("heredoc_delim", segs).

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


def _close_paren(s, i):
    """i: índice justo después de '('. Devuelve el índice del ')' que cierra."""
    depth = 1
    n = len(s)
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
        if i + 2 < n and s[i + 2] == "(":  # $(( aritmética ))
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
    tokens = []
    segs = []
    has_word = False
    heredocs = []          # [(delimitador, quitar_tabs)]
    want_delim = None      # quitar_tabs si la próxima palabra es delimitador
    i, n = 0, len(s)

    def flush():
        nonlocal segs, has_word, want_delim
        if has_word:
            merged = []  # fundir literales contiguos: `W=/x` es un solo literal
            for seg in segs:
                if seg[0] == "lit" and merged and merged[-1][0] == "lit":
                    merged[-1] = ("lit", merged[-1][1] + seg[1])
                else:
                    merged.append(seg)
            segs = merged
            if want_delim is not None:
                delim = "".join(v for k, v in segs if k == "lit")
                heredocs.append((delim, want_delim))
                want_delim = None
                tokens.append(("heredoc_delim", segs))
            else:
                tokens.append(("word", segs))
        segs = []
        has_word = False

    while i < n:
        c = s[i]
        if c == "\\":
            if i + 1 < n and s[i + 1] == "\n":
                i += 2
                continue
            if i + 1 < n:
                segs.append(("lit", s[i + 1]))
                has_word = True
            i += 2
            continue
        if c == "'":
            j = _skip_squote(s, i + 1)
            segs.append(("lit", s[i + 1:j - 1]))
            has_word = True
            i = j
            continue
        if c == '"':
            has_word = True
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
            tokens.append(("op", "\n"))
            i += 1
            for delim, strip in heredocs:  # cuerpo del heredoc: texto
                while i < n:
                    j = s.find("\n", i)
                    line = s[i:] if j < 0 else s[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if strip else line) == delim:
                        break
            heredocs = []
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
                strip = i < n and s[i] == "-"
                if strip:
                    i += 1
                want_delim = strip
                continue
            if i + 1 < n and s[i + 1] == "(":  # <( … ) / >( … )
                j = _close_paren(s, i + 2)
                tokens.append(("word", [("sub", s[i + 2:j])]))
                i = j + 1
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
            for op in ("||", "|&", "|"):
                if s.startswith(op, i):
                    tokens.append(("op", op))
                    i += len(op)
                    break
            continue
        if c == ";":
            flush()
            tokens.append(("op", ";"))
            i += 2 if s.startswith(";;", i) else 1
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
    return tokens


# ── Evaluación ───────────────────────────────────────────────────────────────

class Ctx:
    """Estado del análisis. `cwds` es el conjunto de cwds POSIBLES (un `cd`
    condicional puede no ejecutarse); None dentro de él = no resoluble."""

    def __init__(self, cwds, home):
        self.cwds = tuple(cwds)
        self.home = home
        self.vars = {}
        self.git_env = False
        self.out = []

    @property
    def cwd(self):
        return self.cwds[0] if len(self.cwds) == 1 else UNKNOWN

    def snapshot(self):
        return (self.cwds, dict(self.vars), self.git_env)

    def restore(self, snap):
        self.cwds, self.vars, self.git_env = snap


def _union(*groups):
    out = []
    for g in groups:
        for c in g:
            if c not in out:
                out.append(c)
    return tuple(out)


ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\+?=")


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
            if val in ctx.vars:
                v = ctx.vars[val]
            elif val == "HOME":
                v = ctx.home
            elif val == "PWD":
                v = ctx.cwd
            else:
                v = UNKNOWN
            if v is UNKNOWN:
                return UNKNOWN
            parts.append(v)
        else:
            return UNKNOWN
    return "".join(parts)


def is_assignment(segs):
    return bool(segs) and segs[0][0] == "lit" and ASSIGN_RE.match(segs[0][1]) is not None


def assignment(segs, ctx):
    first = segs[0][1]
    m = ASSIGN_RE.match(first)
    rest = list(segs[1:])
    value = first[m.end():]
    if value.startswith("~"):  # bash expande la tilde tras `=`
        tm = re.match(r"~([A-Za-z0-9_.-]*)", value)
        rest.insert(0, ("lit", value[len(tm.group(0)):]))
        rest.insert(0, ("tilde", tm.group(1)))
    elif value:
        rest.insert(0, ("lit", value))
    return m.group(1), expand(rest, ctx)


def set_var(ctx, name, val):
    ctx.vars[name] = val
    if name in GIT_ENV:
        ctx.git_env = True


def emit(ctx, op, d):
    ctx.out.append((op, "" if d is UNKNOWN else d))


def emit_text(ctx, text):
    for m in LEGACY_RE.finditer(text):
        emit(ctx, m.group(1).lower(), UNKNOWN)


def _build_items(tokens):
    """Agrupa en listas and-or: [("list", [(op_previo, [tubería…]), …])] con
    marcas ("push",)/("pop",) para subshells `( … )`."""
    items, cur, pipe, lst, prev = [], [], [], [], ";"

    def close_cmd():
        nonlocal cur
        pipe.append(cur)
        cur = []

    def close_pipe():
        nonlocal pipe, prev
        if any(pipe):
            lst.append((prev, pipe))
        pipe = []

    def close_list():
        nonlocal lst
        if lst:
            items.append(("list", lst))
        lst = []

    for t in tokens:
        if t[0] == "op" and t[1] in ("|", "|&"):
            close_cmd()
        elif t[0] == "op" and t[1] in ("&&", "||"):
            close_cmd()
            close_pipe()
            prev = t[1]
        elif t[0] == "op" and t[1] in (";", "&", "\n"):
            close_cmd()
            close_pipe()
            close_list()
            prev = ";"
            if t[1] == "&" and items and items[-1][0] == "list":
                items[-1] = ("bg", items[-1][1])
        elif t[0] == "op" and t[1] == "(":
            if not cur:
                close_pipe()
                close_list()
                items.append(("push",))
                prev = ";"
        elif t[0] == "op" and t[1] == ")":
            close_cmd()
            close_pipe()
            close_list()
            items.append(("pop",))
            prev = ";"
        else:
            cur.append(t)
    close_cmd()
    close_pipe()
    close_list()
    return items


def _run_pipe(pipe, ctx, depth):
    if len(pipe) > 1:  # cada elemento de una tubería es una subshell
        for toks in pipe:
            snap = ctx.snapshot()
            if toks:
                simple(toks, ctx, depth)
            ctx.restore(snap)
    elif pipe and pipe[0]:
        simple(pipe[0], ctx, depth)


def _run_list(lst, ctx, depth):
    """Lista and-or. El primer elemento se ejecuta seguro; uno tras `&&` puede
    saltarse, y uno tras `||` puede correr sin que haya corrido el anterior.
    Mientras la cadena sea solo `&&`, el cwd es el secuencial exacto; si hay
    `||`, cualquier estado visto (incluido el de partida) es posible. Tras la
    lista, es posible el estado tras cualquier elemento ya ejecutado."""
    start = ctx.cwds
    seen = ()
    and_only = True
    for k, (op, pipe) in enumerate(lst):
        if k > 0:
            if op == "||":
                and_only = False
            if not and_only:
                ctx.cwds = _union(seen, start)
        before = ctx.cwds
        _run_pipe(pipe, ctx, depth)
        if and_only:
            seen = _union(seen, ctx.cwds)
        else:
            # `cd X || echo fallo; git commit`: el estado de partida solo era
            # posible para el elemento tras `||` (si el cd fallara); no lo
            # arrastra a la lista siguiente salvo que ese elemento cambie el cwd.
            seen = _union(seen, [c for c in ctx.cwds if c not in before or c in seen])
    ctx.cwds = seen if seen else start


def run(command, ctx, depth=0):
    if depth > MAX_DEPTH:
        emit_text(ctx, command)
        return
    try:
        tokens = lex(command)
    except ParseError:
        emit_text(ctx, command)
        return
    stack = []
    for it in _build_items(tokens):
        if it[0] == "push":
            stack.append(ctx.snapshot())
        elif it[0] == "pop":
            if stack:
                ctx.restore(stack.pop())
        elif it[0] == "bg":  # segundo plano: subshell
            snap = ctx.snapshot()
            _run_list(it[1], ctx, depth)
            ctx.restore(snap)
        else:
            _run_list(it[1], ctx, depth)


def run_subs(segs, ctx, depth):
    for kind, val in segs:
        if kind == "sub":
            snap = ctx.snapshot()
            run(val, ctx, depth + 1)
            ctx.restore(snap)


def simple(toks, ctx, depth):
    words, skip = [], False
    for kind, val in toks:
        if kind == "redir":
            skip = True
        elif kind == "heredoc_delim":
            pass
        elif skip:
            skip = False
            run_subs(val, ctx, depth)
        else:
            words.append(val)
    for w in words:
        run_subs(w, ctx, depth)
    assigns = []
    while words and is_assignment(words[0]):
        assigns.append(assignment(words[0], ctx))
        words = words[1:]
    if not words:
        for name, val in assigns:
            set_var(ctx, name, val)
        return
    git_env = any(name in GIT_ENV for name, _ in assigns)
    argv = [expand(w, ctx) for w in words]
    execute(argv, words, ctx, depth, git_env)


SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}",
            "fi", "done", "esac"}
WRAPPER_ARGS = {
    "nice": {"-n"}, "stdbuf": {"-i", "-o", "-e"}, "exec": {"-a"},
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"},
    "time": set(), "nohup": set(), "command": set(), "builtin": set(), "setsid": set(),
}
NON_EXEC = {"echo", "printf", "cat", "grep", "rg", "sed", "awk", "tee", "jq", "test", "["}


def execute(argv, words, ctx, depth, git_env):
    unresolved = git_env or ctx.git_env
    while argv:
        if argv[0] is UNKNOWN:
            return
        base = os.path.basename(argv[0])
        if base in KEYWORDS:
            argv, words = argv[1:], words[1:]
        elif base == "env":
            argv, words = argv[1:], words[1:]
            while argv and argv[0] is not UNKNOWN:
                a = argv[0]
                if a in ("-u", "--unset", "-C", "--chdir", "-S"):
                    if a in ("-C", "--chdir", "-S"):
                        unresolved = True
                    argv, words = argv[2:], words[2:]
                elif a.startswith("-"):
                    argv, words = argv[1:], words[1:]
                elif ASSIGN_RE.match(a):
                    if ASSIGN_RE.match(a).group(1) in GIT_ENV:
                        unresolved = True
                    argv, words = argv[1:], words[1:]
                else:
                    break
        elif base == "timeout":
            argv, words = argv[1:], words[1:]
            while argv and argv[0] is not UNKNOWN and argv[0].startswith("-"):
                step = 2 if argv[0] in ("-s", "--signal", "-k", "--kill-after") else 1
                argv, words = argv[step:], words[step:]
            argv, words = argv[1:], words[1:]  # duración
        elif base == "xargs":
            # el destino depende de la entrada: sin resolver
            argv, words = argv[1:], words[1:]
            unresolved = True
            while argv and argv[0] is not UNKNOWN and argv[0].startswith("-"):
                step = 2 if argv[0] in ("-I", "-n", "-L", "-P", "-d", "-a", "-E", "-s") else 1
                argv, words = argv[step:], words[step:]
        elif base in WRAPPER_ARGS:
            takes = WRAPPER_ARGS[base]
            argv, words = argv[1:], words[1:]
            while argv and argv[0] is not UNKNOWN and argv[0].startswith("-") and argv[0] != "-":
                step = 2 if argv[0] in takes else 1
                argv, words = argv[step:], words[step:]
        else:
            break
    if not argv or argv[0] is UNKNOWN:
        return
    base = os.path.basename(argv[0])

    if base in ("cd", "pushd"):
        args = [a for a in argv[1:] if a is UNKNOWN or a == "-" or not a.startswith("-")]
        new = []
        for cwd in ctx.cwds:
            if not args:
                target = ctx.home if base == "cd" else UNKNOWN
            elif args[0] is UNKNOWN or args[0] == "-":
                target = UNKNOWN
            elif os.path.isabs(args[0]):
                target = os.path.normpath(args[0])
            elif cwd is UNKNOWN:
                target = UNKNOWN
            else:
                target = os.path.normpath(os.path.join(cwd, args[0]))
            if target is UNKNOWN or os.path.isdir(target):
                new.append(target)
            else:
                new.append(cwd)  # inexistente: el cd falla y el cwd no cambia
        ctx.cwds = _union(new)
        return
    if base == "popd":
        ctx.cwds = (UNKNOWN,)
        return
    if base in ("export", "declare", "typeset", "readonly", "local"):
        for w in words[1:]:
            if is_assignment(w):
                set_var(ctx, *assignment(w, ctx))
        return
    if base == "eval":
        rest = argv[1:]
        if any(a is UNKNOWN for a in rest):
            emit_text(ctx, " ".join(a for a in rest if a is not UNKNOWN))
            return
        run(" ".join(rest), ctx, depth + 1)
        return
    if base in SHELLS:
        rest = argv[1:]
        for k, a in enumerate(rest):
            if a is UNKNOWN or not a.startswith("-") or a.startswith("--"):
                return  # `bash script.sh`: no analizable aquí
            if "c" in a[1:]:
                if k + 1 < len(rest):
                    script = rest[k + 1]
                    if script is UNKNOWN:
                        emit_text(ctx, " ".join(x for x in rest if x is not UNKNOWN))
                        return
                    snap = ctx.snapshot()
                    inner = Ctx(ctx.cwds, ctx.home)
                    inner.git_env = ctx.git_env or unresolved
                    run(script, inner, depth + 1)
                    ctx.out.extend(inner.out)
                    ctx.restore(snap)
                return
        return
    if base == "git":
        git(argv, ctx, unresolved)
        return
    if base in NON_EXEC:
        return
    # `git` como argumento de otra orden (find -exec, watch, parallel…)
    for k, a in enumerate(argv[1:], start=1):
        if a is not UNKNOWN and os.path.basename(a) == "git":
            for b in argv[k + 1:]:
                if b in OPS:
                    emit(ctx, b, UNKNOWN)
                    return


def git(argv, ctx, unresolved):
    for cwd in ctx.cwds:
        _git_one(argv, ctx, unresolved, cwd)


def _git_one(argv, ctx, unresolved, gdir):
    k = 1
    while k < len(argv):
        a = argv[k]
        if a is UNKNOWN:
            # subcomando no resoluble: decide el texto restante
            for b in argv[k + 1:]:
                if b in OPS:
                    emit(ctx, b, UNKNOWN)
                    return
            return
        if a == "-C":
            nxt = argv[k + 1] if k + 1 < len(argv) else ""
            if nxt is UNKNOWN or gdir is UNKNOWN and not (nxt or "").startswith("/"):
                unresolved = True
            elif nxt:
                # git -C hace chdir físico: resolver enlaces simbólicos
                gdir = os.path.realpath(os.path.join(gdir or "/", nxt))
            k += 2
            continue
        if a in ("-c", "--namespace", "--config-env", "--super-prefix", "--exec-path"):
            k += 2
            continue
        if a in ("--git-dir", "--work-tree"):
            unresolved = True
            k += 2
            continue
        if a.startswith(("--git-dir=", "--work-tree=")):
            unresolved = True
            k += 1
            continue
        if a.startswith("-"):
            k += 1
            continue
        if a in OPS:
            emit(ctx, a, UNKNOWN if unresolved else gdir)
        return


def main():
    base = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else os.getcwd()
    ctx = Ctx([os.path.normpath(base)], os.environ.get("HOME") or UNKNOWN)
    run(sys.stdin.read(), ctx)
    for op, d in ctx.out:
        sys.stdout.write("%s\t%s\n" % (op, d))
    return 0


if __name__ == "__main__":
    sys.exit(main())
