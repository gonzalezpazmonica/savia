#!/usr/bin/env bats
# Guard de firmantes (scripts/operator-grant.sh guard): los cuerpos de heredoc
# son DATO para llaves y comodines solo cuando nadie los ejecuta como shell.
# Complementa tests/test-guards-falsos-positivos.bats (G1): aquí, las formas
# peligrosas parecidas que la poda de heredocs NO debe dejar pasar.
# Las órdenes nunca se ejecutan: solo se pasan al guard como evento PreToolUse.

setup() {
  SOURCE_ROOT="${HOOKS_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  CASE_ROOT=$(mktemp -d /tmp/savia-grant-heredoc.XXXXXX)
  REPO="$CASE_ROOT/repo"
  mkdir -p "$REPO/scripts/lib" "$REPO/config"
  cp "$SOURCE_ROOT/scripts/operator-grant.sh" "$REPO/scripts/"
  cp "$SOURCE_ROOT/scripts/lib/guard-decision-log.sh" "$REPO/scripts/lib/"
  printf '# fixture sin claves\n' > "$REPO/config/operator-grant-signers"
  printf 'entrada\n' > "$REPO/x"
  export CLAUDE_PROJECT_DIR="$REPO"
  cd "$REPO"
}

teardown() {
  cd /tmp
  [[ "${CASE_ROOT:-}" == /tmp/savia-grant-heredoc.* ]] && rm -rf -- "$CASE_ROOT"
}

guard() {
  jq -nc --arg c "$1" --arg d "$PWD" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' \
    | bash "$REPO/scripts/operator-grant.sh" guard
}

assert_block() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"raíz de confianza"* ]]
}

@test "allow: cat a un fichero con llaves y comodines en el cuerpo" {
  run guard $'cat > notas.md <<\'EOF\'\nconfig/* {a,b} o*\nEOF'
  [ "$status" -eq 0 ]
}

@test "allow: python3 con delimitador entre comillas y comodín como dato" {
  run guard $'python3 - <<\'PY\'\nprint("config/*")\nPY'
  [ "$status" -eq 0 ]
}

@test "block: el cuerpo de cat se ejecuta después con bash" {
  run guard $'cat > s.sh <<\'EOF\'\ncp x config/*\nEOF\nbash s.sh'
  assert_block
}

@test "block: el cuerpo de cat se carga con source" {
  run guard $'cat > s.sh <<\'EOF\'\ncp x config/*\nEOF\nsource s.sh'
  assert_block
}

@test "block: cat por tubería a bash" {
  run guard $'cat <<\'EOF\' | bash\ncp x config/*\nEOF'
  assert_block
}

@test "block: python lanza un shell con el comodín" {
  run guard $'python3 - <<\'PY\'\nimport os\nos.system("cp x " + "config/*")\nPY'
  assert_block
}

@test "block: python enumera config/* con glob" {
  run guard $'python3 - <<\'PY\'\nimport glob\nfor p in glob.glob("config/*"): open(p, "w")\nPY'
  assert_block
}

@test "block: heredoc sin comillas no se poda" {
  run guard $'python3 - <<PY\nprint("config/*")\nPY'
  assert_block
}

@test "block: tubería a un shell con nombre no listado (ksh93)" {
  run guard $'cat <<\'EOF\' | ksh93\ncp x config/*\nEOF'
  assert_block
}

@test "block: un << dentro de comillas no abre heredoc" {
  run guard $'cat "<<\'EOF\' "\ncp x config/*\nEOF'
  assert_block
}

@test "block: un << tras # es comentario y no abre heredoc" {
  run guard $'cat > n.md # <<\'EOF\'\ncp x config/*\nEOF'
  assert_block
}

@test "block: un << en una línea de comentario no abre heredoc" {
  run guard $'# cat <<\'EOF\'\ncp x config/*\nEOF'
  assert_block
}

@test "block: lector desconocido conserva el cuerpo" {
  run guard $'awk -f /dev/stdin <<\'EOF\'\ncp x config/*\nEOF'
  assert_block
}

@test "block: heredoc sin cerrar conserva la orden entera" {
  run guard $'cat > n.md <<\'EOF\'\ncp x config/*'
  assert_block
}

# --- Revisión de #1628: formas que la primera poda dejaba pasar -------------

@test "block: heredoc sin comillas delante del entrecomillado en la misma línea" {
  run guard $'cat <<EOF <<\'X\'\n$(sed -i s/a/b/ config/*)\nEOF\nX'
  assert_block
}

@test "block: cat escribe un .py y python3 lo ejecuta después" {
  run guard $'cat > s.py <<\'EOF\'\nimport os; g = "config/*"; os.system("tee " + g + " < x")\nEOF\npython3 s.py'
  assert_block
}

@test "block: cat escribe un .js y node lo ejecuta después" {
  run guard $'cat > s.js <<\'EOF\'\nconst g = "config/*"; require("child_process").execSync("tee " + g + " < x")\nEOF\nnode s.js'
  assert_block
}

@test "block: cat escribe un script y se ejecuta por su ruta" {
  run guard $'cat > s <<\'EOF\'\ncp x config/*\nEOF\n./s'
  assert_block
}

@test "block: perl ya no es lector de datos (operador glob <config/*>)" {
  run guard $'perl - <<\'PL\'\nfor (<config/*>) { open F, ">$_" }\nPL'
  assert_block
}

@test "block: ruby ya no es lector de datos (%x)" {
  run guard $'ruby - <<\'RB\'\n%x(tee config/* < x)\nRB'
  assert_block
}

@test "block: python llega a os.system por getattr y __import__" {
  run guard $'python3 - <<\'PY\'\ng = "config/*"; getattr(__import__("o"+"s"), "sys"+"tem")("tee " + g + " < x")\nPY'
  assert_block
}

@test "block: python importa un módulo fuera de la lista cerrada" {
  run guard $'python3 - <<\'PY\'\nimport tarfile\nprint("config/*")\nPY'
  assert_block
}

@test "block: python3 con un script como argumento no lee el cuerpo como dato" {
  run guard $'python3 run.py <<\'PY\'\nconfig/*\nPY'
  assert_block
}

@test "block: lector suplantado por ruta (./cat)" {
  run guard $'./cat > n.md <<\'EOF\'\ncp x config/*\nEOF'
  assert_block
}

@test "block: lector suplantado con PATH delante" {
  run guard $'PATH=.:$PATH cat > n.md <<\'EOF\'\ncp x config/*\nEOF'
  assert_block
}

@test "block: python3 por ruta absoluta no es el lector desnudo" {
  run guard $'/tmp/x/python3 - <<\'PY\'\nprint("config/*")\nPY'
  assert_block
}

@test "allow: python3 con import de la lista cerrada y comodín como dato" {
  run guard $'python3 - <<\'PY\'\nimport json\nprint(json.dumps({"g": "config/*"}))\nPY'
  [ "$status" -eq 0 ]
}

# --- Medición: el código de motivo no depende del texto del mensaje ---------

last_reason() {
  tail -n1 "$REPO/output/guard-decisions/operator-grant.jsonl" | jq -r '.verdict + " " + .reason'
}

raw_guard() {
  printf '%s' "$1" | bash "$REPO/scripts/operator-grant.sh" guard
}

@test "medición: cada decisión registra su código de motivo" {
  run guard $'cat > n.md <<\'EOF\'\nconfig/*\nEOF'
  [ "$status" -eq 0 ]
  [ "$(last_reason)" = "allow bash-heredoc-dato" ]
  run guard 'ls scripts'
  [ "$status" -eq 0 ]
  [ "$(last_reason)" = "allow bash-sin-firmantes" ]
  run guard 'cp x config/*'
  assert_block
  [ "$(last_reason)" = "block firmantes-destino" ]
  run raw_guard 'no json'
  [ "$status" -eq 2 ]
  [ "$(last_reason)" = "block evento-no-evaluable" ]
  run raw_guard '{"tool_name":"Write","tool_input":{"file_path":"n.md"}}'
  [ "$status" -eq 0 ]
  [ "$(last_reason)" = "allow fichero-ajeno" ]
  run raw_guard '{"tool_name":"Read","tool_input":{"file_path":"n.md"}}'
  [ "$status" -eq 0 ]
  [ "$(last_reason)" = "allow herramienta-sin-ruta" ]
  [ "$(wc -l < "$REPO/output/guard-decisions/operator-grant.jsonl")" -eq 6 ]
}

@test "medición: el código de motivo no sale por stdout del hook" {
  run bash -c 'printf "%s" "$1" | bash "$2" guard 2>/dev/null' _ \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}' "$REPO/scripts/operator-grant.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Revisión de seguridad #1628, P1-1: la medición no puede cambiar la decisión,
# ni con un `exit` al cargar la librería ni con uno dentro de su función.
@test "block: una librería de medición que hace exit 0 al cargarse no convierte el bloqueo en allow" {
  printf 'exit 0\n' > "$REPO/scripts/lib/guard-decision-log.sh"
  run guard 'cp x config/*'
  assert_block
}

@test "block: una función de medición que hace exit 0 no convierte el bloqueo en allow" {
  printf 'guard_decision_log() { exit 0; }\n' > "$REPO/scripts/lib/guard-decision-log.sh"
  run guard 'cp x config/*'
  assert_block
}

@test "allow: una función de medición que hace exit 2 no convierte el allow en bloqueo" {
  printf 'guard_decision_log() { exit 2; }\n' > "$REPO/scripts/lib/guard-decision-log.sh"
  run guard 'ls config'
  [ "$status" -eq 0 ]
}

@test "allow: la medición no escribe nada en la salida del guard" {
  printf 'guard_decision_log() { echo FUGA; echo FUGA >&2; }\n' > "$REPO/scripts/lib/guard-decision-log.sh"
  run guard 'ls config'
  [ "$status" -eq 0 ]
  [[ "$output" != *FUGA* ]]
}

@test "medición: una orden Bash vacía tiene su código de motivo, no sin-motivo" {
  run guard ''
  [ "$status" -eq 0 ]
  [ "$(last_reason)" = "allow bash-sin-firmantes" ]
}
