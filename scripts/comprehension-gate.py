#!/usr/bin/env python3
"""comprehension-gate.py — SE-505: puerta de comprensión de las specs con superficie humana.

Una spec que toca una interfaz o una experiencia humana no puede estar APPROVED,
IMPLEMENTING ni IMPLEMENTED sin la sección «Lo que he entendido» completa y confirmada
por la persona que pidió el producto. Además declara un slice S0 de prototipo
navegable, y ningún slice posterior se marca en curso sin la confirmación de S0.

Regla: docs/rules/domain/comprehension-gate.md.

Uso:
  comprehension-gate.py [--root DIR] [--state planning-state.json] [--spec FICHERO ...]

Sin --spec revisa docs/specs/**/SE-*.md, docs/propuestas/SE-*.md y la evidencia de cada
iniciativa de --state; una iniciativa en ámbito del estado sin spec localizable es FAIL.
La evidence solo se usa si la iniciativa no tiene spec en los globs y es un .md con «status:».
EXEMPT y DECLARED-FALSE se imprimen siempre (también con --quiet) para que la revisora los vea.
Salida: 0 PASS · 1 FAIL (incluye ficheros ilegibles: fail-closed) · 2 uso.
"""
from __future__ import annotations

import argparse
import datetime
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


FENCE_RE = re.compile(r"^\s*(```|~~~)")


def frontmatter(text: str) -> dict[str, str] | None:
    """Claves del frontmatter. {} si no hay; None si se abre y no se cierra (malformado).
    Con claves repetidas manda la primera, igual que el `grep -m1` de roadmap.sh."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fm: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return fm
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if m and m.group(1) not in fm:
            fm[m.group(1)] = fm_value(m.group(2))
    return None


def fm_value(raw: str) -> str:
    """Valor escalar: si va entre comillas, lo de dentro (un «#» ahí es texto); si no, sin el
    comentario YAML final («  # …»)."""
    raw = raw.strip()
    q = re.match(r"^([\"'])(.*?)\1", raw)
    if q:
        return q.group(2)
    return re.sub(r"\s+#.*$", "", raw).strip()


def unfenced(text: str) -> list[str]:
    """Líneas fuera de bloques de código cercados (los de dentro quedan en blanco)."""
    out, fence = [], None
    for line in text.splitlines():
        m = FENCE_RE.match(line)
        if m and (fence is None or m.group(1) == fence):
            fence = None if fence else m.group(1)
            out.append("")
            continue
        out.append("" if fence else line)
    return out


def section(text: str, heading_re: str, level: int) -> str | None:
    """Cuerpo de la primera sección cuyo título casa con heading_re, hasta el siguiente
    título de nivel <= level. None si no existe."""
    lines = unfenced(text)
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


def confirmation_errors(body: str | None, label: str, not_before: str = "") -> list[str]:
    if body is None:
        return [f"falta el bloque de confirmación {label}"]
    errs = []
    date = DATE_RE.search(field(body, "fecha"))
    real = None
    if date:
        try:
            real = datetime.date.fromisoformat(date.group(0))
        except ValueError:
            pass
    if not date:
        errs.append(f"confirmación {label} sin «fecha: AAAA-MM-DD»")
    elif real is None:
        errs.append(f"confirmación {label} con fecha {date.group(0)} que no existe en el calendario")
    elif real > datetime.date.today():
        errs.append(f"confirmación {label} con fecha {date.group(0)} posterior a hoy: "
                    "no se confirma lo que aún no ha pasado")
    elif not_before and date.group(0) < not_before:
        errs.append(f"confirmación {label} con fecha {date.group(0)} anterior a las palabras de la "
                    f"persona ({not_before}): no puede confirmar lo que aún no había dicho")
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
    words_date = ""
    if words is None:
        errs.append("falta «### Palabras de la persona»")
    else:
        quotes = [q for q in QUOTE_RE.findall(words) if not PLACEHOLDER_RE.match(q)]
        if not quotes or not DATE_RE.search(words):
            errs.append("«### Palabras de la persona» necesita una cita literal «…» con fecha AAAA-MM-DD")
        else:
            words_date = max(DATE_RE.findall(words))
    for title, rx in (("Qué SÍ será", r"Qu[eé] S[IÍií] ser[aá]"), ("Qué NO será", r"Qu[eé] NO ser[aá]")):
        body = section(sec, rx, 3)
        if body is None or items(body) == 0:
            errs.append(f"«### {title}» vacía o ausente")
    errs += confirmation_errors(section(sec, r"Confirmaci[oó]n", 3), "de las escenas", words_date)
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


def norm_id(raw: str) -> str:
    """SE-0504 → SE-504, igual que la normalización de roadmap.sh."""
    m = re.match(r"^SE-0*(\d+)", raw)
    return f"SE-{int(m.group(1))}" if m else raw


def id_in_scope(spec_id: str) -> bool:
    m = re.match(r"^SE-(\d+)$", spec_id)
    return bool(m) and int(m.group(1)) >= SPEC_FLOOR


def in_scope(spec_id: str, fm: dict[str, str]) -> bool:
    if id_in_scope(spec_id):
        return True
    approved = fm.get("approved_at", "")
    return bool(DATE_RE.fullmatch(approved)) and approved >= CUTOFF


def check_spec(path: Path, state_status: dict[str, str], forced_id: str = "") -> tuple[str, list[str]]:
    """Devuelve (veredicto, mensajes). Veredictos: SKIP, EXEMPT, PASS, FAIL."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return "FAIL", [f"ilegible: {exc}"]
    m = re.match(r"^(SE-\d+)", path.name)
    spec_id = forced_id or (norm_id(m.group(1)) if m else path.stem)
    fm = frontmatter(text)
    if fm is None:
        if id_in_scope(spec_id) or state_status.get(spec_id, "") in GATED_STATUSES:
            return "FAIL", ["frontmatter sin cerrar («---»): no se puede leer el estado ni human_surface"]
        return "SKIP", []
    spec_status = fm.get("status", "").upper()
    st = state_status.get(spec_id, "")
    statuses = {spec_status, st} - {""}
    if not statuses & GATED_STATUSES or not in_scope(spec_id, fm):
        return "SKIP", []
    declared = fm.get("human_surface", "").lower()
    detected = bool(SURFACE_RE.search(text))
    if declared == "false":
        if not detected:
            return "DECLARED-FALSE", ["human_surface: false sin rutas de superficie detectadas; "
                                      "lo comprueba la revisión humana"]
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
    # S1, S01, S1a, S1.2, S2-api…: cualquier slice posterior a S0 cuenta como en curso.
    started = bool(statuses & STARTED_STATUSES) or (
        bool(re.match(r"S0*[1-9]", fm.get("current_slice", "").strip().upper()))
    )
    errs = understanding_errors(text) + s0_errors(text, started)
    return ("FAIL", errs) if errs else ("PASS", [])


def load_state(path: str | None) -> tuple[dict[str, str], dict[str, str]]:
    """(id → status, id → evidence) de la vista de planificación, con IDs normalizados."""
    if not path:
        return {}, {}
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("initiatives", []), list):
        raise ValueError("se esperaba un objeto con «initiatives» como lista")
    status, evidence = {}, {}
    for i in data.get("initiatives", []):
        if not isinstance(i, dict):
            raise ValueError(f"iniciativa que no es un objeto: {i!r}")
        if "id" not in i:
            continue
        sid = norm_id(str(i["id"]))
        status[sid] = str(i.get("status", "")).upper()
        if isinstance(i.get("evidence"), str):
            evidence[sid] = i["evidence"]
    return status, evidence


def file_id(path: Path) -> str:
    m = re.match(r"^(SE-\d+)", path.name)
    return norm_id(m.group(1)) if m else ""


def evidence_spec(root_r: Path, ev: str) -> Path | None:
    """La evidence como spec: fichero .md dentro de root con frontmatter de spec («status:»)
    o con frontmatter sin cerrar (check_spec lo da por FAIL). Ilegible también vale: FAIL allí.
    Cualquier otra cosa (un script, un informe, «PR #1080», una ruta imposible) no es spec."""
    if not ev:
        return None
    try:
        p = (root_r / ev).resolve()
        if p.suffix.lower() != ".md" or not p.is_file() or root_r not in p.parents:
            return None
    except (OSError, ValueError):
        return None
    try:
        fm = frontmatter(p.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError):
        return p
    return p if fm is None or "status" in fm else None


def discover(root: Path, status: dict[str, str],
             evidence: dict[str, str]) -> tuple[list[tuple[Path, str]], list[str]]:
    """Ficheros a revisar y mensajes FAIL de iniciativas en ámbito sin spec localizable.
    Se recorre el estado, no solo los globs: una spec con un nombre que no casa no escapa."""
    globbed = sorted(root.glob("docs/specs/**/SE-*.md")) + sorted(root.glob("docs/propuestas/SE-*.md"))
    found: list[tuple[Path, str]] = [(p, "") for p in globbed]
    ids = {file_id(p) for p in globbed}
    seen = {p.resolve() for p in globbed}
    missing = []
    root_r = root.resolve()
    for sid, st in sorted(status.items()):
        if st not in GATED_STATUSES or not id_in_scope(sid) or sid in ids:
            continue  # con spec en los globs, la evidence es texto libre y no se evalúa
        ev = evidence.get(sid, "")
        ev_path = evidence_spec(root_r, ev)
        if ev_path is not None:
            other = file_id(ev_path)
            if other and other != sid:
                missing.append(f"{sid} está {st} en la vista y su evidence ({ev}) es la spec de "
                               f"{other}, no la suya; la puerta no puede evaluarla")
            elif ev_path not in seen:
                found.append((ev_path, sid))  # la ID la da la vista, no el nombre del fichero
                seen.add(ev_path)
            continue
        missing.append(f"{sid} está {st} en la vista de planificación pero no hay spec localizable "
                       f"(evidence: {ev or 'vacía'}); la puerta no puede evaluarla")
    return found, missing


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--state")
    ap.add_argument("--spec", action="append", default=[])
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    try:
        state, evidence = load_state(args.state)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(f"FAIL: comprehension-gate: estado ilegible ({exc})")
        return 1
    root = Path(args.root)
    missing: list[str] = []
    if args.spec:
        specs = [(Path(s), "") for s in args.spec]
    else:
        specs, missing = discover(root, state, evidence)
    fails = len(missing)
    for msg in missing:
        print(f"FAIL: comprehension-gate: {msg}")
    for spec, forced_id in specs:
        verdict, msgs = check_spec(spec, state, forced_id)
        if verdict == "FAIL":
            fails += 1
            for msg in msgs:
                print(f"FAIL: comprehension-gate {spec.name}: {msg}")
        elif verdict in ("EXEMPT", "DECLARED-FALSE"):
            print(f"{verdict}: comprehension-gate {spec.name}: {msgs[0]}")
    if fails:
        print(f"FAIL: comprehension-gate: {fails} spec(s) con superficie humana sin comprensión confirmada "
              "(docs/rules/domain/comprehension-gate.md)")
        return 1
    if not args.quiet:
        print("PASS: comprehension-gate")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
