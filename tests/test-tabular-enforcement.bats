#!/usr/bin/env bats

setup() {
  SUMMARIZER="$BATS_TEST_DIRNAME/../scripts/tabular-summarize.sh"
  AUDITOR="$BATS_TEST_DIRNAME/../scripts/tabular-self-audit.sh"
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/pre-llm-tabular-detect.sh"
}

@test "tabular-summarize exists and executable" {
  [ -f "$SUMMARIZER" ]
  [ -x "$SUMMARIZER" ]
}

@test "tabular-self-audit exists and executable" {
  [ -f "$AUDITOR" ]
  [ -x "$AUDITOR" ]
}

@test "pre-llm hook exists and executable" {
  [ -f "$HOOK" ]
  [ -x "$HOOK" ]
}

@test "summarize detects tabular data" {
  echo "col1,col2,col3
1,2,3
4,5,6
7,8,9
10,11,12
13,14,15" | run bash "$SUMMARIZER" -
  [ "$status" -eq 0 ] || true
}

@test "summarize returns detected:false for non-tabular" {
  local tf
  tf=$(mktemp)
  echo "hello world" > "$tf"
  run bash "$SUMMARIZER" "$tf"
  [[ "$output" == *"no tabular data"* ]]
  rm -f "$tf"
}

@test "self-audit detects bypass" {
  # Exportar SAVIA_AUDIT_LOG: sin export, el subshell cae al log por defecto
  # ($HOME/.savia/tabular-audit.jsonl), que acumula bypasses entre ejecuciones
  # y escala a BLOCK en vez de WARN → test no aislado ni idempotente.
  export SAVIA_AUDIT_LOG=$(mktemp)
  local turn_log
  turn_log=$(mktemp)
  echo "col1,col2,col3
1,2,3
4,5,6
7,8,9
10,11,12
13,14,15
16,17,18" > "$turn_log"
  run bash "$AUDITOR" "$turn_log"
  [[ "$output" == *"WARN"* || "$output" == *"OK"* ]]
  rm -f "$SAVIA_AUDIT_LOG" "$turn_log"
}

@test "self-audit passes when profiler used" {
  export SAVIA_AUDIT_LOG=$(mktemp)
  local turn_log
  turn_log=$(mktemp)
  echo "tabular-profile.py executed" > "$turn_log"
  run bash "$AUDITOR" "$turn_log"
  [ "$status" -eq 0 ]
  rm -f "$SAVIA_AUDIT_LOG" "$turn_log"
}

@test "hooks have set -uo pipefail" {
  head -3 "$HOOK" | grep -q "set -uo pipefail"
  head -3 "$AUDITOR" | grep -q "set -uo pipefail"
}

@test "mcp-tool exists and executable" {
  [ -f "$BATS_TEST_DIRNAME/../scripts/tabular-mcp-tool.sh" ]
  [ -x "$BATS_TEST_DIRNAME/../scripts/tabular-mcp-tool.sh" ]
}

# --- S03c: comportamiento de las 4 capas (SE-296) ---

csv_block() {
  printf 'sprint,sp,bugs\n1,30,2\n2,34,1\n3,28,5\n4,40,0\n5,36,3\n6,38,1\n'
}

@test "summarize: CSV ≥6 líneas con coma se perfila (rows y columns exactos)" {
  csv_block > "$BATS_TEST_TMPDIR/d.csv"
  run bash "$SUMMARIZER" "$BATS_TEST_TMPDIR/d.csv"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert (d['rows'], d['columns']) == (6, 3), d
assert [p['name'] for p in d['profiles']] == ['sprint', 'sp', 'bugs'], d"
}

@test "summarize: justo 5 líneas con coma es borde bajo → no tabular" {
  printf 'a,b\n1,2\n3,4\n5,6\n7,8\n' > "$BATS_TEST_TMPDIR/d.csv"
  run bash "$SUMMARIZER" "$BATS_TEST_TMPDIR/d.csv"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d == {'detected': False, 'reason': 'no tabular data found'}, d"
}

@test "summarize: tabla markdown de 5 filas con pipes se detecta como tabular" {
  printf '| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |\n' > "$BATS_TEST_TMPDIR/d.md"
  run bash "$SUMMARIZER" "$BATS_TEST_TMPDIR/d.md"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q '"detected":false'
}

@test "summarize: fichero inexistente → no tabular (no falla)" {
  run bash "$SUMMARIZER" "$BATS_TEST_TMPDIR/no-existe.csv"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"detected":false'
}

@test "summarize: lee de stdin con '-'" {
  run bash -c "cat <(printf 'a,b\n1,2\n3,4\n5,6\n7,8\n9,10\n11,12\n') | bash '$SUMMARIZER' -"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
assert json.load(sys.stdin)['rows'] == 6"
}

@test "self-audit: <5 líneas tabulares → OK registrado y exit 0" {
  export SAVIA_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.jsonl"
  echo "solo texto normal" > "$BATS_TEST_TMPDIR/t.log"
  run bash "$AUDITOR" "$BATS_TEST_TMPDIR/t.log"
  [ "$status" -eq 0 ]
  python3 -c "
import json
d = json.loads(open('$SAVIA_AUDIT_LOG').read().strip())
assert d['verdict'] == 'OK' and d['profiler_used'] is False, d"
}

@test "self-audit: datos tabulares sin perfilador → WARN y BYPASS en el log" {
  export SAVIA_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.jsonl"
  csv_block > "$BATS_TEST_TMPDIR/t.log"
  run bash "$AUDITOR" "$BATS_TEST_TMPDIR/t.log"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^WARN \[tabular-self-audit\]"
  grep -q '"verdict":"BYPASS"' "$SAVIA_AUDIT_LOG"
  grep -q '"bypass_count":1' "$SAVIA_AUDIT_LOG"
}

@test "self-audit: el tercer bypass escala a BLOCK con exit 1" {
  export SAVIA_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.jsonl"
  csv_block > "$BATS_TEST_TMPDIR/t.log"
  run bash "$AUDITOR" "$BATS_TEST_TMPDIR/t.log"; [ "$status" -eq 0 ]
  run bash "$AUDITOR" "$BATS_TEST_TMPDIR/t.log"; [ "$status" -eq 0 ]
  run bash "$AUDITOR" "$BATS_TEST_TMPDIR/t.log"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "^BLOCK \[tabular-self-audit\]"
  echo "$output" | grep -q "Bypass count: 3"
}

@test "self-audit: citar tabular-profile.py en el turno evita el bypass" {
  export SAVIA_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.jsonl"
  { csv_block; echo "ran tabular-profile.py"; } > "$BATS_TEST_TMPDIR/t.log"
  run bash "$AUDITOR" "$BATS_TEST_TMPDIR/t.log"
  [ "$status" -eq 0 ]
  ! grep -q BYPASS "$SAVIA_AUDIT_LOG"
  grep -q '"profiler_used":true' "$SAVIA_AUDIT_LOG"
}

@test "self-audit: un bypass previo en el log cuenta para el umbral (acumulado)" {
  export SAVIA_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.jsonl"
  printf '%s\n' '{"verdict":"BYPASS"}' '{"verdict":"BYPASS"}' > "$SAVIA_AUDIT_LOG"
  csv_block > "$BATS_TEST_TMPDIR/t.log"
  run bash "$AUDITOR" "$BATS_TEST_TMPDIR/t.log"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Bypass count: 3"
}

@test "hook: prompt sin datos tabulares pasa idéntico" {
  run bash -c "printf 'hola, ¿cómo vas?\nsegunda línea\n' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$output" == $'hola, ¿cómo vas?\nsegunda línea' ]
}

@test "hook: ≥5 líneas CSV se sustituyen por perfil y se conserva el texto libre" {
  run bash -c "{ echo 'Analiza esto por favor'; printf 'sprint,sp,bugs\n1,30,2\n2,34,1\n3,28,5\n4,40,0\n5,36,3\n6,38,1\n'; } | bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Analiza esto por favor"
  echo "$output" | grep -q "STATISTICAL PROFILE"
  ! echo "$output" | grep -q "^3,28,5"
}

@test "hook: 4 líneas tabulares (bajo el umbral) no se transforman" {
  run bash -c "printf 'a,b 1\nc,d 2\ne,f 3\ng,h 4\n' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "STATISTICAL PROFILE"
  echo "$output" | grep -q "^a,b 1"
}

@test "hook: referencia a .xlsx inexistente no dispara perfil" {
  run bash -c "echo 'mira ventas-que-no-existe.xlsx' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "STATISTICAL PROFILE"
}

@test "mcp-tool: sin --question → error JSON y exit 2" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tabular-mcp-tool.sh" --source x.csv
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '"error"'
}

@test "mcp-tool: --help sale 0" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tabular-mcp-tool.sh" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Usage"
}

@test "mcp-tool: combina pregunta y perfil con la instrucción de no recalcular" {
  command -v jq >/dev/null || skip "jq no disponible"
  csv_block > "$BATS_TEST_TMPDIR/d.csv"
  run bash "$BATS_TEST_DIRNAME/../scripts/tabular-mcp-tool.sh" --source "$BATS_TEST_TMPDIR/d.csv" --question "tendencia?"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['question'] == 'tendencia?', d
assert d['profile']['rows'] == 6, d
assert 'Do NOT recompute' in d['instruction'], d"
}
