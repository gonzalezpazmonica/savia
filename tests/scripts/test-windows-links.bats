#!/usr/bin/env bats
# tests/scripts/test-windows-links.bats — Comportamiento de scripts/windows-links.sh
# Repo git desechable con core.symlinks=false: los enlaces (modo 120000) se
# extraen como ficheros de texto y el script los materializa como junction o
# hard link. Los casos que crean enlaces solo corren en Windows (Git Bash);
# fuera de Windows se comprueba que el script es un no-op.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/windows-links.sh"

on_windows() { case "${OSTYPE:-}" in msys*|cygwin*) return 0 ;; *) return 1 ;; esac; }

# Registra en el índice un enlace rel -> target y lo extrae como textlink.
add_link() {
  local oid
  oid="$(printf '%s' "$2" | git -C "$REPO" hash-object -w --stdin)"
  git -C "$REPO" update-index --add --cacheinfo "120000,$oid,$1"
}

setup() {
  TMP="$(mktemp -d)"
  REPO="$TMP/repo"
  mkdir -p "$REPO/scripts" "$REPO/.claude/hooks" "$REPO/docs" "$REPO/.opencode"
  cp "$SCRIPT" "$REPO/scripts/windows-links.sh"
  printf 'echo hook\n' > "$REPO/.claude/hooks/h.sh"
  printf 'constitucion\n' > "$REPO/.claude/C.md"
  git -C "$REPO" init -q
  git -C "$REPO" config core.symlinks false
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name test
  git -C "$REPO" add -A
  add_link .opencode/hooks ../.claude/hooks
  add_link .opencode/C.md ../.claude/C.md
  git -C "$REPO" commit -qm fixture
  rm -rf "$REPO/.opencode/hooks" "$REPO/.opencode/C.md"
  git -C "$REPO" checkout -q -- .opencode
}

teardown() {
  # rmdir sobre una junction no toca su destino; rm -rf sí lo recorrería.
  if on_windows && [ -L "$REPO/.opencode/hooks" ]; then
    MSYS2_ARG_CONV_EXCL='*' cmd /c rmdir "$(cygpath -w "$REPO/.opencode/hooks")" >/dev/null 2>&1
  fi
  rm -rf "$TMP"
}

@test "fuera de Windows es un no-op con exit 0" {
  on_windows && skip "solo fuera de Windows"
  run bash "$REPO/scripts/windows-links.sh" repair
  [ "$status" -eq 0 ]
  [[ "$output" == *"no aplica"* ]]
  [ -f "$REPO/.opencode/hooks" ] || [ -L "$REPO/.opencode/hooks" ]
}

@test "argumento desconocido devuelve exit 2" {
  run bash "$REPO/scripts/windows-links.sh" borrar
  [ "$status" -eq 2 ]
}

@test "check detecta textlinks pendientes sin modificar nada" {
  on_windows || skip "requiere Windows"
  run bash "$REPO/scripts/windows-links.sh" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"PENDING  .opencode/hooks (textlink)"* ]]
  [[ "$output" == *"PENDING  .opencode/C.md (textlink)"* ]]
  [ -f "$REPO/.opencode/hooks" ] && [ ! -L "$REPO/.opencode/hooks" ]
}

@test "repair materializa directorio y fichero y deja git status limpio" {
  on_windows || skip "requiere Windows"
  run bash "$REPO/scripts/windows-links.sh" repair
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/.opencode/hooks/h.sh")" = "echo hook" ]
  [ "$REPO/.opencode/C.md" -ef "$REPO/.claude/C.md" ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
  git -C "$REPO" ls-files -v .opencode/hooks | grep -q '^S '
}

@test "repair es idempotente y check queda en verde" {
  on_windows || skip "requiere Windows"
  bash "$REPO/scripts/windows-links.sh" repair --quiet
  run bash "$REPO/scripts/windows-links.sh" repair
  [ "$status" -eq 0 ]
  [[ "$output" == *"repaired=0 pending=0 conflicts=0"* ]]
  run bash "$REPO/scripts/windows-links.sh" check --quiet
  [ "$status" -eq 0 ]
}

@test "junction que apunta a otro clon se reapunta al destino del repo" {
  on_windows || skip "requiere Windows"
  mkdir -p "$TMP/otro-clon/hooks"
  rm -f "$REPO/.opencode/hooks"
  MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(cygpath -w "$REPO/.opencode/hooks")" "$(cygpath -w "$TMP/otro-clon/hooks")" >/dev/null
  run bash "$REPO/scripts/windows-links.sh" check
  [[ "$output" == *"PENDING  .opencode/hooks (stale)"* ]]
  run bash "$REPO/scripts/windows-links.sh" repair
  [ "$status" -eq 0 ]
  [ -f "$REPO/.opencode/hooks/h.sh" ]
  [ -d "$TMP/otro-clon/hooks" ]
}

@test "destino que escapa del repositorio se rechaza sin crear enlace" {
  on_windows || skip "requiere Windows"
  mkdir -p "$TMP/fuera"
  add_link .opencode/escape ../../fuera
  git -C "$REPO" commit -qm escape
  git -C "$REPO" checkout -q -- .opencode/escape
  run bash "$REPO/scripts/windows-links.sh" repair
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT .opencode/escape: destino fuera del repositorio"* ]]
  [ ! -L "$REPO/.opencode/escape" ]
}

@test "fichero con contenido ajeno en la ruta del enlace no se sobrescribe" {
  on_windows || skip "requiere Windows"
  git -C "$REPO" update-index --skip-worktree -- .opencode/C.md
  printf 'notas locales\n' > "$REPO/.opencode/C.md"
  run bash "$REPO/scripts/windows-links.sh" repair
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT .opencode/C.md"* ]]
  [ "$(cat "$REPO/.opencode/C.md")" = "notas locales" ]
}
