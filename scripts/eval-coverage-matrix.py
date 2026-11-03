#!/usr/bin/env python3
"""eval-coverage-matrix.py — SE-381: cobertura de eval conductual ponderada por riesgo.

Lee el registry canónico (.scm/registry.json, SE-375) y contrasta la cobertura
de evidencia de evaluación (bats, evals, golden) contra la matriz mínima §12.2
por nivel de riesgo. v1 = report-only (exit 0 siempre); el gate de bloqueo se
activa cuando la cobertura de datos llegue al 100% (slice S3 de la spec).

Salidas: output/eval-coverage-matrix.json + .md (deterministas, sin timestamp).
Uso: python3 scripts/eval-coverage-matrix.py [--root DIR]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

REQUIRED = {
    "L0": ["smoke"],
    "L1": ["smoke", "golden"],
    "L2": ["smoke", "golden", "edge"],
    "L3": ["smoke", "golden", "edge", "adversarial", "regression"],
    "L4": ["smoke", "golden", "edge", "adversarial", "regression",
           "negative_safety", "enforcement", "unsafe_action", "bypass"],
}


def sha(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()[:12]


def evidence_for(name: str, root: str) -> list:
    ev = []
    bats_dir = os.path.join(root, "tests", "bats")
    evals_dir = os.path.join(root, "tests", "evals")
    golden_dir = os.path.join(root, "tests", "golden")
    if os.path.isdir(bats_dir):
        for fn in os.listdir(bats_dir):
            if name.replace("-", "_") in fn or name in fn or name.replace("-", "") in fn:
                ev.append("smoke")
                break
    if os.path.isdir(evals_dir) and os.path.isdir(os.path.join(evals_dir, name)):
        ev += ["golden", "regression"]
        for fx, kind in (("edge.json","edge"),("adversarial.json","adversarial"),("bypass.json","bypass")):
            if os.path.exists(os.path.join(evals_dir, name, fx)):
                ev.append(kind)
    if os.path.isdir(golden_dir):
        for fn in os.listdir(golden_dir):
            if name in fn:
                ev.append("golden")
                break
    for marker, kind in (("anti-sycophancy", "adversarial"), ("anti-", "adversarial")):
        if marker in name:
            ev.append(kind)
    return sorted(set(ev))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = ap.parse_args()
    root = os.path.abspath(args.root)

    reg_path = os.path.join(root, ".scm", "registry.json")
    # SE-501 AC-11: el registry es D (no versionado); derived.sh ensure lo genera si falta.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import derived_canon
    if derived_canon.ensure(root, [".scm/registry.json"]):
        print(f"registry ausente; {derived_canon.ENSURE_HINT}", file=sys.stderr)
        return 1
    reg = json.load(open(reg_path, encoding="utf-8"))

    caps = [c for c in reg["capabilities"] if c["kind"] in ("agent", "skill")]
    rows = []
    for c in caps:
        stem = c["id"].split(":", 1)[1]
        c["name"] = stem.rsplit("/", 1)[-1].replace(".md", "")
        risk = c.get("risk_level")
        if c["kind"] == "skill" and not risk:
            risk = "unknown"
        if not risk:
            risk = "unknown"
        present = evidence_for(c["name"], root)
        if c["kind"] == "agent":
            desc_dir = os.path.join(root, "contracts", "capabilities")
            for df in (os.listdir(desc_dir) if os.path.isdir(desc_dir) else []):
                dtxt = open(os.path.join(desc_dir, df), encoding="utf-8").read()
                if "agent." + c["name"] + ":" not in dtxt and ("id: agent." + c["name"]) not in dtxt:
                    continue
                if "- LAW-" in dtxt and "enforcement:" in dtxt and "negative_tests:" in dtxt:
                    present += ["negative_safety", "enforcement", "unsafe_action"]
        required = REQUIRED.get(risk, ["smoke"])
        missing = [r for r in required if r not in present]
        rows.append({
            "id": c["id"], "kind": c["kind"], "risk": risk,
            "evidence": present, "required": required, "missing": missing,
            "covered": len(missing) == 0,
        })

    rows.sort(key=lambda r: r["id"])
    by_risk: dict = {}
    for r in rows:
        by_risk.setdefault(r["risk"], {"total": 0, "covered": 0})
        by_risk[r["risk"]]["total"] += 1
        by_risk[r["risk"]]["covered"] += 1 if r["covered"] else 0

    payload = {
        "matrix_version": 1,
        "content_hash": sha(json.dumps(rows, sort_keys=True, ensure_ascii=False)),
        "summary_by_risk": by_risk,
        "report_only": True,
        "rows": rows,
    }
    outdir = os.path.join(root, "output")
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "eval-coverage-matrix.json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True, ensure_ascii=False)

    with open(os.path.join(outdir, "eval-coverage-matrix.md"), "w", encoding="utf-8") as f:
        f.write("# Matriz de cobertura eval ponderada por riesgo (SE-381)\n\n")
        f.write("v1 report-only. Reutiliza paired-delta/golden existentes; no crea framework.\n\n")
        f.write("| Riesgo | Capabilities | Cobertura completa | Cobertura % |\n|---|---|---|---|\n")
        for risk in sorted(by_risk):
            t, c = by_risk[risk]["total"], by_risk[risk]["covered"]
            pct = round(100 * c / t) if t else 100
            f.write(f"| {risk} | {t} | {c} | {pct}% |\n")
        gaps = [r for r in rows if not r["covered"]]
        f.write(f"\nGaps: {len(gaps)} capabilities sin cobertura completa según matriz §12.2.\n\n")
        f.write("| Capability | Riesgo | Requerido | Presente | Falta |\n|---|---|---|---|---|\n")
        for r in gaps:
            f.write(f"| {r['id']} | {r['risk']} | {','.join(r['required'])} | "
                    f"{','.join(r['evidence']) or '—'} | {','.join(r['missing'])} |\n")
    print(f"eval-coverage: {len(rows)} capabilities evaluadas → output/eval-coverage-matrix.{{json,md}}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
