#!/usr/bin/env bats
# `.githooks/pre-commit` paso 0: git rechaza el commit en main/master sea cual sea la forma de la orden.
# Complementa block-commit-to-main.sh (#1467), que lee el texto de la orden y no ve dos casos:
# un script escrito y ejecutado en la misma orden, y git invocado con otro nombre (enlace).
# Commits de verdad en repos temporales con core.hooksPath .githooks.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset SAVIA_ALLOW_MAIN_COMMIT CLAUDE_PROJECT_DIR
  export SAVIA_TURN_SDLC_LOG_DIR="$BATS_TEST_TMPDIR/log"
  LOG="$SAVIA_TURN_SDLC_LOG_DIR/commit-guard.jsonl"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/.githooks"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  # Base sin hook; luego se activa el pre-commit del workspace.
  echo base > "$R/f.txt"; git -C "$R" add -A; git -C "$R" commit -q -m base
  cp "$ROOT/.githooks/pre-commit" "$R/.githooks/"
  git -C "$R" config core.hooksPath .githooks
}

cambio() { echo "$RANDOM$1" >> "$R/f.txt"; git -C "$R" add f.txt; }
commits() { git -C "$R" rev-list --count HEAD; }

@test "commit en main: bloqueado, sin commit nuevo y con registro block" {
  cambio a
  run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"commit en main bloqueado"* ]]
  [ "$(commits)" -eq 1 ]
  grep -q '"verdict":"block","source":"githook"' "$LOG"
}

@test "commit en master: bloqueado" {
  git -C "$R" branch -m main master
  cambio a
  run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  [ "$(commits)" -eq 1 ]
}

@test "agent/* permitido y main bloqueado en el mismo repo: decide la rama" {
  cambio a
  run git -C "$R" commit -m en-main
  [ "$status" -ne 0 ]
  git -C "$R" switch -q -c agent/tarea
  run git -C "$R" commit -m en-agent
  [ "$status" -eq 0 ]
  [ "$(commits)" -eq 2 ]
}

@test "HEAD separado: permitido; main sigue bloqueado" {
  cambio a
  run git -C "$R" commit -m en-main
  [ "$status" -ne 0 ]
  git -C "$R" switch -q --detach
  run git -C "$R" commit -m separado
  [ "$status" -eq 0 ]
  [ "$(commits)" -eq 2 ]
}

@test "bypass SAVIA_ALLOW_MAIN_COMMIT=1: permite y registra bypass" {
  cambio a
  SAVIA_ALLOW_MAIN_COMMIT=1 run git -C "$R" commit -m operadora
  [ "$status" -eq 0 ]
  [ "$(commits)" -eq 2 ]
  grep -q '"verdict":"bypass","source":"githook","env":"SAVIA_ALLOW_MAIN_COMMIT=1"' "$LOG"
}

@test "bypass con otro valor (0, true): no vale, bloqueado" {
  cambio a
  SAVIA_ALLOW_MAIN_COMMIT=0 run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  SAVIA_ALLOW_MAIN_COMMIT=true run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  [ "$(commits)" -eq 1 ]
}

@test "script escrito y ejecutado en la misma orden: bloqueado" {
  cambio a
  S="$BATS_TEST_TMPDIR/s.sh"
  run bash -c "printf 'cd \"%s\" && git commit -m desde-script\n' '$R' > '$S'; bash '$S'"
  [ "$status" -ne 0 ]
  [ "$(commits)" -eq 1 ]
}

@test "git invocado mediante un enlace con otro nombre: bloqueado" {
  cambio a
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$(command -v git)" "$BATS_TEST_TMPDIR/bin/herramienta"
  run "$BATS_TEST_TMPDIR/bin/herramienta" -C "$R" commit -m por-enlace
  [ "$status" -ne 0 ]
  [ "$(commits)" -eq 1 ]
}

@test "git -C hacia main desde otro directorio: bloqueado" {
  cambio a
  cd "$BATS_TEST_TMPDIR"
  run git -C "$R" commit -m x
  [ "$status" -ne 0 ]
  [ "$(commits)" -eq 1 ]
}

@test "worktree en agent/* con el repo principal en main: permitido; el principal sigue bloqueado" {
  W="$BATS_TEST_TMPDIR/wt"
  git -C "$R" worktree add -q "$W" -b agent/wt
  mkdir -p "$W/.githooks"; cp "$ROOT/.githooks/pre-commit" "$W/.githooks/"   # core.hooksPath relativo: raíz del worktree
  echo x > "$W/g.txt"; git -C "$W" add g.txt
  run git -C "$W" commit -m en-worktree
  [ "$status" -eq 0 ]
  cambio a
  run git -C "$R" commit -m en-main
  [ "$status" -ne 0 ]
}

# Instalación en repos sin core.hooksPath: scripts/install-git-hooks.sh --hooks-path
inst() { bash "$ROOT/scripts/install-git-hooks.sh" --hooks-path --repo "$@"; }

@test "instalador --hooks-path: activa el pre-commit en un repo sin core.hooksPath y bloquea main" {
  git -C "$R" config --unset core.hooksPath
  cambio a
  run git -C "$R" commit -m sin-hook
  [ "$status" -eq 0 ]
  run inst "$R"
  [ "$status" -eq 0 ]
  [ "$(git -C "$R" config --get core.hooksPath)" = ".githooks" ]
  cambio b
  run git -C "$R" commit -m con-hook
  [ "$status" -ne 0 ]
  run inst "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sin cambios"* ]]
}

@test "instalador --hooks-path: no pisa otro core.hooksPath ni acepta un no-repo" {
  git -C "$R" config core.hooksPath /otra/ruta
  run inst "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pisa"* ]]
  [ "$(git -C "$R" config --get core.hooksPath)" = "/otra/ruta" ]
  mkdir -p "$BATS_TEST_TMPDIR/norepo"
  run inst "$BATS_TEST_TMPDIR/norepo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es un repositorio git"* ]]
}
