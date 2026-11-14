#!/usr/bin/env bats
# SE-529 — coherencia de la spec de compactación.
# Ref: docs/specs/SE-529-compactacion-que-conserva-y-reinyecta.spec.md
# Comprobador: tests/se529_spec_check.py. Caso positivo (la spec real pasa) y casos
# negativos (copias mutadas fallan con su motivo).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-529-compactacion-que-conserva-y-reinyecta.spec.md"
CHECK="$REPO_ROOT/tests/se529_spec_check.py"
PLAN="$REPO_ROOT/docs/propuestas/planning.d/SE-529.json"

setup() {
  MS="$BATS_TEST_TMPDIR/spec.md"
  cp "$SPEC" "$MS"
}

# mutate <fichero> <viejo> <nuevo>: sustitución literal; falla si no encuentra el texto.
mutate() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit("mutación sin efecto: " + old[:60])
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

@test "real: coherente" {
  run python3 -I "$CHECK" "$SPEC" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uso: sin argumentos sale 2" {
  run python3 -I "$CHECK"
  [ "$status" -eq 2 ]
}

@test "fichero ausente sale 2" {
  run python3 -I "$CHECK" /nonexistent/spec.md "$REPO_ROOT"
  [ "$status" -eq 2 ]
}

@test "referencia a un fichero inexistente falla" {
  python3 -I - "$MS" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("tests/test-pre-compact-backup.bats", "tests/no-existe-compact.bats"))
PY
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fichero inexistente"* ]]
}

@test "referencia fuera de rango falla" {
  mutate "$MS" "pre-compact-backup.sh\`, que es" "pre-compact-backup.sh:9999\`, que es"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fuera de rango"* ]]
}

@test "falta un AC falla" {
  mutate "$MS" "**AC-9 (S2 negativos):**" "**Otra cosa (S2 negativos):**"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta AC-9"* ]]
}

@test "un AC marcado como cumplido sin implementar falla" {
  mutate "$MS" "- [ ] **AC-4 " "- [x] **AC-4 "
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"marcado como cumplido"* ]]
}

@test "status APPROVED con el prototipo sin confirmar falla" {
  mutate "$MS" "status: PROPOSED" "status: APPROVED"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"status debe ser PROPOSED"* ]]
}

@test "sin la comprobacion de ruta (realpath) falla" {
  python3 -I - "$MS" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("realpath", "ruta"))
PY
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ruta no fiable"* ]]
}

@test "sin la salida honesta 'no confirmado' falla" {
  python3 -I - "$MS" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("no confirmado", "guardado"))
PY
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fail honesto"* ]]
}

@test "S4 sin la salida 'no aplicable' falla" {
  mutate "$MS" "**no aplicable**" "aplicable"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S4 puede ser no aplicable"* ]]
}

@test "sin fijar parametros antes de S1/S2 falla" {
  mutate "$MS" "antes de ver el resultado de S1/S2" "cuando convenga"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S0 fija parámetros"* ]]
}

@test "un termino privado en la spec falla" {
  printf '\nVer informe en %s.\n' "Savia""Labs" >> "$MS"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"término no permitido"* ]]
}

@test "falta la seccion S5 falla" {
  mutate "$MS" "### S5 — Redacción" "### Redacción"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta la sección de S5"* ]]
}

@test "planning: SE-529 PROPOSED con evidencia existente" {
  run python3 -I - "$PLAN" "$REPO_ROOT" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
assert d["id"] == "SE-529" and d["status"] == "PROPOSED" and "approval" not in d, d
assert os.path.isfile(os.path.join(sys.argv[2], d["evidence"])), d["evidence"]
PY
  [ "$status" -eq 0 ]
}

@test "Q2 reabierta (sin marca de resuelta) falla" {
  mutate "$MS" "**Q2 (resuelta, 2026-11-13).**" "**Q2.**"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Q2 resuelta"* ]]
}

@test "paridad sin aceptar el aviso explicito falla" {
  mutate "$MS" "ese aviso se acepta como paridad (Q2, resuelta)" "se exige fuente alternativa"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"paridad por aviso explícito"* ]]
}

@test "S1 que exige fuente alternativa falla" {
  mutate "$MS" "no se busca una fuente alternativa" "se busca una fuente alternativa"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S1 sin fuente alternativa"* ]]
}

@test "Q3 debe constar resuelta: Q3 borrada falla" {
  mutate "$MS" "- **Q3 (resuelta, 2026-11-13).**" "- Q3 borrada."
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Q3 resuelta"* ]]
}

@test "Q2 sin registro de la orquestadora (texto literal) falla" {
  mutate "$MS" "registro de la orquestadora, no texto literal" "texto literal"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Q2 registrada"* ]]
}

@test "confirmación del prototipo pendiente: spec que la marca respondida falla" {
  mutate "$MS" "- respuesta: pendiente. La spec no pasa a APPROVED ni S1 se pone en curso" "- respuesta: aprobada. La spec no pasa a APPROVED ni S1 se pone en curso"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"confirmación del prototipo pendiente"* ]]
}

@test "confirmación de las escenas sin fecha falla" {
  mutate "$MS" "- fecha: 2026-11-13
- respuesta: «Confirmo" "- fecha: pendiente
- respuesta: «Confirmo"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"confirmación de las escenas sin fecha"* ]]
}

@test "confirmación de las escenas con respuesta vacía falla" {
  mutate "$MS" "- respuesta: «Confirmo todo como está»." "- respuesta: «»."
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin respuesta literal"* ]]
}

@test "S0 sin la línea del prototipo falla" {
  mutate "$MS" "- prototipo: " "- prototipado: "
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S0 con prototipo"* ]]
}

@test "Q1 borrada falla" {
  mutate "$MS" "- **Q1 (resuelta, 2026-11-13).**" "- Q1 borrada."
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Q1 resuelta"* ]]
}

@test "referencia con .. fuera de la raiz falla" {
  mutate "$MS" "pre-compact-backup.sh\`, que es" "pre-compact-backup.sh:1\` y \`../../../../etc/hosts.json:1\`, que es"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fuera de la raíz"* ]]
}

@test "palabra española común no da falso positivo (armónica)" {
  printf '\nUna melodía armónica y destilada.\n' >> "$MS"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "spec no UTF-8 sale 2, no traceback" {
  printf '\xff\xfe\x00' > "$MS"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 2 ]
}

@test "término privado en el planning falla" {
  R="$BATS_TEST_TMPDIR/root"; mkdir -p "$R/docs/propuestas/planning.d" "$R/CHANGELOG.d" "$R/docs/propuestas/LOG.d"
  cp "$REPO_ROOT/CHANGELOG.d/se529-compactacion.md" "$R/CHANGELOG.d/"
  cp "$REPO_ROOT/docs/propuestas/LOG.d/SE-529-PROPOSED.md" "$R/docs/propuestas/LOG.d/"
  cp "$PLAN" "$R/docs/propuestas/planning.d/SE-529.json"
  cp "$REPO_ROOT/docs/propuestas/ROADMAP-CURRENT.md" "$R/docs/propuestas/"
  python3 -I -c "
import sys
p=sys.argv[1]; open(p,'a').write('mac'+'book')" "$R/docs/propuestas/planning.d/SE-529.json"
  run python3 -I "$CHECK" "$SPEC" "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-529.json"*"término no permitido"* ]]
}

@test "ruta privada de usuario en la spec falla (el ancla no la desactiva)" {
  python3 -I -c "
import sys
open(sys.argv[1],'a').write('\nVer ~/.sa'+'via/x y \`/home/u/.sa'+'via/\` aqui.\n')" "$MS"
  run python3 -I "$CHECK" "$MS" "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"término no permitido"* ]]
}

@test "fichero público ausente falla en vez de saltarse el escaneo" {
  R="$BATS_TEST_TMPDIR/root2"; mkdir -p "$R/CHANGELOG.d"
  cp "$REPO_ROOT/CHANGELOG.d/se529-compactacion.md" "$R/CHANGELOG.d/"
  run python3 -I "$CHECK" "$SPEC" "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-529.json ausente o ilegible"* ]]
}

@test "planning APPROVED con la spec en PROPOSED falla" {
  R="$BATS_TEST_TMPDIR/root3"; mkdir -p "$R/docs/propuestas/planning.d" "$R/CHANGELOG.d" "$R/docs/propuestas/LOG.d"
  cp "$REPO_ROOT/CHANGELOG.d/se529-compactacion.md" "$R/CHANGELOG.d/"
  cp "$REPO_ROOT/docs/propuestas/LOG.d/SE-529-PROPOSED.md" "$R/docs/propuestas/LOG.d/"
  cp "$REPO_ROOT/docs/propuestas/ROADMAP-CURRENT.md" "$R/docs/propuestas/"
  sed 's/"status": "PROPOSED"/"status": "APPROVED"/' "$PLAN" > "$R/docs/propuestas/planning.d/SE-529.json"
  run python3 -I "$CHECK" "$SPEC" "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"planning: SE-529 debe ser PROPOSED"* ]]
}

@test "roadmap con SE-529 APPROVED falla" {
  R="$BATS_TEST_TMPDIR/root4"; mkdir -p "$R/docs/propuestas/planning.d" "$R/CHANGELOG.d" "$R/docs/propuestas/LOG.d"
  cp "$REPO_ROOT/CHANGELOG.d/se529-compactacion.md" "$R/CHANGELOG.d/"
  cp "$REPO_ROOT/docs/propuestas/LOG.d/SE-529-PROPOSED.md" "$R/docs/propuestas/LOG.d/"
  cp "$PLAN" "$R/docs/propuestas/planning.d/SE-529.json"
  cp "$REPO_ROOT/docs/propuestas/ROADMAP-CURRENT.md" "$R/docs/propuestas/"
  printf -- '- SE-529 [APPROVED] x\n' >> "$R/docs/propuestas/ROADMAP-CURRENT.md"
  run python3 -I "$CHECK" "$SPEC" "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"roadmap: SE-529 figura APPROVED"* ]]
}
