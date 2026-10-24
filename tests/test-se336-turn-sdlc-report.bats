#!/usr/bin/env bats
# SE-336 S4 — turn-sdlc-report: consolidación por ventana
# Ref: docs/specs/SE-336-turn-sdlc.spec.md
# Spec: docs/specs/SE-336-turn-sdlc.spec.md (AC-08)
# Todo se ejecuta contra logs y carpeta de salida temporales (variables SAVIA_TURN_SDLC_*):
# nunca se toca output/ del repo.

SCRIPT="scripts/turn-sdlc-report.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIXDIR"
  DISC="$FIXDIR/disc.jsonl"; DOD="$FIXDIR/dod.jsonl"; OUT="$FIXDIR/out"
  export SAVIA_TURN_SDLC_DISCOVERY_LOG="$DISC" SAVIA_TURN_SDLC_DOD_LOG="$DOD" SAVIA_TURN_SDLC_OUT_DIR="$OUT"
}

@test "el script existe, tiene sintaxis valida y usa set -uo pipefail" {
  [[ -f "$SCRIPT" ]]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -c '^set -uo pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

# turn <order_ok> <first_tools>
turn() { printf '{"ts":"t","query_hash":"h","first_tools":"%s","order_ok":"%s"}\n' "$2" "$1" >> "$DISC"; }
# dod <rule> <severity>
dod() { printf '{"ts":"t","rule":"%s","severity":"%s","detail":"d","query_hash":"h"}\n' "$1" "$2" >> "$DOD"; }
# js <expresion-python-sobre-d>: evalua sobre el JSON de --json
js() { run bash "$SCRIPT" --window W1 --json; [ "$status" -eq 0 ]; python3 -c "import json,sys;d=json.loads(sys.argv[1]);assert $1, d" "$output"; }
report() { cat "$OUT/turn-sdlc-report-${1:-W1}.md"; }
# has <ventana> <literal>: el literal esta en el informe (sin tuberias que mueran por SIGPIPE)
has() { grep -qF -- "$2" "$OUT/turn-sdlc-report-$1.md"; }

@test "AC-08a: reporte con contadores coherentes con JSONL de fixture" {
  for t in "savia-vaults_vault_search," "memory-store.sh," "codegraph_explore," "savia-vaults_vault_read,"; do turn true "$t"; done
  turn false "grep,grep,grep,savia-vaults_vault_search,"
  turn false "glob,read,grep,"
  turn na "edit,bash,"
  dod DOD-001 block; dod DOD-002 warn; dod DOD-003 warn
  run bash "$SCRIPT" --window WTEST
  [ "$status" -eq 0 ]
  [ -f "$OUT/turn-sdlc-report-WTEST.md" ]
  grep -qF "| Turnos observados | 7 |" "$OUT/turn-sdlc-report-WTEST.md"
  grep -qF "| order_ok=true | 4 |" "$OUT/turn-sdlc-report-WTEST.md"
  grep -qF "| order_ok=false | 2 |" "$OUT/turn-sdlc-report-WTEST.md"
  grep -qF "| order_ok=na (no-cognitivo) | 1 |" "$OUT/turn-sdlc-report-WTEST.md"
  grep -qF "| **% order_ok (excl. na)** | **66%** |" "$OUT/turn-sdlc-report-WTEST.md"
  grep -qF "| DOD bloqueos | 1 |" "$OUT/turn-sdlc-report-WTEST.md"
  grep -qF "| DOD warnings | 2 |" "$OUT/turn-sdlc-report-WTEST.md"
}

@test "AC-08b: --json produce contadores correctos" {
  turn false "grep,"; turn true "vault_search,"
  js "d['turns']==2 and d['order_false']==1 and d['order_ok']==1 and d['order_na']==0 and d['pct_order_ok']==50 and d['window']=='W1'"
}

@test "--json no escribe ningun fichero de reporte" {
  turn true "vault_search,"
  run bash "$SCRIPT" --window W1 --json
  [ "$status" -eq 0 ]
  [ ! -e "$OUT" ]
}

@test "el modo normal imprime la ruta generada y el resumen de una linea" {
  turn true "a,"; turn false "grep,"; dod R block; dod R warn
  run bash "$SCRIPT" --window W9
  [ "$status" -eq 0 ]
  [[ "$output" == *"Generated $OUT/turn-sdlc-report-W9.md"* ]]
  [[ "$output" == *"turnos=2 · order_ok=50% · dod_blocked=1 · dod_warn=1"* ]]
}

@test "el porcentaje excluye los turnos na y trunca (no redondea)" {
  turn true a; turn true b; turn false grep; turn na x; turn na y
  js "d['pct_order_ok']==66 and d['order_na']==2 and d['turns']==5"
}

@test "todos los turnos na dan 0 % sin dividir por cero" {
  turn na x; turn na y
  js "d['pct_order_ok']==0 and d['turns']==2 and d['order_na']==2"
}

@test "sin turnos el porcentaje es 0" {
  js "d['pct_order_ok']==0 and d['turns']==0 and d['top_violations']=={} and d['dod_rules']=={}"
}

@test "100 % cuando no hay violaciones" {
  turn true a; turn true b
  js "d['pct_order_ok']==100"
}

@test "un order_ok con valor desconocido o ausente cuenta como na" {
  turn raro "x,"
  printf '%s\n' '{"first_tools":"y,"}' >> "$DISC"
  js "d['order_na']==2 and d['order_ok']==0 and d['order_false']==0"
}

@test "las lineas en blanco se ignoran" {
  turn true a
  printf '\n\n' >> "$DISC"
  turn false grep
  js "d['turns']==2"
}

@test "una linea que no es JSON cuenta como turno na y no rompe el informe" {
  turn true a
  echo "esto no es json" >> "$DISC"
  js "d['turns']==2 and d['order_na']==1 and d['order_ok']==1"
}

@test "la primera herramienta de cada turno falso suma en top_violations" {
  turn false "grep,grep,vault_search,"
  turn false "grep,read,"
  turn false "glob,grep,"
  turn true "grep,vault_search,"
  js "d['top_violations']=={'grep':2,'glob':1}"
}

@test "las violaciones sin first_tools no aportan a top_violations pero si al contador" {
  turn false ""
  js "d['order_false']==1 and d['top_violations']=={}"
}

@test "los turnos true no entran en top_violations" {
  turn true "grep,vault_search,"
  js "d['top_violations']=={}"
}

@test "DOD cuenta por severidad: block y warn, y otras severidades no suman" {
  dod R1 block; dod R1 block; dod R2 warn; dod R3 info
  js "d['dod_blocked']==2 and d['dod_warn']==1"
}

@test "dod_rules cuenta cada regla, incluida la de severidad info" {
  dod R1 block; dod R1 warn; dod R2 warn; dod R3 info
  js "d['dod_rules']=={'R1':2,'R2':1,'R3':1}"
}

@test "un evento DOD sin regla no crea entrada vacia en dod_rules" {
  printf '%s\n' '{"severity":"block"}' >> "$DOD"
  js "d['dod_blocked']==1 and d['dod_rules']=={}"
}

@test "el informe markdown lista las violaciones y reglas con su cuenta" {
  turn false "grep,x,"; turn false "grep,y,"
  dod DOD-007 warn
  run bash "$SCRIPT" --window W1
  [ "$status" -eq 0 ]
  has W1 '| `grep` | 2 |'
  has W1 '| DOD-007 | 1 |'
}

@test "sin violaciones ni reglas el informe muestra la fila vacia" {
  turn true a
  run bash "$SCRIPT" --window W1
  [ "$status" -eq 0 ]
  [ "$(grep -cF '| — | 0 |' "$OUT/turn-sdlc-report-W1.md")" -eq 2 ]
}

@test "con violaciones y reglas no aparece la fila vacia" {
  turn false "grep,"; dod R warn
  run bash "$SCRIPT" --window W1
  [ "$status" -eq 0 ]
  ! has W1 '| — | 0 |'
}

@test "el informe lleva titulo con la ventana, fecha de hoy y las tres secciones" {
  run bash "$SCRIPT" --window W42
  [ "$status" -eq 0 ]
  [ "$(head -1 "$OUT/turn-sdlc-report-W42.md")" = "# Turn-SDLC Report — W42 ($(date +%Y-%m-%d))" ]
  has W42 "## Resumen"
  has W42 "## Top violaciones de orden (primera tool del turno)"
  has W42 "## Reglas DOD disparadas"
}

@test "crea la carpeta de salida si no existe y no falla si ya existe" {
  run bash "$SCRIPT" --window W1
  [ "$status" -eq 0 ]
  [ -d "$OUT" ]
  run bash "$SCRIPT" --window W1
  [ "$status" -eq 0 ]
}

@test "ventana por defecto W? cuando no se indica" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"window":"W?"'* ]]
}

@test "--json imprime una unica linea JSON valida con todas las claves" {
  turn false "grep,"; dod R warn
  run bash "$SCRIPT" --window W1 --json
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
  python3 -c 'import json,sys;d=json.loads(sys.argv[1]);assert set(d)=={"window","turns","order_ok","order_false","order_na","pct_order_ok","dod_blocked","dod_warn","top_violations","dod_rules"},d' "$output"
}

@test "sin logs existentes → reporte vacío pero válido (exit 0)" {
  run bash "$SCRIPT" --window WTEST
  [ "$status" -eq 0 ]
  grep -qF "| Turnos observados | 0 |" "$OUT/turn-sdlc-report-WTEST.md"
  grep -qF "| DOD bloqueos | 0 |" "$OUT/turn-sdlc-report-WTEST.md"
}

@test "input inválido → exit 2 con uso en stderr y sin informe" {
  run bash "$SCRIPT" --badflag
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
  [ ! -e "$OUT" ]
}

@test "un argumento valido seguido de uno invalido tambien falla con 2" {
  run bash "$SCRIPT" --window W1 --nope
  [ "$status" -eq 2 ]
}
