#!/usr/bin/env python3
"""derived_canon.py — SE-501: forma canónica y validación interna de los derivados (D).

Uso:
  derived_canon.py same <ruta-D> <fichero-a> <fichero-b>   → 0 iguales en forma canónica · 1 distintos · 2 ilegible
  derived_canon.py validate <ruta-D> <fichero>             → 0 válido · 1 inválido (motivo en stderr)

Forma canónica (sin marca de tiempo, como fija SE-500 S2):
  docs/rules/domain/rule-manifest.json  JSON sin la clave «generated».
  docs/rules/INDEX.md                   sin la fecha de la línea 1.
  resto de D (.scm/…)                   bytes.

Importable: ensure(root, rels, group) y ENSURE_HINT para los lectores de D en Python (SE-501 AC-11).
"""
import json
import re
import sys

MANIFEST = "docs/rules/domain/rule-manifest.json"
INDEX = "docs/rules/INDEX.md"
MANIFEST_KEYS = ("generated", "total", "tier1_count", "tier2_count", "dormant_count", "rules")
MANIFEST_DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
INDEX_HEAD = re.compile(r"# Rules Index — auto-generated ([0-9]{4}-[0-9]{2}-[0-9]{2}) · ([0-9]+) rules")
INDEX_ROW = re.compile(r"\| [^|]* \| \[[^\]]+\]\(domain/[^)]+\) \|")


class Invalid(Exception):
    pass


def read(p):
    with open(p, "rb") as f:
        return f.read()


def validate(path, raw):
    if path == MANIFEST:
        d = json.loads(raw.decode("utf-8"))
        if not isinstance(d, dict) or any(k not in d for k in MANIFEST_KEYS):
            raise Invalid("rule-manifest.json sin las claves obligatorias")
        if not isinstance(d["generated"], str) or not MANIFEST_DATE.fullmatch(d["generated"]):
            raise Invalid("rule-manifest.json con «generated» inválido")
        if not isinstance(d["rules"], dict) or d["total"] != len(d["rules"]):
            raise Invalid("rule-manifest.json: total no coincide con las reglas")
        if d["tier1_count"] + d["tier2_count"] + d["dormant_count"] != d["total"]:
            raise Invalid("rule-manifest.json: los recuentos por tier no suman el total")
    elif path == INDEX:
        lines = raw.decode("utf-8").split("\n")
        m = INDEX_HEAD.fullmatch(lines[0]) if lines else None
        if not m:
            raise Invalid("INDEX.md sin cabecera con fecha y recuento")
        rows = sum(1 for l in lines if INDEX_ROW.match(l))
        if rows != int(m.group(2)):
            raise Invalid(f"INDEX.md: {rows} filas para {m.group(2)} reglas")
    elif path.endswith(".json"):
        json.loads(raw.decode("utf-8"))


def canon(path, raw):
    if path == MANIFEST:
        d = json.loads(raw.decode("utf-8"))
        d.pop("generated", None)
        return d
    if path == INDEX:
        lines = raw.decode("utf-8").split("\n")
        if lines and INDEX_HEAD.fullmatch(lines[0]):
            lines[0] = INDEX_HEAD.sub(lambda m: f"# Rules Index — auto-generated · {m.group(2)} rules", lines[0])
        return "\n".join(lines)
    return raw


# ── SE-501 AC-11: lectores de D en Python ───────────────────────────────────
# D no se versiona. Un lector llama a ensure() antes de leer; si D sigue faltando, el lector termina con
# ≠ 0 y su mensaje incluye ENSURE_HINT (la orden que lo arregla).
ENSURE_HINT = "ejecutar: bash scripts/derived.sh ensure"


def is_own_repo(root):
    """¿Es `root` el repo que acompaña a este módulo? Solo ahí puede ensure() generar D."""
    import os
    here = os.path.dirname(os.path.realpath(__file__))
    return os.path.realpath(os.fspath(root)) == os.path.dirname(here)


def ensure(root, rels, group="scm"):
    """Si falta alguna ruta de `rels` bajo `root`, ejecuta «bash scripts/derived.sh ensure --only <group>».
    Devuelve las rutas que siguen faltando (lista vacía = todas presentes).
    Solo ejecuta el derived.sh que acompaña a este módulo y solo si `root` es su propio repo: nunca
    ejecuta código de una raíz ajena (--root a otro árbol, fixture). Ahí devuelve lo que falta."""
    import os
    import subprocess
    root = os.path.realpath(os.fspath(root))
    here = os.path.dirname(os.path.realpath(__file__))
    def missing():
        return [r for r in rels if not os.path.isfile(os.path.join(root, r))]
    gone = missing()
    script = os.path.join(here, "derived.sh")
    if gone and is_own_repo(root) and os.path.isfile(script):
        subprocess.run(["bash", script, "ensure", "--only", group], cwd=root,
                       stdout=sys.stderr, stdin=subprocess.DEVNULL, check=False)
        gone = missing()
    return gone


DERIVED_LIST = "scripts/derived-paths.txt"


def derived_entries(root):
    """Entradas de la lista cerrada D de `root` (exactas, o prefijos si acaban en «/»). Sin lista: ()."""
    import os
    try:
        with open(os.path.join(os.fspath(root), DERIVED_LIST), encoding="utf-8") as fh:
            return tuple(l.strip() for l in fh if l.strip() and not l.lstrip().startswith("#"))
    except OSError:
        return ()


def is_derived(path, entries):
    return any(path == e or (e.endswith("/") and path.startswith(e)) for e in entries)


def main(argv):
    try:
        if len(argv) == 4 and argv[0] == "same":
            return 0 if canon(argv[1], read(argv[2])) == canon(argv[1], read(argv[3])) else 1
        if len(argv) == 3 and argv[0] == "validate":
            validate(argv[1], read(argv[2]))
            return 0
    except Invalid as e:
        print(f"derived_canon: {e}", file=sys.stderr)
        return 1
    except (OSError, UnicodeDecodeError, ValueError) as e:
        print(f"derived_canon: {argv[1]}: ilegible ({e})", file=sys.stderr)
        return 2
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
