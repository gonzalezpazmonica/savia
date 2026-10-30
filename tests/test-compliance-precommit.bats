#!/usr/bin/env bats
# #1413: la verificación de compliance la hace git en `.githooks/pre-commit`, en el repo real del commit
# y sobre lo que va en stage, sea cual sea la forma de la orden. Estos tests hacen commits de verdad en
# repos temporales con el pre-commit instalado (core.hooksPath), en las formas que el análisis de texto
# anterior no sabía seguir. La CI ejecuta el mismo runner con --range.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_PROJECT_DIR
  R="$BATS_TEST_TMPDIR/repo"; mkrepo "$R"
}

mkrepo() {  # mkrepo <dir>: repo con el pre-commit, el runner y sus checks, como el workspace
  mkdir -p "$1"
  git -C "$1" init -q -b feature/x
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name t
  mkdir -p "$1/.githooks" "$1/.claude" "$1/scripts"
  cp "$ROOT/.githooks/pre-commit" "$1/.githooks/"
  cp -r "$ROOT/.claude/compliance" "$1/.claude/"
  cp "$ROOT/scripts/protect-project-privacy.sh" "$1/scripts/"
  [[ -f "$ROOT/scripts/validate-changelog-links.sh" ]] && cp "$ROOT/scripts/validate-changelog-links.sh" "$1/scripts/"
  git -C "$1" config core.hooksPath .githooks
  echo ok > "$1/README.md"; echo base > "$1/base.txt"
  git -C "$1" add -A && git -C "$1" commit -q -m base
}

violar() { seq 1 151 > "$1/README.md"; }   # README > 150 líneas: violación de check-readme-sync

@test "violación en stage: el commit falla en el pre-commit" {
  violar "$R"; git -C "$R" add README.md
  run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"COMPLIANCE"* ]]
}

@test "sin violación: el commit pasa" {
  echo cambio >> "$R/base.txt"; git -C "$R" add base.txt
  run git -C "$R" commit -m x
  [ "$status" -eq 0 ]
}

@test "desde otro directorio con git -C: se evalúa el repo del commit" {
  violar "$R"; git -C "$R" add README.md
  cd "$BATS_TEST_TMPDIR"
  run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
}

@test "subshell multilínea y bloque { }: se evalúa el repo del commit" {
  violar "$R"; git -C "$R" add README.md
  run bash -c "(
cd '$R'
git commit -m x
)"
  [ "$status" -ne 0 ]
  run bash -c "{ cd '$R'; git commit -m x; }"
  [ "$status" -ne 0 ]
}

@test "script escrito con heredoc y ejecutado: se evalúa el repo del commit" {
  violar "$R"; git -C "$R" add README.md
  cat > "$BATS_TEST_TMPDIR/s.sh" <<EOF
cd "$R" && git commit -m x
EOF
  run bash "$BATS_TEST_TMPDIR/s.sh"
  [ "$status" -ne 0 ]
}

@test "prefijo command, -c con valor entre comillas y bash -c: el pre-commit corre igual" {
  violar "$R"; git -C "$R" add README.md; cd "$R"
  run command git commit -m x
  [ "$status" -ne 0 ]
  run git -c user.name="Jane Doe" commit -m x
  [ "$status" -ne 0 ]
  run bash -c "git commit -m x"
  [ "$status" -ne 0 ]
}

@test "commit -a con la violación sin stage: git la prepara y el pre-commit la ve" {
  violar "$R"
  run git -C "$R" commit -a -m x
  [ "$status" -ne 0 ]
}

@test "worktree: se evalúa su árbol, no el del repo principal ni el de CLAUDE_PROJECT_DIR" {
  W="$BATS_TEST_TMPDIR/wt"; git -C "$R" worktree add -q -b agent/w "$W"
  violar "$W"; git -C "$W" add README.md
  run env CLAUDE_PROJECT_DIR="$R" git -C "$W" commit -m x
  [ "$status" -ne 0 ]
  echo cambio >> "$R/base.txt"; git -C "$R" add base.txt
  run env CLAUDE_PROJECT_DIR="$W" git -C "$R" commit -m y
  [ "$status" -eq 0 ]
}

@test "runner --range (CI): detecta la violación del rango, pasa un rango limpio y falla cerrado sin rango" {
  # El commit con la violación se hace sin hooks: simula uno que esquivó el pre-commit local.
  violar "$R"; git -C "$R" add README.md; git -C "$R" -c core.hooksPath=/dev/null commit -q -m v
  cd "$R"
  run bash .claude/compliance/runner.sh --range HEAD~1...HEAD
  [ "$status" -ne 0 ]
  echo ok > README.md; git add README.md; git -c core.hooksPath=/dev/null commit -q -m arreglo
  run bash .claude/compliance/runner.sh --range HEAD~1...HEAD
  [ "$status" -eq 0 ]
  run bash .claude/compliance/runner.sh --range no-existe...HEAD
  [ "$status" -eq 2 ]
  run bash .claude/compliance/runner.sh --range
  [ "$status" -eq 2 ]
}

@test "el PreToolUse compliance-gate ya no evalúa nada: sale con 0" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git commit -m x\"}}" | bash "$1"' _ "$ROOT/.claude/hooks/compliance-gate.sh"
  [ "$status" -eq 0 ]
}

# ── Revisión de #1413 en e49de789b ──

@test "runner --range: un comando sin frontmatter en el rango falla; con frontmatter pasa" {
  mkdir -p "$R/.claude/commands"; cd "$R"
  printf 'sin frontmatter\n' > .claude/commands/malo.md
  git add .claude/commands/malo.md; git -c core.hooksPath=/dev/null commit -q -m malo
  run bash .claude/compliance/runner.sh --range HEAD~1..HEAD
  [ "$status" -eq 2 ]
  [[ "$output" == *"malo.md: comando sin frontmatter"* ]]
  printf -- '---\nname: bueno\n---\n' > .claude/commands/malo.md
  git add .claude/commands/malo.md; git -c core.hooksPath=/dev/null commit -q -m arreglo
  run bash .claude/compliance/runner.sh --range HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"Frontmatter de comandos OK"* ]]
}

@test "pre-commit: se evalúa lo que va en stage, no el árbol de trabajo" {
  violar "$R"; git -C "$R" add README.md; echo ok > "$R/README.md"   # en stage malo, en disco bueno
  run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md: 151 líneas"* ]]
  git -C "$R" add README.md; violar "$R"                              # en stage bueno, en disco malo
  echo cambio >> "$R/base.txt"; git -C "$R" add base.txt
  run git -C "$R" commit -m y
  [ "$status" -eq 0 ]
}

@test "pre-commit sin nada en stage (--allow-empty): no evalúa el commit anterior" {
  violar "$R"; git -C "$R" add README.md; git -C "$R" -c core.hooksPath=/dev/null commit -q -m v
  run git -C "$R" commit --allow-empty -m vacio
  [ "$status" -eq 0 ]
  [[ "$output" != *"README.md: 151"* ]]
}

@test "runner --range: un rango sin .. ni ... se rechaza (exit 2)" {
  cd "$R"
  for r in HEAD 'HEAD..' '..HEAD' 'HEAD....HEAD'; do
    run bash .claude/compliance/runner.sh --range "$r"
    [ "$status" -eq 2 ]
  done
}

@test "nombre de fichero no ASCII: el límite de líneas se aplica igual" {
  mkdir -p "$R/.claude/skills"; seq 1 151 > "$R/.claude/skills/ñ.md"
  git -C "$R" add .claude/skills
  run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"ñ.md: 151 líneas"* ]]
}

@test "runner con violación: sale con 2 e imprime el resumen (no muere en la primera)" {
  violar "$R"; git -C "$R" add README.md; cd "$R"
  run bash .claude/compliance/runner.sh --staged
  [ "$status" -eq 2 ]
  [[ "$output" == *"1 verificación(es) fallida(s)"* ]]
}
