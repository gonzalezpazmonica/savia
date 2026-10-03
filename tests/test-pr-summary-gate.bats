#!/usr/bin/env bats
# BATS tests for .opencode/hooks/pr-summary-gate.sh
# PreToolUse (gh pr create): exige .pr-summary.md y lo revisa con un LLM vía proxy.
# La revisión LLM tiene un plazo corto y determinista: conexión ≤ 3 s y respuesta
# ≤ PR_SUMMARY_LLM_TIMEOUT (90 s por defecto, como antes). Si el proxy no
# existe o no contesta a tiempo, el gate se omite con aviso (fail-open documentado).
#
# Limitación conocida: no hay test fiable de `--connect-timeout 3`. Un puerto
# cerrado se rechaza al instante y el servidor blackhole sí completa la conexión
# TCP, así que ninguno ejercita el plazo de conexión; hacerlo exigiría una
# dirección no enrutable, dependiente de la red de la máquina (test inestable).
# Ref: docs/rules/domain/pr-natural-language-summary.md

SCRIPT=".opencode/hooks/pr-summary-gate.sh"
MOCK="tests/fixtures/hook-net-mock/server.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  export TMPDIR="$TMP"
  export CLAUDE_PROJECT_DIR="$TMP/proj"
  mkdir -p "$CLAUDE_PROJECT_DIR"
  export CLAUDE_TOOL_INPUT='gh pr create --draft --title "x"'
  export MOCK_LOG="$TMP/requests.log"
  unset PR_SUMMARY_LLM_TIMEOUT SAVIA_HOOK_PROFILE 2>/dev/null || true
  MARK="Marcador-$(basename "$TMP")"
  printf '## Qué hace este PR (en lenguaje no técnico)\n\n%s: el arranque ya no se queda esperando.\n' \
    "$MARK" > "$CLAUDE_PROJECT_DIR/.pr-summary.md"
  : > "$TMP/pids"
}

teardown() {
  local pid
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  done < "$TMP/pids"
  rm -rf "$TMP"
}

start_mock() {
  python3 "$MOCK" "$1" "$TMP/port.$1" >/dev/null 2>&1 &
  echo "$!" >> "$TMP/pids"
  local i
  for i in $(seq 1 50); do
    [[ -s "$TMP/port.$1" ]] && { cat "$TMP/port.$1"; return 0; }
    sleep 0.1
  done
  return 1
}

closed_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

run_timed() {
  local s e
  s=$(date +%s%N)
  run bash "$SCRIPT"
  e=$(date +%s%N)
  ELAPSED_MS=$(( (e - s) / 1000000 ))
}

@test "script uses set -uo pipefail" {
  head -3 "$SCRIPT" | grep -q 'set -uo pipefail'
}

@test "positive: LLM approves -> exit 0" {
  export MOCK_BODY='{"content":[{"type":"text","text":"{\"ok\": true}"}]}'
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(start_mock ok)"
  run_timed
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR summary OK"* ]]
}

@test "negative: LLM rejects -> block with reason (exit 2)" {
  export MOCK_BODY='{"content":[{"type":"text","text":"{\"ok\": false, \"reason\": \"cita SE-123\"}"}]}'
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(start_mock ok)"
  run_timed
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO"* && "$output" == *"cita SE-123"* ]]
}

@test "positive: request carries this PR's own summary section" {
  export MOCK_BODY='{"content":[{"type":"text","text":"{\"ok\": true}"}]}'
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(start_mock ok)"
  run_timed
  [ "$status" -eq 0 ]
  grep -q "$MARK" "$MOCK_LOG"
}

@test "negative: summary is not written to a shared world path (/tmp race between sessions)" {
  export MOCK_BODY='{"content":[{"type":"text","text":"{\"ok\": true}"}]}'
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(start_mock ok)"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Antes: /tmp/_pr_summary_section.txt fijo, compartido por todas las sesiones.
  run grep -qs "$MARK" /tmp/_pr_summary_section.txt
  [ "$status" -ne 0 ]
}

@test "boundary: hung proxy is bounded by PR_SUMMARY_LLM_TIMEOUT and fails open" {
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(start_mock blackhole)"
  export PR_SUMMARY_LLM_TIMEOUT=2
  run_timed
  [ "$status" -eq 0 ]
  [[ "$output" == *"no respondio"* ]]
  # Antes: 90 s fijos.
  [ "$ELAPSED_MS" -lt 5000 ]
}

@test "boundary: closed proxy port fails open fast (<3s)" {
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(closed_port)"
  run_timed
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADVERTENCIA"* ]]
  [ "$ELAPSED_MS" -lt 3000 ]
}

@test "invalid: non-numeric or zero timeout falls back to the default without crashing" {
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(closed_port)"
  local v
  for v in abc 0 -5 '1;id'; do
    PR_SUMMARY_LLM_TIMEOUT="$v" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA"* ]]
    [[ "$output" != *"uid="* ]]
  done
}

@test "negative: missing .pr-summary.md blocks (exit 2)" {
  mv "$CLAUDE_PROJECT_DIR/.pr-summary.md" "$TMP/summary.bak"
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"falta .pr-summary.md"* ]]
}

@test "negative: missing canonical heading blocks (exit 2)" {
  printf '## Resumen\n\nTexto.\n' > "$CLAUDE_PROJECT_DIR/.pr-summary.md"
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "negative: summary older than 24h blocks (exit 2)" {
  touch -d '2 days ago' "$CLAUDE_PROJECT_DIR/.pr-summary.md"
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"antiguedad"* ]]
}

@test "edge: commands other than gh pr create are ignored (empty input)" {
  CLAUDE_TOOL_INPUT='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
  CLAUDE_TOOL_INPUT='git status' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "edge: unparseable LLM answer fails open with warning" {
  export MOCK_BODY='not json at all'
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$(start_mock ok)"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no parseable"* ]]
}
