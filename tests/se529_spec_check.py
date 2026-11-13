#!/usr/bin/env python3
"""SE-529: comprobador de coherencia de la spec de compactación.

Uso: python3 -I tests/se529_spec_check.py <spec.md> [<raiz-repo>]
Exit 0 si es coherente; 1 con un motivo por línea en stderr; 2 si no se puede leer.

Parte ejecutable: cada referencia `fichero:línea` de la spec debe existir en la raíz del
repo y la línea no puede exceder la longitud del fichero (evita citar código inventado).
Parte textual: cada AC, slice y frase de honestidad obligatoria está escrita. Límite
declarado: lo textual solo prueba que la frase está, no que el diseño sea correcto.
"""
import os
import re
import sys

ERR = []


def err(msg):
    ERR.append(msg)


def main():
    if len(sys.argv) < 2:
        print("uso: se529_spec_check.py <spec.md> [raiz]", file=sys.stderr)
        return 2
    spec_path = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()
    try:
        text = open(spec_path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as e:
        print("no se puede leer: %s" % e, file=sys.stderr)
        return 2

    fm = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not fm:
        err("sin frontmatter")
    else:
        if not re.search(r"^status:\s*PROPOSED\s*$", fm.group(1), re.M):
            err("frontmatter: status debe ser PROPOSED")
        if not re.search(r"^risk:\s*L2\s*$", fm.group(1), re.M):
            err("frontmatter: risk L2 (tier 2) ausente")

    # Referencias fichero:línea verificables
    refs = re.findall(r"`((?:\.?[A-Za-z0-9_./-]+/)?[A-Za-z0-9_.-]+\.(?:sh|ts|json|bats|py)):(\d+)(?:-(\d+))?", text)
    if len(refs) < 8:
        err("pocas referencias fichero:línea (%d < 8)" % len(refs))
    for path, a, b in refs:
        full = os.path.realpath(os.path.join(root, path))
        real_root = os.path.realpath(root)
        if os.path.isabs(path) or os.path.commonpath([real_root, full]) != real_root:
            err("referencia fuera de la raíz del repo: %s" % path)
            continue
        if not os.path.isfile(full):
            err("referencia a fichero inexistente: %s" % path)
            continue
        n = sum(1 for _ in open(full, encoding="utf-8", errors="replace"))
        hi = int(b) if b else int(a)
        if hi > n:
            err("referencia fuera de rango: %s:%s (el fichero tiene %d líneas)" % (path, hi, n))

    # AC-1..AC-16
    for i in range(1, 17):
        if not re.search(r"^- \[ \] \*\*AC-%d " % i, text, re.M):
            err("falta AC-%d" % i)
    if re.search(r"^- \[x\] \*\*AC-", text, re.M):
        err("un AC marcado como cumplido en una spec PROPOSED")

    # Slices
    for s in ("S0", "S1", "S2", "S3", "S4", "S5"):
        if not re.search(r"^#{2,3} Slice? ?%s\b" % s, text, re.M) and not re.search(r"^#{2,3} %s\b" % s, text, re.M) and not re.search(r"^## Slice %s\b" % s, text, re.M):
            err("falta la sección de %s" % s)

    required = [
        ("escenas antes/después", "*Antes:*"),
        ("S0 fija parámetros antes de S1/S2", "antes de ver el resultado de S1/S2"),
        ("canal de reinyección medido", "S0.2 Canal de reinyección"),
        ("ruta no fiable", "realpath"),
        ("solo texto de conversación, no resultados de herramientas", "no resultados de herramientas"),
        ("S4 puede ser no aplicable", "**no aplicable**"),
        ("idempotencia por huella", "sha-256"),
        ("estados del archivado", "confirmado, fallido, desconocido, no disponible"),
        ("fail honesto", "no confirmado"),
        ("tests fallan antes (SE-456)", "debe fallar (SE-456)"),
        ("settings.json es tier 4 y aparte", "tier 4"),
        ("reversión sin migración", "sin migración de datos"),
        ("paridad", "DUAL_BINDING"),
        ("plantilla OpenCode", "## OpenCode Implementation Plan"),
        ("preguntas abiertas", "## Preguntas abiertas"),
        ("redacción de privados", "multilínea"),
        ("sin cambiar el esquema", "No cambia el esquema del almacén"),
        ("nada de contenido real en el repo", "ningún fragmento de conversación real"),
        ("comprobado, no supuesto", "sin medir"),
        ("Q2 resuelta", "**Q2 (resuelta, 2026-11-13).**"),
        ("Q2 registrada como registro de la orquestadora", "registro de la orquestadora"),
        ("paridad por aviso explícito (Q2)", "ese aviso se acepta como paridad (Q2, resuelta)"),
        ("S1 sin fuente alternativa (Q2)", "no se busca una fuente alternativa"),
        ("Q1 abierta", "- **Q1.**"),
        ("Q3 abierta", "- **Q3.**"),
    ]
    # La confirmación debe seguir pendiente: línea de lista «respuesta ...: pendiente».
    if not re.search(r"^- respuesta[^\n:]*: pendiente", text, re.M):
        err("falta frase obligatoria (confirmación pendiente): - respuesta ...: pendiente")
    for name, phrase in required:
        if phrase not in text:
            err("falta frase obligatoria (%s): %s" % (name, phrase))

    extras = [os.path.join(root, f) for f in (
        "CHANGELOG.d/se529-compactacion.md",
        "docs/propuestas/LOG.d/SE-529-PROPOSED.md",
        "docs/propuestas/planning.d/SE-529.json")]
    # Confidencialidad del repo público
    # Los términos se parten para que este fichero no contenga los literales que busca.
    # Alfanuméricos: frontera de palabra. Ruta (empieza en «.»): sin \b, que exigiría
    # un carácter de palabra antes del punto y no casaría tras «/», «~/» o espacio.
    terms = ["mac" + "book", "accen" + "ture", "m[oó]" + "nica", "inten" + "sivo", "reconc" + "iliar", "des" + "til", "Savia" + "Labs"]
    banned = re.compile(r"(?<!\w)(?:" + "|".join(terms) + r")(?!\w)|(?<!\w)\.sa" + r"via/", re.I)
    for n, line in enumerate(text.splitlines(), 1):
        if banned.search(line):
            err("línea %d con término no permitido en repo público" % n)
    # Los demás ficheros públicos de SE-529 (changelog, log, planning) también se escanean.
    for extra in extras:
        try:
            lines = open(extra, encoding="utf-8").read().splitlines()
        except (OSError, UnicodeDecodeError) as e:
            err("%s ausente o ilegible, no se puede escanear: %s" % (os.path.basename(extra), type(e).__name__))
            continue
        for n, line in enumerate(lines, 1):
            if banned.search(line):
                err("%s línea %d con término no permitido en repo público" % (os.path.basename(extra), n))

    for m in ERR:
        print(m, file=sys.stderr)
    return 1 if ERR else 0


if __name__ == "__main__":
    sys.exit(main())
