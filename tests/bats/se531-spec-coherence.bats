#!/usr/bin/env bats
# SE-531 — coherencia de la spec: tres slices con su tier, los siete campos obligatorios de la ficha,
# medir antes de supervisar, reglas fail-closed y nada privado en el texto.
# Cada comprobación se ejecuta también sobre una copia mutada y debe fallar.

set -o pipefail  # las tuberías de check() fallan si falla cualquier etapa (fail-closed)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-531-ficha-de-harness-ejecutable.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-531.json"

check() {  # check <fichero>: devuelve 0 si la spec es coherente
  local f="$1" n c last
  grep -q '^status: APPROVED$' "$f" || { echo "status != APPROVED"; return 1; }
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
  grep -q '`limite_de_turno`\*\* se relanza\|nunca\*\* se relanza' "$f" || { echo "limite_de_turno se relanza"; return 1; }
  # Criterios de aceptación: todos presentes y al menos un tipo negativo en cada slice.
  for c in AC-S1a AC-S1b AC-S1c AC-S1d AC-S1e AC-S1f AC-S1g AC-S2a AC-S2b AC-S2c AC-S2d AC-S2e AC-S2f AC-S2g AC-S3a AC-S3b AC-S3c AC-X1 AC-X2; do
    grep -q "^| $c |" "$f" || { echo "falta $c"; return 1; }
  done
  for c in S1b S2b S2f S3b; do
    grep -E "^\| AC-$c \|" "$f" | grep -q 'negativo' || { echo "AC-$c sin tipo negativo"; return 1; }
  done
  grep -q '^## OpenCode Implementation Plan$' "$f" || { echo "falta plan OpenCode"; return 1; }
  grep -q '^## Puerta de comprensión$' "$f" || { echo "falta puerta de comprensión"; return 1; }
  # Repo público: nada privado.
  # El patrón se arma en trozos para que este fichero no contenga los términos que busca.
  local priv='(mac''book|accen''ture|m[oó]ni''ca|\.sa''via/|inten''sivo|reconci''liar|des''til|Savia''Labs)'
  ! grep -inE "$priv" "$f" >/dev/null || { echo "texto privado"; return 1; }
}

check_planning() {  # check_planning <json>: 0 si es SE-531 APPROVED con evidencia existente
  python3 -I -c "
import json,os,sys
d=json.load(open(sys.argv[1]))
assert d['id']=='SE-531' and d['status']=='APPROVED', d
assert 'Ficha de harness' in d['title'], d['title']
assert os.path.exists(os.path.join(sys.argv[2], d['evidence'])), d['evidence']
" "$1" "$REPO_ROOT"
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

@test "negativo: status distinto de APPROVED falla" {
  mutate 'status: APPROVED' 'status: PROPOSED'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != APPROVED"* ]]
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
  printf '\nVer el informe en Savia''Labs.\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"texto privado"* ]]
}

@test "planning: SE-531 APPROVED apunta a la spec existente" {
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

@test "negativo: planning con otro status falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['status']='DRAFT'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DRAFT"* ]]
}
