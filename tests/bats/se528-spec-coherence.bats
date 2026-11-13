#!/usr/bin/env bats
# SE-528 — coherencia de la spec: front-matter, slices con AC, registros
# y casos negativos sobre copias mutadas.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-528-seguridad-web-puente-cupulas.spec.md"

setup() {
  set -uo pipefail
  MS="$BATS_TEST_TMPDIR/spec.md"
  cp "$SPEC" "$MS"
}

# check <fichero>: devuelve 0 si la spec es coherente; imprime el motivo y sale 1 si no.
check() {
  python3 -I - "$1" <<'PY'
import re, sys
try:
    s = open(sys.argv[1], encoding="utf-8").read()
except OSError as e:
    sys.exit("no se puede leer la spec: " + e.__class__.__name__)
errs = []
fm = re.match(r"---\n(.*?)\n---\n", s, re.S)
if not fm: sys.exit("sin front-matter")
f = fm.group(1)
if "status: PROPOSED" not in f: errs.append("status no es PROPOSED")
for sl in ("S1", "S2", "S3", "S4"):
    if not re.search(rf"^### {sl} — ", s, re.M): errs.append(f"falta el slice {sl}")
# cada AC debe estar DEFINIDO (viñeta al inicio de línea), no solo mencionado
for ac in ("AC-1.1", "AC-1.2", "AC-1.3", "AC-1.4", "AC-1.5", "AC-2.1", "AC-2.2", "AC-2.3", "AC-2.4", "AC-2.5", "AC-2.6", "AC-2.7", "AC-2.8", "AC-2.9", "AC-2.10", "AC-2.11", "AC-2.12", "AC-3.1", "AC-3.2", "AC-3.3", "AC-3.4", "AC-3.5", "AC-2.13", "AC-2.14", "AC-2.15", "AC-4.1", "AC-4.2", "AC-4.3", "AC-4.4", "AC-4.5"):
    if not re.search(rf"^- {re.escape(ac)} ", s, re.M): errs.append(f"falta {ac}")
for sec in ("## Problema", "## Puerta de comprensión", "## Fuera de alcance", "## OpenCode Implementation Plan", "## Tier de riesgo"):
    if sec not in s: errs.append(f"falta la sección {sec}")
for q in ("Q1", "Q2", "Q3"):
    if not re.search(rf"^- {q}\. ", s, re.M): errs.append(f"faltan decisiones de la operadora ({q})")
if "Condiciones de fusión: (1) revisión humana de confidencialidad" not in s: errs.append("faltan las condiciones de fusión (revisión humana de confidencialidad)")
if "**Decisiones de la operadora (2026-11-13)**" not in s: errs.append("falta el registro de decisiones de la operadora")
for stale in ("Decisiones abiertas", "Preguntas abiertas", "Deprecation", "14 días", "fecha de corte", "según Q1", "según Q2", "según Q3"):
    if stale in s: errs.append("resto de una decisión abierta: " + stale)
for q, chosen in (("Q1", "sin transición"), ("Q2", "bucle local"), ("Q3", "pidan el token una vez")):
    ql = re.search(rf"^- {q}\. .*$", s, re.M)
    if ql and chosen not in ql.group(0): errs.append(f"{q} no describe lo elegido: " + chosen)
# Limitación asumida: es un test de FORMA (viñeta presente, en su slice, con texto sustancial y
# términos clave); no prueba que cada AC sea verificable ni correcto.
def section(n):
    m = re.search(rf"^### S{n} — .*?(?=^### |^## )", s, re.M | re.S)
    return m.group(0) if m else ""
for m in re.finditer(r"^- (AC-(\d)\.\d+) (.*)$", s, re.M):
    ident, n, body = m.group(1), m.group(2), m.group(3)
    if len(body) < 40: errs.append(f"{ident} sin contenido sustancial")
    if m.group(0) not in section(n): errs.append(f"{ident} fuera de su slice S{n}")
def acs(n):
    return "\n".join(l for l in section(n).splitlines() if re.match(rf"- AC-{n}\.\d+ ", l))
for n, t_ in ((2, "401"), (2, "Allow-Credentials"), (2, "Origin"), (2, "endpoint de estado de sesión"), (4, "endpoint de estado"), (3, "clave no disponible"), (3, "no cambia"), (4, "sin sesión por cookie")):
    if t_ not in acs(n): errs.append(f"S{n} no cubre {t_} en sus AC")
# el orden S1 < S2 < S3 < S4
pos = [s.find(f"### {x} — ") for x in ("S1", "S2", "S3", "S4")]
if pos != sorted(pos): errs.append("slices fuera de orden")
if errs: print("; ".join(errs)); sys.exit(1)
PY
  local rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  leak_scan "$1"
}

# leak_scan <ficheros...>: heurística GENÉRICA (formas, no nombres) de detalle operativo en ficheros públicos.
# Es una lista negra: no sustituye a la revisión humana de seguridad ni garantiza ausencia de detalle.
# Patrones específicos (nombres reales) solo en un fichero privado opcional: SE528_PRIVATE_PATTERNS.
leak_scan() {
  python3 -I - "$@" <<'PY'
import os, re, sys
generic = [
    r"\b[\w./-]+\.(?:vue|ts|tsx|py|kt|rs|sh|js):L?[0-9]+",   # fichero:línea
    r"(?<![\w-])(?!risk-tier\.py\b)[\w-]+\.(?:vue|ts|tsx|py|kt|rs)\b",                 # nombre de fichero de código
    r"\b(?!scripts/risk-tier\.py)(?:src|projects|scripts)/[\w./-]+",                  # rutas de código
    r"(?<![\w\"])[a-z]+_[a-z_]+\b(?![\w\"]*:)",               # identificadores snake_case (no claves YAML)
    r"\b[a-z]+[A-Z]\w*\(",                                    # llamadas camelCase
    r"\b\w+\(\)",                                            # llamadas con paréntesis
    r"(?<![-\w])--[a-z][a-z-]+",                               # flags de línea de órdenes
    r"[?&]\w+=",                                              # parámetros de consulta
    r"\b(?!127\.0\.0\.1\b)\d{1,3}(?:\.\d{1,3}){3}\b",       # IPv4 distinta de bucle local
    r"\b[0-9a-f]{9,40}\b",                                    # hashes
    r"Cadena:",
    r"sin sanear|legible desde|por defecto|autoarreglo|en la dirección",   # descripción del estado actual
    # revelación semántica del estado actual, umbrales y vectores (revisión #1544, P1)
    r"DOMPurify|renderMarkdownSafe|\b\d+ bytes\b|nunca se sustituye|no rota\b|\bno 200\b|enlaces guardados|javascript:|manejador|se borra su código|canal retirado|ahora son visibles|deja de guardar",
]
pats = list(generic)
pf = os.environ.get("SE528_PRIVATE_PATTERNS")
if pf and os.path.isfile(pf):
    pats += [l.strip() for l in open(pf, encoding="utf-8") if l.strip() and not l.startswith("#")]
rx = re.compile("|".join(pats))
bad = []
for f in sys.argv[1:]:
    txt = open(f, encoding="utf-8").read()
    m = rx.search(txt)
    if m: bad.append(f"{os.path.basename(f)}: {m.group(0)}")
if bad: print("detalle explotable (heurística) en: " + "; ".join(bad)); sys.exit(1)
PY
}

mutate() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s: sys.exit("mutación sin efecto: " + old[:60])
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

@test "aviso visible si faltan los patrones privados (CI no los tiene)" {
  if [ -z "${SE528_PRIVATE_PATTERNS:-}" ]; then
    echo "# AVISO: SE528_PRIVATE_PATTERNS sin definir; solo corre la heuristica generica, no los nombres reales" >&3
  fi
  [ -f "$SPEC" ]
}

@test "la spec real es coherente" {
  run check "$MS"
  [ "$status" -eq 0 ]
}

@test "negativo: status distinto de PROPOSED es fail" {
  mutate "$MS" "status: PROPOSED" "status: APPROVED"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es PROPOSED"* ]]
}

@test "negativo: borrar solo la definicion de AC-3.1 es fail aunque se mencione en otro sitio" {
  mutate "$MS" "- AC-3.1 Test:" "- AC-3.X Test:"
  [ "$(grep -c 'AC-3.1' "$MS")" -ge 1 ]   # premisa: sigue mencionado en el plan
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta AC-3.1"* ]]
}

@test "negativo: missing slice S2 es fail" {
  mutate "$MS" "### S2 — " "### Sx — "
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta el slice S2"* ]]
}

@test "negativo: slices fuera de orden es fail" {
  python3 -I - "$MS" <<'PY2'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("### S1 — ", "@@A@@", 1).replace("### S3 — ", "### S1 — ", 1).replace("@@A@@", "### S3 — ", 1)
open(p, "w", encoding="utf-8").write(s)
PY2
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fuera de orden"* ]]
  [[ "$output" != *"falta el slice"* ]]
}

@test "planning.d y LOG.d de SE-528 existen y coinciden con la spec" {
  run regs_match "$SPEC" "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json" "$REPO_ROOT/docs/propuestas/LOG.d/SE-528-PROPOSED.md"
  [ "$status" -eq 0 ]
}

# regs_match <spec> <planning.json> <LOG.md>: id, status, prioridad, fase y título del planning
# coinciden con la spec (que es la fuente), y el LOG existe y cita SE-528 PROPOSED y Q1.
regs_match() {
  python3 -I - "$@" <<'PY5'
import json, re, sys
spec, plan, log = sys.argv[1:4]
try:
    s = open(spec, encoding="utf-8").read()
    d = json.load(open(plan, encoding="utf-8"))
    l = open(log, encoding="utf-8").read()
except (OSError, ValueError) as e:
    sys.exit("registro ilegible: " + e.__class__.__name__)
fm = re.match(r"---\n(.*?)\n---\n", s, re.S).group(1)
def key(k): return re.search(rf"^{k}: (.*)$", fm, re.M).group(1).strip()
title = re.search(r"^# (SE-528) — (.*)$", s, re.M).group(2).strip()
errs = []
if d.get("id") != "SE-528": errs.append("id")
if d.get("status") != key("status"): errs.append("status")
if d.get("priority") != key("priority"): errs.append("priority")
if d.get("phase") != key("phase"): errs.append("phase")
if d.get("title") != title.split(":")[0].strip() and d.get("title") not in title and title.lower() not in d.get("title", "").lower():
    errs.append("title")
if not str(d.get("evidence", "")).endswith("SE-528-seguridad-web-puente-cupulas.spec.md"): errs.append("evidence")
if "SE-528 PROPOSED" not in l or "Q1" not in l: errs.append("LOG sin SE-528 PROPOSED / Q1")
if errs: print("registro no coincide con la spec: " + ", ".join(errs)); sys.exit(1)
PY5
}

@test "negativo: planning con prioridad o titulo distintos, o LOG sin contenido, es fail" {
  P="$BATS_TEST_TMPDIR/p.json"; L="$BATS_TEST_TMPDIR/l.md"
  cp "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json" "$P"; cp "$REPO_ROOT/docs/propuestas/LOG.d/SE-528-PROPOSED.md" "$L"
  run regs_match "$SPEC" "$P" "$L"; [ "$status" -eq 0 ]
  sed -i 's/"priority": "P1"/"priority": "P3"/' "$P"
  run regs_match "$SPEC" "$P" "$L"; [ "$status" -eq 1 ]; [[ "$output" == *"priority"* ]]
  cp "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json" "$P"
  sed -i 's/"title": "[^"]*"/"title": "Otro asunto"/' "$P"
  run regs_match "$SPEC" "$P" "$L"; [ "$status" -eq 1 ]; [[ "$output" == *"title"* ]]
  cp "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json" "$P"; echo "nada" > "$L"
  run regs_match "$SPEC" "$P" "$L"; [ "$status" -eq 1 ]; [[ "$output" == *"LOG"* ]]
  run regs_match "$SPEC" "$BATS_TEST_TMPDIR/no-existe.json" "$L"; [ "$status" -eq 1 ]; [[ "$output" == *"ilegible"* ]]
}

@test "negativo: missing decision Q1 de la operadora es fail" {
  mutate "$MS" "- Q1." "- Qx."
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"decisiones de la operadora (Q1)"* ]]
}

@test "negativo: reintroducir la transicion o las preguntas abiertas es fail" {
  for t in "Deprecation" "14 días" "Decisiones abiertas" "fecha de corte" "según Q1"; do
    cp "$SPEC" "$MS"
    printf '\nnota %s\n' "$t" >> "$MS"
    run check "$MS"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resto de una decisión abierta: $t"* ]]
  done
}

@test "negativo: quitar el registro de decisiones o lo elegido es fail" {
  mutate "$MS" "**Decisiones de la operadora (2026-11-13)**" "**Decisiones**"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta el registro de decisiones"* ]]
  cp "$SPEC" "$MS"
  mutate "$MS" "Corte inmediato de todo canal de credenciales que no sea la cabecera ni la sesión, sin transición" "Corte inmediato de todo canal de credenciales que no sea la cabecera ni la sesión, con transición"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Q1 no describe lo elegido: sin transición"* ]]
}

@test "edge: fichero vacio es fail por falta de front-matter" {
  : > "$MS"
  run check "$MS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sin front-matter"* ]]
}

@test "edge: fichero nonexistent es fail, no pasa en silencio" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se puede leer la spec"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "negativo: missing AC-2.8 (CSRF/CORS) es fail" {
  mutate "$MS" "- AC-2.8 Test:" "- AC-2.X Test:"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta AC-2.8"* ]]
}

@test "negativo: missing AC-2.9 (modo abierto valida Host/Origin) es fail" {
  mutate "$MS" "- AC-2.9 Test:" "- AC-2.X Test:"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta AC-2.9"* ]]
}

@test "negativo: missing slice S4 es fail" {
  mutate "$MS" "### S4 — " "### Sx — "
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta el slice S4"* ]]
}

@test "negativo: falta Q3 es fail" {
  mutate "$MS" "- Q3. " "- Qx. "
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Q3"* ]]
}

@test "negativo: Allow-Credentials solo en el diseño y no en los AC de S2 es fail" {
  python3 -I - "$MS" <<'PY3'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
out = [l.replace("Allow-Credentials", "Allow-Xx") if l.startswith("- AC-2.") else l for l in lines]
assert out != lines
assert any("Allow-Credentials" in l and not l.startswith("- AC-") for l in out)  # sigue en el diseño
open(p, "w", encoding="utf-8").write("\n".join(out))
PY3
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S2 no cubre Allow-Credentials"* ]]
}

@test "negativo: AC-2.11 (sin Origin con cookie) ausente es fail" {
  mutate "$MS" "- AC-2.11 " "- AC-2.X "
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta AC-2.11"* ]]
}

@test "negativo: formas genericas de detalle operativo en la spec son fail (cada una)" {
  for x in "fn_algo()" "mod_x.py:12" "src/algo/x.ts" "una_variable_interna" "--bandera-x" "?clave=1" "10.0.0.5" "doThing(" "se pinta sin sanear" "legible desde el script" "clave de 31 bytes" "nunca se sustituye" "DOMPurify" "renderMarkdownSafe" "javascript:" "enlaces guardados" "un error de lectura no rota" "devuelve 401, no 200" "canal retirado"; do
    cp "$SPEC" "$MS"
    printf '\nnota %s\n' "$x" >> "$MS"
    run check "$MS"
    [ "$status" -eq 1 ]
    [[ "$output" == *"detalle explotable"* ]]
  done
}

@test "positivo: bucle local 127.0.0.1 y el helper previsto no disparan la heuristica" {
  run leak_scan "$SPEC"
  [ "$status" -eq 0 ]
}

@test "el patron privado opcional tambien se aplica" {
  printf 'palabraprivada\n' > "$BATS_TEST_TMPDIR/p.txt"
  printf '\nnota palabraprivada\n' >> "$MS"
  SE528_PRIVATE_PATTERNS="$BATS_TEST_TMPDIR/p.txt" run leak_scan "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"palabraprivada"* ]]
  run leak_scan "$MS"
  [ "$status" -eq 0 ]
}

@test "negativo: un AC vacio o fuera de su slice es fail" {
  mutate "$MS" "- AC-3.3 Caso positivo: sin fichero de clave se crea y se firma." "- AC-3.3 Vacio."
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-3.3 sin contenido sustancial"* ]]
  cp "$SPEC" "$MS"
  printf '\n- AC-1.9 %s\n' "AC colocado al final del documento fuera de su slice con texto suficiente" >> "$MS"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-1.9 fuera de su slice S1"* ]]
}

@test "negativo: S4 sin cobertura del despliegue sin cookie es fail" {
  python3 -I - "$MS" <<'PY4'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
out = [l.replace("sin sesión por cookie", "otro caso") if l.startswith("- AC-4.") else l for l in lines]
assert out != lines
open(p, "w", encoding="utf-8").write("\n".join(out))
PY4
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S4 no cubre sin sesión por cookie"* ]]
}

@test "registros y changelog pasan la misma heuristica generica" {
  run leak_scan "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json" \
    "$REPO_ROOT/docs/propuestas/LOG.d/SE-528-PROPOSED.md" \
    "$REPO_ROOT/CHANGELOG.d/se528-spec-seguridad.md"
  [ "$status" -eq 0 ]
}

@test "negativo: detalle inyectado en copias de los registros reales es fail (cada uno)" {
  for f in docs/propuestas/planning.d/SE-528.json docs/propuestas/LOG.d/SE-528-PROPOSED.md CHANGELOG.d/se528-spec-seguridad.md; do
    cp "$REPO_ROOT/$f" "$BATS_TEST_TMPDIR/reg-$(basename "$f")"
    printf '\nnota fn_interna() en mod_x.py:9\n' >> "$BATS_TEST_TMPDIR/reg-$(basename "$f")"
    run leak_scan "$BATS_TEST_TMPDIR/reg-$(basename "$f")"
    [ "$status" -eq 1 ]
    [[ "$output" == *"reg-$(basename "$f")"* ]]
  done
}

@test "negativo: quitar las condiciones de fusion o el endpoint de estado es fail" {
  mutate "$MS" "Condiciones de fusión: (1) revisión humana de confidencialidad" "Condiciones: (1) revisión"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"condiciones de fusión"* ]]
  cp "$SPEC" "$MS"
  mutate "$MS" "- AC-2.15 " "- AC-2.X "
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta AC-2.15"* ]]
}

@test "negativo: la heuristica detecta detalle en un registro" {
  printf 'nota fn_interna() en mod_x.py:9\n' > "$BATS_TEST_TMPDIR/reg.md"
  run leak_scan "$BATS_TEST_TMPDIR/reg.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reg.md"* ]]
}
