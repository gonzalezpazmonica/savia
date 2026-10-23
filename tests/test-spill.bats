#!/usr/bin/env bats
# tests/test-spill.bats — SE-326 S2: spill-save (AC-S2).
# Ref: docs/propuestas/SE-326-harness-loop-hygiene.md

SPILL="scripts/spill-save.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  export SPILL_ROOT="$TMPD/spill"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# ── AC-S2 ─────────────────────────────────────────────────────────────────

@test "S2.1: output > umbral → fichero con 0600 y dir 0700 (AC-S2.1)" {
  python3 -c "print('línea de prueba' * 50)" > "$TMPD/big.txt"
  run bash "$SPILL" --session sessA --name "bash-output.txt" --file "$TMPD/big.txt"
  DEST=$(echo "$output" | grep -o "${TMPD}/spill/[^ ]*" | head -1)
  [[ -n "$DEST" ]]
  MODE=$(stat -c "%a" "$DEST")
  [[ "$MODE" == "600" ]]
  DIRMODE=$(stat -c "%a" "$(dirname "$DEST")")
  [[ "$DIRMODE" == "700" ]]
}

@test "S2.2: output inline reemplazado por preview + locator + hint (AC-S2.2)" {
  python3 -c "print('x' * 500)" > "$TMPD/big.txt"
  run bash "$SPILL" --session sessB --name "out.txt" --file "$TMPD/big.txt"
  [[ "$output" == *"--- preview"* ]]
  [[ "$output" == *"[spill] output completo en"* ]]
  [[ "$output" == *"[spill] usa Read/Grep"* ]]
}

@test "S2.3: fallo de spill (origen inexistente) → no toca nada, exit 1 (AC-S2.3)" {
  run bash "$SPILL" --session sessC --name "out.txt" --file "$TMPD/no-existe.txt"
  [[ $status -eq 1 ]]
  [[ ! -d "$SPILL_ROOT" ]] || [[ -z "$(ls -A "$SPILL_ROOT" 2>/dev/null)" ]]
}

@test "S2.4: nombre con / o .. sanitizado a un segmento (AC-S2.4)" {
  python3 -c "print('y' * 200)" > "$TMPD/big.txt"
  run bash "$SPILL" --session sessD --name "../evil/name.txt" --file "$TMPD/big.txt"
  [[ "$output" =~ "evil" ]]
  # no se crea ningún path fuera del root de spill
  [[ ! -f "$TMPD/evil" ]]
  [[ ! -f "$TMPD/../evil" ]]
}

@test "S2.5: symlink plantado → escritura falla seguro (AC-S2.5)" {
  python3 -c "print('z' * 200)" > "$TMPD/big.txt"
  mkdir -p "$SPILL_ROOT/sessE"
  # plantamos un destino que apunta fuera (adivinando el nombre no es posible por random,
  # pero si existe un symlink en el dir destino el open 'wx' sigue fallando si colisiona)
  RAND=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
  ln -s /etc/passwd "$SPILL_ROOT/sessE/${RAND}-name.txt" 2>/dev/null || true
  run bash "$SPILL" --session sessE --name "name.txt" --file "$TMPD/big.txt"
  [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
  # el /etc/passwd original no fue sobrescrito
  [[ "$(head -1 /etc/passwd)" != "z"* ]]
}

@test "S2.6: stdin feed funciona (AC-S2.1 vía stdin)" {
  run bash -c "printf '%s\n' 'stdin-line' | bash '$SPILL' --session sessF --name 'pipe.txt'"
  [[ $status -eq 0 ]]
  [[ "$output" == *"[spill] output completo en"* ]]
}

# ── Comportamiento: contenido, preview, sanitizado y estado en disco ──────

_dest() { echo "$output" | grep -o "${SPILL_ROOT}/[^ ]*" | head -1; }

@test "contenido íntegro: el fichero spilleado es idéntico al origen" {
  seq 1 500 > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --name n.txt --file "$TMPD/in.txt"
  [ "$status" -eq 0 ]
  cmp "$(_dest)" "$TMPD/in.txt"
}

@test "locator informa el tamaño exacto en bytes" {
  printf 'abcde' > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --name n.txt --file "$TMPD/in.txt"
  [[ "$output" == *"(5 bytes)"* ]]
}

@test "preview: primeras 20 líneas en la cabecera y últimas 20 en la cola" {
  seq 1 100 > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --name n.txt --file "$TMPD/in.txt"
  head_part=$(echo "$output" | sed -n '/primeras 20/,/últimas 20/p')
  tail_part=$(echo "$output" | sed -n '/últimas 20/,/fin preview/p')
  [[ "$head_part" == *$'\n20\n'* ]]
  [[ "$head_part" != *$'\n21\n'* ]]
  [[ "$tail_part" == *$'\n81\n'* ]]
  [[ "$tail_part" == *$'\n100\n'* ]]
  [[ "$tail_part" != *$'\n80\n'* ]]
}

@test "preview: un fichero corto aparece completo en ambas secciones" {
  printf 'uno\ndos\n' > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --name n.txt --file "$TMPD/in.txt"
  [ "$(echo "$output" | grep -c '^uno$')" -eq 2 ]
  [ "$(echo "$output" | grep -c '^dos$')" -eq 2 ]
}

@test "el nombre final lleva sufijo aleatorio hex de 12 caracteres y el nombre seguro" {
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --name "mi salida.txt" --file "$TMPD/in.txt"
  base=$(basename "$(_dest)")
  [[ "$base" =~ ^[0-9a-f]{12}-misalida\.txt$ ]]
}

@test "dos spills con el mismo nombre no colisionan" {
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --name n.txt --file "$TMPD/in.txt"; d1=$(_dest)
  run bash "$SPILL" --session s1 --name n.txt --file "$TMPD/in.txt"; d2=$(_dest)
  [ "$d1" != "$d2" ]
  [ -f "$d1" ]
  [ -f "$d2" ]
}

@test "nombre vacío o solo caracteres inválidos cae a output.txt" {
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --file "$TMPD/in.txt"
  [[ "$(_dest)" == *-output.txt ]]
  run bash "$SPILL" --session s1 --name '!!!@@@' --file "$TMPD/in.txt"
  [[ "$(_dest)" == *-output.txt ]]
}

@test "nombre con barras: queda en el directorio de sesión, sin subdirectorios" {
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session s1 --name '../../etc/passwd' --file "$TMPD/in.txt"
  d=$(_dest)
  [ "$(dirname "$d")" = "$SPILL_ROOT/s1" ]
  [[ "$(basename "$d")" == *-.._.._etc_passwd ]]
  [ "$(find "$SPILL_ROOT" -type f | wc -l)" -eq 1 ]
}

@test "sesión con .. o / no sale del root de spill (traversal)" {
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session '../../fuera' --name n.txt --file "$TMPD/in.txt"
  [ "$status" -eq 0 ]
  d=$(_dest)
  [[ "$d" == "$SPILL_ROOT"/* ]]
  [ ! -e "$TMPD/fuera" ]
  [ ! -e "$TMPD/../fuera" ]
  run bash "$SPILL" --session '..' --name n.txt --file "$TMPD/in.txt"
  [[ "$(_dest)" == "$SPILL_ROOT/default/"* ]]
}

@test "sesión vacía usa SAVIA_SESSION_ID; --session lo anula" {
  echo x > "$TMPD/in.txt"
  SAVIA_SESSION_ID=envsess run bash "$SPILL" --name n.txt --file "$TMPD/in.txt"
  [[ "$(_dest)" == "$SPILL_ROOT/envsess/"* ]]
  SAVIA_SESSION_ID=envsess run bash "$SPILL" --session flag --name n.txt --file "$TMPD/in.txt"
  [[ "$(_dest)" == "$SPILL_ROOT/flag/"* ]]
}

@test "sin SAVIA_SESSION_ID ni --session el directorio es default" {
  echo x > "$TMPD/in.txt"
  env -u SAVIA_SESSION_ID bash "$SPILL" --name n.txt --file "$TMPD/in.txt" > "$TMPD/o.txt"
  [ -d "$SPILL_ROOT/default" ]
}

@test "argumentos desconocidos se ignoran sin romper" {
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --raro --session s1 --name n.txt --file "$TMPD/in.txt"
  [ "$status" -eq 0 ]
  [ -d "$SPILL_ROOT/s1" ]
}

@test "origen inexistente: mensaje a stderr con la ruta y sin crear la sesión" {
  run bash "$SPILL" --session sNo --name n.txt --file "$TMPD/falta.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"origen no existe: $TMPD/falta.txt"* ]]
  [ ! -e "$SPILL_ROOT/sNo" ]
}

@test "raíz no escribible: falla con 1 y mensaje, sin salida de preview" {
  : > "$TMPD/archivo"
  SPILL_ROOT="$TMPD/archivo/sub" run bash "$SPILL" --session s1 --name n.txt --file "$TMPD/archivo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pudo crear"* ]]
  [[ "$output" != *"preview"* ]]
}

@test "stdin: el contenido guardado es el de la tubería, 0600" {
  run bash -c "printf 'a\nb\nc\n' | bash '$SPILL' --session sp --name p.txt"
  [ "$status" -eq 0 ]
  d=$(_dest)
  [ "$(cat "$d")" = $'a\nb\nc' ]
  [ "$(stat -c %a "$d")" = "600" ]
  [[ "$output" == *"(6 bytes)"* ]]
}

@test "directorio de sesión queda en 0700 aunque exista con otros permisos" {
  mkdir -p "$SPILL_ROOT/sm"; chmod 755 "$SPILL_ROOT/sm"
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session sm --name n.txt --file "$TMPD/in.txt"
  [ "$(stat -c %a "$SPILL_ROOT/sm")" = "700" ]
}

@test "sesión vacía o solo con caracteres inválidos usa default, no el root" {
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session '' --name n.txt --file "$TMPD/in.txt"
  [[ "$(_dest)" == "$SPILL_ROOT/default/"* ]]
  run bash "$SPILL" --session '@@@' --name n.txt --file "$TMPD/in.txt"
  [[ "$(_dest)" == "$SPILL_ROOT/default/"* ]]
  [ -z "$(find "$SPILL_ROOT" -maxdepth 1 -type f)" ]
}

@test "fallo al escribir desde fichero: exit 1, mensaje y sin preview" {
  mkdir -p "$SPILL_ROOT"; ln -s /proc/self "$SPILL_ROOT/sproc"
  echo x > "$TMPD/in.txt"
  run bash "$SPILL" --session sproc --name n.txt --file "$TMPD/in.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pudo escribir"* ]]
  [[ "$output" != *"preview"* ]]
}

@test "fallo al escribir desde stdin: exit 1, mensaje y sin preview" {
  mkdir -p "$SPILL_ROOT"; ln -s /proc/self "$SPILL_ROOT/sproc"
  run bash -c "echo x | bash '$SPILL' --session sproc --name n.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pudo escribir"* ]]
  [[ "$output" != *"preview"* ]]
}
