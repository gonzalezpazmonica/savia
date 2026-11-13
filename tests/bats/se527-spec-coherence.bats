#!/usr/bin/env bats
# SE-527 — coherencia de la spec: cuatro slices, S4 el último, neto 14, tier 4 declarado,
# sin interfaz humana, sin contradecir «ahorro de mantenimiento, no de contexto».
# Cada comprobación se ejecuta también sobre una copia mutada y debe fallar.

set -o pipefail  # las tuberías de check() fallan si falla cualquier etapa (fail-closed)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-527-recorte-de-agentes-sobrantes.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-527.json"

check() {  # check <fichero>: devuelve 0 si la spec es coherente
  local f="$1"
  grep -q '^status: PROPOSED$' "$f" || { echo "status != PROPOSED"; return 1; }
  grep -q '^human_surface: false$' "$f" || { echo "human_surface"; return 1; }
  for n in 1 2 3 4; do
    grep -q "^### S$n — " "$f" || { echo "falta slice S$n"; return 1; }
  done
  ! grep -q '^### S5 — ' "$f" || { echo "slice de más"; return 1; }
  # Orden: S4 es el último encabezado de slice (todos los anteriores van antes).
  local last
  last=$(grep -E '^### S[0-9] — ' "$f" | tail -1 | cut -c1-6)
  [ "$last" = "### S4" ] || { echo "S4 no es el último"; return 1; }
  # Cifras: los netos de la tabla D1 suman el total declarado y coinciden con el título y el planning.
  local sum
  sum=$(grep -E '^\| S[1-9] \|' "$f" | sed -E 's/.*\| −([0-9]+) \|[^|]*\|[^|]*\|$/\1/' | paste -sd+ | bc)
  [ "$sum" = "14" ] || { echo "suma de netos $sum != 14"; return 1; }
  grep -q '^# SE-527 — .*(14 de 90, en cuatro slices)' "$f" || { echo "título sin 14 de 90"; return 1; }
  grep -q 'Total −14: 90 → 76' "$f" || { echo "falta total 90 → 76"; return 1; }
  # Cifras antiguas: ninguna aparece (el 75 de espejos es otro dato y no cuenta).
  local old
  for old in '−19' '−15' '90 → 71' '90 → 75' '15 de 90' '19 de 90' 'cinco slices' 'cinco paquetes'; do
    ! grep -q -- "$old" "$f" || { echo "queda cifra antigua: $old"; return 1; }
  done
  # Los cuatro slices de la tabla D1 declaran tier 4 en la última columna.
  local tiers
  tiers=$(grep -cE '^\| S[1-9] \|.*\| \*\*4\*\* \|$' "$f")
  [ "$tiers" -eq 4 ] || { echo "tier 4 declarado en $tiers de 4 slices"; return 1; }
  grep -q 'No es una reducción de contexto' "$f" || { echo "falta aviso de contexto"; return 1; }
  grep -q 'S4 va el último' "$f" || { echo "falta S4 último"; return 1; }
  grep -q '^### D5 — Por qué S5 sale de la spec$' "$f" || { echo "falta D5 de S5 fuera"; return 1; }
  grep -q '^- Los seis agentes por lenguaje (`go-developer`' "$f" || { echo "falta fuera de alcance de lenguajes"; return 1; }
  grep -q '^## OpenCode Implementation Plan$' "$f" || { echo "falta plan OpenCode"; return 1; }
}

check_planning() {  # check_planning <json>: 0 si es SE-527 PROPOSED, título 14 de 90 y evidencia existente
  python3 -I -c "
import json,os,sys
d=json.load(open(sys.argv[1]))
assert d['id']=='SE-527' and d['status']=='PROPOSED', d
assert '14 de 90' in d['title'], d['title']
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
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

@test "real: la spec es coherente" {
  run check "$SPEC"
  [ "$status" -eq 0 ]
}

@test "negativo: un slice con tier distinto de 4 falla" {
  mutate '| Bajo | **4** |' '| Bajo | **2** |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier 4 declarado en 3 de 4"* ]]
}

@test "negativo: faltar S3 falla" {
  mutate '### S3 — ' '### Sx — '
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta slice S3"* ]]
}

@test "negativo: S4 antes de S3 falla" {
  python3 -I - "$M" <<'PY2'
import re,sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
parts=re.split(r'(?m)^(?=### S[0-9] — )',s)
i3=[i for i,x in enumerate(parts) if x.startswith('### S3 — ')][0]
i4=[i for i,x in enumerate(parts) if x.startswith('### S4 — ')][0]
parts[i3],parts[i4]=parts[i4],parts[i3]
open(p,"w",encoding="utf-8").write("".join(parts))
PY2
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"S4 no es el último"* ]]
}

@test "negativo: human_surface true falla" {
  mutate 'human_surface: false' 'human_surface: true'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"human_surface"* ]]
}

@test "negativo: sin el aviso de que no recorta contexto falla" {
  mutate 'No es una reducción de contexto' 'recorta contexto'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta aviso de contexto"* ]]
}

@test "planning: SE-527 PROPOSED apunta a la spec existente" {
  run check_planning "$STATE"
  [ "$status" -eq 0 ]
}

@test "negativo: el estado de planning con spec inexistente falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['evidence']='docs/specs/no-existe.md'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-existe.md"* ]]
}

@test "negativo: el estado de planning con otro status falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['status']='DRAFT'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DRAFT"* ]]
}

@test "edge: empty spec falla" {
  : > "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != PROPOSED"* ]]
}

@test "edge: nonexistent spec falla" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != PROPOSED"* ]]
}

@test "edge: boundary, solo 3 de 4 slices con tier 4 falla (zero tolerancia)" {
  mutate '| Medio | **4** |
| S4' '| Medio | **3** |
| S4'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier 4 declarado en 3 de 4"* ]]
}

@test "negativo: un **4** en otra columna no cuenta como tier" {
  mutate '| Bajo | **4** |' '| **4** | Bajo |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier 4 declarado en 3 de 4"* ]]
}

@test "negativo: encabezado de slice duplicado no rompe el orden con error confuso" {
  mutate '### S2 — ' '### S4 — '
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta slice S2"* ]]
}

@test "negativo: reintroducir un slice S5 falla" {
  printf '\n### S5 — Desarrolladores por lenguaje\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"slice de más"* ]]
}

@test "negativo: un S5 en la tabla D1 falla por tier/suma" {
  mutate '| S4 | P4' '| S5 | P5 lenguajes | x | −1 | Medio-alto | **4** |
| S4 | P4'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"suma de netos"* ]]
}

@test "negativo: status APPROVED en la spec falla (sin confirmación de la operadora)" {
  mutate 'status: PROPOSED' 'status: APPROVED'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != PROPOSED"* ]]
}

@test "negativo: una cifra desfasada (suma de netos) falla" {
  mutate '| −3 | Bajo-medio |' '| −5 | Bajo-medio |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"suma de netos 16 != 14"* ]]
}

@test "negativo: cada cifra antigua residual falla" {
  local old
  for old in '−19 agentes' '−15 agentes' 'pasa a 90 → 71' 'pasa a 90 → 75'; do
    cp "$SPEC" "$M"
    mutate 'Total −14: 90 → 76' "$old; Total −14: 90 → 76"
    run check "$M"
    [ "$status" -ne 0 ]
    [[ "$output" == *"queda cifra antigua"* ]]
  done
}

@test "negativo: faltar la sección de por qué S5 sale falla" {
  mutate '### D5 — Por qué S5 sale de la spec' '### D5 — Otra cosa'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta D5 de S5 fuera"* ]]
}

@test "negativo: faltar los agentes por lenguaje en fuera de alcance falla" {
  mutate '- Los seis agentes por lenguaje (`go-developer`' '- Los agentes (`go-developer`'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"fuera de alcance de lenguajes"* ]]
}

@test "negativo: planning con título desfasado falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['title']=d['title'].replace('14 de 90','19 de 90')
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"19 de 90"* ]]
}

@test "negativo: planning APPROVED falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['status']='APPROVED'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
}
