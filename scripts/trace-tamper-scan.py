#!/usr/bin/env python3
"""SE-470 S2 — detector determinista de manipulación en trazas de agentes.

Recorre recibos de ejecución (stream-json de Claude Code, transcript JSONL de
Claude Code o eventos JSON de OpenCode) y señala, contra una lista EXPLÍCITA de
rutas (sin heurísticas):

  1. holdout_read     Read/Grep/Bash que leen una ruta de holdout
                      (Grep también si busca en un directorio que la contiene).
  2. protected_write  Edit/Write/MultiEdit/NotebookEdit sobre una ruta protegida.
  3. bash_modify      Bash que modifica una ruta protegida: sed -i / perl -i,
                      redirección > o >>, rm, git checkout / git restore,
                      mv, cp (destino), tee, truncate.

Salida: un JSON en stdout con el contrato de SE-453
(docs/rules/domain/gate-result-contract.md): result clean|findings|unknown y
gaps[{check, reason}]. Fail-closed: recibo ilegible, vacío, con líneas
corruptas o en un formato no reconocido, o una lista de rutas vacía, nunca da
clean. Códigos de salida: 0 clean, 1 findings, 2 unknown.

Uso:
  trace-tamper-scan.py --protected 'tests/evals/**/cases.jsonl' \
      --holdout 'tests/holdout/**' recibo1.jsonl [recibo2.jsonl ...]
  (--protected-file / --holdout-file leen un patrón por línea; # comenta)

Patrones: relativos a la raíz del repo; ** cruza directorios, * y ? no. Una
ruta absoluta coincide si algún sufijo alineado por componentes coincide, así
el mismo patrón vale para cualquier worktree. Una ruta parecida
(cases.jsonl.bak, mytests/...) no coincide.
"""
from __future__ import annotations

import argparse
import json
import posixpath
import re
import shlex
import sys
from typing import Any, Iterable

READ_TOOLS = {"read", "grep"}
WRITE_TOOLS = {"edit", "write", "multiedit", "notebookedit"}
PATCH_TOOLS = {"applypatch", "patch"}
PATCH_HDR_RE = re.compile(r"^\*\*\* (?:Update|Add|Delete) File: (.+)$", re.M)
PATH_KEYS =("file_path", "filePath", "notebook_path", "path")
MODIFY_CMDS = {"rm", "mv", "cp", "tee", "truncate", "unlink", "shred"}
INPLACE_CMDS = {"sed", "perl"}
SEPARATORS = {";", "&&", "||", "|", "&", ";;", "(", ")", "|&"}
REDIRECTS = {">", ">>", "&>", "&>>", ">|"}
HEREDOC_RE = re.compile(r"(?<!<)<<(?!<)(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
FALLBACK_RE = re.compile(r"&&|\|\||&>>|&>|>>|>&|<<<|<<|[;|&<>()]|[^\s;|&<>()]+")
EXIT = {"clean": 0, "findings": 1, "unknown": 2}


# ── patrones ────────────────────────────────────────────────────────────────
def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    out, i = [], 0
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**/", i):
            out.append(r"(?:.*/)?")
            i += 3
            continue
        if pattern.startswith("**", i):
            out.append(r".*")
            i += 2
            continue
        out.append({"*": r"[^/]*", "?": r"[^/]"}.get(c, re.escape(c)))
        i += 1
    return re.compile("".join(out) + r"\Z")


class Patterns:
    def __init__(self, raw: Iterable[str]):
        cleaned = (p.strip() for p in raw)
        self.raw = [re.sub(r"^(?:\./|/)+", "", p) for p in cleaned if p and not p.startswith("#")]
        self.regex = [_glob_to_regex(p) for p in self.raw]
        # prefijo literal (hasta el primer comodín) para saber si un directorio contiene la ruta
        self.prefixes = [re.split(r"[*?\[]", p, maxsplit=1)[0] for p in self.raw]

    def __bool__(self) -> bool:
        return bool(self.raw)

    @staticmethod
    def _suffixes(path: str) -> list[str]:
        parts = [p for p in posixpath.normpath(path).split("/") if p not in ("", ".")]
        return ["/".join(parts[i:]) for i in range(len(parts))]

    def match(self, path: str) -> str | None:
        for suffix in self._suffixes(path):
            for raw, rx in zip(self.raw, self.regex):
                if rx.match(suffix):
                    return raw
        return None

    def contained_in(self, directory: str) -> str | None:
        """Patrón cuya ruta vive dentro de `directory` (búsqueda recursiva)."""
        for suffix in self._suffixes(directory):
            for raw, prefix in zip(self.raw, self.prefixes):
                if prefix.startswith(suffix.rstrip("/") + "/"):
                    return raw
        return None


def load_patterns(values: list[str], files: list[str], gaps: list[dict]) -> Patterns:
    raw = list(values)
    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                raw.extend(fh.read().splitlines())
        except OSError:
            gaps.append({"check": f"patterns:{posixpath.basename(f)}", "reason": "unreadable"})
    return Patterns(raw)


# ── lectura de recibos ─────────────────────────────────────────────────────
def _norm_tool(name: Any) -> str:
    return str(name or "").replace("_", "").lower()


def iter_tool_calls(obj: Any) -> Iterable[tuple[str, dict, str | None]]:
    """(tool, input, cwd) de una línea; vacío si la línea no lleva llamadas."""
    if not isinstance(obj, dict):
        return
    cwd = obj.get("cwd") if isinstance(obj.get("cwd"), str) else None
    msg = obj.get("message")
    if obj.get("type") == "assistant" and isinstance(msg, dict):
        for block in msg.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                yield _norm_tool(block.get("name")), block.get("input"), cwd
        return
    part = obj.get("part")  # OpenCode: {"type":"tool_use","part":{"tool":..,"state":{"input":..}}}
    if isinstance(part, dict) and part.get("tool"):
        state = part.get("state") if isinstance(part.get("state"), dict) else {}
        yield _norm_tool(part.get("tool")), state.get("input"), cwd


def is_recognized(obj: Any) -> bool:
    return isinstance(obj, dict) and (
        obj.get("type") in {"assistant", "user", "system", "result", "summary", "tool_use",
                            "step_start", "step_finish", "text", "error"}
        or isinstance(obj.get("part"), dict))


# ── Bash ────────────────────────────────────────────────────────────────────
def _tokens(line: str) -> list[str]:
    """Tokens con los operadores (; && | > >> &> <<) separados."""
    try:
        lex = shlex.shlex(line, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        return list(lex)
    except ValueError:  # comilla sin cerrar (texto multilínea): partición tosca, no se descarta
        return FALLBACK_RE.findall(line)


def _shell_lines(command: str) -> Iterable[str]:
    """Líneas de shell sin el cuerpo de los heredocs (es texto o código de otro intérprete)."""
    pending: list[tuple[str, bool]] = []
    for line in command.splitlines():
        if pending:
            delim, strip_tabs = pending[0]
            if (line.lstrip("\t") if strip_tabs else line) == delim:
                pending.pop(0)
            continue
        yield line
        pending.extend((m.group(3), bool(m.group(1))) for m in HEREDOC_RE.finditer(line))


def _segments(command: str) -> Iterable[list[str]]:
    for line in _shell_lines(command):
        seg: list[str] = []
        for tok in _tokens(line):
            if tok in SEPARATORS:
                if seg:
                    yield seg
                seg = []
            else:
                seg.append(tok)
        if seg:
            yield seg


def _inplace_files(args: list[str]) -> list[str]:
    """Ficheros de sed/perl -i: sin el script (tras -e/-f, o el primer operando si no hay -e/-f)."""
    files, script_given, skip = [], False, False
    for a in args:
        if skip:
            skip = False
        elif a in ("-e", "--expression", "-f", "--file"):
            script_given = skip = True
        elif a.startswith(("--expression=", "--file=")) or re.match(r"^-[a-zA-Z]*e.", a):
            script_given = True  # -e'expr' pegado: el script va en el mismo token
        elif not a.startswith("-"):
            files.append(a)
    return files if script_given else files[1:]


def _resolve(cwd: str | None, path: str) -> str:
    return path if path.startswith("/") or not cwd else posixpath.join(cwd, path)


def scan_bash(command: str, cwd: str | None, prot: Patterns, hold: Patterns) -> list[dict]:
    hits: list[dict] = []
    for toks in _segments(command):
        redirects, args = [], []
        i = 0
        while i < len(toks):
            if toks[i] in REDIRECTS:
                if i + 1 < len(toks):
                    redirects.append(toks[i + 1])
                i += 2
                continue
            if toks[i] in ("<", "<<", "<<<", ">&", "<&"):
                i += 2  # entrada, heredoc o duplicado de descriptor: no es destino de escritura
                continue
            args.append(toks[i])
            i += 1
        while args and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", args[0]):
            args.pop(0)
        if args and args[0] in ("sudo", "env", "command", "nohup", "timeout"):
            args = args[1:]
            while args and (args[0].startswith("-") or re.match(r"^\d+[smhd]?$", args[0])):
                args.pop(0)
        cmd = posixpath.basename(args[0]) if args else ""
        if cmd == "cd" and len(args) > 1:
            cwd = _resolve(cwd, args[1])
            continue
        op = None
        operands = [a for a in args[1:] if not a.startswith("-")]
        if cmd in INPLACE_CMDS and any(re.match(r"^-[a-zA-Z]*i", a) or a.startswith("--in-place")
                                       for a in args[1:]):
            op = f"{cmd} -i"
            operands = _inplace_files(args[1:])
        elif cmd in MODIFY_CMDS:
            op = cmd
            if cmd == "cp":
                operands = operands[-1:]
        elif cmd == "git":
            sub = [a for a in args[1:]]
            while sub and sub[0].startswith("-"):
                sub = sub[2:] if sub[0] in ("-C", "-c") else sub[1:]
            if sub and sub[0] in ("checkout", "restore"):
                op = f"git {sub[0]}"
                operands = [a for a in sub[1:] if not a.startswith("-")]
        for target in redirects:
            pat = prot.match(_resolve(cwd, target))
            if pat:
                hits.append({"kind": "bash_modify", "op": ">", "path": target, "pattern": pat})
        if op:
            for a in operands:
                pat = prot.match(_resolve(cwd, a))
                if pat:
                    hits.append({"kind": "bash_modify", "op": op, "path": a, "pattern": pat})
        for a in args[1:] + redirects:
            pat = hold.match(_resolve(cwd, a)) if hold else None
            if pat:
                hits.append({"kind": "holdout_read", "op": cmd or "bash", "path": a, "pattern": pat})
    return hits


# ── escaneo ─────────────────────────────────────────────────────────────────
def scan_call(tool: str, inp: Any, cwd: str | None, prot: Patterns, hold: Patterns) -> tuple[list[dict], bool]:
    """Hallazgos de una llamada y si se pudo evaluar."""
    if tool not in READ_TOOLS | WRITE_TOOLS | PATCH_TOOLS | {"bash"}:
        return [], True
    if not isinstance(inp, dict):
        return [], False
    if tool == "bash":
        cmd = inp.get("command")
        if not isinstance(cmd, str):
            return [], False
        return scan_bash(cmd, cwd, prot, hold), True
    if tool in PATCH_TOOLS:  # OpenCode apply_patch: rutas en las cabeceras del parche
        text = inp.get("patchText") or inp.get("patch")
        if not isinstance(text, str):
            return [], False
        hits = []
        for target in PATCH_HDR_RE.findall(text):
            pat = prot.match(_resolve(cwd, target.strip()))
            if pat:
                hits.append({"kind": "protected_write", "op": tool, "path": target.strip(), "pattern": pat})
        return hits, True
    path = next((inp[k] for k in PATH_KEYS if isinstance(inp.get(k), str)), None)
    if tool == "grep" and path is None:
        return [], True  # sin ruta: el cwd; el detector no conoce la raíz, no se presume
    if path is None:
        return [], False
    full = _resolve(cwd, path)
    if tool in WRITE_TOOLS:
        pat = prot.match(full)
        return ([{"kind": "protected_write", "op": tool, "path": path, "pattern": pat}] if pat else []), True
    pat = hold.match(full) if hold else None
    if pat is None and tool == "grep" and hold:
        pat = hold.contained_in(full)
    return ([{"kind": "holdout_read", "op": tool, "path": path, "pattern": pat}] if pat else []), True


def scan_receipt(path: str, prot: Patterns, hold: Patterns) -> dict:
    name = posixpath.basename(path)
    findings: list[dict] = []
    gaps: list[dict] = []
    lines = recognized = calls = 0
    try:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                if not line.strip():
                    continue
                lines += 1
                try:
                    obj = json.loads(line)
                except ValueError:
                    gaps.append({"check": f"{name}:{lineno}", "reason": "unreadable"})
                    continue
                recognized += is_recognized(obj)
                for tool, inp, cwd in iter_tool_calls(obj):
                    calls += 1
                    hits, ok = scan_call(tool, inp, cwd, prot, hold)
                    if not ok:
                        gaps.append({"check": f"{name}:{lineno}:{tool}", "reason": "unreadable"})
                    for h in hits:
                        findings.append({"receipt": name, "line": lineno, **h})
    except (OSError, UnicodeDecodeError):
        gaps.append({"check": name, "reason": "unreadable"})
    if not gaps and lines == 0:
        gaps.append({"check": name, "reason": "unreadable"})  # vacío: nada que medir
    elif not gaps and recognized == 0:
        gaps.append({"check": f"{name}:format", "reason": "unreadable"})
    result = "findings" if findings else ("unknown" if gaps else "clean")
    return {"receipt": name, "result": result, "lines": lines, "tool_calls": calls,
            "findings": findings, "gaps": gaps}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("receipts", nargs="*")
    ap.add_argument("--protected", action="append", default=[])
    ap.add_argument("--holdout", action="append", default=[])
    ap.add_argument("--protected-file", action="append", default=[])
    ap.add_argument("--holdout-file", action="append", default=[])
    ap.add_argument("--list", action="append", default=[], help="fichero con una ruta de recibo por línea")
    ap.add_argument("--summary", action="store_true", help="sin el detalle por recibo")
    a = ap.parse_args(argv)

    gaps: list[dict] = []
    prot = load_patterns(a.protected, a.protected_file, gaps)
    hold = load_patterns(a.holdout, a.holdout_file, gaps)
    if not prot and not hold:
        gaps.append({"check": "patterns", "reason": "unreadable"})  # sin lista explícita no hay veredicto
    for f in a.list:
        try:
            with open(f, encoding="utf-8") as fh:
                a.receipts.extend(line.strip() for line in fh if line.strip())
        except OSError:
            gaps.append({"check": f"list:{posixpath.basename(f)}", "reason": "unreadable"})
    if not a.receipts:
        gaps.append({"check": "receipts", "reason": "unreadable"})

    reports = [scan_receipt(r, prot, hold) for r in a.receipts] if not gaps else []
    findings = [f for r in reports for f in r["findings"]]
    gaps += [g for r in reports for g in r["gaps"]]
    result = "findings" if findings else ("unknown" if gaps else "clean")
    by_kind: dict[str, int] = {}
    for f in findings:
        by_kind[f["kind"]] = by_kind.get(f["kind"], 0) + 1
    out = {"result": result, "gaps": gaps, "receipts": len(a.receipts),
           "receipts_by_result": {k: sum(r["result"] == k for r in reports) for k in EXIT},
           "findings_count": len(findings), "findings_by_kind": by_kind,
           "findings": findings}
    if not a.summary:
        out["per_receipt"] = [{k: r[k] for k in ("receipt", "result", "lines", "tool_calls")}
                              for r in reports]
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")
    return EXIT[result]


if __name__ == "__main__":
    sys.exit(main())
