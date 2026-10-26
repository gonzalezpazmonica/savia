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
    grep -qE 'cat( |\)|$)|read -r|hook_extract' ".claude/hooks/$f" || bad="$bad $f"
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
