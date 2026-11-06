#!/usr/bin/env python3
"""
review-policy-parse.py — SE-359: parsea REVIEW.md (política canónica de review).

Extrae de REVIEW.md:
  - passes (secciones con instrucciones)
  - severidad (Important vs Nit)
  - cap de nits
  - exclusiones (paths a no reportar)

Salida JSON consumible por el Code Review Court.

Uso:
  review-policy-parse.py --file REVIEW.md [--json]

Si REVIEW.md no existe → fail-soft con defaults (no rompe el court).

Ref: SE-359 — REVIEW.md policy (playbook Anthropic Stage 5)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULTS = {
    "passes": ["Bugs", "Security", "Compliance"],
    "important": "findings that break behavior, leak data or breach a policy",
    "nit_cap": 5,
    "exclusions": ["generated", "src/gen", "CI-enforced"],
}


def parse_policy(path: str | Path) -> dict:
    """Extrae la política de REVIEW.md (o defaults si no existe)."""
    p = Path(path)
    if not p.exists():
        return {**DEFAULTS, "source": str(p), "exists": False}

    text = p.read_text(encoding="utf-8")

    # Passes: elementos de lista «- **Nombre**: ...» o «- Nombre: ...» bajo
    # «## Passes». La prosa del bloque no es un pass.
    passes = []
    m = re.search(r"(?ism)^## Passes[ \t]*\n(.*?)(?=^## |\Z)", text)
    if m:
        for line in m.group(1).splitlines():
            lm = re.match(r"^\s*[-*]\s+(?:\*\*)?([^:*]+?)(?:\*\*)?\s*:", line)
            if lm:
                name = lm.group(1).strip()
                if name and name.lower() not in [x.lower() for x in passes]:
                    passes.append(name)

    # Severidad: primer párrafo de «## What Important means here» (unido).
    important = DEFAULTS["important"]
    m = re.search(r"(?ism)^## What Important means here[ \t]*\n(.*?)(?=^## |\Z)", text)
    if m:
        para = m.group(1).strip().split("\n\n")[0]
        joined = " ".join(x.strip() for x in para.splitlines() if x.strip())
        if joined:
            important = joined

    # Cap de nits: «at most N nits», con o sin negrita/cursiva alrededor de N.
    nit_cap = DEFAULTS["nit_cap"]
    m = re.search(r"(?i)at most\s+[*_]*(\d+)[*_]*\s+nits", text)
    if m:
        nit_cap = int(m.group(1))

    # Exclusiones: cada elemento de lista de «## Do not report»; las líneas de
    # continuación (sangradas, sin viñeta) se unen a su elemento.
    exclusions: list[str] = []
    m = re.search(r"(?ism)^## Do not report[ \t]*\n(.*?)(?=^## |\Z)", text)
    if m:
        for line in m.group(1).splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if re.match(r"^[-*]\s+", stripped):
                exclusions.append(re.sub(r"^[-*]\s+", "", stripped))
            elif exclusions and line[:1] in (" ", "\t"):
                exclusions[-1] += " " + stripped
            else:
                exclusions.append(stripped)

    if not passes:
        passes = DEFAULTS["passes"]

    return {
        "source": str(p),
        "exists": True,
        "passes": passes,
        "important": important,
        "nit_cap": nit_cap,
        "exclusions": exclusions or DEFAULTS["exclusions"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Parser de REVIEW.md (SE-359)")
    parser.add_argument("--file", required=True, help="ruta a REVIEW.md")
    parser.add_argument("--json", action="store_true", help="salida JSON")
    args = parser.parse_args()

    policy = parse_policy(args.file)

    if args.json:
        print(json.dumps(policy, indent=2, ensure_ascii=False))
    else:
        print(f"REVIEW policy ({policy['source']}):")
        print(f"  passes: {', '.join(policy['passes'])}")
        print(f"  nit_cap: {policy['nit_cap']}")
        print(f"  important: {policy['important']}")
        print(f"  exclusions: {', '.join(policy['exclusions'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
