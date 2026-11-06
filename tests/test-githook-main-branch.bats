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

# ── S03o: modo clásico de scripts/install-git-hooks.sh (.git/hooks) y errores de --hooks-path ──
# Ref: docs/rules/domain/autonomous-safety.md
SCRIPT="scripts/install-git-hooks.sh"

# legacy_repo <dir>: repo temporal con una copia del instalador en scripts/.
legacy_repo() {
  git init -q -b agent/x "$1"
  mkdir -p "$1/scripts"
  cp "$ROOT/$SCRIPT" "$1/scripts/"
}

@test "instalador: declara set -uo pipefail" {
  head -3 "$ROOT/$SCRIPT" | grep -q "set -uo pipefail"
}

@test "instalador clásico: instala pre-commit, pre-push y commit-msg en el .git/hooks del propio repo" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"
  run bash "$L/scripts/install-git-hooks.sh"
  [ "$status" -eq 0 ]
  for h in pre-commit pre-push commit-msg; do
    [ -x "$L/.git/hooks/$h" ]
    head -2 "$L/.git/hooks/$h" | grep -q "set -uo pipefail"
  done
  grep -q 'pre-commit-review.sh' "$L/.git/hooks/pre-commit"
  grep -q 'run-hook.sh" block-force-push Bash' "$L/.git/hooks/pre-push"
  grep -q 'run-hook.sh" prompt-hook-commit Edit' "$L/.git/hooks/commit-msg"
  [[ "$output" == *"Hooks de Git instalados correctamente"* ]]
  [[ "$output" == *"$L/.git/hooks/pre-commit"* ]]
}

@test "instalador clásico (install_hook): respalda un hook previo con su contenido" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"
  printf '#!/bin/sh\necho previo\n' > "$L/.git/hooks/pre-push"
  run bash "$L/scripts/install-git-hooks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hook pre-push existente respaldado"* ]]
  local bak; bak=$(ls "$L/.git/hooks/" | grep '^pre-push\.backup\.' | head -1)
  [ -n "$bak" ]
  grep -q 'echo previo' "$L/.git/hooks/$bak"
  grep -q 'block-force-push' "$L/.git/hooks/pre-push"
}

@test "instalador clásico en un worktree: instala en el directorio común, no falla por .git fichero" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m base
  W="$BATS_TEST_TMPDIR/legacy-wt"
  git -C "$L" worktree add -q "$W" -b agent/wt2
  [ -f "$W/.git" ]
  run bash "$W/scripts/install-git-hooks.sh"
  [ "$status" -eq 0 ]
  [ -x "$L/.git/hooks/commit-msg" ]
}

@test "instalador clásico con core.hooksPath activo: error y no toca .githooks ni .git/hooks" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"
  mkdir -p "$L/.githooks"; echo original > "$L/.githooks/pre-commit"
  git -C "$L" config core.hooksPath .githooks
  run bash "$L/scripts/install-git-hooks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git no ejecutaría .git/hooks"* ]]
  [ "$(cat "$L/.githooks/pre-commit")" = "original" ]
  [ ! -e "$L/.git/hooks/pre-push" ]
}

@test "instalador clásico fuera de un repo: error (invalid), sin escribir hooks" {
  N="$BATS_TEST_TMPDIR/nogit"; mkdir -p "$N/scripts"; cp "$ROOT/$SCRIPT" "$N/scripts/"
  run env GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" bash "$N/scripts/install-git-hooks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es un repositorio git"* ]]
  [ ! -e "$N/.git" ]
}

@test "instalador --hooks-path: repo sin .githooks/pre-commit da error (missing)" {
  E="$BATS_TEST_TMPDIR/empty"; git init -q "$E"
  run bash "$ROOT/$SCRIPT" --hooks-path --repo "$E"
  [ "$status" -eq 1 ]
  [[ "$output" == *".githooks/pre-commit no existe"* ]]
  [ -z "$(git -C "$E" config --get core.hooksPath)" ]
}

@test "instalador --hooks-path: --repo sin directorio da error (no arg)" {
  run bash "$ROOT/$SCRIPT" --hooks-path --repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"--repo necesita un directorio"* ]]
}

@test "instalador --hooks-path sin --repo usa el directorio actual (subdirectorio incluido)" {
  git -C "$R" config --unset core.hooksPath
  mkdir -p "$R/sub"
  cd "$R/sub"
  run bash "$ROOT/$SCRIPT" --hooks-path
  [ "$status" -eq 0 ]
  [ "$(git -C "$R" config --get core.hooksPath)" = ".githooks" ]
  [[ "$output" == *"core.hooksPath = .githooks en $R"* ]]
}

@test "instalador clásico: repo sin directorio de hooks (plantilla vacía) da error y no lo crea" {
  L="$BATS_TEST_TMPDIR/nohooks"; mkdir -p "$BATS_TEST_TMPDIR/tpl-vacia"
  git init -q --template="$BATS_TEST_TMPDIR/tpl-vacia" "$L"
  mkdir -p "$L/scripts"; cp "$ROOT/$SCRIPT" "$L/scripts/"
  [ ! -d "$L/.git/hooks" ]
  run bash "$L/scripts/install-git-hooks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No se encuentra .git/hooks"* ]]
  [ ! -d "$L/.git/hooks" ]
}

# stubs <repo>: dobles de las revisiones que llaman los hooks generados; registran sus argumentos.
stubs() {
  mkdir -p "$1/.claude/hooks" "$1/.opencode/scripts/opencode-hooks"
  for s in pre-commit-review stop-quality-gate; do
    printf '#!/bin/bash\necho "%s $(cat | wc -c)" >> "%s/llamadas"\n' "$s" "$BATS_TEST_TMPDIR" > "$1/.claude/hooks/$s.sh"
    chmod +x "$1/.claude/hooks/$s.sh"
  done
  printf '#!/bin/bash\necho "run-hook $*" >> "%s/llamadas"\nexit "${STUB_RC:-0}"\n' "$BATS_TEST_TMPDIR" \
    > "$1/.opencode/scripts/opencode-hooks/run-hook.sh"
  chmod +x "$1/.opencode/scripts/opencode-hooks/run-hook.sh"
}

@test "hooks generados: pre-commit ejecuta las dos revisiones con stdin vacío" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"; stubs "$L"
  run bash "$L/scripts/install-git-hooks.sh"
  [ "$status" -eq 0 ]
  cd "$L"
  run "$L/.git/hooks/pre-commit"
  [ "$status" -eq 0 ]
  grep -qx "pre-commit-review 0" "$BATS_TEST_TMPDIR/llamadas"
  grep -qx "stop-quality-gate 0" "$BATS_TEST_TMPDIR/llamadas"
}

@test "hooks generados: pre-push pasa el remoto a block-force-push y bloquea si el hook falla" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"; stubs "$L"
  bash "$L/scripts/install-git-hooks.sh" >/dev/null
  cd "$L"
  run "$L/.git/hooks/pre-push" origin file:///x
  [ "$status" -eq 0 ]
  grep -qx "run-hook block-force-push Bash git push origin" "$BATS_TEST_TMPDIR/llamadas"
  STUB_RC=2 run "$L/.git/hooks/pre-push" origin file:///x
  [ "$status" -eq 1 ]
}

@test "hooks generados: commit-msg pasa el fichero del mensaje y bloquea si el hook falla" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"; stubs "$L"
  bash "$L/scripts/install-git-hooks.sh" >/dev/null
  cd "$L"
  run "$L/.git/hooks/commit-msg" .git/COMMIT_EDITMSG
  [ "$status" -eq 0 ]
  grep -qx "run-hook prompt-hook-commit Edit .git/COMMIT_EDITMSG" "$BATS_TEST_TMPDIR/llamadas"
  STUB_RC=2 run "$L/.git/hooks/commit-msg" .git/COMMIT_EDITMSG
  [ "$status" -eq 1 ]
}

@test "hooks generados: sin run-hook.sh, pre-push avisa y no bloquea (skip documentado)" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"
  bash "$L/scripts/install-git-hooks.sh" >/dev/null
  cd "$L"
  run "$L/.git/hooks/pre-push" origin file:///x
  [ "$status" -eq 0 ]
  [[ "$output" == *"run‑hook.sh no encontrado"* ]]
}

@test "hooks generados: lanzados desde un subdirectorio localizan la raíz del repo" {
  L="$BATS_TEST_TMPDIR/legacy"; legacy_repo "$L"; stubs "$L"
  bash "$L/scripts/install-git-hooks.sh" >/dev/null
  mkdir -p "$L/sub/dir"; cd "$L/sub/dir"
  run "$L/.git/hooks/pre-push" origin file:///x
  [ "$status" -eq 0 ]
  run "$L/.git/hooks/commit-msg" msg.txt
  [ "$status" -eq 0 ]
  grep -qx "run-hook block-force-push Bash git push origin" "$BATS_TEST_TMPDIR/llamadas"
  grep -qx "run-hook prompt-hook-commit Edit msg.txt" "$BATS_TEST_TMPDIR/llamadas"
}
