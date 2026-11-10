#!/usr/bin/env bats
# Prototipos S0 de SE-493 y SE-498 (revisiones de la PR #1501).
# Dos tipos de comprobación:
#  - derivadas de la spec: los códigos de salida y la gracia se leen de la spec
#    (SE-493 §2c y tabla §3d; SE-498 tabla de códigos de salida) y se cotejan
#    con el prototipo; si la spec cambia y el prototipo no, fallan.
#  - de redacción: frases que el prototipo debe (o no debe) decir a la operadora.
# Cada comprobación tiene caso negativo con un fixture que reproduce el defecto.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
P493="$REPO_ROOT/docs/specs/assets/SE-493-prototipo.md"
P498="$REPO_ROOT/docs/specs/assets/SE-498-prototipo.md"
S493="$REPO_ROOT/docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md"
S498="$REPO_ROOT/docs/specs/SE-498-global-stop-cross-executor-revocation.spec.md"

setup() { TMP="$(mktemp -d)"; }
teardown() { rm -rf "$TMP"; }

# --- Derivadas de la spec ---------------------------------------------------

# Tabla §3d de SE-493 -> líneas «RESULTADO EXIT».
spec493_exits() {
  awk -F'|' '/\*\*3d\. Exits de `reconcile`/ {on=1; next}
    on && /^ *\|/ {tbl=1}
    on && tbl && !/^ *\|/ {exit}
    on && /^ *\| `[A-Z_]+`.*\| *[0-9]+ *\| *$/ {
      if (match($3, /`[A-Z_]+`/)) {
        r = substr($3, RSTART + 1, RLENGTH - 2); e = $4; gsub(/ /, "", e); print r, e
      }
    }' "$1"
}

# Cada `RESULTADO … [salida N]` del prototipo casa con la tabla §3d; al menos 3.
check_493_exits_from_spec() {
  local proto="$1" spec="$2" map n=0 res ex want
  map="$(spec493_exits "$spec")"
  [ "$(echo "$map" | grep -c .)" -ge 5 ] || return 1
  while read -r res ex; do
    want="$(echo "$map" | awk -v r="$res" '$1==r {print $2}')"
    [ -n "$want" ] && [ "$want" = "$ex" ] || return 1
    n=$((n + 1))
  done < <(sed -nE 's/^([A-Z_]+) .*\[salida ([0-9]+)\].*/\1 \2/p' "$proto")
  [ "$n" -ge 3 ]
}

# Gracia de pr.merge (SE-493 §2c) expresada en minutos en la escena 1.
check_493_grace_from_spec() {
  local proto="$1" spec="$2" s
  s="$(grep -oE 'Para `pr\.merge`: [0-9]+ s y [0-9]+ s' "$spec" | grep -oE '[0-9]+ s$' | grep -oE '[0-9]+')"
  [ -n "$s" ] && [ $((s % 60)) -eq 0 ] || return 1
  grep -q "para un merge, $((s / 60)) minutos" "$proto"
}

# Fila «| N | significado |» de la tabla de salidas de SE-498.
spec498_row() {
  grep -E "^\| $2 \| " "$1"
}

# Cada [salida N] del prototipo SE-498 existe en la tabla de la spec y casa por
# significado: palabra del prototipo y palabra de la fila N de la spec.
check_498_exits_from_spec() {
  local proto="$1" spec="$2" line n row pk sk seen=0
  while IFS= read -r line; do
    n="$(echo "$line" | grep -oE '\[salida [0-9]+\]' | grep -oE '[0-9]+')"
    case "$n" in
      4) pk='aprobación';   sk='aprobación' ;;
      5) pk='indeterminado'; sk='INDETERMINATE' ;;
      6) pk='Parado';       sk='modo parado' ;;
      8) pk='época';        sk='STALE_EPOCH' ;;
      *) return 1 ;;
    esac
    row="$(spec498_row "$spec" "$n")"
    [ -n "$row" ] || return 1
    echo "$row" | grep -q "$sk" || return 1
    echo "$line" | grep -q "$pk" || return 1
    seen=$((seen + 1))
  done < <(grep -E '\[salida [0-9]+\]' "$proto")
  [ "$seen" -ge 4 ]
}

# --- Redacción --------------------------------------------------------------

# SE-493 2c/3d: dentro de la gracia un DISPATCHED dudoso sigue en vuelo;
# «en revisión» solo pasado el plazo.
check_493_grace() {
  local f="$1"
  grep -q 'sigue \*\*en vuelo\*\*' "$f" || return 1
  grep -q '| `IN_FLIGHT` |' "$f" || return 1
  grep -Eq 'pasado el plazo.*«en revisión»' "$f" || return 1
}

# SE-493 3d: un PRESENT discrepante va a revisión sin esperar la gracia.
check_493_present_mismatch() {
  grep -Eq 'no coincide con lo pedido.*«en revisión» sin esperar' "$1"
}

# SE-493 3d: reconcile recibe una clave por llamada; no existe --all.
check_493_reconcile_per_key() {
  local f="$1"
  grep -q 'reconcile --all' "$f" && return 1
  [ "$(grep -Ec '^\$ effect-ledger\.py reconcile [^-]' "$f")" -eq 3 ] || return 1
}

# SE-493 3d: NOT_SENT nunca es «adelante». La fila de la tabla de significados
# existe y su columna «¿Se puede volver a pedir?» no empieza por «Sí».
check_493_not_sent() {
  local f="$1" row last
  grep -q 'No significa «adelante»' "$f" || return 1
  row="$(grep -E '^\| `NOT_SENT` \|' "$f")"
  [ -n "$row" ] || return 1
  last="$(echo "$row" | awk -F'|' '{print $(NF-1)}')"
  echo "$last" | grep -Eqi '^ *(\*\*)?s[ií]\b' && return 1
  return 0
}

# SE-493 Regla 5: la vía manual exige grant firmado; existe la vía por sonda.
check_493_resolve_paths() {
  local f="$1"
  grep -q 'permiso firmado' "$f" || return 1
  grep -q 'Volver a comprobarlo' "$f" || return 1
}

# Sección «## Escena 2» del fichero (hasta el siguiente «## »).
scene2() {
  awk '/^## Escena 2/{on=1;print;next} on&&/^## /{exit} on' "$1"
}

# SE-498 R4: dentro de la escena 2, «parado» (6) antes que «época anterior» (8).
check_498_scene2() {
  local blk l6 l8
  blk="$(scene2 "$1")"
  [ -n "$blk" ] || return 1
  l6="$(echo "$blk" | grep -n 'salida 6\]' | grep 'Parado' | head -1 | cut -d: -f1)"
  l8="$(echo "$blk" | grep -n 'salida 8\]' | grep 'época' | head -1 | cut -d: -f1)"
  [ -n "$l6" ] && [ -n "$l8" ] && [ "$l6" -lt "$l8" ]
}

# Bloque de código de `resume` ejecutado por la operadora.
resume_block() {
  awk '/^\$ savia-control\.py resume/{on=1} on&&/^```/{exit} on' "$1"
}

# SE-498 R4/R6.2: Yema no puede seguir tras resume; Soul figura; se acepta por id
# y el id aceptado es el indeterminado del reconcile.
check_498_resume() {
  local f="$1" blk ind acc
  blk="$(resume_block "$f")"
  [ -n "$blk" ] || return 1
  echo "$blk" | grep -E '^ +Yema ' | grep -Eq 'pueden seguir|en marcha' && return 1
  echo "$blk" | grep -Eq '^ +Soul ' || return 1
  ind="$(grep -Eo '^ +indeterminado +[a-z0-9-]+' "$f" | awk '{print $2}' | head -1)"
  acc="$(echo "$blk" | grep -Eo 'acepto [a-z0-9-]+' | awk '{print $2}' | head -1)"
  [ -n "$ind" ] && [ "$ind" = "$acc" ]
}

# SE-498 R3/R5: reconcile cuadra el recuento y sale 5 con un indeterminado.
check_498_reconcile() {
  local f="$1" n rows
  n="$(grep -Eo 'Efectos abiertos en ámbitos parados: [0-9]+' "$f" | grep -Eo '[0-9]+$')"
  rows="$(awk '/^\$ savia-control\.py reconcile/{on=1;next} on&&/^```/{exit} on' "$f" \
    | grep -Ec '^ +(confirmado|rechazado|compensado|indeterminado) ')"
  [ -n "$n" ] && [ "$n" -eq "$rows" ] || return 1
  grep -q 'Queda 1 indeterminado\. *\[salida 5\]' "$f"
}

# Datos de ejemplo: solo números de PR de la lista permitida. #1500 viene literal
# de las escenas confirmadas; #9001 y #9002 son ficticios. Cualquier otro #N falla.
check_pr_numbers_allowlist() {
  local bad
  bad="$(grep -oE '#[0-9]+' "$1" | grep -vxE '#(1500|9001|9002)' || true)"
  [ -z "$bad" ]
}

# --- Casos positivos sobre los prototipos reales -----------------------------

@test "SE-493: códigos de salida del prototipo = tabla 3d de la spec" {
  check_493_exits_from_spec "$P493" "$S493"
}

@test "SE-493: plazo de espera del prototipo = gracia de pr.merge en la spec" {
  check_493_grace_from_spec "$P493" "$S493"
}

@test "SE-498: códigos de salida del prototipo = tabla de la spec" {
  check_498_exits_from_spec "$P498" "$S498"
}

@test "SE-493: el prototipo distingue en vuelo (dentro del plazo) de en revisión" {
  check_493_grace "$P493"
}

@test "SE-493: escena 1 manda a revisión sin esperar si lo visto no coincide" {
  check_493_present_mismatch "$P493"
}

@test "SE-493: reconcile por clave, sin --all" {
  check_493_reconcile_per_key "$P493"
}

@test "SE-493: NOT_SENT no se presenta como permiso para repetir" {
  check_493_not_sent "$P493"
}

@test "SE-493: resolución con vía por sonda y vía manual con grant" {
  check_493_resolve_paths "$P493"
}

@test "SE-498: escena 2 muestra parado (6) antes que época anterior (8)" {
  check_498_scene2 "$P498"
}

@test "SE-498: resume no deja seguir a Yema, lista Soul y acepta el id indeterminado" {
  check_498_resume "$P498"
}

@test "SE-498: reconcile cuadra el recuento y sale con 5" {
  check_498_reconcile "$P498"
}

@test "prototipos: solo números de PR de la lista permitida" {
  check_pr_numbers_allowlist "$P493"
  check_pr_numbers_allowlist "$P498"
}

# --- Casos negativos ---------------------------------------------------------

@test "negativo SE-493: la spec cambia un exit y el prototipo no" {
  sed 's/| `ALREADY_SUCCEEDED`: sin cambios, imprime el recibo | 7 |/| `ALREADY_SUCCEEDED`: sin cambios, imprime el recibo | 9 |/' "$S493" >"$TMP/s.md"
  run cmp -s "$S493" "$TMP/s.md"
  [ "$status" -ne 0 ]
  run check_493_exits_from_spec "$P493" "$TMP/s.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: el prototipo da un exit distinto del de la spec" {
  printf '%s\n' 'ALREADY_SUCCEEDED eff-1 run-1 abc [salida 7]' 'NOT_SENT eff-2 run-1 - [salida 4]' \
    'NEEDS_REVIEW eff-3 run-2 - [salida 4]' >"$TMP/p.md"
  run check_493_exits_from_spec "$TMP/p.md" "$S493"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: resultado que la spec no define" {
  printf '%s\n' 'ALREADY_SUCCEEDED eff-1 run-1 abc [salida 7]' 'NOT_SENT eff-2 run-1 - [salida 0]' \
    'PROCEED eff-3 run-2 - [salida 0]' >"$TMP/p.md"
  run check_493_exits_from_spec "$TMP/p.md" "$S493"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: la spec cambia la gracia y el prototipo no" {
  sed 's/Para `pr\.merge`: 120 s y 300 s\./Para `pr.merge`: 120 s y 600 s./' "$S493" >"$TMP/s.md"
  run cmp -s "$S493" "$TMP/s.md"
  [ "$status" -ne 0 ]
  run check_493_grace_from_spec "$P493" "$TMP/s.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: la spec renumera STALE_EPOCH y el prototipo no" {
  sed 's/^| 8 | `check --issued-epoch N`/| 10 | `check --issued-epoch N`/' "$S498" >"$TMP/s.md"
  run cmp -s "$S498" "$TMP/s.md"
  [ "$status" -ne 0 ]
  run check_498_exits_from_spec "$P498" "$TMP/s.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: salida 6 con el significado de la 8" {
  printf '%s\n' '> Parado. [salida 6]' '> Permiso rechazado por época. [salida 6]' \
    '> hace falta la aprobación. [salida 4]' 'Queda 1 indeterminado. [salida 5]' >"$TMP/p.md"
  run check_498_exits_from_spec "$TMP/p.md" "$S498"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: sin red pasa directo a en revisión" {
  printf '%s\n' '**Si la comprobación no concluye** (sigue sin red): no repite nada. El efecto pasa a «en revisión».' >"$TMP/p.md"
  run check_493_grace "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: escena 1 promete «hecho» ante cualquier merge visto" {
  printf '%s\n' '**Si la comprobación confirma que GitHub sí lo aplicó** (en cualquier momento), Savia lo marca como hecho.' >"$TMP/p.md"
  run check_493_present_mismatch "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: reconcile --all" {
  printf '%s\n' '$ effect-ledger.py reconcile --all' >"$TMP/p.md"
  run check_493_reconcile_per_key "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: NOT_SENT como 'se puede repetir' (otra redacción)" {
  printf '%s\n' 'No significa «adelante».' '| `NOT_SENT` | No hay envío en este registro. | Sí, sin más. |' >"$TMP/p.md"
  run check_493_not_sent "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: NOT_SENT sin fila en la tabla de significados" {
  printf '%s\n' 'No significa «adelante».' >"$TMP/p.md"
  run check_493_not_sent "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: solo hecho/fallido sin grant ni sonda" {
  printf '%s\n' '1. **Darlo por hecho**' '2. **Darlo por fallido**' >"$TMP/p.md"
  run check_493_resolve_paths "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: escena 2 solo con permiso rechazado por época" {
  printf '%s\n' '## Escena 2' '> Permiso rechazado: es anterior a la parada (época 5, vigente 6).   `[salida 8]`' >"$TMP/p.md"
  run check_498_scene2 "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: el 6 y el 8 están fuera de la escena 2" {
  printf '%s\n' '## Escena 1' '> Parado. `[salida 6]`' '> Permiso de otra época. `[salida 8]`' \
    '## Escena 2' 'Nada.' '## Escena 3' >"$TMP/p.md"
  run check_498_scene2 "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: Yema en pueden seguir y sin acepto <id>" {
  cat >"$TMP/p.md" <<'EOF'
  indeterminado    eff-7f3a   merge de #1500     no se sabe si ocurrió
```
$ savia-control.py resume
  workers            sin permiso propio -> pueden seguir
  Yema               sin permiso propio -> pueden seguir
  Soul               su parada solo la levantas tú
```
EOF
  run check_498_resume "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: acepta un id distinto del indeterminado" {
  cat >"$TMP/p.md" <<'EOF'
  indeterminado    eff-7f3a   merge de #1500     no se sabe si ocurrió
```
$ savia-control.py resume
Para aceptar cada uno, teclea «acepto <id>»: acepto eff-0000
  Soul               sigue parada
  Yema               sigue parada
```
EOF
  run check_498_resume "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: reconcile con recuento que no cuadra y sin salida 5" {
  cat >"$TMP/p.md" <<'EOF'
```
$ savia-control.py reconcile
Efectos abiertos en ámbitos parados: 2
  indeterminado    merge de #1500                     no se sabe si ocurrió
No se ha ejecutado ningún efecto. Queda 1 indeterminado.
```
EOF
  run check_498_reconcile "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo: dato de ejemplo con un número de PR fuera de la lista" {
  printf '%s\n' 'EFECTO 2   fusionar PR ejemplo/repo-a#1499' >"$TMP/p.md"
  run check_pr_numbers_allowlist "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "límite: solo #1500, #9001 y #9002 pasan la lista" {
  printf '%s\n' 'merge de #1500' 'ejemplo/repo-a#9001' 'ejemplo/repo-a#9002' >"$TMP/p.md"
  run check_pr_numbers_allowlist "$TMP/p.md"
  [ "$status" -eq 0 ]
  printf '%s\n' 'ejemplo/repo-a#90010' >"$TMP/q.md"
  run check_pr_numbers_allowlist "$TMP/q.md"
  [ "$status" -ne 0 ]
}
