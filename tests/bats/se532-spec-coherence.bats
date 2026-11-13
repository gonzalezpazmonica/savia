#!/usr/bin/env bats
# SE-532 — coherencia de la spec: tres slices en orden (S1 antes de SE-527, S2 después, S3 al final),
# tiers calculados, cifras del catálogo, relación con SE-253 sin duplicar y repo público limpio.
# Aviso: las comprobaciones de texto (cifras, tiers, frases) fijan que la spec no cambie sin querer;
# no verifican que las cifras del catálogo sean ciertas (eso lo medirá el validador de S1).
# Cada comprobación se ejecuta también sobre una copia mutada y debe fallar.

set -o pipefail  # las tuberías de check() fallan si falla cualquier etapa (fail-closed)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-532-catalogo-de-agentes-con-esquema-y-retirada.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-532.json"

# Patrón de datos privados: palabras del entorno de la operadora más formas genéricas (correo,
# ruta de usuario, tokens). Armado por trozos para que este fichero no se dispare a sí mismo.
priv_re() {
  printf '%s' "mac""book|accen""ture|m[oó]""nica|\\.sa""via/|inten""sivo|reconci""liar|des""til|Savia""Labs" \
    "|[A-Za-z0-9._-]+@[A-Za-z0-9-]+\\.[a-z]{2,}|/ho""me/[a-z]|gh""p_[A-Za-z0-9]{20,}|s""k-[A-Za-z0-9]{20,}"
}

check() {  # check <fichero>: devuelve 0 si la spec es coherente
  local f="$1"
  [ -s "$f" ] || { echo "spec vacía o inexistente"; return 1; }
  grep -q '^status: PROPOSED$' "$f" || { echo "status != PROPOSED"; return 1; }
  grep -q '^human_surface: false$' "$f" || { echo "human_surface"; return 1; }
  grep -q '^# SE-532 — ' "$f" || { echo "título"; return 1; }
  for n in 1 2 3; do
    grep -q "^### S$n — " "$f" || { echo "falta slice S$n"; return 1; }
  done
  ! grep -q '^### S4 — ' "$f" || { echo "slice de más"; return 1; }
  local last
  last=$(grep -E '^### S[0-9] — ' "$f" | tail -1 | cut -c1-6)
  [ "$last" = "### S3" ] || { echo "S3 no es el último"; return 1; }
  # Orden de los encabezados: S1, S2, S3.
  [ "$(grep -E '^### S[0-9] — ' "$f" | cut -c1-6 | paste -sd,)" = "### S1,### S2,### S3" ] \
    || { echo "orden de slices"; return 1; }
  # Tiers calculados (última columna de la tabla D1): S1=2, S2=4, S3=2.
  grep -qE '^\| S1 \|.*\| \*\*2\*\* \|$' "$f" || { echo "tier calculado S1 != 2"; return 1; }
  grep -qE '^\| S2 \|.*\| \*\*4\*\* \|$' "$f" || { echo "tier calculado S2 != 4"; return 1; }
  grep -qE '^\| S3 \|.*\| \*\*2\*\* \|$' "$f" || { echo "tier calculado S3 != 2"; return 1; }
  # Orden respecto a SE-527 y a SE-518.
  grep -qE '^\| S1 \|.*\*\*Antes de SE-527\*\*' "$f" || { echo "S1 no va antes de SE-527"; return 1; }
  grep -qE '^\| S2 \|.*Después de SE-527 \|' "$f" || { echo "S2 no va después de SE-527"; return 1; }
  grep -qE '^\| S3 \|.*Después de que SE-518 esté fusionada' "$f" || { echo "S3 no espera a SE-518"; return 1; }
  # El tier 2 de S1 es una coincidencia medida (.json contiene .js): debe quedar dicho.
  grep -q 'por una coincidencia' "$f" || { echo "falta el matiz del tier de S1"; return 1; }
  # Cifras verificadas en el catálogo.
  grep -q '19 claves de cabecera distintas' "$f" || { echo "falta 19 claves"; return 1; }
  grep -q '\*\*90 agentes\*\*' "$f" || { echo "falta 90 agentes"; return 1; }
  grep -q '\*\*18 líneas\*\*' "$f" || { echo "falta 18 excepciones"; return 1; }
  # Reglas R1 a R10 y criterios AC-1 a AC-11 presentes.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    grep -qE "^\| R$i \|" "$f" || { echo "falta regla R$i"; return 1; }
  done
  for i in 1 2 3 4 5 6 7 8 9 10 11; do
    grep -qE "^\| AC-$i \|" "$f" || { echo "falta AC-$i"; return 1; }
  done
  # SE-253: se cita, se invoca y no se duplica.
  grep -q '^## Relación con SE-253 (espejos de agentes): no se duplica$' "$f" || { echo "falta sección SE-253"; return 1; }
  grep -q 'Esta spec \*\*no vuelve a calcular ese emparejamiento ni toca la allowlist\*\*' "$f" || { echo "SE-253 duplicado"; return 1; }
  # Honestidad sobre los límites.
  grep -q 'No cambia ningún permiso' "$f" || { echo "falta aviso de permisos"; return 1; }
  grep -q 'Hoy no hay referencias colgantes' "$f" || { echo "falta medición de colgantes"; return 1; }
  grep -q '^## Puerta de comprensión$' "$f" || { echo "falta puerta de comprensión"; return 1; }
  grep -q '^## OpenCode Implementation Plan$' "$f" || { echo "falta plan OpenCode"; return 1; }
  # Repo público: nada privado ni de sesión.
  # El patrón se arma por trozos para que este fichero no contenga los literales que busca.
  local priv; priv=$(priv_re)
  ! grep -inE "$priv" "$f" || { echo "dato privado en la spec"; return 1; }
}

check_planning() {  # check_planning <json>: 0 si es SE-532 PROPOSED, 3 slices y evidencia existente
  python3 -I -c "
import json,os,sys
d=json.load(open(sys.argv[1]))
assert d['id']=='SE-532' and d['status']=='PROPOSED', d
assert 'SE-253' in d['note'] and 'S1' in d['note'] and 'S3' in d['note'], d['note']
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

@test "negativo: faltar S3 falla" {
  mutate '### S3 — Deriva en Pulse' '### S9 — Deriva en Pulse'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta slice S3"* ]]
}

@test "negativo: S1 y S2 intercambiados fallan por el orden, no por otra causa" {
  python3 -I - "$M" <<'PY2'
import sys,re
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
s=s.replace("### S1 — ","### SX — ",1).replace("### S2 — ","### S1 — ",1).replace("### SX — ","### S2 — ",1)
open(p,"w",encoding="utf-8").write(s)
PY2
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"orden de slices"* ]]
}

@test "negativo: un cuarto slice falla" {
  mutate '### S3 — Deriva en Pulse' '### S4 — Deriva en Pulse'
  printf '\n### S3 — Extra\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"slice de más"* ]]
}

@test "negativo: S2 declarado tier 3 (el pedido, no el calculado) falla" {
  mutate '| Después de SE-527 | 3 | **4** |' '| Después de SE-527 | 3 | **3** |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier calculado S2 != 4"* ]]
}

@test "negativo: S1 con tier calculado 3 falla" {
  mutate '| 2 | **2** |
| S2 |' '| 2 | **3** |
| S2 |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier calculado S1 != 2"* ]]
}

@test "negativo: S1 que no va antes de SE-527 falla" {
  mutate '**Antes de SE-527**' 'Después de SE-527'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"S1 no va antes de SE-527"* ]]
}

@test "negativo: S3 sin esperar a SE-518 falla" {
  mutate 'Después de que SE-518 esté fusionada' 'Cuando se pueda'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"S3 no espera a SE-518"* ]]
}

@test "negativo: falta la regla R7 de protegidos" {
  mutate '| R7 |' '| X7 |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta regla R7"* ]]
}

@test "negativo: falta un criterio de aceptación" {
  mutate '| AC-9 |' '| AC-x |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta AC-9"* ]]
}

@test "negativo: cifra de excepciones distinta de 18 falla" {
  mutate '**18 líneas**' '**20 líneas**'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta 18 excepciones"* ]]
}

@test "negativo: cifra de claves distinta de 19 falla" {
  mutate '19 claves de cabecera distintas' '21 claves de cabecera distintas'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta 19 claves"* ]]
}

@test "negativo: sin la sección que separa SE-253 falla" {
  mutate '## Relación con SE-253 (espejos de agentes): no se duplica' '## Otra cosa'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta sección SE-253"* ]]
}

@test "negativo: human_surface true falla" {
  mutate 'human_surface: false' 'human_surface: true'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"human_surface"* ]]
}

@test "negativo: status APPROVED sin confirmación de la operadora falla" {
  mutate 'status: PROPOSED' 'status: APPROVED'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != PROPOSED"* ]]
}

@test "negativo: una referencia a un dato privado falla" {
  printf '\nVer ~/.sa''via/session-handoff.md\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dato privado"* ]]
}

@test "negativo: una palabra del patrón privado, aunque sea suelta, falla" {
  printf '\nSavia''Labs\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dato privado"* ]]
}

@test "planning: SE-532 PROPOSED apunta a la spec existente" {
  run check_planning "$STATE"
  [ "$status" -eq 0 ]
}

@test "negativo: el estado de planning con spec inexistente falla" {
  python3 -I - "$STATE" "$BATS_TEST_TMPDIR/p.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d['evidence']='docs/specs/no-existe.spec.md'
json.dump(d,open(sys.argv[2],'w'))
PY
  run check_planning "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -ne 0 ]
}

@test "negativo: el estado de planning con otro status falla" {
  python3 -I - "$STATE" "$BATS_TEST_TMPDIR/p.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d['status']='APPROVED'
json.dump(d,open(sys.argv[2],'w'))
PY
  run check_planning "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -ne 0 ]
}

@test "edge: spec vacía falla" {
  : > "$M"
  run check "$M"
  [ "$status" -ne 0 ]
}

@test "edge: spec inexistente falla" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -ne 0 ]
}

@test "repo público: changelog, LOG, planning y este test no contienen datos privados" {
  local priv; priv=$(priv_re)
  for f in "$REPO_ROOT/CHANGELOG.d/se532-catalogo-agentes.md" \
           "$REPO_ROOT/docs/propuestas/LOG.d/SE-532-PROPOSED.md" \
           "$STATE" "$BATS_TEST_FILENAME"; do
    [ -s "$f" ]
    run grep -inE "$priv" "$f"
    [ "$status" -eq 1 ]
  done
}

@test "sanity: el patrón privado detecta un literal, un correo y una ruta de usuario" {
  local priv; priv=$(priv_re)
  local n=0 x
  for x in '~/.sa''via/x' 'alguien@ejem''plo.org' '/ho''me/usuario/x' 'gh''p_abcdefghijklmnopqrstuvwx'; do
    printf '%s\n' "$x" > "$BATS_TEST_TMPDIR/aux.md"
    run grep -inE "$priv" "$BATS_TEST_TMPDIR/aux.md"
    [ "$status" -eq 0 ] || { echo "no detecta: $x"; return 1; }
    n=$((n+1))
  done
  [ "$n" -eq 4 ]
  # Caso límite negativo: texto normal con guiones y arrobas de código no dispara.
  printf 'risk-tier.py y el decorador @dataclass\n' > "$BATS_TEST_TMPDIR/aux.md"
  run grep -inE "$priv" "$BATS_TEST_TMPDIR/aux.md"
  [ "$status" -eq 1 ]
}

@test "negativo: una ruta de usuario en la spec falla" {
  printf '\nVer /ho''me/usuario/x\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dato privado"* ]]
}

@test "negativo: sin el matiz de la coincidencia del tier de S1 falla" {
  mutate 'por una coincidencia' 'por diseño'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"matiz del tier de S1"* ]]
}
