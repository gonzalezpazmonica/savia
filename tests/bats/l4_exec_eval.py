#!/usr/bin/env python3
"""l4_exec_eval.py — ejecuta los cases "aggregate" de un fixture L4 contra el script real.

Ejecutor unico de las evals L4 de comportamiento que corren un script o hook.
Formato y semantica: tests/bats/l4-exec-lib.bash. Determinista, sin red ni modelo.
Uso: l4_exec_eval.py <fixture.json> [--script ORIG=REEMPLAZO ...]
Exit: 0 todos cumplen · 1 primera discrepancia (id del case en stderr) · 2 fixture invalido.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ALLOWED = {"script", "args", "cwd", "stdin", "stdin_json", "stdin_command", "files", "env", "expect"}
EXPECT_KEYS = {"exit", "stdout_match", "stdout_not_match", "stderr_match", "stderr_not_match",
               "stdout_empty", "json", "files_match", "files_absent"}
# Variables del operador que cambian la decision de hooks y scripts: se quitan del
# entorno antes de aplicar el env del case, para que el resultado no dependa de la sesion.
ISOLATE = ("CLAUDE_PROJECT_DIR", "OPENCODE_PROJECT_DIR", "SAVIA_WORKSPACE_DIR", "PROJECT_ROOT",
           "AGENTS_DIR", "SAVIA_HOOK_PROFILE", "SAVIA_DOME_GUARD", "SAVIA_GATES_PIN",
           "SAVIA_SPACE_DOMES_FILE", "SAVIA_DOME_READ_DIR", "COHERENCE_SCORE_PASS",
           "COHERENCE_SCORE_CONDITIONAL", "COHERENCE_PREMISES_DIR", "COURT_MAX_LOC",
           "COURT_SCORE_PASS", "COURT_SCORE_CONDITIONAL", "COURT_MAX_FIX_ROUNDS")
OLD_PLACEHOLDER = "{{TMP}}"


class Invalid(Exception):
    pass


def text(value, ctx: str) -> str:
    """Un texto es una cadena o una lista de partes que se concatenan."""
    if isinstance(value, str):
        return value
    if isinstance(value, list) and all(isinstance(p, str) for p in value):
        return "".join(value)
    raise Invalid(f"{ctx}: se esperaba cadena o lista de cadenas")


def sub(s: str, d: str) -> str:
    return s.replace("{dir}", d)


def regexes(value, ctx: str) -> list:
    """Una expectativa de regex es una cadena o una lista de cadenas (todas cuentan)."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and value and all(isinstance(p, str) for p in value):
        return value
    raise Invalid(f"{ctx}: se esperaba regex o lista no vacia de regex")


def no_old_placeholder(node, ctx: str = "aggregate") -> None:
    """{{TMP}} era el marcador del ejecutor retirado; ahora es {dir}. Falla cerrado."""
    if isinstance(node, str) and OLD_PLACEHOLDER in node:
        raise Invalid(f"{ctx}: usa {{dir}}, no {OLD_PLACEHOLDER}")
    if isinstance(node, dict):
        for k, v in node.items():
            no_old_placeholder(v, f"{ctx}.{k}")
    elif isinstance(node, list):
        for v in node:
            no_old_placeholder(v, ctx)


NOT_JSON = "<stdout no es JSON>"


def jq_value(path: str, stdout: str):
    """Evalua una ruta jq sobre el stdout. NOT_JSON si el stdout no es un JSON."""
    p = subprocess.run(["jq", "-c", path], input=stdout, capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        return NOT_JSON
    try:
        return json.loads(p.stdout)
    except ValueError:
        return NOT_JSON


def run_case(case: dict, overrides: dict, base_tmp: str) -> str | None:
    """Devuelve None si cumple, o el motivo de la discrepancia."""
    agg = case["aggregate"]
    unknown = set(agg) - ALLOWED
    if unknown:
        raise Invalid(f"claves desconocidas en aggregate: {sorted(unknown)}")
    if "script" not in agg or "expect" not in agg or "exit" not in agg["expect"]:
        raise Invalid("aggregate necesita script y expect.exit")
    exp = agg["expect"]
    if set(exp) - EXPECT_KEYS:
        raise Invalid(f"claves desconocidas en expect: {sorted(set(exp) - EXPECT_KEYS)}")
    if len(exp) == 1 and exp["exit"] == 0:
        raise Invalid("un exit 0 sin ninguna otra expectativa no prueba nada")
    if "stdout_empty" in exp and exp["stdout_empty"] is not True:
        raise Invalid("stdout_empty solo admite true")
    if "json" in exp and not (isinstance(exp["json"], dict) and exp["json"]):
        raise Invalid("json necesita un objeto {ruta jq: valor} no vacio")
    no_old_placeholder(agg)

    d = tempfile.mkdtemp(prefix="case-", dir=base_tmp)
    for rel, content in (agg.get("files") or {}).items():
        path = os.path.join(d, rel)
        if os.path.relpath(path, d).startswith(".."):
            raise Invalid(f"fichero fuera del directorio del case: {rel}")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(sub(text(content, f"files[{rel}]"), d))

    stdin = ""
    sources = [k for k in ("stdin", "stdin_json", "stdin_command") if k in agg]
    if len(sources) > 1:
        raise Invalid(f"solo una fuente de stdin: {sources}")
    if "stdin" in agg:
        stdin = sub(text(agg["stdin"], "stdin"), d)
    elif "stdin_json" in agg:
        stdin = json.dumps(agg["stdin_json"])
    elif "stdin_command" in agg:
        stdin = json.dumps({"tool_name": "Bash",
                            "tool_input": {"command": sub(text(agg["stdin_command"], "stdin_command"), d)}})

    env = {k: v for k, v in os.environ.items() if k not in ISOLATE}
    for k, v in (agg.get("env") or {}).items():
        env[k] = sub(text(v, f"env[{k}]"), d)
    script = overrides.get(agg["script"], agg["script"])
    if not os.path.isfile(script):
        raise Invalid(f"script ausente: {script}")
    script = os.path.abspath(script)
    args = [sub(text(a, "args"), d) for a in agg.get("args") or []]
    cwd = sub(text(agg["cwd"], "cwd"), d) if "cwd" in agg else None
    if cwd is not None and not os.path.isdir(cwd):
        raise Invalid(f"cwd ausente: {cwd}")
    try:
        p = subprocess.run(["bash", script, *args], input=stdin, capture_output=True,
                           text=True, env=env, timeout=60, cwd=cwd)
    except subprocess.TimeoutExpired:
        return "timeout (60 s)"

    if p.returncode != exp["exit"]:
        return f"exit {p.returncode} != esperado {exp['exit']} (stderr: {p.stderr.strip()[:200]})"
    for stream, out in (("stdout", p.stdout), ("stderr", p.stderr)):
        for rx in regexes(exp[f"{stream}_match"], f"{stream}_match") if f"{stream}_match" in exp else []:
            if not re.search(rx, out, re.M):
                return f"{stream} no casa /{rx}/: {out.strip()[:200]}"
        for rx in regexes(exp[f"{stream}_not_match"], f"{stream}_not_match") if f"{stream}_not_match" in exp else []:
            if re.search(rx, out, re.M):
                return f"{stream} casa lo prohibido /{rx}/"
    if exp.get("stdout_empty") and p.stdout:
        return f"stdout no vacio: {p.stdout.strip()[:200]}"
    for path, want in (exp.get("json") or {}).items():
        got = jq_value(path, p.stdout)
        if got is NOT_JSON or got != want:
            return f"{path}={json.dumps(got)} != esperado {json.dumps(want)} (stdout: {p.stdout.strip()[:200]})"
    for rel, rx in (exp.get("files_match") or {}).items():
        path = os.path.join(d, rel)
        if not os.path.isfile(path):
            return f"fichero esperado ausente: {rel}"
        if not re.search(rx, open(path, encoding="utf-8").read(), re.M):
            return f"{rel} no casa /{rx}/"
    for rel in exp.get("files_absent") or []:
        if os.path.exists(os.path.join(d, rel)):
            return f"fichero que no debia existir: {rel}"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fixture")
    ap.add_argument("--script", action="append", default=[], help="ORIG=REEMPLAZO")
    a = ap.parse_args()
    overrides = {}
    for m in a.script:
        if "=" not in m:
            print(f"l4: --script sin '=': {m}", file=sys.stderr)
            return 2
        k, v = m.split("=", 1)
        overrides[k] = v
    try:
        cases = json.load(open(a.fixture, encoding="utf-8"))["cases"]
    except (OSError, ValueError, KeyError) as e:
        print(f"l4: fixture ilegible {a.fixture}: {e}", file=sys.stderr)
        return 2
    runnable = [c for c in cases if isinstance(c, dict) and "aggregate" in c]
    if not runnable:
        print(f"l4: {a.fixture} sin cases aggregate", file=sys.stderr)
        return 2
    used = {c["aggregate"].get("script") for c in runnable}
    stale = set(overrides) - used
    if stale:
        print(f"l4: --script para un script que ningun case usa: {sorted(stale)}", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="l4-exec-") as tmp:
        for c in runnable:
            cid = c.get("id", "?")
            try:
                why = run_case(c, overrides, tmp)
            except Invalid as e:
                print(f"l4: case '{cid}' invalido: {e}", file=sys.stderr)
                return 2
            if why:
                print(f"l4: FALLA case '{cid}': {why}", file=sys.stderr)
                return 1
    print(f"l4: {len(runnable)} cases ejecutados OK ({a.fixture})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
