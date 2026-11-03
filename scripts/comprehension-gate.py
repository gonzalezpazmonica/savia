#!/usr/bin/env python3
"""comprehension-gate.py — SE-505: puerta de comprensión de las specs con superficie humana.

Una spec que toca una interfaz o una experiencia humana no puede estar APPROVED,
IMPLEMENTING ni IMPLEMENTED sin la sección «Lo que he entendido» completa y confirmada
por la persona que pidió el producto. Además declara un slice S0 de prototipo
navegable, y ningún slice posterior se marca en curso sin la confirmación de S0.

Regla: docs/rules/domain/comprehension-gate.md.

Uso:
  comprehension-gate.py [--root DIR] [--state planning-state.json] [--spec FICHERO ...]

Sin --spec revisa docs/specs/SE-*.spec.md y docs/propuestas/SE-*.md de --root.
Salida: 0 PASS · 1 FAIL (incluye ficheros ilegibles: fail-closed) · 2 uso.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Ámbito: specs numeradas desde SE-504 (la primera propuesta tras la decisión del 2026-11-03)
# o aprobadas a partir del día siguiente. Lo aprobado antes no se reabre (ver la spec SE-505).
SPEC_FLOOR = 504
CUTOFF = "2026-11-04"
GATED_STATUSES = {"APPROVED", "IMPLEMENTING", "IMPLEMENTED"}
STARTED_STATUSES = {"IMPLEMENTING", "IMPLEMENTED"}
SCENES_MIN, SCENES_MAX = 3, 5

DATE_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b")
# Rutas de superficie humana citadas en la spec entre comillas invertidas.
SURFACE_RE = re.compile(
    r"`(?:\./)?(?:"
    r"apps/|ui/"
    r"|projects/[^/`\s]+/(?:src/web|web|ui|app|android|ios|mobile|frontend)(?:/|`)"
    r"|projects/[^/`\s]*(?:web|mobile|space)[^/`\s]*/"
    r"|[^`\s]+\.(?:tsx|jsx|vue|svelte|html|css)(?::\d+)?`"
    r")"
)
ITEM_RE = re.compile(r"^(?: ?)(?:\d+[.)]|[-*]) +\S")
QUOTE_RE = re.compile(r"«([^»]*)»")
PLACEHOLDER_RE = re.compile(r"^\s*(?:\{.*\}|pendiente|tbd|todo|\.\.\.|…|-)?\s*$", re.I)


def frontmatter(text: str) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fm: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return fm
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return {}  # frontmatter sin cerrar: se trata como ausente


def section(text: str, heading_re: str, level: int) -> str | None:
    """Cuerpo de la primera sección cuyo título casa con heading_re, hasta el siguiente
    título de nivel <= level. None si no existe."""
    lines = text.splitlines()
    pat = re.compile(r"^(#{%d})\s+(?:%s)\s*$" % (level, heading_re), re.I)
    for i, line in enumerate(lines):
        if pat.match(line):
            body = []
            for nxt in lines[i + 1:]:
                h = re.match(r"^(#+)\s", nxt)
                if h and len(h.group(1)) <= level:
                    break
                body.append(nxt)
            return "\n".join(body)
    return None


def items(body: str) -> int:
    return sum(1 for line in body.splitlines() if ITEM_RE.match(line))


def field(body: str, name: str) -> str:
    # Solo espacios en línea: un campo vacío no puede tomar el valor de la línea siguiente.
    m = re.search(r"^[ \t]*[-*]?[ \t]*\**%s\**[ \t]*:[ \t]*(.*)$" % name, body, re.I | re.M)
    return m.group(1).strip() if m else ""


def confirmation_errors(body: str | None, label: str) -> list[str]:
    if body is None:
        return [f"falta el bloque de confirmación {label}"]
    errs = []
    if not DATE_RE.search(field(body, "fecha")):
        errs.append(f"confirmación {label} sin «fecha: AAAA-MM-DD»")
    resp = field(body, "respuesta")
    quoted = QUOTE_RE.search(resp)
    text = quoted.group(1) if quoted else ""
    if not quoted or PLACEHOLDER_RE.match(text):
        errs.append(f"confirmación {label} vacía: «respuesta: «…»» con el texto literal de la persona")
    return errs


def understanding_errors(text: str) -> list[str]:
    sec = section(text, r"Lo que he entendido", 2)
    if sec is None:
        return ["falta la sección «## Lo que he entendido»"]
    errs = []
    scenes = section(sec, r"Escenas", 3)
    n = items(scenes) if scenes is not None else 0
    if not SCENES_MIN <= n <= SCENES_MAX:
        errs.append(f"«### Escenas» debe tener de {SCENES_MIN} a {SCENES_MAX} escenas (tiene {n})")
    words = section(sec, r"Palabras de la persona", 3)
    if words is None:
        errs.append("falta «### Palabras de la persona»")
    else:
        quotes = [q for q in QUOTE_RE.findall(words) if not PLACEHOLDER_RE.match(q)]
        if not quotes or not DATE_RE.search(words):
            errs.append("«### Palabras de la persona» necesita una cita literal «…» con fecha AAAA-MM-DD")
    for title, rx in (("Qué SÍ será", r"Qu[eé] S[IÍií] ser[aá]"), ("Qué NO será", r"Qu[eé] NO ser[aá]")):
        body = section(sec, rx, 3)
        if body is None or items(body) == 0:
            errs.append(f"«### {title}» vacía o ausente")
    errs += confirmation_errors(section(sec, r"Confirmaci[oó]n", 3), "de las escenas")
    return errs


def s0_errors(text: str, started: bool) -> list[str]:
    s0 = section(text, r"Slice S0\b.*", 2)
    if s0 is None:
        return ["falta «## Slice S0 — Prototipo navegable»"]
    errs = []
    if PLACEHOLDER_RE.match(field(s0, "prototipo")):
        errs.append("el slice S0 no dice qué prototipo navegable se enseña («prototipo: …»)")
    if started:
        errs += [e + " (requerida para poner en curso S1 o posteriores)"
                 for e in confirmation_errors(section(s0, r"Confirmaci[oó]n.*", 3), "del prototipo S0")]
    return errs


def in_scope(spec_id: str, fm: dict[str, str]) -> bool:
    m = re.match(r"^SE-(\d+)$", spec_id)
    if m and int(m.group(1)) >= SPEC_FLOOR:
        return True
    approved = fm.get("approved_at", "")
    return bool(DATE_RE.fullmatch(approved)) and approved >= CUTOFF


def check_spec(path: Path, state_status: dict[str, str]) -> tuple[str, list[str]]:
    """Devuelve (veredicto, mensajes). Veredictos: SKIP, EXEMPT, PASS, FAIL."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return "FAIL", [f"ilegible: {exc}"]
    m = re.match(r"^(SE-\d+)", path.name)
    spec_id = m.group(1) if m else path.stem
    fm = frontmatter(text)
    spec_status = fm.get("status", "").upper()
    st = state_status.get(spec_id, "")
    statuses = {spec_status, st} - {""}
    if not statuses & GATED_STATUSES or not in_scope(spec_id, fm):
        return "SKIP", []
    declared = fm.get("human_surface", "").lower()
    detected = bool(SURFACE_RE.search(text))
    if declared == "false":
        if not detected:
            return "PASS", []
        reason = fm.get("human_surface_exempt", "")
        if PLACEHOLDER_RE.match(reason):
            return "FAIL", ["cita rutas de superficie humana y dice human_surface: false: "
                            "exige «human_surface_exempt: <motivo>» o human_surface: true"]
        return "EXEMPT", [reason]
    if declared == "":
        hint = " (hay rutas de superficie humana citadas)" if detected else ""
        return "FAIL", [f"falta «human_surface: true|false» en el frontmatter{hint}"]
    if declared != "true":
        return "FAIL", [f"human_surface inválido: {declared!r} (true o false)"]
    started = bool(statuses & STARTED_STATUSES) or (
        bool(re.fullmatch(r"S([1-9]\d*)", fm.get("current_slice", "").upper()))
    )
    errs = understanding_errors(text) + s0_errors(text, started)
    return ("FAIL", errs) if errs else ("PASS", [])


def load_state(path: str | None) -> dict[str, str]:
    if not path:
        return {}
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return {i["id"]: str(i.get("status", "")).upper() for i in data.get("initiatives", []) if "id" in i}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--state")
    ap.add_argument("--spec", action="append", default=[])
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    try:
        state = load_state(args.state)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(f"FAIL: comprehension-gate: estado ilegible ({exc})")
        return 1
    root = Path(args.root)
    if args.spec:
        specs = [Path(s) for s in args.spec]
    else:
        specs = sorted(root.glob("docs/specs/SE-*.spec.md")) + sorted(root.glob("docs/propuestas/SE-*.md"))
    fails = 0
    for spec in specs:
        verdict, msgs = check_spec(spec, state)
        if verdict == "FAIL":
            fails += 1
            for msg in msgs:
                print(f"FAIL: comprehension-gate {spec.name}: {msg}")
        elif verdict == "EXEMPT" and not args.quiet:
            print(f"EXEMPT: comprehension-gate {spec.name}: {msgs[0]}")
    if fails:
        print(f"FAIL: comprehension-gate: {fails} spec(s) con superficie humana sin comprensión confirmada "
              "(docs/rules/domain/comprehension-gate.md)")
        return 1
    if not args.quiet:
        print("PASS: comprehension-gate")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
