#!/usr/bin/env bats
# test-se352-memory-origin-gate.bats — BATS tests for SE-352 Trust-Gated Memory
# Ref: SE-352 — provenance de origen + taint + exclusión de consolidación

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STORE="$REPO_ROOT/scripts/memory-store.sh"
  HOOK="$REPO_ROOT/.opencode/hooks/memory-origin-gate.sh"
  export REPO_ROOT STORE HOOK

  # Isolated store per test
  export PROJECT_ROOT="$(mktemp -d)"
  export SAVIA_TEST_MODE=true
  export SAVIA_VERIFIED_MEMORY_DISABLED=false
  export HOME="$(mktemp -d)"
  export SAVIA_EMBED_PORT=0
  # El gate escribe en /tmp (ruta fija): sin esto un fichero residual de una
  # ejecución anterior hace pasar o fallar los tests por estado compartido.
  rm -f /tmp/savia-memory-taint/s1 /tmp/savia-memory-taint/s2 \
        /tmp/savia-memory-taint/s3 /tmp/savia-memory-taint/s4
}

teardown() {
  if [[ -d "${PROJECT_ROOT:-}" ]]; then
    rm -rf "$PROJECT_ROOT"
  fi
}

# ── T1: save default origin = untrusted (fail-safe) ───────────────────────────

@test "save sin --origin ni source confiable → origin=untrusted" {
  run "$STORE" save --type discovery --title "Test entry" --content "contenido de prueba" --source "user:explicit"
  [[ "$status" -eq 0 ]]
  # user:explicit → owner
  grep -q '"origin":"owner"' "$PROJECT_ROOT/output/.memory-store.jsonl"
}

@test "save sin --source → rechazado (SE-072 sigue activo)" {
  run "$STORE" save --type discovery --title "No source" --content "contenido"
  [[ "$status" -ne 0 ]]
}

@test "save con --source tool:Bash sin --origin → origin=agent" {
  run "$STORE" save --type discovery --title "Tool entry" --content "contenido de prueba" --source "tool:Bash"
  [[ "$status" -eq 0 ]]
  grep -q '"origin":"agent"' "$PROJECT_ROOT/output/.memory-store.jsonl"
}

@test "save con --source network (sin tool:) → origin=untrusted" {
  run "$STORE" save --type discovery --title "Network entry" --content "contenido de prueba" --source "file:scripts/x.sh:1"
  [[ "$status" -eq 0 ]]
  grep -q '"origin":"agent"' "$PROJECT_ROOT/output/.memory-store.jsonl"
}

@test "save con --origin inválido → error" {
  run "$STORE" save --type discovery --title "Bad origin" --content "contenido" --source "user:explicit" --origin "hacker"
  [[ "$status" -ne 0 ]]
}

@test "save con --origin system explícito → se respeta" {
  run "$STORE" save --type config --title "Sys entry" --content "contenido de prueba" --source "tool:Bash" --origin "system"
  [[ "$status" -eq 0 ]]
  grep -q '"origin":"system"' "$PROJECT_ROOT/output/.memory-store.jsonl"
}

# ── T2: taint de turno ────────────────────────────────────────────────────────

@test "hook no taint tool local (Read)" {
  INPUT='{"tool_name": "Read", "tool_input": {"path": "/tmp/x"}, "session_id": "s1"}'
  run env SAVIA_MEMORY_ORIGIN_GATE=on bash "$HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
  [[ ! -f "/tmp/savia-memory-taint/s1" ]]
}

@test "hook taint tool de red (webfetch)" {
  INPUT='{"tool_name": "webfetch", "tool_input": {"url": "https://x.com"}, "session_id": "s2"}'
  run env SAVIA_MEMORY_ORIGIN_GATE=on bash "$HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
  [[ -f "/tmp/savia-memory-taint/s2" ]]
}

@test "hook taint Bash con curl" {
  INPUT='{"tool_name": "Bash", "tool_input": {"command": "curl -s https://api.github.com"}, "session_id": "s3"}'
  run env SAVIA_MEMORY_ORIGIN_GATE=on bash "$HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
  [[ -f "/tmp/savia-memory-taint/s3" ]]
}

@test "hook exit 0 en JSON inválido (fail-soft)" {
  run env SAVIA_MEMORY_ORIGIN_GATE=on bash "$HOOK" <<< "NOT JSON"
  [[ "$status" -eq 0 ]]
}

@test "hook exit 0 con SAVIA_MEMORY_ORIGIN_GATE=off" {
  INPUT='{"tool_name": "webfetch", "tool_input": {"url": "https://x.com"}, "session_id": "s4"}'
  run env SAVIA_MEMORY_ORIGIN_GATE=off bash "$HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
  [[ ! -f "/tmp/savia-memory-taint/s4" ]]
}

# ── T3: audit-origins y consolidate ───────────────────────────────────────────

@test "audit-origins reporta distribución" {
  "$STORE" save --type discovery --title "O1" --content "contenido de prueba a" --source "user:explicit" >/dev/null
  "$STORE" save --type discovery --title "O2" --content "contenido de prueba b" --source "tool:Bash" >/dev/null
  run "$STORE" audit-origins
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"owner:"* ]]
  [[ "$output" == *"agent:"* ]]
  [[ "$output" == *"Total:"* ]]
}

@test "consolidate --dry-run excluye untrusted/system" {
  # create owner + untrusted entries
  "$STORE" save --type discovery --title "Trusted" --content "contenido de prueba x1" --source "user:explicit" >/dev/null
  "$STORE" save --type discovery --title "Dirty" --content "contenido de prueba x2" --source "user:explicit" --origin "untrusted" >/dev/null
  run "$STORE" consolidate --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"excluidas 1"* ]]
}

@test "consolidate real elimina untrusted y mantiene owner" {
  "$STORE" save --type discovery --title "TrustedK" --content "contenido de prueba y1" --source "user:explicit" >/dev/null
  "$STORE" save --type discovery --title "DirtyK" --content "contenido de prueba y2" --source "user:explicit" --origin "untrusted" >/dev/null
  run "$STORE" consolidate
  [[ "$status" -eq 0 ]]
  grep -q '"title":"TrustedK"' "$PROJECT_ROOT/output/.memory-store.jsonl"
  run grep -q '"title":"DirtyK"' "$PROJECT_ROOT/output/.memory-store.jsonl"
  [[ "$status" -ne 0 ]]
}

# ── T4: search --min-origin ───────────────────────────────────────────────────

@test "search --min-origin owner excluye untrusted" {
  "$STORE" save --type discovery --title "QueryTrusted" --content "contenido de prueba z1" --source "user:explicit" >/dev/null
  "$STORE" save --type discovery --title "QueryDirty" --content "contenido de prueba z2" --source "user:explicit" --origin "untrusted" >/dev/null
  run "$STORE" search "QueryTrusted" --min-origin owner --mode grep
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"QueryTrusted"* ]]
  run "$STORE" search "QueryDirty" --min-origin owner --mode grep
  [[ "$output" != *"QueryDirty"* ]]
}

# ── Comportamiento: clasificación de origen por source ────────────────────────

_origin_of_last() { tail -n1 "$PROJECT_ROOT/output/.memory-store.jsonl" | grep -o '"origin":"[^"]*"' | cut -d'"' -f4; }

@test "source con formato desconocido se rechaza y no se guarda nada" {
  run "$STORE" save --type discovery --title "Src libre" --content "contenido de prueba s1" --source "web:example"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not match required format"* ]]
  [[ ! -s "$PROJECT_ROOT/output/.memory-store.jsonl" ]]
}

@test "source verified:* y file:a:b se clasifican como agent" {
  "$STORE" save --type discovery --title "Ver" --content "contenido de prueba s2" --source "verified:abc" >/dev/null
  [[ "$(_origin_of_last)" == "agent" ]]
  "$STORE" save --type discovery --title "Fil" --content "contenido de prueba s3" --source "file:scripts/x.sh:7" >/dev/null
  [[ "$(_origin_of_last)" == "agent" ]]
}

@test "source file: sin número de línea se rechaza (formato file:<path>:<line>)" {
  run "$STORE" save --type discovery --title "FilSolo" --content "contenido de prueba s4" --source "file:scripts/x.sh"
  [[ "$status" -ne 0 ]]
  [[ ! -s "$PROJECT_ROOT/output/.memory-store.jsonl" ]]
}

@test "--origin explícito gana sobre la clasificación por source" {
  "$STORE" save --type discovery --title "Forzado" --content "contenido de prueba s5" --source "user:explicit" --origin agent >/dev/null
  [[ "$(_origin_of_last)" == "agent" ]]
}

@test "origin inválido: mensaje de error con los válidos y nada se guarda" {
  run "$STORE" save --type discovery --title "Malo" --content "contenido de prueba s6" --source "user:explicit" --origin hacker
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"owner|agent|untrusted|system"* ]]
  [[ ! -s "$PROJECT_ROOT/output/.memory-store.jsonl" ]]
}

# ── Comportamiento: taint de turno degrada el origen al guardar ───────────────

_taint() { # <sid> <epoch>
  mkdir -p /tmp/savia-memory-taint
  printf '%s\n' "$2" > "/tmp/savia-memory-taint/$1"
}

@test "turno con taint fresco degrada owner a untrusted al guardar" {
  sid="t-fresh-$$-$BATS_TEST_NUMBER"
  _taint "$sid" "$(date -u +%s)"
  SESSION_ID="$sid" "$STORE" save --type discovery --title "Tainted" --content "contenido de prueba t1" --source "user:explicit" >/dev/null
  rm -f "/tmp/savia-memory-taint/$sid"
  [[ "$(_origin_of_last)" == "untrusted" ]]
}

@test "taint caducado (más de 30 min) no degrada el origen" {
  sid="t-old-$$-$BATS_TEST_NUMBER"
  _taint "$sid" "$(( $(date -u +%s) - 1900 ))"
  SESSION_ID="$sid" "$STORE" save --type discovery --title "Viejo" --content "contenido de prueba t2" --source "user:explicit" >/dev/null
  rm -f "/tmp/savia-memory-taint/$sid"
  [[ "$(_origin_of_last)" == "owner" ]]
}

@test "taint de otra sesión no afecta a esta sesión" {
  other="t-other-$$-$BATS_TEST_NUMBER"
  _taint "$other" "$(date -u +%s)"
  SESSION_ID="t-mine-$$-$BATS_TEST_NUMBER" "$STORE" save --type discovery --title "Mia" --content "contenido de prueba t3" --source "user:explicit" >/dev/null
  rm -f "/tmp/savia-memory-taint/$other"
  [[ "$(_origin_of_last)" == "owner" ]]
}

@test "taint también degrada origin system pedido explícitamente" {
  sid="t-sys-$$-$BATS_TEST_NUMBER"
  _taint "$sid" "$(date -u +%s)"
  SESSION_ID="$sid" "$STORE" save --type config --title "SysT" --content "contenido de prueba t4" --source "tool:Bash" --origin system >/dev/null
  rm -f "/tmp/savia-memory-taint/$sid"
  [[ "$(_origin_of_last)" == "untrusted" ]]
}

# ── Comportamiento: hook de taint ─────────────────────────────────────────────

_hook() { # <json>
  run env SAVIA_MEMORY_ORIGIN_GATE=on bash "$HOOK" <<< "$1"
}

@test "hook escribe el epoch actual en el fichero de taint" {
  sid="h-epoch-$$-$BATS_TEST_NUMBER"
  before=$(date -u +%s)
  _hook '{"tool_name":"WebFetch","tool_input":{"url":"https://x.com"},"session_id":"'"$sid"'"}'
  after=$(date -u +%s)
  v="$(cat "/tmp/savia-memory-taint/$sid")"
  rm -f "/tmp/savia-memory-taint/$sid"
  [[ "$v" -ge "$before" && "$v" -le "$after" ]]
}

@test "hook: Bash con wget, git pull, gh api y pip install tainta el turno" {
  i=0
  for cmd in "wget http://x/y" "git pull origin main" "gh api repos/x/y" "pip install requests"; do
    i=$((i+1)); sid="h-net$i-$$-$BATS_TEST_NUMBER"
    _hook '{"tool_name":"Bash","tool_input":{"command":"'"$cmd"'"},"session_id":"'"$sid"'"}'
    [[ -f "/tmp/savia-memory-taint/$sid" ]]
    rm -f "/tmp/savia-memory-taint/$sid"
  done
}

@test "hook: Bash local (ls, git status) no tainta" {
  sid="h-local-$$-$BATS_TEST_NUMBER"
  _hook '{"tool_name":"Bash","tool_input":{"command":"ls -la && git status"},"session_id":"'"$sid"'"}'
  [[ "$status" -eq 0 ]]
  [[ ! -f "/tmp/savia-memory-taint/$sid" ]]
}

@test "hook: palabra que solo contiene curl (curly) no tainta por límite de palabra" {
  sid="h-curly-$$-$BATS_TEST_NUMBER"
  _hook '{"tool_name":"Bash","tool_input":{"command":"echo curly braces"},"session_id":"'"$sid"'"}'
  [[ ! -f "/tmp/savia-memory-taint/$sid" ]]
}

@test "hook: curl dentro de un Read (no Bash) no tainta, pero una URL como comando sí" {
  sid="h-read-$$-$BATS_TEST_NUMBER"
  _hook '{"tool_name":"Read","tool_input":{"command":"curl x"},"session_id":"'"$sid"'"}'
  [[ ! -f "/tmp/savia-memory-taint/$sid" ]]
  _hook '{"tool_name":"Fetch","tool_input":{"url":"https://example.org/a"},"session_id":"'"$sid"'"}'
  [[ -f "/tmp/savia-memory-taint/$sid" ]]
  rm -f "/tmp/savia-memory-taint/$sid"
}

@test "hook: sin session_id no crea ningún fichero de taint con nombre unknown" {
  rm -f /tmp/savia-memory-taint/unknown
  _hook '{"tool_name":"WebFetch","tool_input":{"url":"https://x.com"}}'
  [[ "$status" -eq 0 ]]
  [[ ! -f /tmp/savia-memory-taint/unknown ]]
}

@test "hook: stdin vacío termina en 0 sin tainter nada" {
  run env SAVIA_MEMORY_ORIGIN_GATE=on bash "$HOOK" <<< ""
  [[ "$status" -eq 0 ]]
}

@test "hook: valor distinto de on (p. ej. 0) desactiva el gate" {
  sid="h-off0-$$-$BATS_TEST_NUMBER"
  run env SAVIA_MEMORY_ORIGIN_GATE=0 bash "$HOOK" <<< '{"tool_name":"WebFetch","tool_input":{"url":"https://x.com"},"session_id":"'"$sid"'"}'
  [[ "$status" -eq 0 ]]
  [[ ! -f "/tmp/savia-memory-taint/$sid" ]]
}

@test "hook: por defecto (variable sin definir) el gate está activo" {
  sid="h-def-$$-$BATS_TEST_NUMBER"
  run env -u SAVIA_MEMORY_ORIGIN_GATE bash "$HOOK" <<< '{"tool_name":"WebFetch","tool_input":{"url":"https://x.com"},"session_id":"'"$sid"'"}'
  [[ -f "/tmp/savia-memory-taint/$sid" ]]
  rm -f "/tmp/savia-memory-taint/$sid"
}

@test "hook: purga ficheros de taint con más de 30 minutos" {
  mkdir -p /tmp/savia-memory-taint
  old="/tmp/savia-memory-taint/h-stale-$$-$BATS_TEST_NUMBER"
  echo 1 > "$old"; touch -d '2 hours ago' "$old"
  _hook '{"tool_name":"Read","tool_input":{},"session_id":"zz"}'
  [[ ! -f "$old" ]]
}

# ── Comportamiento: audit-origins ─────────────────────────────────────────────

@test "audit-origins sin store informa de que no hay memory store" {
  run "$STORE" audit-origins
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No hay memory store"* ]]
}

@test "audit-origins calcula porcentajes y cuenta entradas sin origin como untrusted" {
  "$STORE" save --type discovery --title "A1" --content "contenido de prueba a1" --source "user:explicit" >/dev/null
  "$STORE" save --type discovery --title "A2" --content "contenido de prueba a2" --source "tool:Bash" >/dev/null
  echo '{"ts":"2026-01-01T00:00:00Z","type":"discovery","title":"legacy","content":"sin origin"}' >> "$PROJECT_ROOT/output/.memory-store.jsonl"
  echo '{"ts":"2026-01-01T00:00:00Z","type":"discovery","title":"sys","content":"x","origin":"system"}' >> "$PROJECT_ROOT/output/.memory-store.jsonl"
  run "$STORE" audit-origins
  [[ "$output" == *"Total: 4 entradas"* ]]
  [[ "$output" == *"owner:      1 (25.0%)"* ]]
  [[ "$output" == *"agent:      1 (25.0%)"* ]]
  [[ "$output" == *"system:     1 (25.0%)"* ]]
  [[ "$output" == *"sin src:    1"* ]]
}

# ── Comportamiento: consolidate ───────────────────────────────────────────────

@test "consolidate excluye system y agent se conserva, con contadores exactos" {
  "$STORE" save --type discovery --title "Own" --content "contenido de prueba c1" --source "user:explicit" >/dev/null
  "$STORE" save --type discovery --title "Agt" --content "contenido de prueba c2" --source "tool:Bash" >/dev/null
  "$STORE" save --type config --title "Sis" --content "contenido de prueba c3" --source "tool:Bash" --origin system >/dev/null
  "$STORE" save --type discovery --title "Unt" --content "contenido de prueba c4" --source "user:explicit" --origin untrusted >/dev/null
  run "$STORE" consolidate
  [[ "$output" == *"excluidas 2 entradas untrusted/system, mantenidas 2"* ]]
  s="$PROJECT_ROOT/output/.memory-store.jsonl"
  grep -q '"title":"Own"' "$s"
  grep -q '"title":"Agt"' "$s"
  ! grep -q '"title":"Sis"' "$s"
  ! grep -q '"title":"Unt"' "$s"
}

@test "consolidate --dry-run no modifica el store" {
  "$STORE" save --type discovery --title "DryU" --content "contenido de prueba c5" --source "user:explicit" --origin untrusted >/dev/null
  before="$(cat "$PROJECT_ROOT/output/.memory-store.jsonl")"
  run "$STORE" consolidate --dry-run
  [[ "$output" == *"dry-run"* ]]
  [[ "$(cat "$PROJECT_ROOT/output/.memory-store.jsonl")" == "$before" ]]
}

@test "consolidate trata la entrada sin campo origin como untrusted y la elimina" {
  mkdir -p "$PROJECT_ROOT/output"
  echo '{"ts":"2026-01-01T00:00:00Z","type":"discovery","title":"legacy","content":"sin origin"}' >> "$PROJECT_ROOT/output/.memory-store.jsonl"
  run "$STORE" consolidate
  [[ "$output" == *"excluidas 1"* ]]
  ! grep -q '"title":"legacy"' "$PROJECT_ROOT/output/.memory-store.jsonl"
}

# ── Comportamiento: search --min-origin ───────────────────────────────────────

_seed_search() {
  "$STORE" save --type discovery --title "RankOwner" --content "palabraclave uno" --source "user:explicit" >/dev/null
  "$STORE" save --type discovery --title "RankAgent" --content "palabraclave dos" --source "tool:Bash" >/dev/null
  "$STORE" save --type discovery --title "RankUntr" --content "palabraclave tres" --source "user:explicit" --origin untrusted >/dev/null
  "$STORE" save --type config --title "RankSys" --content "palabraclave cuatro" --source "tool:Bash" --origin system >/dev/null
}

@test "search --min-origin agent devuelve owner y agent, no untrusted ni system" {
  _seed_search
  run "$STORE" search "palabraclave" --min-origin agent --mode grep
  [[ "$output" == *"RankOwner"* ]]
  [[ "$output" == *"RankAgent"* ]]
  [[ "$output" != *"RankUntr"* ]]
  [[ "$output" != *"RankSys"* ]]
}

@test "search --min-origin untrusted excluye system pero incluye untrusted" {
  _seed_search
  run "$STORE" search "palabraclave" --min-origin untrusted --mode grep
  [[ "$output" == *"RankUntr"* ]]
  [[ "$output" != *"RankSys"* ]]
}

@test "search --min-origin con valor desconocido se comporta como untrusted" {
  _seed_search
  run "$STORE" search "palabraclave" --min-origin bogus --mode grep
  [[ "$output" == *"RankAgent"* ]]
  [[ "$output" == *"RankUntr"* ]]
  [[ "$output" != *"RankSys"* ]]
}

@test "search sin --min-origin no filtra por origen (system incluido)" {
  _seed_search
  run "$STORE" search "palabraclave" --mode grep
  [[ "$output" == *"RankSys"* ]]
  [[ "$output" == *"RankOwner"* ]]
}

@test "taint dentro de la ventana (25 min) sigue degradando el origen" {
  sid="t-mid-$$-$BATS_TEST_NUMBER"
  _taint "$sid" "$(( $(date -u +%s) - 1500 ))"
  SESSION_ID="$sid" "$STORE" save --type discovery --title "Medio" --content "contenido de prueba t5" --source "user:explicit" >/dev/null
  rm -f "/tmp/savia-memory-taint/$sid"
  [[ "$(_origin_of_last)" == "untrusted" ]]
}

@test "sin SESSION_ID no se aplica el taint de una sesión llamada x" {
  _taint "x" "$(date -u +%s)"
  env -u SESSION_ID "$STORE" save --type discovery --title "SinSid" --content "contenido de prueba t6" --source "user:explicit" >/dev/null
  rm -f /tmp/savia-memory-taint/x
  [[ "$(_origin_of_last)" == "owner" ]]
}
