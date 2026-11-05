#!/usr/bin/env bats
# BATS tests for scripts/ext-platform-gate.sh
# SE-272 Slice 4 — External platform gate: asymmetry + deny-by-default allowlist.
# Ref: docs/propuestas/SE-272-servicio-gestionado.md

SCRIPT="scripts/ext-platform-gate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  TEST_DIR=$(mktemp -d "$TMPDIR/epg-XXXXXX")
  export DATA_DIR="$TEST_DIR/data"
  mkdir -p "$DATA_DIR"

  # Create cards file
  export PLATFORM_CARDS_FILE="$TEST_DIR/cards.yaml"
  cat > "$PLATFORM_CARDS_FILE" << 'YAMLEOF'
version: "1.0"
spec: "SE-272"
cards:
  client-alpha-platform:
    id: "ext-platform-client-alpha-9901"
    organization: "Client Alpha Corp"
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx..."
    exposed_skills:
      - "situacion.query"
      - "dependency.notify"
      - "handoff.request"
    allowed_skills:
      - "situacion.query"
      - "dependency.notify"
    max_payload_level: 2
    engagement: "engagements/2026-client-alpha-001"
    status: active
  limited-platform:
    id: "ext-platform-limited-9902"
    organization: "Limited Corp"
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGy..."
    exposed_skills:
      - "situacion.query"
      - "commitment.propose"
    allowed_skills:
      - "situacion.query"
    max_payload_level: 1
    engagement: "engagements/2026-limited-001"
    status: active
  inactive-platform:
    id: "ext-platform-inactive-9903"
    organization: "Inactive Corp"
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGz..."
    exposed_skills: ["situacion.query"]
    allowed_skills: ["situacion.query"]
    max_payload_level: 1
    engagement: "engagements/2026-inactive-001"
    status: suspended
default: deny
YAMLEOF

  # Create allowlist file
  export ALLOWLIST_FILE="$TEST_DIR/allowlist.yaml"
  cat > "$ALLOWLIST_FILE" << 'YAMLEOF'
version: 1
skills:
  situacion.query:
    allow: true
    maxLevel: 2
    readOnly: true
  dependency.notify:
    allow: true
    maxLevel: 2
    readOnly: true
  commitment.propose:
    allow: true
    maxLevel: 2
    readOnly: false
  commitment.ack:
    allow: true
    maxLevel: 2
    readOnly: false
  handoff.request:
    allow: true
    maxLevel: 2
    readOnly: false
default: deny
YAMLEOF
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

# ── gate: allowed skill ──────────────────────────────

@test "gate: allowed skill passes" {
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-client-alpha-9901" \
    --skill "situacion.query" \
    --payload-level 2 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALLOW"* ]]
}

@test "gate: allowed skill with valid payload level" {
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-limited-9902" \
    --skill "situacion.query" \
    --payload-level 1 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALLOW"* ]]
}

# ── gate: deny-by-default — skill not in allowlist ──

@test "gate: skill not in global allowlist denied" {
  # Use a skill that's never in the allowlist
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-client-alpha-9901" \
    --skill "deploy.apply" \
    --payload-level 1 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENY"* ]]
}

# ── gate: skill not in card's allowed_skills ─────────

@test "gate: exposed-but-not-allowed skill denied" {
  # handoff.request is in exposed_skills but NOT in allowed_skills for alpha
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-client-alpha-9901" \
    --skill "handoff.request" \
    --payload-level 1 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENY"* ]]
}

@test "gate: skill not in card's exposed_skills at all" {
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-client-alpha-9901" \
    --skill "commitment.propose" \
    --payload-level 1 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENY"* ]]
}

# ── gate: payload level exceeds card max ─────────────

@test "gate: payload level above card max denied" {
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-limited-9902" \
    --skill "situacion.query" \
    --payload-level 3 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENY"* ]]
}

# ── gate: inactive card ──────────────────────────────

@test "gate: inactive platform card denied" {
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-inactive-9903" \
    --skill "situacion.query" \
    --payload-level 1 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENY"* ]]
}

# ── gate: unknown card id ────────────────────────────

@test "gate: unknown card id denied" {
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-nonexistent" \
    --skill "situacion.query" \
    --payload-level 1 \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 1 ]
}

# ── check-principal ──────────────────────────────────

@test "check-principal: confirms ext platforms are not principals" {
  run bash "$SCRIPT" check-principal
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEVER principal"* ]]
  [[ "$output" == *"PASS"* ]]
}

# ── list-deny ────────────────────────────────────────

@test "list-deny: produces audit output" {
  run bash "$SCRIPT" list-deny \
    --cards-file "$PLATFORM_CARDS_FILE" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DENY-BY-DEFAULT"* ]]
}

# ── Missing files ────────────────────────────────────

@test "gate: missing cards file returns error" {
  run bash "$SCRIPT" gate \
    --card-id "ext-platform-client-alpha-9901" \
    --skill "situacion.query" \
    --payload-level 1 \
    --cards-file "$TEST_DIR/nonexistent.yaml" \
    --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 1 ]
}

# ── Coverage ─────────────────────────────────────────

@test "coverage: exit codes 0,1,2 all used" {
  run grep -c 'exit 0\|exit 1\|exit 2' "$SCRIPT"
  [[ "$output" -ge 3 ]]
}

@test "coverage: deny-by-default mentioned" {
  run grep -ci 'deny.by.default\|deny_by_default\|DENY' "$SCRIPT"
  [[ "$output" -ge 2 ]]
}

# ── S03n: comportamiento discriminante ───────────────

_gate() {
  bash "$SCRIPT" gate --cards-file "$PLATFORM_CARDS_FILE" --allowlist "$ALLOWLIST_FILE" "$@"
}

@test "S03n seguridad: una comilla en --card-id no suplanta otra tarjeta activa" {
  run _gate --card-id "nadie' or 'a'=='a" --skill "situacion.query" --payload-level 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found or inactive"* ]]
  [[ "$output" != *"ALLOW"* ]]
}

@test "S03n seguridad: una comilla en --skill no amplía la allowlist global" {
  run _gate --card-id "ext-platform-client-alpha-9901" --skill "x' or True or '" --payload-level 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in card allowed_skills"* ]]
}

@test "S03n seguridad: --payload-level no numérico es error de uso, no nivel 0" {
  run _gate --card-id "ext-platform-client-alpha-9901" --skill "situacion.query" --payload-level "abc"
  [ "$status" -eq 2 ]
  [[ "$output" != *"ALLOW"* ]]
}

@test "S03n seguridad: --payload-level no se evalúa como expresión aritmética" {
  local marker="$TEST_DIR/pwned"
  run _gate --card-id "ext-platform-client-alpha-9901" --skill "situacion.query" \
    --payload-level "a[\$(touch $marker)]"
  [ "$status" -eq 2 ]
  [ ! -e "$marker" ]
}

@test "S03n frontera: payload igual al máximo de la tarjeta pasa y uno más se deniega" {
  run _gate --card-id "ext-platform-limited-9902" --skill "situacion.query" --payload-level 1
  [ "$status" -eq 0 ]
  [[ "$output" == "ALLOW: card_id=ext-platform-limited-9902 skill=situacion.query payload_level=1" ]]
  run _gate --card-id "ext-platform-limited-9902" --skill "situacion.query" --payload-level 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"payload_level=2 exceeds card max=1"* ]]
}

@test "S03n frontera: el máximo de la allowlist global también limita" {
  # La tarjeta permite hasta 2; la allowlist baja situacion.query a 1.
  sed -i '/situacion.query:/,/readOnly/ s/maxLevel: 2/maxLevel: 1/' "$ALLOWLIST_FILE"
  run _gate --card-id "ext-platform-client-alpha-9901" --skill "situacion.query" --payload-level 1
  [ "$status" -eq 0 ]
  run _gate --card-id "ext-platform-client-alpha-9901" --skill "situacion.query" --payload-level 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"exceeds allowlist max=1"* ]]
}

@test "S03n: skill permitida por la tarjeta pero con allow:false en la allowlist se deniega" {
  sed -i '/dependency.notify:/,/readOnly/ s/allow: true/allow: false/' "$ALLOWLIST_FILE"
  run _gate --card-id "ext-platform-client-alpha-9901" --skill "dependency.notify"
  [ "$status" -eq 1 ]
  [[ "$output" == *"denied by global allowlist — deny_by_default"* ]]
}

@test "S03n: allowlist ausente deniega (fail-closed)" {
  run bash "$SCRIPT" gate --cards-file "$PLATFORM_CARDS_FILE" --allowlist "$TEST_DIR/no-hay.yaml" \
    --card-id "ext-platform-client-alpha-9901" --skill "situacion.query"
  [ "$status" -eq 1 ]
  [[ "$output" == *"denied by global allowlist — allowlist_unavailable"* ]]
}

@test "S03n: allowlist con default allow deja pasar una skill no listada si la tarjeta la permite" {
  printf 'version: 1\nskills: {}\ndefault: allow\n' > "$ALLOWLIST_FILE"
  run _gate --card-id "ext-platform-client-alpha-9901" --skill "dependency.notify" --payload-level 2
  [ "$status" -eq 0 ]
}

@test "S03n: cada decisión queda en el log JSONL con su motivo" {
  _gate --card-id "ext-platform-client-alpha-9901" --skill "situacion.query" --payload-level 1 || true
  _gate --card-id "ext-platform-inactive-9903" --skill "situacion.query" || true
  python3 - "$DATA_DIR/ext-platform-gate-decisions.jsonl" <<'PY'
import json,sys
recs=[json.loads(l) for l in open(sys.argv[1])]
assert [(r["decision"],r["reason"]) for r in recs]==[("ALLOW","all_checks_passed"),("DENY","card_not_found_or_inactive")], recs
assert recs[0]["card_id"]=="ext-platform-client-alpha-9901" and recs[0]["skill"]=="situacion.query"
PY
}

@test "S03n: el log registra también entradas con comillas sin perder la decisión" {
  _gate --card-id "o'brien" --skill "situacion.query" || true
  python3 - "$DATA_DIR/ext-platform-gate-decisions.jsonl" <<'PY'
import json,sys
recs=[json.loads(l) for l in open(sys.argv[1])]
assert len(recs)==1 and recs[0]["card_id"]=="o'brien" and recs[0]["decision"]=="DENY", recs
PY
}

@test "S03n: faltan --card-id o --skill → exit 2" {
  run _gate --skill "situacion.query"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--card-id is required"* ]]
  run _gate --card-id "ext-platform-client-alpha-9901"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--skill is required"* ]]
}

@test "S03n: list-deny muestra las expuestas no permitidas y omite tarjetas suspendidas" {
  run bash "$SCRIPT" list-deny --cards-file "$PLATFORM_CARDS_FILE" --allowlist "$ALLOWLIST_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exposed_but_not_allowed(denied): ['handoff.request']"* ]]
  [[ "$output" == *"exposed_but_not_allowed(denied): ['commitment.propose']"* ]]
  [[ "$output" != *"inactive-platform"* ]]
  [[ "$output" == *"Default: deny"* ]]
}

@test "S03n: tarjeta sin max_payload_level entero se deniega y lo registra (fail-closed)" {
  sed -i '/ext-platform-limited-9902/,/status/ s/max_payload_level: 1/max_payload_level: "alto"/' "$PLATFORM_CARDS_FILE"
  run _gate --card-id "ext-platform-limited-9902" --skill "situacion.query" --payload-level 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no valid max_payload_level"* ]]
  run grep -c '"reason": "card_max_payload_level_invalid"' "$DATA_DIR/ext-platform-gate-decisions.jsonl"
  [ "$output" = "1" ]
}
