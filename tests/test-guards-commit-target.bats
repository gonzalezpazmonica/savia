#!/usr/bin/env bats
# Guards de rama: miran la rama del repo DESTINO de cada git commit/add real
# (git -C, cd encadenado, variables literales), no la del checkout de la sesión.
# El resolvedor es fail-closed: ante una forma que no entiende con certeza emite
# la op con destino vacío (veredicto BLOQUEAR). Los hooks bash bloquean ese
# destino vacío sin mirar la rama del cwd, y también si falta el resolvedor.
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
# Veredicto del resolvedor (sin hook): `commit\t` con destino vacío = BLOQUEAR.
verdict() {  # $1 = orden, $2 = cwd
  printf '%s' "$1" | python3 "$BATS_TEST_DIRNAME/../scripts/lib/git_op_targets.py" "${2:-$MAIN}"
}
blocked_verdict() { grep -qxP "${1:-commit}\t" <<< "$output"; }
blocked_bcm() { [ "$(echo "$output" | jq -r .decision 2>/dev/null)" = "block" ]; }
# exit 2 por ESTE guard (no por entrada malformada ni por otro guard).
blocked_vbg() { [ "$status" -eq 2 ] && [[ "$output" == *"BLOQUEADO: rama 'main'"* || "$output" == *"fail-closed"* ]]; }
blocked_unsure_bcm() { [[ "$(echo "$output" | jq -r .reason 2>/dev/null)" == *"git -C <ruta> commit"* ]]; }
blocked_unsure_vbg() { [ "$status" -eq 2 ] && [[ "$output" == *"fail-closed"*"git -C <ruta>"* ]]; }
# PATH sin python3: el resolvedor no está disponible.
no_python_path() {
  local d="$TMPDIR/nopy-bin" f
  mkdir -p "$d"
  local IFS=: dir
  # todo el PATH (no solo /usr/bin): jq, git o timeout pueden vivir en otro sitio
  for dir in $PATH; do
    for f in "$dir"/*; do
      [ -x "$f" ] || continue
      case "$(basename "$f")" in python3*|python) continue ;; esac
      [ -e "$d/$(basename "$f")" ] || ln -s "$f" "$d/$(basename "$f")" 2>/dev/null || true
    done
  done
  [ ! -e "$d/python3" ] || return 1
  echo "$d"
}

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
  blocked_vbg
}

@test "bcm: git -C hacia main desde el worktree bloquea (con y sin comillas)" {
  run bcm "git -C $MAIN commit -m x" "$WT"
  blocked_bcm
  run bcm "git -C \"$MAIN\" commit -m x" "$WT"
  blocked_bcm
}

@test "vbg: git -C hacia main desde el worktree bloquea" {
  run vbg "git -C $MAIN commit -m x" "$WT"
  blocked_vbg
  run vbg "git -C '$MAIN' add f" "$WT"
  blocked_vbg
}

@test "bcm y vbg: cd a main tras un cd al worktree bloquea" {
  run bcm "cd $WT && git add . ; cd $MAIN && git commit -m z" "$WT"
  blocked_bcm
  run vbg "cd $WT && git add . ; cd $MAIN && git commit -m z" "$WT"
  blocked_vbg
}

@test "bcm y vbg: cd condicional al worktree no salva el commit en main" {
  run bcm "false && cd $WT; git commit -m x"
  blocked_bcm
  run vbg "false && cd $WT; git commit -m x"
  blocked_vbg
}

@test "bcm y vbg: cd en subshell o tubería no salva el commit en main" {
  run bcm "(cd $WT); git commit -m x"
  blocked_bcm
  run vbg "cd $WT | true; git commit -m x"
  blocked_vbg
}

@test "bcm y vbg: variable no resoluble es conservadora (cwd en main)" {
  run bcm 'git -C $DESCONOCIDA commit -m x'
  blocked_bcm
  run vbg 'git -C $DESCONOCIDA commit -m x'
  blocked_vbg
}

@test "bcm y vbg: git commit tras un heredoc sí cuenta" {
  run bcm $'cat > f <<EOF\ntexto\nEOF\ngit commit -m x'
  blocked_bcm
  run vbg $'cat > f <<EOF\ntexto\nEOF\ngit commit -m x'
  blocked_vbg
}

@test "bash -c con git commit: veredicto BLOQUEAR también desde el worktree" {
  run verdict "bash -c 'cd $MAIN && git commit -m x'" "$WT"
  blocked_verdict
  run bcm "bash -c 'cd $WT && git commit -m x'"
  blocked_bcm
  run vbg "bash -c 'cd $WT && git commit -m x'"
  blocked_vbg
}

# ── Fail-closed: formas que el resolvedor no reconoce (revisión PR #1467) ───

@test "bcm y vbg: orden no resoluble delante de git commit bloquea en main" {
  for c in '$SUDO git commit -m x' '${X:-} git add . && ${X:-} git commit -m x'; do
    run bcm "$c"
    blocked_bcm
    run vbg "$c"
    blocked_vbg
  done
  # desde el worktree: el resolvedor no da destino, veredicto BLOQUEAR
  for c in "\$(which git) -C $MAIN commit -m x" "\$SUDO git -C $MAIN commit -m x"; do
    run verdict "$c" "$WT"
    blocked_verdict
  done
}

@test "bcm y vbg: bash con opciones -c git commit bloquea en main" {
  for c in 'bash --norc -c "git commit -m x"' 'bash -o pipefail -c "git commit -m x"'; do
    run bcm "$c"
    blocked_bcm
    run vbg "$c"
    blocked_vbg
  done
}

@test "bcm y vbg: awk/script/python que ejecutan git commit bloquean en main" {
  for c in "awk 'BEGIN{system(\"git commit -m x\")}'" 'script -qc "git commit -m x" /dev/null' \
           "python3 -c \"import os; os.system('git commit -m x')\""; do
    run bcm "$c"
    blocked_bcm
    run vbg "$c"
    blocked_vbg
  done
}

@test "bcm y vbg: heredoc sin comillas con \$(git commit) bloquea; con comillas no" {
  run bcm $'cat <<EOF\n$(git commit -m x)\nEOF'
  blocked_bcm
  run vbg $'cat <<EOF\n$(git commit -m x)\nEOF'
  blocked_vbg
  run bcm $'cat <<\'EOF\'\n$(git commit -m x)\nEOF'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run vbg $'cat <<\'EOF\'\n$(git add .)\nEOF'
  [ "$status" -eq 0 ]
}

@test "veredicto BLOQUEAR no depende de la rama del cwd (worktree agent/*)" {
  run verdict 'bash --norc -c "git commit -m x"' "$WT"
  blocked_verdict
  [ "$(echo "$output" | grep -c .)" -eq 1 ]
}

@test "vbg y bcm sin python3: fail-closed, bloquean git commit desde cualquier rama" {
  P=$(no_python_path)
  run env PATH="$P" bash -c "jq -n --arg c 'git -C $MAIN commit -m x' '{tool_input:{command:\$c}}' | (cd '$WT' && bash '$VBG')"
  blocked_unsure_vbg
  run env PATH="$P" bash -c "jq -n --arg c 'git -C $WT commit -m x' --arg d '$WT' '{tool_input:{command:\$c},cwd:\$d}' | (cd '$WT' && bash '$BCM')"
  blocked_unsure_bcm
  run env PATH="$P" bash -c "jq -n --arg c 'git -C $WT commit -m x' '{tool_input:{command:\$c}}' | (cd '$MAIN' && bash '$VBG')"
  blocked_vbg
}

# ── Shell que lee la orden de stdin y cd que el hook no ve (revisión 2) ─────

@test "bcm y vbg: bash/sh que leen git commit de heredoc, here-string o tubería bloquean en main" {
  for c in $'bash <<\'EOF\'\ngit commit -m x\nEOF' $'sh <<EOF\ngit commit -m x\nEOF' \
           "bash <<< 'git commit -m x'" "echo 'git commit -m x' | bash" \
           "printf 'git add .' | sh -s"; do
    run bcm "$c"
    if [[ "$c" == *"git add"* ]]; then [ -z "$output" ]; else blocked_bcm; fi
    run vbg "$c"
    blocked_vbg
  done
}

@test "bcm y vbg: heredoc a bash con git commit bloquea aunque haga cd al worktree" {
  run bcm $'bash <<\'EOF\'\ncd '"$WT"$' && git commit -m x\nEOF'
  blocked_bcm
  run vbg $'bash <<\'EOF\'\ncd '"$WT"$' && git commit -m x\nEOF'
  blocked_vbg
  run verdict $'bash <<\'EOF\'\ncd '"$MAIN"$' && git commit -m x\nEOF' "$WT"
  blocked_verdict
}

@test "bcm y vbg: cd a un directorio inexistente no apaga el guard en main" {
  run bcm "cd \"$HOME/no-existe\" && git commit -m x"
  blocked_bcm
  run vbg "cd \"$HOME/no-existe\" && git commit -m x"
  blocked_vbg
}

@test "bcm y vbg: CDPATH no apaga el guard en main" {
  run bcm "CDPATH=$HOME; cd savia-otro && git commit -m x"
  blocked_bcm
  run vbg "CDPATH=$HOME; cd savia-otro && git commit -m x"
  blocked_vbg
}

@test "GIT_DIR y --git-dir: veredicto BLOQUEAR; git -C al worktree pasa" {
  run verdict "GIT_DIR=$MAIN/.git git commit -m x" "$WT"
  blocked_verdict
  run verdict "git --git-dir=$MAIN/.git commit -m x" "$WT"
  blocked_verdict
  run bcm "GIT_DIR=$WT/.git git commit -m x"
  blocked_bcm
  run bcm "git -C $WT commit -m x" "$WT"
  [ -z "$output" ]
}

@test "bcm y vbg: git commit-tree en main bloquea" {
  run bcm "git commit-tree HEAD^{tree} -m x"
  blocked_bcm
  run vbg "git commit-tree HEAD^{tree} -m x"
  blocked_vbg
}

# ── Fail-closed por defecto (decisión 2026-11-03): un test por P1 ───────────

@test "bcm y vbg: P1 de las revisiones de seguridad bloquean con la sesión en main" {
  for c in 'git $(echo commit) -m x' 'g(){ git "$@"; }; g commit -m x' \
           'env -S "git commit -m x"' "bash -c -- 'git commit -m x'" \
           "sed -n '1e git commit -m x' f" 'su -c "git commit -m x"' \
           "flock f -c \"git -C $WT commit -m x\"" "eval 'git -C $WT commit -m x'" \
           "echo . | xargs git -C $WT commit -m x" "sudo git -C $WT commit -m x"; do
    run bcm "$c"
    blocked_bcm
    run vbg "$c"
    blocked_vbg
  done
}

@test "veredicto BLOQUEAR desde el worktree para cada P1 (sin destino cierto)" {
  for c in 'git $(echo commit) -m x' 'g(){ git "$@"; }; g commit -m x' \
           'env -S "git commit -m x"' "bash -c -- 'git commit -m x'" \
           '$SUDO git commit -m x' 'bash --norc -c "git commit -m x"' \
           "awk 'BEGIN{system(\"git commit -m x\")}'" $'cat <<EOF\n$(git commit -m x)\nEOF' \
           "echo 'git commit -m x' | bash" "bash <<< 'git commit -m x'" \
           "CDPATH=$HOME; cd savia && git commit -m x"; do
    run verdict "$c" "$WT"
    blocked_verdict
  done
}

@test "texto que solo menciona git commit sigue sin bloquear en main" {
  for c in 'echo "luego git commit"' 'grep -r "git commit" docs' "git log --grep commit" \
           $'cat > n.md <<\'EOF\'\ngit commit -m x\nEOF'; do
    run bcm "$c"
    [ -z "$output" ]
    run vbg "$c"
    [ "$status" -eq 0 ]
  done
}

@test "forma admitida: git -C <worktree> commit con mensaje por heredoc pasa en main" {
  c="git -C $WT add -A && git -C $WT commit -m \"\$(cat <<'EOF'
fix(x): uno) dos, git add mencionado
EOF
)\""
  run bcm "$c"
  [ -z "$output" ]
  run vbg "$c"
  [ "$status" -eq 0 ]
}

# ── Hooks fail-closed: destino vacío bloquea también desde el worktree ──────

@test "bcm y vbg: forma no reconocida bloquea desde el worktree agent/*" {
  for c in 'git $(echo commit) -m x' 'g(){ git "$@"; }; g commit -m x' \
           'env -S "git commit -m x"' "bash -c -- 'git commit -m x'" \
           '$SUDO git commit -m x' "bash -c 'cd $MAIN && git commit -m x'" \
           "echo 'git commit -m x' | bash" "GIT_DIR=$MAIN/.git git commit -m x" \
           "CDPATH=$HOME; cd savia && git commit -m x"; do
    run bcm "$c" "$WT"
    blocked_unsure_bcm
    run vbg "$c" "$WT"
    blocked_unsure_vbg
  done
}

# Resto de P1 de las tres revisiones de seguridad, también desde el worktree
# (con los hooks anteriores pasaban: el destino vacío se evaluaba por agent/x).
@test "bcm y vbg: el resto de P1 de las revisiones bloquea desde el worktree agent/*" {
  for c in "\${X:-} git commit -m x" 'bash --norc -c "git commit -m x"' \
           'bash -o pipefail -c "git commit -m x"' "awk 'BEGIN{system(\"git commit -m x\")}'" \
           "sed 'e git commit -m x' /dev/null" 'script -qc "git commit -m x" /dev/null' \
           'su -c "git commit -m x"' 'flock f -c "git commit -m x"' \
           "python3 -c \"import os; os.system('git commit -m x')\"" \
           $'cat <<EOF\n$(git commit -m x)\nEOF' $'bash <<\'EOF\'\ngit commit -m x\nEOF' \
           $'sh <<EOF\ngit commit -m x\nEOF' "bash <<< 'git commit -m x'" \
           "printf 'git commit -m x' | sh -s" 'cd /no/existe && git commit -m x'; do
    run bcm "$c" "$WT"
    blocked_unsure_bcm
    run vbg "$c" "$WT"
    blocked_unsure_vbg
  done
  # git add: solo lo guarda vbg (bcm protege commits)
  run vbg '${X:-} git add .' "$WT"
  blocked_unsure_vbg
}

@test "bcm y vbg: formas admitidas al worktree siguen pasando desde el worktree" {
  for c in "git -C $WT commit -m x" "cd $WT && git commit -m x" 'git commit -m x' \
           'echo "git commit"'; do
    run bcm "$c" "$WT"
    [ -z "$output" ]
    run vbg "$c" "$WT"
    [ "$status" -eq 0 ]
  done
}

# ── revisión 4 (#1467): prefiltro sobre el texto sin comillas ni barras y
# alias de git (P1 de corrección y de seguridad) ────────────────────────────
@test "bcm y vbg: comillas partidas o barras en git/commit no saltan el guard en main" {
  for c in "bash -c 'gi''t com''mit -m x'" "git co''mmit -m x" 'g\it commit -m x' \
           'gi""t commit -m x' 'git com\mit -m x'; do
    run bcm "$c"
    blocked_bcm
    run vbg "$c"
    blocked_vbg
  done
}

@test "bcm y vbg: comillas partidas desde el worktree: bash -c es incierto; git directo pasa" {
  run bcm "bash -c 'gi''t com''mit -m x'" "$WT"
  blocked_unsure_bcm
  run vbg "bash -c 'gi''t com''mit -m x'" "$WT"
  blocked_unsure_vbg
  run bcm "git co''mmit -m x" "$WT"
  [ -z "$output" ]
  run vbg "git co''mmit -m x" "$WT"
  [ "$status" -eq 0 ]
}

@test "bcm y vbg: alias de git que hace commit bloquea en main; alias seguro y worktree pasan" {
  git -C "$MAIN" config alias.ci commit
  git -C "$MAIN" config alias.st 'status -sb'
  run bcm 'git ci -m x'
  [[ "$(echo "$output" | jq -r .reason)" == *"rama humana (main)"* ]]
  run vbg 'git ci -m x'
  [ "$status" -eq 2 ] && [[ "$output" == *"BLOQUEADO: rama 'main'"* ]]
  run bcm 'git ci -m x' "$WT"
  [ -z "$output" ]
  run vbg 'git ci -m x' "$WT"
  [ "$status" -eq 0 ]
  run bcm 'git st'
  [ -z "$output" ]
  run vbg 'git st'
  [ "$status" -eq 0 ]
}

@test "bcm: bypass de la operadora vale también ante destino incierto (queda registrado)" {
  run bcm 'env -S "git commit -m x"' "$WT"
  blocked_unsure_bcm
  SAVIA_ALLOW_MAIN_COMMIT=1 run bcm 'env -S "git commit -m x"' "$WT"
  [ -z "$output" ]
  grep -q '"verdict":"bypass"' "$SAVIA_TURN_SDLC_LOG_DIR/commit-guard.jsonl"
}

@test "bcm y vbg sin python3: git status no se bloquea; git commit sí" {
  P=$(no_python_path)
  run env PATH="$P" bash -c "jq -n --arg c 'git status' --arg d '$WT' '{tool_input:{command:\$c},cwd:\$d}' | (cd '$WT' && bash '$BCM')"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run env PATH="$P" bash -c "jq -n --arg c 'git status' '{tool_input:{command:\$c}}' | (cd '$WT' && bash '$VBG')"
  [ "$status" -eq 0 ]
  run env PATH="$P" bash -c "jq -n --arg c 'git -C $WT commit -m x' '{tool_input:{command:\$c}}' | (cd '$WT' && bash '$VBG')"
  blocked_unsure_vbg
}
