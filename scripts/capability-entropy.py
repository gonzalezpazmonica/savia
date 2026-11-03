#!/usr/bin/env python3
"""capability-entropy.py — SE-380: métrica de entropía arquitectónica (v0).

Fórmula provisional (pesos 1.0, congelados en baseline hasta validación):
    entropy = active_capabilities + overlap_pairs + mirror_pairs
            + dependency_edges + manual_sync_surfaces + exception_count
Componentes medibles hoy desde el registry SE-375 y el árbol. routing_ambiguity
queda a 0 hasta integrar RESOLVER OVERRIDE (documentado como límite).

--check: falla si entropy > baseline congelado (ratchet: solo puede bajar).
Baseline: tests/baselines/capability-entropy.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--v1", action="store_true")
    args = ap.parse_args()
    root = os.path.abspath(args.root)

    # SE-501 AC-11: el registry es D (no versionado); derived.sh ensure lo genera si falta.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import derived_canon
    gone = derived_canon.ensure(root, [".scm/registry.json", ".scm/INDEX.scm"])
    if gone:
        print(f"FAIL: falta {', '.join(gone)} — {derived_canon.ENSURE_HINT}", file=sys.stderr)
        return 2
    reg = json.load(open(os.path.join(root, ".scm", "registry.json"), encoding="utf-8"))
    caps = reg["capabilities"]

    active = sum(1 for c in caps if c.get("status") != "deprecated")
    # overlap: mismo basename con distinta extensión/kind en scripts y skills
    stems = Counter(
        os.path.basename(c["source"]).rsplit(".", 1)[0].lower()
        for c in caps if c["kind"] in ("script", "skill", "agent", "cmd")
    )
    overlap_pairs = sum(v - 1 for v in stems.values() if v > 1)
    # mirrors: pares skill/agent/hook con mismo basename en .claude y .opencode
    claude = {c["id"] for c in caps if str(c["source"]).startswith(".claude")}
    opencode = {c["id"] for c in caps if str(c["source"]).startswith(".opencode")}
    mirror_pairs = len(claude & opencode)
    dep_edges = sum(len(c.get("depends_on") or []) for c in caps)
    sync_surfaces = sum(
        os.path.exists(os.path.join(root, f)) for f in
        (".scm/INDEX.scm", "AGENTS.md", "SKILLS.md", "docs/RESOLVER.md")
    )
    exceptions = 0  # SE-376: excepciones aprobadas (ninguna aún)

    entropy = (active + overlap_pairs + mirror_pairs
               + dep_edges + sync_surfaces + exceptions)
    components = {
        "active_capabilities": active,
        "overlap_pairs": overlap_pairs,
        "mirror_pairs": mirror_pairs,
        "dependency_edges": dep_edges,
        "routing_ambiguity": 0,
        "manual_sync_surfaces": sync_surfaces,
        "exception_count": exceptions,
    }
    payload = {"entropy_version": 0, "weights": "all-1.0-provisional",
               "entropy": entropy, "components": components}

    base_path = os.path.join(root, "tests", "baselines", "capability-entropy.json")
    v1 = False
    if args.v1:
        v1 = True
        unowned = sum(1 for c in caps if c["kind"] == "agent" and not c.get("owner_domain"))
        import re as _re
        untested = 0
        bats_dir = os.path.join(root, "tests", "bats")
        bat_files = os.listdir(bats_dir) if os.path.isdir(bats_dir) else []
        for c in caps:
            if c.get("kind") == "agent" and c.get("risk_level") in ("L3", "L4"):
                name = c["id"].split(":", 1)[-1].split("/")[-1].replace(".md", "")
                if not any(name in fn for fn in bat_files):
                    untested += 1
        payload["entropy_v1"] = payload["entropy"] + untested + unowned
        payload["components"]["unowned_agents"] = unowned
        payload["components"]["untested_high_risk"] = untested
    if args.check:
        base = json.load(open(base_path, encoding="utf-8"))
        if entropy > base["entropy"]:
            print(f"FAIL: entropía {entropy} > baseline {base['entropy']} — consolidar antes de crecer")
            return 1
        print(f"PASS: entropía {entropy} <= baseline {base['entropy']}")
        return 0

    if os.path.exists(base_path):
        if args.v1:
            # Calibración v1: solo toca los campos v1. El ratchet v0 (entropy y
            # sus componentes) jamás se reescribe desde aquí: hacerlo subiría la
            # baseline en silencio (RN-03: el budget nunca sube).
            base = json.load(open(base_path, encoding="utf-8"))
            base["entropy_v1"] = payload["entropy_v1"]
            for k in ("unowned_agents", "untested_high_risk"):
                base.setdefault("components", {})[k] = payload["components"][k]
            with open(base_path, "w", encoding="utf-8") as f:
                json.dump(base, f, indent=2, sort_keys=True)
                f.write("\n")
            print(f"entropy v1 = {payload.get('entropy_v1')} congelado (calibración); "
                  f"v0 baseline {base['entropy']} intacto (actual {entropy})")
        else:
            print(f"entropy v0 = {entropy} (baseline congelado: "
                  f"{json.load(open(base_path))['entropy']}); usa --check para ratchet")
    else:
        with open(base_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"entropy v0 = {entropy} congelado en {base_path} (primera medición)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
