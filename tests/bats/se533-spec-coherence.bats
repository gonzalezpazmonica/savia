#!/usr/bin/env bats
# SE-533 — coherencia de la spec: seis slices en serie, tiers calculados, los tres falsos verdes del
# analizador, diseño anti-fricción (observación primero), permiso cerrado por defecto, sin superficie
# humana nueva y repo público limpio.
# Aviso: las comprobaciones de texto fijan que la spec no cambie sin querer; no verifican que las cifras
# del árbol vivo sean ciertas (eso lo medirá S0). Cada comprobación se ejecuta también sobre una copia
# mutada y debe fallar.

set -o pipefail  # las tuberías de check() fallan si falla cualquier etapa (fail-closed)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-533-limites-compartidos-de-delegacion.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-533.json"

# Patrón de datos privados, armado por trozos para que este fichero no contenga los literales que busca.
priv_re() {
  printf '%s' "mac""book|accen""ture|m[oó]""nica|\\.sa""via/|inten""sivo|reconci""liar|Savia""Labs|co""dex" \
    "|[A-Za-z0-9._-]+@[A-Za-z0-9-]+\\.[a-z]{2,}|/ho""me/[a-z]|gh""p_[A-Za-z0-9]{20,}|s""k-[A-Za-z0-9]{20,}"
}

check() {  # check <fichero>: devuelve 0 si la spec es coherente
  local f="$1"
  [ -s "$f" ] || { echo "spec vacía o inexistente"; return 1; }
  grep -q '^status: PROPOSED$' "$f" || { echo "status != PROPOSED"; return 1; }
  grep -q '^human_surface: false$' "$f" || { echo "human_surface"; return 1; }
  grep -q '^# SE-533 — ' "$f" || { echo "título"; return 1; }
  # Seis slices S0..S5 en este orden y ninguno más.
  [ "$(grep -E '^### S[0-9] — ' "$f" | cut -c1-6 | paste -sd,)" = "### S0,### S1,### S2,### S3,### S4,### S5" ] \
    || { echo "orden o número de slices"; return 1; }
  # Tiers calculados (última columna de la tabla de slices): S0=2, S1=2, S2=4, S3=3, S4=3, S5=2.
  local pair s t
  for pair in S0:2 S1:2 S2:4 S3:3 S4:3 S5:2; do
    s=${pair%%:*}; t=${pair##*:}
    grep -qE "^\| $s \|.*\| \*\*$t\*\* \|\$" "$f" || { echo "tier calculado $s != $t"; return 1; }
  done
  # Los tres falsos verdes y el control de contraste del analizador.
  grep -q '| `a→b`, `b→a` | rc 0, PASS | FAIL (ciclo) |' "$f" || { echo "falta el falso verde del ciclo"; return 1; }
  grep -q '| `a→a` | rc 0, PASS | FAIL (autobucle) |' "$f" || { echo "falta el falso verde del autobucle"; return 1; }
  grep -q 'más `a→d` | rc 0, PASS' "$f" || { echo "falta el falso verde del atajo"; return 1; }
  grep -q 'control de contraste' "$f" || { echo "falta el control de contraste"; return 1; }
  # El test actual del analizador no puede fallar y no corre en CI: debe quedar dicho.
  grep -q 'tiene un único test con `skip`' "$f" || { echo "falta el test con skip"; return 1; }
  # Diseño anti-fricción: observación primero y prueba de que el límite no molesta.
  grep -q 'mode: observe | enforce' "$f" || { echo "falta el modo observación"; return 1; }
  grep -q 'Modo observación primero' "$f" || { echo "falta observación primero"; return 1; }
  grep -q 'lo son en el analizador estático' "$f" || { echo "falta qué es duro desde el inicio"; return 1; }
  grep -q 'ventana de 7 días' "$f" || { echo "falta la ventana de 7 días"; return 1; }
  grep -q 'No se ha medido el uso real' "$f" || { echo "falta honestidad sobre el uso medido"; return 1; }
  # Permiso: cerrado por defecto, sin comodín, sin escalada y sin conceder autoridad de efectos.
  grep -q 'cerrado por defecto' "$f" || { echo "falta cerrado por defecto"; return 1; }
  grep -q 'Un comodín (`\*`) es error del validador' "$f" || { echo "falta la prohibición del comodín"; return 1; }
  grep -q '\*\*Sin escalada:\*\*' "$f" || { echo "falta sin escalada"; return 1; }
  grep -q 'No concede autoridad de efectos' "$f" || { echo "falta aviso de autoridad de efectos"; return 1; }
  # Fallos seguidos y repetición.
  grep -q 'N=3' "$f" || { echo "falta N=3"; return 1; }
  grep -q 'Esperar por cuota \*\*no\*\* consume intento' "$f" || { echo "falta cuota no cuenta"; return 1; }
  grep -q 'Límite honesto' "$f" || { echo "falta límite honesto de la repetición"; return 1; }
  # Fail-closed y entrada por stdin.
  grep -q '\*\*Fail-closed.\*\*' "$f" || { echo "falta fail-closed"; return 1; }
  grep -q 'Entrada por stdin' "$f" || { echo "falta entrada por stdin"; return 1; }
  # Criterios de aceptación AC-1 a AC-14.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    grep -qE "^\| AC-$i \|" "$f" || { echo "falta AC-$i"; return 1; }
  done
  # Puerta de comprensión y fuera de alcance.
  grep -q '^## Puerta de comprensión$' "$f" || { echo "falta puerta de comprensión"; return 1; }
  grep -q 'Probablemente sin interfaz humana nueva' "$f" || { echo "falta la declaración de sin interfaz"; return 1; }
  grep -q '^## Fuera de alcance$' "$f" || { echo "falta fuera de alcance"; return 1; }
  grep -q '^## Relación con otras specs: no se duplica$' "$f" || { echo "falta la sección de no duplicación"; return 1; }
  local sp
  for sp in SE-496 SE-498 SE-531 SE-532 SPEC-121 SE-332; do
    # Fila de la sección «no se duplica» cuya segunda columna («La responde») empieza por la spec.
    sed -n '/^## Relación con otras specs: no se duplica$/,/^## Qué decide esta spec$/p' "$f" \
      | grep -qE "^\|[^|]*\| $sp([ ,]|\$)" || { echo "no se relaciona con $sp"; return 1; }
  done
  # Reversión por slice y plan de OpenCode.
  [ "$(grep -c '^- \*\*Reversión\.\*\*' "$f")" -ge 6 ] || { echo "falta reversión en algún slice"; return 1; }
  grep -q '^## OpenCode Implementation Plan$' "$f" || { echo "falta plan OpenCode"; return 1; }
  # Aprobación: sigue PROPOSED, sin confirmación inventada.
  grep -q 'No está aprobada' "$f" || { echo "falta aviso de no aprobada"; return 1; }
  ! grep -q '^### Confirmación$' "$f" || { echo "confirmación inventada en una spec PROPOSED"; return 1; }
  # Repo público: nada privado ni de sesión.
  local priv; priv=$(priv_re)
  ! grep -inE "$priv" "$f" || { echo "dato privado en la spec"; return 1; }
}

check_planning() {  # check_planning <json>: 0 si es SE-533 PROPOSED, seis slices y evidencia existente
  python3 -I -c "
import json,os,sys
d=json.load(open(sys.argv[1]))
assert d['id']=='SE-533' and d['status']=='PROPOSED', d
assert 'S0' in d['note'] and 'S5' in d['note'] and 'observación' in d['note'], d['note']
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

neg() {  # neg <mensaje esperado>: la spec mutada falla por ese motivo y no por otro
  run check "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$1"* ]]
}

@test "real: la spec es coherente" {
  run check "$SPEC"
  [ "$status" -eq 0 ]
}

@test "negativo: faltar S0 falla por el orden de slices" {
  mutate '### S0 — Medir antes de limitar' '### S9 — Medir antes de limitar'
  neg "orden o número de slices"
}

@test "negativo: S1 y S2 intercambiados fallan por el orden" {
  python3 -I - "$M" <<'PY2'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
s=s.replace("### S1 — ","### SX — ",1).replace("### S2 — ","### S1 — ",1).replace("### SX — ","### S2 — ",1)
open(p,"w",encoding="utf-8").write(s)
PY2
  neg "orden o número de slices"
}

@test "negativo: un séptimo slice falla" {
  printf '\n### S6 — Extra\n' >> "$M"
  neg "orden o número de slices"
}

@test "negativo: S2 declarado tier 3 (el pedido, no el calculado) falla" {
  mutate '| S2 | Allowlist en los seis delegadores y `delegation-entrypoints.yaml`; las excepciones se vacían | 3 | **4** |' \
         '| S2 | Allowlist en los seis delegadores y `delegation-entrypoints.yaml`; las excepciones se vacían | 3 | **3** |'
  neg "tier calculado S2 != 4"
}

@test "negativo: S4 con tier calculado 2 falla" {
  mutate '| S4 | Paso a `enforce` límite a límite, con los valores de S0 | 3 | **3** |' \
         '| S4 | Paso a `enforce` límite a límite, con los valores de S0 | 3 | **2** |'
  neg "tier calculado S4 != 3"
}

@test "negativo: sin el falso verde del ciclo falla" {
  mutate 'rc 0, PASS | FAIL (ciclo)' 'rc 1, FAIL | FAIL (ciclo)'
  neg "falso verde del ciclo"
}

@test "negativo: sin el falso verde del atajo falla" {
  mutate 'más `a→d` | rc 0, PASS' 'más `a→d` | rc 1, FAIL'
  neg "falso verde del atajo"
}

@test "negativo: sin el control de contraste falla" {
  mutate 'control de contraste' 'comprobación'
  neg "control de contraste"
}

@test "negativo: sin el aviso del test con skip falla" {
  mutate 'tiene un único test con `skip`' 'tiene tests'
  neg "test con skip"
}

@test "negativo: sin el modo observación falla" {
  mutate 'mode: observe | enforce' 'mode: enforce'
  neg "modo observación"
}

@test "negativo: sin ninguna ventana de 7 días falla" {
  python3 -I - "$M" <<'PY4'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
assert s.count("ventana de 7 días")>1
open(p,"w",encoding="utf-8").write(s.replace("ventana de 7 días","ventana de un día"))
PY4
  neg "ventana de 7 días"
}

@test "negativo: sin la honestidad de que no se midió el uso real falla" {
  mutate 'No se ha medido el uso real' 'Se ha medido el uso real'
  neg "honestidad sobre el uso medido"
}

@test "negativo: permitir comodín falla" {
  mutate 'Un comodín (`*`) es error del validador' 'Un comodín (`*`) se acepta'
  neg "prohibición del comodín"
}

@test "negativo: sin el aviso de no conceder autoridad falla" {
  mutate 'No concede autoridad de efectos' 'Concede autoridad de efectos'
  neg "aviso de autoridad de efectos"
}

@test "negativo: que la cuota cuente como fallo del compañero falla" {
  mutate 'Esperar por cuota **no** consume intento' 'Esperar por cuota consume intento'
  neg "cuota no cuenta"
}

@test "negativo: sin fail-closed falla" {
  mutate '**Fail-closed.**' '**Fail-open.**'
  neg "fail-closed"
}

@test "negativo: falta un criterio de aceptación" {
  mutate '| AC-9 |' '| AC-X |'
  neg "falta AC-9"
}

@test "negativo: sin la declaración de sin interfaz humana falla" {
  mutate 'Probablemente sin interfaz humana nueva' 'Con interfaz humana nueva'
  neg "declaración de sin interfaz"
}

@test "negativo: human_surface true falla" {
  mutate 'human_surface: false' 'human_surface: true'
  neg "human_surface"
}

@test "negativo: status APPROVED falla en una spec PROPOSED" {
  mutate 'status: PROPOSED' 'status: APPROVED'
  neg "status != PROPOSED"
}

@test "negativo: una confirmación inventada falla" {
  printf '\n### Confirmación\n\n- fecha: 2026-11-14\n' >> "$M"
  neg "confirmación inventada"
}

@test "negativo: sin relacionarse con SE-496 falla" {
  python3 -I - "$M" <<'PY3'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read().replace("SE-496","SE-000")
open(p,"w",encoding="utf-8").write(s)
PY3
  neg "no se relaciona con SE-496"
}

@test "negativo: borrar solo la fila de relación con SE-531 falla aunque la spec la mencione en otros sitios" {
  python3 -I - "$M" <<'PY4'
import sys
p=sys.argv[1]; L=open(p,encoding="utf-8").read().split("\n")
out=[l for l in L if not (l.startswith("| ¿Cómo se corta un proceso hijo") )]
assert len(out)==len(L)-1
open(p,"w",encoding="utf-8").write("\n".join(out))
PY4
  grep -q 'SE-531' "$M"
  neg "no se relaciona con SE-531"
}

@test "negativo: borrar solo la fila de relación con SE-532 falla" {
  python3 -I - "$M" <<'PY5'
import sys
p=sys.argv[1]; L=open(p,encoding="utf-8").read().split("\n")
out=[l for l in L if not l.startswith("| ¿Cómo se valida la cabecera de cada agente?")]
assert len(out)==len(L)-1
open(p,"w",encoding="utf-8").write("\n".join(out))
PY5
  grep -q 'SE-532' "$M"
  neg "no se relaciona con SE-532"
}

@test "negativo: S3 declarado tier 2 falla (el calculado es 3)" {
  mutate '| S3 | Mediador en modo observación: reserva, repetición, fallos seguidos y recibo | 2 | **3** |' '| S3 | Mediador en modo observación: reserva, repetición, fallos seguidos y recibo | 2 | **2** |'
  neg "tier calculado S3 != 3"
}

@test "negativo: D de ejecución declarado duro desde el primer día falla" {
  mutate 'Solo D y el ciclo son estructurales, y lo son en el analizador estático' 'Solo D y el ciclo son estructurales'
  neg "falta qué es duro desde el inicio"
}

@test "negativo: un slice sin reversión falla" {
  mutate '- **Reversión.** `git revert`; el script vuelve a su versión anterior.' '- Nada.'
  neg "falta reversión"
}

@test "edge: boundary de slices, con cinco en vez de seis falla" {
  python3 -I - "$M" <<'PY5'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
assert "### S5 — " in s
open(p,"w",encoding="utf-8").write(s.replace("### S5 — ","### Sección — ",1))
PY5
  neg "orden o número de slices"
}

@test "edge: zero reversiones (ninguna) falla" {
  python3 -I - "$M" <<'PY6'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
open(p,"w",encoding="utf-8").write(s.replace("- **Reversión.**","- **Vuelta atrás.**"))
PY6
  neg "falta reversión"
}

@test "negativo: una referencia a un dato privado falla" {
  printf '\nVer %s\n' "$(printf '%s/%s' 'inten''sivo' 'x')" >> "$M"
  neg "dato privado"
}

@test "negativo: una ruta de usuario en la spec falla" {
  printf '\nSe lee %s\n' "$(printf '/ho''me/%s' 'alguien/x')" >> "$M"
  neg "dato privado"
}

@test "negativo: nombrar al proveedor de la revisión independiente falla" {
  printf '\nRevisó %s\n' "$(printf 'Co''dex')" >> "$M"
  neg "dato privado"
}

@test "planning: SE-533 PROPOSED apunta a la spec existente" {
  run check_planning "$STATE"
  [ "$status" -eq 0 ]
}

@test "negativo: el estado de planning con otro status falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['status']='APPROVED'
json.dump(d,open(sys.argv[2],'w'))
" "$STATE" "$BATS_TEST_TMPDIR/p.json"
  run check_planning "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -ne 0 ]
}

@test "negativo: el estado de planning con spec inexistente falla" {
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); d['evidence']='docs/specs/no-existe.spec.md'
json.dump(d,open(sys.argv[2],'w'))
" "$STATE" "$BATS_TEST_TMPDIR/p.json"
  run check_planning "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -ne 0 ]
}

@test "edge: empty spec (vacía) falla" {
  : > "$M"
  neg "spec vacía"
}

@test "edge: nonexistent spec (inexistente) falla" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -ne 0 ]
}

# priv_scan <fichero>: devuelve 1 si el fichero contiene un dato privado (fail-closed: fichero vacío o ausente también falla).
priv_scan() {
  [ -s "$1" ] || { echo "falta o vacío: $1"; return 1; }
  if grep -inE "$(priv_re)" "$1"; then echo "dato privado en $1"; return 1; fi
  return 0
}

@test "repo público: changelog, LOG y planning no contienen datos privados" {
  # Un `! grep` dentro de un bucle no aborta bajo errexit; por eso se usa priv_scan con return explícito.
  local f
  for f in "$REPO_ROOT/CHANGELOG.d/se533-limites-delegacion.md" \
           "$REPO_ROOT/docs/propuestas/LOG.d/SE-533-PROPOSED.md" "$STATE"; do
    priv_scan "$f"
  done
}

@test "negativo: un dato privado en el primer fichero del bucle hace fallar priv_scan" {
  local f="$BATS_TEST_TMPDIR/cl.md"
  cp "$REPO_ROOT/CHANGELOG.d/se533-limites-delegacion.md" "$f"
  printf 'contacto %s\n' "$(printf 'x@y''.es')" >> "$f"
  run priv_scan "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dato privado"* ]]
}

@test "negativo: una ruta de usuario o un literal privado en el LOG falla; el fichero vacío también" {
  local f="$BATS_TEST_TMPDIR/log.md"
  cp "$REPO_ROOT/docs/propuestas/LOG.d/SE-533-PROPOSED.md" "$f"
  printf '%s/u/x\n' "$(printf '/ho''me')" >> "$f"
  run priv_scan "$f"
  [ "$status" -ne 0 ]
  : > "$f"
  run priv_scan "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falta o vacío"* ]]
}

@test "sanity: el patrón privado detecta un literal, un correo y una ruta de usuario" {
  local priv; priv=$(priv_re)
  printf 'x %s y\n' "$(printf 'Savia''Labs')" | grep -qiE "$priv"
  printf 'a@b.es\n' | grep -qiE "$priv"
  printf '%s\n' "$(printf '/ho''me/u')" | grep -qiE "$priv"
  run bash -c "printf 'texto normal sin nada\n' | grep -qiE '$priv'"
  [ "$status" -ne 0 ]
}

# resolve_ref <fichero[:línea]>: ruta absoluta del fichero citado (con directorio o solo nombre; nombre ambiguo = fallo).
resolve_ref() {
  local file="$1" hits
  case "$file" in *..*|/*) echo "ruta no admitida: $file"; return 1;; esac
  if [[ "$file" == */* || -f "$REPO_ROOT/$file" ]]; then echo "$REPO_ROOT/$file"; return 0; fi
  hits=$(git -C "$REPO_ROOT" ls-files | grep -E "(^|/)$file\$" || true)
  [ "$(printf '%s\n' "$hits" | grep -c .)" -eq 1 ] || { echo "nombre ausente o ambiguo: $file"; return 1; }
  echo "$REPO_ROOT/$hits"
}

@test "las referencias fichero:línea citadas siguen existiendo en main" {
  # Anti-deriva: cada fichero citado con línea existe y tiene al menos esa línea. No prueba su contenido.
  # Cubre citas con directorio y citas solo con nombre; las citas «:NN» sueltas se acotan abajo.
  local ref file line path n=0 refs
  refs=$(grep -oE '[A-Za-z0-9_./-]+\.(sh|md|json|py|yaml|bats):[0-9]+' "$SPEC" | sort -u)
  while read -r ref; do
    file=${ref%%:*}; line=${ref##*:}
    path=$(resolve_ref "$file") || { echo "$path"; return 1; }
    [ -f "$path" ] || { echo "no existe $file"; return 1; }
    [ "$(grep -c '' "$path")" -ge "$line" ] || { echo "$file sin línea $line"; return 1; }
    n=$((n + 1))
  done <<< "$refs"
  [ "$n" -ge 8 ] || { echo "solo $n referencias comprobadas: la extracción no funciona"; return 1; }
  # Citas «:NN» sueltas: las mayores de cada fichero citado en el texto.
  [ "$(grep -c '' "$REPO_ROOT/scripts/agent-depth-limit.sh")" -ge 120 ]
  [ "$(grep -c '' "$REPO_ROOT/.claude/hooks/delegation-guard.sh")" -ge 35 ]
}

# ref_ok <fichero> <línea>: 0 si el fichero citado existe y tiene al menos esa línea.
ref_ok() {
  local path; path=$(resolve_ref "$1") || return 1
  [ -f "$path" ] && [ "$(grep -c '' "$path")" -ge "$2" ]
}

@test "negativo: una referencia a una línea inexistente o a un nombre ausente falla" {
  run resolve_ref "no-existe-jamas.sh"
  [ "$status" -ne 0 ]
  run resolve_ref "../../etc/passwd"
  [ "$status" -ne 0 ]
  run ref_ok "delegation-guard.sh" 35
  [ "$status" -eq 0 ]
  run ref_ok "delegation-guard.sh" 99999
  [ "$status" -ne 0 ]
}
