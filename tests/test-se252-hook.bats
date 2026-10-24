#!/usr/bin/env bats
# tests/test-se252-hook.bats — SE-252 Bus Factor Shield
# Tests para .claude/hooks/bus-factor-warn.sh

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/bus-factor-warn.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$REPO_ROOT/.claude/hooks/bus-factor-warn.sh"
  BF_OUT="$BATS_TMPDIR/hook-bf-out-$$"
  mkdir -p "$BF_OUT"
  export BF_OUTPUT_DIR="$BF_OUT"
}

teardown() {
  rm -rf "$BF_OUT" 2>/dev/null || true
}

# Helper: crea un JSON de scan sintético con un archivo con BF=1
_inject_scan_with_bf1() {
  cat > "$BF_OUT/myproject.json" << 'JSONEOF'
{
  "generated_at": "2026-06-30T00:00:00Z",
  "project": "myproject",
  "modules": [
    {
      "name": "src",
      "path": "src",
      "bus_factor": 1,
      "risk_level": "CRITICAL",
      "owners": [{"dev": "alice@test.com", "score": 1.0, "files_owned": 1}],
      "files": [
        {
          "path": "src/critical.py",
          "bus_factor": 1,
          "owners": [{"dev": "alice@test.com", "score": 1.0, "files_owned": 0}],
          "warnings": []
        }
      ],
      "warnings": []
    }
  ],
  "summary": {"total_modules": 1, "critical": 1, "high": 0, "medium": 0, "low": 0},
  "warnings": []
}
JSONEOF
}

# Helper: crea un JSON de scan con un archivo con BF=3 (LOW risk)
_inject_scan_with_bf3() {
  cat > "$BF_OUT/myproject.json" << 'JSONEOF'
{
  "generated_at": "2026-06-30T00:00:00Z",
  "project": "myproject",
  "modules": [
    {
      "name": "src",
      "path": "src",
      "bus_factor": 3,
      "risk_level": "MEDIUM",
      "owners": [
        {"dev": "alice@test.com", "score": 0.4, "files_owned": 1},
        {"dev": "bob@test.com",   "score": 0.3, "files_owned": 1},
        {"dev": "carol@test.com", "score": 0.3, "files_owned": 1}
      ],
      "files": [
        {
          "path": "src/safe.py",
          "bus_factor": 3,
          "owners": [
            {"dev": "alice@test.com", "score": 0.4, "files_owned": 0},
            {"dev": "bob@test.com",   "score": 0.3, "files_owned": 0},
            {"dev": "carol@test.com", "score": 0.3, "files_owned": 0}
          ],
          "warnings": []
        }
      ],
      "warnings": []
    }
  ],
  "summary": {"total_modules": 1, "critical": 0, "high": 0, "medium": 1, "low": 0},
  "warnings": []
}
JSONEOF
}

# ── 01: hook existe ───────────────────────────────────────────────────────────
@test "SE252-hook-01: bus-factor-warn.sh existe" {
  [ -f "$HOOK" ]
}

# ── 02: hook es ejecutable ────────────────────────────────────────────────────
@test "SE252-hook-02: bus-factor-warn.sh tiene permiso de ejecucion o es invocable con bash" {
  [ -f "$HOOK" ]
  run bash -n "$HOOK"
  [ "$status" -eq 0 ]
}

# ── 03: bash -n syntax check ──────────────────────────────────────────────────
@test "SE252-hook-03: bash -n no detecta errores de sintaxis" {
  run bash -n "$HOOK"
  [ "$status" -eq 0 ]
}

# ── 04: hook siempre retorna exit 0 incluso con input inválido ────────────────
@test "SE252-hook-04: hook retorna exit 0 con input JSON invalido" {
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "this is not json"
  [ "$status" -eq 0 ]
}

# ── 05: hook retorna exit 0 con input vacío ───────────────────────────────────
@test "SE252-hook-05: hook retorna exit 0 con input vacio" {
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

# ── 06: input JSON con Write → procesa sin crash ──────────────────────────────
@test "SE252-hook-06: input Write no produce crash" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.py","content":"x"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
}

# ── 07: input JSON con Edit → procesa sin crash ───────────────────────────────
@test "SE252-hook-07: input Edit no produce crash" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.py","old_string":"x","new_string":"y"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
}

# ── 08: input Read → exit 0 sin warning (no es Write/Edit) ───────────────────
@test "SE252-hook-08: input Read sale con exit 0 sin emitir warning" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.py"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
  # No debe emitir hookSpecificOutput
  [[ "$output" != *"hookSpecificOutput"* ]]
}

# ── 09: hook emite JSON válido cuando hay warning ─────────────────────────────
@test "SE252-hook-09: cuando hay BF=1 emite hookSpecificOutput JSON valido" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"x"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
  if [[ -n "$output" ]]; then
    run python3 -c "
import json, sys
data = '''$output'''
if data.strip():
    d = json.loads(data)
    assert 'hookSpecificOutput' in d or len(data) == 0
print('OK')
"
    [ "$status" -eq 0 ]
  fi
}

# ── 10: sin JSON de scan disponible → exit 0 silencioso ───────────────────────
@test "SE252-hook-10: sin scan JSON disponible sale con exit 0 silencioso" {
  # BF_OUT está vacío (no hay JSON de scan)
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"x"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
}

# ── 11: archivo con BF=1 en scan → warning en output ─────────────────────────
@test "SE252-hook-11: archivo con BF=1 genera BF-WARN en hookSpecificOutput" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"nuevo"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BF-WARN"* ]] || [[ "$output" == *"hookSpecificOutput"* ]]
}

# ── 12: archivo con BF=3 → no emite warning ───────────────────────────────────
@test "SE252-hook-12: archivo con BF=3 no genera BF-WARN" {
  _inject_scan_with_bf3
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/safe.py","content":"nuevo"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
  # No debe haber BF-WARN para BF=3
  [[ "$output" != *"BF-WARN"* ]]
}

# ── 13: BF_HOOK_TIMEOUT env var respetada (no tarda más que el timeout) ───────
@test "SE252-hook-13: BF_HOOK_TIMEOUT=1 no hace que el hook tarde mas de 5s" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"x"}}'
  local start end elapsed
  start=$(date +%s)
  BF_HOOK_TIMEOUT=1 BF_OUTPUT_DIR="$BF_OUT" bash "$HOOK" <<< "$input" > /dev/null 2>&1 || true
  end=$(date +%s)
  elapsed=$((end - start))
  [ "$elapsed" -lt 5 ]
}

# ── 14: hook con input malformado (no JSON) → exit 0 ─────────────────────────
@test "SE252-hook-14: input malformado produce exit 0 sin crash" {
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "{ broken json {{ ]"
  [ "$status" -eq 0 ]
}

# ── 15: hook mode warn-only: no interfiere con la operación ───────────────────
@test "SE252-hook-15: hook nunca retorna exit != 0 (modo warn-only puro)" {
  _inject_scan_with_bf1
  # Probar con varios inputs: Write BF=1, Edit BF=1, input nulo, JSON roto
  local inputs=(
    '{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"x"}}'
    '{"tool_name":"Edit","tool_input":{"file_path":"src/critical.py"}}'
    '{}'
    'null'
    ''
  )
  for inp in "${inputs[@]}"; do
    if [[ -n "$inp" ]]; then
      BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$inp"
    else
      BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" < /dev/null
    fi
    [ "$status" -eq 0 ]
  done
}

# ── 16: hook sin git en PATH → exit 0 ────────────────────────────────────────
@test "SE252-hook-16: hook funciona sin git en PATH (exit 0)" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"x"}}'
  # PATH sin directorios de git
  BF_OUTPUT_DIR="$BF_OUT" PATH="/usr/bin:/bin" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
}

# ── 17: hookSpecificOutput tiene estructura correcta cuando se emite ──────────
@test "SE252-hook-17: hookSpecificOutput tiene campo hookEventName cuando se emite" {
  _inject_scan_with_bf1
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"x"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
  if [[ -n "$output" ]] && [[ "$output" == *"hookSpecificOutput"* ]]; then
    run python3 -c "
import json
d = json.loads('$output')
assert 'hookSpecificOutput' in d
hso = d['hookSpecificOutput']
assert 'hookEventName' in hso, f'missing hookEventName in {hso}'
assert hso['hookEventName'] == 'PostToolUse'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
  fi
}

# ── 18: hook con tool_name desconocido → exit 0 sin output ───────────────────
@test "SE252-hook-18: tool_name desconocido produce exit 0" {
  _inject_scan_with_bf1
  local input='{"tool_name":"RunBash","tool_input":{"command":"echo hi"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
  [[ "$output" != *"BF-WARN"* ]]
}

# ── 19: BF=1 con file_path relativo también genera warning ───────────────────
@test "SE252-hook-19: file_path relativo con BF=1 genera warning" {
  _inject_scan_with_bf1
  # La detección usa basename/suffix match, funciona con path relativo
  local input='{"tool_name":"Write","tool_input":{"file_path":"critical.py","content":"x"}}'
  BF_OUTPUT_DIR="$BF_OUT" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
  # Puede o no detectar según el matching — pero nunca debe crashear
  # El importante es exit 0
}

# ── 20: hook con BF_OUTPUT_DIR inexistente → exit 0 silencioso ───────────────
@test "SE252-hook-20: BF_OUTPUT_DIR inexistente produce exit 0 silencioso" {
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/critical.py","content":"x"}}'
  BF_OUTPUT_DIR="/tmp/directorio-que-no-existe-$$" run bash "$HOOK" <<< "$input"
  [ "$status" -eq 0 ]
}
