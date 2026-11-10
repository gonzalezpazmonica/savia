#!/usr/bin/env bats
# Coherencia interna de los prototipos S0 de SE-510, SE-513 y SE-514
# (hallazgos de la revisión de la PR #1503). Cada caso negativo muta una
# copia del prototipo real y comprueba que el checker la rechaza.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHK="$ROOT/tests/prototype_s0_consistency.py"
  A="$ROOT/docs/specs/assets"
  HTML="$A/SE-514-prototipo.html"
  R510="$A/prototipo-SE-510.md"
  P513="$A/prototipo-SE-513.md"
  S513="$ROOT/docs/specs/SE-513-admision-duradera-y-comprobacion-previa.spec.md"
  T="$BATS_TEST_TMPDIR"
}

# --- SE-514: consecuencia propia por botón ---

@test "SE-514: el prototipo real pasa (10 botones con mensaje propio)" {
  run python3 "$CHK" html "$HTML"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK html: 10 botones en 4 grupos"* ]]
}

@test "SE-514: «Publica sin comprobar» no puede decir que se ejecuta la comprobación" {
  run grep -o 'data-msg="[^"]*">Publica sin comprobar' "$HTML"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Ejecuto la comprobación"* ]]
}

@test "SE-514 negativo: dos botones con el mismo mensaje se rechazan" {
  sed 's/data-msg="Aplazado. No publico[^"]*"/data-msg="Ejecuto la comprobación y vuelvo con el resultado. No publico hasta tenerlo."/' "$HTML" > "$T/p.html"
  run python3 "$CHK" html "$T/p.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grupo c4: botones distintos muestran el mismo mensaje"* ]]
}

@test "SE-514 negativo: un botón sin data-msg se rechaza" {
  sed 's/ data-msg="Registrado: el informe se queda en borrador."//' "$HTML" > "$T/p.html"
  run python3 "$CHK" html "$T/p.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"«No publicar» (c3) sin data-msg propio"* ]]
}

@test "SE-514 negativo: role como propiedad se rechaza" {
  sed 's/b.setAttribute("role","tab");/b.role="tab";/' "$HTML" > "$T/p.html"
  run python3 "$CHK" html "$T/p.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"setAttribute"* ]]
}

@test "SE-514 negativo: interpolar el mensaje en HTML se rechaza" {
  sed 's/d.textContent=b.dataset.msg;/d.innerHTML=`${b.dataset.msg}`;/' "$HTML" > "$T/p.html"
  run python3 "$CHK" html "$T/p.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"textContent"* ]]
}

# --- SE-510: el informe cuadra ---

@test "SE-510: el informe real cuadra (filas, TOTAL y vista list)" {
  run python3 "$CHK" report "$R510"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK report: 5 guardas, TOTAL 24"* ]]
}

@test "SE-510 negativo: 3 falsos al 100 % con 2 falsos en la vista list se rechaza" {
  # Reproduce la versión revisada: fila y TOTAL cuadran entre sí, la vista list no.
  sed -e 's/^pr-summary-gate                   7            3       2        67 %              4$/pr-summary-gate                   7            3       3       100 %              4/' \
      -e 's/^TOTAL                            24           15       5        33 %              9$/TOTAL                            24           15       6        40 %              9/' \
      "$R510" > "$T/r.md"
  run python3 "$CHK" report "$T/r.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pr-summary-gate: la vista list no cuadra con su fila del informe"* ]]
}

@test "SE-510 negativo: tasa mal calculada se rechaza" {
  sed 's/^\(validate-bash-global .*\)33 %/\140 %/' "$R510" > "$T/r.md"
  run python3 "$CHK" report "$T/r.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"validate-bash-global: tasa 40 % != 33 %"* ]]
}

@test "SE-510 límite: UNKNOWN con 0 etiquetados es válido; 0 % no" {
  sed 's/^\(repeat-tool-guard .*\)UNKNOWN/\1    0 %/' "$R510" > "$T/r.md"
  run python3 "$CHK" report "$T/r.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"repeat-tool-guard: tasa 0 % != UNKNOWN"* ]]
}

# --- SE-513: ningún «aplicado» sin prueba ---

@test "SE-513: el prototipo real pasa" {
  run python3 "$CHK" states "$P513" "$S513"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK states: 7 frases, 3 cambios"* ]]
}

@test "SE-513 negativo: frase no fijada por la spec sin marcar como propuesta" {
  sed 's/^\*\*Savia:\*\* \*(propuesta)\* Ya lo tenía/**Savia:** Ya lo tenía/' "$P513" > "$T/s.md"
  run python3 "$CHK" states "$T/s.md" "$S513"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fijada por la spec y sin marcar"* ]]
}

@test "SE-513 negativo: «aplicado» en la escena 5 sin fila con prueba se rechaza" {
  sed 's/^\*\*Savia:\*\* \*(propuesta)\* Ha terminado su paso.*/**Savia:** *(propuesta)* Ha terminado su paso. Ha seguido el orden nuevo: aplicado./' "$P513" > "$T/s.md"
  run python3 "$CHK" states "$T/s.md" "$S513"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aplicado» sin fila con prueba"* ]]
}

@test "SE-513 negativo: APLICADO en la tabla final sin prueba se rechaza" {
  sed 's/^#9      migración después de la CI             NO SÉ       11:34/#9      migración después de la CI             APLICADO    11:34/' "$P513" > "$T/s.md"
  run python3 "$CHK" states "$T/s.md" "$S513"
  [ "$status" -eq 1 ]
  [[ "$output" == *"#9: APLICADO en la tabla sin ninguna fila con prueba"* ]]
}

# --- fail-closed ---

@test "fail-closed: fichero inexistente sale 2" {
  run python3 "$CHK" report "$T/no-existe.md"
  [ "$status" -eq 2 ]
}

@test "fail-closed: modo desconocido o sin spec sale 2" {
  run python3 "$CHK" states "$P513"
  [ "$status" -eq 2 ]
  run python3 "$CHK" otro "$P513"
  [ "$status" -eq 2 ]
}

@test "fail-closed: fichero sin tabla sale 2, no PASS" {
  printf '# vacío\n' > "$T/v.md"
  run python3 "$CHK" report "$T/v.md"
  [ "$status" -eq 2 ]
}
