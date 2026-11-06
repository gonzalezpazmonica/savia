#!/usr/bin/env python3
"""
plan-validate.py — SE-358: valida plan.md (formato del playbook).

Verifica que un plan.md tenga las secciones requeridas:
  Files that change / Order of work / Risks / Proof

Uso:
  plan-validate.py --plan plan.md            # exit 0 si válido, 2 si malformado
  plan-validate.py --plan plan.md --json     # salida JSON
  plan-validate.py --files plan.md           # lista los archivos del plan

Fail-soft: un plan malformado no bloquea (exit 2 informativo), salvo --strict.

Ref: SE-358 — plan.md verificado
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REQUIRED_SECTIONS = ["Files that change", "Order of work", "Risks", "Proof"]
FILES_MARKER = "Files that change"


def parse_plan(path: str | Path) -> dict:
    """Extrae secciones y archivos de un plan.md."""
    p = Path(path)
    if not p.exists():
        return {"valid": False, "errors": [f"archivo no existe: {p}"], "files": []}

    text = p.read_text(encoding="utf-8")
    lower = text.lower()
    present = [s for s in REQUIRED_SECTIONS if s.lower() in lower]
    missing = [s for s in REQUIRED_SECTIONS if s.lower() not in lower]

    # Extraer archivos listados bajo "Files that change"
    files: list[str] = []
    # Cabecera en su propia línea; el bloque acaba en la siguiente cabecera.
    # [ \t] y no \s: una sección vacía no debe tragarse la siguiente.
    m = re.search(r"(?ims)^#+[ \t]*Files that change[ \t]*\n(.*?)(?=^#+\s|\Z)", text)
    if m:
        block = m.group(1)
        for line in block.splitlines():
            line = line.strip().lstrip("-*").strip()
            if not line or line.startswith("#") or line.startswith("```"):
                continue
            # La spec admite varias rutas por línea separadas por comas.
            for item in line.split(","):
                # quitar anotaciones tipo (new)/(modified) y comillas de código
                name = re.sub(r"\s*\((new|modified|deleted)\)\s*$", "", item.strip())
                name = name.strip().strip("`").strip()
                if name and name not in files:
                    files.append(name)

    errors = []
    if missing:
        errors.append(f"faltan secciones: {', '.join(missing)}")
    if not files:
        errors.append("no se listan archivos bajo 'Files that change'")

    return {"valid": not errors, "errors": errors, "files": files, "present": present}


def main() -> int:
    parser = argparse.ArgumentParser(description="Validador de plan.md (SE-358)")
    parser.add_argument("--plan", required=True, help="ruta al plan.md")
    parser.add_argument("--json", action="store_true", help="salida JSON")
    parser.add_argument("--files", action="store_true", help="solo lista de archivos")
    parser.add_argument("--strict", action="store_true", help="exit != 0 si malformado")
    args = parser.parse_args()

    result = parse_plan(args.plan)

    if args.files:
        for f in result["files"]:
            print(f)
        return 0 if result["files"] else 2

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if result["valid"]:
            print(f"OK: {args.plan} — {len(result['files'])} archivos, secciones completas")
        else:
            for e in result["errors"]:
                print(f"WARN: {e}", file=sys.stderr)

    if not result["valid"] and args.strict:
        return 2
    if "archivo no existe" in " ".join(result.get("errors", [])):
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
