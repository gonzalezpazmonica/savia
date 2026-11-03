#!/usr/bin/env bats
# Guards de rama: miran la rama del repo DESTINO de cada git commit/add real
# (git -C, cd encadenado, variables literales), no la del checkout de la sesión.
# Hooks: .claude/hooks/block-commit-to-main.sh y validate-bash-global.sh.
# Resolvedor compartido: scripts/lib/git_op_targets.py (también lo usa el port
# TS .opencode/plugins/guards/block-commit-to-main.ts, con los mismos casos).
# HOOKS_ROOT permite ejecutar los casos contra otra copia del árbol de hooks.

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
  R="${HOOKS_ROOT:-$PWD}"
  BCM="$R/.claude/hooks/block-commit-to-main.sh"
  VBG="$R/.claude/hooks/validate-bash-global.sh"
  export SAVIA_TURN_SDLC_LOG_DIR="$TMPDIR/bcm-log"
  export SAVIA_HOOK_PROFILE="standard"
  unset SAVIA_ALLOW_MAIN_COMMIT
  T="$(cd "$TMPDIR" && pwd -P)/gt"
  export HOME="$T/home"
  MAIN="$HOME/savia"          # repo "savia" en main (checkout de la sesión)
  WT="$HOME/wt-x"             # worktree agent/x del mismo repo
  mkdir -p "$MAIN"
  git init -q -b main "$MAIN"
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$MAIN" worktree add -q -b agent/x "$WT"
  export CLAUDE_PROJECT_DIR="$MAIN"
}

teardown() { cd /; }

# Ejecuta block-commit-to-main con la sesión en main. Salida = JSON si bloquea.
bcm() {  # $1 = orden, $2 = cwd de la orden (por defecto: main)
  jq -n --arg c "$1" --arg d "${2:-$MAIN}" '{tool_input:{command:$c},cwd:$d}' \
    | (cd "${2:-$MAIN}" && bash "$BCM")
}
# Ejecuta validate-bash-global con la sesión en $2 (por defecto: main). exit 2 = bloqueo.
vbg() {
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | (cd "${2:-$MAIN}" && bash "$VBG")
}
blocked_bcm() { [ "$(echo "$output" | jq -r .decision 2>/dev/null)" = "block" ]; }

# ── Casos reales que fallaron (sesión en main) ──────────────────────────────

@test "bcm caso 1: W=<worktree>; git -C \$W add && git -C \$W commit pasa" {
  run bcm "W=$WT; git -C \$W add f && git -C \$W commit -q --no-edit"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "vbg caso 1: W=<worktree>; git -C \$W add && git -C \$W commit pasa" {
  run vbg "W=$WT; git -C \$W add f && git -C \$W commit -q --no-edit"
  [ "$status" -eq 0 ]
}

@test "bcm caso 2: cd ~/wt sin comillas && git merge ; git commit pasa" {
  run bcm 'cd ~/wt-x && git merge origin/main ; git commit -m y'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "vbg caso 2: cd ~/wt sin comillas && git merge ; git commit pasa" {
  run vbg 'cd ~/wt-x && git merge origin/main ; git commit -m y'
  [ "$status" -eq 0 ]
}

@test "bcm caso 3: heredoc cuyo texto dice git commit/commitear no bloquea" {
  run bcm $'cat > notas.md <<\'EOF\'\nhay que commitear; git commit -m x\nlos commits\nEOF'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "vbg caso 3: heredoc cuyo texto dice git commit/git add no bloquea" {
  run vbg $'cat > notas.md <<\'EOF\'\nhay que commitear; git commit -m x\ngit add .\nEOF'
  [ "$status" -eq 0 ]
}

@test "bcm y vbg: comillas raras en el cd al worktree pasan" {
  run bcm "cd \"$HOME\"/'wt-x' && git commit -m x"
  [ -z "$output" ]
  run vbg "cd \"$HOME\"/'wt-x' && git commit -m x"
  [ "$status" -eq 0 ]
}

# ── Rodeos: el destino es main, por cualquier forma ─────────────────────────

@test "bcm: git commit en main sigue bloqueado" {
  run bcm 'git commit -m x'
  blocked_bcm
}

@test "vbg: git commit en main sigue bloqueado" {
  run vbg 'git commit -m x'
  [ "$status" -eq 2 ]
}

@test "bcm: git -C hacia main desde el worktree bloquea (con y sin comillas)" {
  run bcm "git -C $MAIN commit -m x" "$WT"
  blocked_bcm
  run bcm "git -C \"$MAIN\" commit -m x" "$WT"
  blocked_bcm
}

@test "vbg: git -C hacia main desde el worktree bloquea" {
  run vbg "git -C $MAIN commit -m x" "$WT"
  [ "$status" -eq 2 ]
  run vbg "git -C '$MAIN' add f" "$WT"
  [ "$status" -eq 2 ]
}

@test "bcm y vbg: cd a main tras un cd al worktree bloquea" {
  run bcm "cd $WT && git add . ; cd $MAIN && git commit -m z" "$WT"
  blocked_bcm
  run vbg "cd $WT && git add . ; cd $MAIN && git commit -m z" "$WT"
  [ "$status" -eq 2 ]
}

@test "bcm y vbg: cd condicional al worktree no salva el commit en main" {
  run bcm "false && cd $WT; git commit -m x"
  blocked_bcm
  run vbg "false && cd $WT; git commit -m x"
  [ "$status" -eq 2 ]
}

@test "bcm y vbg: cd en subshell o tubería no salva el commit en main" {
  run bcm "(cd $WT); git commit -m x"
  blocked_bcm
  run vbg "cd $WT | true; git commit -m x"
  [ "$status" -eq 2 ]
}

@test "bcm y vbg: variable no resoluble es conservadora (cwd en main)" {
  run bcm 'git -C $DESCONOCIDA commit -m x'
  blocked_bcm
  run vbg 'git -C $DESCONOCIDA commit -m x'
  [ "$status" -eq 2 ]
}

@test "bcm y vbg: git commit tras un heredoc sí cuenta" {
  run bcm $'cat > f <<EOF\ntexto\nEOF\ngit commit -m x'
  blocked_bcm
  run vbg $'cat > f <<EOF\ntexto\nEOF\ngit commit -m x'
  [ "$status" -eq 2 ]
}

@test "bcm y vbg: bash -c con cd a main desde el worktree bloquea" {
  run bcm "bash -c 'cd $MAIN && git commit -m x'" "$WT"
  blocked_bcm
  run vbg "bash -c 'cd $MAIN && git commit -m x'" "$WT"
  [ "$status" -eq 2 ]
}
