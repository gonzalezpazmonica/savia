#!/usr/bin/env python3
"""SE-496: comprobador de coherencia interna de la spec (revisión PR #1452).

Uso: python3 -I tests/se496_spec_check.py <spec.md>
Exit 0 si la spec es coherente; 1 con un motivo por línea en stderr.

Reglas (cada una cierra un hallazgo de la revisión de corrección):
  R-PHASE   cada AC aparece en exactamente una fase, y un AC que prueba D04
            o el EEP cae en una fase cuya entrega nombra el componente que usa.
  R-CODES   cada código de motivo usado en la batería, en los casos técnicos
            o en los AC figura en la tabla de precedencia de R3.
  R-BATTERY ninguna fila D01..D15 espera REQUIRES_APPROVAL.
  R-USES    si hay `max_uses`, la spec define el ledger: quién consume,
            creación exclusiva y que `evaluate` no consume.
  R-DIGEST  `state_digest` tiene lista cerrada de campos.
"""
import re
import sys

CODE_RE = re.compile(r"`(?:DENY |REQUIRES_APPROVAL )?([A-Z][A-Z_]{3,})(?::<id>)?`")
NOT_CODES = {"ALLOW", "DENY", "REQUIRES_APPROVAL", "HOME", "PATH"}


def section(text, start, end_re=r"\n## "):
    i = text.find(start)
    if i < 0:
        return ""
    m = re.search(end_re, text[i + len(start):])
    return text[i: i + len(start) + (m.start() if m else len(text))]


def expand(cell):
    acs = set()
    for a, b in re.findall(r"AC-(\d+)\.\.AC-(\d+)", cell):
        acs |= {str(n) for n in range(int(a), int(b) + 1)}
    cell = re.sub(r"AC-\d+\.\.AC-\d+", "", cell)
    acs |= set(re.findall(r"AC-(\d+[a-z]?)", cell))
    return acs


def main(path):
    text = open(path, encoding="utf-8").read()
    errors = []

    # --- R-PHASE ---
    acs = dict(re.findall(r"^- \*\*AC-(\d+[a-z]?)\*\* (.*)$", text, re.M))
    phases = {}
    for name, cell in re.findall(r"^\| (F\d) \| (.*?) \|", section(text, "## Fases"), re.M):
        phases[name] = cell
    if not acs or not phases:
        errors.append("R-PHASE: no hay AC o tabla de fases")
    owner = {}
    for name, cell in phases.items():
        for ac in expand(cell):
            owner.setdefault(ac, []).append(name)
    for ac, body in acs.items():
        where = owner.get(ac, [])
        if len(where) != 1:
            errors.append(f"R-PHASE: AC-{ac} en {len(where)} fases {where}")
            continue
        cell = phases[where[0]]
        if "D04" in body or "authority-exec.sh" in body:
            needs = [c for c in ("recheck", "authority-exec.sh") if c in body]
            if not needs:
                needs = ["recheck"]  # D04 sin componente nombrado: se exige el primitivo
            for comp in needs:
                if comp not in cell:
                    errors.append(f"R-PHASE: AC-{ac} usa {comp} pero {where[0]} no lo entrega")

    # --- R-CODES ---
    r3 = section(text, "### R3", r"\n### ")
    prec = section(r3, "**Orden de evaluación", r"\n\n\*\*")
    declared = set(CODE_RE.findall(prec))
    if not declared:
        errors.append("R-CODES: falta la tabla de precedencia de códigos en R3")
    r5 = section(text, "### R5", r"\n### ")
    ac_text = "\n".join(acs.values())
    used = (set(CODE_RE.findall(r5)) | set(CODE_RE.findall(ac_text))) - NOT_CODES
    for code in sorted(used - declared):
        errors.append(f"R-CODES: {code} se usa pero no está en el orden de R3")

    # --- R-BATTERY ---
    for row in re.findall(r"^\| D\d\d \|.*$", r5, re.M):
        if "REQUIRES_APPROVAL" in row:
            errors.append(f"R-BATTERY: fila con REQUIRES_APPROVAL: {row[:40]}")
    if "donde se indica" in acs.get("3", ""):
        errors.append("R-BATTERY: AC-3 remite a un REQUIRES_APPROVAL que la batería no indica")

    # --- R-USES ---
    if "max_uses" in text:
        ledger = section(text, "**Ledger de usos", r"\n\n\*\*|\n## |\n### |\nEn F2")
        if not ledger:
            errors.append("R-USES: max_uses sin ledger definido")
        else:
            for need, why in (("O_EXCL", "creación exclusiva"),
                              ("recheck", "quién consume"),
                              ("no consume", "evaluate no consume")):
                if need not in ledger:
                    errors.append(f"R-USES: el ledger no fija {why}")

    # --- R-DIGEST ---
    digest = section(text, "**`state_digest`.**", r"\n\n\*\*|\n## |\n### ")
    if not digest or len(re.findall(r"^- ", digest, re.M)) < 3:
        errors.append("R-DIGEST: state_digest sin lista cerrada de campos")

    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("uso: se496_spec_check.py <spec.md>", file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1]))
    except OSError as exc:
        print(f"no se puede leer: {exc}", file=sys.stderr)
        sys.exit(2)
