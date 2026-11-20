#!/usr/bin/env python3
"""SE-448 S0: cuenta documentos de terceros con texto imperativo dirigido a agentes.

Mide, no bloquea. Método (reproducible): recorre los ficheros de texto bajo las
raíces dadas (por defecto `external/`), descarta los bloques de código vallados,
y aplica patrones por línea en cuatro categorías:

  override      "ignora las instrucciones anteriores" y variantes
  agent-modal   alusión a un agente/IA/«you» + verbo modal imperativo en la misma línea
  action-ban    prohibición o cambio de acción de entrega ("no despliegues", "cambia al revisor")
  exfil         orden de enviar/subir algo a una URL

Salida: SOLO recuentos y rutas relativas (nunca el texto coincidente), para poder
publicarla aunque el documento sea privado. Los ficheros que son instrucciones de
agente por diseño (SKILL.md, agents/*.md, CLAUDE.md, AGENTS.md) se cuentan aparte:
dirigirse a un agente es su función, no un hallazgo. Se omiten LICENSE/NOTICE/COPYING
(texto legal con «you must»). Límite: heurística léxica; no detecta órdenes sin
mención de agente ni en otros idiomas, y no distingue un modal dirigido a una
persona lectora de uno dirigido a un agente. Da una cota, no una prueba.

Uso: third-party-directives.py [--root DIR ...] [--json]
Salida 0 siempre que la medición termine; 2 si una raíz no existe (fail-closed).
"""
import argparse
import json
import os
import re
import sys

TEXT_EXT = {".md", ".txt", ".rst", ".html", ".htm", ".yaml", ".yml", ".json", ".py", ".sh", ".ts", ".js", ".mdx"}
SKIP_NAME = re.compile(r"^(LICENSE|LICENCE|NOTICE|COPYING)(\.[A-Za-z]+)?$")
BY_DESIGN = re.compile(r"(^|/)(SKILL\.md|CLAUDE\.md|AGENTS\.md|agents/[^/]+\.md)$")

AGENT = r"(?:\bclaude\b|\b(?:the |an? )?(?:ai|llm|agent|assistant|model)\b|\b(?:el |la )?(?:agente|asistente|modelo|ia)\b)"
MODAL = r"(?:\bmust\b|\bshould\b|\balways\b|\bnever\b|\bdo not\b|\bdon't\b|\bdebes\b|\bdebe\b|\bnunca\b|\bsiempre\b|\bno debes\b)"
PATTERNS = {
    "override": [
        r"\bignore\s+(?:all\s+|any\s+|the\s+)?(?:previous|prior|above|earlier)\s+(?:instructions|rules|prompts?)",
        r"\bdisregard\s+(?:all\s+|any\s+|the\s+)?(?:previous|prior|above)\s+(?:instructions|rules)",
        r"\bignora\s+(?:todas\s+)?las\s+(?:instrucciones|reglas)\s+anteriores",
    ],
    "agent-modal": [AGENT + r".{0,60}" + MODAL, MODAL + r".{0,60}" + AGENT],
    "action-ban": [
        r"\b(?:do not|don't|never|no|nunca)\s+(?:deploy|publish|push|merge|commit|despliegues?|publiques?|fusiones?)\b",
        r"\b(?:switch|change|cambia(?:r)?)\s+(?:to\s+|al?\s+)?(?:the\s+)?(?:reviewer|revisor)",
    ],
    "exfil": [
        r"\b(?:send|post|upload|exfiltrate|env[ií]a|sube)\b.{0,60}https?://",
    ],
}
COMPILED = {k: [re.compile(p, re.IGNORECASE) for p in v] for k, v in PATTERNS.items()}
FENCE = re.compile(r"^\s*(```|~~~)")


def scan_text(text):
    """Devuelve {categoría: nº de líneas que casan} fuera de bloques vallados."""
    counts = {k: 0 for k in COMPILED}
    fenced = False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        for cat, pats in COMPILED.items():
            if any(p.search(line) for p in pats):
                counts[cat] += 1
    return counts


def scan_roots(roots):
    files = []
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in {".git", "node_modules", "target"})
            for fn in sorted(filenames):
                if SKIP_NAME.match(fn) or os.path.splitext(fn)[1].lower() not in TEXT_EXT:
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    with open(path, encoding="utf-8") as fh:
                        text = fh.read()
                except (UnicodeDecodeError, OSError):
                    continue
                c = scan_text(text)
                files.append({
                    "path": path.replace(os.sep, "/"),
                    "by_design": bool(BY_DESIGN.search(path.replace(os.sep, "/"))),
                    "counts": c,
                    "directive": sum(c.values()) > 0,
                })
    return files


def summarize(files):
    other = [f for f in files if not f["by_design"]]
    design = [f for f in files if f["by_design"]]
    return {
        "scanned_files": len(files),
        "not_by_design": {"files": len(other), "with_directive": sum(f["directive"] for f in other)},
        "by_design": {"files": len(design), "with_directive": sum(f["directive"] for f in design)},
        "with_directive_paths_not_by_design": [f["path"] for f in other if f["directive"]],
        "with_directive_paths_by_design": [f["path"] for f in design if f["directive"]],
        "per_file": files,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", action="append", help="raíz a medir (repetible); por defecto external/")
    ap.add_argument("--json", action="store_true", help="salida JSON completa")
    a = ap.parse_args(argv)
    roots = a.root or ["external"]
    for r in roots:
        if not os.path.isdir(r):
            print(f"ERROR: raíz inexistente: {r}", file=sys.stderr)
            return 2
    s = summarize(scan_roots(roots))
    if a.json:
        print(json.dumps(s, indent=2, ensure_ascii=False))
    else:
        nd, d = s["not_by_design"], s["by_design"]
        print(f"scanned_files={s['scanned_files']}")
        print(f"not_by_design files={nd['files']} with_directive={nd['with_directive']}")
        print(f"by_design files={d['files']} with_directive={d['with_directive']}")
        for p in s["with_directive_paths_not_by_design"]:
            print(f"directive: {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
