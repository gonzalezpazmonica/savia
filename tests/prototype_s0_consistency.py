#!/usr/bin/env python3
"""Coherencia interna de los prototipos S0 de SE-510, SE-513 y SE-514.

Revisión de la PR #1503: los prototipos enseñaban consecuencias falsas
(un mismo mensaje para botones opuestos), un informe cuyas cuentas no
cuadraban y un «aplicado» sin prueba. Este checker convierte esos fallos
en comprobaciones que fallan de verdad.

Uso: prototype_s0_consistency.py {html|report|states} <fichero> [spec]
Sale 0 si es coherente, 1 si no (con el motivo en stderr), 2 si la
entrada no se puede leer o no tiene la forma esperada (fail-closed).
"""
import re
import sys


def fail(msg, code=1):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


# ---------- SE-514: cada botón de respuesta lleva su propia consecuencia ----------
# Los botones viven dentro de plantillas JS (texto de <script>), así que se
# leen con una expresión regular y no con un parser de HTML.
BUTTON = re.compile(r"<button\b([^>]*)>(.*?)</button>", re.S)
ATTR = re.compile(r'([\w-]+)="([^"]*)"')


def check_html(path):
    src = open(path, encoding="utf-8").read()
    buttons = []
    for attrs, text in BUTTON.findall(src):
        a = dict(ATTR.findall(attrs))
        if "data-a" in a:
            buttons.append((a["data-a"], a.get("data-msg"), text))
    if not buttons:
        fail("no hay botones de respuesta (data-a)", 2)
    groups = {}
    for grp, msg, text in buttons:
        if not msg or not msg.strip():
            fail(f"botón «{text.strip()}» ({grp}) sin data-msg propio")
        groups.setdefault(grp, []).append((text.strip(), msg))
    for grp, items in groups.items():
        msgs = [m for _, m in items]
        if len(set(msgs)) != len(msgs):
            fail(f"grupo {grp}: botones distintos muestran el mismo mensaje")
    # El mensaje común de escena no debe existir: reabriría el fallo.
    if re.search(r"\bmsg\s*:", src):
        fail("queda un msg común por escena; cada botón debe llevar el suyo")
    if re.search(r"\$\{[^}]*msg[^}]*\}", src):
        fail("el mensaje se interpola en HTML; usar textContent")
    if re.search(r"\.role\s*=", src):
        fail("role asignado como propiedad; usar setAttribute")
    print(f"OK html: {len(buttons)} botones en {len(groups)} grupos")


# ---------- SE-510: el informe semanal cuadra consigo mismo ----------
ROW = re.compile(
    r"^(?P<g>[\w-]+)\s+(?P<b>\d+)\s+(?P<e>\d+)\s+(?P<f>\d+)\s+"
    r"(?P<t>\d+ %|UNKNOWN)\s+(?P<s>\d+)\s*$")
LIST = re.compile(r"^\s*\d+\s+\S+\s+\d\d:\d\d\s+\S+\s+.*\s(falso|verdadero)\s*$")


def _rate(f, e):
    return "UNKNOWN" if e == 0 else f"{round(100 * f / e)} %"


def check_report(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    rows, total = {}, None
    for ln in lines:
        m = ROW.match(ln)
        if not m:
            continue
        r = {k: (m[k] if k in ("g", "t") else int(m[k])) for k in "gbefts"}
        if r["g"] == "TOTAL":
            total = r
        else:
            rows[r["g"]] = r
    if not rows or total is None:
        fail("no se encuentra la tabla del informe con fila TOTAL", 2)
    for r in list(rows.values()) + [total]:
        if r["e"] + r["s"] != r["b"]:
            fail(f"{r['g']}: etiquetados + sin etiquetar != bloqueos")
        if r["f"] > r["e"]:
            fail(f"{r['g']}: más falsos que etiquetados")
        if r["t"] != _rate(r["f"], r["e"]):
            fail(f"{r['g']}: tasa {r['t']} != {_rate(r['f'], r['e'])}")
    for k in "befs":
        if sum(r[k] for r in rows.values()) != total[k]:
            fail(f"TOTAL columna {k} no es la suma de las filas")
    m = re.search(r"Falsos sin entrar en el corpus[^:]*:\s*(\d+)", "\n".join(lines))
    if m and int(m[1]) > total["f"]:
        fail("hay más falsos fuera del corpus que falsos en total")
    # La vista detallada de una guarda debe cuadrar con su fila.
    text = "\n".join(lines)
    for lm in re.finditer(r"list [^\n]*--guard ([\w-]+)\n(.*?)```", text, re.S):
        g, body = lm[1], lm[2]
        labels = [x[1] for x in (LIST.match(l) for l in body.splitlines()) if x]
        if g not in rows:
            fail(f"list de {g} sin fila en el informe")
        if len(labels) != rows[g]["e"] or labels.count("falso") != rows[g]["f"]:
            fail(f"{g}: la vista list no cuadra con su fila del informe")
    print(f"OK report: {len(rows)} guardas, TOTAL {total['b']}")


# ---------- SE-513: ningún «aplicado» sin prueba y frases no fijadas marcadas ----------
def _norm(s):
    return re.sub(r"\s+", " ", s).strip().lower()


def check_states(path, spec):
    text = open(path, encoding="utf-8").read()
    spec_n = _norm(open(spec, encoding="utf-8").read())
    says = re.findall(r"^\*\*Savia:\*\*\s*(.+)$", text, re.M)
    if not says:
        fail("no hay frases de Savia", 2)
    for s in says:
        if "*(propuesta" in s:
            continue
        if _norm(s) not in spec_n:
            fail(f"frase de Savia no fijada por la spec y sin marcar: «{s[:60]}»")
    # Las escenas son situaciones alternativas, no una línea de tiempo:
    # el estado final de cada cambio en la tabla tiene que haberse visto en
    # alguna escena, y APLICADO solo vale si alguna fila lo muestra con prueba.
    sections = re.split(r"^## ", text, flags=re.M)
    final = next((s for s in sections if s.startswith("Tabla completa")), None)
    if final is None:
        fail("falta la tabla completa", 2)
    st = re.compile(r"^(#\d+)\s+.*?\s(ADMITIDO|APLICADO|NO SÉ)\s(.*)$")
    seen = {}
    for s in sections:
        if s is final:
            continue
        for ln in s.splitlines():
            m = st.match(ln)
            if m:
                seen.setdefault(m[1], set()).add(
                    m[2] + ("+prueba" if "(prueba:" in m[3] else ""))
        # Una frase de Savia que declara «aplicado» exige una fila APLICADO
        # con prueba en la misma escena.
        for say in re.findall(r"^\*\*Savia:\*\*\s*(.+)$", s, re.M):
            if re.search(r"(?<!lo ha )\baplicado\b", say, re.I) and \
                    not re.search(r"APLICADO .*\(prueba:", s):
                fail(f"Savia dice «aplicado» sin fila con prueba: «{say[:60]}»")
    for ln in final.splitlines():
        m = st.match(ln)
        if not m:
            continue
        states = seen.get(m[1], set())
        if m[2] == "APLICADO" and "APLICADO+prueba" not in states:
            fail(f"{m[1]}: APLICADO en la tabla sin ninguna fila con prueba")
        if m[2] != "APLICADO" and m[2] not in states:
            fail(f"{m[1]}: la tabla dice {m[2]} y ninguna escena lo muestra así")
    print(f"OK states: {len(says)} frases, {len(seen)} cambios")


def main(argv):
    if len(argv) < 3:
        fail(__doc__, 2)
    mode, path = argv[1], argv[2]
    try:
        if mode == "html":
            check_html(path)
        elif mode == "report":
            check_report(path)
        elif mode == "states" and len(argv) == 4:
            check_states(path, argv[3])
        else:
            fail(f"modo desconocido o argumentos incompletos: {mode}", 2)
    except OSError as e:
        fail(f"no se puede leer: {e}", 2)


if __name__ == "__main__":
    main(sys.argv)
