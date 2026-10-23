#!/usr/bin/env bats
# tests/test-session-registry.bats — SE-229 Slice 1: 15 tests
# bats ≥ 1.7 required

REGISTRY=""

setup() {
  # Use a temp dir per test to avoid cross-test pollution
  export HOME_BACKUP="$HOME"
  export TEST_HOME
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export SAVIA_DIR="$TEST_HOME/.savia"
  mkdir -p "$SAVIA_DIR"

  # Locate the registry script relative to this test file
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REGISTRY="${SCRIPT_DIR}/../scripts/session-registry.sh"
  # Ensure executable
  chmod +x "$REGISTRY"
}

teardown() {
  export HOME="$HOME_BACKUP"
  rm -rf "$TEST_HOME" 2>/dev/null || true
}

# Helper: create a stale timestamp (>10 min ago) in ISO-8601 UTC
stale_ts() {
  date -u -d "15 minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(minutes=15)).strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

# Helper: fresh timestamp
fresh_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ── Test 1: register crea entrada en JSONL ────────────────────────────────────
@test "1: register creates entry in JSONL" {
  run bash "$REGISTRY" register \
    --session "sess-001" --nido "test-nido" \
    --branch "feature/test" --task "test task"
  [ "$status" -eq 0 ]
  [ -f "$SAVIA_DIR/active-sessions.jsonl" ]
  run grep '"session_id":"sess-001"' "$SAVIA_DIR/active-sessions.jsonl"
  [ "$status" -eq 0 ]
}

# ── Test 2: register con misma session_id es idempotente ─────────────────────
@test "2: register with same session_id is idempotent" {
  bash "$REGISTRY" register --session "sess-idem" --nido "n" --branch "b" --task "t"
  bash "$REGISTRY" register --session "sess-idem" --nido "n" --branch "b" --task "t"
  run grep -c '"session_id":"sess-idem"' "$SAVIA_DIR/active-sessions.jsonl"
  # Should have exactly 1 active entry (idempotent = no duplicate)
  [ "$output" -eq 1 ]
}

# ── Test 3: list muestra sesiones activas ─────────────────────────────────────
@test "3: list shows active sessions" {
  bash "$REGISTRY" register --session "sess-list" --nido "my-nido" \
    --branch "main" --task "coding"
  run bash "$REGISTRY" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"sess-list"* ]]
}

# ── Test 4: list no muestra sesiones con heartbeat >10 min ───────────────────
@test "4: list hides stale sessions (heartbeat >10 min)" {
  local ts; ts=$(stale_ts)
  local entry
  if command -v jq >/dev/null 2>&1; then
    entry=$(jq -cn \
      --arg sid "sess-stale" --arg ts "$ts" \
      '{session_id:$sid,pid:"1",nido:"n",branch:"b",task:"t",worktree:"",started_at:$ts,heartbeat_at:$ts,status:"active"}')
  else
    entry=$(python3 -c "
import json,sys
d={'session_id':'sess-stale','pid':'1','nido':'n','branch':'b','task':'t','worktree':'',
   'started_at':sys.argv[1],'heartbeat_at':sys.argv[1],'status':'active'}
print(json.dumps(d))" "$ts")
  fi
  echo "$entry" >> "$SAVIA_DIR/active-sessions.jsonl"

  run bash "$REGISTRY" list
  [ "$status" -eq 0 ]
  [[ "$output" != *"sess-stale"* ]]
}

# ── Test 5: claim devuelve 0 si rama libre ────────────────────────────────────
@test "5: claim returns 0 when branch is free" {
  run bash "$REGISTRY" claim --branch "free-branch" --session "sess-a"
  [ "$status" -eq 0 ]
}

# ── Test 6: claim devuelve 1 y warning si rama ocupada por otra sesión ────────
@test "6: claim returns 1 with warning when branch is taken by another session" {
  bash "$REGISTRY" register --session "sess-owner" --nido "n" \
    --branch "contested" --task "t"
  run bash "$REGISTRY" claim --branch "contested" --session "sess-other"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARNING"* ]]
}

# ── Test 7: claim devuelve 0 si la única sesión con esa rama es la propia ─────
@test "7: claim returns 0 when only claimant for that branch is self" {
  bash "$REGISTRY" register --session "sess-self" --nido "n" \
    --branch "my-branch" --task "t"
  run bash "$REGISTRY" claim --branch "my-branch" --session "sess-self"
  [ "$status" -eq 0 ]
}

# ── Test 8: release marca entry como released ─────────────────────────────────
@test "8: release marks entry as released" {
  bash "$REGISTRY" register --session "sess-rel" --nido "n" \
    --branch "b" --task "t"
  run bash "$REGISTRY" release --session "sess-rel"
  [ "$status" -eq 0 ]
  run grep '"session_id":"sess-rel"' "$SAVIA_DIR/active-sessions.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"released"'* ]]
}

# ── Test 9: release + list no muestra la entrada released ─────────────────────
@test "9: released session is not shown by list" {
  bash "$REGISTRY" register --session "sess-hide" --nido "n" \
    --branch "b" --task "t"
  bash "$REGISTRY" release --session "sess-hide"
  run bash "$REGISTRY" list
  [[ "$output" != *"sess-hide"* ]]
}

# ── Test 10: heartbeat actualiza heartbeat_at ─────────────────────────────────
@test "10: heartbeat updates heartbeat_at" {
  # Write entry with stale heartbeat
  local ts; ts=$(stale_ts)
  local entry
  if command -v jq >/dev/null 2>&1; then
    entry=$(jq -cn --arg sid "sess-hb" --arg ts "$ts" \
      '{session_id:$sid,pid:"1",nido:"n",branch:"b",task:"t",worktree:"",started_at:$ts,heartbeat_at:$ts,status:"active"}')
  else
    entry=$(python3 -c "
import json,sys
d={'session_id':'sess-hb','pid':'1','nido':'n','branch':'b','task':'t','worktree':'',
   'started_at':sys.argv[1],'heartbeat_at':sys.argv[1],'status':'active'}
print(json.dumps(d))" "$ts")
  fi
  echo "$entry" >> "$SAVIA_DIR/active-sessions.jsonl"

  # Heartbeat should refresh it
  run bash "$REGISTRY" heartbeat --session "sess-hb"
  [ "$status" -eq 0 ]

  # Now list should show it (no longer stale)
  run bash "$REGISTRY" list
  [[ "$output" == *"sess-hb"* ]]
}

# ── Test 11: gc elimina entradas stale ────────────────────────────────────────
@test "11: gc removes stale entries (heartbeat >10 min)" {
  local ts; ts=$(stale_ts)
  local entry
  if command -v jq >/dev/null 2>&1; then
    entry=$(jq -cn --arg sid "sess-gc-stale" --arg ts "$ts" \
      '{session_id:$sid,pid:"1",nido:"n",branch:"b",task:"t",worktree:"",started_at:$ts,heartbeat_at:$ts,status:"active"}')
  else
    entry=$(python3 -c "
import json,sys
d={'session_id':'sess-gc-stale','pid':'1','nido':'n','branch':'b','task':'t','worktree':'',
   'started_at':sys.argv[1],'heartbeat_at':sys.argv[1],'status':'active'}
print(json.dumps(d))" "$ts")
  fi
  echo "$entry" >> "$SAVIA_DIR/active-sessions.jsonl"

  bash "$REGISTRY" gc
  run grep '"session_id":"sess-gc-stale"' "$SAVIA_DIR/active-sessions.jsonl"
  [ "$status" -ne 0 ]
}

# ── Test 12: gc no elimina entradas activas recientes ─────────────────────────
@test "12: gc does not remove recent active entries" {
  bash "$REGISTRY" register --session "sess-gc-keep" --nido "n" \
    --branch "b" --task "t"
  bash "$REGISTRY" gc
  run grep '"session_id":"sess-gc-keep"' "$SAVIA_DIR/active-sessions.jsonl"
  [ "$status" -eq 0 ]
}

# ── Test 13: concurrent writes no corrompen JSONL ─────────────────────────────
@test "13: concurrent writes do not corrupt JSONL" {
  # Fire 5 parallel registers
  for i in 1 2 3 4 5; do
    bash "$REGISTRY" register --session "sess-c${i}" --nido "n${i}" \
      --branch "b${i}" --task "t${i}" &
  done
  wait

  # Every line must be valid JSON
  local bad=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    python3 -c "import sys,json; json.loads(sys.argv[1])" "$line" 2>/dev/null || bad=$((bad+1))
  done < "$SAVIA_DIR/active-sessions.jsonl"
  [ "$bad" -eq 0 ]

  # All 5 sessions should be present
  for i in 1 2 3 4 5; do
    run grep "sess-c${i}" "$SAVIA_DIR/active-sessions.jsonl"
    [ "$status" -eq 0 ]
  done
}

# ── Test 14: gc con fichero vacío es no-op ────────────────────────────────────
@test "14: gc on empty file is no-op" {
  touch "$SAVIA_DIR/active-sessions.jsonl"
  run bash "$REGISTRY" gc
  [ "$status" -eq 0 ]
}

# ── Test 15: register sin nido funciona (nido="") ─────────────────────────────
@test "15: register without nido works (manual session, nido=empty string)" {
  run bash "$REGISTRY" register \
    --session "sess-manual" --nido "" --branch "main" --task "manual work"
  [ "$status" -eq 0 ]
  run grep '"session_id":"sess-manual"' "$SAVIA_DIR/active-sessions.jsonl"
  [ "$status" -eq 0 ]
  # nido field should be empty string, not missing
  [[ "$output" == *'"nido":""'* ]]
}

# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

# Entrada JSONL con heartbeat hace $3 segundos y estado $4 (default active).
mk_entry() {
  local ts; ts=$(date -u -d "$3 seconds ago" +"%Y-%m-%dT%H:%M:%SZ")
  jq -cn --arg sid "$1" --arg br "$2" --arg ts "$ts" --arg st "${4:-active}" \
    '{session_id:$sid,pid:"1",nido:"n",branch:$br,task:"t",worktree:"",started_at:$ts,heartbeat_at:$ts,status:$st}' \
    >> "$SAVIA_DIR/active-sessions.jsonl"
}

# Campo de la última entrada de una sesión.
field() { grep "\"session_id\":\"$1\"" "$SAVIA_DIR/active-sessions.jsonl" | tail -1 | jq -r ".$2"; }

@test "usa modo estricto de bash (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$REGISTRY"
}

@test "register guarda todos los campos y estado active con heartbeat igual a started_at" {
  run bash "$REGISTRY" register --session s1 --nido nd --branch br --task "mi tarea" --worktree /tmp/wt
  [ "$status" -eq 0 ]
  [ "$(field s1 nido)" = "nd" ]
  [ "$(field s1 branch)" = "br" ]
  [ "$(field s1 task)" = "mi tarea" ]
  [ "$(field s1 worktree)" = "/tmp/wt" ]
  [ "$(field s1 status)" = "active" ]
  [ "$(field s1 heartbeat_at)" = "$(field s1 started_at)" ]
  [[ "$(field s1 started_at)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  [ "$(field s1 focal_state_path)" = "$TEST_HOME/.savia/focal-state/nd.json" ]
}

@test "register without --session fails with 1 and creates no record" {
  run bash "$REGISTRY" register --nido n --branch b
  [ "$status" -eq 1 ]
  [[ "$output" == *"--session"* ]]
  [[ ! -s "$SAVIA_DIR/active-sessions.jsonl" ]]
}

@test "register idempotente refresca el heartbeat de la entrada existente en vez de duplicarla" {
  mk_entry sid-x br 300
  before="$(field sid-x heartbeat_at)"
  run bash "$REGISTRY" register --session sid-x --nido n --branch br --task t
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SAVIA_DIR/active-sessions.jsonl")" -eq 1 ]
  [ "$(field sid-x heartbeat_at)" != "$before" ]
}

@test "register tras release crea una entrada activa nueva (la idempotencia solo aplica a active)" {
  bash "$REGISTRY" register --session s2 --nido n --branch b --task t
  bash "$REGISTRY" release --session s2
  bash "$REGISTRY" register --session s2 --nido n --branch b --task t
  [ "$(grep -c '"session_id":"s2"' "$SAVIA_DIR/active-sessions.jsonl")" -eq 2 ]
  [ "$(field s2 status)" = "active" ]
}

@test "list with nonexistent file or all stale (empty result) reports No active sessions" {
  run bash "$REGISTRY" list
  [ "$status" -eq 0 ]
  [ "$output" = "No active sessions." ]
  mk_entry old b 900
  run bash "$REGISTRY" list
  [[ "$output" == *"No active sessions."* ]]
}

@test "list boundary at 600 s: 590 s stays active and 610 s does not" {
  mk_entry recent b1 590
  mk_entry expired b2 610
  run bash "$REGISTRY" list
  [[ "$output" == *"recent"* ]]
  [[ "$output" != *"expired"* ]]
}

@test "list imprime cabecera y trunca session_id a 36 y task a 50 caracteres" {
  long_sid="$(printf 'a%.0s' $(seq 1 50))"
  long_task="$(printf 'b%.0s' $(seq 1 80))"
  bash "$REGISTRY" register --session "$long_sid" --nido n --branch b --task "$long_task"
  run bash "$REGISTRY" list
  [[ "${lines[0]}" == SESSION_ID* ]]
  [[ "$output" == *"$(printf 'a%.0s' $(seq 1 36)) "* ]]
  [[ "$output" != *"$(printf 'a%.0s' $(seq 1 37))"* ]]
  [[ "$output" == *"$(printf 'b%.0s' $(seq 1 50))" ]] || [[ "$output" == *"$(printf 'b%.0s' $(seq 1 50))"$'\n'* ]]
  [[ "$output" != *"$(printf 'b%.0s' $(seq 1 51))"* ]]
}

@test "claim: una sesión stale no bloquea la rama (610 s) pero una de 590 s sí" {
  mk_entry dueña rama 610
  run bash "$REGISTRY" claim --branch rama --session otra
  [ "$status" -eq 0 ]
  mk_entry viva rama 590
  run bash "$REGISTRY" claim --branch rama --session otra
  [ "$status" -eq 1 ]
  [[ "$output" == *"claimed by session 'viva'"* ]]
}

@test "claim: una sesión released no bloquea la rama" {
  mk_entry vieja rama 10 released
  run bash "$REGISTRY" claim --branch rama --session otra
  [ "$status" -eq 0 ]
}

@test "claim solo bloquea la rama exacta, no otras" {
  mk_entry viva rama-a 10
  run bash "$REGISTRY" claim --branch rama-b --session otra
  [ "$status" -eq 0 ]
}

@test "claim with missing --branch or --session fails with 1" {
  run bash "$REGISTRY" claim --branch x
  [ "$status" -eq 1 ]
  run bash "$REGISTRY" claim --session x
  [ "$status" -eq 1 ]
}

@test "release cambia solo la sesión indicada y refresca su heartbeat" {
  mk_entry uno b1 300
  mk_entry dos b2 300
  before_dos="$(field dos heartbeat_at)"
  run bash "$REGISTRY" release --session uno
  [ "$status" -eq 0 ]
  [ "$(field uno status)" = "released" ]
  [ "$(field uno heartbeat_at)" != "$(field dos heartbeat_at)" ]
  [ "$(field dos status)" = "active" ]
  [ "$(field dos heartbeat_at)" = "$before_dos" ]
}

@test "release of a nonexistent session leaves the file intact" {
  mk_entry uno b1 10
  before="$(cksum < "$SAVIA_DIR/active-sessions.jsonl")"
  run bash "$REGISTRY" release --session no-existe
  [ "$status" -eq 0 ]
  [ "$(cksum < "$SAVIA_DIR/active-sessions.jsonl")" = "$before" ]
}

@test "release or heartbeat with missing --session fail with 1" {
  run bash "$REGISTRY" release
  [ "$status" -eq 1 ]
  run bash "$REGISTRY" heartbeat
  [ "$status" -eq 1 ]
}

@test "heartbeat refresca solo la sesión indicada y no cambia su estado" {
  mk_entry uno b1 400
  mk_entry dos b2 400
  before_dos="$(field dos heartbeat_at)"
  run bash "$REGISTRY" heartbeat --session uno
  [ "$status" -eq 0 ]
  [ "$(field uno heartbeat_at)" != "$before_dos" ]
  [ "$(field dos heartbeat_at)" = "$before_dos" ]
  [ "$(field uno status)" = "active" ]
}

@test "gc elimina released y stale pero conserva las activas recientes intactas" {
  mk_entry viva b1 10
  mk_entry vieja b2 900
  mk_entry liberada b3 10 released
  before="$(grep '"session_id":"viva"' "$SAVIA_DIR/active-sessions.jsonl")"
  run bash "$REGISTRY" gc
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SAVIA_DIR/active-sessions.jsonl")" -eq 1 ]
  [ "$(cat "$SAVIA_DIR/active-sessions.jsonl")" = "$before" ]
}

@test "gc with nonexistent sessions file is a no-op with exit 0" {
  run bash "$REGISTRY" gc
  [ "$status" -eq 0 ]
  [[ ! -e "$SAVIA_DIR/active-sessions.jsonl" ]]
}

@test "invalid or missing subcommand prints usage and exits 1" {
  run bash "$REGISTRY" borrar-todo
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: session-registry.sh"* ]]
  run bash "$REGISTRY"
  [ "$status" -eq 1 ]
}
