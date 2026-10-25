#!/usr/bin/env python3
"""Valida la forma de evals.json de una skill (SE-457 AC6/AC7).

Uso: check-skill-evals.py <evals.json> [--positives N] [--total N] [--evals N]
Sale 0 si cumple, 1 si no.
"""
import argparse
import json
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--positives", type=int, default=10)
    ap.add_argument("--total", type=int, default=20)
    ap.add_argument("--evals", type=int, default=3)
    a = ap.parse_args()
    d = json.load(open(a.path, encoding="utf-8"))
    trig = d.get("trigger_evals", [])
    pos = sum(1 for t in trig if t.get("should_trigger") is True)
    errs = []
    if len(trig) != a.total:
        errs.append(f"trigger_evals={len(trig)} (esperado {a.total})")
    if pos != a.positives:
        errs.append(f"positivas={pos} (esperado {a.positives})")
    ev = d.get("evals", [])
    if len(ev) != a.evals:
        errs.append(f"evals={len(ev)} (esperado {a.evals})")
    for i, e in enumerate(ev):
        for k in ("prompt", "expected_output", "assertions"):
            if not e.get(k):
                errs.append(f"evals[{i}] sin {k}")
    for e in errs:
        print("FAIL:", e, file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
