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
for ac in ("AC-1.1", "AC-1.4", "AC-1.5", "AC-2.1", "AC-2.3", "AC-2.4", "AC-2.8", "AC-2.9", "AC-3.1", "AC-3.4", "AC-4.1", "AC-4.3"):
    if not re.search(rf"^- {re.escape(ac)} ", s, re.M): errs.append(f"falta {ac}")
for sec in ("## Problema", "## Puerta de comprensión", "## Fuera de alcance", "## OpenCode Implementation Plan", "## Tier de riesgo"):
    if sec not in s: errs.append(f"falta la sección {sec}")
for q in ("Q1", "Q2", "Q3", "Q4"):
    if not re.search(rf"^- {q}\. ", s, re.M): errs.append(f"faltan decisiones abiertas ({q})")
# cobertura: cada término debe aparecer dentro del bloque de AC de su slice
def block(n):
    m = re.search(rf"^### S{n} — .*?(?=^### S|^## )", s, re.S | re.M)
    return m.group(0) if m else ""
for n, t in ((2, "Deprecation"), (2, "Allow-Credentials"), (3, "GrantKeyUnavailable"), (3, "ENOENT")):
    if t not in block(n): errs.append(f"S{n} no cubre {t}")
# el orden S1 < S2 < S3 < S4
pos = [s.find(f"### {x} — ") for x in ("S1", "S2", "S3", "S4")]
if pos != sorted(pos): errs.append("slices fuera de orden")
# spec pública: sin detalle explotable (heurística; ver el registro privado)
leak = r"ChatPage|FileViewer|grants\.ts|savia-bridge|auth\.ts|0\.0\.0\.0|v-html|innerHTML=|document\.cookie|onerror|self\.auth_token|Cadena:|\.(vue|ts|py|kt|md|json|tsx):L?[0-9]+"
m = re.search(leak, s)
if m: errs.append("detalle explotable en la spec pública: " + m.group(0))
if errs: print("; ".join(errs)); sys.exit(1)
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
  grep -q "AC-3.1" "$MS" || skip "la mencion en el plan ya no existe"
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
  run python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['id']=='SE-528' and d['status']=='PROPOSED' and d['evidence'].endswith('SE-528-seguridad-web-puente-cupulas.spec.md')" "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json"
  [ "$status" -eq 0 ]
  [ -f "$REPO_ROOT/docs/propuestas/LOG.d/SE-528-PROPOSED.md" ]
}

@test "negativo: missing decisiones abiertas Q1 es fail" {
  mutate "$MS" "- Q1." "- Qx."
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"decisiones abiertas"* ]]
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

@test "negativo: faltan Q4 es fail" {
  mutate "$MS" "- Q4. " "- Qx. "
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Q4"* ]]
}

@test "negativo: cobertura de Allow-Credentials fuera de S2 es fail" {
  python3 -I - "$MS" <<'PY3'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("Allow-Credentials", "Allow-Xx")
open(p, "w", encoding="utf-8").write(s)
PY3
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S2 no cubre Allow-Credentials"* ]]
}

@test "negativo: un fichero:linea o un patron de codigo en la spec es fail" {
  printf '\nver ChatPage.vue:111\n' >> "$MS"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"detalle explotable"* ]]
}

@test "negativo: el valor de escucha por defecto en la spec es fail" {
  printf '\nescucha en 0.0.0.0\n' >> "$MS"
  run check "$MS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"detalle explotable"* ]]
}

@test "registros y changelog tampoco llevan detalle explotable (heuristica)" {
  run grep -nE 'ChatPage|FileViewer|grants\.ts|savia-bridge|auth\.ts|0\.0\.0\.0|v-html|document\.cookie|onerror|\.(vue|ts|py):[0-9]+' \
    "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json" \
    "$REPO_ROOT/docs/propuestas/LOG.d/SE-528-PROPOSED.md" \
    "$REPO_ROOT/CHANGELOG.d/se528-spec-seguridad.md"
  [ "$status" -eq 1 ]
}
