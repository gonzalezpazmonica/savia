#!/usr/bin/env bats
# SE-230 S3: persistencia, errores de escritura y límites de carga.
# Pruebas aisladas; los casos de reloj fijan la ventana sin esperas.
# Ref: docs/rules/domain/focal-parallelization-protocol.md

NIDO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="scripts/focal-checkin.sh"
FOCAL_CHECKIN="$NIDO_DIR/$SCRIPT"
TEST_FOCAL_DIR=""

@test "latido con session_pid null rechaza el estado sin modificarlo" {
  local file="$HOME/.savia/focal-state/parcial.json"
  printf '{"nido":"parcial","updated_at":"2000-01-01T00:00:00Z","session_pid":null}\n' > "$file"
  local before; before=$(cat "$file")
  run bash "$FOCAL_CHECKIN" --nido parcial
  [ "$status" -ne 0 ]
  [ "$(cat "$file")" = "$before" ]
}

@test "intervalo con updated_at null rechaza el estado sin modificarlo" {
  local file="$HOME/.savia/focal-state/parcial.json"
  printf '{"nido":"parcial","updated_at":null,"check_in_interval_min":10}\n' > "$file"
  local before; before=$(cat "$file")
  run bash "$FOCAL_CHECKIN" --nido parcial --set-interval 20
  [ "$status" -ne 0 ]
  [ "$(cat "$file")" = "$before" ]
}

setup() {
  TEST_FOCAL_DIR="$(mktemp -d /tmp/focal-checkin-test-XXXXXX)"
  export REAL_HOME="$HOME"
  export HOME="$TEST_FOCAL_DIR"
  mkdir -p "$HOME/.savia/focal-state"
}

teardown() {
  export HOME="$REAL_HOME"
  rm -rf "$TEST_FOCAL_DIR"
}

_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_past_iso() {
  date -u -d "-${1} minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
  date -u -v "-${1}M" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}

_write_focal() {
  local name="$1"
  local now; now=$(_now_iso)
  cat > "$HOME/.savia/focal-state/${name}.json" <<EOF
{
  "nido": "${name}",
  "branch": "agent/test",
  "task": "test",
  "status": "active",
  "last_action": "",
  "context_summary": "",
  "waiting_for": null,
  "next_human_decision": null,
  "check_in_interval_min": 10,
  "session_pid": 9999,
  "last_commit_hash": "abc",
  "created_at": "${now}",
  "updated_at": "${now}"
}
EOF
}

_write_decision_nido() {
  local name="$1"
  local now; now=$(_now_iso)
  cat > "$HOME/.savia/focal-state/${name}.json" <<EOF
{
  "nido": "${name}",
  "branch": "agent/test",
  "task": "test",
  "status": "active",
  "last_action": "",
  "context_summary": "",
  "waiting_for": null,
  "next_human_decision": {
    "type": "review",
    "description": "pending decision",
    "blocking": true,
    "urgency": 2,
    "cognitive_cost": 2,
    "created_at": "${now}"
  },
  "check_in_interval_min": 10,
  "session_pid": 9999,
  "last_commit_hash": "abc",
  "created_at": "${now}",
  "updated_at": "${now}"
}
EOF
}

# ── Test 1: --nido actualiza updated_at ───────────────────────────────────────
@test "1. focal-checkin --nido actualiza updated_at" {
  _write_focal "checkin-nido"
  local old_ts="2000-01-01T00:00:00Z"
  sed -i 's/"updated_at": "[^"]*"/"updated_at": "2000-01-01T00:00:00Z"/' "$HOME/.savia/focal-state/checkin-nido.json"
  run bash "$FOCAL_CHECKIN" --nido "checkin-nido"
  [ "$status" -eq 0 ]
  local new_ts; new_ts=$(grep -oP '"updated_at"\s*:\s*"\K[^"]*' "$HOME/.savia/focal-state/checkin-nido.json")
  # El timestamp debe ser diferente
  [ "$old_ts" != "$new_ts" ]
}

# ── Test 2: --set-interval actualiza check_in_interval_min ───────────────────
@test "2. focal-checkin --set-interval actualiza el campo" {
  _write_focal "interval-nido"
  run bash "$FOCAL_CHECKIN" --set-interval 25 --nido "interval-nido"
  [ "$status" -eq 0 ]
  local val; val=$(grep -oP '"check_in_interval_min"\s*:\s*\K[0-9]+' "$HOME/.savia/focal-state/interval-nido.json")
  [ "$val" = "25" ]
}

# ── Test 3: --load con 0 switches → OK ────────────────────────────────────────
@test "3. focal-checkin --load con 0 switches devuelve OK" {
  # No hay .switch-log
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

# ── Test 4: --load con 6 switches en 1h → OVERLOAD ───────────────────────────
@test "4. focal-checkin --load con 6 switches en 1h devuelve OVERLOAD" {
  # Crear .switch-log con 6 entradas en la última hora
  local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  for i in 1 2 3 4 5 6; do
    local ts; ts=$(date -u -d "-${i} minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                   date -u -v "-${i}M" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    printf '%s nidoA→nidoB\n' "$ts" >> "$HOME/.savia/.switch-log"
  done
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "OVERLOAD" ]
}

# ── Test 5: --load con 6 decisiones pendientes → OVERLOAD ────────────────────
@test "5. focal-checkin --load con 6 decisiones pendientes devuelve OVERLOAD" {
  for i in 1 2 3 4 5 6; do
    _write_decision_nido "dec-nido-${i}"
  done
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "OVERLOAD" ]
}

# ── Test 6: --load con 4 switches → HIGH ─────────────────────────────────────
@test "6. focal-checkin --load con 4 switches en 1h devuelve HIGH" {
  for i in 1 2 3 4; do
    local ts; ts=$(date -u -d "-${i} minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                   date -u -v "-${i}M" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    printf '%s nidoA→nidoB\n' "$ts" >> "$HOME/.savia/.switch-log"
  done
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "HIGH" ]
}

# ── Test 7: .switch-log es append-only ────────────────────────────────────────
@test "7. .switch-log es append-only (no se sobreescribe)" {
  local SWITCH_SCRIPT="$NIDO_DIR/scripts/focal-switch.sh"
  local f1="$HOME/.savia/focal-state/nido-x.json"
  local f2="$HOME/.savia/focal-state/nido-y.json"
  local now; now=$(_now_iso)
  # Crear nidos mínimos
  cat > "$f1" <<EOF
{"nido":"nido-x","branch":"b","task":"t","status":"active","last_action":"","context_summary":"","waiting_for":null,"next_human_decision":null,"check_in_interval_min":10,"session_pid":1,"last_commit_hash":"","created_at":"${now}","updated_at":"${now}"}
EOF
  cat > "$f2" <<EOF
{"nido":"nido-y","branch":"b","task":"t","status":"active","last_action":"","context_summary":"","waiting_for":null,"next_human_decision":null,"check_in_interval_min":10,"session_pid":1,"last_commit_hash":"","created_at":"${now}","updated_at":"${now}"}
EOF
  bash "$SWITCH_SCRIPT" --from "nido-x" --to "nido-y" --task "primer cambio"
  bash "$SWITCH_SCRIPT" --from "nido-y" --to "nido-x" --task "segundo cambio"
  [ -f "$HOME/.savia/.switch-log" ]
  local lines; lines=$(wc -l < "$HOME/.savia/.switch-log")
  [ "$lines" -ge 2 ]
}

# ── Test 8: focal-checkin funciona sin jq ni python3 ─────────────────────────
@test "8. focal-checkin funciona sin jq" {
  _write_focal "nojq-nido"
  # Forzar que el PATH no incluya jq ni python3
  run env PATH="/usr/bin:/bin" bash "$FOCAL_CHECKIN" --nido "nojq-nido"
  [ "$status" -eq 0 ]
}

# ── Test 9: sin .switch-log → OK ──────────────────────────────────────────────
@test "9. sin .switch-log focal-checkin --load muestra OK" {
  rm -f "$HOME/.savia/.switch-log"
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

# ── Test 10: --load respeta ventana de 1 hora (switches de hace 2h no cuentan) ──
@test "10. --load solo cuenta switches de la última hora" {
  # Escribir 10 switches de hace 2 horas (no deben contar)
  for i in 1 2 3 4 5 6 7 8 9 10; do
    local ts; ts=$(date -u -d "-$((120 + i)) minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                   date -u -v "-$((120 + i))M" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    printf '%s nidoA→nidoB\n' "$ts" >> "$HOME/.savia/.switch-log"
  done
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  # 0 switches en la última hora → OK
  [ "$output" = "OK" ]
}

# ── S03n: comportamiento discriminante (fronteras, conservación, errores) ─────
# Ref: docs/propuestas/SE-230-focal-attention.md (Slice 3) — umbrales OK ≤2, HIGH 3–5, OVERLOAD >5.

_switches() {  # _switches N: N cambios en los últimos minutos
  local i ts
  for ((i = 1; i <= $1; i++)); do
    ts=$(_past_iso "$i")
    printf '%s nidoA→nidoB\n' "$ts" >> "$HOME/.savia/.switch-log"
  done
}

_null_decision_nido() { _write_focal "$1"; }

@test "11. frontera switches: 2 → OK, 3 → HIGH" {
  _switches 2
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
  _switches 1
  run bash "$FOCAL_CHECKIN" --load
  [ "$output" = "HIGH" ]
}

@test "12. frontera switches: 5 → HIGH (no OVERLOAD)" {
  _switches 5
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "HIGH" ]
}

@test "13. frontera decisiones: 2 → OK, 3 → HIGH, 5 → HIGH, 6 → OVERLOAD" {
  _write_decision_nido d1; _write_decision_nido d2
  run bash "$FOCAL_CHECKIN" --load
  [ "$output" = "OK" ]
  _write_decision_nido d3
  run bash "$FOCAL_CHECKIN" --load
  [ "$output" = "HIGH" ]
  _write_decision_nido d4; _write_decision_nido d5
  run bash "$FOCAL_CHECKIN" --load
  [ "$output" = "HIGH" ]
  _write_decision_nido d6
  run bash "$FOCAL_CHECKIN" --load
  [ "$output" = "OVERLOAD" ]
}

@test "14. negativo: nidos con next_human_decision null no cuentan como decisión" {
  for i in 1 2 3 4 5 6 7; do _null_decision_nido "n$i"; done
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "15. negativo: líneas vacías o con fecha ilegible en .switch-log no cuentan" {
  printf '\nbasura nidoA→nidoB\nno-es-fecha x\n\n' > "$HOME/.savia/.switch-log"
  _switches 2
  run bash "$FOCAL_CHECKIN" --load
  [ "$output" = "OK" ]
}

@test "16. heartbeat: fija updated_at a ahora y session_pid nuevo, conserva el resto" {
  _write_focal "hb"
  local f="$HOME/.savia/focal-state/hb.json"
  sed -i 's/"updated_at": "[^"]*"/"updated_at": "2000-01-01T00:00:00Z"/' "$f"
  run bash "$FOCAL_CHECKIN" --nido hb
  [ "$status" -eq 0 ]
  [[ "$output" == "Check-in registrado para hb"* ]]
  python3 - "$f" <<'P'
import json, sys, datetime
d = json.load(open(sys.argv[1]))
ts = datetime.datetime.strptime(d["updated_at"], "%Y-%m-%dT%H:%M:%SZ")
assert abs((datetime.datetime.utcnow() - ts).total_seconds()) < 120, d["updated_at"]
assert d["session_pid"] != 9999
assert d["task"] == "test" and d["check_in_interval_min"] == 10 and d["created_at"] != "2000-01-01T00:00:00Z"
P
}

@test "17. heartbeat sobre nido inexistente crea un estado JSON mínimo válido" {
  run bash "$FOCAL_CHECKIN" --nido nuevo
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["nido"]=="nuevo" and d["updated_at"] and isinstance(d["session_pid"], int)' \
    "$HOME/.savia/focal-state/nuevo.json"
}

@test "18. heartbeat sobre JSON con nido pero sin updated_at lo añade" {
  printf '{"nido":"parcial","task":"t"}\n' > "$HOME/.savia/focal-state/parcial.json"
  run bash "$FOCAL_CHECKIN" --nido parcial
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["task"]=="t" and "updated_at" in d and "session_pid" in d' \
    "$HOME/.savia/focal-state/parcial.json"
}

@test "19. --set-interval inserta el campo si no existía y conserva el resto" {
  printf '{"nido":"sinint","task":"t"}\n' > "$HOME/.savia/focal-state/sinint.json"
  run bash "$FOCAL_CHECKIN" --set-interval 7 --nido sinint
  [ "$status" -eq 0 ]
  [[ "$output" == *"actualizado a 7 para sinint"* ]]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["check_in_interval_min"]==7 and d["task"]=="t"' \
    "$HOME/.savia/focal-state/sinint.json"
}

@test "20. error: --set-interval sin --nido sale 1 y no escribe nada" {
  run bash "$FOCAL_CHECKIN" --set-interval 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"requiere --nido"* ]]
  [ -z "$(ls -A "$HOME/.savia/focal-state")" ]
}

@test "21. error: sin argumentos sale 1 con uso" {
  run bash "$FOCAL_CHECKIN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"especifica --nido"* ]]
}

@test "22. negativo: --nido con ruta (../) se rechaza y no escribe fuera de focal-state" {
  run bash "$FOCAL_CHECKIN" --nido ../../escapa
  [ "$status" -eq 1 ]
  [[ "$output" == *"no válido"* ]]
  [ ! -e "$HOME/escapa.json" ]
  [ ! -e "$HOME/.savia/escapa.json" ]
}

@test "23. negativo: --set-interval no numérico se rechaza y no toca el estado" {
  _write_focal "intv"
  local before; before=$(cat "$HOME/.savia/focal-state/intv.json")
  for bad in 'x/' '0' '-3' '10000' '5;rm'; do
    run bash "$FOCAL_CHECKIN" --set-interval "$bad" --nido intv
    [ "$status" -eq 1 ]
    [[ "$output" == *"entero"* ]]
  done
  [ "$(cat "$HOME/.savia/focal-state/intv.json")" = "$before" ]
}

@test "24. límite: --set-interval 9999 se acepta" {
  _write_focal "maxint"
  run bash "$FOCAL_CHECKIN" --set-interval 9999 --nido maxint
  [ "$status" -eq 0 ]
  grep -q '"check_in_interval_min": 9999' "$HOME/.savia/focal-state/maxint.json"
}

@test "25. lock ocupado: heartbeat y set-interval salen 1 sin escribir" {
  command -v flock >/dev/null || skip "sin flock"
  _write_focal "lk"
  local before; before=$(cat "$HOME/.savia/focal-state/lk.json")
  # El propio proceso del test retiene el lock en el fd 9: sin proceso en
  # segundo plano que pueda quedar huérfano. El script abre su propio fd sobre
  # el fichero (otra descripción de fichero), así que choca con este lock.
  exec 9>"$HOME/.savia/focal-state.lock"
  flock -n 9
  run bash "$FOCAL_CHECKIN" --nido lk
  [ "$status" -eq 1 ]
  [[ "$output" == *"flock timeout"* ]]
  [[ "$output" != *"registrado"* ]]
  run bash "$FOCAL_CHECKIN" --set-interval 3 --nido lk
  [ "$status" -eq 1 ]
  [[ "$output" != *"actualizado"* ]]
  exec 9>&-
  [ "$(cat "$HOME/.savia/focal-state/lk.json")" = "$before" ]
  # Liberado el lock, el heartbeat vuelve a funcionar (el bloqueo era el lock).
  run bash "$FOCAL_CHECKIN" --nido lk
  [ "$status" -eq 0 ]
}

_read_state() {
  python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True))' \
    "$HOME/.savia/focal-state/$1.json"
}

_fail_command() {
  mkdir -p "$TEST_FOCAL_DIR/bin"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_FOCAL_DIR/bin/$1"
  chmod +x "$TEST_FOCAL_DIR/bin/$1"
  export PATH="$TEST_FOCAL_DIR/bin:$PATH"
}

_fixed_clock() {
  mkdir -p "$TEST_FOCAL_DIR/bin"
  # Las fechas del log siguen usando GNU date; solo se fija el presente.
  cat > "$TEST_FOCAL_DIR/bin/date" <<'SH'
#!/bin/sh
if [ "$*" = '+%s' ]; then
  echo 1793880000
else
  exec /usr/bin/date "$@"
fi
SH
  chmod +x "$TEST_FOCAL_DIR/bin/date"
  export PATH="$TEST_FOCAL_DIR/bin:$PATH"
}

@test "intervalo en nido nuevo crea un objeto JSON válido con identidad" {
  run bash "$FOCAL_CHECKIN" --set-interval 25 --nido nuevo
  [ "$status" -eq 0 ]
  run _read_state nuevo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"check_in_interval_min": 25'* ]]
  [[ "$output" == *'"nido": "nuevo"'* ]]
}

@test "latido añade pid ausente aunque el estado ya tenga updated_at" {
  printf '{"nido":"parcial","updated_at":"2000-01-01T00:00:00Z","task":"conservar"}\n' \
    > "$HOME/.savia/focal-state/parcial.json"
  run bash "$FOCAL_CHECKIN" --nido parcial
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["session_pid"]>0; assert d["task"]=="conservar"; assert d["updated_at"]!="2000-01-01T00:00:00Z"' \
    "$HOME/.savia/focal-state/parcial.json"
  [ "$status" -eq 0 ]
}

@test "intervalo añade updated_at ausente y conserva la decisión anidada" {
  printf '{"nido":"parcial","check_in_interval_min":10,"next_human_decision":{"description":"revisar","blocking":true}}\n' \
    > "$HOME/.savia/focal-state/parcial.json"
  run bash "$FOCAL_CHECKIN" --set-interval 30 --nido parcial
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["updated_at"]; assert d["check_in_interval_min"]==30; assert d["next_human_decision"]=={"description":"revisar","blocking":True}' \
    "$HOME/.savia/focal-state/parcial.json"
  [ "$status" -eq 0 ]
}

@test "error de flock impide anunciar éxito y deja intacto el estado" {
  _write_focal bloqueado
  local before; before=$(cat "$HOME/.savia/focal-state/bloqueado.json")
  _fail_command flock
  for mode in heartbeat interval; do
    if [[ "$mode" == heartbeat ]]; then
      run bash "$FOCAL_CHECKIN" --nido bloqueado
    else
      run bash "$FOCAL_CHECKIN" --nido bloqueado --set-interval 25
    fi
    [ "$status" -ne 0 ]
    [[ "$output" != *"registrado"* && "$output" != *"actualizado"* ]]
    [ "$(cat "$HOME/.savia/focal-state/bloqueado.json")" = "$before" ]
  done
}

@test "error de escritura no anuncia éxito" {
  mkdir "$HOME/.savia/focal-state/directorio.json"
  run bash "$FOCAL_CHECKIN" --nido directorio
  [ "$status" -ne 0 ]
  [[ "$output" != *"registrado"* ]]
}

@test "error al crear el directorio de estado aborta incluso en lectura de carga" {
  _fail_command mkdir
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -ne 0 ]
  [[ "$output" != "OK" ]]
}

@test "argumento sin valor produce diagnóstico controlado" {
  for flag in --nido --set-interval; do
    run bash "$FOCAL_CHECKIN" "$flag"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR:"* ]]
    [[ "$output" != *"unbound variable"* ]]
  done
}

@test "intervalo inválido no modifica el estado existente" {
  _write_focal valido
  local before; before=$(cat "$HOME/.savia/focal-state/valido.json")
  for value in '' 0 -1 1.5 texto 01 '5,"inject":true'; do
    run bash "$FOCAL_CHECKIN" --nido valido --set-interval "$value"
    [ "$status" -ne 0 ]
    [ "$(cat "$HOME/.savia/focal-state/valido.json")" = "$before" ]
  done
}

@test "nombre inválido no permite salir del directorio focal" {
  for name in '../fuera' '/absoluto' '' 'linea
rota'; do
    run bash "$FOCAL_CHECKIN" --nido "$name"
    [ "$status" -ne 0 ]
  done
  [ ! -e "$HOME/.savia/fuera.json" ]
}

@test "opción desconocida se rechaza sin crear estado" {
  run bash "$FOCAL_CHECKIN" --nido nuevo --desconocido
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.savia/focal-state/nuevo.json" ]
}

@test "límites de carga con dos tres cinco y seis cambios" {
  _fixed_clock
  local n expected i
  for n in 2 3 5 6; do
    : > "$HOME/.savia/.switch-log"
    for ((i=0; i<n; i++)); do
      printf '2026-11-05T11:30:00Z a→b\n' >> "$HOME/.savia/.switch-log"
    done
    case "$n" in 2) expected=OK ;; 3|5) expected=HIGH ;; 6) expected=OVERLOAD ;; esac
    run bash "$FOCAL_CHECKIN" --load
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
  done
}

@test "límite de ventana incluye una hora exacta y excluye futuro y anterior" {
  _fixed_clock
  # Dos cambios dentro y uno justo en el límite: HIGH.
  printf '2026-11-05T11:30:00Z a→b\n2026-11-05T11:30:00Z a→b\n2026-11-05T11:00:00Z a→b\n' \
    > "$HOME/.savia/.switch-log"
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = HIGH ]
  printf '2026-11-05T11:30:00Z a→b\n2026-11-05T11:30:00Z a→b\n2026-11-05T10:59:59Z a→b\n2026-11-05T12:00:01Z a→b\nincorrecto a→b\n' \
    > "$HOME/.savia/.switch-log"
  run bash "$FOCAL_CHECKIN" --load
  [ "$status" -eq 0 ]
  [ "$output" = OK ]
}

@test "límites de decisiones con dos tres cinco y seis pendientes" {
  local n expected i
  for n in 2 3 5 6; do
    for ((i=1; i<=n; i++)); do _write_decision_nido "decision-$i"; done
    case "$n" in 2) expected=OK ;; 3|5) expected=HIGH ;; 6) expected=OVERLOAD ;; esac
    run bash "$FOCAL_CHECKIN" --load
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
  done
}

@test "estado ausente permite latido válido con nombre habitual" {
  run bash "$FOCAL_CHECKIN" --nido nido_1-prueba.2
  [ "$status" -eq 0 ]
  run _read_state nido_1-prueba.2
  [ "$status" -eq 0 ]
  [[ "$output" == *'"nido": "nido_1-prueba.2"'* ]]
  [[ "$output" == *'"session_pid":'* ]]
}

@test "estado con campo escalar inválido falla sin reescribir el fichero" {
  local state before
  state="$HOME/.savia/focal-state/invalido.json"
  for before in '{"nido":"invalido","session_pid":null}' \
    '{"nido":"invalido","session_pid":1.5}' \
    '{"nido":"invalido","updated_at":null}' 'no es un objeto'; do
    printf '%s\n' "$before" > "$state"
    run bash "$FOCAL_CHECKIN" --nido invalido
    [ "$status" -ne 0 ]
    [ "$(cat "$state")" = "$before" ]
  done
}

@test "lectura tras el bloqueo conserva un cambio anterior a obtener el lock" {
  _write_focal actualizado
  mkdir -p "$TEST_FOCAL_DIR/bin"
  # Intercalar una escritura justo donde se adquiere el lock, sin carreras
  # temporales: leer antes de flock perdería este valor.
  cat > "$TEST_FOCAL_DIR/bin/flock" <<'SH'
#!/bin/sh
sed -i 's/"task": "test"/"task": "cambio reciente"/' "$HOME/.savia/focal-state/actualizado.json"
SH
  chmod +x "$TEST_FOCAL_DIR/bin/flock"
  run env PATH="$TEST_FOCAL_DIR/bin:$PATH" bash "$FOCAL_CHECKIN" --nido actualizado
  [ "$status" -eq 0 ]
  run _read_state actualizado
  [ "$status" -eq 0 ]
  [[ "$output" == *'"task": "cambio reciente"'* ]]
}
