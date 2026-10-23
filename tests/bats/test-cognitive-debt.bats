#!/usr/bin/env bats
# tests/bats/test-cognitive-debt.bats — SPEC-107 BATS tests
# Validates hook existence, master switch, protocol doc, and script output.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

@test "cognitive-debt-check.sh exists and is executable" {
  local hook="$REPO_ROOT/.opencode/hooks/cognitive-debt-check.sh"
  [ -f "$hook" ]
  [ -x "$hook" ]
}

@test "SAVIA_COGNITIVE_MONITOR=off exits 0 without banner" {
  local hook="$REPO_ROOT/.opencode/hooks/cognitive-debt-check.sh"
  run env SAVIA_COGNITIVE_MONITOR=off bash "$hook"
  [ "$status" -eq 0 ]
  # stderr must be empty when monitor is off
  [ -z "$output" ]
}

@test "cognitive-debt-protocol.md exists and mentions MIT Media Lab" {
  local doc="$REPO_ROOT/docs/rules/domain/cognitive-debt-protocol.md"
  [ -f "$doc" ]
  grep -q "MIT Media Lab" "$doc"
}

@test "cognitive-debt-monitor.py exists and produces JSON output" {
  local script="$REPO_ROOT/scripts/cognitive-debt-monitor.py"
  [ -f "$script" ]
  run python3 "$script" --session-hours 2 --verification-rate 0.8 --json
  [ "$status" -eq 0 ]
  # output must be valid JSON with cognitive_load_score field
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cognitive_load_score' in d"
  [ "$?" -eq 0 ]
}

@test "hook exits 0 when SAVIA_COGNITIVE_MONITOR=on but session is short" {
  local hook="$REPO_ROOT/.opencode/hooks/cognitive-debt-check.sh"
  # Force a fresh session start file far in the future (session ~0h)
  local tmp_start
  tmp_start=$(mktemp)
  date +%s > "$tmp_start"
  run env SAVIA_COGNITIVE_MONITOR=on \
      SAVIA_SESSION_START_FILE="$tmp_start" \
      COGNITIVE_DEBT_SESSION_LIMIT=4 \
      bash "$hook"
  [ "$status" -eq 0 ]
  rm -f "$tmp_start"
}

# --- Comportamiento de scripts/cognitive-debt.sh: settings y telemetría en directorios temporales ---

CD="$REPO_ROOT/scripts/cognitive-debt.sh"

cd_env() {
  export SAVIA_SETTINGS_OVERRIDE="$BATS_TEST_TMPDIR/settings.json"
  export SAVIA_COGNITIVE_DIR="$BATS_TEST_TMPDIR/cog"
  export USER=tester
  LOG="$SAVIA_COGNITIVE_DIR/tester.jsonl"
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash other.sh"}]}]},"nota":"acentuación"}' > "$SAVIA_SETTINGS_OVERRIDE"
}

@test "sin subcomando imprime uso y sale 2; subcomando desconocido sale 2 con error" {
  run bash "$CD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"enable"* && "$output" == *"forget"* ]]
  run bash "$CD" inventado
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown subcommand: inventado"* ]]
}

@test "enable cablea ambos hooks, conserva los ajenos y los acentos, y crea copia de seguridad" {
  cd_env
  run bash "$CD" enable
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup: "* ]]
  ls "$SAVIA_SETTINGS_OVERRIDE".bak.* >/dev/null
  run jq -r '.hooks.PostToolUse[0].matcher, .hooks.PostToolUse[0].hooks[0].name, .hooks.PostToolUse[0].hooks[0].blocking, .hooks.PostToolUse[0].hooks[0].timeout' "$SAVIA_SETTINGS_OVERRIDE"
  [ "$output" = $'Edit|Write|Task\ncognitive-debt-telemetry\nfalse\n2' ]
  [ "$(jq -r '.hooks.PreToolUse | map(.matcher) | join(",")' "$SAVIA_SETTINGS_OVERRIDE")" = "Bash,Edit|Write" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SAVIA_SETTINGS_OVERRIDE")" = "bash other.sh" ]
  grep -q 'acentuación' "$SAVIA_SETTINGS_OVERRIDE"
  [ -d "$SAVIA_COGNITIVE_DIR" ]
  [ "$(stat -c %a "$SAVIA_COGNITIVE_DIR")" = "700" ]
}

@test "enable dos veces es idempotente: segunda dice Already enabled y no duplica" {
  cd_env
  bash "$CD" enable >/dev/null
  run bash "$CD" enable
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already enabled"* ]]
  [ "$(grep -c 'cognitive-debt-telemetry' "$SAVIA_SETTINGS_OVERRIDE")" -eq 2 ]
}

@test "enable sobre matcher existente añade el hook sin duplicar la entrada" {
  cd_env
  echo '{"hooks":{"PostToolUse":[{"matcher":"Edit|Write|Task","hooks":[{"type":"command","command":"bash x.sh"}]}]}}' > "$SAVIA_SETTINGS_OVERRIDE"
  run bash "$CD" enable
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.PostToolUse | length' "$SAVIA_SETTINGS_OVERRIDE")" -eq 1 ]
  [ "$(jq '.hooks.PostToolUse[0].hooks | length' "$SAVIA_SETTINGS_OVERRIDE")" -eq 2 ]
}

@test "enable sin settings.json sale 5; con JSON invalido sale 6 y no toca el fichero" {
  cd_env
  mv "$SAVIA_SETTINGS_OVERRIDE" "$BATS_TEST_TMPDIR/otro.json"
  run bash "$CD" enable
  [ "$status" -eq 5 ]
  echo '{roto' > "$SAVIA_SETTINGS_OVERRIDE"
  run bash "$CD" enable
  [ "$status" -eq 6 ]
  [[ "$output" == *"not valid JSON"* ]]
  [ "$(cat "$SAVIA_SETTINGS_OVERRIDE")" = "{roto" ]
  ! ls "$SAVIA_SETTINGS_OVERRIDE".bak.* >/dev/null 2>&1
}

@test "disable quita solo los dos hooks propios, deja cognitive-debt-check y los ajenos" {
  cd_env
  echo '{"hooks":{"PostToolUse":[{"matcher":"Edit|Write|Task","hooks":[{"command":"bash .opencode/hooks/cognitive-debt-telemetry.sh"},{"command":"bash .opencode/hooks/cognitive-debt-check.sh"}]}],"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"command":"bash .opencode/hooks/cognitive-debt-hypothesis-first.sh"}]},{"matcher":"Bash","hooks":[{"command":"bash ajeno.sh"}]}]}}' > "$SAVIA_SETTINGS_OVERRIDE"
  run bash "$CD" disable
  [ "$status" -eq 0 ]
  [[ "$output" == *"Telemetry preserved"* ]]
  ! grep -q 'cognitive-debt-telemetry' "$SAVIA_SETTINGS_OVERRIDE"
  ! grep -q 'hypothesis-first' "$SAVIA_SETTINGS_OVERRIDE"
  grep -q 'cognitive-debt-check.sh' "$SAVIA_SETTINGS_OVERRIDE"
  grep -q 'ajeno.sh' "$SAVIA_SETTINGS_OVERRIDE"
  [ "$(jq '.hooks.PreToolUse | length' "$SAVIA_SETTINGS_OVERRIDE")" -eq 1 ]
}

@test "disable elimina el evento entero cuando queda vacio" {
  cd_env
  bash "$CD" enable >/dev/null
  echo '{"hooks":{"PostToolUse":[{"matcher":"m","hooks":[{"command":"bash cognitive-debt-telemetry.sh"}]}]}}' > "$SAVIA_SETTINGS_OVERRIDE"
  bash "$CD" disable >/dev/null
  [ "$(jq '.hooks | has("PostToolUse")' "$SAVIA_SETTINGS_OVERRIDE")" = "false" ]
}

@test "disable cuando no esta activo dice Already disabled y no crea copia; sin settings sale 0" {
  cd_env
  run bash "$CD" disable
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already disabled"* ]]
  ! ls "$SAVIA_SETTINGS_OVERRIDE".bak.* >/dev/null 2>&1
  mv "$SAVIA_SETTINGS_OVERRIDE" "$BATS_TEST_TMPDIR/otro.json"
  run bash "$CD" disable
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to disable"* ]]
}

@test "enable seguido de disable deja los hooks ajenos como estaban" {
  cd_env
  before=$(jq -S '.hooks.PreToolUse[0]' "$SAVIA_SETTINGS_OVERRIDE")
  bash "$CD" enable >/dev/null
  bash "$CD" disable >/dev/null
  [ "$(jq -S '.hooks.PreToolUse[0]' "$SAVIA_SETTINGS_OVERRIDE")" = "$before" ]
}

@test "status: DISABLED sin hooks, ENABLED con ellos, y cuenta eventos de hoy en UTC" {
  cd_env
  run bash "$CD" status
  [[ "$output" == *"State:        DISABLED"* ]]
  [[ "$output" == *"Total events: 0 (no telemetry yet)"* ]]
  bash "$CD" enable >/dev/null
  mkdir -p "$SAVIA_COGNITIVE_DIR"
  today=$(date -u +%Y-%m-%d)
  printf '{"ts": "%sT01:00:00Z"}\n{"ts":"%sT02:00:00Z"}\n{"ts":"2020-01-01T00:00:00Z"}\n' "$today" "$today" > "$LOG"
  run bash "$CD" status
  [[ "$output" == *"State:        ENABLED"* ]]
  [[ "$output" == *"Total events: 3"* ]]
  [[ "$output" == *"Today:        2 events"* ]]
}

@test "summary sin telemetria avisa y sale 0" {
  cd_env
  run bash "$CD" summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"No telemetry data yet"* ]]
}

@test "summary: ventana de 7 dias UTC, fast-accept solo sobre eventos con duracion numerica" {
  cd_env
  mkdir -p "$SAVIA_COGNITIVE_DIR"
  today=$(date -u +%Y-%m-%d); d6=$(date -u -d '6 days ago' +%Y-%m-%d); d7=$(date -u -d '7 days ago' +%Y-%m-%d)
  {
    printf '{"ts":"%sT01:00:00Z","duration_ms":1000}\n' "$today"
    printf '{"ts":"%sT01:00:00Z","duration_ms":4999}\n' "$today"
    printf '{"ts":"%sT01:00:00Z","duration_ms":5000}\n' "$today"
    printf '{"ts":"%sT01:00:00Z","duration_ms":null}\n' "$d6"
    printf '{"ts":"%sT01:00:00Z","duration_ms":true}\n' "$d6"
    printf '{"ts":"%sT01:00:00Z","duration_ms":10}\n' "$d7"
    printf 'basura no json\n[1,2]\n{"sin_ts":1}\n'
  } > "$LOG"
  run bash "$CD" summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total events (last 7d):  5"* ]]
  [[ "$output" == *"Fast-accept ratio:       67%"* ]]
  [[ "$output" == *"timed events: 3"* ]]
  [[ "$output" == *"$d6     2"* ]]
  [[ "$output" != *"$d7"* ]]
}

@test "summary sin eventos con duracion muestra n/a" {
  cd_env
  mkdir -p "$SAVIA_COGNITIVE_DIR"
  printf '{"ts":"%sT01:00:00Z"}\n' "$(date -u +%Y-%m-%d)" > "$LOG"
  run bash "$CD" summary
  [[ "$output" == *"Fast-accept ratio:       n/a"* ]]
}

@test "forget sin --confirm sale 2 y no borra; con argumento desconocido sale 2" {
  cd_env
  mkdir -p "$SAVIA_COGNITIVE_DIR"; echo '{"ts":"x"}' > "$LOG"
  run bash "$CD" forget
  [ "$status" -eq 2 ]
  [[ "$output" == *"--confirm required"* ]]
  [ -f "$LOG" ]
  run bash "$CD" forget --si
  [ "$status" -eq 2 ]
  [ -f "$LOG" ]
}

@test "forget --confirm borra la telemetria; segunda vez dice que no hay nada" {
  cd_env
  mkdir -p "$SAVIA_COGNITIVE_DIR"; echo '{"ts":"x"}' > "$LOG"
  run bash "$CD" forget --confirm
  [ "$status" -eq 0 ]
  [[ "$output" == *"Telemetry wiped"* ]]
  [ ! -e "$LOG" ]
  run bash "$CD" forget --confirm
  [[ "$output" == *"No telemetry to wipe"* ]]
}

@test "summary: la barra por dia se limita a 30 caracteres" {
  cd_env
  mkdir -p "$SAVIA_COGNITIVE_DIR"
  for i in $(seq 1 40); do printf '{"ts":"%sT01:00:00Z"}\n' "$(date -u +%Y-%m-%d)"; done > "$LOG"
  run bash "$CD" summary
  bar=$(grep -o '█*' <<<"$output" | sort -r | head -1)
  [ "${#bar}" -eq 30 ]
}

@test "status y summary cuentan 'hoy' en UTC aunque la zona local ya sea otro dia" {
  cd_env
  mkdir -p "$SAVIA_COGNITIVE_DIR"
  utc_h=$(date -u +%H)
  if [ "$((10#$utc_h))" -ge 10 ]; then tz="Pacific/Kiritimati"; else tz="Etc/GMT+12"; fi
  [ "$(TZ=$tz date +%Y-%m-%d)" != "$(date -u +%Y-%m-%d)" ]
  printf '{"ts": "%sT01:00:00Z"}\n' "$(date -u +%Y-%m-%d)" > "$LOG"
  TZ=$tz run bash "$CD" status
  [[ "$output" == *"Today:        1 events"* ]]
}

@test "enable no duplica hypothesis-first si ya estaba bajo su matcher" {
  cd_env
  echo '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"command":"bash .opencode/hooks/cognitive-debt-hypothesis-first.sh"}]}]}}' > "$SAVIA_SETTINGS_OVERRIDE"
  run bash "$CD" enable
  [ "$status" -eq 0 ]
  [ "$(grep -c 'hypothesis-first' "$SAVIA_SETTINGS_OVERRIDE")" -eq 1 ]
  [ "$(jq '.hooks.PreToolUse[0].hooks | length' "$SAVIA_SETTINGS_OVERRIDE")" -eq 1 ]
}

@test "enable con estructura de hooks inesperada falla con exit 6 y mensaje" {
  cd_env
  echo '{"hooks":[]}' > "$SAVIA_SETTINGS_OVERRIDE"
  run bash "$CD" enable
  [ "$status" -eq 6 ]
  [[ "$output" == *"could not update"* ]]
}

@test "forget --confirm con un argumento desconocido no borra y sale 2" {
  cd_env
  mkdir -p "$SAVIA_COGNITIVE_DIR"; echo '{"ts":"x"}' > "$LOG"
  run bash "$CD" forget --confirm --si
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg: --si"* ]]
  [ -f "$LOG" ]
}

@test "settings.json enlazado simbolicamente se actualiza en su destino y el enlace sobrevive" {
  cd_env
  mv "$SAVIA_SETTINGS_OVERRIDE" "$BATS_TEST_TMPDIR/real.json"
  ln -s "$BATS_TEST_TMPDIR/real.json" "$SAVIA_SETTINGS_OVERRIDE"
  run bash "$CD" enable
  [ "$status" -eq 0 ]
  [ -L "$SAVIA_SETTINGS_OVERRIDE" ]
  grep -q 'cognitive-debt-telemetry' "$BATS_TEST_TMPDIR/real.json"
}
