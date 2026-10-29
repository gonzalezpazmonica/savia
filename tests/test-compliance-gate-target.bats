#!/usr/bin/env bats
# Compliance gate evalúa el repo objetivo del commit (git -C / cd previo / cwd), no el de la sesión.
# SCRIPT=.claude/hooks/compliance-gate.sh
# Violación usada: README.md de 151 líneas staged (check 4 del runner, máx 150).

ROOT="$BATS_TEST_DIRNAME/.."

mkrepo() {  # mkrepo <dir> <violation|clean>
  mkdir -p "$1"
  git -C "$1" init -q -b feature/x
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name t
  echo base > "$1/base.txt"
  git -C "$1" add base.txt
  git -C "$1" commit -q -m base
  if [[ "$2" == violation ]]; then
    seq 1 151 > "$1/README.md"
  else
    echo ok > "$1/README.md"
  fi
  git -C "$1" add README.md
}

gate() {  # gate <cwd> <orden> → ejecuta el hook con JSON por stdin
  local cwd="$1" cmd="$2" json
  json=$(jq -n --arg c "$cmd" --arg d "$cwd" '{tool_input:{command:$c},cwd:$d}')
  cd "$cwd" 2>/dev/null || cd "$BATS_TEST_TMPDIR"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$ROOT/.claude/hooks/compliance-gate.sh"
}

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SAVIA_HOOK_PROFILE=standard
  export CLAUDE_PROJECT_DIR="$(cd "$ROOT" && pwd)"
  unset CLAUDE_TOOL_INPUT COMPLIANCE_TARGET_DIR
  A="$BATS_TEST_TMPDIR/a"; B="$BATS_TEST_TMPDIR/b"
}

@test "cwd normal: violación staged en el cwd bloquea" {
  mkrepo "$A" violation
  gate "$A" "git commit -m x"
  [ "$status" -eq 2 ]
}

@test "cwd normal: cwd limpio pasa" {
  mkrepo "$A" clean
  gate "$A" "git commit -m x"
  [ "$status" -eq 0 ]
}

@test "git -C otro repo: bloquea por la violación del objetivo aunque el cwd esté limpio" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "git -C $B commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$B"* ]]
}

@test "git -C otro repo limpio: pasa aunque el cwd tenga violación" {
  mkrepo "$A" violation; mkrepo "$B" clean
  gate "$A" "git -C $B commit -m x"
  [ "$status" -eq 0 ]
}

@test "cd x && git commit: bloquea por la violación del objetivo" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "cd $B && git commit -m x"
  [ "$status" -eq 2 ]
}

@test "cd x && git commit con objetivo limpio: pasa aunque el cwd tenga violación" {
  mkrepo "$A" violation; mkrepo "$B" clean
  gate "$A" "cd \"$B\" && git commit -m x"
  [ "$status" -eq 0 ]
}

@test "cd relativo + git -C relativo se componen" {
  mkrepo "$A" clean; mkrepo "$BATS_TEST_TMPDIR/w/b" violation
  gate "$A" "cd ../w && git -C b commit -m x"
  [ "$status" -eq 2 ]
}

@test "dos commits en repos distintos: se evalúan ambos" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "git commit -m x; git -C $B commit -m y"
  [ "$status" -eq 2 ]
}

@test "la palabra cd en prosa antes del commit no cambia el objetivo" {
  mkrepo "$A" violation
  gate "$A" "echo 'usa cd nope y luego' ; git commit -m x"
  [ "$status" -eq 2 ]
}

@test "sin objetivo resoluble: ruta con variable bloquea" {
  mkrepo "$A" clean
  gate "$A" 'git -C "$TARGET" commit -m x'
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

@test "sin objetivo resoluble: directorio inexistente bloquea" {
  mkrepo "$A" clean
  gate "$A" "git -C $BATS_TEST_TMPDIR/nope commit -m x"
  [ "$status" -eq 2 ]
}

@test "sin objetivo resoluble: cd a sustitución de comando bloquea" {
  mkrepo "$A" clean
  gate "$A" 'cd $(mktemp -d) && git commit -m x'
  [ "$status" -eq 2 ]
}

@test "sin objetivo resoluble: --git-dir bloquea" {
  mkrepo "$A" clean
  gate "$A" "git --git-dir=$A/.git commit -m x"
  [ "$status" -eq 2 ]
}

@test "sin objetivo resoluble: cwd fuera de un repo bloquea" {
  mkdir -p "$BATS_TEST_TMPDIR/norepo"
  gate "$BATS_TEST_TMPDIR/norepo" "git commit -m x"
  [ "$status" -eq 2 ]
}

@test "órdenes que no son commit no se evalúan" {
  mkrepo "$A" violation
  gate "$A" "git -C $A status"
  [ "$status" -eq 0 ]
}

@test "cat > fichero <<EOF con líneas git commit dentro no es un commit" {
  mkrepo "$A" clean
  gate "$A" "$(printf "cat > t.sh <<'EOF'\ngit -C \"\$1\" commit -q -m base\nEOF")"
  [ "$status" -eq 0 ]
}

@test "bash <<EOF con git commit dentro sí se evalúa" {
  mkrepo "$A" clean
  gate "$A" "$(printf "bash <<'EOF'\ngit -C \"\$1\" commit -q -m base\nEOF")"
  [ "$status" -eq 2 ]
}
