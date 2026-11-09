#!/usr/bin/env bats
# Coherencia de los prototipos S0 de SE-493 y SE-498 con su spec (revisión PR #1501).
# Cada comprobación es una función sobre un fichero; los casos negativos usan
# fixtures que reproducen los defectos detectados por la revisora.

ROOT="$BATS_TEST_DIRNAME/.."
P493="$ROOT/docs/specs/assets/SE-493-prototipo.md"
P498="$ROOT/docs/specs/assets/SE-498-prototipo.md"

setup() { TMP="$(mktemp -d)"; }
teardown() { rm -rf "$TMP"; }

# SE-493 regla 2c/3d: dentro de la gracia un DISPATCHED dudoso sigue en vuelo;
# «en revisión» solo pasado el plazo.
check_493_grace() {
  local f="$1"
  grep -q 'sigue \*\*en vuelo\*\*' "$f" || return 1
  grep -q '| `IN_FLIGHT` |' "$f" || return 1
  grep -Eq 'pasado el plazo.*(«en revisión»|en revisión)' "$f" || return 1
}

# SE-493 3d: reconcile recibe una clave por llamada; no existe --all.
check_493_reconcile_per_key() {
  local f="$1"
  grep -q 'reconcile --all' "$f" && return 1
  [ "$(grep -Ec '^\$ effect-ledger\.py reconcile [^-]' "$f")" -eq 3 ] || return 1
}

# SE-493 3d: NOT_SENT nunca es «adelante».
check_493_not_sent() {
  local f="$1"
  grep -q 'No significa «adelante»' "$f" || return 1
  grep -q 'Se comprobó que no ocurrió. | Sí.' "$f" && return 1
  return 0
}

# SE-493 Regla 5: la vía manual exige grant firmado; existe la vía por sonda.
check_493_resolve_paths() {
  local f="$1"
  grep -q 'permiso firmado' "$f" || return 1
  grep -q 'Volver a comprobarlo' "$f" || return 1
}

# SE-498 R4: mientras sigue parado, check sale 6; STALE_EPOCH (8) solo tras resume.
check_498_scene2() {
  local f="$1" l6 l8
  l6="$(grep -n 'salida 6\]' "$f" | head -1 | cut -d: -f1)"
  l8="$(grep -n 'salida 8\]' "$f" | head -1 | cut -d: -f1)"
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

# Datos de ejemplo: nada de números de PR reales recientes salvo la etiqueta #1500
# que viene literal de las escenas confirmadas.
check_no_real_prs() {
  ! grep -Eq '#1501\b' "$1"
}

@test "SE-493: el prototipo distingue en vuelo (dentro del plazo) de en revisión" {
  check_493_grace "$P493"
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

@test "prototipos: no usan el número de esta PR como dato de ejemplo" {
  check_no_real_prs "$P493"
  check_no_real_prs "$P498"
}

# --- Casos negativos: fixtures con los defectos de la versión revisada ---

@test "negativo SE-493: sin red pasa directo a en revisión" {
  printf '%s\n' '**Si la comprobación no concluye** (sigue sin red): no repite nada. El efecto pasa a «en revisión».' >"$TMP/p.md"
  run check_493_grace "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: reconcile --all" {
  printf '%s\n' '$ effect-ledger.py reconcile --all' >"$TMP/p.md"
  run check_493_reconcile_per_key "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: NOT_SENT como 'se puede repetir'" {
  printf '%s\n' '| `NOT_SENT` | Se comprobó que no ocurrió. | Sí. |' >"$TMP/p.md"
  run check_493_not_sent "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-493: solo hecho/fallido sin grant ni sonda" {
  printf '%s\n' '1. **Darlo por hecho**' '2. **Darlo por fallido**' >"$TMP/p.md"
  run check_493_resolve_paths "$TMP/p.md"
  [ "$status" -ne 0 ]
}

@test "negativo SE-498: escena 2 solo con permiso rechazado por época" {
  printf '%s\n' '> Permiso rechazado: es anterior a la parada (época 5, vigente 6).   `[salida 8]`' >"$TMP/p.md"
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

@test "negativo: dato de ejemplo con #1501" {
  printf '%s\n' 'EFECTO 2   fusionar PR ejemplo/repo-a#1501' >"$TMP/p.md"
  run check_no_real_prs "$TMP/p.md"
  [ "$status" -ne 0 ]
}
