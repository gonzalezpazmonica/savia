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
  run bash "$SUMMARIZER" - <<< "col1,col2,col3
1,2,3
4,5,6
7,8,9
10,11,12
13,14,15"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"rows": 5'* ]]
  [[ "$output" != *'"detected":false'* ]]
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
