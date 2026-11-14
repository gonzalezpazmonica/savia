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
        # APPROVED exige una aprobación verificable en la PR (SE-505, SE-488); el prototipo
        # ya está confirmado (2026-11-14) pero la aprobación solo consta como registro de la
        # orquestadora: el estado correcto sigue siendo PROPOSED.
        if not re.search(r"^status:\s*PROPOSED\s*$", fm.group(1), re.M):
            err("frontmatter: status debe ser PROPOSED mientras la aprobación no conste de forma verificable")
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
        err("un AC marcado como cumplido en una spec aún sin implementar")

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
        ("Q2 registrada como registro de la orquestadora", "registro de la orquestadora, no texto literal"),
        ("paridad por aviso explícito (Q2)", "ese aviso se acepta como paridad (Q2, resuelta)"),
        ("S1 sin fuente alternativa (Q2)", "no se busca una fuente alternativa"),
        ("Q1 resuelta", "- **Q1 (resuelta, 2026-11-13).**"),
        ("Q3 resuelta", "- **Q3 (resuelta, 2026-11-13).**"),
        ("S0 con prototipo", "- prototipo: "),
    ]
    # Confirmación de las escenas: fecha real y respuesta literal entre «…», no vacía.
    conf = re.search(r"^### Confirmación\n(.*?)(?=^#{1,3} )", text, re.M | re.S)
    body = conf.group(1) if conf else ""
    if not re.search(r"^- fecha: 2026-11-1[3-9]\s*$", body, re.M):
        err("confirmación de las escenas sin fecha")
    if not re.search(r"^- respuesta: «[^»\s][^»]*»", body, re.M):
        err("confirmación de las escenas sin respuesta literal")
    # Confirmación del prototipo (2026-11-14): fecha real y respuesta entre «…», no vacía,
    # y ningún «pendiente» residual en el slice S0 (SE-505).
    s0 = re.search(r"^## Slice S0\b.*?(?=^## )", text, re.M | re.S)
    s0b = s0.group(0) if s0 else ""
    pc = re.search(r"^### Confirmación del prototipo\n(.*?)(?=^#{1,3} )", s0b + "\n## ", re.M | re.S)
    pb = pc.group(1) if pc else ""
    if not re.search(r"^- fecha: 2026-11-1[4-9]\s*$", pb, re.M):
        err("confirmación del prototipo sin fecha")
    if not re.search(r"^- respuesta: «[^»\s][^»]*»", pb, re.M):
        err("confirmación del prototipo sin respuesta literal")
    if re.search(r"^- (?:prototipo|fecha|respuesta): pendiente", s0b, re.M):
        err("S0 conserva un campo pendiente (prototipo o confirmación)")
    if "prototipo pendiente" in text.lower():
        err("la spec aún dice «prototipo pendiente»")
    # Coherencia del estado en planning y roadmap (fuente: la spec, aquí PROPOSED).
    plan_path = os.path.join(root, "docs/propuestas/planning.d/SE-529.json")
    try:
        import json
        plan = json.load(open(plan_path, encoding="utf-8"))
        if plan.get("status") != "PROPOSED" or "approval" in plan:
            err("planning: SE-529 debe ser PROPOSED y sin campo approval")
    except (OSError, ValueError, UnicodeDecodeError):
        pass  # ausente o ilegible: lo comunica el escaneo de ficheros públicos
    try:
        road = open(os.path.join(root, "docs/propuestas/ROADMAP-CURRENT.md"), encoding="utf-8").read()
        if re.search(r"^- SE-529 \[APPROVED\]", road, re.M):
            err("roadmap: SE-529 figura APPROVED con la spec en PROPOSED")
    except (OSError, UnicodeDecodeError):
        err("ROADMAP-CURRENT.md ausente o ilegible, no se puede comprobar el estado")
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
