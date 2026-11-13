#!/usr/bin/env bats
# SE-528 — coherencia de la spec: front-matter, slices con AC, referencias vivas en main,
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
s = open(sys.argv[1], encoding="utf-8").read()
errs = []
fm = re.match(r"---\n(.*?)\n---\n", s, re.S)
if not fm: sys.exit("sin front-matter")
f = fm.group(1)
if "status: PROPOSED" not in f: errs.append("status no es PROPOSED")
for sl in ("S1", "S2", "S3"):
    if not re.search(rf"^### {sl} — ", s, re.M): errs.append(f"falta el slice {sl}")
for ac in ("AC-1.1", "AC-1.4", "AC-2.1", "AC-2.3", "AC-2.4", "AC-3.1", "AC-3.4"):
    if ac not in s: errs.append(f"falta {ac}")
for t in ("onerror", "?token=", "EBUSY", "ENOENT", "--no-auth"):
    if t not in s: errs.append(f"falta cobertura de {t}")
for sec in ("## Problema", "## Puerta de comprensión", "## Fuera de alcance", "## OpenCode Implementation Plan", "## Tier de riesgo"):
    if sec not in s: errs.append(f"falta la sección {sec}")
if not re.search(r"Q1\.", s): errs.append("faltan decisiones abiertas Q1-Q3")
# el orden S1 < S2 < S3
pos = [s.find(f"### {x} — ") for x in ("S1", "S2", "S3")]
if pos != sorted(pos): errs.append("slices fuera de orden")
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

@test "negativo: missing AC-3.1 (caso ENOENT/EBUSY) es fail" {
  mutate "$MS" "- AC-3.1 Test:" "- AC-3.X Test:"; sed -i "s/AC-3\.1/AC-3.X/g" "$MS"
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
  mutate "$MS" "### S1 — " "### S9 — "
  run check "$MS"
  [ "$status" -eq 1 ]
}

@test "referencias vivas: las líneas citadas siguen existiendo en main" {
  grep -q 'v-html="renderMd(msg.content)"' "$REPO_ROOT/projects/savia-web/src/pages/ChatPage.vue"
  grep -q 'v-html="markdownBody"' "$REPO_ROOT/projects/savia-web/src/components/files/FileViewer.vue"
  grep -q 'document.cookie = `${COOKIE_NAME}' "$REPO_ROOT/projects/savia-web/src/stores/auth.ts"
  grep -q 'params.get("token"' "$REPO_ROOT/scripts/savia-bridge.py"
  grep -q 'if not self.auth_token:' "$REPO_ROOT/scripts/savia-bridge.py"
  grep -q 'return this.rotate();' "$REPO_ROOT/projects/savia-vaults/src/server/grants.ts"
}

@test "planning.d y LOG.d de SE-528 existen y coinciden con la spec" {
  run python3 -I -c "import json,sys; d=json.load(open('$REPO_ROOT/docs/propuestas/planning.d/SE-528.json')); assert d['id']=='SE-528' and d['status']=='PROPOSED' and d['evidence'].endswith('SE-528-seguridad-web-puente-cupulas.spec.md')"
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
  [ "$status" -ne 0 ]
}
