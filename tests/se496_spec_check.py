#!/usr/bin/env python3
"""SE-496: comprobador de coherencia interna de la spec (revisión PR #1452).

Uso: python3 -I tests/se496_spec_check.py <spec.md>
Exit 0 si la spec es coherente; 1 con un motivo por línea en stderr;
2 si no se puede leer (uso, fichero ausente o no UTF-8).

Reglas (cada una cierra un hallazgo de las revisiones de la PR):
  R-PHASE   cada AC aparece en exactamente una fase, y un AC que prueba D04,
            `recheck` o el EEP cae en una fase cuya entrega nombra el
            componente que usa.
  R-CODES   cada código de motivo usado en R4, en la batería, en los casos
            técnicos o en los AC figura en la columna de código del orden
            de R3.
  R-BATTERY ninguna fila D01..D15 espera REQUIRES_APPROVAL.
  R-USES    si hay `max_uses`, la spec define el ledger: `recheck` consume,
            creación exclusiva y `evaluate` no consume.
  R-DIGEST  `state_digest` tiene exactamente la lista cerrada de campos.
  R-EXIT    tabla única caso → (decisión, exit) coherente con
            ALLOW 0 / DENY 1 / REQUIRES_APPROVAL 4 / sin decisión 2, y
            ninguna frase de la spec la contradice.
"""
import re
import sys

CODE_RE = re.compile(r"`(?:DENY |REQUIRES_APPROVAL )?([A-Z][A-Z_]{3,})(?::<id>)?`")
NOT_CODES = {"ALLOW", "DENY", "REQUIRES_APPROVAL", "HOME", "PATH"}
DIGEST_FIELDS = {"contract_sha256", "capability_sha256", "signers_blob",
                 "revoked", "target", "facts"}
EXIT_OF = {"ALLOW": "0", "DENY": "1", "REQUIRES_APPROVAL": "4", "sin decisión": "2"}


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


def sentences(text):
    return [s for s in re.split(r"(?<=\.)\s+|\n", text) if s.strip()]


def check_phase(text, acs, errors):
    phases = dict(re.findall(r"^\| (F\d) \| (.*?) \|", section(text, "## Fases"), re.M))
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
        needs = [c for c in ("recheck", "authority-exec.sh") if c in body]
        if "D04" in body and not needs:
            needs = ["recheck"]  # D04 sin componente nombrado: se exige el primitivo
        for comp in needs:
            if comp not in phases[where[0]]:
                errors.append(f"R-PHASE: AC-{ac} usa {comp} pero {where[0]} no lo entrega")


def check_codes(text, acs, errors):
    r3 = section(text, "### R3", r"\n### ")
    prec = section(r3, "**Orden de evaluación", r"\n\n\*\*")
    declared = set()
    for cell in re.findall(r"^\| \d+ \| [^|]*\| ([^|]*)\|", prec, re.M):
        declared |= set(CODE_RE.findall(cell))
    if not declared:
        errors.append("R-CODES: falta la tabla de precedencia de códigos en R3")
    r4 = section(text, "### R4", r"\n### ")
    r5 = section(text, "### R5", r"\n### ")
    for name, body in (("R4", r4), ("R5", r5)):
        if not body:
            errors.append(f"R-CODES: falta la sección {name}")
    ac_text = "\n".join(acs.values())
    used = set()
    for body in (r4, r5, ac_text):
        used |= set(CODE_RE.findall(body))
    for code in sorted(used - NOT_CODES - declared):
        errors.append(f"R-CODES: {code} se usa pero no está en el orden de R3")
    return r5


def check_battery(r5, errors):
    rows = re.findall(r"^\| D\d\d \|.*$", r5, re.M)
    if r5 and not rows:
        errors.append("R-BATTERY: la batería de R5 no tiene filas D..")
    for row in rows:
        if "REQUIRES_APPROVAL" in row:
            errors.append(f"R-BATTERY: fila con REQUIRES_APPROVAL: {row[:40]}")


def check_uses(text, errors):
    if "max_uses" not in text:
        return
    ledger = section(text, "**Ledger de usos", r"\n\n\*\*|\n## |\n### |\nEn F2")
    if not ledger:
        errors.append("R-USES: max_uses sin ledger definido")
        return
    checks = ((r"O_EXCL", "creación exclusiva"),
              (r"`recheck`[^\n]*\bconsume\b", "quién consume"),
              (r"`evaluate`[^\n]*no consume", "evaluate no consume"))
    for pattern, why in checks:
        if not re.search(pattern, ledger):
            errors.append(f"R-USES: el ledger no fija {why}")


def check_digest(text, errors):
    digest = section(text, "**`state_digest`.**", r"\n\n\*\*|\n## |\n### ")
    fields = set()
    for line in re.findall(r"^- (.*)$", digest, re.M):
        fields |= set(re.findall(r"`([a-z_0-9]+)`", line.split(":", 1)[0]))
    if not digest or "exactamente estos campos" not in digest:
        errors.append("R-DIGEST: state_digest sin lista cerrada de campos")
        return
    for f in sorted(fields - DIGEST_FIELDS):
        errors.append(f"R-DIGEST: campo no previsto en state_digest: {f}")
    for f in sorted(DIGEST_FIELDS - fields):
        errors.append(f"R-DIGEST: falta el campo {f} en state_digest")


def check_exit(text, errors):
    table = section(text, "**Códigos de salida.**", r"\n\n\*\*|\n### ")
    rows = re.findall(r"^\| ([^|]+?) \| ([^|]+?) \| (\d) \|$", table, re.M)
    if not rows:
        errors.append("R-EXIT: falta la tabla «Códigos de salida»")
        return
    for case, decision, code in rows:
        decision = decision.strip("`")
        if EXIT_OF.get(decision) != code:
            errors.append(f"R-EXIT: «{case}» da {decision} con exit {code}")
    cases = " ".join(c for c, _, _ in rows)
    for need in ("mal formada", "no se puede leer"):
        if need not in cases:
            errors.append(f"R-EXIT: la tabla no fija el caso «{need}»")
    for s in sentences(text):
        low = s.lower()
        if ("malformad" in low or "mal formad" in low) and "`DENY" in s:
            errors.append(f"R-EXIT: entrada malformada con DENY: {s.strip()[:60]}")
        if "UNKNOWN_STATE" in s and "exit 2" in s:
            errors.append(f"R-EXIT: UNKNOWN_STATE con exit 2: {s.strip()[:60]}")


def main(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    errors = []
    acs = dict(re.findall(r"^- \*\*AC-(\d+[a-z]?)\*\* (.*)$", text, re.M))
    check_phase(text, acs, errors)
    r5 = check_codes(text, acs, errors)
    check_battery(r5, errors)
    check_uses(text, errors)
    check_digest(text, errors)
    check_exit(text, errors)
    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("uso: se496_spec_check.py <spec.md>", file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1]))
    except (OSError, UnicodeDecodeError) as exc:
        print(f"no se puede leer: {exc}", file=sys.stderr)
        sys.exit(2)
