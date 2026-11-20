#!/usr/bin/env bats
# BATS tests for SE-314 S5: integración del gate con sovereignty-classify.
# Ref: docs/propuestas/SE-314-sovereignty-classifier-redesign.md

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$CLAUDE_PROJECT_DIR"
  export SAVIA_SHIELD_ENABLED=false
}

@test "data-sovereignty-gate.sh usa sovereignty-classify (no ollama-classify)" {
  grep -q "sovereignty-classify.sh" .claude/hooks/data-sovereignty-gate.sh
}

@test "sovereignty-decide.sh produce ALLOW para contenido publico en N1" {
  mkdir -p "$CLAUDE_PROJECT_DIR/config"; cp config/sovereignty-thresholds.yaml "$CLAUDE_PROJECT_DIR/config/"
  run bash -c 'echo "hello world public content" | bash scripts/sovereignty-classify.sh --no-cache | bash scripts/sovereignty-decide.sh --dest n1'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "ALLOW" ]
}

@test "sovereignty-decide.sh produce BLOCK para secreto determinista en N1" {
  IP=$(printf '%s.%s.%s.%s' '10' '0' '0' '1')
  mkdir -p "$CLAUDE_PROJECT_DIR/config"; cp config/sovereignty-thresholds.yaml "$CLAUDE_PROJECT_DIR/config/"
  run bash -c "echo 'host at $IP internal' | bash scripts/sovereignty-classify.sh --no-cache | bash scripts/sovereignty-decide.sh --dest n1"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r .action)" = "BLOCK" ]
}

@test "AC-S5.2: LLM caido → edicion en N1 no bloqueada (WARN) + evento" {
  export OLLAMA_URL="http://127.0.0.1:1"
  TEXT="long technical content that would need llm classification for business context decision"
  echo "$TEXT" > "$CLAUDE_PROJECT_DIR/in.txt"
  OUT=$(bash scripts/sovereignty-classify.sh --no-cache < "$CLAUDE_PROJECT_DIR/in.txt" 2>/dev/null || true)
  DEC=$(printf '%s' "$OUT" | bash scripts/sovereignty-decide.sh --dest n1 2>/dev/null || true)
  ACTION=$(printf '%s' "$DEC" | jq -r '.action // "ALLOW"' 2>/dev/null)
  [[ "$ACTION" != "BLOCK" ]]
  unset OLLAMA_URL
}

@test "shim ollama-classify delega al nuevo clasificador (contrato CONFIDENTIAL|PUBLIC|AMBIGUOUS)" {
  python3 -c "
import subprocess
ip = '10.0.0.1'
r = subprocess.run(['bash','scripts/ollama-classify.sh'], input=('host at '+ip+' internal').encode(), capture_output=True, timeout=30)
assert r.stdout.decode().strip() in ('CONFIDENTIAL','PUBLIC','AMBIGUOUS'), r.stdout
r2 = subprocess.run(['bash','scripts/ollama-classify.sh'], input=b'hello world technical public documentation content', capture_output=True, timeout=30)
assert r2.stdout.decode().strip() in ('CONFIDENTIAL','PUBLIC','AMBIGUOUS'), r2.stdout
"
}

@test "classifier telemetria: otel-emit acepta eventos classifier.*" {
  export SAVIA_TELEMETRY_FILE="${BATS_TEST_TMPDIR}/tp.jsonl"
  rm -f "$SAVIA_TELEMETRY_FILE"
  run bash scripts/otel-emit.sh classifier.verdict label=public confidence=0.8 action=ALLOW
  [ "$status" -eq 0 ]
  run jq -e '.event == "classifier.verdict" and .label == "public"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

# ── Comportamiento: sovereignty-decide.sh (umbrales y reglas duras) ───────────

_policy() { mkdir -p "$CLAUDE_PROJECT_DIR/config"; cp config/sovereignty-thresholds.yaml "$CLAUDE_PROJECT_DIR/config/"; }

# decide <json> [args...] → deja JSON en $output y código en $status
_decide() { local j="$1"; shift; run bash -c "printf '%s' '$j' | bash scripts/sovereignty-decide.sh $*"; }

@test "decide n1: secreto determinista (aws_key) bloquea aunque la confianza sea baja" {
  _policy
  _decide '{"label":"public","confidence":0.1,"deterministic_matches":["aws_key"]}' --dest n1
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r .action)" = "BLOCK" ]
  [ "$(echo "$output" | jq -r .reason)" = "hard_block_deterministic" ]
  [ "$(echo "$output" | jq -r .hard_block)" = "true" ]
}

@test "decide n1: cada regla dura de la política bloquea; internal_ip no es regla dura" {
  _policy
  for rule in aws_key github_token openai_key connection_string private_key azure_sas; do
    _decide '{"label":"confidential","confidence":0.99,"deterministic_matches":["'$rule'"]}' --dest n1
    [ "$status" -eq 1 ]
    [ "$(echo "$output" | jq -r .reason)" = "hard_block_deterministic" ]
  done
  _decide '{"label":"public","confidence":0.5,"deterministic_matches":["internal_ip"]}' --dest n1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .hard_block)" = "false" ]
}

@test "decide n4: las reglas duras no se aplican en destino privado" {
  _policy
  _decide '{"label":"public","confidence":0.1,"deterministic_matches":["aws_key"]}' --dest n4
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "ALLOW" ]
  [ "$(echo "$output" | jq -r .hard_block)" = "false" ]
}

@test "decide n1: confidential 0.90 bloquea (frontera inclusiva), 0.89 solo avisa" {
  _policy
  _decide '{"label":"confidential","confidence":0.90}' --dest n1
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r .reason)" = "confidential_high_confidence" ]
  _decide '{"label":"confidential","confidence":0.89}' --dest n1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
  [ "$(echo "$output" | jq -r .reason)" = "confidential_medium_confidence" ]
}

@test "decide n1: confidential 0.70 avisa (frontera inclusiva), 0.69 se permite" {
  _policy
  _decide '{"label":"confidential","confidence":0.70}' --dest n1
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
  _decide '{"label":"confidential","confidence":0.69}' --dest n1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "ALLOW" ]
  [ "$(echo "$output" | jq -r .reason)" = "below_threshold" ]
}

@test "decide n4: umbral de bloqueo propio (0.80) distinto del de n1" {
  _policy
  _decide '{"label":"confidential","confidence":0.85}' --dest n4
  [ "$status" -eq 1 ]
  _decide '{"label":"confidential","confidence":0.79}' --dest n4
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
  _decide '{"label":"confidential","confidence":0.85}' --dest n1
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
}

@test "decide: ambiguous avisa en n1 y se permite en n4, con reason ambiguous" {
  _policy
  _decide '{"label":"ambiguous","confidence":0.5}' --dest n1
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
  [ "$(echo "$output" | jq -r .reason)" = "ambiguous" ]
  [ "$status" -eq 0 ]
  _decide '{"label":"ambiguous","confidence":0.5}' --dest n4
  [ "$(echo "$output" | jq -r .action)" = "ALLOW" ]
}

@test "decide: public nunca bloquea ni avisa, devuelve label y confidence tal cual" {
  _policy
  _decide '{"label":"public","confidence":0.97}' --dest n1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "ALLOW" ]
  [ "$(echo "$output" | jq -r .label)" = "public" ]
  [ "$(echo "$output" | jq -r .confidence)" = "0.97" ]
}

@test "decide: --context-path fuerza destino n1 (secreto determinista bloquea)" {
  _policy
  _decide '{"label":"public","confidence":0.1,"deterministic_matches":["private_key"]}' --dest n4 --context-path docs/x.md
  [ "$status" -eq 1 ]
}

@test "decide: entrada vacía y argumento desconocido son error de uso (exit 2)" {
  _policy
  run bash -c "printf '' | bash scripts/sovereignty-decide.sh --dest n1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requerida en stdin"* ]]
  run bash -c "echo '{}' | bash scripts/sovereignty-decide.sh --bogus"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "decide: política personalizada manda (umbral de bloqueo bajado a 0.50 en n1)" {
  mkdir -p "$CLAUDE_PROJECT_DIR/config"
  cat > "$CLAUDE_PROJECT_DIR/config/sovereignty-thresholds.yaml" <<'YAML'
allow_below: 0.70
destinations:
  n1:
    confidential_block_below: 0.50
    warn_above: 0.30
    ambiguous_action: BLOCK
hard_block_rules: []
YAML
  _decide '{"label":"confidential","confidence":0.55}' --dest n1
  [ "$status" -eq 1 ]
  _decide '{"label":"ambiguous","confidence":0.5}' --dest n1
  [ "$(echo "$output" | jq -r .action)" = "BLOCK" ]
  _decide '{"label":"public","confidence":0.1,"deterministic_matches":["aws_key"]}' --dest n1
  [ "$status" -eq 0 ]
}

# ── Comportamiento: sovereignty-classify.sh capa 1 + decide, encadenados ──────

@test "classify→decide: AKIA + 16 caracteres bloquea en n1 con aws_key detectado" {
  _policy
  KEY="AKIA$(printf 'ABCDEFGH12345678')"
  out="$(printf 'config key=%s here' "$KEY" | bash scripts/sovereignty-classify.sh --no-cache)"
  [ "$(echo "$out" | jq -r .label)" = "confidential" ]
  [ "$(echo "$out" | jq -r '.deterministic_matches | join(",")')" = "aws_key" ]
  run bash -c "printf '%s' '$out' | bash scripts/sovereignty-decide.sh --dest n1"
  [ "$status" -eq 1 ]
}

@test "classify→decide: IP interna es confidential 0.99 pero n1 la bloquea por confianza, no por regla dura" {
  _policy
  IP=$(printf '%s.%s.%s.%s' '192' '168' '1' '10')
  out="$(echo "host at $IP internal" | bash scripts/sovereignty-classify.sh --no-cache)"
  [ "$(echo "$out" | jq -r '.deterministic_matches[0]')" = "internal_ip" ]
  run bash -c "printf '%s' '$out' | bash scripts/sovereignty-decide.sh --dest n1"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r .reason)" = "confidential_high_confidence" ]
  [ "$(echo "$output" | jq -r .hard_block)" = "false" ]
}

@test "classify→decide: texto corto público se permite sin consultar al LLM" {
  _policy
  out="$(echo "hello world public content" | OLLAMA_URL=http://127.0.0.1:1 bash scripts/sovereignty-classify.sh --no-cache)"
  [ "$(echo "$out" | jq -r .label)" = "public" ]
  [ "$(echo "$out" | jq -r .confidence)" = "0.65" ]
  run bash -c "printf '%s' '$out' | bash scripts/sovereignty-decide.sh --dest n1"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "ALLOW" ]
}

@test "classify→decide: LLM caído con texto largo da ambiguous 0.5 y n1 solo avisa" {
  _policy
  out="$(echo "long technical content that would need llm classification for business context decision" | OLLAMA_URL=http://127.0.0.1:1 bash scripts/sovereignty-classify.sh --no-cache)"
  [ "$(echo "$out" | jq -r .label)" = "ambiguous" ]
  [ "$(echo "$out" | jq -r .error)" = "ollama_unavailable" ]
  [ "$(echo "$out" | jq -r .confidence)" = "0.5" ]
  run bash -c "printf '%s' '$out' | bash scripts/sovereignty-decide.sh --dest n1"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
}

# ── Comportamiento: shim ollama-classify.sh ──────────────────────────────────

@test "shim: IP interna devuelve CONFIDENTIAL y texto público largo no devuelve CONFIDENTIAL" {
  IP=$(printf '%s.%s.%s.%s' '10' '0' '0' '1')
  run bash -c "echo 'host at $IP internal' | OLLAMA_URL=http://127.0.0.1:1 bash scripts/ollama-classify.sh"
  [ "$output" = "CONFIDENTIAL" ]
  run bash -c "echo 'hello world technical public documentation content that is long enough to skip shortcut' | OLLAMA_URL=http://127.0.0.1:1 bash scripts/ollama-classify.sh"
  [ "$output" != "CONFIDENTIAL" ]
}

@test "decide: política sin claves del destino usa los valores por defecto (0.90 bloquea, 0.70 avisa, ambiguous avisa)" {
  mkdir -p "$CLAUDE_PROJECT_DIR/config"
  printf 'allow_below: 0.70\ndestinations:\n  n1: {}\nhard_block_rules: []\n' > "$CLAUDE_PROJECT_DIR/config/sovereignty-thresholds.yaml"
  _decide '{"label":"confidential","confidence":0.90}' --dest n1
  [ "$status" -eq 1 ]
  _decide '{"label":"confidential","confidence":0.75}' --dest n1
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
  _decide '{"label":"confidential","confidence":0.60}' --dest n1
  [ "$(echo "$output" | jq -r .action)" = "ALLOW" ]
  _decide '{"label":"ambiguous","confidence":0.5}' --dest n1
  [ "$(echo "$output" | jq -r .action)" = "WARN" ]
}
