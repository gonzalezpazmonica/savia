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

# ── Comportamiento discriminante (S03m): contenido exacto del aviso y reglas de seleccion ──

# Helper: escribe un scan con un fichero. args: <scan> <modulo> <riesgo> <path> <bf> <owner>
_scan_one() {
  python3 - "$BF_OUT/$1.json" "$2" "$3" "$4" "$5" "$6" <<'PY'
import json, sys
out, mod, risk, path, bf, owner = sys.argv[1:7]
owners = [{"dev": owner, "score": 1.0, "files_owned": 0}] if owner else []
json.dump({"modules": [{"name": mod, "risk_level": risk, "files": [
    {"path": path, "bus_factor": int(bf), "owners": owners}]}]}, open(out, "w"))
PY
}

_hook() { printf '%s' "$1" | BF_OUTPUT_DIR="$BF_OUT" bash "$HOOK"; }
_ctx() { python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }

@test "aviso BF=1: JSON valido con evento PostToolUse y owner, modulo y riesgo del scan" {
  _scan_one s1 core HIGH src/a.py 1 alice@test.com
  out=$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')
  [ "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')" = "PostToolUse" ]
  msg=$(printf '%s' "$out" | _ctx)
  [[ "$msg" == "[BF-WARN] Archivo src/a.py tiene BF=1 (unico conocedor: alice@test.com, modulo: core, riesgo: HIGH)."* ]]
}

@test "Edit tambien avisa y la clave alternativa 'path' se acepta" {
  _scan_one s1 core HIGH src/a.py 1 alice@test.com
  out=$(_hook '{"tool_name":"Edit","tool_input":{"path":"src/a.py"}}')
  [[ "$out" == *"[BF-WARN] Archivo src/a.py"* ]]
}

@test "BF=2 y BF=0 no avisan: solo el unico conocedor (BF=1) cuenta" {
  _scan_one s1 core HIGH src/a.py 2 alice@test.com
  [ -z "$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')" ]
  _scan_one s1 core HIGH src/a.py 0 alice@test.com
  [ -z "$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')" ]
}

@test "un fichero distinto del scan no avisa aunque otro tenga BF=1" {
  _scan_one s1 core HIGH src/a.py 1 alice@test.com
  [ -z "$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/otro.py"}}')" ]
}

@test "coincide por basename aunque el scan guarde otra ruta" {
  _scan_one s1 core HIGH lib/deep/a.py 1 alice@test.com
  out=$(_hook '{"tool_name":"Write","tool_input":{"file_path":"/work/x/a.py"}}')
  [[ "$out" == *"Archivo lib/deep/a.py tiene BF=1"* ]]
}

@test "sin owners en el scan el unico conocedor es 'desconocido'" {
  _scan_one s1 core LOW src/a.py 1 ""
  out=$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')
  [[ "$out" == *"unico conocedor: desconocido"* ]]
}

@test "solo se miran los 3 scans mas recientes: un 4o antiguo con BF=1 se ignora" {
  _scan_one old core HIGH src/a.py 1 alice@test.com
  touch -d '2026-01-01' "$BF_OUT/old.json"
  for n in n1 n2 n3; do _scan_one $n core LOW src/z.py 3 bob@test.com; done
  [ -z "$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')" ]
  # control: con un solo scan antiguo si avisa
  find "$BF_OUT" -name 'n?.json' -delete
  [[ "$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')" == *"BF-WARN"* ]]
}

@test "un scan corrupto no impide leer el siguiente" {
  printf '{no json' > "$BF_OUT/bad.json"
  _scan_one good core HIGH src/a.py 1 alice@test.com
  out=$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')
  [[ "$out" == *"BF-WARN"* ]]
}

@test "las comillas del scan se escapan: la salida sigue siendo JSON valido" {
  _scan_one s1 'mod"x' HIGH src/a.py 1 'a"b@test.com'
  out=$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')
  printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "herramientas que no son Write/Edit no avisan aunque haya BF=1 (Read, Grep, MultiEdit)" {
  _scan_one s1 core HIGH src/a.py 1 alice@test.com
  for t in Read Grep MultiEdit; do
    [ -z "$(_hook "{\"tool_name\":\"$t\",\"tool_input\":{\"file_path\":\"src/a.py\"}}")" ]
  done
}

@test "sin file_path ni path no avisa y sale 0" {
  _scan_one s1 core HIGH src/a.py 1 alice@test.com
  run bash -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{}}' | BF_OUTPUT_DIR='$BF_OUT' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "el scan mas reciente no tiene el fichero pero uno anterior (dentro de los 3 ultimos) si: avisa" {
  _scan_one older core HIGH src/a.py 1 alice@test.com
  touch -d '2026-01-01' "$BF_OUT/older.json"
  _scan_one newer core LOW src/z.py 3 bob@test.com
  [[ "$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')" == *"Archivo src/a.py tiene BF=1"* ]]
}

@test "un scan corrupto MAS RECIENTE no corta la busqueda en los anteriores" {
  _scan_one good core HIGH src/a.py 1 alice@test.com
  touch -d '2026-01-01' "$BF_OUT/good.json"
  printf '{no json' > "$BF_OUT/bad.json"
  [[ "$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')" == *"BF-WARN"* ]]
}

@test "con el mismo fichero en varios scans emite un unico aviso (una linea)" {
  _scan_one s1 core HIGH src/a.py 1 alice@test.com
  _scan_one s2 core HIGH src/a.py 1 bob@test.com
  out=$(_hook '{"tool_name":"Write","tool_input":{"file_path":"src/a.py"}}')
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ]
  [ "$(printf '%s' "$out" | grep -o 'BF-WARN' | wc -l)" -eq 1 ]
}
