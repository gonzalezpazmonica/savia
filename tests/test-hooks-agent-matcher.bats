#!/usr/bin/env bats
# La herramienta de subagentes de Claude Code se llama «Agent» (antes «Task»). Los hooks registrados solo
# con matcher «Task» no se ejecutaban nunca. Estos tests fijan el registro con «Agent|Task» y comprueban
# que cada hook así registrado acepta una invocación «Agent» benigna sin bloquear, romper ni colgarse.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"; mkdir -p "$HOME"
  unset SAVIA_LOOP_CONTEXT SAVIA_AUTONOMOUS_MODE SAVIA_AUTONOMOUS_SKILL SAVIA_DELEGATION_DEPTH
}

teardown() { rm -rf "$TMP"; }

hooks_for() {  # $1 = PreToolUse|PostToolUse → rutas de los hooks command registrados para Agent
  python3 -c 'import json,re,sys
d=json.load(open(".claude/settings.json"))
for m in d["hooks"].get(sys.argv[1],[]):
    if "Agent" in m.get("matcher","").split("|"):
        for h in m.get("hooks",[]):
            for f in re.findall(r"hooks/([A-Za-z0-9_.-]+\.sh)", h.get("command","")): print(f)' "$1" | sort -u
}

@test "ningún matcher nombra Task sin nombrar también Agent" {
  run python3 -c 'import json
d=json.load(open(".claude/settings.json"))
bad=[(e,m["matcher"]) for e,a in d["hooks"].items() for m in a if "Task" in m.get("matcher","").split("|") and "Agent" not in m.get("matcher","").split("|")]
print(bad); raise SystemExit(1 if bad else 0)'
  [ "$status" -eq 0 ]
}

@test "los guards de subagentes PreToolUse quedan registrados para Agent" {
  run hooks_for PreToolUse
  for h in recursion-guard.sh protected-job-guard.sh agent-dispatch-validate.sh; do
    [[ "$output" == *"$h"* ]] || { echo "falta $h"; return 1; }
  done
}

@test "cada hook PreToolUse de Agent acepta una invocación benigna (exit 0, < 15 s)" {
  printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","description":"leer","prompt":"Lee README.md y resume en una línea"}}' > "$TMP/in.json"
  for h in $(hooks_for PreToolUse); do
    run timeout 15 bash ".claude/hooks/$h" < "$TMP/in.json"
    [ "$status" -eq 0 ] || { echo "$h rc=$status: ${output:0:300}"; return 1; }
  done
}

@test "cada hook PostToolUse de Agent acepta una respuesta benigna (exit 0, < 15 s)" {
  printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","description":"leer","prompt":"Lee README.md"},"tool_response":"README describe el proyecto."}' > "$TMP/in.json"
  for h in $(hooks_for PostToolUse); do
    run timeout 15 bash ".claude/hooks/$h" < "$TMP/in.json"
    [ "$status" -eq 0 ] || { echo "$h rc=$status: ${output:0:300}"; return 1; }
  done
}

@test "protected-job-guard bloquea un agente protegido invocado como Agent en modo autónomo" {
  export SAVIA_AUTONOMOUS_MODE=1
  unset SAVIA_PROTECTED_JOB_OVERRIDE
  printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"architect","prompt":"diseña"}}' > "$TMP/in.json"
  run bash .claude/hooks/protected-job-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "protected-job-guard deja pasar un agente no protegido invocado como Agent" {
  export SAVIA_AUTONOMOUS_MODE=1
  printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"x"}}' > "$TMP/in.json"
  run bash .claude/hooks/protected-job-guard.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

@test "recursion-guard bloquea por stdin una invocación Agent que lanza otro bucle dentro de uno activo" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  unset OPENCODE_TOOL_INPUT
  printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"Ejecuta /overnight-sprint"}}' > "$TMP/in.json"
  run bash .claude/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "sycophancy-strip en modo strip quita la adulación de la salida de Agent y conserva la línea VERDICT" {
  printf '%s' '{"tool_name":"Agent","tool_input":{"prompt":"revisa"},"tool_response":"Great question! VERDICT: HOLD pr=1 sha=abc role=security p0=0 p1=1\nP1-1 detalle"}' > "$TMP/in.json"
  mkdir -p "$TMP/proj"
  CLAUDE_PROJECT_DIR="$TMP/proj" SAVIA_ANTIADULATION_LAYER1=strip run bash .claude/hooks/sycophancy-strip.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: HOLD pr=1 sha=abc role=security p0=0 p1=1"* ]]
  [[ "$output" != *"Great question"* ]]
}

@test "learning-capture-hook sigue sin actuar sobre Agent (escribiría extractos en docs/, versionado)" {
  printf '%s' '{"tool_name":"Agent","tool_input":{"prompt":"x"},"tool_response":"Lección aprendida: debí usar otra ruta. No debería haber tocado docs."}' > "$TMP/in.json"
  mkdir -p "$TMP/props"
  SCL_PROPOSALS_DIR="$TMP/props" SCL_GRAPH_INDEX="$TMP/graph.jsonl" run bash .claude/hooks/learning-capture-hook.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$TMP/props")" ]
}
