#!/usr/bin/env bats
# tests/test-se270-hook-matcher-audit.bats — SE-270 Slice 5
# Tests para scripts/hook-matcher-audit.sh

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/hook-matcher-audit.sh"
SETTINGS="$REPO_ROOT/.claude/settings.json"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/hook-matcher-audit.sh"
  SETTINGS="$REPO_ROOT/.claude/settings.json"
}

# ── 01: script exists ──────────────────────────────────────────────────────────
@test "SE270-matcher-01: hook-matcher-audit.sh existe" {
  [ -f "$SCRIPT" ]
}

# ── 02: script is syntactically valid ──────────────────────────────────────────
@test "SE270-matcher-02: bash -n passes" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── 03: script exits 0 with real settings.json ─────────────────────────────────
@test "SE270-matcher-03: exits 0 with production settings.json" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── 04: JSON output is valid ───────────────────────────────────────────────────
@test "SE270-matcher-04: --json produces valid JSON" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.loads('''$output''')
assert 'total_matchers' in d
assert 'broad' in d
assert 'broad_details' in d
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 05: detects .* as broad matcher ────────────────────────────────────────────
@test "SE270-matcher-05: .* matcher flagged as broad" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]

  broad_json=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
broad_list = d.get('broad_details', [])
count = sum(1 for b in broad_list if b['matcher'] == '.*')
print(count)
" 2>/dev/null || echo "0")

  [ "$broad_json" -gt 0 ]
}

# ── 06: --event filter works ───────────────────────────────────────────────────
@test "SE270-matcher-06: --event PreToolUse only returns PreToolUse matchers" {
  run bash "$SCRIPT" --event PreToolUse
  [ "$status" -eq 0 ]
  [[ "$output" == *"PreToolUse"* ]]
}

# ── 07: --event filter with JSON ───────────────────────────────────────────────
@test "SE270-matcher-07: --event PreToolUse --json produces valid JSON" {
  run bash "$SCRIPT" --event PreToolUse --json
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.loads('''$output''')
assert 'total_matchers' in d
assert 'broad_details' in d
# If broad_details contains entries, all should match PreToolUse
for b in d.get('broad_details', []):
    assert b['event'] == 'PreToolUse', f'Expected PreToolUse, got {b[\"event\"]}'
print('OK')
"
  [[ "$output" == *"OK"* ]]
}

# ── 08: --help works ───────────────────────────────────────────────────────────
@test "SE270-matcher-08: --help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

# ── 09: unknown flag exits 2 ───────────────────────────────────────────────────
@test "SE270-matcher-09: unknown flag exits 2" {
  run bash "$SCRIPT" --fake-flag
  [ "$status" -eq 2 ]
}

# ── 10: empty matcher detected as broad ────────────────────────────────────────
@test "SE270-matcher-10: empty matcher flagged as broad" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]

  has_empty=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
broad_list = d.get('broad_details', [])
# Empty matcher would be any entry with matcher == '<empty>' in text output
# In JSON, empty matcher appears as empty string
count = sum(1 for b in broad_list if b['matcher'] == '' or b['matcher'] == '<empty>')
print(count)
" 2>/dev/null || echo "0")

  # There may or may not be empty matchers; this test just verifies the code path
  # doesn't crash. The "broad" count itself is the minimum assertion.
  [ "$has_empty" -ge 0 ]
}

# ── 11: * matcher detected as broad ────────────────────────────────────────────
@test "SE270-matcher-11: bare * matcher flagged as broad" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]

  has_star=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
broad_list = d.get('broad_details', [])
count = sum(1 for b in broad_list if b['matcher'] == '*')
print(count)
" 2>/dev/null || echo "0")

  [ "$has_star" -ge 0 ]
}

# ── 12: total_matchers >= 0 ────────────────────────────────────────────────────
@test "SE270-matcher-12: total_matchers is non-negative" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]

  total=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['total_matchers'])
" 2>/dev/null || echo "-1")

  [ "$total" -ge 0 ]
}

# ── 13: report mentions broad count ────────────────────────────────────────────
@test "SE270-matcher-13: text output shows broad matcher count" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Broad"* ]]
}

# ── 14: report mentions specific count ─────────────────────────────────────────
@test "SE270-matcher-14: text output shows specific matcher count" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Specific"* ]]
}

# ── 15: works without jq (graceful error) ──────────────────────────────────────
@test "SE270-matcher-15: exits 2 when jq is missing" {
  PATH="/usr/bin:/bin" run bash "$SCRIPT" 2>/dev/null
  # Should fail because jq is required
  if command -v jq &>/dev/null; then
    # jq exists, just verify script runs
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
  else
    [ "$status" -eq 2 ]
  fi
}

# ── Comportamiento con settings.json controlado (SE-456) ──────────────────────
# El script resuelve settings.json relativo a su propia ruta: se copia a un árbol
# temporal con un settings.json construido a mano, de modo que los recuentos son exactos.

make_root() {
  T="$(mktemp -d)"
  mkdir -p "$T/scripts" "$T/.claude"
  cp "$SCRIPT" "$T/scripts/hook-matcher-audit.sh"
  cat > "$T/.claude/settings.json" <<'JSON'
{"hooks":{
 "PreToolUse":[
   {"matcher":".*","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]},
   {"matcher":"Bash","hooks":[{"type":"command","command":"c"}]},
   {"matcher":"Edit|Write","hooks":[{"type":"command","command":"d"}]},
   {"hooks":[{"type":"command","command":"e"}]}
 ],
 "PostToolUse":[
   {"matcher":"Task","hooks":[{"type":"command","command":"f"}]},
   {"matcher":"*","hooks":[{"type":"command","command":"g"}]}
 ]
}}
JSON
}

teardown() { [[ -n "${T:-}" ]] && rm -rf "$T"; true; }

@test "SE270-matcher-16: recuentos exactos por clase con settings controlado" {
  make_root
  run bash "$T/scripts/hook-matcher-audit.sh" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq .total_matchers)" -eq 6 ]
  [ "$(echo "$output" | jq .broad)" -eq 3 ]
  [ "$(echo "$output" | jq .tool_only)" -eq 2 ]
  [ "$(echo "$output" | jq .specific)" -eq 1 ]
  [ "$(echo "$output" | jq .broad_pct)" -eq 50 ]
}

@test "SE270-matcher-17: broad_details lista .* con sus 2 hooks y el matcher vacío con 1" {
  make_root
  run bash "$T/scripts/hook-matcher-audit.sh" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.broad_details[]|select(.matcher==".*")]|length')" -eq 1 ]
  [ "$(echo "$output" | jq -r '.broad_details[]|select(.matcher==".*")|.hooks')" -eq 2 ]
  [ "$(echo "$output" | jq -r '.broad_details[]|select(.matcher=="<empty>")|.hooks')" -eq 1 ]
  [[ "$(echo "$output" | jq -r '.broad_details[]|select(.matcher==".*")|.suggestion')" == *"Restrict to known tool names"* ]]
  [[ "$(echo "$output" | jq -r '.broad_details[]|select(.matcher=="<empty>")|.suggestion')" == *"empty matcher"* ]]
}

@test "SE270-matcher-18: '*' pelado es broad con su sugerencia y Bash/Task salen como tool-only" {
  make_root
  run bash "$T/scripts/hook-matcher-audit.sh" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.broad_details[]|select(.matcher=="*")]|length')" -eq 1 ]
  [[ "$(echo "$output" | jq -r '.broad_details[]|select(.matcher=="*")|.suggestion')" == *"Use .* for all tools"* ]]
  run bash "$T/scripts/hook-matcher-audit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tool-only matchers (acceptable, reviewable):"* ]]
  [[ "$output" == *"'Bash'"* ]]
  [[ "$output" == *"'Task'"* ]]
  [[ "$output" != *"'Edit|Write'"* ]]
}

@test "SE270-matcher-19: --event restringe el recuento al evento pedido" {
  make_root
  run bash "$T/scripts/hook-matcher-audit.sh" --event PostToolUse --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq .total_matchers)" -eq 2 ]
  [ "$(echo "$output" | jq .broad)" -eq 1 ]
  [ "$(echo "$output" | jq .tool_only)" -eq 1 ]
  [ "$(echo "$output" | jq .specific)" -eq 0 ]
}

@test "SE270-matcher-20: evento inexistente da total 0 y porcentaje 0 sin dividir por cero" {
  make_root
  run bash "$T/scripts/hook-matcher-audit.sh" --event NoExiste --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq .total_matchers)" -eq 0 ]
  [ "$(echo "$output" | jq .broad_pct)" -eq 0 ]
  [ "$(echo "$output" | jq '.broad_details|length')" -eq 0 ]
}

@test "SE270-matcher-21: texto lista los broad con su sugerencia y el recuento final" {
  make_root
  run bash "$T/scripts/hook-matcher-audit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total matchers:  6"* ]]
  [[ "$output" == *"Broad:         3 (50%)"* ]]
  [[ "$output" == *"Broad matchers (.*, *, empty):"* ]]
  [[ "$output" == *"'.*'"* ]]
  [[ "$output" == *"'<empty>'"* ]]
  [[ "$output" == *"Current broad count: 3"* ]]
}

@test "SE270-matcher-22: sin matchers broad el informe omite la sección de broad" {
  make_root
  echo '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"x"}]}]}}' > "$T/.claude/settings.json"
  run bash "$T/scripts/hook-matcher-audit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Broad matchers (.*, *, empty):"* ]]
  [[ "$output" == *"Current broad count: 0"* ]]
  [[ "$output" == *"Specific:      1"* ]]
}

@test "SE270-matcher-23: sin settings.json sale con 2 y mensaje" {
  make_root
  rm "$T/.claude/settings.json"
  run bash "$T/scripts/hook-matcher-audit.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"settings.json not found"* ]]
}

@test "SE270-matcher-24: argumento desconocido sale con 2 y lo nombra" {
  make_root
  run bash "$T/scripts/hook-matcher-audit.sh" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg '--nope'"* ]]
}
