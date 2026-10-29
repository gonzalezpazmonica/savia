#!/usr/bin/env bats
# Hooks PostToolUse agent-trace-log y bash-output-compress: la entrada llega por stdin (JSON de Claude Code),
# no por variables TOOL_* que ningún runtime define. Misma clase de fallo que #1398 (PreToolUse).
# Aislados: HOME, CLAUDE_PROJECT_DIR y SPILL_ROOT en un temporal; el árbol del repo no debe cambiar.

REPO="$BATS_TEST_DIRNAME/../.."

setup() {
  T="$(mktemp -d)"
  export HOME="$T/home"; mkdir -p "$HOME"
  export CLAUDE_PROJECT_DIR="$T/ws"; mkdir -p "$CLAUDE_PROJECT_DIR/scripts" "$CLAUDE_PROJECT_DIR/output"
  export SPILL_ROOT="$T/spill"
  export SAVIA_SESSION_ID="bats"
  cp "$REPO/scripts/output-compress.sh" "$REPO/scripts/spill-save.sh" "$CLAUDE_PROJECT_DIR/scripts/"
  unset TOOL_NAME TOOL_INPUT TOOL_OUTPUT TOOL_DURATION TOOL_RESULT_STATUS CLAUDE_TOOL_INPUT
  TRACE="$CLAUDE_PROJECT_DIR/output/agent-traces.jsonl"
  TRACE_HOOK="$REPO/.claude/hooks/agent-trace-log.sh"
  COMPRESS_HOOK="$REPO/.claude/hooks/bash-output-compress.sh"
  TREE_BEFORE="$(git -C "$REPO" status --porcelain --ignored)"
}

teardown() {
  # el hook no debe haber escrito nada en el repo
  [ "$(git -C "$REPO" status --porcelain --ignored)" = "$TREE_BEFORE" ]
  rm -r "$T"
}

agent_json() {  # $1 = tool_name, $2 = duración en ms
  jq -nc --arg t "$1" --argjson d "$2" \
    '{hook_event_name:"PostToolUse",tool_name:$t,tool_input:{subagent_type:"code-reviewer",description:"revisa",prompt:"hola"},tool_response:{content:[{type:"text",text:"hecho"}],totalDurationMs:$d}}'
}

bash_json() {  # $1 = nº de líneas de stdout
  local out; out=$(seq 1 "$1" | sed 's/^/linea de salida numero /')
  jq -nc --arg o "$out" '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"npm test"},tool_response:{stdout:$o,stderr:"",interrupted:false}}'
}

# ── agent-trace-log ──────────────────────────────────────

@test "agent-trace-log: con JSON por stdin (Agent) escribe la traza con el agente" {
  run bash "$TRACE_HOOK" <<<"$(agent_json Agent 5000)"
  [ "$status" -eq 0 ]
  [ -f "$TRACE" ]
  [ "$(wc -l < "$TRACE")" -eq 1 ]
  grep -q '"agent":"code-reviewer"' "$TRACE"
  grep -q '"duration_ms":5000' "$TRACE"
  grep -q '"outcome":"success"' "$TRACE"
}

@test "agent-trace-log: también registra la herramienta Task" {
  run bash "$TRACE_HOOK" <<<"$(agent_json Task 10)"
  [ "$status" -eq 0 ]
  grep -q '"agent":"code-reviewer"' "$TRACE"
}

@test "agent-trace-log: límite, más de 120 s de duración es failure y 120 s exactos no" {
  run bash "$TRACE_HOOK" <<<"$(agent_json Agent 121000)"
  [ "$status" -eq 0 ]
  grep -q '"outcome":"failure"' "$TRACE"
  run bash "$TRACE_HOOK" <<<"$(agent_json Agent 120000)"
  [ "$status" -eq 0 ]
  tail -1 "$TRACE" | grep -q '"outcome":"success"'
}

@test "agent-trace-log: negativo, una herramienta que no es Agent/Task no deja traza" {
  run bash "$TRACE_HOOK" <<<"$(bash_json 3)"
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

@test "agent-trace-log: JSON malformado o stdin vacío salen con 0 sin traza" {
  run bash "$TRACE_HOOK" <<<'{"tool_name":"Agent","tool_input":'
  [ "$status" -eq 0 ]
  run bash "$TRACE_HOOK" <<<''
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

@test "agent-trace-log: la variable TOOL_NAME sigue valiendo de respaldo si stdin llega vacío" {
  TOOL_NAME=Agent TOOL_INPUT='{"subagent_type":"architect"}' run bash "$TRACE_HOOK" <<<''
  [ "$status" -eq 0 ]
  grep -q '"agent":"architect"' "$TRACE"
}

@test "agent-trace-log: el JSON de stdin manda sobre una variable heredada" {
  TOOL_NAME=Read run bash "$TRACE_HOOK" <<<"$(agent_json Agent 1)"
  [ "$status" -eq 0 ]
  grep -q '"agent":"code-reviewer"' "$TRACE"
}

# ── bash-output-compress ─────────────────────────────────

@test "bash-output-compress: salida de 300 líneas por stdin se desvía a fichero y avisa" {
  run bash "$COMPRESS_HOOK" <<<"$(bash_json 300)"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "${#output}" -lt 4000 ]
  local spilled; spilled="$(find "$SPILL_ROOT" -type f 2>/dev/null | head -1)"
  [ -n "$spilled" ]
  [ "$(wc -l < "$spilled")" -ge 300 ]
}

@test "bash-output-compress: salida intermedia (60 líneas) se comprime y es más corta" {
  run bash "$COMPRESS_HOOK" <<<"$(bash_json 60)"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$(wc -l <<<"$output")" -lt 60 ]
}

@test "bash-output-compress: negativo, salida corta (5 líneas) no emite nada" {
  run bash "$COMPRESS_HOOK" <<<"$(bash_json 5)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bash-output-compress: negativo, otra herramienta no se procesa aunque la salida sea larga" {
  run bash "$COMPRESS_HOOK" <<<"$(bash_json 300 | jq -c '.tool_name = "Read"')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bash-output-compress: JSON malformado o stdin vacío salen con 0 sin salida" {
  run bash "$COMPRESS_HOOK" <<<'{"tool_name":"Bash","tool_response":'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash "$COMPRESS_HOOK" <<<''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bash-output-compress: respaldo por variables TOOL_* si stdin llega vacío" {
  local big; big=$(seq 1 300 | sed 's/^/linea /')
  TOOL_NAME=Bash TOOL_OUTPUT="$big" run bash "$COMPRESS_HOOK" <<<''
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# ── matchers de settings.json ────────────────────────────

@test "settings.json registra agent-trace-log para Agent|Task y bash-output-compress para Bash" {
  run jq -r '.hooks.PostToolUse[] | select(any(.hooks[]; .command | test("agent-trace-log"))) | .matcher' "$REPO/.claude/settings.json"
  [ "$output" = "Agent|Task" ]
  run jq -r '.hooks.PostToolUse[] | select(any(.hooks[]; .command | test("bash-output-compress"))) | .matcher' "$REPO/.claude/settings.json"
  [ "$output" = "Bash" ]
}
