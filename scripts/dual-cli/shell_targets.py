"""Files a shell command writes, as far as its text tells (SE-392 S3).

`write`/`edit`/`apply_patch` on gate files were already denied in both cores; the same
rewrite through `bash` (`> .claude/settings.json`, `rm -rf .claude`, `sed -i`, `git
checkout -- .codex`) went through. This module reads the command text, never runs it,
and returns the write targets of the writers it knows: redirections, the file tools of
coreutils, `sed/perl -i`, `dd of=`, `git` subcommands that rewrite the worktree (with
`-C`/`--work-tree`), and the text of `bash -c`/`-lc`/`eval` and of a heredoc fed to a shell,
analysed recursively. `cd`/`pushd` move the base of the relative paths that follow; after a
`cd` to an unknown place a literal relative path is judged against every directory on the way
to a gate. Code of other interpreters (`python -c`) is not analysed: that gap is stated, not
hidden. A text the tokenizer cannot close (open quote, unbalanced substitution) is an error,
never "no targets".

Ported line by line to savia-gates lib/shell-targets.ts; parity is tested against a
shared corpus (tests/dual-cli/test_shell_targets.py).
"""
import os
import posixpath
import re

from protocol import ProtocolError

MAX_DEPTH = 8
MAX_BRACE = 64
_OPERATORS = (";;", "&&", "||", "|&", ";", "|", "&", "(", ")", "\n")
_WRAPPERS = {"sudo", "command", "builtin", "nohup", "time", "nice", "exec", "doas", "stdbuf", "ionice",
             "timeout", "env"}
# Options of the wrappers that take the next word as their value (`sudo -u root rm …`).
_WRAPPER_VALUED = {
    "sudo": {"-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "--user", "--group", "--host",
             "--prompt", "--close-from", "--chdir", "--chroot", "--command-timeout", "--other-user"},
    "doas": {"-u", "-C"}, "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "-P", "-u", "--class", "--classdata", "--pid", "--pgid", "--uid"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "stdbuf": {"-i", "-o", "-e", "--input", "--output", "--error"},
    "env": {"-u", "-C", "-S", "--unset", "--chdir", "--split-string"},
}
_CHDIR_OPTIONS = {"env": {"-C", "--chdir"}, "sudo": {"-D", "--chdir"}}  # the command runs there
_KEYWORDS = {"{", "}", "!", "if", "then", "do", "else", "elif", "while", "until"}
# Every non-option argument is written (or removed).
_ALL_ARGS = {"rm", "rmdir", "unlink", "shred", "touch", "truncate", "mkdir", "chmod", "chown",
             "chgrp", "tee", "mv", "patch", "setfacl", "chattr"}
# Only the last non-option argument (or -t DIR) is written; the rest are read.
_LAST_ARG = {"cp", "install", "ln", "rsync", "scp"}
# Writers whose argument may be a directory holding the gate: removing it removes the gate.
DESTRUCTIVE = {"rm", "rmdir", "unlink", "shred"}
# Destructive on a directory only when recursive. `mv` sources are destructive, its destination is not.
_RECURSIVE_ONLY = {"chmod", "chown", "chgrp", "setfacl"}
_GIT_WRITERS = {"checkout", "restore", "rm", "mv", "apply", "clean", "reset", "stash", "am",
                "switch", "merge", "pull", "rebase", "cherry-pick", "revert"}
# Their pathspecs reach every file below them: `git checkout ref -- scripts` rewrites scripts/dual-cli.
_GIT_PATHSPEC_TREE = {"checkout", "restore", "rm", "clean", "reset", "stash"}
_SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
_SHELL_VALUED = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
_RECURSIVE_COPY = re.compile(r"-[a-zA-Z]*[rRa][a-zA-Z]*|--recursive|--archive")
# `find` predicates: names narrow the walk; these take one value and do not widen it.
_FIND_NAME = {"-name", "-iname"}
_FIND_VALUED = {"-type", "-maxdepth", "-mindepth"}
_FIND_PLAIN = {"(", ")", "-a", "-and", "-print", "-print0", "-delete", "-depth"}
_FIND_EXEC = {"-exec", "-execdir", "-ok", "-okdir"}


class _Word:
    """A shell word. `base`: directory its relative path starts from (`cd`, `git -C`), relative to
    the payload cwd. `loose`: that directory is unknown. `names`: `find -name` patterns that narrow
    what a `find` start path reaches, as (pattern, case_insensitive)."""
    __slots__ = ("text", "dynamic", "glob", "base", "loose", "names")

    def __init__(self):
        self.text, self.dynamic, self.glob = "", False, False
        self.base, self.loose, self.names = "", False, None


def _copy(w, **changes):
    out = _Word()
    out.text, out.dynamic, out.glob = w.text, w.dynamic, w.glob
    out.base, out.loose, out.names = w.base, w.loose, w.names
    for k, v in changes.items():
        setattr(out, k, v)
    return out


def _heredoc_start(text, i):
    """At text[i] just past `<<`/`<<-`: (delimiter, strip_tabs, index after it)."""
    strip = text.startswith("-", i)
    if strip:
        i += 1
    m = re.match(r"[ \t]*(?:'([^']*)'|\"([^\"]*)\"|\\?([^\s;&|()<>]+))", text[i:])
    if not m:
        raise ProtocolError("INVALID_EVENT")
    return next(g for g in m.groups() if g is not None), strip, i + len(m.group(0))


def _skip_heredocs(text, i, heredocs):
    """At text[i] just past a newline: index after the bodies of the pending heredocs.

    A heredoc entry may carry a third item, a list that receives its body."""
    n = len(text)
    for doc in heredocs:
        delim, strip, start = doc[0], doc[1], i
        body_end = n
        while i < n:
            end = text.find("\n", i)
            line = text[i:] if end < 0 else text[i:end]
            line_start, i = i, n if end < 0 else end + 1
            if (line.lstrip("\t") if strip else line) == delim:
                body_end = line_start
                break
        if len(doc) > 2:
            doc[2].append(text[start:body_end])
    return i


_ANSI_ESCAPES = {"a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n", "r": "\r",
                 "t": "\t", "v": "\v", "\\": "\\", "'": "'", '"': '"', "?": "?"}


def _ansi_decode(body):
    """Value of the body of `$'…'`: `$'\\x2eclaude'` is `.claude`."""
    def one(m):
        e = m.group(1)
        if e[0] in "xuU":
            code = int(e[1:], 16)
        elif e[0] in "01234567":
            code = int(e, 8) & 0xFF
        elif e[0] == "c":
            code = ord(e[1]) & 0x1F
        else:
            return _ANSI_ESCAPES.get(e, m.group(0))
        if code > 0x10FFFF:
            raise ProtocolError("INVALID_EVENT")
        return chr(code)
    return re.sub(r"\\(x[0-9a-fA-F]{1,2}|u[0-9a-fA-F]{1,4}|U[0-9a-fA-F]{1,8}|[0-7]{1,3}|c[\s\S]|[\s\S])",
                  one, body)


def _arith_end(text, i):
    """At text[i] just past `((`: index after the `))` that closes the arithmetic command, or
    None when the parentheses are two subshells (`((cd a) )`). `<<` in there is a shift."""
    depth, n = 2, len(text)
    while i < n:
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            if depth == 2:
                return i + 2 if text.startswith("))", i) else None
            depth -= 1
        i += 1
    return None


def _ansi_end(text, i):
    """At text[i] just past `$'`: index after the closing quote (backslash escapes)."""
    n = len(text)
    while i < n:
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == "'":
            return i + 1
        i += 1
    raise ProtocolError("INVALID_EVENT")


def _closing(text, i, opener, closer):
    """Index just past the `closer` that balances the `opener` at text[i-1].

    Quotes and heredoc bodies are skipped: a `)` or `'` in a commit message is text.
    """
    depth, n, heredocs = 1, len(text), []
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "\n" and heredocs:
            i = _skip_heredocs(text, i + 1, heredocs)
            heredocs = []
            continue
        if text.startswith("<<", i) and not text.startswith("<<<", i):
            delim, strip, i = _heredoc_start(text, i + 2)
            heredocs.append((delim, strip))
            continue
        if text.startswith("$'", i):
            i = _ansi_end(text, i + 2)
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise ProtocolError("INVALID_EVENT")
            i = j + 1
            continue
        if c == '"':
            i = _skip_double(text, i + 1)
            continue
        if c == opener:
            depth += 1
        elif c == closer:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ProtocolError("INVALID_EVENT")


def _skip_double(text, i):
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        if text.startswith("$(", i):
            i = _closing(text, i + 2, "(", ")")
            continue
        if c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                raise ProtocolError("INVALID_EVENT")
            i = j + 1
            continue
        i += 1
    raise ProtocolError("INVALID_EVENT")


def tokenize(text, nested):
    """Shell text -> list of tokens: ("word", _Word), ("op", str), ("redir", str), and
    ("body", [text]) where a heredoc opens: the list receives its body once it is read.

    Command substitutions are appended to `nested` as raw text: their commands run too.
    """
    tokens, i, n = [], 0, len(text)
    word, heredocs = None, []

    def flush():
        nonlocal word
        if word is not None:
            tokens.append(("word", word))
            word = None

    while i < n:
        c = text[i]
        if c == "\n" and heredocs:
            flush()
            tokens.append(("op", "\n"))
            i = _skip_heredocs(text, i + 1, heredocs)
            heredocs = []
            continue
        if c in " \t":
            flush()
            i += 1
            continue
        if c == "#" and word is None:
            end = text.find("\n", i)
            i = n if end < 0 else end
            continue
        if c == "\\":
            if i + 1 < n and text[i + 1] == "\n":
                i += 2
                continue
            word = word or _Word()
            word.text += text[i + 1:i + 2]
            i += 2
            continue
        if text.startswith("$'", i):
            end = _ansi_end(text, i + 2)
            word = word or _Word()
            word.text += _ansi_decode(text[i + 2:end - 1])
            i = end
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise ProtocolError("INVALID_EVENT")
            word = word or _Word()
            word.text += text[i + 1:j]
            i = j + 1
            continue
        if word is None and text.startswith("((", i):
            end = _arith_end(text, i + 2)
            if end is not None:  # arithmetic: writes no file
                i = end
                continue
        if c == '"':
            word = word or _Word()
            i += 1
            while True:
                if i >= n:
                    raise ProtocolError("INVALID_EVENT")
                d = text[i]
                if d == '"':
                    i += 1
                    break
                if d == "\\" and i + 1 < n and text[i + 1] in '"\\$`\n':
                    word.text += text[i + 1]
                    i += 2
                    continue
                if text.startswith("$(", i):
                    end = _closing(text, i + 2, "(", ")")
                    nested.append(text[i + 2:end - 1])
                    word.text += "$(...)"
                    word.dynamic = True
                    i = end
                    continue
                if d == "`":
                    j = text.find("`", i + 1)
                    if j < 0:
                        raise ProtocolError("INVALID_EVENT")
                    nested.append(text[i + 1:j])
                    word.text += "$(...)"
                    word.dynamic = True
                    i = j + 1
                    continue
                if d == "$":
                    word.dynamic = True
                word.text += d
                i += 1
            continue
        if text.startswith("$(", i):
            end = _closing(text, i + 2, "(", ")")
            nested.append(text[i + 2:end - 1])
            word = word or _Word()
            word.text += "$(...)"
            word.dynamic = True
            i = end
            continue
        if c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                raise ProtocolError("INVALID_EVENT")
            nested.append(text[i + 1:j])
            word = word or _Word()
            word.text += "$(...)"
            word.dynamic = True
            i = j + 1
            continue
        if c in "<>" or (c == "&" and text.startswith("&>", i)):
            fd = word is not None and re.fullmatch(r"[0-9]+", word.text) is not None and not word.dynamic
            if word is not None and not fd:
                flush()
            word = None
            m = re.match(r"&>>|&>|>>|>\||>&|<<<|<<-|<<|<>|<&|>|<", text[i:])
            op = m.group(0)
            i += len(op)
            if op in (">&", "<&"):
                m2 = re.match(r"[ \t]*([0-9]+-?|-)(?=[\s;&|()<>]|$)", text[i:])
                if m2:  # fd duplication, no file
                    i += len(m2.group(0))
                    continue
                op = ">" if op == ">&" else "<"
            if op in ("<<", "<<-"):
                delim, strip, i = _heredoc_start(text, i - len(op) + 2)
                body = []
                heredocs.append((delim, strip, body))
                tokens.append(("body", body))
                continue
            tokens.append(("redir", op))
            continue
        op = next((o for o in _OPERATORS if text.startswith(o, i)), None)
        if op is not None:
            flush()
            tokens.append(("op", op))
            i += len(op)
            continue
        word = word or _Word()
        if c == "$":
            word.dynamic = True
        elif c in "*?[":
            word.glob = True
        word.text += c
        i += 1
    flush()
    return tokens


def _non_options(args):
    out, ended = [], False
    for w in args:
        if not ended and w.text == "--":
            ended = True
            continue
        if not ended and w.text.startswith("-") and w.text != "-":
            continue
        out.append(w)
    return out


def _plain(text, like):
    return _copy(like, text=text)


def _is_assignment(text):
    return re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", text, re.S) is not None


def _rebase(w, base, loose=False):
    """w seen from a directory `base` (relative to where the command starts), or from an unknown one."""
    if base:
        w = _copy(w, base=posixpath.join(base, w.base) if w.base else base)
    return _copy(w, loose=True) if loose and not w.loose else w


def _joined(dest, src):
    """What `cp/mv src dest` writes when dest is a directory: dest/basename(src)."""
    return _copy(dest, text=posixpath.join(dest.text, posixpath.basename(src.text)),
                 dynamic=dest.dynamic or src.dynamic, glob=dest.glob or src.glob)


def _into(dest, sources, reach):
    """dest itself, and each source's place inside it; `reach` when that place replaces a tree."""
    return [(dest, False)] + [(_joined(dest, s), reach) for s in sources]


def _command_targets(words, depth, bodies=()):
    """Write targets of one simple command: list of (word, destructive).

    `bodies`: text fed to its stdin by heredocs and here-strings."""
    i, base, loose = 0, "", False
    while i < len(words):
        name = os.path.basename(words[i].text)
        if _is_assignment(words[i].text) or name in _KEYWORDS:
            i += 1
            continue
        if name not in _WRAPPERS:
            break
        valued, chdir = _WRAPPER_VALUED.get(name, set()), _CHDIR_OPTIONS.get(name, set())
        i += 1
        while i < len(words):
            t = words[i].text
            if t == "--":
                i += 1
                break
            if name == "env" and _is_assignment(t):
                i += 1
            elif t.startswith("-"):
                opt, eq, val = t.partition("=")
                value = _plain(val, words[i]) if eq else (words[i + 1] if i + 1 < len(words) else None)
                if name == "env" and opt in ("-S", "--split-string") and value is not None:
                    rest = words[i + (1 if eq else 2):]
                    inner = analyse(" ".join([value.text] + [w.text for w in rest]), depth + 1)
                    return [(_rebase(w, base, loose), d) for w, d in inner]
                if opt in chdir and value is not None:
                    if value.dynamic or value.text.startswith("~"):
                        loose = True
                    else:
                        base = posixpath.join(base, value.text)
                i += 2 if opt in valued and not eq else 1
            elif re.fullmatch(r"[0-9.]+[smhd]?", t):
                i += 1
            else:
                break
    if i >= len(words):
        return []
    return [(_rebase(w, base, loose), d)
            for w, d in _targets_of(os.path.basename(words[i].text), words[i + 1:], depth, bodies)]


def _targets_of(name, args, depth, bodies):
    if name in _SHELLS:
        k = 0
        while k < len(args):
            t = args[k].text
            if re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", t):  # -c, -lc, -ec, -xec …
                return analyse(args[k + 1].text, depth + 1) if k + 1 < len(args) else []
            if t in _SHELL_VALUED:
                k += 2
            elif t.startswith(("-", "+")):
                k += 1
            else:
                return []  # a script file: what it writes is not in this text
        # The script comes from stdin: a heredoc or here-string is in the text.
        return [t for body in bodies for t in analyse(body, depth + 1)]
    if name == "eval":
        return analyse(" ".join(w.text for w in args), depth + 1)
    if name == "xargs":
        # The arguments xargs appends come from stdin: only the literal ones are seen.
        k = 0
        while k < len(args) and args[k].text.startswith("-"):
            k += 2 if args[k].text in ("-I", "-n", "-L", "-P", "-d", "-s", "-E", "-a") else 1
        return _command_targets(args[k:], depth)
    if name == "find":
        return _find_targets(args, depth)
    if name in _ALL_ARGS:
        rest = _non_options(args)
        if name == "mv":
            if len(rest) < 2:
                return [(w, False) for w in rest]
            return [(w, True) for w in rest[:-1]] + _into(rest[-1], rest[:-1], True)
        if name in _RECURSIVE_ONLY:
            recursive = any(w.text == "--recursive" or re.fullmatch(r"-[a-zA-Z]*R[a-zA-Z]*", w.text)
                            for w in args)
            return [(w, recursive) for w in rest]
        return [(w, name in DESTRUCTIVE) for w in rest]
    if name in _LAST_ARG:
        recursive = any(_RECURSIVE_COPY.fullmatch(w.text) for w in args)
        for k, w in enumerate(args):
            if w.text in ("-t", "--target-directory") and k + 1 < len(args):
                return _into(args[k + 1], _non_options(args[:k] + args[k + 2:]), recursive)
            if w.text.startswith("--target-directory="):
                return _into(_plain(w.text.split("=", 1)[1], w), _non_options(args[:k] + args[k + 1:]),
                             recursive)
        rest = _non_options(args)
        return _into(rest[-1], rest[:-1], recursive) if len(rest) >= 2 else []
    if name in ("sed", "perl") and any(w.text.startswith("--in-place") or re.fullmatch(r"-[a-zA-Z]*i.*", w.text)
                                       for w in args):
        return [(w, False) for w in _non_options(args)]
    if name == "dd":
        return [(_plain(w.text[3:], w), False) for w in args if w.text.startswith("of=")]
    if name == "git":
        k, base, loose = 0, "", False
        while k < len(args) and args[k].text.startswith("-"):
            opt, eq, val = args[k].text.partition("=")
            if opt in ("-C", "--work-tree") and (eq or k + 1 < len(args)):
                value = _plain(val, args[k]) if eq else args[k + 1]
                if value.dynamic or value.text.startswith("~"):
                    loose = True
                else:
                    base = posixpath.join(base, value.text)
                k += 1 if eq else 2
                continue
            k += 2 if args[k].text in ("-c", "--git-dir", "--namespace") else 1
        if k < len(args) and args[k].text in _GIT_WRITERS:
            reach = args[k].text in _GIT_PATHSPEC_TREE
            return [(_rebase(w, base, loose), reach) for w in _non_options(args[k + 1:])]
    return []


def _find_targets(args, depth):
    """`find` start paths when the expression deletes or runs a writer. They reach their whole tree
    unless `-name`/`-iname` narrow it (no `-o`, `!` or other predicate that could widen it); the
    patterns go with the word and are matched against the gate names in protected_target."""
    k, starts = 0, []
    while k < len(args) and not (args[k].text.startswith("-") or args[k].text in ("(", "!")):
        starts.append(args[k])
        k += 1
    writes, names, narrow = False, [], True
    while k < len(args):
        t = args[k].text
        if t in _FIND_EXEC:
            end = next((j for j in range(k + 1, len(args)) if args[j].text in (";", "+")), len(args))
            inner = args[k + 1:end]
            if inner and (os.path.basename(inner[0].text) in _SHELLS or _command_targets(inner, depth)):
                writes = True
            k = end + 1
            continue
        if t in _FIND_NAME and k + 1 < len(args):
            names.append((args[k + 1].text, t == "-iname"))
            k += 2
            continue
        if t in _FIND_VALUED:
            k += 2
            continue
        if t == "-delete":
            writes = True
        elif t not in _FIND_PLAIN:
            narrow = False  # -o, !, -not, -path, -mtime…: a gate cannot be ruled out
        k += 1
    if not writes:
        return []
    if not starts:
        starts = [_plain(".", _Word())]
    keep = names if names and narrow else None
    return [(_copy(w, names=keep), True) for w in starts]


def _cd(words, base, loose, dirs):
    """(base, loose) after one simple command: `cd`/`pushd`/`popd` move it."""
    k = 0
    while k < len(words) and (_is_assignment(words[k].text) or words[k].text in _KEYWORDS):
        k += 1
    if k >= len(words):
        return base, loose
    name = words[k].text
    if name == "popd":
        return dirs.pop() if dirs else (base, True)
    if name not in ("cd", "pushd"):
        return base, loose
    if name == "pushd":
        dirs.append((base, loose))
    args = [w for w in words[k + 1:] if w.text not in ("-L", "-P", "-e", "-@", "--")]
    if not args or args[0].dynamic or args[0].glob or args[0].text.startswith(("~", "-", "+")):
        return base, True  # home, previous directory, a variable: unknown
    target = args[0].text
    return posixpath.join(base, target), loose and not target.startswith("/")


def analyse(text, depth=0):
    """(word, destructive) for every write target the command text shows. Raises INVALID_EVENT."""
    if depth > MAX_DEPTH or not isinstance(text, str):
        raise ProtocolError("INVALID_EVENT")
    nested = []
    tokens = tokenize(text, nested)
    targets, words, bodies, pending = [], [], [], None
    base, loose, scopes, dirs = "", False, [], []
    for kind, value in tokens + [("op", ";")]:
        if pending is not None:
            if kind != "word":
                raise ProtocolError("INVALID_EVENT")
            if pending == "<<<":
                bodies.append(value.text)
            elif pending != "<":
                targets.append((_rebase(value, base, loose), False))
            pending = None
            continue
        if kind == "redir":
            pending = value
        elif kind == "body":
            bodies += value
        elif kind == "word":
            words.append(value)
        else:
            targets += [(_rebase(w, base, loose), d) for w, d in _command_targets(words, depth, bodies)]
            base, loose = _cd(words, base, loose, dirs)
            if value == "(":
                scopes.append((base, loose))
            elif value == ")" and scopes:
                base, loose = scopes.pop()  # a subshell's `cd` ends with it
            words, bodies = [], []
    for inner in nested:
        targets += analyse(inner, depth + 1)
    return targets


def _rx(pattern, flags=0):
    try:
        return re.compile(_glob_regex(pattern), re.S | flags)
    except re.error as exc:  # `[z-a]`: the same refusal as the port's RegExp error
        raise ProtocolError("INVALID_EVENT") from exc


def _glob_regex(pattern):
    out, i, n = "", 0, len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        elif c == "[":
            j = pattern.find("]", i + 2 if i + 1 < n and pattern[i + 1] in "!^" else i + 1)
            if j < 0:
                out += r"\["
            else:
                body = pattern[i + 1:j]
                neg = body[:1] in ("!", "^")
                body = body[1:] if neg else body
                out += "[" + ("^" if neg else "") + re.sub(r"([\\\]\[^])", r"\\\1", body) + "]"
                i = j
        else:
            out += re.escape(c)
        i += 1
    return out


def _ancestors(path):
    """path and all its parents."""
    out = [path]
    while path != os.path.dirname(path):
        path = os.path.dirname(path)
        out.append(path)
    return out


def _glob_hits(path, bases, destructive):
    """A glob reaches a gate when its leading components match a gate path (the match lies
    inside it) or, for a destructive writer, when the whole glob matches a parent of one."""
    comps = path.split("/")
    for k in range(2, len(comps) + 1):
        rx = _rx("/".join(comps[:k]))
        if any(rx.fullmatch(b) for b in bases):
            return True
    rx = _rx(path)
    return destructive and any(rx.fullmatch(a) for b in bases for a in _ancestors(b))


def _split_top(body):
    parts, depth, start = [], 0, 0
    for i, c in enumerate(body):
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(body[start:i])
            start = i + 1
    return parts + [body[start:]]


def _braces(text):
    """Brace expansion: `{.claude,tmp}` -> `.claude`, `tmp`; `.clau{d,}e` -> `.claude`, `.claue`."""
    depth, start = 0, -1
    for i, c in enumerate(text):
        if c == "{":
            if depth == 0:
                start = i
            depth += 1
        elif c == "}" and depth > 0:
            depth -= 1
            parts = _split_top(text[start + 1:i]) if depth == 0 else []
            if len(parts) > 1:
                out = []
                for part in parts:
                    out += _braces(text[:start] + part + text[i + 1:])
                    if len(out) > MAX_BRACE:
                        raise ProtocolError("INVALID_EVENT")
                return out
    return [text]


MAX_WALK = 5000
_GENERATED = {"__pycache__", "node_modules"}  # regenerable, not gate code: `find . -name '*.pyc' -delete`


def _gate_names(bases, protected_rel):
    """Every file and directory name on the way to or inside a gate; None when there are too many."""
    names, seen = {c for rel in protected_rel for c in rel.split("/")}, 0
    for base in bases:
        for _dir, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in _GENERATED]
            seen += len(dirs) + len(files)
            if seen > MAX_WALK:
                return None
            names.update(dirs)
            names.update(files)
    return names


def protected_target(command, cwd, root, protected_rel):
    """First write target of `command` that is gate code, or None. Raises INVALID_EVENT."""
    root = os.path.normpath(root)
    bases = [os.path.normpath(os.path.join(root, rel)) for rel in protected_rel]
    real_bases = bases + [os.path.realpath(b) for b in bases]
    home = os.environ.get("HOME", "")
    # After a `cd` to an unknown place: every directory a relative path could start from to reach a gate.
    anchors = sorted({a for b in bases for a in _ancestors(os.path.dirname(b))
                      if a == root or a.startswith(root + os.sep)} | set(bases))
    names = []

    def reaches(word):
        """A `find` narrowed by -name reaches a gate only when a pattern matches a gate name."""
        if word.names is None:
            return True
        if not names:
            names.append(_gate_names(bases, protected_rel))
        return names[0] is None or any(_rx(p, re.I if ci else 0).fullmatch(n)
                                       for p, ci in word.names for n in names[0])

    def inside(path, destructive):
        for cand in (path, os.path.realpath(path)):
            for base in real_bases:
                if cand == base or cand.startswith(base + os.sep):
                    return True
                if destructive and base.startswith(cand.rstrip(os.sep) + os.sep):
                    return True
        return False

    def hits(word, text, destructive):
        here = os.path.normpath(os.path.join(cwd, word.base))
        for var in ("${CLAUDE_PROJECT_DIR}", "$CLAUDE_PROJECT_DIR"):
            text = text.replace(var, root)
        if home:
            for var in ("${HOME}", "$HOME"):
                text = text.replace(var, home)
            if text == "~" or text.startswith("~/"):
                text = home + text[1:]
        if not word.loose:
            for var in ("${PWD}", "$PWD"):
                text = text.replace(var, here)
        if text.startswith("~"):
            return False  # another user's home: outside the repository
        if word.dynamic and "$" in text:
            # An unexpanded variable may stand for the root: judge the literal tail.
            tail = "/" + text.lstrip("/")
            return any(tail.endswith("/" + rel) or ("/" + rel + "/") in tail for rel in protected_rel)
        rel = posixpath.join(word.base, text)
        if word.loose and not rel.startswith("/"):
            # Unknown directory: a literal path is a gate if it is one from any directory on the way
            # to a gate, or an existing file from inside one (any name is inside a gate directory).
            return not word.glob and any(
                inside(cand, False) and (a not in bases or os.path.lexists(cand))
                for a in anchors for cand in [os.path.normpath(os.path.join(a, rel))])
        path = os.path.normpath(os.path.join(here, text))
        destructive = destructive and reaches(word)
        if word.glob:
            return _glob_hits(path, bases, destructive)
        return inside(path, destructive)

    for word, destructive in analyse(command):
        if any(hits(word, text, destructive) for text in _braces(word.text)):
            return word.text
    return None
