#!/usr/bin/env bats
# BATS tests for scripts/agent-request-validate.sh
# SE-272 Slice 3 — Agent request origin validation.
# Ref: docs/propuestas/SE-272-servicio-gestionado.md

SCRIPT="scripts/agent-request-validate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  TEST_DIR=$(mktemp -d "$TMPDIR/arv-XXXXXX")
  export DATA_DIR="$TEST_DIR/data"
  mkdir -p "$DATA_DIR"
  export PLATFORM_CARDS_FILE="$TEST_DIR/cards.yaml"
}

teardown() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
  cd /
}

@test "script exists" { [[ -f "$SCRIPT" ]]; }
@test "script is executable" { [[ -x "$SCRIPT" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
@test "SE-272 reference present" {
  run grep -c 'SE-272' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }

# ── CLI ──────────────────────────────────────────────

@test "help: prints usage when no subcommand" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cli: unknown subcommand exits 2" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

# ── validate: human origin ───────────────────────────

@test "validate: human origin accepted without agent-id" {
  run bash "$SCRIPT" validate --origin human
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACCEPT"* ]]
}

@test "validate: human origin ignores agent-id if provided" {
  run bash "$SCRIPT" validate --origin human --agent-id "ext-platform-any"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACCEPT"* ]]
}

# ── validate: agent origin — no cards file ───────────

@test "validate: agent origin without agent-id fails" {
  run bash "$SCRIPT" validate --origin agent
  [ "$status" -eq 2 ]
}

@test "validate: agent rejected when no cards file present" {
  run bash "$SCRIPT" validate --origin agent --agent-id "ext-platform-missing" --platform-card "$TEST_DIR/missing.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REJECT"* ]]
}

# ── validate: agent origin — with cards file ─────────

@test "validate: active agent card accepted" {
  cat > "$PLATFORM_CARDS_FILE" << 'YAMLEOF'
version: "1.0"
spec: "SE-272"
cards:
  test-platform:
    id: "ext-platform-test-9999"
    organization: "Test Organization"
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx..."
    exposed_skills:
      - "situacion.query"
    allowed_skills:
      - "situacion.query"
    max_payload_level: 2
    engagement: "engagements/2026-test-001"
    status: active
default: deny
YAMLEOF
  run bash "$SCRIPT" validate --origin agent --agent-id "ext-platform-test-9999" --platform-card "$PLATFORM_CARDS_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACCEPT"* ]]
}

@test "validate: inactive agent card rejected" {
  cat > "$PLATFORM_CARDS_FILE" << 'YAMLEOF'
version: "1.0"
spec: "SE-272"
cards:
  test-platform-inactive:
    id: "ext-platform-test-8888"
    organization: "Test Org Inactive"
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx..."
    exposed_skills:
      - "situacion.query"
    allowed_skills:
      - "situacion.query"
    max_payload_level: 2
    engagement: "engagements/2026-test-002"
    status: suspended
default: deny
YAMLEOF
  run bash "$SCRIPT" validate --origin agent --agent-id "ext-platform-test-8888" --platform-card "$PLATFORM_CARDS_FILE"
  [ "$status" -eq 1 ]
}

@test "validate: unregistered agent id rejected" {
  cat > "$PLATFORM_CARDS_FILE" << 'YAMLEOF'
version: "1.0"
spec: "SE-272"
cards:
  test-platform:
    id: "ext-platform-test-9999"
    organization: "Test Organization"
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx..."
    exposed_skills: ["situacion.query"]
    allowed_skills: ["situacion.query"]
    max_payload_level: 2
    engagement: "engagements/2026-test-001"
    status: active
default: deny
YAMLEOF
  run bash "$SCRIPT" validate --origin agent --agent-id "ext-platform-nonexistent" --platform-card "$PLATFORM_CARDS_FILE"
  [ "$status" -eq 1 ]
}

# ── identify ─────────────────────────────────────────

@test "identify: human token" {
  run bash "$SCRIPT" identify --token "human:User Name"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ORIGIN: human"* ]]
  [[ "$output" == *"User Name"* ]]
}

@test "identify: agent token" {
  run bash "$SCRIPT" identify --token "agent:ext-platform-test-9999"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ORIGIN: agent"* ]]
}

@test "identify: unknown token exits 1" {
  run bash "$SCRIPT" identify --token "robot:some-bot"
  [ "$status" -eq 1 ]
}

# ── Logging ──────────────────────────────────────────

@test "validate: writes identity log entry" {
  cat > "$PLATFORM_CARDS_FILE" << 'YAMLEOF'
version: "1.0"
spec: "SE-272"
cards:
  test-platform:
    id: "ext-platform-test-9999"
    organization: "Test Organization"
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx..."
    exposed_skills: ["situacion.query"]
    allowed_skills: ["situacion.query"]
    max_payload_level: 2
    engagement: "engagements/2026-test-001"
    status: active
default: deny
YAMLEOF
  export IDENTITY_LOG="$TEST_DIR/identity-log.jsonl"
  run bash "$SCRIPT" validate --origin agent --agent-id "ext-platform-test-9999" --platform-card "$PLATFORM_CARDS_FILE"
  [ "$status" -eq 0 ]
  [[ -f "$IDENTITY_LOG" ]]
  run grep -c "ACCEPT" "$IDENTITY_LOG"
  [[ "$output" -ge 1 ]]
}

# ── Edge cases ───────────────────────────────────────

@test "validate: dies on missing --origin" {
  run bash "$SCRIPT" validate --agent-id "ext-platform-test-9999"
  [ "$status" -eq 2 ]
}

@test "coverage: exit codes 0,1,2 all used" {
  run grep -c 'exit 0\|exit 1\|exit 2' "$SCRIPT"
  [[ "$output" -ge 3 ]]
}

# ── Comportamiento: mensajes, registro, inyección y casos límite ─────────────

mk_cards() {  # mk_cards <fichero>  (dos tarjetas: una activa, una suspendida)
  cat > "$1" <<'YAMLEOF'
cards:
  alpha:
    id: "ext-alpha"
    status: active
  beta:
    id: "ext-beta"
    status: suspended
  gamma:
    id: "ext-gamma"
    status: active
YAMLEOF
}

lastlog() { tail -1 "$IDENTITY_LOG"; }
logf() { python3 -c 'import json,sys; print(json.loads(sys.stdin.read().splitlines()[-1])[sys.argv[1]])' "$1" < "$IDENTITY_LOG"; }

@test "regresión: un agent-id con comillas no altera la comprobación de tarjeta (antes se aceptaba)" {
  mk_cards "$PLATFORM_CARDS_FILE"; export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  run bash "$SCRIPT" validate --origin agent --agent-id "zz' or 'a'=='a"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REJECT_UNREGISTERED"* ]]
  [[ "$output" != *"ACCEPT"* ]]
  run bash "$SCRIPT" validate --origin agent --agent-id "x' or True or '"
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" validate --origin agent --agent-id "' or ''=='"
  [ "$status" -eq 1 ]
}

@test "regresión: la ruta de la tarjeta con comillas se lee como ruta, no como código" {
  mk_cards "$TEST_DIR/it's.yaml"
  run bash "$SCRIPT" validate --origin agent --agent-id ext-alpha --platform-card "$TEST_DIR/it's.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == "ACCEPT: agent origin verified — card_id=alpha" ]]
}

@test "validate: salida exacta de aceptación humana y registro" {
  export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  run bash "$SCRIPT" validate --origin human
  [ "$status" -eq 0 ]
  [ "$output" = "ACCEPT: human origin" ]
  [ "$(logf origin)" = human ]
  [ "$(logf decision)" = ACCEPT ]
  [ "$(logf reason)" = "human-origin-no-verification-needed" ]
  [ "$(logf agent_id)" = "" ]
}

@test "validate: aceptación de agente devuelve la clave de la tarjeta y la registra" {
  mk_cards "$PLATFORM_CARDS_FILE"; export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  run bash "$SCRIPT" validate --origin agent --agent-id ext-gamma
  [ "$status" -eq 0 ]
  [ "$output" = "ACCEPT: agent origin verified — card_id=gamma" ]
  [ "$(logf agent_id)" = ext-gamma ]
  [ "$(logf card_id)" = gamma ]
  [ "$(logf decision)" = ACCEPT ]
  [ "$(logf reason)" = "verified-against-cards" ]
  python3 -c 'import json,re,sys; d=json.loads(sys.stdin.read().splitlines()[-1]); assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", d["timestamp"])' < "$IDENTITY_LOG"
}

@test "validate: rechazo por tarjeta suspendida, desconocida o con otro id, con mensaje y registro REJECT" {
  mk_cards "$PLATFORM_CARDS_FILE"; export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  local id
  for id in ext-beta ext-nope EXT-ALPHA ""; do
    [ -z "$id" ] && continue
    run bash "$SCRIPT" validate --origin agent --agent-id "$id"
    [ "$status" -eq 1 ]
    [[ "$output" == *"REJECT_UNREGISTERED: agent_id '$id' not found or not active in platform cards"* ]]
    [[ "$output" == *"REJECT: agent origin without verifiable identity — agent_id=$id"* ]]
    [ "$(logf decision)" = REJECT ]
    [ "$(logf reason)" = "no-verifiable-identity" ]
    [ "$(logf card_id)" = "" ]
  done
}

@test "validate: el estado debe ser exactamente active" {
  printf 'cards:\n  a:\n    id: "x1"\n    status: Active\n  b:\n    id: "x2"\n' > "$PLATFORM_CARDS_FILE"
  export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  run bash "$SCRIPT" validate --origin agent --agent-id x1
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" validate --origin agent --agent-id x2
  [ "$status" -eq 1 ]
}

@test "validate: tarjetas inexistentes, YAML roto o sin sección cards rechazan" {
  export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  printf 'otra: cosa\n' > "$PLATFORM_CARDS_FILE"
  run bash "$SCRIPT" validate --origin agent --agent-id x
  [ "$status" -eq 1 ]
  printf 'cards: [esto no es\n  un mapa' > "$PLATFORM_CARDS_FILE"
  run bash "$SCRIPT" validate --origin agent --agent-id x
  [ "$status" -eq 1 ]
  printf '' > "$PLATFORM_CARDS_FILE"
  run bash "$SCRIPT" validate --origin agent --agent-id x
  [ "$status" -eq 1 ]
}

@test "validate: sin fichero de tarjetas -> REJECT_NO_CARDS_FILE con la ruta y exit 1" {
  export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  run bash "$SCRIPT" validate --origin agent --agent-id x --platform-card "$TEST_DIR/falta.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REJECT_NO_CARDS_FILE: platform card registry not found at $TEST_DIR/falta.yaml"* ]]
  [ "$(logf decision)" = REJECT ]
}

@test "validate: --platform-card pisa PLATFORM_CARDS_FILE; sin él se usa la variable" {
  mk_cards "$TEST_DIR/otra.yaml"; export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  printf 'cards:\n  z:\n    id: "solo-env"\n    status: active\n' > "$PLATFORM_CARDS_FILE"
  run bash "$SCRIPT" validate --origin agent --agent-id solo-env
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" validate --origin agent --agent-id solo-env --platform-card "$TEST_DIR/otra.yaml"
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" validate --origin agent --agent-id ext-alpha --platform-card "$TEST_DIR/otra.yaml"
  [ "$status" -eq 0 ]
}

@test "validate: mensajes de error de uso salen con exit 2" {
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: --origin is required"* ]]
  run bash "$SCRIPT" validate --origin agent
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: --agent-id is required for agent origin"* ]]
  run bash "$SCRIPT" validate --origin robot
  [ "$status" -eq 2 ]
  [[ "$output" == *"Invalid origin 'robot'. Must be 'human' or 'agent'."* ]]
  run bash "$SCRIPT" validate --origin human --otra x
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option: --otra"* ]]
}

@test "validate: un origen inválido no escribe registro" {
  export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  run bash "$SCRIPT" validate --origin robot
  [ "$status" -eq 2 ]
  [ ! -e "$IDENTITY_LOG" ]
}

@test "registro: se acumula una línea JSON válida por intento y soporta comillas en el agent-id" {
  mk_cards "$PLATFORM_CARDS_FILE"; export IDENTITY_LOG="$TEST_DIR/log.jsonl"
  bash "$SCRIPT" validate --origin human >/dev/null
  bash "$SCRIPT" validate --origin agent --agent-id ext-alpha >/dev/null
  bash "$SCRIPT" validate --origin agent --agent-id "q'uo\"te" >/dev/null 2>&1 || true
  [ "$(wc -l < "$IDENTITY_LOG")" -eq 3 ]
  [ "$(logf agent_id)" = "q'uo\"te" ]
}

@test "registro: sin IDENTITY_LOG usa DATA_DIR/agent-request-identity.jsonl y crea el directorio" {
  unset IDENTITY_LOG
  export DATA_DIR="$TEST_DIR/nuevo/data"
  run bash "$SCRIPT" validate --origin human
  [ "$status" -eq 0 ]
  [ -s "$DATA_DIR/agent-request-identity.jsonl" ]
}

@test "identify: salida exacta para humano, agente y token con varios dos puntos" {
  run bash "$SCRIPT" identify --token "human:Ana Pérez"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ORIGIN: human" ]
  [ "${lines[1]}" = "DISPLAY_NAME: Ana Pérez" ]
  run bash "$SCRIPT" identify --token "agent:ext:alpha:1"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ORIGIN: agent" ]
  [ "${lines[1]}" = "AGENT_ID: ext:alpha:1" ]
}

@test "identify: resto vacío cae a unknown" {
  run bash "$SCRIPT" identify --token "human:"
  [ "${lines[1]}" = "DISPLAY_NAME: unknown" ]
  run bash "$SCRIPT" identify --token "agent:"
  [ "${lines[1]}" = "AGENT_ID: unknown" ]
}

@test "identify: origen desconocido -> exit 1 y eco del token" {
  run bash "$SCRIPT" identify --token "robot:r2"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "ORIGIN: unknown" ]
  [ "${lines[1]}" = "TOKEN: robot:r2" ]
}

@test "identify: sin token u opción desconocida -> exit 2" {
  run bash "$SCRIPT" identify
  [ "$status" -eq 2 ]
  [[ "$output" == *"--token is required"* ]]
  run bash "$SCRIPT" identify --otro x
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option: --otro"* ]]
}

@test "uso: sin subcomando muestra ambos subcomandos y los códigos de salida" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"validate  "* && "$output" == *"identify  "* ]]
  [[ "$output" == *"2 — usage error"* ]]
}
