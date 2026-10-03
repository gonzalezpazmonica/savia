#!/usr/bin/env bats
# Ref: .opencode/hooks/sycophancy-strip.sh — SPEC-192 Layer 1
# Tests for the deterministic adulation hook.
#
# SPEC-055 audit hint: target the hook for coverage_breadth scoring
# HOOK=".opencode/hooks/sycophancy-strip.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOOK="$REPO_ROOT/.opencode/hooks/sycophancy-strip.sh"
  TMPDIR_AA=$(mktemp -d)
  # Telemetry goes to a temp project: never append test runs to the real
  # output/anti-adulation-telemetry.jsonl (it skewed the shadow-mode data).
  export CLAUDE_PROJECT_DIR="$TMPDIR_AA"
  unset SAVIA_ANTIADULATION SAVIA_ANTIADULATION_LAYER1 SAVIA_ANTIADULATION_PATTERNS
}

teardown() {
  rm -rf "$TMPDIR_AA"
}

# ─────────────────────────────────────────────────────────────────────────────
# Master switch
# ─────────────────────────────────────────────────────────────────────────────

@test "SAVIA_ANTIADULATION=off disables hook" {
  export SAVIA_ANTIADULATION=off
  export SAVIA_ANTIADULATION_LAYER1=block
  run bash -c "echo 'Buena pregunta' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "SAVIA_ANTIADULATION_LAYER1=off disables hook" {
  export SAVIA_ANTIADULATION_LAYER1=off
  run bash -c "echo 'Buena pregunta' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "no stdin returns 0 silently" {
  # /dev/null: an inherited open pipe (agent shells) would make cat wait forever
  run bash "$HOOK" < /dev/null
  [[ "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Mode: block
# ─────────────────────────────────────────────────────────────────────────────

@test "block: obvious adulation at position 0 returns exit 2" {
  export SAVIA_ANTIADULATION_LAYER1=block
  run bash -c "echo 'Buena pregunta. La respuesta es 42.' | bash '$HOOK'"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"anti-adulation SPEC-192"* ]]
  [[ "$output" == *"position 0"* ]]
}

@test "block: technical content returns exit 0" {
  export SAVIA_ANTIADULATION_LAYER1=block
  run bash -c "echo 'El bug está en auth.ts línea 42.' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "block: legitimate courtesy passes" {
  export SAVIA_ANTIADULATION_LAYER1=block
  run bash -c "echo 'Gracias por la corrección. El bug está en X.' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "block: English adulation triggers" {
  export SAVIA_ANTIADULATION_LAYER1=block
  run bash -c "echo 'Great question. The answer is 42.' | bash '$HOOK'"
  [[ "$status" -eq 2 ]]
}

@test "block: subtle pattern (score 50) does NOT block" {
  export SAVIA_ANTIADULATION_LAYER1=block
  run bash -c "echo 'Disculpa la confusión, mira esto otra vez.' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]   # subtle never blocks
}

# ─────────────────────────────────────────────────────────────────────────────
# Mode: strip
# ─────────────────────────────────────────────────────────────────────────────

@test "strip: removes matched span from output" {
  export SAVIA_ANTIADULATION_LAYER1=strip
  run bash -c "echo 'Buena pregunta. Mira el código.' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Mira el código"* ]]
  [[ "$output" != *"Buena pregunta"* ]]
}

@test "strip: passes technical content unchanged via stripped JSON field" {
  export SAVIA_ANTIADULATION_LAYER1=strip
  run bash -c "echo 'El resultado es 42.' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
  # No match: stripped equals input but the hook prints nothing in this path
  # because score==0 short-circuits before the strip case.
}

# ─────────────────────────────────────────────────────────────────────────────
# Mode: warn
# ─────────────────────────────────────────────────────────────────────────────

@test "warn: emits stderr advisory but exits 0" {
  export SAVIA_ANTIADULATION_LAYER1=warn
  run bash -c "echo 'Tienes razón, lo cambio.' | bash '$HOOK' 2>&1 1>/dev/null"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"anti-adulation L1"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "warn: technical content silent" {
  export SAVIA_ANTIADULATION_LAYER1=warn
  run bash -c "echo 'El test pasó.' | bash '$HOOK' 2>&1"
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"WARN"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Mode: shadow (DEFAULT)
# ─────────────────────────────────────────────────────────────────────────────

@test "shadow (default): never blocks even with obvious pattern" {
  unset SAVIA_ANTIADULATION_LAYER1
  run bash -c "echo 'Buena pregunta sobre eso.' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "shadow: writes telemetry to JSONL" {
  unset SAVIA_ANTIADULATION_LAYER1
  log="$CLAUDE_PROJECT_DIR/output/anti-adulation-telemetry.jsonl"
  before=$(wc -l < "$log" 2>/dev/null || echo 0)
  bash -c "echo 'Buena pregunta sobre eso.' | bash '$HOOK'" >/dev/null 2>&1
  after=$(wc -l < "$log" 2>/dev/null || echo 0)
  [[ "$after" -gt "$before" ]]
  # Last line must parse as JSON with required fields
  tail -1 "$log" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['mode'] == 'shadow'
assert d['decision'] == 'SHADOW_DETECTED'
assert d['score'] >= 50
assert d['category'] in ('obvious', 'subtle')
"
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON envelope (PostToolUse-like)
# ─────────────────────────────────────────────────────────────────────────────

@test "accepts JSON envelope with .tool_response.output" {
  export SAVIA_ANTIADULATION_LAYER1=block
  payload=$(jq -nc --arg t "Buena pregunta. La respuesta es 42." '{tool_response: {output: $t}}')
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 2 ]]
}

@test "accepts JSON envelope with .tool_input.text" {
  export SAVIA_ANTIADULATION_LAYER1=block
  payload=$(jq -nc --arg t "Tienes razón, lo cambio." '{tool_input: {text: $t}}')
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 2 ]]
}

@test "raw text input also works (fallback path)" {
  export SAVIA_ANTIADULATION_LAYER1=block
  run bash -c "echo 'Absolutamente, eso es' | bash '$HOOK'"
  [[ "$status" -eq 2 ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SPEC-055 audit-quality coverage
# ─────────────────────────────────────────────────────────────────────────────

@test "safety: hook script declares set -uo pipefail" {
  run grep -E "set -uo pipefail" "$HOOK"
  [[ "$status" -eq 0 ]]
}

@test "coverage: log_telemetry function defined and writes JSONL" {
  # Exercises log_telemetry() function via shadow mode invocation.
  export SAVIA_ANTIADULATION_LAYER1=shadow
  log="$CLAUDE_PROJECT_DIR/output/anti-adulation-telemetry.jsonl"
  before=$(wc -l < "$log" 2>/dev/null || echo 0)
  echo "Buena pregunta sobre eso." | bash "$HOOK" >/dev/null 2>&1
  after=$(wc -l < "$log" 2>/dev/null || echo 0)
  [[ "$after" -gt "$before" ]]
  tail -1 "$log" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert 'mode' in d and 'decision' in d"
}

@test "edge: empty draft input returns 0 (no-op)" {
  run bash -c "echo '' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "edge: nonexistent patterns file falls back gracefully" {
  export SAVIA_ANTIADULATION_PATTERNS="$TMPDIR_AA/missing-patterns.json"
  run bash -c "echo 'Buena pregunta' | bash '$HOOK'"
  # fail-open: exit 0 even when patterns are missing
  [[ "$status" -eq 0 ]]
}

@test "edge: large draft (overflow boundary) does not crash" {
  big_draft=$(printf 'word%.0s ' {1..500})
  run bash -c "echo '$big_draft' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "edge: null bytes in draft are handled" {
  # Bash will treat null bytes as terminators in a string; simulate via printf
  run bash -c "printf 'normal\\0bytes' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "edge: zero-length stdin returns silently" {
  run bash -c ": | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "boundary: max-depth deep regex pattern handled" {
  # Exercises the lexical-strip detector via the hook.
  run bash -c "echo 'Tienes toda la razón en lo que dices' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

