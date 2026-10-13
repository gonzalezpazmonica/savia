#!/usr/bin/env python3
"""Guard de cúpulas (SE-436 S5, D30-4): núcleo del hook dome-guard.sh.

Port de `crates/space-orchestrator/src/dome_guard.rs` de Savia Space @ 9137d4f, ronda 5 (y del
subconjunto de su `shell.rs` que necesita). Más estricto que el original en dos puntos que Space no
necesita: un cwd de sesión dentro de una cúpula la toca siempre (en Space el proyecto es el workspace) y
el registro de cúpulas (base y local) no lo escribe el motor. Gemelo TypeScript: `scripts/opencode-plugin/savia-gates/lib/dome-guard.ts`.
Misma entrada, misma decisión: lo comprueba `tests/hooks/test-dome-guard-parity.bats`.

- Escritura (edit, write, patch, multiedit, notebookedit o un bash que escriba) dentro de la raíz de
  una cúpula del registro fusionado: `ask` con el aviso de propuesta («Guardar como nota»).
- Lectura de una cúpula N2 o superior no adjunta, con proveedor de nube: `ask`. N3 o superior: `deny`.
- Fuera de cualquier cúpula: `pass` (decide la configuración del motor).
- Falla cerrado: registro ilegible → `ask` en todo lo que mira; sin contexto de sesión → nube sin adjuntos.

Principio (causa común de las variantes de las revisiones r1-r3): el guard no enumera formas peligrosas,
enumera las seguras. Solo un lector conocido (READ_ONLY) con rutas literales se analiza con precisión;
cualquier otra orden, con cualquier programa (también envoltorios, `sh -c`, `eval`, `$(...)`, comodines,
llaves, `clave=valor`), alcanza una cúpula o el registro si alguna palabra cae en ellos o en un ancestro.
Cualquier error que no sea un ENOENT real, cualquier tope que corte un análisis y cualquier herramienta
desconocida con una ruta que los toque preguntan.
El mismo principio aplica al directorio de trabajo (rondas 7-9 de Space): bash se analiza con su directorio
si se sabe dónde corre (entrada objeto con las claves del esquema de bash de los dos motores y `workdir`
ausente o texto no vacío; en Claude Code, `cwd` del payload de texto). Si no, veredicto cerrado y de coste
constante: deny si la sesión es de nube y hay alguna cúpula N3 o superior, ask en el resto; nunca pass ni
rebaja. Con el directorio conocido, una N3 en nube que la orden nombra o cuya ruta toca se deniega aunque el
programa no sea un lector conocido (`base64`, `cp`, `curl -F file=@`). Una llamada sin herramienta se evalúa
como cada herramienta y gana la más estricta.
Falsos positivos aceptados (preguntan sin tocar una cúpula): un programa desconocido con `.` o una variable
(`prettier --write .`), `rm -rf $X`, `mv a ..` y un literal entre comillas de un guion `-c`/`-e` que nombra
un ancestro de una cúpula o del registro.

Uso: `dome_guard.py --root DIR [--hook]` con el payload PreToolUse por stdin. Imprime
`{"decision", "reason"}`; con `--hook`, la salida PreToolUse de Claude Code (nada si pasa).
"""
from __future__ import annotations

import json
import os
import re
import stat
import sys

WRITE_NOTICE = ("Usa una propuesta: Guardar como nota. El motor no escribe en una cúpula; "
                "la propuesta la revisa la persona")
UNKNOWN_NOTICE = ("la orden toca una cúpula y no es una lectura conocida; si escribe, usa una propuesta: "
                  "Guardar como nota")
REGISTRY_NOTICE = ("el registro de cúpulas no lo cambia el motor: lo cambia la persona desde Savia Space "
                   "o con savia-vaults dome create")
PAYLOAD_NOTICE = "la llamada no se puede leer; no se sabe si toca una cúpula"
UNKNOWN_TOOL_NOTICE = ("el guard no conoce esta herramienta y una de sus rutas toca una cúpula; si escribe, usa una "
                       "propuesta: Guardar como nota")
UNKNOWN_CWD_NOTICE = ("no se sabe en qué directorio corre la orden, así que podría leer o escribir una cúpula: "
                      "confirmar a mano")
CLOUD_DENIED = ("contenido N3 o superior no sale a la nube: esta cúpula no se lee con el motor. "
                "Pide a la persona una tarea del carril local; el resultado lo ve ella y no vuelve a ti")

WRITERS = {"cp", "mv", "rm", "touch", "tee", "sed", "dd", "install", "ln", "truncate", "chmod", "chown",
           "mkdir", "rmdir", "tar", "unzip", "rsync", "git", "python3", "python", "node", "bash", "sh",
           "perl", "ruby", "patch", "cpio", "zip", "7z", "scp", "curl", "wget", "eval",
           "rename", "unlink", "shred", "chgrp", "chattr", "setfacl"}
# Herramientas de escritura: las de OpenCode y las de Claude Code (notebookedit), en minúsculas.
WRITE_TOOLS = {"edit", "write", "patch", "multiedit", "notebookedit", "apply_patch"}
FILE_TOOLS = {"read", "grep", "glob", "list"}
READ_ONLY = {"cat", "ls", "head", "tail", "grep", "wc", "stat", "du", "diff", "nl"}
TRAVERSERS = {"grep", "rg", "find", "tree", "du", "ls", "tar", "cp", "rsync", "zip", "cpio", "7z", "scp"}
WRITE_PATH_KEYS = ("filePath", "file_path", "path", "notebook_path")
# Esquema de la herramienta bash de los dos motores: OpenCode (command, workdir, timeout, description) y
# Claude Code (además run_in_background, dangerouslyDisableSandbox). Otra clave podría fijar el directorio.
BASH_KEYS = {"command", "workdir", "timeout", "description", "run_in_background", "dangerouslyDisableSandbox"}
# Profundidad con la que una búsqueda recursiva mira enlaces que entran en una cúpula.
LINK_DEPTH = 3
# Tope de entradas por directorio al buscar enlaces; un directorio mayor cuenta como que tiene uno.
MAX_ENTRIES = 5000
# Programas que mueven, borran o quitan permisos a lo que nombran (más `git mv/rm/clean/stash -u` y
# `find -delete/-exec`, ver `destroys`): sobre un ancestro de una cúpula o del registro, se los llevan.
DESTROYERS = {"mv", "rm", "rmdir", "unlink", "shred", "rename", "chmod", "chown", "chgrp", "chattr", "setfacl"}
# Programas que ejecutan otro programa con sus argumentos: lo que hagan no se ve, cuentan como destructivos.
WRAPPERS = {"env", "command", "builtin", "exec", "nice", "nohup", "timeout", "stdbuf", "time", "ionice", "setsid",
            "sudo", "doas", "xargs", "chronic", "unbuffer", "flock", "watch", "parallel", "strace", "ltrace",
            "nsenter", "unshare", "chroot", "fakeroot", "systemd-run", "busybox"}
# Programas que el guard conoce: tras un envoltorio, uno que no esté aquí cuenta como que recorre lo que nombra.
# Linters y filtros habituales: no escriben salvo por redirección, así que `.` en ellos no es destructivo.
KNOWN_PROGRAMS = (WRITERS | DESTROYERS | READ_ONLY | TRAVERSERS | {
    "echo", "printf", "true", "false", "test", "cd", "pwd", "cargo", "npm", "make", "go", "pytest",
    "jq", "yq", "ruff", "eslint", "shellcheck", "sort", "uniq", "cut", "tr", "awk", "mypy", "tsc"})
# Intérpretes cuyo guion `-c`/`-e` se mira por las rutas literales entre comillas que nombra.
INTERPRETERS = {"python", "python3", "node", "perl", "ruby"}
QUOTED = re.compile(r"'([^'\\]*)'|\"([^\"\\]*)\"")
# Sandboxes cuyo comando va tras `--` (las opciones de antes son monturas).
SANDBOXES = {"bwrap"}
# Intérpretes de shell cuyo `-c` es otra orden que se analiza como tal.
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "mksh"}
# Claves de una herramienta desconocida que pueden llevar una ruta.
PATH_KEY = re.compile(r"path|file|dir|dest|target|source|^(src|from|to|old|new)$", re.I)
# Profundidad máxima de órdenes anidadas (`sh -c`, `$(...)`, `eval`): más allá, no se analiza y pregunta.
MAX_NESTING = 4
LEVELS = {"N1": 1, "N2": 2, "": 2, "N3": 3, "N4": 4, "N4B": 4}
# Espacio en blanco ASCII explícito: el gemelo TS usa el mismo conjunto (los `\s` de Python y JS difieren).
WS = " \t\n\r\x0b\x0c"


def level_name(n: int) -> str:
    return f"N{n}"


def parse_level(s: str) -> int | None:
    return LEVELS.get(s.strip(WS).upper())


def tool_permission(tool: str) -> str:
    t = (tool or "").lower()
    return "list" if t == "ls" else t


# ── Rutas ─────────────────────────────────────────────────────────────────────

def split_path(p: str) -> tuple[bool, list[str]]:
    """Componentes como los de Rust: raíz aparte, sin `.` ni vacíos (los `..` se conservan)."""
    return p.startswith("/"), [c for c in p.split("/") if c not in ("", ".")]


def join_parts(absolute: bool, parts: list[str]) -> str:
    return ("/" if absolute else "") + "/".join(parts)


def join(base: str, raw: str) -> str:
    return raw if raw.startswith("/") else (base.rstrip("/") + "/" + raw if base else raw)


def under(path: str, root: str) -> bool:
    (pa, pp), (ra, rp) = split_path(path), split_path(root)
    return pa == ra and pp[:len(rp)] == rp


def real_path(p: str, depth: int = 40) -> str | None:
    """Sigue los enlaces componente a componente y aplica `..` sobre lo ya resuelto."""
    if depth == 0:
        return None
    absolute, parts = split_path(p)
    cur_abs, cur = absolute, []
    for c in parts:
        if c == "..":
            if cur:
                cur.pop()
            continue
        cur.append(c)
        here = join_parts(cur_abs, cur)
        if os.path.islink(here):
            try:
                target = os.readlink(here)
            except OSError:
                return None
            joined = target if target.startswith("/") else join(join_parts(cur_abs, cur[:-1]), target)
            resolved = real_path(joined, depth - 1)
            if resolved is None:
                return None
            cur_abs, cur = split_path(resolved)
    return join_parts(cur_abs, cur)


def touches(root: str, project: str, raw: str, recursive: bool) -> bool:
    a, r = real_path(join(project, raw)), real_path(root)
    if a is None or r is None:
        return True
    a, r = a.lower(), r.lower()
    return under(a, r) or (recursive and under(r, a))


def lexical(p: str) -> str:
    absolute, parts = split_path(p)
    out: list[str] = []
    for c in parts:
        if c == "..":
            if out:
                out.pop()
        else:
            out.append(c)
    return join_parts(absolute, out)


def canonical(p: str) -> str | None:
    try:
        return os.path.realpath(p, strict=True) if p else None
    except OSError:
        return None


def resolve(p: str) -> str:
    """Ruta real: el último ancestro que existe, canonizado, más el resto."""
    p = lexical(p)
    absolute, parts = split_path(p)
    for i in range(len(parts), -1, -1):
        c = canonical(join_parts(absolute, parts[:i]))
        if c is not None:
            rest = parts[i:]
            return c if not rest else c.rstrip("/") + "/" + "/".join(rest)
    return p


def file_name(p: str) -> str:
    parts = split_path(p)[1]
    return parts[-1] if parts and parts[-1] != ".." else ""


def strip_prefix(p: str, base: str) -> str | None:
    (pa, pp), (ba, bp) = split_path(p), split_path(base)
    if pa != ba or pp[:len(bp)] != bp:
        return None
    return "/".join(pp[len(bp):])


def wildcard(pattern: str, text: str) -> bool:
    pi = ti = mark = 0
    star = None
    while ti < len(text):
        if pi < len(pattern) and (pattern[pi] == "?" or pattern[pi] == text[ti]):
            pi += 1
            ti += 1
        elif pi < len(pattern) and pattern[pi] == "*":
            star, mark = pi, ti
            pi += 1
        elif star is not None:
            pi = star + 1
            mark += 1
            ti = mark
        else:
            return False
    return all(c == "*" for c in pattern[pi:])


def list_dir(d: str) -> list[str]:
    try:
        return sorted(os.listdir(d))
    except OSError:
        return []


def expand_glob(project: str, pattern: str) -> list[str] | None:
    """Expansión de un comodín contra el disco, con tope. `None` si el tope corta la expansión: quien llama
    lo trata como que alcanza la cúpula (falla cerrado)."""
    if pattern.startswith("/"):
        cur, rest = ["/"], pattern[1:]
    else:
        cur, rest = [project], pattern
    budget = 5000
    for seg in [s for s in rest.split("/") if s not in ("", ".")]:
        nxt: list[str] = []
        for base in cur:
            if "*" not in seg and "?" not in seg:
                nxt.append(join(base, seg))
                continue
            for name in list_dir(base):
                budget = max(0, budget - 1)
                if (not name.startswith(".") or seg.startswith(".")) and wildcard(seg, name):
                    nxt.append(join(base, name))
                if budget == 0:
                    return None
        cur = nxt
    return cur


def symlinks_into(root: str, target: str, depth: int) -> list[str] | None:
    """Enlaces bajo `root` (hasta `depth` niveles) cuyo destino cae en `target`. `None` si algún directorio
    supera el tope de entradas: quien llama lo trata como que hay enlace (falla cerrado)."""
    out: list[str] = []
    names = list_dir(root)
    if len(names) > MAX_ENTRIES:
        return None
    for name in names:
        p = join(root, name)
        if os.path.islink(p):
            c = canonical(p)
            if c is not None and under(c, target):
                out.append(p)
        elif os.path.isdir(p) and depth > 1 and not name.startswith("."):
            inner = symlinks_into(p, target, depth - 1)
            if inner is None:
                return None
            out.extend(inner)
    return out


TOKEN_SPLIT = re.compile("[" + re.escape(WS) + "'\"`;&|()<>=]+")
COMPONENT_SPLIT = re.compile("[" + re.escape(WS) + "/'\"`;&|()<>=:]+")


def mentions_dome(root: str, project: str, command: str) -> bool:
    """La orden menciona la cúpula: su ruta, su nombre como componente, un enlace del workspace hacia
    ella o un comodín que la alcanza (la rama «menciona» de `bash_vault_reason`)."""
    ws, rd = resolve(project), resolve(root)
    rel = strip_prefix(root, project) or None
    tokens = [t for t in TOKEN_SPLIT.split(command) if t]
    components = [t for t in COMPONENT_SPLIT.split(command) if t]
    name = file_name(rd)
    if root in command or rd in command or (name and name in components):
        return True
    if rel is not None and rel in command:
        return True
    links = symlinks_into(ws, rd, 2)
    if links is None:
        return True
    for link in links:
        r = strip_prefix(link, ws)
        if r is not None and r in command:
            return True
    for t in tokens:
        if "*" in t or "?" in t:
            matches = expand_glob(project, t)
            if matches is None or any(under(resolve(m), rd) for m in matches):
                return True
    return False


# ── Análisis léxico de la orden (subconjunto de bash, como shell.rs) ─────────

MAX_LEN = 32 * 1024
MAX_CMDS = 2000
RESERVED = {"if", "then", "else", "elif", "fi", "while", "until", "do", "done", "esac", "{", "}", "!", "function"}
CONTROL = {"for", "case", "select"}
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


class ParseError(Exception):
    pass


def valid_name(s: str) -> bool:
    return bool(NAME_RE.match(s))


def is_digit(ch: str | None) -> bool:
    return ch is not None and "0" <= ch <= "9"


def literal(word: list) -> str | None:
    out = []
    for kind, text, _q in word:
        if kind != "lit":
            return None
        out.append(text)
    return "".join(out)


def push_lit(parts: list, ch: str, quoted: bool) -> None:
    if parts and parts[-1][0] == "lit" and parts[-1][2] == quoted:
        parts[-1] = ("lit", parts[-1][1] + ch, quoted)
    else:
        parts.append(("lit", ch, quoted))


def ensure_quoted(parts: list) -> None:
    if not (parts and parts[-1][0] == "lit" and parts[-1][2]):
        parts.append(("lit", "", True))


def read_balanced(c: str, i: int, op: str, cl: str) -> tuple[str, int] | None:
    """Texto hasta el cierre equilibrado (`i` justo tras la apertura); comillas y escapes respetados."""
    start, depth = i, 1
    while i < len(c):
        ch = c[i]
        if ch == "\\":
            i += 1
        elif ch == "'":
            i += 1
            while i < len(c) and c[i] != "'":
                i += 1
        elif ch == '"':
            i += 1
            while i < len(c) and c[i] != '"':
                if c[i] == "\\":
                    i += 1
                i += 1
        elif ch == op:
            depth += 1
        elif ch == cl:
            depth -= 1
            if depth == 0:
                return c[start:i], i + 1
        i += 1
    return None


def extract_subs(text: str) -> list[str]:
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == "$" and text[i + 1:i + 2] == "(":
            i += 2
            r = read_balanced(text, i, "(", ")")
            if r is not None:
                out.append(r[0])
                i = r[1]
                continue
        elif text[i] == "`":
            j = i + 1
            while j < len(text) and text[j] != "`":
                j += 1
            if j < len(text):
                out.append(text[i + 1:j])
                i = j
        i += 1
    return out


class Lexer:
    def __init__(self, src: str):
        self.c, self.i = src, 0

    def peek(self, n: int = 0) -> str | None:
        j = self.i + n
        return self.c[j] if j < len(self.c) else None

    def tokens(self) -> list:
        out: list = []
        pending: list = []
        while (ch := self.peek()) is not None:
            if ch in " \t":
                self.i += 1
            elif ch == "\\" and self.peek(1) == "\n":
                self.i += 2
            elif ch == "\n":
                self.i += 1
                out.append(("break",))
                self.read_heredocs(pending, out)
            elif ch == "#":
                while self.peek() not in (None, "\n"):
                    self.i += 1
            elif ch in ";()":
                self.i += 1
                out.append(("break",))
            elif ch == "&":
                if self.peek(1) == ">":
                    self.i += 1
                    self.redirect(out, pending, True)
                elif self.peek(1) == "&":
                    self.i += 2
                    out.append(("break",))
                else:
                    self.i += 1
                    out.append(("break",))
            elif ch == "|":
                self.i += 1
                if self.peek() == "|":
                    self.i += 1
                    out.append(("break",))
                elif self.peek() == "&":
                    self.i += 1
                    out.append(("pipe",))
                else:
                    out.append(("pipe",))
            elif ch in "<>" and self.peek(1) != "(":
                self.redirect(out, pending, False)
            elif is_digit(ch) and self.digits_then_redirect():
                while is_digit(self.peek()):
                    self.i += 1
                self.redirect(out, pending, False)
            else:
                out.append(("word", self.word()))
        for p in pending:
            out[p["tok"]][1]["body"] = ""
        return out

    def digits_then_redirect(self) -> bool:
        j = self.i
        while j < len(self.c) and is_digit(self.c[j]):
            j += 1
        return j < len(self.c) and self.c[j] in "<>" and self.c[j + 1:j + 2] != "("

    def redirect(self, out: list, pending: list, amp: bool) -> None:
        op = self.peek() or ">"
        self.i += 1
        kind = "in" if op == "<" else "out"
        heredoc = None
        maybe_dup = False
        nxt = self.peek()
        if op == "<":
            if nxt == "<":
                self.i += 1
                if self.peek() == "<":
                    self.i += 1
                    kind = "herestring"
                else:
                    kind = "heredoc"
                    strip = self.peek() == "-"
                    if strip:
                        self.i += 1
                    heredoc = strip
            elif nxt == "&":
                self.i += 1
                maybe_dup = True
            elif nxt == ">":
                self.i += 1
        else:
            if nxt == ">":
                self.i += 1
                kind = "append"
            elif nxt == "&" and not amp:
                self.i += 1
                maybe_dup = True
            elif nxt == "|":
                self.i += 1
        while self.peek() in (" ", "\t"):
            self.i += 1
        target = [] if self.peek() in (None, "\n", ";", "&", "|", "(", ")") else self.word()
        if maybe_dup:
            t = literal(target) or ""
            if t == "-" or (t and all(is_digit(ch) for ch in t)):
                kind = "dup"
        redir = {"kind": kind, "target": target, "body": None, "subs": []}
        if heredoc is not None:
            quoted = any(k == "lit" and q for k, _t, q in target)
            delim = "".join(t for k, t, _q in target if k == "lit")
            pending.append({"tok": len(out), "delim": delim, "strip": heredoc, "quoted": quoted})
        out.append(("redir", redir))

    def read_heredocs(self, pending: list, out: list) -> None:
        for p in pending:
            body = ""
            while self.i < len(self.c):
                start = self.i
                while self.peek() not in (None, "\n"):
                    self.i += 1
                line = self.c[start:self.i]
                if self.peek() == "\n":
                    self.i += 1
                cmp = line.lstrip("\t") if p["strip"] else line
                if cmp == p["delim"]:
                    break
                body += (cmp if p["strip"] else line) + "\n"
            r = out[p["tok"]][1]
            r["subs"] = [] if p["quoted"] else extract_subs(body)
            r["body"] = body
        pending.clear()

    def word(self) -> list:
        parts: list = []
        start = self.i
        while (ch := self.peek()) is not None:
            if ch in " \t\n;&|()":
                break
            if ch in "<>":
                if self.peek(1) != "(":
                    break
                self.i += 2
                r = read_balanced(self.c, self.i, "(", ")")
                if r is None:
                    raise ParseError("sustitución de proceso sin cerrar")
                parts.append(("proc", r[0], False))
                self.i = r[1]
            elif ch == "\\":
                self.i += 1
                nxt = self.peek()
                if nxt is None:
                    push_lit(parts, "\\", True)
                elif nxt == "\n":
                    self.i += 1
                else:
                    self.i += 1
                    push_lit(parts, nxt, True)
            elif ch == "'":
                self.i += 1
                ensure_quoted(parts)
                while True:
                    nxt = self.peek()
                    if nxt is None:
                        raise ParseError("comilla simple sin cerrar")
                    self.i += 1
                    if nxt == "'":
                        break
                    push_lit(parts, nxt, True)
            elif ch == '"':
                self.i += 1
                self.double_quoted(parts)
            elif ch == "$":
                self.dollar(parts, False)
            elif ch == "`":
                self.backtick(parts, False)
            elif ch == "~" and (self.i == start or assignment_prefix(parts)):
                self.i += 1
                if self.peek() in (None, "/", " ", "\t", "\n", ";", "&", "|", ")"):
                    parts.append(("var", "HOME", False))
                else:
                    push_lit(parts, "~", False)
            else:
                self.i += 1
                push_lit(parts, ch, False)
        return parts

    def double_quoted(self, parts: list) -> None:
        ensure_quoted(parts)
        while True:
            ch = self.peek()
            if ch is None:
                raise ParseError("comilla doble sin cerrar")
            if ch == '"':
                self.i += 1
                return
            if ch == "\\":
                self.i += 1
                nxt = self.peek()
                if nxt is None:
                    raise ParseError("comilla doble sin cerrar")
                self.i += 1
                if nxt == "\n":
                    continue
                if nxt in "$`\"\\":
                    push_lit(parts, nxt, True)
                else:
                    push_lit(parts, "\\", True)
                    push_lit(parts, nxt, True)
            elif ch == "$":
                self.dollar(parts, True)
            elif ch == "`":
                self.backtick(parts, True)
            else:
                self.i += 1
                push_lit(parts, ch, True)

    def backtick(self, parts: list, quoted: bool) -> None:
        self.i += 1
        script = ""
        while True:
            ch = self.peek()
            if ch is None:
                raise ParseError("comillas invertidas sin cerrar")
            if ch == "`":
                self.i += 1
                break
            if ch == "\\" and self.peek(1) in ("`", "\\", "$"):
                script += self.c[self.i + 1]
                self.i += 2
            else:
                script += ch
                self.i += 1
        parts.append(("sub", script, quoted))

    def dollar(self, parts: list, quoted: bool) -> None:
        nxt = self.peek(1)
        if nxt == "(":
            arithmetic = self.peek(2) == "("
            self.i += 2
            r = read_balanced(self.c, self.i, "(", ")")
            if r is None:
                raise ParseError("sustitución sin cerrar")
            inner, self.i = r
            if arithmetic:
                parts.append(("dyn", "", quoted))
                parts.extend(("sub", s, quoted) for s in extract_subs(inner))
            else:
                parts.append(("sub", inner, quoted))
        elif nxt == "{":
            self.i += 2
            r = read_balanced(self.c, self.i, "{", "}")
            if r is None:
                raise ParseError("expansión ${ sin cerrar")
            inner, self.i = r
            if valid_name(inner):
                parts.append(("var", inner, quoted))
            else:
                parts.append(("dyn", "", quoted))
                parts.extend(("sub", s, quoted) for s in extract_subs(inner))
        elif nxt is not None and (nxt == "_" or (nxt.isascii() and nxt.isalpha())):
            self.i += 1
            name = ""
            while (ch := self.peek()) is not None and (ch == "_" or (ch.isascii() and ch.isalnum())):
                name += ch
                self.i += 1
            parts.append(("var", name, quoted))
        elif nxt is not None and (is_digit(nxt) or nxt in "@*#?$!-"):
            self.i += 2
            parts.append(("dyn", "", quoted))
        elif nxt == "'" and not quoted:
            self.i += 2
            ensure_quoted(parts)
            self.ansi_c(parts)
        elif nxt == '"' and not quoted:
            self.i += 2
            self.double_quoted(parts)
        else:
            self.i += 1
            push_lit(parts, "$", quoted)

    def ansi_c(self, parts: list) -> None:
        simple = {"n": "\n", "t": "\t", "r": "\r", "a": "\x07", "b": "\x08", "e": "\x1b", "E": "\x1b",
                  "f": "\x0c", "v": "\x0b"}
        while True:
            ch = self.peek()
            if ch is None:
                raise ParseError("comilla $' sin cerrar")
            self.i += 1
            if ch == "'":
                return
            if ch != "\\":
                push_lit(parts, ch, True)
                continue
            e = self.peek()
            if e is None:
                raise ParseError("comilla $' sin cerrar")
            self.i += 1
            if e in simple:
                out = simple[e]
            elif e in "xuU":
                out = self.numeric(16, {"x": 2, "u": 4, "U": 8}[e]) or e
            elif e in "01234567":
                self.i -= 1
                out = self.numeric(8, 3) or "0"
            else:
                out = e
            push_lit(parts, out, True)

    def numeric(self, radix: int, maximum: int) -> str | None:
        digits = "0123456789abcdef"[:radix]
        v = n = 0
        while n < maximum:
            ch = self.peek()
            if ch is None or not ch.isascii() or ch.lower() not in digits:
                break
            v = v * radix + digits.index(ch.lower())
            self.i += 1
            n += 1
        if n == 0 or v > 0x10FFFF or 0xD800 <= v <= 0xDFFF:
            return None
        return chr(v)


def assignment_prefix(parts: list) -> bool:
    return (len(parts) == 1 and parts[0][0] == "lit" and not parts[0][2]
            and parts[0][1].endswith("=") and valid_name(parts[0][1][:-1]))


def split_assignment(word: list) -> tuple[str, list] | None:
    if not word or word[0][0] != "lit" or word[0][2]:
        return None
    text = word[0][1]
    eq = text.find("=")
    if eq < 0:
        return None
    name = text[:eq]
    name = name[:-1] if name.endswith("+") else name
    if not valid_name(name):
        return None
    parts = [("lit", text[eq + 1:], False)] if eq + 1 < len(text) else []
    return name, parts + word[1:]


def new_cmd() -> dict:
    return {"assigns": [], "words": [], "redirs": [], "control": False}


def parse(src: str) -> list[dict]:
    if len(src.encode("utf-8", "surrogatepass")) > MAX_LEN:
        raise ParseError("orden demasiado larga")
    cmds: list[dict] = []
    cur, started = new_cmd(), False
    for tok in Lexer(src).tokens():
        if tok[0] == "word":
            w = tok[1]
            unq = w[0][1] if len(w) == 1 and w[0][0] == "lit" and not w[0][2] else None
            if cur["control"]:
                cur["words"].append(w)
            elif not cur["words"]:
                if not cur["assigns"] and unq in RESERVED:
                    continue
                if not cur["assigns"] and unq in CONTROL:
                    cur["control"] = started = True
                    continue
                a = split_assignment(w)
                if a is not None:
                    cur["assigns"].append(a)
                else:
                    cur["words"].append(w)
            else:
                cur["words"].append(w)
            started = True
        elif tok[0] == "redir":
            cur["redirs"].append(tok[1])
            started = True
        elif started:
            cmds.append(cur)
            cur, started = new_cmd(), False
            if len(cmds) > MAX_CMDS:
                raise ParseError("demasiados comandos")
    if started:
        cmds.append(cur)
    return cmds


# ── Decisión ──────────────────────────────────────────────────────────────────

def word_text(word: list) -> str:
    out = []
    for kind, text, _q in word:
        out.append(text if kind in ("lit", "sub", "proc") else ("$" + text if kind == "var" else "$"))
    return "".join(out)


def unquoted(script: list[dict]) -> str:
    return " ; ".join(" ".join([word_text(w) for w in c["words"]] + [word_text(r["target"]) for r in c["redirs"]])
                      for c in script)


def lit_or_dollar(word: list) -> str:
    t = literal(word)
    return "$" if t is None else t


def base_name(prog: str) -> str:
    return prog.rsplit("/", 1)[-1]


def outputs(c: dict) -> bool:
    return any(r["kind"] in ("out", "append") and literal(r["target"]) != "/dev/null" for r in c["redirs"])


def writes(script: list[dict]) -> bool:
    for c in script:
        prog = literal(c["words"][0]) if c["words"] else None
        dynamic = any(literal(w) is None for w in c["words"])
        if outputs(c) or dynamic or prog is None or base_name(prog) in WRITERS or base_name(prog) in WRAPPERS:
            return True
    return False


def bash_reads_only(script: list[dict]) -> bool:
    if not script:
        return False
    for c in script:
        is_literal = all(literal(w) is not None for w in c["words"])
        prog = (literal(c["words"][0]) if c["words"] else None) or ""
        if c["control"] or c["assigns"] or not is_literal or outputs(c) or base_name(prog) not in READ_ONLY:
            return False
    return True


def is_recursive(prog: str, flags: list[str]) -> bool:
    def short(ch: str) -> bool:
        return any(not f.startswith("--") and ch in f for f in flags)

    if prog in ("rg", "find", "tree", "du", "tar", "rsync", "cpio", "7z"):
        return True
    if prog == "grep":
        return short("r") or short("R") or any(f.startswith("--recursive") for f in flags)
    if prog in ("zip", "scp"):
        return short("r") or short("R")
    if prog == "ls":
        return short("R")
    if prog == "cp":
        return (short("R") or short("r") or short("a")
                or any(f == "--archive" or f.startswith("--recursive") for f in flags))
    return False


DURATION = re.compile(r"[0-9]+(\.[0-9]+)?[smhd]?\Z")


def unwrap(words: list[str]) -> list[str]:
    """El programa que ejecuta un envoltorio (`timeout 5 grep`, `env LANG=C cat`, `nice -n 5 mv`): se quitan
    el envoltorio, sus opciones, asignaciones y duraciones. Lo que quede puede no ser un programa (el valor
    de una opción con argumento): entonces cuenta como desconocido."""
    while words and base_name(words[0]) in WRAPPERS:
        words = words[1:]
        while words and (words[0].startswith("-") or "=" in words[0] or DURATION.match(words[0])):
            words = words[1:]
    return words


def traversal_reaches(script: list[dict], project: str, root: str) -> bool:
    for c in script:
        words = [lit_or_dollar(w) for w in c["words"]]
        words = unwrap(words)
        if not words:
            continue
        prog = base_name(words[0])
        # Un programa que no se conoce (o que queda tras un envoltorio que no se sabe leer) recorre lo que nombre
        # cualquiera de sus palabras; uno conocido que no recorre, no.
        wrapped = prog not in KNOWN_PROGRAMS
        if not wrapped and prog not in TRAVERSERS:
            continue
        if not wrapped and not is_recursive(prog, [w for w in words[1:] if w.startswith("-") and len(w) > 1]):
            continue
        args = [w for w in words[1:] if not w.startswith("-")]
        if prog in ("grep", "rg") and args:
            args.pop(0)
        if wrapped:
            # `.`, `..` o `/` como argumento de un desconocido (las monturas de un sandbox) no cuentan: si no, toda
            # orden envuelta por bwrap «recorrería» el disco entero.
            if any(a != "$" and touches(root, project, a, True) and not contains_base(project, a) for a in args):
                return True
            continue
        if not args:
            if touches(root, project, ".", True):
                return True
        elif any(a == "$" or touches(root, project, a, True) for a in args):
            return True
    return False


def read_verdict(ctx: dict, touched: list[dict]) -> tuple[str, str]:
    if not ctx["cloud"]:
        return "pass", ""
    for d in touched:
        if d["level"] >= 3:
            return "deny", f"la cúpula «{d['id']}» es {level_name(d['level'])}: {CLOUD_DENIED}"
    for d in touched:
        if d["level"] >= 2 and d["id"] not in ctx["attached"] and d["id"] not in ctx["granted"]:
            return "ask", (f"la cúpula «{d['id']}» es {level_name(d['level'])} y no está adjunta: "
                           "su contenido saldría al proveedor de nube")
    return "pass", ""


def effective_cwd(project: str, tool_input) -> tuple[str, bool] | None:
    """Directorio de trabajo efectivo de una orden de bash y si difiere del proyecto (ronda 7 de dome_guard.rs).
    `None` = no se sabe dónde corre: la llamada no es un objeto, lleva una clave fuera del esquema de bash de
    los dos motores (podría fijar el directorio) o un `workdir` que no es texto."""
    if not isinstance(tool_input, dict) or any(k not in BASH_KEYS for k in tool_input):
        return None
    v = tool_input.get("workdir")
    if v is None:
        return project, False
    if not isinstance(v, str) or not v:
        return None
    base = join(project, v)
    return base, real_path(base) != real_path(project)


def git_subcommand(words: list[str]) -> tuple[str, list[str]]:
    """Subcomando de git y sus argumentos, saltando las opciones globales (`git -C dir rm`)."""
    rest = words[1:]
    while rest and rest[0].startswith("-"):
        rest = rest[2:] if rest[0] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") else rest[1:]
    return (rest[0], rest[1:]) if rest else ("", [])


def wipes_tree(c: dict) -> bool:
    """`git clean` (sin -n) y `git stash -u/--all` borran lo no versionado del árbol, registro local incluido."""
    words = [lit_or_dollar(w) for w in c["words"]]
    if not words or base_name(words[0]) != "git":
        return False
    sub, args = git_subcommand(words)
    if sub == "clean":
        return not any(a in ("-n", "--dry-run") or (a.startswith("-") and not a.startswith("--") and "n" in a)
                       for a in args)
    return sub == "stash" and any(a in ("-u", "-a", "--all", "--include-untracked") for a in args)


def destroys(c: dict) -> bool:
    """El comando mueve, borra o cambia permisos de lo que nombra, o ejecuta otro programa que podría hacerlo."""
    words = [lit_or_dollar(w) for w in c["words"]]
    if not words:
        return False
    prog = base_name(words[0])
    if prog in DESTROYERS or prog in WRAPPERS or prog not in KNOWN_PROGRAMS:
        return True
    if prog == "git":
        return git_subcommand(words)[0] in ("rm", "mv") or wipes_tree(c)
    return prog == "find" and any(w in ("-delete", "-exec", "-execdir", "-ok", "-okdir") for w in words[1:])


def flatten(script: list[dict], depth: int = 0) -> list[dict]:
    """Los comandos de la orden más los de sus órdenes anidadas: `$(...)`, `<(...)`, here-documents sin
    comillas, el `-c` de un shell y `eval`. Una anidada que no se puede analizar es un ParseError."""
    if depth > MAX_NESTING:
        raise ParseError("demasiado anidada")
    out: list[dict] = []
    for c in script:
        all_words = [lit_or_dollar(w) for w in c["words"]]
        if all_words and base_name(all_words[0]) in SANDBOXES and "--" in all_words:
            # Las opciones de un sandbox son monturas, no rutas que toque: cuenta lo que ejecuta tras `--`.
            i = all_words.index("--")
            inner_cmd = {"assigns": [], "words": c["words"][i + 1:], "redirs": c["redirs"], "control": False}
            out += flatten([inner_cmd], depth + 1)
            continue
        out.append(c)
        inner: list[str] = []
        for w in c["words"] + [r["target"] for r in c["redirs"]] + [a[1] for a in c["assigns"]]:
            inner += [text for kind, text, _q in w if kind in ("sub", "proc")]
        for r in c["redirs"]:
            inner += r["subs"]
        words = unwrap(all_words)
        prog = base_name(words[0]) if words else ""
        if prog in SHELLS:
            for i, w in enumerate(words[1:-1], start=1):
                if w.startswith("-") and not w.startswith("--") and "c" in w:
                    inner.append(words[i + 1])
                    break
        if prog == "eval":
            inner.append(" ".join(words[1:]))
        for text in inner:
            out += flatten(parse(text), depth + 1)
    return out


def expand_braces(word: str) -> list[str]:
    """Un nivel de llaves con comas (`{vaults,src}`), como haría el shell."""
    m = re.search(r"\{([^{}]*,[^{}]*)\}", word)
    if not m:
        return [word]
    return [word[:m.start()] + alt + word[m.end():] for alt in m.group(1).split(",")]


def candidates(word: str) -> list[str]:
    """Rutas que puede nombrar una palabra: ella, lo que va tras `=` o `@`, y sus llaves expandidas."""
    out = [word]
    if "=" in word:
        out.append(word.split("=", 1)[1])
    if "@" in word:
        out.append(word.split("@", 1)[1])
    return [x for c in out for x in expand_braces(c) if x and not x.startswith("-")]


def contains_base(base: str, cand: str) -> bool:
    """La palabra es el directorio de trabajo o un ancestro suyo (`.`, `..`, `/`)."""
    a, b = real_path(join(base, cand)), real_path(base)
    return a is None or b is None or under(b.lower(), a.lower())


def chain_of(target: str, base: str) -> list[str]:
    """Componentes (en minúsculas) de la ruta de la cúpula desde el directorio de trabajo."""
    rt, rb = resolve(target), resolve(base)
    rel = strip_prefix(rt, rb)
    return [c.lower() for c in (rel.split("/") if rel else split_path(rt)[1]) if c]


def changes_dir(cmds: list[dict]) -> bool:
    """Alguna parte de la orden cambia de directorio, así que las rutas relativas no se resuelven bien."""
    return any(w in ("cd", "pushd", "popd", "-C") or w.startswith(("--chdir", "--directory"))
               for c in cmds for w in (lit_or_dollar(x) for x in c["words"]))


def script_literals(c: dict) -> list[str]:
    """Literales entre comillas del guion `-c`/`-e` de un intérprete (tras un envoltorio, también)."""
    words = unwrap([lit_or_dollar(w) for w in c["words"]])
    if not words or base_name(words[0]) not in INTERPRETERS:
        return []
    for i, w in enumerate(words[1:-1], start=1):
        if w in ("-c", "-e", "-E") or (w.startswith("-") and not w.startswith("--") and w[-1] in "ce"):
            return [a or b for a, b in QUOTED.findall(words[i + 1]) if a or b]
    return []


def writes_reach(cmds: list[dict], base: str, target: str) -> bool:
    """Un comando que no es de solo lectura alcanza la cúpula (o el registro) o un ancestro suyo con cualquiera
    de sus palabras. Falla cerrado: no depende de qué programa sea, salvo para aflojar `.`/`..` en los que
    no destruyen (`git add .`). Una palabra dinámica o un comodín en uno que destruye, pregunta."""
    moved = changes_dir(cmds)
    chain = chain_of(target, base) if moved else []
    piped_any = any(base_name(lit_or_dollar(c["words"][0])) == "xargs" for c in cmds if c["words"])
    for c in cmds:
        first = lit_or_dollar(c["words"][0]) if c["words"] else ""
        if bash_reads_only([c]) or first in ("cd", "pushd", "popd"):
            continue
        destructive = destroys(c) or piped_any
        if wipes_tree(c) and touches(target, base, ".", True):
            return True
        words = c["words"][1:] + [r["target"] for r in c["redirs"] if r["kind"] in ("out", "append")]
        words += [a[1] for a in c["assigns"]]
        # El guion de un intérprete (`python3 -c "shutil.move('vaults', x)"`): sus literales entre comillas
        # cuentan como palabras del comando (con la regla de los que no destruyen: `.` no cuenta).
        words += [[("lit", q, True)] for q in script_literals(c)]
        for w in words:
            lit = literal(w)
            if lit is None:
                if destructive:
                    return True
                continue
            for cand in candidates(lit):
                if any(ch in cand for ch in "*?["):
                    matches = expand_glob(base, cand)
                    if matches is None or any(touches(target, base, m, True) for m in matches):
                        return True
                    continue
                if touches(target, base, cand, True) and (destructive or not contains_base(base, cand)):
                    return True
                if moved and file_name(cand).lower() in chain:
                    return True
    return False


RANK = {"pass": 0, "ask": 1, "deny": 2}


def strictest(verdicts: list[tuple[str, str]]) -> tuple[str, str]:
    """El veredicto más estricto (deny > ask > pass); a igualdad, el primero (su motivo)."""
    best = ("pass", "")
    for v in verdicts:
        if RANK[v[0]] > RANK[best[0]]:
            best = v
    return best


def decide_bash(domes: list[dict], files: list[str], project: str, ctx: dict, tool_input,
                cwd_known: bool = True) -> tuple[str, str]:
    # El directorio de trabajo decide contra qué se resuelven las rutas de la orden.
    cwd = effective_cwd(project, tool_input) if cwd_known else None
    if cwd is not None:
        return analyse_bash(domes, files, project, ctx, tool_input, *cwd)
    # Sin saber dónde corre no se sabe qué lee ni qué escribe, y cualquier cúpula podría ser su directorio de
    # trabajo (ronda 9 de dome_guard.rs). Veredicto cerrado y de coste constante: deny si la sesión es de nube y
    # hay alguna cúpula N3 o superior (la política de N3 en nube no se rebaja por una clave que el modelo
    # controla); ask en el resto. Nunca pass.
    v = read_verdict(ctx, [d for d in domes if d["level"] >= 3])
    return v if v[0] == "deny" else ("ask", UNKNOWN_CWD_NOTICE)


def analyse_bash(domes: list[dict], files: list[str], project: str, ctx: dict, tool_input: dict, base: str,
                 shifted: bool) -> tuple[str, str]:
    """Análisis de la orden con `base` como directorio de trabajo (`shifted`: distinto del proyecto)."""
    command = tool_input.get("command")
    if command is not None and not isinstance(command, str):
        return "ask", PAYLOAD_NOTICE
    command = command or ""
    try:
        script = parse(command)
    except ParseError:
        return "ask", f"la orden de shell no se puede analizar: {WRITE_NOTICE}"
    try:
        cmds = flatten(script)
    except ParseError:
        return "ask", f"la orden de shell no se puede analizar: {WRITE_NOTICE}"
    plain = unquoted(script)
    lower_tokens = re.split("[" + re.escape(WS) + "/{},=@:]", plain.lower())
    words = [lit_or_dollar(w) for c in script for w in c["words"] + [r["target"] for r in c["redirs"]]]
    pathlike = [w for w in words if "/" in w and not any(ch in w for ch in "*?$")]
    reads_only = bash_reads_only(script)
    # Solo un lector conocido con rutas literales y limpias puede aflojar el nombre: cualquier otro programa
    # (`env -C`, `sh -c`, `dd if=`, `curl -F file=@`) puede cambiar de directorio o esconder la ruta en una
    # palabra mayor, y entonces vale el nombre. Con otro directorio de trabajo, también.
    name_only_ok = (shifted or not pathlike or not reads_only
                    or any(any(ch in w for ch in "*?=@{}" + WS) for w in words))

    def reads_it(d: dict) -> bool:
        """La orden nombra la cúpula o una ruta suya (el `direct` de dome_guard.rs)."""
        name = file_name(d["root"]).lower()
        named = (bool(name) and name in lower_tokens) or any(mentions_dome(d["root"], project, c)
                                                             for c in (command, plain))
        # Una ruta que cae en la cúpula la nombra aunque no se llame como ella, y un directorio de trabajo
        # dentro de ella (el efectivo o el de la sesión) hace que toda orden la toque.
        by_path = any(touches(d["root"], base, w, False) for w in pathlike) or touches(d["root"], base, ".", False)
        return (named and name_only_ok) or by_path

    def direct(d: dict) -> bool:
        # Mover o borrar un ancestro se lleva la cúpula o el registro (y con él, todo el guard).
        return reads_it(d) or (not reads_only and writes_reach(cmds, base, d["root"]))

    direct_hit = [d for d in domes if direct(d)]
    if direct_hit and not reads_only:
        # Un programa que no es lector conocido (`base64`, `awk`, `cp`, `curl -F file=@`) puede leer igual: una N3
        # tocada en nube se rechaza como con un lector, no se rebaja a una pregunta (ronda 9 de dome_guard.rs).
        # Solo lo que la nombra o cae en ella: alcanzarla por un ancestro o una variable pregunta, como en Space.
        v = read_verdict(ctx, [d for d in direct_hit if reads_it(d)])
        if v[0] == "deny":
            return v
        # Una orden que además recorre una N3 hacia la nube se deniega: la pregunta de escritura no la afloja.
        reached = [d for d in domes if traversal_reaches(cmds, base, d["root"])]
        if reached and read_verdict(ctx, reached)[0] == "deny":
            return read_verdict(ctx, reached)
        return "ask", WRITE_NOTICE if writes(cmds) else UNKNOWN_NOTICE
    if not reads_only and any(direct({"root": f}) for f in files):
        return "ask", REGISTRY_NOTICE
    touched = list(direct_hit)
    for d in domes:
        if not any(t["id"] == d["id"] for t in touched) and traversal_reaches(cmds, base, d["root"]):
            touched.append(d)
    if not touched:
        return "pass", ""
    return read_verdict(ctx, touched)


def patch_paths(text: str) -> list[str]:
    return [m.strip() for m in re.findall(r"^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$", text, re.M)]


def search_root(project: str, permission: str, tool_input: dict) -> str | None:
    """Ruta donde busca o lee la herramienta; `None` = no se sabe. Un `glob` sin `path` no sale del
    prefijo literal de su patrón."""
    keys = ("filePath", "file_path") if permission == "read" else ("path",)
    for k in keys:
        v = tool_input.get(k)
        if isinstance(v, str) and v:
            return v
    if permission == "read":
        return None
    pattern = tool_input.get("pattern")
    if permission == "glob" and isinstance(pattern, str) and not pattern.startswith("/"):
        segs = []
        for s in pattern.split("/"):
            if not s or any(ch in s for ch in "*?[{"):
                break
            segs.append(s)
        if segs:
            return join(project, "/".join(segs))
    return project


def reaches_by_link(project: str, root: str, dome_root: str) -> bool:
    """Una búsqueda recursiva desde `root` entra en la cúpula por un enlace que hay debajo."""
    links = symlinks_into(resolve(join(project, root)), resolve(dome_root), LINK_DEPTH)
    return links is None or bool(links)


def path_values(value, depth: int = 0) -> list[str]:
    """Cadenas bajo claves de ruta, también anidadas en objetos y listas (hasta 8 niveles)."""
    out: list[str] = []
    if depth > 8:
        return out
    if isinstance(value, dict):
        for k, v in value.items():
            if isinstance(v, str) and v and PATH_KEY.search(k):
                out.append(v)
            elif isinstance(v, (dict, list)):
                out += path_values(v, depth + 1)
    elif isinstance(value, list):
        for v in value:
            out += path_values(v, depth + 1)
    return out


def decide_unknown(registry: dict, project: str, tool_input: dict) -> tuple[str, str]:
    """Herramienta que el guard no conoce (MCP, otras de edición): si alguna clave de ruta toca una cúpula,
    el registro o un ancestro suyo, pregunta. Sin claves de ruta no decide nada."""
    paths = path_values(tool_input)
    if not paths:
        return "pass", ""
    if "error" in registry:
        return "ask", f"registro de cúpulas ilegible ({registry['error']}): {WRITE_NOTICE}"
    if not registry["domes"]:
        return "pass", ""
    if any(touches(d["root"], project, p, True) for p in paths for d in registry["domes"]):
        return "ask", UNKNOWN_TOOL_NOTICE
    if any(touches(f, project, p, True) for p in paths for f in registry["files"]):
        return "ask", REGISTRY_NOTICE
    return "pass", ""


# Una llamada sin herramienta se evalúa como cada una de ellas y gana la más estricta: quitar la herramienta
# nunca da un veredicto menos estricto (monotonía). La desconocida va primero: su motivo es el que vale.
ANY_TOOL = ("", "edit", "bash", "read", "grep", "glob", "list")


def decide(registry: dict, project: str, tool: str, tool_input, ctx: dict, cwd_known: bool = True) -> tuple[str, str]:
    """`cwd_known`: el directorio de la llamada se conoce (en Claude Code, el `cwd` del payload es texto).
    `tool` vacío: no se sabe qué herramienta es."""
    if not tool:
        return strictest([decide_tool(registry, project, t, tool_input, ctx, cwd_known) for t in ANY_TOOL])
    return decide_tool(registry, project, tool, tool_input, ctx, cwd_known)


def decide_tool(registry: dict, project: str, tool: str, tool_input, ctx: dict, cwd_known: bool) -> tuple[str, str]:
    permission = tool_permission(tool)
    raw_input = tool_input
    if not isinstance(tool_input, dict):
        tool_input = {}
    if not (permission == "bash" or permission in FILE_TOOLS or permission in WRITE_TOOLS):
        return decide_unknown(registry, project, tool_input)
    if "error" in registry:
        return "ask", f"registro de cúpulas ilegible ({registry['error']}): {WRITE_NOTICE}"
    domes, files = registry["domes"], registry.get("files", [])
    if not domes:
        return "pass", ""
    if not isinstance(tool_input, dict):
        tool_input = {}
    if permission in WRITE_TOOLS:
        paths = [tool_input[k] for k in WRITE_PATH_KEYS if isinstance(tool_input.get(k), str)]
        for k in ("patchText", "patch"):
            if isinstance(tool_input.get(k), str):
                paths.extend(patch_paths(tool_input[k]))
        if not paths:
            return "ask", f"no se sabe qué ruta escribe el motor: {WRITE_NOTICE}"
        if any(touches(d["root"], project, p, False) for p in paths for d in domes):
            return "ask", WRITE_NOTICE
        if any(touches(f, project, p, False) for p in paths for f in files):
            return "ask", REGISTRY_NOTICE
        return "pass", ""
    if permission == "bash":
        return decide_bash(domes, files, project, ctx, raw_input, cwd_known)
    root = search_root(project, permission, tool_input)
    if root is None:
        return read_verdict(ctx, domes)
    recursive = permission != "read"
    touched = [d for d in domes if touches(d["root"], project, root, recursive)
               or (recursive and reaches_by_link(project, root, d["root"]))]
    return read_verdict(ctx, touched)


# ── Registro y contexto ──────────────────────────────────────────────────────

def local_registry_path(base: str) -> str:
    head, name = os.path.split(base)
    stem, ext = os.path.splitext(name)
    return os.path.join(head, f"{stem}.local{ext}")


def base_registry_path(file: str) -> str:
    return file[:-len(".local.json")] + ".json" if file.endswith(".local.json") else file


def reject_constant(name: str):
    raise ValueError(name)


def read_registry_file(file: str) -> list[dict]:
    try:
        if not stat.S_ISREG(os.stat(file).st_mode):
            raise ValueError(f"{file}: no es un fichero")
        with open(file, encoding="utf-8") as fh:
            raw = fh.read()
    except (OSError, UnicodeDecodeError):
        raise ValueError(f"{file}: no se puede leer")
    try:
        data = json.loads(raw, parse_constant=reject_constant)
    except ValueError:
        raise ValueError(f"{file}: JSON no válido")
    if not isinstance(data, dict) or not isinstance(data.get("domes"), dict):
        raise ValueError(f"{file}: sin objeto «domes»")
    folder = os.path.dirname(file) or "."
    out = []
    for dome_id, e in data["domes"].items():
        if not isinstance(e, dict) or not isinstance(e.get("path"), str):
            raise ValueError(f"{file}: «{dome_id}» sin ruta")
        conf = e.get("confidentiality")
        if conf is not None and not isinstance(conf, str):
            raise ValueError(f"{file}: nivel de «{dome_id}» no válido")
        level = parse_level(conf) if isinstance(conf, str) else 2
        if level is None:
            raise ValueError(f"{file}: nivel «{conf}» de «{dome_id}» no válido")
        out.append({"id": dome_id, "root": join(folder, e["path"]), "level": level})
    return out


def registry_entry_exists(file: str) -> bool:
    """Solo un ENOENT de verdad significa «no hay registro». Cualquier otro error (permisos, un componente que
    no es directorio, un enlace roto) es un ValueError: el guard falla cerrado."""
    try:
        os.stat(file)
        return True
    except FileNotFoundError:
        pass
    except OSError:
        raise ValueError(f"{file}: no se puede comprobar")
    try:
        os.lstat(file)
    except FileNotFoundError:
        return False
    except OSError:
        raise ValueError(f"{file}: no se puede comprobar")
    raise ValueError(f"{file}: enlace roto")


def load_registry(file: str, required: bool) -> dict:
    """Registro fusionado: base más local, con el mismo id gana el local."""
    base = base_registry_path(file)
    merged: list[dict] = []
    found = False
    try:
        for f in (base, local_registry_path(base)):
            if not registry_entry_exists(f):
                continue
            found = True
            for d in read_registry_file(f):
                merged = [m for m in merged if m["id"] != d["id"]] + [d]
    except ValueError as e:
        return {"error": str(e)}
    if not found and required:
        return {"error": f"{base}: no existe"}
    # Orden fijo por id: decide qué cúpula nombra el aviso cuando la orden toca varias. `files`: el registro
    # base y el local, que el motor no puede escribir (si los vaciara, el guard dejaría de proteger).
    return {"domes": sorted(merged, key=lambda d: d["id"]), "files": [base, local_registry_path(base)]}


def registry_file(root: str) -> tuple[str, bool]:
    env = os.environ.get("SAVIA_SPACE_DOMES_FILE", "")
    if env:
        return env, True
    return os.path.join(root, "projects/savia-vaults/savia-vaults.domes.json"), False


def session_context(payload: dict) -> dict:
    """Contexto de la sesión que da quien ejecuta el hook (`dome_context`); sin él, nube sin adjuntos."""
    raw = payload.get("dome_context")
    raw = raw if isinstance(raw, dict) else {}

    def ids(v) -> list[str]:
        return [x for x in v if isinstance(x, str)] if isinstance(v, list) else []

    return {"cloud": raw.get("cloud") is not False, "attached": ids(raw.get("attached")),
            "granted": ids(raw.get("granted"))}


def clean_strings(value, depth: int = 0) -> bool:
    """Ninguna cadena (ni clave) lleva un NUL o un sustituto UTF-16 suelto: el sistema de ficheros no los
    interpretaría como el guard, así que una llamada así no se decide (pregunta)."""
    if depth > 64:
        return False
    if isinstance(value, str):
        if "\x00" in value:
            return False
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            return False
        return True
    if isinstance(value, dict):
        return all(clean_strings(k, depth + 1) and clean_strings(v, depth + 1) for k, v in value.items())
    if isinstance(value, list):
        return all(clean_strings(v, depth + 1) for v in value)
    return True


def decide_payload(raw: str, root: str) -> tuple[str, str]:
    """Decisión para el payload PreToolUse en texto. Uno que no se puede leer, con cúpulas, pregunta."""
    try:
        payload = json.loads(raw, parse_constant=reject_constant)
    except (ValueError, RecursionError):
        payload = None
    file, required = registry_file(root)
    registry = load_registry(file, required)
    if not isinstance(payload, dict) or not clean_strings(payload):
        return ("ask", PAYLOAD_NOTICE) if ("error" in registry or registry["domes"]) else ("pass", "")
    cwd = payload.get("cwd")
    cwd_known = isinstance(cwd, str) and bool(cwd)
    project = os.path.abspath(cwd if cwd_known else root)
    tool = payload.get("tool_name")
    return decide(registry, project, tool if isinstance(tool, str) else "", payload.get("tool_input"),
                  session_context(payload), cwd_known)


def main(argv: list[str]) -> int:
    root = argv[argv.index("--root") + 1] if "--root" in argv else os.getcwd()
    try:
        raw = sys.stdin.buffer.read().decode("utf-8")
    except UnicodeDecodeError:
        raw = ""  # bytes que no son UTF-8: payload ilegible
    decision, reason = decide_payload(raw, root)
    if "--hook" not in argv:
        print(json.dumps({"decision": decision, "reason": reason}, ensure_ascii=False))
    elif decision != "pass":
        print(hook_output(decision, reason))
    return 0


def hook_output(decision: str, reason: str) -> str:
    """Salida PreToolUse de Claude Code: `ask` o `deny` con el motivo que ve la persona."""
    return json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                              "permissionDecisionReason": f"Guard de cúpulas: {reason}"}},
                      ensure_ascii=False)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
