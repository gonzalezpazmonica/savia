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


def fixture_stats(path: str) -> dict:
    """Clasifica un fixture L4 por lo que ejecuta.

    behavior: casos con "aggregate" (se ejecuta el script real y se compara el
    resultado). definition: checks que solo hacen grep sobre el prompt del agente
    o un fichero; se pueden satisfacer escribiendo texto, no prueban comportamiento.
    Un fixture sin ninguno de los dos es declarativo y no prueba nada.
    """
    try:
        cases = json.load(open(path, encoding="utf-8")).get("cases", [])
    except (OSError, ValueError, AttributeError):
        return {"behavior_cases": 0, "definition_checks": 0}
    behavior = sum(1 for c in cases if isinstance(c, dict) and "aggregate" in c)
    checks = sum(len(c.get("checks") or []) for c in cases if isinstance(c, dict))
    return {"behavior_cases": behavior, "definition_checks": checks}


def evidence_for(name: str, root: str, behavior_only: bool = False) -> list:
    """Evidencia presente. Con behavior_only, los fixtures solo cuentan si ejecutan comportamiento."""
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
        def counts(fx: str) -> bool:
            path = os.path.join(evals_dir, name, fx)
            if not os.path.exists(path):
                return False
            return not behavior_only or fixture_stats(path)["behavior_cases"] > 0
        if counts("golden.json") or not behavior_only and os.path.isdir(os.path.join(evals_dir, name)):
            ev += ["golden", "regression"]
        for fx, kind in (("edge.json","edge"),("adversarial.json","adversarial"),("bypass.json","bypass")):
            if counts(fx):
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
        present = evidence_for(c["name"], root, behavior_only=True)
        present_def = evidence_for(c["name"], root)
        stats = {"behavior_cases": 0, "definition_checks": 0}
        fx_dir = os.path.join(root, "tests", "evals", c["name"])
        for fx in ("golden", "edge", "adversarial", "bypass"):
            fp = os.path.join(fx_dir, fx + ".json")
            if os.path.exists(fp):
                for k, v in fixture_stats(fp).items():
                    stats[k] += v
        if c["kind"] == "agent":
            desc_dir = os.path.join(root, "contracts", "capabilities")
            for df in (os.listdir(desc_dir) if os.path.isdir(desc_dir) else []):
                dtxt = open(os.path.join(desc_dir, df), encoding="utf-8").read()
                if "agent." + c["name"] + ":" not in dtxt and ("id: agent." + c["name"]) not in dtxt:
                    continue
                if "- LAW-" in dtxt and "enforcement:" in dtxt and "negative_tests:" in dtxt:
                    present += ["negative_safety", "enforcement", "unsafe_action"]
                    present_def += ["negative_safety", "enforcement", "unsafe_action"]
        required = REQUIRED.get(risk, ["smoke"])
        present = sorted(set(present))
        present_def = sorted(set(present_def))
        missing = [r for r in required if r not in present]
        missing_def = [r for r in required if r not in present_def]
        # covered = solo comportamiento (cuenta para L4); covered_definition = criterio
        # antiguo, que tambien admite fixtures de grep sobre el prompt del agente.
        rows.append({
            "id": c["id"], "kind": c["kind"], "risk": risk,
            "evidence": present, "required": required, "missing": missing,
            "covered": len(missing) == 0,
            "evidence_definition": present_def, "missing_definition": missing_def,
            "covered_definition": len(missing_def) == 0,
            "behavior_cases": stats["behavior_cases"],
            "definition_checks": stats["definition_checks"],
        })

    rows.sort(key=lambda r: r["id"])
    by_risk: dict = {}
    for r in rows:
        by_risk.setdefault(r["risk"], {"total": 0, "covered": 0, "covered_definition": 0})
        by_risk[r["risk"]]["total"] += 1
        by_risk[r["risk"]]["covered"] += 1 if r["covered"] else 0
        by_risk[r["risk"]]["covered_definition"] += 1 if r["covered_definition"] else 0

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
        f.write("Solo las evals de comportamiento (ejecutan el script o agregador real) cuentan "
                "como cobertura. Las de definicion (grep sobre el prompt del agente) se reportan "
                "aparte: se cumplen escribiendo texto.\n\n")
        f.write("| Riesgo | Capabilities | Cobertura comportamiento | Cobertura % | Cobertura definicion |\n|---|---|---|---|---|\n")
        for risk in sorted(by_risk):
            t, c = by_risk[risk]["total"], by_risk[risk]["covered"]
            pct = round(100 * c / t) if t else 100
            f.write(f"| {risk} | {t} | {c} | {pct}% | {by_risk[risk]['covered_definition']} |\n")
        gaps = [r for r in rows if not r["covered"]]
        f.write(f"\nGaps: {len(gaps)} capabilities sin cobertura completa según matriz §12.2.\n\n")
        f.write("| Capability | Riesgo | Requerido | Presente (comportamiento) | Falta | Casos de comportamiento | Checks de definicion |\n|---|---|---|---|---|---|---|\n")
        for r in gaps:
            f.write(f"| {r['id']} | {r['risk']} | {','.join(r['required'])} | "
                    f"{','.join(r['evidence']) or '—'} | {','.join(r['missing'])} | "
                    f"{r['behavior_cases']} | {r['definition_checks']} |\n")
    print(f"eval-coverage: {len(rows)} capabilities evaluadas → output/eval-coverage-matrix.{{json,md}}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
