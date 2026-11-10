#!/usr/bin/env python3
"""generate-savia-core.py — SE-511 S2 (D1): bloque compacto de arranque.

Genera docs/rules/domain/savia-core.md extrayendo, literal y en orden fijo,
las regiones marcadas en las fuentes de verdad:

    <!-- savia-core:<id> -->
    ...texto...
    <!-- /savia-core:<id> -->

más la frase corta de identidad (<!-- identity:short -->, SE-483). El bloque
no se redacta a mano: se edita la fuente y se regenera (AC-5).

Uso:
  python3 scripts/generate-savia-core.py            escribe el bloque
  python3 scripts/generate-savia-core.py --check    exit 1 si el bloque difiere
  python3 scripts/generate-savia-core.py --stdout   imprime el bloque sin escribir

Fail-closed: fuente ausente, región ausente, duplicada, sin cierre o vacía
→ exit 1 sin escribir nada. Env: SAVIA_CORE_ROOT (raíz alternativa, tests).
"""
import os
import re
import sys

OUT = "docs/rules/domain/savia-core.md"

# (título de sección, fichero fuente, [ids de región en orden])
SECTIONS = [
    ("Identidad", ".claude/profiles/savia.md", ["identity:short", "savia-core:identidad"]),
    ("Cómo habla", ".claude/profiles/savia.md", ["savia-core:principios"]),
    ("Voz: frases que sí son de Savia", ".claude/profiles/savia.md", ["savia-core:frases-si"]),
    ("Voz: frases que Savia no dice", ".claude/profiles/savia.md", ["savia-core:frases-no"]),
    ("Radical Honesty (Rule #24): prohibiciones", "docs/rules/domain/radical-honesty.md",
     ["savia-core:prohibiciones"]),
    ("Radical Honesty (Rule #24): obligaciones", "docs/rules/domain/radical-honesty.md",
     ["savia-core:obligaciones"]),
    ("Caveman: brevedad por defecto", "docs/rules/domain/caveman-default.md",
     ["savia-core:reglas", "savia-core:excepciones"]),
    ("Seguridad autónoma (inmutable)", "docs/rules/domain/autonomous-safety.md",
     ["savia-core:autonomia", "savia-core:obligaciones"]),
]

ON_DEMAND = (
    "Texto completo, ejemplos y tablas de tono, bajo demanda: `.claude/profiles/savia.md`, "
    "`docs/rules/domain/radical-honesty.md`, `docs/rules/domain/caveman-default.md`, "
    "`docs/rules/domain/autonomous-safety.md`, `docs/rules/domain/savia-ethical-principles.md`."
)


class GenError(Exception):
    pass


def extract(text, rid, src):
    op, cl = f"<!-- {rid} -->", f"<!-- /{rid} -->"
    lines = text.splitlines()
    starts = [i for i, l in enumerate(lines) if l.strip() == op]
    if not starts:
        raise GenError(f"región '{rid}' ausente en {src}")
    if len(starts) > 1:
        raise GenError(f"región '{rid}' duplicada en {src}")
    s = starts[0]
    ends = [i for i, l in enumerate(lines) if l.strip() == cl and i > s]
    if not ends:
        raise GenError(f"región '{rid}' sin cierre en {src}")
    body = lines[s + 1:ends[0]]
    if any(l.strip().startswith("<!-- savia-core:") for l in body):
        raise GenError(f"región '{rid}' anidada o sin cierre previo en {src}")
    if not "".join(body).strip():
        raise GenError(f"región '{rid}' vacía en {src}")
    out = []
    for l in body:
        if rid == "identity:short":
            l = re.sub(r"^> ?", "", l)
        # Las cabeceras de la fuente bajan dos niveles: el bloque usa ## por sección.
        m = re.match(r"^(#{1,4}) (.*)$", l)
        if m:
            l = "#" * min(len(m.group(1)) + 2, 6) + " " + m.group(2)
        out.append(l.rstrip())
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return "\n".join(out)


def render(root):
    parts = []
    for title, src, ids in SECTIONS:
        path = os.path.join(root, src)
        if not os.path.isfile(path):
            raise GenError(f"fuente ausente: {src}")
        text = open(path, encoding="utf-8").read()
        chunk = "\n\n".join(extract(text, rid, src) for rid in ids)
        parts.append(f"## {title}\n\n<!-- fuente: {src} -->\n{chunk}")
    body = (
        "# Savia — núcleo de arranque\n\n"
        "> GENERADO por `scripts/generate-savia-core.py` (SE-511 D1). No editar: editar las "
        "regiones `savia-core:*` de las fuentes y regenerar. `--check` falla si difiere.\n\n"
        + "\n\n".join(parts)
        + "\n\n## Bajo demanda\n\n" + ON_DEMAND + "\n"
    )

    def front(budget):
        return f"---\ncontext_tier: L1\ntoken_budget: {budget}\n---\n\n"

    # Presupuesto declarado honesto (>= bytes/4, test SPEC-181), redondeado a 50.
    budget = 0
    for _ in range(3):
        need = len((front(budget) + body).encode("utf-8")) // 4
        budget = -(-need // 50) * 50
    return front(budget) + body


def main(argv):
    root = os.environ.get("SAVIA_CORE_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mode = argv[1] if len(argv) > 1 else "--write"
    if mode not in ("--write", "--check", "--stdout"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        content = render(root)
    except GenError as e:
        print(f"generate-savia-core: ERROR {e}", file=sys.stderr)
        return 1
    out = os.path.join(root, OUT)
    if mode == "--stdout":
        sys.stdout.write(content)
        return 0
    if mode == "--check":
        cur = open(out, encoding="utf-8").read() if os.path.isfile(out) else None
        if cur != content:
            print(f"generate-savia-core: DRIFT {OUT} no coincide con sus fuentes; "
                  "regenerar con python3 scripts/generate-savia-core.py", file=sys.stderr)
            return 1
        print(f"generate-savia-core: OK {OUT} al día")
        return 0
    with open(out, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"generate-savia-core: escrito {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
