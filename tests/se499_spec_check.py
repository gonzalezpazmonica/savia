#!/usr/bin/env python3
"""SE-499: comprobador de coherencia interna de la spec (revisión PR #1461).

Uso: python3 -I tests/se499_spec_check.py <spec.md>
Exit 0 si la spec es coherente; 1 con un motivo por línea en stderr;
2 si no se puede leer (uso, fichero ausente o no UTF-8).

Reglas (cada una cierra un hallazgo de las revisiones de la PR):
  R-STICKY   (P1-1) existe R6 (registro de altas) y ninguna frase deja que
             transporte inaccesible, red cortada o `install_id` cambiado den
             `UNANCHORED` sin acotarlo a instalaciones sin alta.
  R-STICKY-AC (P1-1) un AC cubre las cinco variantes de ocultación con FAIL
             y `run` parado con exit 4, y su negativo sin alta.
  R-A3       (P1-1) la garantía de A3 distingue fabricación de ocultación.
  R-EXIT     (P2-2) R5 traduce cada código del verificador sin `set -e`.
  R-PENDING  (P2-3) `pr-comment` define `pending` y reintento.
  R-HEAD     (P2-4) `head` en una tabla única; sin «`prev_hash` siguiente».
  R-PRIVATE  (seguridad P2-2) `yema/*` y `effects/*` solo por transportes
             privados, con rechazo en `checkpoint`.
  R-PLAN     cada AC definido aparece en el plan de implementación.
"""
import re
import sys


def section(text, title_re, level="###"):
    m = re.search(rf"^{level} {title_re}.*$", text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    end = re.search(rf"^#{{1,{len(level)}}} ", rest, re.M)
    return rest[: end.start()] if end else rest


def check(text):
    errs = []
    # R-STICKY
    r6 = section(text, r"R6\b")
    if not r6:
        errs.append("R-STICKY: falta la sección R6 (registro de altas)")
    elif "FAIL" not in r6 or "origin/main" not in r6:
        errs.append("R-STICKY: R6 no convierte la ausencia de ancla en FAIL desde origin/main")
    escape = re.compile(r"inaccesible|sin red|no responde|`install_id` local|anchors\.conf", re.I)
    # R6 describe el ataque que cierra; sus líneas no cuentan como permiso.
    r6_lines = set(r6.splitlines()) if r6 else set()
    for n, line in enumerate(text.splitlines(), 1):
        if line in r6_lines:
            continue
        if "UNANCHORED" in line and escape.search(line) and "alta" not in line:
            errs.append(f"R-STICKY: línea {n} permite UNANCHORED por ocultación sin acotarlo a «sin alta»")
    r2 = section(text, r"R2\b")
    if not re.search(r"`UNANCHORED`[^\n]*no est[áa] dada de alta", r2):
        errs.append("R-STICKY: R2.3 no limita UNANCHORED a cadenas sin alta")
    # R-STICKY-AC
    m = re.search(r"^- \*\*AC-\d+ — estado pegajoso\.\*\*(.*)$", text, re.M)
    if not m:
        errs.append("R-STICKY-AC: falta el AC de estado pegajoso")
    else:
        ac = m.group(1)
        for v in "abcde":
            if f"({v})" not in ac:
                errs.append(f"R-STICKY-AC: falta la variante ({v})")
        for need in ("FAIL", "exit 4", "UNANCHORED", "sin alta"):
            if need not in ac:
                errs.append(f"R-STICKY-AC: el AC no menciona «{need}»")
    # R-A3
    a3 = section(text, r"A3\b")
    g = re.search(r"^- \*\*Garantía:\*\*(.*)$", a3, re.M)
    if not g or "fabricación" not in g.group(1) or "ocultación" not in g.group(1):
        errs.append("R-A3: la garantía de A3 no distingue fabricación de ocultación")
    # R-EXIT
    r5 = section(text, r"R5\b")
    for need in ("|| rc=$?", "Exit 1", "Exit 2", "Exit 3", "Cualquier otro código"):
        if need not in r5:
            errs.append(f"R-EXIT: R5 no define «{need}»")
    # R-PENDING
    r3 = section(text, r"R3\b")
    pc = re.search(r"^- `pr-comment`: publica(.*)$", r3, re.M)
    if not pc or "pending" not in pc.group(1) or "reintenta" not in pc.group(1):
        errs.append("R-PENDING: `pr-comment` sin `pending` ni reintento")
    # R-HEAD
    if "`prev_hash` siguiente" in text:
        errs.append("R-HEAD: «`prev_hash` siguiente» no existe para la última entrada")
    r1 = section(text, r"R1\b")
    rows = [l for l in r1.splitlines() if l.strip().startswith("|") and "---" not in l]
    if len(rows) < 4:
        errs.append("R-HEAD: falta la tabla de `head` por cadena (cabecera + 3 filas)")
    # R-PRIVATE
    ch = re.search(r"^- `chain`:(.*)$", r1, re.M)
    if not ch or "transportes privados" not in ch.group(1) or "rechaza" not in ch.group(1):
        errs.append("R-PRIVATE: `yema/*`/`effects/*` sin restricción a transportes privados")
    # R-PLAN
    plan = section(text, r"Plan de implementación", "##")
    for ac in sorted(set(re.findall(r"^- \*\*(AC-\d+) ", text, re.M)), key=lambda a: int(a[3:])):
        if not re.search(rf"\b{ac}\b", plan):
            errs.append(f"R-PLAN: {ac} no aparece en el plan de implementación")
    return errs


def main(argv):
    if len(argv) != 2:
        print("uso: se499_spec_check.py <spec.md>", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        print(f"no se puede leer: {exc}", file=sys.stderr)
        return 2
    errs = check(text)
    for e in errs:
        print(e, file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
