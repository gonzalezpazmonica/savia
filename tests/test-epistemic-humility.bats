#!/usr/bin/env bats
# Ref: .claude/skills/epistemic-humility/SKILL.md (Patrón A — adulación refleja)
# Ref: docs/propuestas/SPEC-192-anti-adulation-illusory-truth.md (Layer 1)
# Ref: docs/rules/domain/radical-honesty.md (Rule #24)
#
# Calibración SE-376: la capa determinista de la skill es el hook
# sycophancy-strip.sh (PostToolUse, matcher Task). Estos tests ejercitan el
# hook con los sobres reales de Claude Code y con la lista NUNCA de la skill.
# Cada caso positivo usa modo block para que la detección sea observable por
# exit code; la telemetría se escribe siempre en un CLAUDE_PROJECT_DIR temporal.

SCRIPT=".claude/hooks/sycophancy-strip.sh"
DETECTOR="scripts/anti-adulation/lexical-strip.py"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$REPO_ROOT/$SCRIPT"
  TMPDIR_EH="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$TMPDIR_EH/proyecto con espacios"
  mkdir -p "$CLAUDE_PROJECT_DIR"
  LOG="$CLAUDE_PROJECT_DIR/output/anti-adulation-telemetry.jsonl"
  unset SAVIA_ANTIADULATION SAVIA_ANTIADULATION_PATTERNS
  export SAVIA_ANTIADULATION_LAYER1=block
}

teardown() {
  rm -rf "$TMPDIR_EH"
}

# Ejecuta el hook con el texto dado por stdin.
hook_with() {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$1" "$HOOK"
}

# Sobre PostToolUse real de Claude Code para la herramienta Task/Agent.
cc_envelope() {
  jq -nc --arg t "$1" '{hook_event_name:"PostToolUse", tool_name:"Task",
    tool_input:{description:"x", prompt:"tarea"},
    tool_response:{status:"completed", content:[{type:"text", text:$t}]}}'
}

last_decision() {
  tail -1 "$LOG" | jq -r '.decision'
}

# ── Contrato estructural ─────────────────────────────────────────────────────

@test "safety: el hook declara set -uo pipefail y pasa bash -n" {
  run grep -cE '^set -uo pipefail' "$HOOK"
  [ "$output" -ge 1 ]
  run bash -n "$HOOK"
  [ "$status" -eq 0 ]
}

# ── Sobres reales de Claude Code (antes: el hook escaneaba el JSON crudo) ────

@test "block: sobre real con tool_response.content[].text detecta adulación" {
  hook_with "$(cc_envelope 'Buena pregunta. La respuesta es 42.')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"anti-adulation SPEC-192"* ]]
  [ "$(last_decision)" = "BLOCKED" ]
}

@test "block: tool_response como cadena detecta adulación" {
  hook_with "$(jq -nc '{tool_name:"Task", tool_response:"Tienes razón, lo cambio."}')"
  [ "$status" -eq 2 ]
}

@test "block: tool_response como lista de bloques de texto detecta adulación" {
  hook_with "$(jq -nc '{tool_name:"Task", tool_response:[{type:"text", text:"Great question. The answer is 42."}]}')"
  [ "$status" -eq 2 ]
}

@test "block: varios bloques de texto se concatenan y el primero cuenta" {
  hook_with "$(jq -nc '{tool_response:{content:[{type:"text",text:"Gran idea."},{type:"text",text:"Detalle técnico."}]}}')"
  [ "$status" -eq 2 ]
}

@test "negative: sobre sin texto de respuesta no escanea el prompt y lo registra" {
  # El prompt contiene adulación pero no es salida del agente: no debe bloquear.
  hook_with "$(jq -nc '{tool_name:"Task", tool_input:{prompt:"Buena pregunta"}, tool_response:{status:"async_launched", agentId:"a1"}}')"
  [ "$status" -eq 0 ]
  [ "$(last_decision)" = "NO_TEXT" ]
}

@test "negative: sobre real con contenido técnico pasa y registra PASS" {
  hook_with "$(cc_envelope 'El bug está en auth.ts línea 42.')"
  [ "$status" -eq 0 ]
  [ "$(last_decision)" = "PASS" ]
  # draft_len mide el texto del agente, no el JSON del sobre
  [ "$(tail -1 "$LOG" | jq -r '.draft_len')" -eq "$(printf '%s' 'El bug está en auth.ts línea 42.' | wc -m)" ]
}

# ── Lista NUNCA de la skill (Patrón A) ───────────────────────────────────────

@test "block: apertura española con signo de exclamación inicial" {
  hook_with '¡Buena pregunta! La respuesta es 42.'
  [ "$status" -eq 2 ]
  hook_with '¡Tienes toda la razón!'
  [ "$status" -eq 2 ]
}

@test "block: fórmulas de acuerdo seguidas de punto o al final del texto" {
  for d in 'Por supuesto. Aquí está.' 'Absolutamente.' 'Claro que sí.' 'Of course! Here it is.'; do
    hook_with "$d"
    [ "$status" -eq 2 ] || { echo "no bloqueó: $d"; return 1; }
  done
}

@test "block: apertura en negrita markdown" {
  hook_with '**Buena pregunta.** La respuesta es 42.'
  [ "$status" -eq 2 ]
}

@test "negative: adverbio con contenido no es adulación (reject false positive)" {
  hook_with 'Absolutamente todos los tests fallan con exit 2.'
  [ "$status" -eq 0 ]
  hook_with 'Por supuestos de partida erróneos, el plan falla.'
  [ "$status" -eq 0 ]
}

@test "negative: cortesía con sustancia pasa (Gracias por la corrección)" {
  hook_with 'Gracias por la corrección. El bug está en X.'
  [ "$status" -eq 0 ]
}

# ── Fallos silenciosos ───────────────────────────────────────────────────────

@test "large: borrador de 200 KB con adulación inicial se bloquea" {
  big="$TMPDIR_EH/big.txt"
  python3 -c "print('Buena pregunta. ' + 'x' * 200000)" > "$big"
  run bash -c 'bash "$1" < "$2"' _ "$HOOK" "$big"
  [ "$status" -eq 2 ]
  [ "$(last_decision)" = "BLOCKED" ]
}

@test "error: fichero de patrones ausente hace fail-open pero deja rastro" {
  export SAVIA_ANTIADULATION_PATTERNS="$TMPDIR_EH/no-existe.json"
  hook_with 'Buena pregunta.'
  [ "$status" -eq 0 ]
  [ "$(last_decision)" = "FAIL_OPEN" ]
}

@test "error: patrones inválidos hacen fail-open con rastro" {
  printf '{"obvious": ["("]}' > "$TMPDIR_EH/bad.json"
  export SAVIA_ANTIADULATION_PATTERNS="$TMPDIR_EH/bad.json"
  hook_with 'Buena pregunta.'
  [ "$status" -eq 0 ]
  [ "$(last_decision)" = "FAIL_OPEN" ]
}

# ── Modos y límites ──────────────────────────────────────────────────────────

@test "boundary: modo desconocido cae a shadow (no bloquea, registra)" {
  export SAVIA_ANTIADULATION_LAYER1=bogus
  hook_with 'Buena pregunta.'
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$LOG" | jq -r '.mode')" = "shadow" ]
  [ "$(last_decision)" = "SHADOW_DETECTED" ]
}

@test "boundary: master switch off no escribe telemetría" {
  export SAVIA_ANTIADULATION=off
  hook_with 'Buena pregunta.'
  [ "$status" -eq 0 ]
  [ ! -e "$LOG" ]
}

@test "empty: stdin vacío sale 0 sin telemetría" {
  hook_with ''
  [ "$status" -eq 0 ]
  [ ! -e "$LOG" ]
}

@test "strip: elimina la apertura y conserva el contenido" {
  export SAVIA_ANTIADULATION_LAYER1=strip
  hook_with "$(cc_envelope '¡Buena pregunta! Mira el código.')"
  [ "$status" -eq 0 ]
  [ "$output" = "Mira el código." ]
}

@test "detector: --draft - lee el borrador por stdin" {
  run bash -c 'printf "Buena pregunta. X" | python3 "$1" --draft - --json' _ "$REPO_ROOT/$DETECTOR"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.score')" -eq 95 ]
}
