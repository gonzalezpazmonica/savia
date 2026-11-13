#!/usr/bin/env bats
# SE-530 — coherencia de la spec: tres slices en orden S1-S2-S3, tiers declarados,
# estados declarado/verificado/refutado, prerregistro de H9, escenas, fallo cerrado,
# sin modo sombra. Cada comprobación se ejecuta también sobre una copia mutada y debe fallar.

set -o pipefail  # las tuberías de check() fallan si falla cualquier etapa (fail-closed)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-530-hecho-verificado.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-530.json"

check() {  # check <fichero>: devuelve 0 si la spec es coherente
  local f="$1"
  grep -q '^status: APPROVED$' "$f" || { echo "status != APPROVED"; return 1; }
  grep -q '^human_surface: true$' "$f" || { echo "human_surface"; return 1; }
  for n in 1 2 3; do
    grep -q "^### S$n — " "$f" || { echo "falta slice S$n"; return 1; }
  done
  ! grep -qE '^### S[4-9] — ' "$f" || { echo "slice de más"; return 1; }
  local order
  order=$(grep -E '^### S[0-9] — ' "$f" | cut -c1-6 | paste -sd,)
  [ "$order" = "### S1,### S2,### S3" ] || { echo "orden de slices: $order"; return 1; }
  # Tiers: S1 1-2, S2 2, S3 3 en la tabla de slices.
  grep -qE '^\| S1 \|.*\| \*\*1-2\*\* \|' "$f" || { echo "tier S1"; return 1; }
  grep -qE '^\| S2 \|.*\| \*\*2\*\* \|' "$f" || { echo "tier S2"; return 1; }
  grep -qE '^\| S3 \|.*\| \*\*3\*\* \|' "$f" || { echo "tier S3"; return 1; }
  # Tres estados con precedencia.
  for s in declarado verificado refutado; do
    grep -qE "^\| \`$s\` \|" "$f" || { echo "falta estado $s"; return 1; }
  done
  grep -q 'Precedencia: `refutado` > `verificado` > `declarado`' "$f" || { echo "falta precedencia"; return 1; }
  # Hipótesis prerregistrada con su umbral y su n mínimo.
  grep -q 'H9' "$f" || { echo "falta H9"; return 1; }
  grep -q 'al menos el 10 %' "$f" || { echo "falta umbral 10 %"; return 1; }
  grep -q 'n ≥ 200' "$f" || { echo "falta n >= 200"; return 1; }
  grep -q 'El umbral del 10 % no se rebaja' "$f" || { echo "falta cláusula de no rebajar umbral"; return 1; }
  # Aplicar desde ya: sin sombra.
  grep -q 'Aplicar desde ya' "$f" || { echo "falta decisión aplicar desde ya"; return 1; }
  grep -q 'no hay modo «sombra»' "$f" || { echo "falta AC sin sombra"; return 1; }
  # Fallo cerrado y comprobación propuesta por el ejecutor.
  grep -q 'nunca «verificado»' "$f" || { echo "falta fallo cerrado"; return 1; }
  grep -q 'No cuenta hasta que la aprueba la persona' "$f" || { echo "falta regla de comprobación propia"; return 1; }
  # S3 depende de SE-518 y SE-518 no está en main.
  grep -q 'SE-518' "$f" || { echo "falta SE-518"; return 1; }
  grep -q 'no en `main`' "$f" || { echo "falta aviso SE-518 fuera de main"; return 1; }
  # Puerta de comprensión: escenas, confirmación pendiente.
  grep -q '^## Lo que he entendido$' "$f" || { echo "falta Lo que he entendido"; return 1; }
  grep -q '^### Escenas$' "$f" || { echo "falta Escenas"; return 1; }
  local escenas
  # Solo cuenta la sección «Escenas» (hasta el siguiente encabezado), no otras listas numeradas.
  escenas=$(awk '/^### Escenas$/{s=1;next} /^##/{s=0} s && /^[1-6]\. \*\*/{n++} END{print n+0}' "$f")
  [ "$escenas" -ge 3 ] && [ "$escenas" -le 5 ] || { echo "escenas: $escenas"; return 1; }
  grep -q '^### Confirmación$' "$f" || { echo "falta Confirmación"; return 1; }
  # Confirmación de las escenas: fecha real y respuesta literal entre «…», no vacía ni «pendiente».
  local conf
  conf=$(awk '/^### Confirmación$/{s=1;next} /^##/{s=0} s' "$f")
  printf '%s\n' "$conf" | grep -qE '^- fecha: 2026-11-1[3-9]$' || { echo "confirmación sin fecha"; return 1; }
  printf '%s\n' "$conf" | grep -qE '^- respuesta: «[^»[:space:]][^»]*»' || { echo "confirmación sin respuesta literal"; return 1; }
  grep -q '^## Slice S0 — Prototipo navegable$' "$f" || { echo "falta S0"; return 1; }
  grep -qE '^- prototipo: [^[:space:]]' "$f" || { echo "falta prototipo"; return 1; }
  # Decisiones 1-5 registradas y preguntas abiertas cerradas.
  grep -q 'Confirmadas el 2026-11-13 por pregunta interactiva' "$f" || { echo "faltan decisiones confirmadas"; return 1; }
  grep -q 'No se puede comprobar: el justificante no dice quién lo hizo' "$f" || { echo "falta aviso de falta de información"; return 1; }
  ! grep -q 'Pendiente de la operadora' "$f" || { echo "aprobación aún pendiente"; return 1; }
  grep -q '^## OpenCode Implementation Plan$' "$f" || { echo "falta plan OpenCode"; return 1; }
  # Repo público: nada de rutas ni nombres privados.
  # Patrones partidos para que este propio fichero no contenga los literales que busca.
  local pat='mac''book|accen''ture|\.sav''ia/|intens''ivo|reconci''liar|des''til|Savia''Labs'
  ! grep -iqE "$pat" "$f" || { echo "dato privado"; return 1; }
}

check_planning() {  # check_planning <json>: 0 si es SE-530 APPROVED con evidencia existente
  python3 -I -c "
import json,os,sys
d=json.load(open(sys.argv[1]))
assert d['id']=='SE-530' and d['status']=='APPROVED', d
assert 'Hecho verificado' in d['title'], d['title']
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

@test "negativo: status PROPOSED falla" {
  mutate 'status: APPROVED' 'status: PROPOSED'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != APPROVED"* ]]
}

@test "negativo: S3 con tier 2 en lugar de 3 falla" {
  mutate '| S3 | Evento `job_verified` en Pulse | **3** |' '| S3 | Evento `job_verified` en Pulse | **2** |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier S3"* ]]
}

@test "negativo: S1 con tier 3 falla" {
  mutate '| **1-2** |' '| **3** |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tier S1"* ]]
}

@test "negativo: faltar S2 falla" {
  mutate '### S2 — ' '### Sx — '
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta slice S2"* ]]
}

@test "negativo: S3 antes de S2 falla" {
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
  [[ "$output" == *"orden de slices"* ]]
}

@test "negativo: un slice S4 de más falla" {
  printf '\n### S4 — Otra cosa\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"slice de más"* ]]
}

@test "negativo: quitar el estado refutado falla" {
  mutate '| `refutado` |' '| `otro` |'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta estado refutado"* ]]
}

@test "negativo: precedencia invertida falla" {
  mutate 'Precedencia: `refutado` > `verificado` > `declarado`' 'Precedencia: `verificado` > `refutado` > `declarado`'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta precedencia"* ]]
}

@test "negativo: bajar el umbral de H9 falla" {
  mutate 'al menos el 10 %' 'al menos el 5 %'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta umbral 10 %"* ]]
}

@test "negativo: bajar el n mínimo de la refutación falla" {
  mutate 'n ≥ 200' 'n ≥ 20'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta n >= 200"* ]]
}

@test "negativo: quitar la cláusula de no rebajar el umbral falla" {
  mutate 'El umbral del 10 % no se rebaja' 'El umbral se ajusta'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cláusula de no rebajar umbral"* ]]
}

@test "negativo: reintroducir la fase en sombra falla" {
  mutate 'no hay modo «sombra»' 'hay un modo sombra de una semana'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta AC sin sombra"* ]]
}

@test "negativo: perder el fallo cerrado falla" {
  python3 -I - "$M" <<'PY3'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
s=s.replace('nunca «verificado»','a veces «verificado»')
open(p,"w",encoding="utf-8").write(s)
PY3
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta fallo cerrado"* ]]
}

@test "negativo: la comprobación propia del ejecutor pasa a contar sin la persona" {
  mutate 'No cuenta hasta que la aprueba la persona' 'Cuenta siempre'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"regla de comprobación propia"* ]]
}

@test "negativo: afirmar que SE-518 ya está en main falla" {
  mutate 'no en `main`' 'ya fusionada'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-518 fuera de main"* ]]
}

@test "negativo: quitar las escenas falla" {
  mutate '### Escenas' '### Otra cosa'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta Escenas"* ]]
}

@test "negativo: borrar las seis escenas conservando el encabezado falla" {
  python3 -I - "$M" <<'PY3'
import re,sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
n=re.sub(r'(?ms)(^### Escenas\n).*?(?=^### )',r'\1\n',s,count=1)
assert n!=s
open(p,"w",encoding="utf-8").write(n)
PY3
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"escenas: 0"* ]]
}

@test "las citas fichero:línea de la spec existen en el repo" {
  run python3 -I - "$SPEC" "$REPO_ROOT" <<'PY4'
import re,sys,os
spec,root=sys.argv[1:3]
cites=re.findall(r'`(scripts/[\w./-]+\.sh):(\d+)(?:-(\d+))?`',open(spec,encoding="utf-8").read())
assert cites, "sin citas"
for f,a,b in cites:
    p=os.path.join(root,f)
    assert os.path.exists(p), f
    n=sum(1 for _ in open(p,encoding="utf-8"))
    assert int(b or a)<=n, (f,a,b,n)
    assert int(a)<=int(b or a), (f,a,b)
PY4
  [ "$status" -eq 0 ]
}

@test "negativo: una cita a una línea inexistente falla" {
  mutate 'scripts/merge-sprint.sh:89' 'scripts/merge-sprint.sh:99999'
  run python3 -I - "$M" "$REPO_ROOT" <<'PY5'
import re,sys,os
spec,root=sys.argv[1:3]
for f,a,b in re.findall(r'`(scripts/[\w./-]+\.sh):(\d+)(?:-(\d+))?`',open(spec,encoding="utf-8").read()):
    n=sum(1 for _ in open(os.path.join(root,f),encoding="utf-8"))
    if int(b or a)>n: sys.exit("fuera de rango")
PY5
  [ "$status" -ne 0 ]
}

@test "negativo: confirmación pendiente sin fecha falla" {
  python3 -I - "$M" <<'PY2'
import sys,re
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
n=s.count("- fecha: 2026-11-13\n- respuesta: «Confirmo")
if n!=1: sys.exit("mutación sin efecto")
open(p,"w",encoding="utf-8").write(s.replace("- fecha: 2026-11-13\n- respuesta: «Confirmo","- fecha: pendiente\n- respuesta: «Confirmo"))
PY2
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"confirmación sin fecha"* ]]
}

@test "negativo: confirmación con respuesta vacía falla" {
  mutate '- respuesta: «Confirmo todo como está»' '- respuesta: «»'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"confirmación sin respuesta literal"* ]]
}

@test "negativo: sin slice S0 falla" {
  mutate '## Slice S0 — Prototipo navegable' '## Slice cero'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta S0"* ]]
}

@test "negativo: más de cinco escenas falla (máximo de la puerta)" {
  python3 -I - "$M" <<'PY3'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
a="5. **El resumen de la mañana y la información que falta.**"
if a not in s: sys.exit("mutación sin efecto")
open(p,"w",encoding="utf-8").write(s.replace(a,"5. **Otra.**\n\n6. **El resumen de la mañana y la información que falta.**"))
PY3
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"escenas: 6"* ]]
}

@test "negativo: human_surface false falla (cambia lo que la persona ve)" {
  mutate 'human_surface: true' 'human_surface: false'
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"human_surface"* ]]
}

@test "negativo: un dato privado en la spec falla" {
  printf '\nVer ~/.sav''ia/algo\n' >> "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dato privado"* ]]
}

@test "edge: spec vacía falla" {
  : > "$M"
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != APPROVED"* ]]
}

@test "edge: spec inexistente falla" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status != APPROVED"* ]]
}

@test "planning: SE-530 APPROVED apunta a la spec existente" {
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

@test "negativo: planning PROPOSED falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['status']='PROPOSED'
json.dump(d,open(sys.argv[2],'w'))" "$STATE" "$BATS_TEST_TMPDIR/s.json"
  run check_planning "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
}
