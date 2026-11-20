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
