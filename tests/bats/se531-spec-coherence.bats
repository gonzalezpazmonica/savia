#!/usr/bin/env bats
# SE-531 — coherencia de la spec: tres slices con su tier, los siete campos obligatorios de la ficha,
# medir antes de supervisar, reglas fail-closed y nada privado en el texto.
# Cada comprobación se ejecuta también sobre una copia mutada y debe fallar.

set -o pipefail  # las tuberías de check() fallan si falla cualquier etapa (fail-closed)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-531-ficha-de-harness-ejecutable.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-531.json"
ROADMAP="$REPO_ROOT/docs/propuestas/ROADMAP-CURRENT.md"

check() {  # check <fichero>: devuelve 0 si la spec es coherente
  local f="$1" n c last
  grep -qE '^status: (PROPOSED|APPROVED|IMPLEMENTED)$' "$f" || { echo "status fuera del ciclo de vida"; return 1; }
  grep -q '^human_surface: false$' "$f" || { echo "human_surface"; return 1; }
  grep -q '^# SE-531 — Ficha de harness ejecutable' "$f" || { echo "título"; return 1; }
  for n in 1 2 3; do
    grep -q "^### S$n — " "$f" || { echo "falta slice S$n"; return 1; }
  done
  ! grep -q '^### S4 — ' "$f" || { echo "slice de más"; return 1; }
  last=$(grep -E '^### S[0-9] — ' "$f" | tail -1 | cut -c1-6)
  [ "$last" = "### S3" ] || { echo "S3 no es el último"; return 1; }
  # Tabla de slices: tier 2, 2–3 y 3 en la columna «Tier».
  grep -qE '^\| S1 \|.*\| \*\*2\*\* \|' "$f" || { echo "tier de S1"; return 1; }
  grep -qE '^\| S2 \|.*\| \*\*2–3\*\* \|' "$f" || { echo "tier de S2"; return 1; }
  grep -qE '^\| S3 \|.*\| \*\*3\*\* \|' "$f" || { echo "tier de S3"; return 1; }
  # Los siete campos obligatorios de la ficha, una fila cada uno en la tabla D1.
  for c in aislamiento rc_en_error senal_cuota informa_uso reanudacion limpieza flujo_llamadas; do
    grep -qE "^\| \`$c\` \|" "$f" || { echo "falta el campo $c"; return 1; }
  done
  grep -qE '^\| `rc_deteccion` \|.*obligatorio si `rc_en_error` es `no_fiable`' "$f" || { echo "regla de rc_deteccion"; return 1; }
  # Fail-closed y supervisión.
  grep -q 'la opción más desconfiada' "$f" || { echo "no_medido sin tratamiento desconfiado"; return 1; }
  grep -q 'Medir primero' "$f" || { echo "falta medir primero"; return 1; }
  grep -q 'por defecto N = 3' "$f" || { echo "falta N por defecto"; return 1; }
  grep -q 'Sin recibo, o con un campo ilegible: no se relanza' "$f" || { echo "relanzar sin recibo"; return 1; }
  grep -qF 'Un corte por `limite_de_turno` **nunca** se relanza' "$f" || { echo "limite_de_turno se relanza"; return 1; }
  grep -qF 'ni se anota como fallo del proveedor' "$f" || { echo "limite_de_turno como fallo del proveedor"; return 1; }
  grep -qF '`rc_deteccion` es un dato, no código' "$f" || { echo "rc_deteccion ejecutable"; return 1; }
  grep -qF '`no_medido` se lee siempre como' "$f" || { echo "no_medido sin lectura concreta"; return 1; }
  # Criterios de aceptación: todos presentes y al menos un tipo negativo en cada slice.
  for c in AC-S1a AC-S1b AC-S1c AC-S1d AC-S1e AC-S1f AC-S1g AC-S1h AC-S1i AC-S2a AC-S2b AC-S2c AC-S2d AC-S2e AC-S2f AC-S2g AC-S3a AC-S3b AC-S3c AC-X1 AC-X2; do
    grep -q "^| $c |" "$f" || { echo "falta $c"; return 1; }
  done
  for c in S1b S1h S1i S2b S2f S3b; do
    grep -E "^\| AC-$c \|" "$f" | grep -q 'negativo' || { echo "AC-$c sin tipo negativo"; return 1; }
  done
  grep -q '^## OpenCode Implementation Plan$' "$f" || { echo "falta plan OpenCode"; return 1; }
  grep -q '^## Puerta de comprensión$' "$f" || { echo "falta puerta de comprensión"; return 1; }
  # Repo público: nada privado.
  # El patrón se arma en trozos para que este fichero no contenga los términos que busca.
  local priv='(mac''book|accen''ture|m[oó]ni''ca|\.sa''via/|inten''sivo|reconci''liar|des''til|/ho''me/|@gm''ail)'
  ! grep -inE "$priv" "$f" >/dev/null || { echo "texto privado"; return 1; }
}

spec_status() { sed -n 's/^status: //p' "$1" | head -1; }

check_planning() {  # check_planning <json> [spec] [roadmap]: 0 si planning, spec y roadmap coinciden y la evidencia es una ruta del repo
  python3 -I -c "
import json,os,re,sys
d=json.load(open(sys.argv[1])); root=os.path.realpath(sys.argv[2])
assert d['id']=='SE-531', d
assert d['status'] in ('PROPOSED','APPROVED','IMPLEMENTED'), d['status']
assert 'Ficha de harness' in d['title'], d['title']
ev=d['evidence']
assert not os.path.isabs(ev) and '..' not in ev.split('/'), 'ruta no relativa: '+ev
real=os.path.realpath(os.path.join(root, ev))
assert real.startswith(root+os.sep) and os.path.exists(real), 'evidencia: '+ev
m=re.search(r'(?m)^status: (\\w+)\$', open(sys.argv[3],encoding='utf-8').read())
assert m and m.group(1)==d['status'], 'estado spec != planning: %s vs %s' % (m and m.group(1), d['status'])
r=re.search(r'(?m)^- SE-531 \\[(\\w+)\\]', open(sys.argv[4],encoding='utf-8').read())
assert r and r.group(1)==d['status'], 'estado roadmap != planning: %s vs %s' % (r and r.group(1), d['status'])
" "$1" "$REPO_ROOT" "${2:-$SPEC}" "${3:-$ROADMAP}"
}

check_files() {  # nada privado en los ficheros de apoyo de la PR
  local priv='(mac''book|accen''ture|m[oó]ni''ca|\.sa''via/|inten''sivo|/ho''me/|@gm''ail)' f
  for f in "$REPO_ROOT"/CHANGELOG.d/se531-*.md "$REPO_ROOT"/docs/propuestas/LOG.d/SE-531-*.md "$STATE"; do
    ! grep -inE "$priv" "$f" >/dev/null || { echo "texto privado en $f"; return 1; }
  done
  ! grep -lE 'SE-531 \(PROPOSED\)|sigue PROPOSED' "$REPO_ROOT"/CHANGELOG.d/se531-*.md "$REPO_ROOT"/docs/propuestas/LOG.d/SE-531-*.md | grep -q . \
    || { echo "estado obsoleto en un fragmento"; return 1; }
}

setup() {
  M="$BATS_TEST_TMPDIR/spec.md"; cp "$SPEC" "$M"
}

mutate() { python3 -I - "$M" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit("mutación sin efecto: " + old[:50])
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}

@test "real: la spec es coherente" {
  run check "$SPEC"
  [ "$status" -eq 0 ]
}

@test "negativo: status fuera del ciclo de vida falla" {
  mutate 'status: APPROVED' 'status: DRAFT'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status fuera del ciclo de vida"* ]]
}

@test "ciclo de vida: PROPOSED sigue siendo un estado válido (el test no blinda APPROVED)" {
  mutate 'status: APPROVED' 'status: PROPOSED'
  run check "$M"
  [ "$status" -eq 0 ]
}

@test "negativo: human_surface true falla" {
  mutate 'human_surface: false' 'human_surface: true'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"human_surface"* ]]
}

@test "negativo: faltar S2 falla" {
  mutate '### S2 — ' '### Sx — '
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta slice S2"* ]]
}

@test "negativo: un cuarto slice falla" {
  printf '\n### S4 — Extra\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"slice de más"* ]]
}

@test "negativo: S2 después de S3 falla" {
  python3 -I - "$M" <<'PY2'
import re,sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
parts=re.split(r'(?m)^(?=### S[0-9] — )',s)
i2=[i for i,x in enumerate(parts) if x.startswith('### S2 — ')][0]
i3=[i for i,x in enumerate(parts) if x.startswith('### S3 — ')][0]
parts[i2],parts[i3]=parts[i3],parts[i2]
open(p,"w",encoding="utf-8").write("".join(parts))
PY2
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"S3 no es el último"* ]]
}

@test "negativo: S3 con tier 2 falla" {
  mutate '| Este repo | **3** |' '| Este repo | **2** |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier de S3"* ]]
}

@test "negativo: S2 con tier 2 a secas falla" {
  mutate '**2–3**' '**2**'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier de S2"* ]]
}

@test "negativo: quitar un campo obligatorio de la ficha falla (uno por campo)" {
  for c in aislamiento rc_en_error senal_cuota informa_uso reanudacion limpieza flujo_llamadas; do
    cp "$SPEC" "$M"
    mutate "| \`$c\` |" "| \`x_$c\` |"
    run check "$M"
    [ "$status" -ne 0 ]
    [[ "$output" == *"falta el campo $c"* ]]
  done
}

@test "negativo: rc_deteccion sin su regla condicional falla" {
  mutate 'obligatorio si `rc_en_error` es `no_fiable`' 'opcional'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"regla de rc_deteccion"* ]]
}

@test "negativo: no_medido sin trato desconfiado falla" {
  mutate 'la opción más desconfiada' 'una opción neutra'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no_medido sin tratamiento desconfiado"* ]]
}

@test "negativo: quitar la medición previa de huérfanos falla" {
  mutate 'Medir primero' 'Medir después'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta medir primero"* ]]
}

@test "negativo: relanzar sin recibo deja de estar prohibido y falla" {
  mutate 'Sin recibo, o con un campo ilegible: no se relanza' 'Sin recibo se relanza'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"relanzar sin recibo"* ]]
}

@test "negativo: quitar un criterio de aceptación falla" {
  mutate '| AC-S2f |' '| AC-S2z |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta AC-S2f"* ]]
}

@test "negativo: un AC de rechazo marcado como positivo falla" {
  mutate '| AC-S1b | El validador falla si una ficha usa un runtime sin bloque `runtime`. | negativo |' '| AC-S1b | El validador falla si una ficha usa un runtime sin bloque `runtime`. | positivo |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC-S1b sin tipo negativo"* ]]
}

@test "negativo: un texto privado en la spec falla" {
  printf '\nVer el informe en /ho''me/alguien.\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"texto privado"* ]]
}

@test "negativo: quitar la regla de no_medido desconfiado concreto falla" {
  mutate '`no_medido` se lee siempre como' '`no_medido` se puede leer como'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no_medido sin lectura concreta"* ]]
}

@test "negativo: quitar la regla de límite de turno no relanzable falla" {
  mutate 'Un corte por `limite_de_turno` **nunca** se relanza' 'Un corte por `limite_de_turno` se relanza'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"limite_de_turno se relanza"* ]]
}

@test "negativo: límite de turno anotado como fallo del proveedor falla" {
  mutate 'ni se anota como fallo del proveedor' 'y se anota como fallo del proveedor'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"limite_de_turno como fallo del proveedor"* ]]
}

@test "negativo: N por defecto distinto de 3 falla" {
  mutate 'por defecto N = 3' 'por defecto N = 9'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta N por defecto"* ]]
}

@test "negativo: rc_deteccion sin la regla de dato no ejecutable falla" {
  mutate '`rc_deteccion` es un dato, no código' '`rc_deteccion` es una orden'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rc_deteccion ejecutable"* ]]
}

@test "negativo: quitar AC-S1h o AC-S1i falla" {
  mutate '| AC-S1h |' '| AC-S1z |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta AC-S1h"* ]]
}

@test "ficheros de apoyo: sin texto privado ni estado obsoleto" {
  run check_files
  [ "$status" -eq 0 ]
}

@test "negativo: un fragmento con ruta personal falla" {
  mkdir -p "$BATS_TEST_TMPDIR/r/CHANGELOG.d" "$BATS_TEST_TMPDIR/r/docs/propuestas/LOG.d"
  cp "$REPO_ROOT"/CHANGELOG.d/se531-*.md "$BATS_TEST_TMPDIR/r/CHANGELOG.d/"
  cp "$REPO_ROOT"/docs/propuestas/LOG.d/SE-531-*.md "$BATS_TEST_TMPDIR/r/docs/propuestas/LOG.d/"
  printf '\nver /ho''me/alguien/x\n' >> "$BATS_TEST_TMPDIR/r/CHANGELOG.d/se531-ficha-harness.md"
  REPO_ROOT="$BATS_TEST_TMPDIR/r" run check_files
  [ "$status" -ne 0 ]
  [[ "$output" == *"texto privado en"* ]]
}

@test "negativo: un fragmento con estado PROPOSED obsoleto falla" {
  mkdir -p "$BATS_TEST_TMPDIR/r/CHANGELOG.d" "$BATS_TEST_TMPDIR/r/docs/propuestas/LOG.d"
  cp "$REPO_ROOT"/CHANGELOG.d/se531-*.md "$BATS_TEST_TMPDIR/r/CHANGELOG.d/"
  cp "$REPO_ROOT"/docs/propuestas/LOG.d/SE-531-*.md "$BATS_TEST_TMPDIR/r/docs/propuestas/LOG.d/"
  printf '\nSE-531 (PROPOSED)\n' >> "$BATS_TEST_TMPDIR/r/CHANGELOG.d/se531-ficha-harness.md"
  REPO_ROOT="$BATS_TEST_TMPDIR/r" run check_files
  [ "$status" -ne 0 ]
  [[ "$output" == *"estado obsoleto"* ]]
}

@test "planning: SE-531 coincide con la spec y el roadmap y apunta a la spec existente" {
  run check_planning "$STATE"
  [ "$status" -eq 0 ]
}

@test "negativo: planning con spec inexistente falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['evidence']='docs/specs/no-existe.md'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-existe.md"* ]]
}

@test "negativo: evidencia con salida del repo falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['evidence']='docs/../../etc/passwd'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ruta no relativa"* ]]
}

@test "negativo: planning y spec con estados distintos fallan" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['status']='PROPOSED'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"estado spec != planning"* ]]
}

@test "negativo: roadmap con otro estado que planning falla" {
  sed 's/^- SE-531 \[APPROVED\]/- SE-531 [PROPOSED]/' "$ROADMAP" > "$BATS_TEST_TMPDIR/rm.md"
  grep -q 'SE-531 \[PROPOSED\]' "$BATS_TEST_TMPDIR/rm.md"
  run check_planning "$STATE" "$SPEC" "$BATS_TEST_TMPDIR/rm.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"estado roadmap != planning"* ]]
}

@test "negativo: planning con otro status falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['status']='DRAFT'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DRAFT"* ]]
}
