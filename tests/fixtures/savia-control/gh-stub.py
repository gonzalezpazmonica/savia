#!/usr/bin/env python3
"""Stub de gh para los tests de SE-498. Estado en $GH_STUB_DIR.

gh api <ruta>  → $GH_STUB_DIR/api/<ruta con / → _ y sin llaves>.json; si falta o existe <…>.fail, sale 1.
                 Con --paginate, un elemento por línea de <…>.json y, si existe, de <…>.page2.json.
gh pr list     → prs.json (lista). gh pr create → añade una PR y suma 1 a «created»
                 (con pr-create.fail presente, falla).
gh pr close N  → la quita de prs.json.
"""
import json
import os
import re
import sys

d = os.environ["GH_STUB_DIR"]
a = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(" ".join(a) + "\n")


def load(p, default):
    try:
        with open(p) as f:
            return json.load(f)
    except OSError:
        return default


prs_p = os.path.join(d, "prs.json")
created_p = os.path.join(d, "created")
if a[:1] == ["api"]:
    base = os.path.join(d, "api", re.sub(r"[{}]", "", a[1]).replace("/", "_"))
    if os.path.exists(base + ".fail") or not os.path.exists(base + ".json"):
        sys.stderr.write("gh stub: fallo simulado\n")
        sys.exit(1)
    if "--paginate" in a:
        # como gh api --paginate --jq '.[]': un elemento por línea; <base>.page2.json simula la página 2
        pages = [base + ".json"] + ([base + ".page2.json"] if os.path.exists(base + ".page2.json") else [])
        for pg in pages:
            for item in json.load(open(pg)):
                print(json.dumps(item))
        sys.exit(0)
    sys.stdout.write(open(base + ".json").read())
    sys.exit(0)
if a[:2] == ["pr", "list"]:
    print(json.dumps(load(prs_p, [])))
    sys.exit(0)
if a[:2] == ["pr", "create"] and os.path.exists(os.path.join(d, "pr-create.fail")):
    sys.stderr.write("gh stub: pr create falla (simulado)\n")
    sys.exit(1)
if a[:2] == ["pr", "create"]:
    head = a[a.index("--head") + 1]
    prs = load(prs_p, [])
    c = int(load(created_p, 0)) + 1
    n = 100 + c
    prs.append({"number": n, "headRefName": head, "url": f"https://example.invalid/pr/{n}"})
    json.dump(prs, open(prs_p, "w"))
    json.dump(c, open(created_p, "w"))
    print(f"https://example.invalid/pr/{n}")
    sys.exit(0)
if a[:2] == ["pr", "close"]:
    json.dump([p for p in load(prs_p, []) if str(p["number"]) != a[2]], open(prs_p, "w"))
    sys.exit(0)
sys.stderr.write("gh stub: orden no soportada\n")
sys.exit(1)
