#!/usr/bin/env bats
# BATS tests for .claude/hooks/block-sensitive-tracking.sh
# Ref: docs/specs/SE-258-brechas-identitarias.spec.md
# SE-339: cobertura de hook crítico (seguridad de datos). SE-258 S1: rutas N2-N4 declaradas.
# Casos de comportamiento: se ejecuta el hook con un config temporal y se comprueba el
# código de salida y el mensaje, no el texto del script.
SCRIPT=".claude/hooks/block-sensitive-tracking.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  REPO="$PWD"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/config"
  cat > "$PROJ/config/sensitive-paths.yaml" <<'EOF'
version: "1.0"

levels:
  N4:
    description: "identidad"
    paths:
      - "data/relacion/**"
      - "vault/*.key"
  N3:
    description: "privado"
    paths:
      - ".claude/rules/pm-config.local.md"
      - "projects/*/private/**"
  N2:
    description: "interno"
    paths:
      - "internal/audit/**"

allowlist:
  paths:
    - "tests/fixtures/**"
    - "projects/*/private/public-readme.md"
EOF
  export CLAUDE_PROJECT_DIR="$PROJ"
  unset SAVIA_SENSITIVE_TRACKING SAVIA_HOOK_PROFILE
}
teardown() { cd /; }

@test "existe y es ejecutable por bash" {
  [[ -f "$SCRIPT" ]]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "usa set -uo pipefail" {
  run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

# hook <tool> <file_path>
hook() {
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" | bash "$SCRIPT"
}

@test "Write a una ruta N4 se bloquea con exit 2 y el mensaje nombra la ruta" {
  run hook Write "data/relacion/pareja.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED [sensitive-tracking]"* ]]
  [[ "$output" == *"'data/relacion/pareja.md'"* ]]
}

@test "Edit a una ruta N3 se bloquea con exit 2" {
  run hook Edit ".claude/rules/pm-config.local.md"
  [ "$status" -eq 2 ]
}

@test "el comodin intermedio de N3 cubre cualquier proyecto" {
  run hook Write "projects/alfa/private/nota.md"
  [ "$status" -eq 2 ]
  run hook Write "projects/otro-distinto/private/sub/dir/x.txt"
  [ "$status" -eq 2 ]
}

@test "la ruta N2 tambien se bloquea (ultimo nivel antes de allowlist)" {
  run hook Write "internal/audit/informe.md"
  [ "$status" -eq 2 ]
}

@test "patron N4 de extension solo bloquea esa extension" {
  run hook Write "vault/master.key"
  [ "$status" -eq 2 ]
  run hook Write "vault/master.txt"
  [ "$status" -eq 0 ]
}

@test "una ruta no declarada pasa en silencio" {
  run hook Write "src/app/main.py"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "la allowlist gana sobre un patron de bloqueo que tambien casa" {
  run hook Write "projects/alfa/private/public-readme.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # la hermana en la misma carpeta, fuera de la allowlist, sigue bloqueada
  run hook Write "projects/alfa/private/secreto.md"
  [ "$status" -eq 2 ]
}

@test "las rutas de la allowlist pasan aunque nadie mas las mencione" {
  run hook Write "tests/fixtures/data/relacion/ejemplo.md"
  [ "$status" -eq 0 ]
}

@test "herramientas que no son Edit ni Write no se evaluan" {
  for t in Read Bash Grep MultiEdit; do
    run hook "$t" "data/relacion/pareja.md"
    [ "$status" -eq 0 ] || { echo "bloqueado con $t"; return 1; }
  done
}

@test "sin file_path el hook no bloquea" {
  run bash -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{}}' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "SAVIA_SENSITIVE_TRACKING=off desactiva el bloqueo; cualquier otro valor lo deja activo" {
  SAVIA_SENSITIVE_TRACKING=off run hook Write "data/relacion/pareja.md"
  [ "$status" -eq 0 ]
  SAVIA_SENSITIVE_TRACKING=on run hook Write "data/relacion/pareja.md"
  [ "$status" -eq 2 ]
}

@test "sin config/sensitive-paths.yaml el hook no bloquea nada" {
  rm "$PROJ/config/sensitive-paths.yaml"
  run hook Write "data/relacion/pareja.md"
  [ "$status" -eq 0 ]
}

@test "el hook corre en los tres perfiles porque es de tier security" {
  for p in minimal standard strict ci; do
    SAVIA_HOOK_PROFILE=$p run hook Write "data/relacion/pareja.md"
    [ "$status" -eq 2 ] || { echo "no bloquea en perfil $p"; return 1; }
  done
}

@test "stdin vacio no rompe ni bloquea" {
  run bash -c "bash '$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
}

@test "sin jq falla abierto (exit 0) en vez de bloquear a ciegas" {
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  for c in dirname timeout cat sed grep head date mkdir tr basename; do
    p=$(command -v "$c") && ln -sf "$p" "$BIN/$c"
  done
  run env PATH="$BIN" "$(command -v bash)" -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"data/relacion/x.md\"}}' | $(command -v bash) '$REPO/$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "el config real del repo protege la identidad activa y el vault de relacion" {
  CLAUDE_PROJECT_DIR="$REPO" run hook Write ".claude/profiles/active-user.md"
  [ "$status" -eq 2 ]
  CLAUDE_PROJECT_DIR="$REPO" run hook Write "data/relacion/x.md"
  [ "$status" -eq 2 ]
  CLAUDE_PROJECT_DIR="$REPO" run hook Write "scripts/otra-cosa.sh"
  [ "$status" -eq 0 ]
}

@test "la allowlist termina en la linea en blanco: otra seccion posterior no la amplia" {
  printf '\nnotas:\n  - "data/relacion/**"\n' >> "$PROJ/config/sensitive-paths.yaml"
  run hook Write "data/relacion/pareja.md"
  [ "$status" -eq 2 ]
  run hook Write "tests/fixtures/ok.md"
  [ "$status" -eq 0 ]
}
