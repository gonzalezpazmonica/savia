"""Files a shell command writes, as far as its text tells (SE-392 S3).

`write`/`edit`/`apply_patch` on gate files were already denied in both cores; the same
rewrite through `bash` (`> .claude/settings.json`, `rm -rf .claude`, `sed -i`, `git
checkout -- .codex`) went through. This module reads the command text, never runs it,
and returns the write targets of the writers it knows: redirections, the file tools of
coreutils, `sed/perl -i`, `dd of=`, `git` subcommands that rewrite the worktree, and the
text of `bash -c`/`eval`, analysed recursively. Code of other interpreters (`python -c`)
is not analysed: that gap is stated, not hidden. A text the tokenizer cannot close
(open quote, unbalanced substitution) is an error, never "no targets".

Ported line by line to savia-gates lib/shell-targets.ts; parity is tested against a
shared corpus (tests/dual-cli/test_shell_targets.py).
"""
import os
import re

from protocol import ProtocolError

MAX_DEPTH = 8
_OPERATORS = (";;", "&&", "||", "|&", ";", "|", "&", "(", ")", "\n")
_WRAPPERS = {"sudo", "command", "builtin", "nohup", "time", "nice", "exec", "doas", "stdbuf", "ionice",
             "timeout"}
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
_SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}


class _Word:
    __slots__ = ("text", "dynamic", "glob")

    def __init__(self):
        self.text, self.dynamic, self.glob = "", False, False


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
    """At text[i] just past a newline: index after the bodies of the pending heredocs."""
    n = len(text)
    for delim, strip in heredocs:
        while i < n:
            end = text.find("\n", i)
            line = text[i:] if end < 0 else text[i:end]
            i = n if end < 0 else end + 1
            if (line.lstrip("\t") if strip else line) == delim:
                break
    return i


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
    """Shell text -> list of tokens: ("word", _Word), ("op", str), ("redir", str).

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
            word.text += text[i + 2:end - 1]
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
                heredocs.append((delim, strip))
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
    w = _Word()
    w.text, w.dynamic, w.glob = text, like.dynamic, like.glob
    return w


def _command_targets(words, depth):
    """Write targets of one simple command: list of (word, destructive)."""
    i = 0
    while i < len(words):
        name = os.path.basename(words[i].text)
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[i].text, re.S) or name in _KEYWORDS:
            i += 1
        elif name in _WRAPPERS:
            i += 1
            while i < len(words) and (words[i].text.startswith("-")
                                      or re.fullmatch(r"[0-9.]+[smhd]?", words[i].text)):
                i += 1
        elif name == "env":
            i += 1
            while i < len(words) and (words[i].text.startswith("-") or "=" in words[i].text):
                i += 1
        else:
            break
    if i >= len(words):
        return []
    name, args = os.path.basename(words[i].text), words[i + 1:]
    if name in _SHELLS:
        for k, w in enumerate(args):
            if w.text == "-c" and k + 1 < len(args):
                return analyse(args[k + 1].text, depth + 1)
        return []
    if name == "eval":
        return analyse(" ".join(w.text for w in args), depth + 1)
    if name == "xargs":
        # The arguments xargs appends come from stdin: only the literal ones are seen.
        k = 0
        while k < len(args) and args[k].text.startswith("-"):
            k += 2 if args[k].text in ("-I", "-n", "-L", "-P", "-d", "-s", "-E", "-a") else 1
        return _command_targets(args[k:], depth)
    if name == "find":
        # Only the start paths are literal; what -delete or -exec reach depends on the tree.
        if not any(w.text in ("-delete", "-exec", "-execdir", "-ok", "-okdir") for w in args):
            return []
        starts = []
        for w in args:
            if w.text.startswith("-") or w.text in ("(", "!"):
                break
            starts.append((w, False))
        return starts
    if name in _ALL_ARGS:
        rest = _non_options(args)
        if name == "mv":
            return [(w, k < len(rest) - 1) for k, w in enumerate(rest)]
        if name in _RECURSIVE_ONLY:
            recursive = any(w.text == "--recursive" or re.fullmatch(r"-[a-zA-Z]*R[a-zA-Z]*", w.text)
                            for w in args)
            return [(w, recursive) for w in rest]
        return [(w, name in DESTRUCTIVE) for w in rest]
    if name in _LAST_ARG:
        for k, w in enumerate(args):
            if w.text in ("-t", "--target-directory") and k + 1 < len(args):
                return [(args[k + 1], False)]
            if w.text.startswith("--target-directory="):
                return [(_plain(w.text.split("=", 1)[1], w), False)]
        rest = _non_options(args)
        return [(rest[-1], False)] if len(rest) >= 2 else []
    if name in ("sed", "perl") and any(w.text.startswith("-i") or w.text.startswith("--in-place")
                                       or (name == "perl" and re.fullmatch(r"-[a-zA-Z]*i.*", w.text))
                                       for w in args):
        return [(w, False) for w in _non_options(args)]
    if name == "dd":
        return [(_plain(w.text[3:], w), False) for w in args if w.text.startswith("of=")]
    if name == "git":
        k = 0
        while k < len(args) and args[k].text.startswith("-"):
            k += 2 if args[k].text in ("-C", "-c", "--git-dir", "--work-tree") else 1
        if k < len(args) and args[k].text in _GIT_WRITERS:
            return [(w, False) for w in _non_options(args[k + 1:])]
    return []


def analyse(text, depth=0):
    """(word, destructive) for every write target the command text shows. Raises INVALID_EVENT."""
    if depth > MAX_DEPTH or not isinstance(text, str):
        raise ProtocolError("INVALID_EVENT")
    nested = []
    tokens = tokenize(text, nested)
    targets, words, pending = [], [], None
    for kind, value in tokens + [("op", ";")]:
        if pending is not None:
            if kind != "word":
                raise ProtocolError("INVALID_EVENT")
            if pending not in ("<", "<<<"):
                targets.append((value, False))
            pending = None
            continue
        if kind == "redir":
            pending = value
        elif kind == "word":
            words.append(value)
        else:
            targets += _command_targets(words, depth)
            words = []
    for inner in nested:
        targets += analyse(inner, depth + 1)
    return targets


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
        rx = re.compile(_glob_regex("/".join(comps[:k])), re.S)
        if any(rx.fullmatch(b) for b in bases):
            return True
    rx = re.compile(_glob_regex(path), re.S)
    return destructive and any(rx.fullmatch(a) for b in bases for a in _ancestors(b))


def protected_target(command, cwd, root, protected_rel):
    """First write target of `command` that is gate code, or None. Raises INVALID_EVENT."""
    root = os.path.normpath(root)
    bases = [os.path.normpath(os.path.join(root, rel)) for rel in protected_rel]
    real_bases = bases + [os.path.realpath(b) for b in bases]
    for word, destructive in analyse(command):
        text = word.text
        for var in ("${CLAUDE_PROJECT_DIR}", "$CLAUDE_PROJECT_DIR"):
            text = text.replace(var, root)
        for var in ("${PWD}", "$PWD"):
            text = text.replace(var, cwd)
        if text.startswith("~"):
            continue  # the home directory: outside the repository
        if word.dynamic and "$" in text:
            # An unexpanded variable may stand for the root: judge the literal tail.
            tail = "/" + text.lstrip("/")
            if any(tail.endswith("/" + rel) or ("/" + rel + "/") in tail for rel in protected_rel):
                return word.text
            continue
        path = os.path.normpath(os.path.join(cwd, text))
        if word.glob:
            if _glob_hits(path, bases, destructive):
                return word.text
            continue
        for cand in (path, os.path.realpath(path)):
            for base in real_bases:
                if cand == base or cand.startswith(base + os.sep):
                    return word.text
                if destructive and base.startswith(cand.rstrip(os.sep) + os.sep):
                    return word.text
    return None
