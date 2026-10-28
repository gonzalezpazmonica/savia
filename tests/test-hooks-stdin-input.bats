#!/usr/bin/env bats
# Hooks PreToolUse que leían solo CLAUDE_TOOL_INPUT (ningún runtime la define) y quedaban en
# fallo abierto: Claude Code y OpenCode pasan la entrada por stdin. Estos tests la pasan por stdin,
# sin exportar la variable, y fallan con la versión anterior de los hooks.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  unset CLAUDE_TOOL_INPUT CLAUDE_TOOL_INPUT_FILE
  export SAVIA_HOOK_PROFILE="standard"
  TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

payload() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' "$@"; }

@test "block-project-whitelist bloquea por stdin una whitelist nueva en .gitignore" {
  mkdir -p "$TMP/proj"; export CLAUDE_PROJECT_DIR="$TMP/proj"
  printf '*.log\n' > "$TMP/proj/.gitignore"
  python3 -c 'import json; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":".gitignore","old_string":"*.log","new_string":"*.log\n!pro"+"jects/a/"}}))' > "$TMP/in.json"
  run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *BLOQUEADO* ]]
}

@test "block-project-whitelist deja pasar por stdin un .gitignore sin whitelist" {
  payload Edit '{"file_path":".gitignore","old_string":"x","new_string":"*.log"}' > "$TMP/in.json"
  run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

@test "pr-summary-gate bloquea por stdin gh pr create sin .pr-summary.md" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  payload Bash '{"command":"gh pr create --draft --title x"}' > "$TMP/in.json"
  run bash .opencode/hooks/pr-summary-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "plan-gate extrae file_path de stdin" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR/projects"
  payload Edit '{"file_path":"src/app.py","old_string":"a","new_string":"b"}' > "$TMP/in.json"
  run bash .opencode/hooks/plan-gate.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan Gate"* ]]
}

@test "ningún hook PreToolUse lee su entrada solo de una variable de entorno" {
  pre=$(python3 -c 'import json,re
d=json.load(open(".claude/settings.json"))
for m in d["hooks"].get("PreToolUse",[]):
    for h in m.get("hooks",[]):
        for f in re.findall(r"hooks/([A-Za-z0-9_.-]+\.sh)", h.get("command","")): print(f)' | sort -u)
  bad=""
  for f in $pre; do
    [ -f ".claude/hooks/$f" ] || continue
    grep -qE '(OPENCODE_|CLAUDE_)?TOOL_INPUT(_FILE)?:-' ".claude/hooks/$f" || continue
    grep -v '^[[:space:]]*#' ".claude/hooks/$f" | grep -qE 'timeout 3 cat|hook_read_command|hook_extract_command' || bad="$bad $f"
  done
  [ -z "$bad" ] || { echo "solo env:$bad"; return 1; }
}

@test "block-project-whitelist no bloquea editar otro fichero que menciona .gitignore y !projects/" {
  payload Edit '{"file_path":"docs/privacidad.md","old_string":"a","new_string":"en .gitignore nunca !projects/x"}' > "$TMP/in.json"
  run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

@test "block-project-whitelist no bloquea quitar un !projects/ de .gitignore" {
  payload Edit '{"file_path":".gitignore","old_string":"!projects/viejo/","new_string":""}' > "$TMP/in.json"
  run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

@test "block-project-whitelist bloquea Write de .gitignore con !projects/ en content" {
  payload Write '{"file_path":"/repo/.gitignore","content":"*.log\n!projects/nuevo/\n"}' > "$TMP/in.json"
  run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "android-adb-validate bloquea por stdin un borrado recursivo por adb shell" {
  export HOME="$TMP"
  payload Bash '{"command":"adb shell rm -rf /sdcard/x"}' > "$TMP/in.json"
  run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "android-adb-validate deja pasar por stdin adb devices" {
  export HOME="$TMP"
  payload Bash '{"command":"adb devices"}' > "$TMP/in.json"
  run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

@test "recursion-guard bloquea por stdin un bucle dentro de otro" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  payload Task '{"prompt":"lanza overnight-sprint otra vez"}' > "$TMP/in.json"
  run bash .opencode/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

# ── Gates que empiezan a actuar: acción real por stdin y sin falsos positivos por menciones ──

repo() {
  git init -q "$TMP/repo" && cd "$TMP/repo"
  git config user.email t@example.invalid && git config user.name t
  printf 'x\n' > a.txt && git add a.txt
}

@test "compliance-gate ejecuta el runner por stdin y bloquea si falla" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude/compliance"
  printf '#!/bin/bash\necho runner-ejecutado >&2\nexit 1\n' > "$CLAUDE_PROJECT_DIR/.claude/compliance/runner.sh"
  payload Bash '{"command":"git commit -m \"mensaje suficientemente largo\""}' > "$TMP/in.json"
  run bash .opencode/hooks/compliance-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *runner-ejecutado* ]]
}

@test "compliance-gate no actúa cuando el texto solo se menciona" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude/compliance"
  printf '#!/bin/bash\nexit 1\n' > "$CLAUDE_PROJECT_DIR/.claude/compliance/runner.sh"
  payload Bash '{"command":"git log --grep=\"git commit\"","description":"buscar git commit"}' > "$TMP/in.json"
  run bash .opencode/hooks/compliance-gate.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

@test "agent-hook-premerge revisa lo preparado por stdin y bloquea marcas de conflicto" {
  H="$PWD/.opencode/hooks/agent-hook-premerge.sh"; repo
  printf '<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> otra\n' > a.txt && git add a.txt
  export AGENT_HOOKS_MODE=hard-block
  payload Bash '{"command":"git merge feature"}' > "$TMP/in.json"
  run bash "$H" < "$TMP/in.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"conflict markers"* ]]
}

@test "agent-hook-premerge no actúa con una mención en un echo" {
  H="$PWD/.opencode/hooks/agent-hook-premerge.sh"; repo
  printf '<<<<<<< HEAD\n' > a.txt && git add a.txt
  export AGENT_HOOKS_MODE=hard-block
  payload Bash '{"command":"echo \"luego git merge\""}' > "$TMP/in.json"
  run bash "$H" < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

@test "prompt-hook-commit revisa por stdin el mensaje y bloquea uno demasiado corto" {
  H="$PWD/.opencode/hooks/prompt-hook-commit.sh"; repo
  export PROMPT_HOOKS_MODE=hard-block
  payload Bash '{"command":"git commit -m \"wip\""}' > "$TMP/in.json"
  run bash "$H" < "$TMP/in.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"too short"* ]]
}

@test "pr-summary-gate no bloquea un heredoc que solo menciona la orden" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  payload Bash '{"command":"cat > .pr-summary.md <<EOF\nantes de gh pr create\nEOF"}' > "$TMP/in.json"
  run bash .opencode/hooks/pr-summary-gate.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

# ── Reproducciones de la revisión de refutación (otro proveedor) ──

runner_falla() {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude/compliance"
  printf '#!/bin/bash\nexit 1\n' > "$CLAUDE_PROJECT_DIR/.claude/compliance/runner.sh"
}

@test "compliance-gate: el prefijo command no elude el gate" {
  runner_falla
  payload Bash '{"command":"command git commit -m \"mensaje suficientemente largo\""}' > "$TMP/in.json"
  run bash .opencode/hooks/compliance-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "compliance-gate: -c con valor entre comillas y espacios no elude el gate" {
  runner_falla
  payload Bash '{"command":"git -c user.name=\"Jane Doe\" commit -m \"mensaje suficientemente largo\""}' > "$TMP/in.json"
  run bash .opencode/hooks/compliance-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "compliance-gate: sudo y bash -c tampoco lo eluden" {
  runner_falla
  for c in 'sudo git commit -m \"mensaje suficientemente largo\"' 'bash -c \"git commit -m mensaje-suficientemente-largo\"'; do
    payload Bash "{\"command\":\"$c\"}" > "$TMP/in.json"
    run bash .opencode/hooks/compliance-gate.sh < "$TMP/in.json"
    [ "$status" -eq 2 ] || { echo "elude: $c"; return 1; }
  done
}

@test "pr-summary-gate: JSON con espacio inicial no elude el gate" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  printf ' {"tool_input":{"command":"gh pr create --draft"}}' > "$TMP/in.json"
  run bash .opencode/hooks/pr-summary-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "pr-summary-gate: JSON truncado falla cerrado" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  printf '{"tool_input":{"command":"gh pr create --draft"}' > "$TMP/in.json"
  run bash .opencode/hooks/pr-summary-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "pr-summary-gate: un cuerpo enorme multilínea no elude el gate (sin SIGPIPE)" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  python3 -c 'import json; print(json.dumps({"tool_input":{"command":"gh pr create --draft --body \"a\n"+"x"*3000000+"\""}}))' > "$TMP/in.json"
  run bash .opencode/hooks/pr-summary-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "sin entrada, el gate queda registrado como no medido" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  run bash .opencode/hooks/pr-summary-gate.sh < /dev/null
  [ "$status" -eq 0 ]
  grep -q '"hook":"pr-summary-gate","reason":"empty_input"' "$CLAUDE_PROJECT_DIR/output/unmeasured-gates.jsonl"
}

@test "ningún hook command PreToolUse usa patrones de argumentos que Claude Code no aplica" {
  run python3 -c 'import json
d=json.load(open(".claude/settings.json"))
bad=[m["matcher"] for m in d["hooks"].get("PreToolUse",[]) if "(" in m.get("matcher","") and any(h.get("type")=="command" for h in m.get("hooks",[]))]
print(bad); raise SystemExit(1 if bad else 0)'
  [ "$status" -eq 0 ]
}

@test "ningún hook de tipo prompt queda con matcher Bash sin filtro (evaluaría con un LLM cada orden)" {
  run python3 -c 'import json
d=json.load(open(".claude/settings.json"))
bad=[m["matcher"] for m in d["hooks"].get("PreToolUse",[]) if m.get("matcher")=="Bash" and any(h.get("type")=="prompt" for h in m.get("hooks",[]))]
print(bad); raise SystemExit(1 if bad else 0)'
  [ "$status" -eq 0 ]
}

# ── Ronda 5: reproducciones de la segunda refutación ──

@test "pr-summary-gate: if, !, env -u y sudo -u no eluden el gate" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  for c in 'if gh pr create --draft; then :; fi' '! gh pr create --draft' 'env -u X gh pr create --draft' 'sudo -u root gh pr create --draft'; do
    payload Bash "{\"command\":\"$c\"}" > "$TMP/in.json"
    run bash .opencode/hooks/pr-summary-gate.sh < "$TMP/in.json"
    [ "$status" -eq 2 ] || { echo "elude: $c"; return 1; }
  done
}

@test "block-project-whitelist: una edición parcial que cambia el nombre de una whitelist bloquea" {
  mkdir -p "$TMP/proj"; export CLAUDE_PROJECT_DIR="$TMP/proj"
  printf '%s\n' "!pro""jects/alfa/" > "$TMP/proj/.gitignore"
  payload Edit '{"file_path":".gitignore","old_string":"alfa","new_string":"beta"}' > "$TMP/in.json"
  run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "block-project-whitelist: contenido enorme no elude por SIGPIPE" {
  mkdir -p "$TMP/proj"; export CLAUDE_PROJECT_DIR="$TMP/proj"
  python3 -c 'import json; print(json.dumps({"tool_input":{"file_path":".gitignore","content":"!pro"+"jects/g/\n#"+"x"*3000000}}))' > "$TMP/in.json"
  run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "recursion-guard: un escape JSON equivalente no elude el guard" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  python3 -c 'print(chr(123)+chr(34)+"tool_name"+chr(34)+":"+chr(34)+"Task"+chr(34)+","+chr(34)+"tool_input"+chr(34)+":"+chr(123)+chr(34)+"prompt"+chr(34)+":"+chr(34)+"lanza overnight"+chr(92)+"u002dsprint"+chr(34)+chr(125)+chr(125))' > "$TMP/in.json"
  grep -q 'u002d' "$TMP/in.json"
  run bash .opencode/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "recursion-guard: un campo enorme no elude por SIGPIPE" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  python3 -c 'import json; print(json.dumps({"tool_name":"Task","tool_input":{"prompt":"lanza overnight-sprint","extra":"x"*3000000}},indent=2))' > "$TMP/in.json"
  run bash .opencode/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

# ── Ronda 6: tercera refutación (guards de seguridad) ──

@test "android-adb-validate: comillas y orden de opciones no eluden el bloqueo" {
  export HOME="$TMP"
  for c in "adb shell 'rm -rf /sdcard/x'" 'adb shell rm -fr /sdcard/x' 'adb shell rm -R -f /sdcard/x' 'adb shell \"rm --recursive /sdcard/x\"'; do
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$c" > "$TMP/in.json"
    run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
    [ "$status" -eq 2 ] || { echo "elude: $c"; return 1; }
  done
}

@test "android-adb-validate: JSON truncado con una orden bloqueada falla cerrado" {
  export HOME="$TMP"
  printf '%s' '{"tool_input":{"command":"adb shell rm -rf /sdcard/x"}' > "$TMP/in.json"
  run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "recursion-guard: dentro de un bucle, entrada vacía o no evaluable falla cerrado" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  run bash .opencode/hooks/recursion-guard.sh < /dev/null
  [ "$status" -eq 2 ]
  printf '[' > "$TMP/in.json"
  run bash .opencode/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "recursion-guard: una clave loop_skill con contenedor vacío sigue detectándose" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  printf '%s' '{"tool_input":{"loop_skill":{}}}' > "$TMP/in.json"
  run bash .opencode/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "recursion-guard: sin jq, un escape que no puede decodificar falla cerrado" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  mkdir -p "$TMP/bin"; for b in bash cat timeout grep head printf; do ln -sf "$(command -v $b)" "$TMP/bin/$b"; done
  python3 -c 'print(chr(123)+chr(34)+"tool_input"+chr(34)+":"+chr(123)+chr(34)+"prompt"+chr(34)+":"+chr(34)+"lanza overnight"+chr(92)+"u002dsprint"+chr(34)+chr(125)+chr(125))' > "$TMP/in.json"
  run env PATH="$TMP/bin" bash .opencode/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "android-adb-validate: comillas, barra o tabulador en el binario no eluden el prefiltro" {
  export HOME="$TMP"
  for c in '"adb" shell rm -rf /sdcard/x' "'adb' shell rm -rf /sdcard/x" 'a\db shell rm -rf /sdcard/x' "$(printf 'adb\tshell rm -rf /sdcard/x')"; do
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$c" > "$TMP/in.json"
    run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
    [ "$status" -eq 2 ] || { echo "elude: $c"; return 1; }
  done
}

@test "android-adb-validate: opciones de borrado recursivo después de la ruta no eluden el bloqueo" {
  export HOME="$TMP"
  for c in 'adb shell rm /sdcard/x -rf' 'adb shell rm /sdcard/x --recursive' 'adb shell rm /sdcard/x -f -R'; do
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$c" > "$TMP/in.json"
    run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
    [ "$status" -eq 2 ] || { echo "elude: $c"; return 1; }
  done
}

@test "android-adb-validate: un borrado no recursivo por adb no se bloquea" {
  export HOME="$TMP"
  python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"adb shell rm /sdcard/fichero-temporal.txt"}}))' > "$TMP/in.json"
  run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
  [ "$status" -eq 0 ]
}

# ── Ronda 9: una variable heredada no puede anular la entrada real por stdin ──

@test "block-project-whitelist: CLAUDE_TOOL_INPUT heredada no anula stdin" {
  mkdir -p "$TMP/proj"; export CLAUDE_PROJECT_DIR="$TMP/proj"
  printf '*.log\n' > "$TMP/proj/.gitignore"
  python3 -c 'import json; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":".gitignore","old_string":"*.log","new_string":"*.log\n!pro"+"jects/a/"}}))' > "$TMP/in.json"
  CLAUDE_TOOL_INPUT=' ' run bash .opencode/hooks/block-project-whitelist.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "android-adb-validate: TOOL_INPUT heredada no anula stdin" {
  export HOME="$TMP"
  python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"adb shell rm -rf /sdcard/x"}}))' > "$TMP/in.json"
  TOOL_INPUT=' ' run bash .opencode/hooks/android-adb-validate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "pr-summary-gate (lector común): CLAUDE_TOOL_INPUT heredada no anula stdin" {
  export CLAUDE_PROJECT_DIR="$TMP/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  printf '%s' '{"tool_input":{"command":"gh pr create --draft"}}' > "$TMP/in.json"
  CLAUDE_TOOL_INPUT='echo hola' run bash .opencode/hooks/pr-summary-gate.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}

@test "recursion-guard: OPENCODE_TOOL_INPUT heredada no anula stdin" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:1"
  printf '%s' '{"tool_input":{"prompt":"lanza overnight-sprint"}}' > "$TMP/in.json"
  OPENCODE_TOOL_INPUT='{"prompt":"ls"}' run bash .opencode/hooks/recursion-guard.sh < "$TMP/in.json"
  [ "$status" -eq 2 ]
}
