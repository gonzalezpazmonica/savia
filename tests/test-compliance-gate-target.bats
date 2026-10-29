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
  [[ "$output" == *"Commit bloqueado"* ]]
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
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
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
  [[ "$output" == *"Commit bloqueado"*"$(cd "$BATS_TEST_TMPDIR/w/b" && pwd -P)"* ]]
}

@test "cd relativo + git -C relativo a un repo limpio: pasa aunque el cwd tenga violación" {
  mkrepo "$A" violation; mkrepo "$BATS_TEST_TMPDIR/w/b" clean
  gate "$A" "cd ../w && git -C b commit -m x"
  [ "$status" -eq 0 ]
}

@test "dos commits en repos distintos: se evalúan ambos" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "git commit -m x; git -C $B commit -m y"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "la palabra cd en prosa antes del commit: cd que no se sigue, bloquea por lista blanca (revisión 3)" {
  mkrepo "$A" violation
  gate "$A" "echo 'usa cd nope y luego' ; git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

@test "lista blanca de cd: cd tras {, then, do o ! bloquea en vez de evaluar otro repo" {
  mkrepo "$A" clean; mkrepo "$B" violation
  for c in "{ cd $B; git commit -m x; }" "if true; then cd $B; git commit -m x; fi" "for i in 1; do cd $B; git commit -m x; done" "! cd $B; git commit -m x"; do
    gate "$A" "$c"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no se puede determinar"* ]]
  done
}

@test "orden anidada: bash -c, sh -c y eval con cd y commit dentro bloquean" {
  mkrepo "$A" clean; mkrepo "$B" violation
  for c in "bash -c 'cd $B && git commit -m x'" "sh -c \"cd $B; git commit -m x\"" "eval \"cd $B && git commit -m x\""; do
    gate "$A" "$c"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no se puede determinar"* ]]
  done
}

@test "la forma estándar cd \"/ruta\" && git commit sigue evaluando el repo objetivo" {
  mkrepo "$A" violation; mkrepo "$B" clean
  gate "$A" "cd \"$B\" && git commit -m \"mensaje con cd dentro\""
  [ "$status" -eq 0 ]
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

@test "cat > fichero <<EOF con git commit dentro: se evalúa y, sin objetivo resoluble, bloquea (falso positivo aceptado, revisión 2)" {
  mkrepo "$A" clean
  gate "$A" "$(printf "cat > t.sh <<'EOF'\ngit -C \"\$1\" commit -q -m base\nEOF")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

@test "bash <<EOF con git commit dentro sí se evalúa (objetivo con violación)" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf "bash <<'EOF'\ngit -C %s commit -q -m base\nEOF" "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "bash <<EOF con git commit dentro sí se evalúa (objetivo limpio pasa)" {
  mkrepo "$A" violation; mkrepo "$B" clean
  gate "$A" "$(printf "bash <<'EOF'\ngit -C %s commit -q -m base\nEOF" "$B")"
  [ "$status" -eq 0 ]
}

# --- Revisión 2: órdenes multilínea ---

@test "multilínea: commit en la 2.ª línea se localiza y se evalúa (limpio pasa)" {
  mkrepo "$A" clean
  gate "$A" "$(printf 'git add README.md\ngit commit -m y')"
  [ "$status" -eq 0 ]
}

@test "multilínea: commit en la 2.ª línea con violación bloquea por la violación" {
  mkrepo "$A" violation
  gate "$A" "$(printf 'git add README.md\ngit commit -m y')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"* ]]
}

@test "multilínea: el 2.º commit de otra línea también se evalúa" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf 'git commit -m a\ngit -C %s commit -m b' "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "multilínea: cd en una línea y commit en la siguiente sigue al cd" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf 'cd %s\ngit commit -m b' "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

# --- Revisión 2: los heredocs que se ejecutan no se descartan ---

@test "cat <<EOF | bash con commit dentro se evalúa" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf "cat <<'EOF' | bash\ngit -C %s commit -m x\nEOF" "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "cat > s.sh <<EOF && bash s.sh con commit dentro se evalúa" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf "cat > s.sh <<'EOF' && bash s.sh\ngit -C %s commit -m x\nEOF" "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "cat > s.sh <<EOF y bash s.sh en otra línea: el cuerpo se evalúa" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf "cat > s.sh <<'EOF'\ngit -C %s commit -m x\nEOF\nbash s.sh" "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "tee >(bash) <<EOF con commit dentro se evalúa" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf "tee >(bash) <<'EOF'\ngit -C %s commit -m x\nEOF" "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "grupo con cat > /dev/stdout canalizado a bash: el cuerpo se evalúa" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf "{\ncat > /dev/stdout <<'EOF'\ngit -C %s commit -m x\nEOF\n} | bash" "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "here-string <<<palabra no abre un heredoc que oculte commits posteriores" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf 'cat <<<foo\ngit -C %s commit -m x' "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "heredoc sin terminador: el cuerpo se conserva y se evalúa" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "$(printf "cat > f.txt <<'EOF'\ngit -C %s commit -m x" "$B")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"*"$B"* ]]
}

@test "tee fichero <<EOF con git commit dentro: se evalúa y, sin objetivo resoluble, bloquea (falso positivo aceptado, revisión 2)" {
  mkrepo "$A" clean
  gate "$A" "$(printf "tee t.sh <<'EOF'\ngit -C \"\$1\" commit -q -m base\nEOF")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

# --- Revisión 2: cd que no cambia el cwd del commit y entorno de git ---

@test "(cd X; true); git commit: el cd del subshell no se sigue y bloquea" {
  mkrepo "$A" violation; mkrepo "$B" clean
  gate "$A" "(cd $B; true); git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

@test "cd entre comillas (texto de un echo) no se sigue y bloquea" {
  mkrepo "$A" violation; mkrepo "$B" clean
  gate "$A" "echo \"x; cd $B\"; git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

@test "pushd X && git commit bloquea (pushd no se sigue)" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "pushd $B && git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

@test "GIT_DIR= en el entorno de la orden bloquea" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "GIT_DIR=$B/.git GIT_WORK_TREE=$B git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

@test "export GIT_WORK_TREE previo bloquea" {
  mkrepo "$A" clean; mkrepo "$B" violation
  gate "$A" "export GIT_WORK_TREE=$B; git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede determinar"* ]]
}

# --- Revisión 2: estado heredado y herramientas que fallan ---

@test "texto plano: HOOK_SESSION_CWD heredado del entorno no desvía el objetivo" {
  mkrepo "$A" violation; mkrepo "$B" clean
  cd "$A"
  run env HOOK_SESSION_CWD="$B" CLAUDE_TOOL_INPUT="git commit -m x" bash "$ROOT/.claude/hooks/compliance-gate.sh" </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"Commit bloqueado"* ]]
}

@test "eval o sh -c dentro del mensaje del commit no es una orden anidada (revisión 4)" {
  mkrepo "$A" clean
  gate "$A" "git commit -m \"fix eval harness; usa sh -c para probar\""
  [ "$status" -eq 0 ]
}

@test "cd en segundo plano o en tubería no cambia el directorio: bloquea (revisión 4)" {
  mkrepo "$A" violation; mkrepo "$B" clean
  for c in "cd $B & git commit -m x" "cd $B | cat; git commit -m x"; do
    gate "$A" "$c"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no se puede determinar"* ]]
  done
}
