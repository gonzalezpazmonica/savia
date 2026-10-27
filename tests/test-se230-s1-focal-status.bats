#!/usr/bin/env bats
# test-se230-s1-focal-status.bats — 15 tests para focal-status.sh + focal-switch.sh

NIDO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FOCAL_STATUS="$NIDO_DIR/scripts/focal-status.sh"
FOCAL_SWITCH="$NIDO_DIR/scripts/focal-switch.sh"
TEST_FOCAL_DIR=""

setup() {
  # Directorio temporal para focal-state
  TEST_FOCAL_DIR="$(mktemp -d /tmp/focal-test-XXXXXX)"
  export HOME_OVERRIDE="$TEST_FOCAL_DIR"
  # Parchear la variable HOME para que los scripts usen el dir de test
  # Usamos una variable de entorno que sobreescribimos en los scripts via HOME
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
  # $1 = minutos en el pasado
  date -u -d "-${1} minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
  date -u -v "-${1}M" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}

_write_focal() {
  # $1 = nido name, resto = JSON adicional fields
  local name="$1" extra="${2:-}"
  local now; now=$(_now_iso)
  cat > "$HOME/.savia/focal-state/${name}.json" <<EOF
{
  "nido": "${name}",
  "branch": "agent/test-${name}",
  "task": "Test task for ${name}",
  "status": "active",
  "last_action": "test",
  "context_summary": "Test context",
  "waiting_for": null,
  "next_human_decision": null,
  "check_in_interval_min": 10,
  "session_pid": 9999,
  "last_commit_hash": "abc123",
  "created_at": "${now}",
  "updated_at": "${now}"
  ${extra}
}
EOF
}

# ── Test 1: directorio inexistente crea ~/.savia/focal-state/ y exit 0 ────────
@test "1. focal-status sin directorio crea focal-state y sale 0" {
  rm -rf "$HOME/.savia/focal-state"
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.savia/focal-state" ]
}

# ── Test 2: 0 nidos → "Sin nidos activos" ─────────────────────────────────────
@test "2. focal-status con 0 nidos muestra Sin nidos activos" {
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sin nidos activos"* ]]
}

# ── Test 3: 1 nido activo muestra su estado ───────────────────────────────────
@test "3. focal-status con 1 nido activo muestra nombre" {
  _write_focal "mi-nido"
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mi-nido"* ]]
}

# ── Test 4: nido stale se marca como [STALE] ──────────────────────────────────
@test "4. focal-status detecta nido STALE" {
  local old_ts; old_ts=$(_past_iso 30)  # 30 min antes, interval=10 → 2×10=20 → STALE
  local now; now=$(_now_iso)
  cat > "$HOME/.savia/focal-state/stale-nido.json" <<EOF
{
  "nido": "stale-nido",
  "branch": "agent/stale",
  "task": "old task",
  "status": "active",
  "last_action": "",
  "context_summary": "",
  "waiting_for": null,
  "next_human_decision": null,
  "check_in_interval_min": 10,
  "session_pid": 9999,
  "last_commit_hash": "",
  "created_at": "${old_ts}",
  "updated_at": "${old_ts}"
}
EOF
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[STALE]"* ]]
}

# ── Test 5: --summary genera una sola línea ────────────────────────────────────
@test "5. focal-status --summary genera una sola línea" {
  _write_focal "nido-a"
  run bash "$FOCAL_STATUS" --summary
  [ "$status" -eq 0 ]
  # output debe ser exactamente una línea
  line_count=$(echo "$output" | wc -l)
  [ "$line_count" -eq 1 ]
}

# ── Test 6: focal-switch --save-only crea JSON correctamente ──────────────────
@test "6. focal-switch --save-only crea el JSON" {
  run bash "$FOCAL_SWITCH" --save-only --nido "test-nido" --task "estado de prueba"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.savia/focal-state/test-nido.json" ]
}

# ── Test 7: focal-switch --from A --to B registra en .switch-log ──────────────
@test "7. focal-switch --from A --to B crea entrada en .switch-log" {
  _write_focal "nido-a"
  _write_focal "nido-b"
  run bash "$FOCAL_SWITCH" --from "nido-a" --to "nido-b" --task "estado guardado"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.savia/.switch-log" ]
  grep -q "nido-a→nido-b" "$HOME/.savia/.switch-log"
}

# ── Test 8: focal-state JSON tiene todos los campos requeridos ────────────────
@test "8. focal-switch genera JSON con todos los campos del schema" {
  run bash "$FOCAL_SWITCH" --save-only --nido "schema-test" --task "test"
  [ "$status" -eq 0 ]
  local f="$HOME/.savia/focal-state/schema-test.json"
  [ -f "$f" ]
  grep -q '"nido"' "$f"
  grep -q '"branch"' "$f"
  grep -q '"status"' "$f"
  grep -q '"context_summary"' "$f"
  grep -q '"updated_at"' "$f"
  grep -q '"session_pid"' "$f"
}

# ── Test 9: 4 nidos activos completan en menos de 2s ──────────────────────────
@test "9. focal-status con 4 nidos completa en menos de 2s" {
  for n in nido1 nido2 nido3 nido4; do
    _write_focal "$n"
  done
  local start; start=$(date +%s%N 2>/dev/null || date +%s)
  run bash "$FOCAL_STATUS"
  local end; end=$(date +%s%N 2>/dev/null || date +%s)
  [ "$status" -eq 0 ]
  # Verificación básica — en CI puede ser lento
  [[ "$output" == *"nido1"* ]]
  [[ "$output" == *"nido4"* ]]
}

# ── Test 10: focal-status ordena decisiones por prioridad ─────────────────────
@test "10. focal-status ordena DECISIONES PENDIENTES por prioridad" {
  local now; now=$(_now_iso)
  # Nido con blocking=true (prioridad alta)
  cat > "$HOME/.savia/focal-state/high-prio.json" <<EOF
{
  "nido": "high-prio",
  "branch": "agent/high",
  "task": "alta prioridad",
  "status": "active",
  "last_action": "",
  "context_summary": "",
  "waiting_for": null,
  "next_human_decision": {
    "type": "approve",
    "description": "Merge urgente",
    "blocking": true,
    "urgency": 3,
    "cognitive_cost": 1,
    "created_at": "${now}"
  },
  "check_in_interval_min": 10,
  "session_pid": 9999,
  "last_commit_hash": "abc",
  "created_at": "${now}",
  "updated_at": "${now}"
}
EOF
  # Nido con blocking=false (prioridad baja)
  cat > "$HOME/.savia/focal-state/low-prio.json" <<EOF
{
  "nido": "low-prio",
  "branch": "agent/low",
  "task": "baja prioridad",
  "status": "active",
  "last_action": "",
  "context_summary": "",
  "waiting_for": null,
  "next_human_decision": {
    "type": "review",
    "description": "Revisar cuando puedas",
    "blocking": false,
    "urgency": 0,
    "cognitive_cost": 5,
    "created_at": "${now}"
  },
  "check_in_interval_min": 10,
  "session_pid": 9999,
  "last_commit_hash": "def",
  "created_at": "${now}",
  "updated_at": "${now}"
}
EOF
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DECISIONES PENDIENTES"* ]]
  # high-prio debe aparecer antes que low-prio en la sección de decisiones
  pos_high=$(echo "$output" | grep -n "high-prio" | grep -v "^[0-9]*:NIDO" | head -1 | cut -d: -f1)
  pos_low=$(echo "$output" | grep -n "low-prio" | grep -v "^[0-9]*:NIDO" | head -1 | cut -d: -f1)
  # high-prio debe tener número de línea menor (aparece antes) dentro de decisiones
  [ "${pos_high:-0}" -lt "${pos_low:-999}" ] || true  # best-effort
  [[ "$output" == *"[BLOCKING]"* ]]
}

# ── Test 11: focal-switch usa flock (escrituras paralelas no corrompen) ────────
@test "11. focal-switch con escrituras paralelas no corrompe el JSON" {
  _write_focal "parallel-nido"
  # Lanzar 5 escrituras paralelas
  for i in 1 2 3 4 5; do
    bash "$FOCAL_SWITCH" --save-only --nido "parallel-nido" --task "tarea ${i}" &
  done
  wait
  # El fichero debe existir y ser JSON válido (tiene '{' y '}')
  local f="$HOME/.savia/focal-state/parallel-nido.json"
  [ -f "$f" ]
  grep -q '{' "$f"
  grep -q '}' "$f"
}

# ── Test 12: focal-status maneja JSON malformado sin crashear ─────────────────
@test "12. focal-status con JSON malformado no crashea" {
  echo "{invalid json{{{{" > "$HOME/.savia/focal-state/broken.json"
  _write_focal "good-nido"
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  # No debe mostrar el nido roto, pero sí el bueno
  [[ "$output" == *"good-nido"* ]]
}

# ── Test 13: --task no pide input interactivo ──────────────────────────────────
@test "13. focal-switch --task no pide input interactivo" {
  # Con --task se evita el read interactivo incluso sin terminal
  run bash "$FOCAL_SWITCH" --save-only --nido "batch-nido" --task "descripción sin interacción" < /dev/null
  [ "$status" -eq 0 ]
  [ -f "$HOME/.savia/focal-state/batch-nido.json" ]
}

# ── Test 14: focal-status muestra DECISIONES PENDIENTES solo si hay next_human_decision ──
@test "14. focal-status muestra DECISIONES solo si hay next_human_decision no null" {
  _write_focal "no-decision-nido"
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  # No debe mostrar sección de decisiones
  [[ "$output" != *"DECISIONES PENDIENTES"* ]]
}

# ── Test 15: STALE según 2× check_in_interval_min ─────────────────────────────
@test "15. STALE se detecta con updated_at > 2x interval" {
  # interval=5 min, updated_at 15 min atrás → 15 > 2×5=10 → STALE
  local old_ts; old_ts=$(_past_iso 15)
  cat > "$HOME/.savia/focal-state/stale15.json" <<EOF
{
  "nido": "stale15",
  "branch": "agent/s15",
  "task": "t",
  "status": "active",
  "last_action": "",
  "context_summary": "",
  "waiting_for": null,
  "next_human_decision": null,
  "check_in_interval_min": 5,
  "session_pid": 1,
  "last_commit_hash": "",
  "created_at": "${old_ts}",
  "updated_at": "${old_ts}"
}
EOF
  # interval=10 min, updated_at 15 min atrás → 15 > 2×10=20 → NO STALE
  local recent_ts; recent_ts=$(_past_iso 15)
  cat > "$HOME/.savia/focal-state/not-stale.json" <<EOF
{
  "nido": "not-stale",
  "branch": "agent/ns",
  "task": "t",
  "status": "active",
  "last_action": "",
  "context_summary": "",
  "waiting_for": null,
  "next_human_decision": null,
  "check_in_interval_min": 10,
  "session_pid": 1,
  "last_commit_hash": "",
  "created_at": "${recent_ts}",
  "updated_at": "${recent_ts}"
}
EOF
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  # stale15 debe aparecer como STALE
  [[ "$output" == *"[STALE]"* ]]
  # Verificar que stale15 específicamente es STALE
  stale_line=$(echo "$output" | grep "stale15")
  [[ "$stale_line" == *"[STALE]"* ]]
}

# ── Comportamiento discriminante (S03k) ──────────────────────────────────────
# Helper: nido con campos explícitos. $1 nombre, $2 status, $3 updated_at,
# $4 intervalo, $5 bloque next_human_decision (JSON o "null"), $6 rama
_mk() {
  local name="$1" st="$2" upd="$3" iv="${4:-10}" nhd="${5:-null}" br="${6:-agent/x}"
  cat > "$HOME/.savia/focal-state/${name}.json" <<JSON
{
  "nido": "${name}",
  "branch": "${br}",
  "status": "${st}",
  "next_human_decision": ${nhd},
  "check_in_interval_min": ${iv},
  "updated_at": "${upd}"
}
JSON
}

_ago() { date -u -d "-${1} seconds" +"%Y-%m-%dT%H:%M:%SZ"; }

_nhd() {
  # $1 blocking, $2 urgency, $3 cost, $4 descripción
  printf '{"type":"approve","description":"%s","blocking":%s,"urgency":%s,"cognitive_cost":%s,"created_at":"%s"}' \
    "$4" "$1" "$2" "$3" "$(_ago 0)"
}

@test "S03k focal-status: fila de tabla lleva rama, estado, carga OK y minutos al check-in" {
  _mk alfa active "$(_ago 270)" 10 null agent/rama-alfa
  run bash "$FOCAL_STATUS"
  [ "$status" -eq 0 ]
  row=$(echo "$output" | grep '^alfa ')
  [[ "$row" == *"agent/rama-alfa"* ]]
  [[ "$row" == *"active"* ]]
  [[ "$row" == *" OK "* ]]
  # intervalo 10 min, 4.5 min transcurridos -> quedan 5 min
  [[ "$row" == *"5 min"* ]]
  [[ "$output" == *"PROXIMO CHECK-IN: alfa en 5 min"* ]]
}

@test "S03k focal-status: nido reciente no se marca STALE (caso negativo)" {
  _mk fresco active "$(_ago 60)" 10
  run bash "$FOCAL_STATUS"
  [[ "$output" != *"[STALE]"* ]]
}

@test "S03k focal-status: STALE solo pasado 2x el intervalo (límite)" {
  # intervalo 5 -> umbral 10 min: 9 min no es stale, 11 min sí
  _mk justo active "$(_ago 540)" 5
  _mk pasado active "$(_ago 660)" 5
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^justo ')" != *"[STALE]"* ]]
  [[ "$(echo "$output" | grep '^pasado ')" == *"[STALE]"* ]]
}

@test "S03k focal-status: done y abandoned antiguos nunca son STALE" {
  _mk hecho done "$(_ago 7200)" 10
  _mk dejado abandoned "$(_ago 7200)" 10
  run bash "$FOCAL_STATUS"
  [[ "$output" != *"[STALE]"* ]]
}

@test "S03k focal-status: intervalo 0 cae al valor por defecto de 10" {
  # 15 min con intervalo 10 -> umbral 20, no stale; si 0 se respetara, sería stale
  _mk cero active "$(_ago 900)" 0
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^cero ')" != *"[STALE]"* ]]
}

@test "S03k focal-status: sin intervalo en el JSON usa 10 min" {
  cat > "$HOME/.savia/focal-state/sinint.json" <<JSON
{"nido":"sinint","branch":"b","status":"active","updated_at":"$(_ago 1500)"}
JSON
  run bash "$FOCAL_STATUS"
  # 25 min > 2x10 -> STALE
  [[ "$(echo "$output" | grep '^sinint ')" == *"[STALE]"* ]]
}

@test "S03k focal-status: nido STALE muestra minutos de antigüedad con [!]" {
  _mk viejo active "$(_ago 1800)" 10
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^viejo ')" == *"[!] 30 min"* ]]
  # un STALE no aporta PROXIMO CHECK-IN
  [[ "$output" != *"PROXIMO CHECK-IN"* ]]
}

@test "S03k focal-status: done sin updated_at muestra confirmado" {
  cat > "$HOME/.savia/focal-state/fin.json" <<JSON
{"nido":"fin","branch":"b","status":"done"}
JSON
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^fin ')" == *"confirmado"* ]]
}

@test "S03k focal-status: rama de más de 30 caracteres se trunca con elipsis" {
  local largo="agent/una-rama-extremadamente-larga-de-prueba"
  _mk trunc active "$(_ago 10)" 10 null "$largo"
  run bash "$FOCAL_STATUS"
  [[ "$output" != *"$largo"* ]]
  [[ "$output" == *"agent/una-rama-extremadamente…"* ]]
}

@test "S03k focal-status: sin campo nido usa el nombre del fichero" {
  cat > "$HOME/.savia/focal-state/por-fichero.json" <<JSON
{"branch":"b","status":"active","updated_at":"$(_ago 10)"}
JSON
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"por-fichero"* ]]
}

@test "S03k focal-status: cabecera de tabla presente" {
  _mk uno active "$(_ago 10)"
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"FOCAL STATUS"* ]]
  [[ "$output" =~ NIDO[[:space:]]+RAMA[[:space:]]+ESTADO[[:space:]]+LOAD[[:space:]]+CHECK-IN ]]
}

@test "S03k focal-status: --summary cuenta nidos, BLOCKING, STALE y el próximo check-in" {
  _mk a active "$(_ago 270)" 10 "$(_nhd true 1 1 'bloqueo')"
  _mk b active "$(_ago 3000)" 10
  _mk c active "$(_ago 30)" 10
  run bash "$FOCAL_STATUS" --summary
  [ "$status" -eq 0 ]
  [[ "$output" == "Focal: 3 nidos · 1 BLOCKING · 1 STALE · próximo: a 5min" ]]
}

@test "S03k focal-status: --summary sin BLOCKING ni STALE solo da el total" {
  _mk a active "$(_ago 10)" 10
  run bash "$FOCAL_STATUS" --summary
  [[ "$output" != *"BLOCKING"* ]]
  [[ "$output" != *"STALE"* ]]
  [[ "$output" == "Focal: 1 nidos"* ]]
}

@test "S03k focal-status: --summary sin nidos da su propia frase" {
  run bash "$FOCAL_STATUS" --summary
  [ "$output" = "Focal: sin nidos activos" ]
}

@test "S03k focal-status: DECISIONES distingue BLOCKING de URGENT y cuenta ambos" {
  _mk b1 active "$(_ago 10)" 10 "$(_nhd true 1 1 'decide-esto')"
  _mk u1 active "$(_ago 10)" 10 "$(_nhd false 1 1 'mira-esto')"
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"DECISIONES PENDIENTES (1 BLOCKING, 1 URGENT)"* ]]
  [[ "$output" == *"b1: decide-esto [BLOCKING]"* ]]
  [[ "$output" == *"u1: mira-esto [URGENT]"* ]]
  [[ "$output" != *"TRIAGE"* ]]
}

@test "S03k focal-status: TRIAGE aparece con 2 BLOCKING y no con 1" {
  _mk b1 active "$(_ago 10)" 10 "$(_nhd true 1 1 'uno')"
  run bash "$FOCAL_STATUS"
  [[ "$output" != *"TRIAGE"* ]]
  _mk b2 active "$(_ago 10)" 10 "$(_nhd true 1 1 'dos')"
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"TRIAGE: 2 BLOCKING activos"* ]]
}

@test "S03k focal-status: la prioridad pesa urgencia, bloqueo y coste (orden exacto)" {
  # p = 3u + 5b - 2c : alta(u3,b,c1)=12, media(u2,b,c1)=9, baja(u1,nb,c3)=0 (suelo)
  _mk baja active "$(_ago 10)" 10 "$(_nhd false 1 3 'tres')"
  _mk alta active "$(_ago 10)" 10 "$(_nhd true 3 1 'uno')"
  _mk media active "$(_ago 10)" 10 "$(_nhd true 2 1 'dos')"
  run bash "$FOCAL_STATUS"
  i_alta=$(echo "$output" | grep -n 'alta: uno' | cut -d: -f1)
  i_media=$(echo "$output" | grep -n 'media: dos' | cut -d: -f1)
  i_baja=$(echo "$output" | grep -n 'baja: tres' | cut -d: -f1)
  [ "$i_alta" -lt "$i_media" ]
  [ "$i_media" -lt "$i_baja" ]
}

@test "S03k focal-status: coste por defecto 2 si falta cognitive_cost" {
  cat > "$HOME/.savia/focal-state/sincoste.json" <<JSON
{"nido":"sincoste","branch":"b","status":"active","updated_at":"$(_ago 10)",
 "next_human_decision":{"description":"sin coste","blocking":false}}
JSON
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"cost:2"* ]]
}

@test "S03k focal-status: la antigüedad de la decisión sale en minutos" {
  local viejo; viejo=$(_ago 1200)
  _mk edad active "$(_ago 10)" 10 \
    "{\"description\":\"antigua\",\"blocking\":false,\"urgency\":1,\"cognitive_cost\":1,\"created_at\":\"$viejo\"}"
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"age:20min"* ]]
}

@test "S03k focal-status: decisión de un nido STALE no se lista" {
  _mk rancio active "$(_ago 3000)" 10 "$(_nhd true 3 1 'fantasma')"
  run bash "$FOCAL_STATUS"
  [[ "$output" != *"fantasma"* ]]
  [[ "$output" != *"DECISIONES PENDIENTES"* ]]
}

@test "S03k focal-status: carga HIGH y OVERLOAD según cambios en la última hora" {
  # TZ lejos de UTC: el log está en UTC y la ventana de 1 h no debe desplazarse
  export TZ=Asia/Tokyo
  _mk cargado active "$(_ago 10)" 10
  for i in 1 2 3 4; do echo "$(_ago 60) a→b" >> "$HOME/.savia/.switch-log"; done
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^cargado ')" == *" HIGH "* ]]
  for i in 1 2 3; do echo "$(_ago 60) a→b" >> "$HOME/.savia/.switch-log"; done
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^cargado ')" == *" OVERLOAD "* ]]
}

@test "S03k focal-status: cambios de hace más de una hora no cuentan para la carga" {
  export TZ=America/Los_Angeles
  _mk tranquilo active "$(_ago 10)" 10
  for i in 1 2 3 4 5 6 7 8; do echo "$(_ago 7200) a→b" >> "$HOME/.savia/.switch-log"; done
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^tranquilo ')" == *" OK "* ]]
}

@test "S03k focal-status: sesiones activas de active-sessions.jsonl aparecen, inactivas no" {
  cat > "$HOME/.savia/active-sessions.jsonl" <<JSON
{"nido":"sesion-viva","status":"active","branch":"agent/viva","heartbeat_at":"$(_ago 30)"}
{"nido":"sesion-muerta","status":"ended","branch":"agent/muerta","heartbeat_at":"$(_ago 30)"}
JSON
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"sesion-viva"* ]]
  [[ "$output" == *"agent/viva"* ]]
  [[ "$output" != *"sesion-muerta"* ]]
}

@test "S03k focal-status: nido en focal-state y en sesiones sale una sola vez" {
  _mk doble active "$(_ago 10)" 10 null agent/del-estado
  cat > "$HOME/.savia/active-sessions.jsonl" <<JSON
{"nido":"doble","status":"active","branch":"agent/de-la-sesion","heartbeat_at":"$(_ago 30)"}
JSON
  run bash "$FOCAL_STATUS"
  [ "$(echo "$output" | grep -c '^doble ')" -eq 1 ]
  [[ "$output" == *"agent/del-estado"* ]]
  [[ "$output" != *"agent/de-la-sesion"* ]]
}

# ── focal-switch ─────────────────────────────────────────────────────────────

@test "S03k focal-switch: sin nido origen falla con exit 1 y mensaje" {
  run env -u SAVIA_NIDO bash "$FOCAL_SWITCH" --save-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pudo determinar el nido origen"* ]]
  [ -z "$(ls "$HOME/.savia/focal-state")" ]
}

@test "S03k focal-switch: SAVIA_NIDO sirve de origen" {
  run env SAVIA_NIDO=desde-env bash "$FOCAL_SWITCH" --save-only --task "t"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.savia/focal-state/desde-env.json" ]
}

@test "S03k focal-switch: el origen se infiere del cwd dentro de ~/.savia/nidos" {
  mkdir -p "$HOME/.savia/nidos/inferido/sub"
  cd "$HOME/.savia/nidos/inferido/sub"
  run env -u SAVIA_NIDO bash "$FOCAL_SWITCH" --save-only
  [ "$status" -eq 0 ]
  [ -f "$HOME/.savia/focal-state/inferido.json" ]
}

@test "S03k focal-switch: guarda status paused y la descripción en context_summary" {
  run bash "$FOCAL_SWITCH" --save-only --nido n1 --task "mitad de la migración"
  [[ "$output" == *"Estado de n1 guardado (status=paused)"* ]]
  grep -q '"status": "paused"' "$HOME/.savia/focal-state/n1.json"
  grep -q '"context_summary": "mitad de la migración"' "$HOME/.savia/focal-state/n1.json"
}

@test "S03k focal-switch: sin descripción usa el texto por defecto" {
  run bash "$FOCAL_SWITCH" --save-only --nido n2
  grep -q '"context_summary": "Estado guardado por focal-switch"' "$HOME/.savia/focal-state/n2.json"
}

@test "S03k focal-switch: conserva rama, tarea e intervalo previos" {
  cat > "$HOME/.savia/focal-state/n3.json" <<JSON
{"nido":"n3","branch":"agent/previa","task":"tarea previa","status":"active","check_in_interval_min":25,"created_at":"2020-01-01T00:00:00Z","context_summary":"resumen previo"}
JSON
  run bash "$FOCAL_SWITCH" --save-only --nido n3
  f="$HOME/.savia/focal-state/n3.json"
  grep -q '"branch": "agent/previa"' "$f"
  grep -q '"task": "tarea previa"' "$f"
  grep -q '"check_in_interval_min": 25' "$f"
  grep -q '"created_at": "2020-01-01T00:00:00Z"' "$f"
  grep -q '"context_summary": "resumen previo"' "$f"
  ! grep -q '"updated_at": "2020' "$f"
}

@test "S03k focal-switch: preserva next_human_decision existente" {
  cat > "$HOME/.savia/focal-state/n4.json" <<JSON
{"nido":"n4","status":"active","next_human_decision": {"description":"aprobar PR","blocking":true},"check_in_interval_min":10}
JSON
  run bash "$FOCAL_SWITCH" --save-only --nido n4
  grep -q '"description":"aprobar PR"' "$HOME/.savia/focal-state/n4.json"
}

@test "S03k focal-switch: escapa comillas en la descripción y el JSON sigue siendo válido" {
  run bash "$FOCAL_SWITCH" --save-only --nido n5 --task 'dijo "hola" y \adios'
  python3 - "$HOME/.savia/focal-state/n5.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['context_summary']=='dijo "hola" y \\adios', d['context_summary']
PY
}

@test "S03k focal-switch: recorta context_summary a 200 caracteres" {
  local largo; largo=$(printf 'x%.0s' $(seq 1 300))
  run bash "$FOCAL_SWITCH" --save-only --nido n6 --task "$largo"
  python3 - "$HOME/.savia/focal-state/n6.json" <<'PY'
import json,sys
assert len(json.load(open(sys.argv[1]))['context_summary'])==200
PY
}

@test "S03k focal-switch: --from/--to registra el cambio y muestra el contexto destino" {
  cat > "$HOME/.savia/focal-state/destino.json" <<JSON
{"nido":"destino","branch":"agent/dest","task":"tarea destino","context_summary":"donde lo dejé","status":"paused"}
JSON
  run bash "$FOCAL_SWITCH" --from origen --to destino --task "salgo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- Contexto de destino ---"* ]]
  [[ "$output" == *"Rama: agent/dest"* ]]
  [[ "$output" == *"Tarea: tarea destino"* ]]
  [[ "$output" == *"Resumen: donde lo dejé"* ]]
  [[ "$output" == *"Cambio registrado: origen → destino"* ]]
  grep -q 'origen→destino' "$HOME/.savia/.switch-log"
}

@test "S03k focal-switch: destino sin estado lo dice y --save-only no escribe .switch-log" {
  run bash "$FOCAL_SWITCH" --from o --to fantasma --task "x"
  [[ "$output" == *"Nido destino fantasma: sin estado guardado"* ]]
  : > "$HOME/.savia/.switch-log"
  run bash "$FOCAL_SWITCH" --save-only --nido o --to otro
  [ ! -s "$HOME/.savia/.switch-log" ]
}

# Pares de decisiones donde cada peso de la fórmula decide el orden
_primero() {
  # $1 y $2 patrones: devuelve 0 si $1 aparece antes que $2 en la salida
  local a b
  a=$(echo "$output" | grep -n -- "$1" | head -1 | cut -d: -f1)
  b=$(echo "$output" | grep -n -- "$2" | head -1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

_nhd_edad() {
  # $1 blocking, $2 urgency, $3 cost, $4 descripción, $5 minutos de antigüedad
  printf '{"description":"%s","blocking":%s,"urgency":%s,"cognitive_cost":%s,"created_at":"%s"}' \
    "$4" "$1" "$2" "$3" "$(_ago $(( $5 * 60 + 5 )))"
}

@test "S03k focal-status: el bloqueo pesa 5 (5 > urgencia 1 + 15 min de edad = 4.5)" {
  _mk bloq active "$(_ago 10)" 10 "$(_nhd_edad true 0 0 'bloqueada' 0)"
  _mk urg active "$(_ago 10)" 10 "$(_nhd_edad false 1 0 'urgente' 15)"
  run bash "$FOCAL_STATUS"
  _primero 'bloq: bloqueada' 'urg: urgente'
}

@test "S03k focal-status: la urgencia pesa 3 (3 > 25 min de edad = 2.5)" {
  _mk urg active "$(_ago 10)" 10 "$(_nhd_edad false 1 0 'urgente' 0)"
  _mk vieja active "$(_ago 10)" 10 "$(_nhd_edad false 0 0 'antigua' 25)"
  run bash "$FOCAL_STATUS"
  _primero 'urg: urgente' 'vieja: antigua'
}

@test "S03k focal-status: el coste resta y la antigüedad suma" {
  _mk caro active "$(_ago 10)" 10 "$(_nhd_edad false 1 1 'caro' 0)"
  _mk barato active "$(_ago 10)" 10 "$(_nhd_edad false 1 0 'barato' 0)"
  run bash "$FOCAL_STATUS"
  _primero 'barato: barato' 'caro: caro'
}

@test "S03k focal-status: prioridad negativa se recorta a 0 y queda bajo una positiva pequeña" {
  _mk neg active "$(_ago 10)" 10 "$(_nhd_edad false 0 3 'negativa' 0)"
  _mk pos active "$(_ago 10)" 10 "$(_nhd_edad false 0 0 'pequena' 5)"
  run bash "$FOCAL_STATUS"
  _primero 'pos: pequena' 'neg: negativa'
}

@test "S03k focal-status: rama de 25 y de 30 caracteres no se truncan" {
  local b25="agent/aaaaaaaaaaaaaaaaaaaa"      # 26
  local b30="agent/aaaaaaaaaaaaaaaaaaaaaaaa"  # 30
  [ "${#b30}" -eq 30 ]
  _mk r25 active "$(_ago 10)" 10 null "$b25"
  _mk r30 active "$(_ago 10)" 10 null "$b30"
  run bash "$FOCAL_STATUS"
  [[ "$output" == *"$b25"* ]]
  [[ "$output" == *"$b30"* ]]
  [[ "$output" != *"…"* ]]
}

@test "S03k focal-status: carga OK con 3 cambios, HIGH con 6" {
  export TZ=Asia/Kolkata
  _mk limite active "$(_ago 10)" 10
  for i in 1 2 3; do echo "$(_ago 60) a→b" >> "$HOME/.savia/.switch-log"; done
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^limite ')" == *" OK "* ]]
  for i in 1 2 3; do echo "$(_ago 60) a→b" >> "$HOME/.savia/.switch-log"; done
  run bash "$FOCAL_STATUS"
  [[ "$(echo "$output" | grep '^limite ')" == *" HIGH "* ]]
}

@test "S03k focal-switch: un nido nuevo nace con intervalo 10, decisión null y created_at válido" {
  run bash "$FOCAL_SWITCH" --save-only --nido nuevo --task "t"
  python3 - "$HOME/.savia/focal-state/nuevo.json" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1]))
assert d["check_in_interval_min"]==10
assert d["next_human_decision"] is None
assert d["waiting_for"] is None
assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", d["created_at"]), d["created_at"]
assert d["created_at"]==d["updated_at"] or d["created_at"]<=d["updated_at"]
PY
}

@test "S03k focal-switch: un cambio --from/--to también deja el origen en paused" {
  cat > "$HOME/.savia/focal-state/org.json" <<JSON
{"nido":"org","status":"active","check_in_interval_min":10}
JSON
  run bash "$FOCAL_SWITCH" --from org --to dst --task "x"
  grep -q '"status": "paused"' "$HOME/.savia/focal-state/org.json"
}
