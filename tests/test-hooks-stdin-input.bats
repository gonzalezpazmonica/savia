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

@test "block-project-whitelist bloquea por stdin un !projects/ en .gitignore" {
  payload Edit '{"file_path":".gitignore","old_string":"x","new_string":"!projects/secreto/"}' > "$TMP/in.json"
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

@test "ningún matcher PreToolUse usa patrones de argumentos que Claude Code no aplica" {
  run python3 -c 'import json
d=json.load(open(".claude/settings.json"))
bad=[m["matcher"] for m in d["hooks"].get("PreToolUse",[]) if "(" in m.get("matcher","")]
print(bad); raise SystemExit(1 if bad else 0)'
  [ "$status" -eq 0 ]
}
