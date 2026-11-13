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
for ac in ("AC-1.1", "AC-1.2", "AC-1.3", "AC-1.4", "AC-1.5", "AC-2.1", "AC-2.2", "AC-2.3", "AC-2.4", "AC-2.5", "AC-2.6", "AC-2.7", "AC-2.8", "AC-2.9", "AC-2.10", "AC-2.11", "AC-2.12", "AC-3.1", "AC-3.2", "AC-3.3", "AC-3.4", "AC-3.5", "AC-4.1", "AC-4.2", "AC-4.3"):
    if not re.search(rf"^- {re.escape(ac)} ", s, re.M): errs.append(f"falta {ac}")
for sec in ("## Problema", "## Puerta de comprensión", "## Fuera de alcance", "## OpenCode Implementation Plan", "## Tier de riesgo"):
    if sec not in s: errs.append(f"falta la sección {sec}")
for q in ("Q1", "Q2", "Q3"):
    if not re.search(rf"^- {q}\. ", s, re.M): errs.append(f"faltan decisiones de la operadora ({q})")
if "**Decisiones de la operadora (2026-11-13)**" not in s: errs.append("falta el registro de decisiones de la operadora")
for stale in ("Decisiones abiertas", "Preguntas abiertas", "Deprecation", "14 días", "fecha de corte", "según Q1", "según Q2", "según Q3"):
    if stale in s: errs.append("resto de una decisión abierta: " + stale)
for q, chosen in (("Q1", "sin transición"), ("Q2", "bucle local"), ("Q3", "pidan el token una vez")):
    ql = re.search(rf"^- {q}\. .*$", s, re.M)
    if ql and chosen not in ql.group(0): errs.append(f"{q} no describe lo elegido: " + chosen)
# cobertura: cada término debe aparecer en las líneas de AC (viñetas "- AC-n.m") de su slice
def acs(n):
    return "\n".join(l for l in s.splitlines() if re.match(rf"- AC-{n}\.\d+ ", l))
for n, t in ((2, "401"), (2, "Allow-Credentials"), (2, "Origin"), (3, "clave no disponible"), (3, "no cambia")):
    if t not in acs(n): errs.append(f"S{n} no cubre {t} en sus AC")
# el orden S1 < S2 < S3 < S4
pos = [s.find(f"### {x} — ") for x in ("S1", "S2", "S3", "S4")]
if pos != sorted(pos): errs.append("slices fuera de orden")
# spec pública: sin detalle explotable. Heurística mínima (lista negra); no sustituye a la revisión humana de seguridad.
leak = r"ChatPage|FileViewer|grants\.ts|savia-bridge|auth\.ts|0\.0\.0\.0|v-html|innerHTML=|document\.cookie|onerror|self\.auth_token|Cadena:|\.(vue|ts|py|kt|md|json|tsx):L?[0-9]+|src/server|projects/savia-(vaults|web)/|composables|no_auth_mode|rotate\(|ENOENT|EBUSY|GrantKeyUnavailable|--no-auth|--host|\?token=|escucha por defecto|\b[0-9a-f]{9,40}\b"
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
  run python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['id']=='SE-528' and d['status']=='PROPOSED' and d['evidence'].endswith('SE-528-seguridad-web-puente-cupulas.spec.md')" "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json"
  [ "$status" -eq 0 ]
  [ -f "$REPO_ROOT/docs/propuestas/LOG.d/SE-528-PROPOSED.md" ]
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
  mutate "$MS" "Corte inmediato del canal de credenciales retirado, sin transición" "Corte inmediato del canal de credenciales retirado, con transición"
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

@test "negativo: un detalle de mecanica o de simbolo en la spec es fail" {
  for t in "rotate()" "no_auth_mode" "src/server" "--no-auth" "?token=" "ENOENT"; do
    cp "$SPEC" "$MS"
    printf '\nnota %s\n' "$t" >> "$MS"
    run check "$MS"
    [ "$status" -eq 1 ]
    [[ "$output" == *"detalle explotable"* ]]
  done
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
  run grep -nE 'ChatPage|FileViewer|grants\.ts|savia-bridge|auth\.ts|0\.0\.0\.0|v-html|document\.cookie|onerror|src/server|no_auth_mode|rotate\(|ENOENT|--no-auth|\?token=|\.(vue|ts|py):[0-9]+' \
    "$REPO_ROOT/docs/propuestas/planning.d/SE-528.json" \
    "$REPO_ROOT/docs/propuestas/LOG.d/SE-528-PROPOSED.md" \
    "$REPO_ROOT/CHANGELOG.d/se528-spec-seguridad.md"
  [ "$status" -eq 1 ]
}
