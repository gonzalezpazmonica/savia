#!/usr/bin/env bats
# tests/test-goal-service.bats — SE-326 S4: goal-service (AC-S4).
# Ref: docs/propuestas/SE-326-harness-loop-hygiene.md

SERVICE="scripts/goal-service.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  export GOAL_STATE_ROOT="$TMPD/goals"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# ── AC-S4 ─────────────────────────────────────────────────────────────────

@test "S4.1: create → fase active, revision 1, round 0 (AC-S4.1)" {
  run bash "$SERVICE" sess1 create --objective "terminar SE-326"
  [[ "$output" =~ '"phase": "active"' ]]
  [[ "$output" =~ '"revision": 1' ]]
  [[ "$output" =~ '"rounds_started": 0' ]]
}

@test "S4.2: mutación con ref desactualizado → version-conflict (AC-S4.2)" {
  out=$(bash "$SERVICE" sess2 create --objective "objetivo A")
  ID=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['goal']['id'])")
  bash "$SERVICE" sess2 edit "$ID" 1 --objective "objetivo B" >/dev/null
  run bash "$SERVICE" sess2 complete "$ID" 1
  [[ $status -eq 3 ]]
  [[ "$output" =~ 'version-conflict' ]]
}

@test "S4.3: round-cap alcanzado → blocked round-cap-reached (AC-S4.3)" {
  out=$(bash "$SERVICE" sess3 create --objective "objetivo" --max-goal-rounds 2)
  ID=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['goal']['id'])")
  bash "$SERVICE" sess3 admit-round "$ID" 1 >/dev/null
  bash "$SERVICE" sess3 admit-round "$ID" 2 >/dev/null
  run bash "$SERVICE" sess3 admit-round "$ID" 3
  [[ "$output" =~ 'round-cap-reached' ]]
  [[ "$output" =~ '"phase": "blocked"' ]]
}

@test "S4.4: block exige code y message (AC-S4.4)" {
  out=$(bash "$SERVICE" sess4 create --objective "objetivo")
  ID=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['goal']['id'])")
  run bash "$SERVICE" sess4 block "$ID" 1
  [[ $status -eq 5 ]]
  run bash "$SERVICE" sess4 block "$ID" 1 --code blocked-by-user --message "pausa manual"
  [[ "$output" =~ '"code": "blocked-by-user"' ]]
  [[ "$output" =~ '"phase": "blocked"' ]]
}

@test "S4.5: clear retiene tombstone, id no se reutiliza (AC-S4.5)" {
  out=$(bash "$SERVICE" sess5 create --objective "objetivo")
  ID=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['goal']['id'])")
  run bash "$SERVICE" sess5 clear "$ID" 1
  [[ "$output" =~ 'tombstone' ]]
  out2=$(bash "$SERVICE" sess5 create --objective "segundo")
  ID2=$(echo "$out2" | python3 -c "import json,sys;print(json.load(sys.stdin)['goal']['id'])")
  [[ "$ID2" -gt "$ID" ]]
}

@test "S4.6: no se puede crear goal si hay uno activo (fase no complete)" {
  bash "$SERVICE" sess6 create --objective "primero" >/dev/null
  run bash "$SERVICE" sess6 create --objective "segundo"
  [[ $status -eq 5 ]]
}

@test "S4.7: estado durable fuera del repo (AC-S4.7)" {
  bash "$SERVICE" sess7 create --objective "objetivo" >/dev/null
  [[ -f "$TMPD/goals/sess7.json" ]]
}

# ── Comportamiento: transiciones, revisiones, códigos de salida y estado ──

_gs() { bash "$SERVICE" "$@"; }
_f() { echo "$1" | python3 -c "import json,sys;d=json.load(sys.stdin);print(eval('d'+sys.argv[1]))" "$2"; }

_new() {  # _new <sesion> [extra...] → imprime el id
  _gs "$1" create --objective "obj" "${@:2}" | python3 -c "import json,sys;print(json.load(sys.stdin)['goal']['id'])"
}

@test "sin sesión: error 2; sin operación: error 2" {
  run bash "$SERVICE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"session obligatoria"* ]]
  run bash "$SERVICE" s
  [ "$status" -eq 2 ]
  [[ "$output" == *"operación obligatoria"* ]]
}

@test "create sin objetivo o con objetivo en blanco: 5 y no escribe estado" {
  run _gs g1 create
  [ "$status" -eq 5 ]
  [[ "$output" == *"objective es obligatorio"* ]]
  run _gs g1 create --objective "   "
  [ "$status" -eq 5 ]
  [ ! -e "$GOAL_STATE_ROOT/g1.json" ]
}

@test "create: objetivo recortado, tope por defecto 10 y tope explícito" {
  run _gs g2 create --objective "  hacer algo  "
  [ "$(_f "$output" "['goal']['objective']")" = "hacer algo" ]
  [ "$(_f "$output" "['goal']['max_goal_rounds']")" = "10" ]
  [ "$(_f "$output" "['goal']['blocked_reason']")" = "None" ]
  run _gs g2b create --objective x --max-goal-rounds 3
  [ "$(_f "$output" "['goal']['max_goal_rounds']")" = "3" ]
}

@test "operación desconocida: 5 con el nombre en el mensaje" {
  run _gs g3 explotar
  [ "$status" -eq 5 ]
  [[ "$output" == *"no permitida: explotar"* ]]
}

@test "get sin objetivo devuelve goal null y 0" {
  run _gs g4 get
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']")" = "None" ]
}

@test "get devuelve el objetivo actual y su revisión" {
  ID=$(_new g5)
  run _gs g5 get
  [ "$(_f "$output" "['goal']['id']")" = "$ID" ]
  [ "$(_f "$output" "['goal']['revision']")" = "1" ]
}

@test "id inexistente: 4 not-found en todas las operaciones con id" {
  _new g6 >/dev/null
  for op in edit pause resume complete block clear admit-round; do
    run _gs g6 "$op" 99 1 --objective x --code c --message m
    [ "$status" -eq 4 ]
    [[ "$output" == *"goal 99 no encontrado"* ]]
  done
}

@test "pause: active→paused sube la revisión; pausar dos veces es 5" {
  ID=$(_new g7)
  run _gs g7 pause "$ID" 1
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['phase']")" = "paused" ]
  [ "$(_f "$output" "['goal']['revision']")" = "2" ]
  run _gs g7 pause "$ID" 2
  [ "$status" -eq 5 ]
  [[ "$output" == *"no se puede pausar goal en fase paused"* ]]
}

@test "resume: paused→active y limpia blocked_reason" {
  ID=$(_new g8)
  _gs g8 block "$ID" 1 --code c-x --message "m" >/dev/null
  run _gs g8 resume "$ID" 2
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['phase']")" = "active" ]
  [ "$(_f "$output" "['goal']['blocked_reason']")" = "None" ]
  [ "$(_f "$output" "['goal']['revision']")" = "3" ]
}

@test "resume de un goal completo es 5" {
  ID=$(_new g9)
  _gs g9 complete "$ID" 1 >/dev/null
  run _gs g9 resume "$ID" 2
  [ "$status" -eq 5 ]
  [[ "$output" == *"no se puede reanudar goal en fase complete"* ]]
}

@test "resume con presupuesto de rondas agotado y bloqueado es 5" {
  ID=$(_new g10 --max-goal-rounds 1)
  _gs g10 admit-round "$ID" 1 >/dev/null
  run _gs g10 admit-round "$ID" 2
  [ "$(_f "$output" "['goal']['phase']")" = "blocked" ]
  run _gs g10 resume "$ID" 3
  [ "$status" -eq 5 ]
  [[ "$output" == *"round budget agotado"* ]]
}

@test "resume bloqueado por el usuario con rondas sobrantes sí reanuda" {
  ID=$(_new g11 --max-goal-rounds 5)
  _gs g11 admit-round "$ID" 1 >/dev/null
  _gs g11 block "$ID" 2 --code por-usuario --message "pausa" >/dev/null
  run _gs g11 resume "$ID" 3
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['phase']")" = "active" ]
}

@test "complete: 0 una vez y 5 si ya está completo" {
  ID=$(_new g12)
  run _gs g12 complete "$ID" 1
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['phase']")" = "complete" ]
  run _gs g12 complete "$ID" 2
  [ "$status" -eq 5 ]
  [[ "$output" == *"goal ya completado"* ]]
}

@test "tras complete se puede crear otro goal con id siguiente" {
  ID=$(_new g13)
  _gs g13 complete "$ID" 1 >/dev/null
  run _gs g13 create --objective "otro"
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['id']")" = "$((ID + 1))" ]
}

@test "create con goal pausado o bloqueado es 5 y cita id y fase" {
  ID=$(_new g14)
  _gs g14 pause "$ID" 1 >/dev/null
  run _gs g14 create --objective "otro"
  [ "$status" -eq 5 ]
  [[ "$output" == *"id $ID, fase paused"* ]]
}

@test "block: exige code y message no vacíos por separado" {
  ID=$(_new g15)
  run _gs g15 block "$ID" 1 --code solo-codigo
  [ "$status" -eq 5 ]
  run _gs g15 block "$ID" 1 --message solo-mensaje
  [ "$status" -eq 5 ]
  run _gs g15 block "$ID" 1 --code "  " --message "  "
  [ "$status" -eq 5 ]
  run _gs g15 get
  [ "$(_f "$output" "['goal']['phase']")" = "active" ]
  [ "$(_f "$output" "['goal']['revision']")" = "1" ]
}

@test "block guarda code y message recortados" {
  ID=$(_new g16)
  run _gs g16 block "$ID" 1 --code " c-1 " --message " texto "
  [ "$(_f "$output" "['goal']['blocked_reason']['code']")" = "c-1" ]
  [ "$(_f "$output" "['goal']['blocked_reason']['message']")" = "texto" ]
}

@test "edit: cambia objetivo y/o tope; sin cambios reales es 5" {
  ID=$(_new g17)
  run _gs g17 edit "$ID" 1 --objective "nuevo"
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['objective']")" = "nuevo" ]
  [ "$(_f "$output" "['goal']['revision']")" = "2" ]
  run _gs g17 edit "$ID" 2 --max-goal-rounds 7
  [ "$(_f "$output" "['goal']['max_goal_rounds']")" = "7" ]
  [ "$(_f "$output" "['goal']['objective']")" = "nuevo" ]
  run _gs g17 edit "$ID" 3 --objective "nuevo"
  [ "$status" -eq 5 ]
  [[ "$output" == *"edit requiere al menos un campo"* ]]
  run _gs g17 get
  [ "$(_f "$output" "['goal']['revision']")" = "3" ]
}

@test "edit con el mismo tope que ya tiene es 5" {
  ID=$(_new g18 --max-goal-rounds 4)
  run _gs g18 edit "$ID" 1 --max-goal-rounds 4
  [ "$status" -eq 5 ]
}

@test "revisión desactualizada: 3 en cada mutación y el estado no cambia" {
  ID=$(_new g19)
  for op in edit pause resume complete block clear admit-round; do
    run _gs g19 "$op" "$ID" 7 --objective y --code c --message m
    [ "$status" -eq 3 ]
    [[ "$output" == *"esperaba rev 7, actual 1"* ]]
  done
  run _gs g19 get
  [ "$(_f "$output" "['goal']['revision']")" = "1" ]
}

@test "admit-round: suma una ronda por llamada y revisión" {
  ID=$(_new g20 --max-goal-rounds 3)
  run _gs g20 admit-round "$ID" 1
  [ "$(_f "$output" "['goal']['rounds_started']")" = "1" ]
  [ "$(_f "$output" "['goal']['revision']")" = "2" ]
  run _gs g20 admit-round "$ID" 2
  [ "$(_f "$output" "['goal']['rounds_started']")" = "2" ]
}

@test "admit-round: la ronda número tope se admite y la siguiente bloquea (frontera)" {
  ID=$(_new g21 --max-goal-rounds 2)
  _gs g21 admit-round "$ID" 1 >/dev/null
  run _gs g21 admit-round "$ID" 2
  [ "$(_f "$output" "['goal']['rounds_started']")" = "2" ]
  [ "$(_f "$output" "['goal']['phase']")" = "active" ]
  run _gs g21 admit-round "$ID" 3
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['blocked']")" = "True" ]
  [ "$(_f "$output" "['goal']['rounds_started']")" = "2" ]
  [ "$(_f "$output" "['goal']['blocked_reason']['message']")" = "cap 2 alcanzado" ]
}

@test "admit-round fuera de fase activa es 5" {
  ID=$(_new g22)
  _gs g22 pause "$ID" 1 >/dev/null
  run _gs g22 admit-round "$ID" 2
  [ "$status" -eq 5 ]
  [[ "$output" == *"no admite rondas"* ]]
}

@test "clear: devuelve tombstone, get queda en null y permite crear" {
  ID=$(_new g23)
  run _gs g23 clear "$ID" 1
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['tombstone']['id']")" = "$ID" ]
  [ "$(_f "$output" "['tombstone']['revision']")" = "2" ]
  run _gs g23 get
  [ "$(_f "$output" "['goal']")" = "None" ]
  run _gs g23 pause "$ID" 2
  [ "$status" -eq 4 ]
  run _gs g23 create --objective "nuevo"
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['id']")" = "$((ID + 1))" ]
}

@test "sesiones aisladas: cada una tiene su fichero y sus ids" {
  A=$(_new sa)
  B=$(_new sb)
  [ "$A" = "1" ]
  [ "$B" = "1" ]
  [ -f "$GOAL_STATE_ROOT/sa.json" ]
  [ -f "$GOAL_STATE_ROOT/sb.json" ]
  _gs sa pause 1 1 >/dev/null
  run _gs sb get
  [ "$(_f "$output" "['goal']['phase']")" = "active" ]
}

@test "estado en disco: JSON válido con next_id y sin fichero .tmp residual" {
  _new g24 >/dev/null
  python3 -c "
import json
d = json.load(open('$GOAL_STATE_ROOT/g24.json'))
assert d['next_id'] == 2 and len(d['goals']) == 1
"
  [ ! -e "$GOAL_STATE_ROOT/g24.json.tmp" ]
}

@test "estado corrupto se trata como vacío en lugar de romper" {
  mkdir -p "$GOAL_STATE_ROOT"
  echo '{no es json' > "$GOAL_STATE_ROOT/g25.json"
  run _gs g25 get
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']")" = "None" ]
  run _gs g25 create --objective x
  [ "$status" -eq 0 ]
}

@test "wrapper: id y revisión sin pasar (faltan) se leen como 0 y dan not-found" {
  _new g26 >/dev/null
  run _gs g26 pause
  [ "$status" -eq 4 ]
  [[ "$output" == *"goal 0 no encontrado"* ]]
}

@test "wrapper: opciones desconocidas se ignoran" {
  run _gs g27 create --objective x --raro
  [ "$status" -eq 0 ]
}

@test "wrapper: --objective con espacios y comillas llega íntegro" {
  run _gs g28 create --objective 'dos "palabras" y más'
  [ "$(_f "$output" "['goal']['objective']")" = 'dos "palabras" y más' ]
}

@test "wrapper: una opción desconocida al principio no descarta las siguientes" {
  run _gs g30 create --raro --objective "tras la rara" --max-goal-rounds 4
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['objective']")" = "tras la rara" ]
  [ "$(_f "$output" "['goal']['max_goal_rounds']")" = "4" ]
}

@test "resume sobre un goal activo es válido: sigue activo y sube la revisión" {
  ID=$(_new g31)
  run _gs g31 resume "$ID" 1
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['phase']")" = "active" ]
  [ "$(_f "$output" "['goal']['revision']")" = "2" ]
}

@test "resume desde pausa con el presupuesto agotado sí reanuda (el tope solo frena bloqueados)" {
  ID=$(_new g32 --max-goal-rounds 1)
  _gs g32 admit-round "$ID" 1 >/dev/null
  _gs g32 pause "$ID" 2 >/dev/null
  run _gs g32 resume "$ID" 3
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['phase']")" = "active" ]
}

@test "complete sobre un goal bloqueado limpia blocked_reason" {
  ID=$(_new g33)
  _gs g33 block "$ID" 1 --code c-1 --message m >/dev/null
  run _gs g33 complete "$ID" 2
  [ "$status" -eq 0 ]
  [ "$(_f "$output" "['goal']['blocked_reason']")" = "None" ]
  [ "$(_f "$output" "['goal']['phase']")" = "complete" ]
}
