#!/usr/bin/env python3
"""SE-510 / SE-511: comprobador de coherencia interna (revisión PR #1482).

Uso: python3 -I tests/se510_se511_spec_check.py <spec.md>
Exit 0 si la spec es coherente; 1 con un motivo por línea en stderr;
2 si no se puede leer (uso, fichero ausente, no UTF-8 o spec desconocida).

Reglas (cada una cierra un hallazgo de las revisiones de la PR):
  R-SEED    (SE-510, P1-1) la semilla de D1 es una tabla id/expect/entrada/par;
            ningún id ni ninguna entrada aparece con dos veredictos; cada ALLOW
            apunta a un par que existe y es BLOCK; los ids que AC-1 dice que
            «contiene» el corpus son todos ALLOW.
  R-SLICE   (SE-510 P2-3, ambas) cada AC de la tabla de criterios aparece en
            exactamente un slice del plan.
  R-TOKENS  (SE-511, P2-4) el total del problema cuadra con su propio método:
            bytes = versionados + índice; tokens inferior = (caracteres +
            índice) / 4; superior = bytes / 3,58.
"""
import re
import sys


def num(s):
    return int(s.replace(".", ""))


def section(text, start, end_re=r"\n## "):
    i = text.find(start)
    if i < 0:
        return ""
    m = re.search(end_re, text[i + len(start):])
    return text[i: i + len(start) + (m.start() if m else len(text))]


def norm(s):
    return re.sub(r"\s+", " ", s.replace("`", "")).strip().lower()


def check_seed(text, errors):
    d1 = section(text, "### D1", r"\n### ")
    rows = []
    for line in d1.splitlines():
        if not re.match(r"^\|\s*[FB]\d", line):
            continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line)]
        ok = (len(cells) == 6 and cells[0] == "" and cells[5] == ""
              and re.fullmatch(r"[FB]\d+[a-z]?", cells[1])
              and cells[2] in ("ALLOW", "BLOCK"))
        if not ok:
            errors.append(f"R-SEED: fila de semilla mal formada: {line[:60]}")
            continue
        rows.append(tuple(cells[1:5]))
    if not rows:
        errors.append("R-SEED: no hay tabla de semilla (id | expect | entrada | par) en D1")
        return
    expect, entry_of = {}, {}
    for rid, exp, entry, _ in rows:
        if rid in expect:
            errors.append(f"R-SEED: id {rid} repetido")
        expect[rid] = exp
        key = norm(entry)
        if key in entry_of and entry_of[key][1] != exp:
            errors.append(f"R-SEED: la misma entrada es {entry_of[key][1]} en {entry_of[key][0]} y {exp} en {rid}")
        entry_of.setdefault(key, (rid, exp))
    for rid, exp, _, par in rows:
        if exp != "ALLOW":
            continue
        par = par.strip()
        if par not in expect:
            errors.append(f"R-SEED: {rid} (ALLOW) sin par BLOCK existente ({par or 'vacío'})")
        elif expect[par] != "BLOCK":
            errors.append(f"R-SEED: el par {par} de {rid} no es BLOCK")
    ac1 = re.search(r"^\| AC-1 \| (.*?) \|", section(text, "## Criterios"), re.M)
    m = re.search(r"contiene (.*?) con `origin", ac1.group(1)) if ac1 else None
    if not m:
        errors.append("R-SEED: AC-1 no enumera la semilla («contiene … con `origin`»)")
        return
    for rid in re.findall(r"\b([FB]\d+[a-z]?)\b", m.group(1)):
        if expect.get(rid) != "ALLOW":
            errors.append(f"R-SEED: AC-1 exige {rid} en el corpus ALLOW, pero en D1 es {expect.get(rid, 'inexistente')}")


def check_slices(text, errors):
    acs = set(re.findall(r"^\| AC-(\d+) \|", section(text, "## Criterios"), re.M))
    plan = section(text, "## Plan por slices")
    slices = re.findall(r"^\d+\. \*\*(S\d+)\*\* — (.*)$", plan, re.M)
    if not acs or not slices:
        errors.append("R-SLICE: no hay AC o slices")
        return
    count = {ac: [] for ac in acs}
    for name, body in slices:
        for ac in set(re.findall(r"AC-(\d+)", body)):
            count.setdefault(ac, []).append(name)
    for ac in sorted(count, key=int):
        if len(count[ac]) != 1:
            errors.append(f"R-SLICE: AC-{ac} en {len(count[ac])} slices ({', '.join(count[ac]) or '-'})")


def check_tokens(text, errors):
    v = re.search(r"\*\*Parte versionada\*\* \| \*\*([\d.]+)\*\* \| \*\*([\d.]+)\*\*", text)
    idx = re.search(r"^\| Índice de memoria del frontend[^|]*\| ([\d.]+) \|", text, re.M)
    tot = re.search(r"el total medido es \*\*([\d.]+) B ≈ ([\d.]+)–([\d.]+) tokens\*\*", text)
    if not (v and idx and tot):
        errors.append("R-TOKENS: faltan la parte versionada, el índice o el total «**N B ≈ A–B tokens**»")
        return
    vb, vc, ib = num(v.group(1)), num(v.group(2)), num(idx.group(1))
    tb, lo, hi = num(tot.group(1)), num(tot.group(2)), num(tot.group(3))
    if tb != vb + ib:
        errors.append(f"R-TOKENS: total {tb} B ≠ {vb} + {ib}")
    want_lo, want_hi = (vc + ib) / 4, (vb + ib) / 3.58
    if abs(lo - want_lo) > 10:
        errors.append(f"R-TOKENS: límite inferior {lo} ≠ ({vc} + {ib}) / 4 = {want_lo:.0f}")
    if abs(hi - want_hi) > 10:
        errors.append(f"R-TOKENS: límite superior {hi} ≠ {vb + ib} / 3,58 = {want_hi:.0f}")


def main(argv):
    if len(argv) != 2:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    path = argv[1]
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        print(f"no se puede leer {path}: {exc}", file=sys.stderr)
        return 2
    title = re.search(r"^# (SE-\d+)", text, re.M)
    spec = title.group(1) if title else ""
    if spec not in ("SE-510", "SE-511"):
        print(f"spec desconocida: {spec or 'sin título SE-NNN'}", file=sys.stderr)
        return 2
    errors = []
    if spec == "SE-510":
        check_seed(text, errors)
    else:
        check_tokens(text, errors)
    check_slices(text, errors)
    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
