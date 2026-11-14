#!/usr/bin/env python3
"""SE-527 S1 — validación D3 de la retirada: el sustituto resuelve la tarea del agente retirado.

Reutiliza el arnés de SE-511 (tests/evals/se511-d4/run.py) sin tocarlo: mismas llamadas
(claude -p sin herramientas, sin settings, sin MCP, sin persistencia), mismo bootstrap con
semilla fija y la misma regla `verdict`. Solo cambia el directorio del experimento (corpus,
checks y variantes propios).

  build   --exp dispatch|tabular   congela variants/A.md (agente retirado en --base-ref)
                                   y variants/B.md (sustituto en el árbol de trabajo)
  run     --exp ...                llamadas (A y B, sonnet y haiku, 3 repeticiones)
  analyze --exp ...                diferencias pareadas B − A, IC 95 % y veredicto

Prerregistro: docs/evidence/SE-527-S1-prerregistro.md (commiteado antes de la 1.ª llamada).
"""
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

# Variante A = el agente retirado tal cual estaba en la base; B = el sustituto declarado.
EXPERIMENTS = {
    "dispatch": {"A": [".opencode/agents/configurator.md"],
                 "B": ["docs/RESOLVER.md", "docs/rules/domain/resolver-protocol.md"]},
    "tabular": {"A": [".opencode/agents/tabular-analyst.md"],
                "B": [".claude/skills/tabular-intelligence/SKILL.md"]},
}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def harness(exp):
    """El run.py de SE-511 apuntado al directorio del experimento."""
    d = os.path.join(HERE, exp)
    sys.path.insert(0, os.path.join(ROOT, "tests", "evals", "se511-d4"))
    h = load("se511_run", os.path.join(ROOT, "tests", "evals", "se511-d4", "run.py"))
    h.HERE = d
    h.checks = load("se527_checks_" + exp, os.path.join(d, "checks.py"))
    return h


def read(ref, path):
    if ref is None:
        return open(os.path.join(ROOT, path), encoding="utf-8").read()
    return subprocess.run(["git", "-C", ROOT, "show", f"{ref}:{path}"], capture_output=True,
                          text=True, check=True).stdout


def build(exp, base_ref):
    d = os.path.join(HERE, exp, "variants")
    os.makedirs(d, exist_ok=True)
    meta = {}
    for v, ref in (("A", base_ref), ("B", None)):
        paths = EXPERIMENTS[exp][v]
        txt = "\n\n".join(read(ref, p).rstrip("\n") for p in paths) + "\n"
        open(os.path.join(d, f"{v}.md"), "w", encoding="utf-8").write(txt)
        meta[v] = {"ref": ref or "worktree", "files": paths, "bytes": len(txt.encode()),
                   "sha256": hashlib.sha256(txt.encode()).hexdigest()}
    json.dump(meta, open(os.path.join(d, "meta.json"), "w"), indent=1)
    print(json.dumps(meta, indent=1))


def verify_frozen(exp):
    """Las variantes no cambian tras el prerregistro: SHA-256 contra meta.json (fail-closed)."""
    d = os.path.join(HERE, exp, "variants")
    meta = json.load(open(os.path.join(d, "meta.json")))
    for v, m in meta.items():
        got = hashlib.sha256(open(os.path.join(d, f"{v}.md"), "rb").read()).hexdigest()
        if got != m["sha256"]:
            raise SystemExit(f"variante {exp}/{v} distinta de la congelada")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["build", "run", "analyze"])
    ap.add_argument("--exp", required=True, choices=sorted(EXPERIMENTS))
    ap.add_argument("--base-ref", default="origin/main")
    ap.add_argument("--models", default="sonnet,haiku")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--max-calls", type=int, default=400)
    a = ap.parse_args()
    raw = os.path.join(HERE, a.exp, "results", "raw.jsonl")
    out = os.path.join(HERE, a.exp, "results", "summary.json")
    if a.cmd == "build":
        build(a.exp, a.base_ref)
        return
    verify_frozen(a.exp)
    h = harness(a.exp)
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    if a.cmd == "run":
        h.run(a.models.split(","), a.reps, a.workers, raw, a.max_calls, "B", None)
    else:
        h.analyze(raw, out, "B")


if __name__ == "__main__":
    main()
