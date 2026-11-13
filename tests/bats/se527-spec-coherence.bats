#!/usr/bin/env bats
# SE-527 — coherencia de la spec: cinco slices, S5 el último, tier 4 declarado,
# sin interfaz humana, sin contradecir «ahorro de mantenimiento, no de contexto».
# Cada comprobación se ejecuta también sobre una copia mutada y debe fallar.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-527-recorte-de-agentes-sobrantes.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-527.json"

check() {  # check <fichero>: devuelve 0 si la spec es coherente
  local f="$1"
  grep -q '^status: PROPOSED$' "$f" || { echo "status != PROPOSED"; return 1; }
  grep -q '^human_surface: false$' "$f" || { echo "human_surface"; return 1; }
  for n in 1 2 3 4 5; do
    grep -q "^### S$n — " "$f" || { echo "falta slice S$n"; return 1; }
  done
  ! grep -q '^### S6 — ' "$f" || { echo "slice de más"; return 1; }
  # Orden: el encabezado de S5 va después del de S4.
  local l4 l5
  l4=$(grep -n '^### S4 — ' "$f" | cut -d: -f1); l5=$(grep -n '^### S5 — ' "$f" | cut -d: -f1)
  [ "$l5" -gt "$l4" ] || { echo "S5 no es el último"; return 1; }
  # Los cinco slices de la tabla D1 declaran tier 4.
  local tiers
  tiers=$(grep -cE '^\| S[1-5] \|.*\*\*4\*\*' "$f")
  [ "$tiers" -eq 5 ] || { echo "tier 4 declarado en $tiers de 5 slices"; return 1; }
  grep -q 'No es una reducción de contexto' "$f" || { echo "falta aviso de contexto"; return 1; }
  grep -q 'S5 va el último' "$f" || { echo "falta S5 último"; return 1; }
  grep -q '^## OpenCode Implementation Plan$' "$f" || { echo "falta plan OpenCode"; return 1; }
}

setup() {
  set -uo pipefail
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
  [[ "$output" == *"tier 4 declarado en 4 de 5"* ]]
}

@test "negativo: faltar S3 falla" {
  mutate '### S3 — ' '### Sx — '
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta slice S3"* ]]
}

@test "negativo: S5 antes de S4 falla" {
  mutate '### S5 — ' '### S9 — '
  mutate '### S1 — ' '### S5 — '
  run check "$M"
  [ "$status" -ne 0 ]
}

@test "negativo: human_surface true falla" {
  mutate 'human_surface: false' 'human_surface: true'
  run check "$M"
  [ "$status" -ne 0 ]
}

@test "negativo: sin el aviso de que no recorta contexto falla" {
  mutate 'No es una reducción de contexto' 'recorta contexto'
  run check "$M"
  [ "$status" -ne 0 ]
}

@test "planning: SE-527 PROPOSED apunta a la spec existente" {
  run python3 -I -c "
import json,os,sys
d=json.load(open(sys.argv[1]))
assert d['id']=='SE-527' and d['status']=='PROPOSED', d
assert os.path.exists(os.path.join(sys.argv[2], d['evidence'])), d['evidence']
" "$STATE" "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "negativo: el estado de planning con spec inexistente falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['evidence']='docs/specs/no-existe.md'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run python3 -I -c "
import json,os,sys
d=json.load(open(sys.argv[1]))
assert os.path.exists(os.path.join(sys.argv[2], d['evidence']))
" "$BATS_TEST_TMPDIR/s.json" "$REPO_ROOT"
  [ "$status" -ne 0 ]
}

@test "edge: empty spec falla" {
  : > "$M"
  run check "$M"
  [ "$status" -ne 0 ]
}

@test "edge: nonexistent spec falla" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -ne 0 ]
}

@test "edge: boundary, solo 4 de 5 slices con tier 4 falla (zero tolerancia)" {
  mutate '| Medio | **4** |
| S4' '| Medio | **3** |
| S4'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier 4 declarado en 4 de 5"* ]]
}
