#!/usr/bin/env bats
# Regresión: validate-ci-local y los tests que crean repos temporales no deben heredar
# GIT_DIR/GIT_WORK_TREE del agente (crearon commits "init" y core.worktree en el repo real).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  DECOY="$TMP/decoy"
  git init -q -b main "$DECOY"
  git -C "$DECOY" -c user.email=a@a -c user.name=a commit -q --allow-empty -m base
  BEFORE_HEAD="$(git -C "$DECOY" rev-parse HEAD)"
  BEFORE_CFG="$(cat "$DECOY/.git/config")"
}

teardown() { rm -rf "$TMP"; }

assert_decoy_intact() {
  [ "$(git -C "$DECOY" rev-parse HEAD)" = "$BEFORE_HEAD" ]
  [ "$(git -C "$DECOY" rev-list --count HEAD)" = "1" ]
  [ "$(cat "$DECOY/.git/config")" = "$BEFORE_CFG" ]
  run git config --file "$DECOY/.git/config" --get core.worktree
  [ -z "$output" ]
}

@test "guardrail-negative-tests no toca el repo de GIT_DIR/GIT_WORK_TREE" {
  env GIT_DIR="$DECOY/.git" GIT_WORK_TREE="$DECOY" GIT_INDEX_FILE="$DECOY/.git/index" \
    bash "$ROOT/scripts/guardrail-negative-tests.sh" >/dev/null 2>&1 || true
  assert_decoy_intact
}

@test "git_env_clean elimina las variables de repositorio y config" {
  run env GIT_DIR=/x GIT_WORK_TREE=/y GIT_INDEX_FILE=/z GIT_COMMON_DIR=/w GIT_CONFIG_COUNT=1 \
    bash -c 'source "$1/scripts/lib/mock-env.sh"; git_env_clean --isolate-config; env | grep -E "^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|CONFIG_COUNT)="; echo "G=$GIT_CONFIG_GLOBAL"' _ "$ROOT"
  [ "$output" = "G=/dev/null" ]
}

@test "validate-ci-local limpia GIT_DIR al arrancar" {
  grep -q 'git_env_clean' "$ROOT/scripts/validate-ci-local.sh"
  git init -q -b main "$TMP/small"
  git -C "$TMP/small" -c user.email=a@a -c user.name=a commit -q --allow-empty -m base
  run env GIT_DIR="$DECOY/.git" GIT_WORK_TREE="$DECOY" \
    bash "$ROOT/scripts/validate-ci-local.sh" --clean-state-only --repo "$TMP/small"
  assert_decoy_intact
}

# ── S03k: comportamiento de validate-ci-local.sh sobre un repo sintético ──
# Se copia el script a un repo falso (cwd = repo) con stubs de coherence-gates
# y gate-result, para observar cada comprobación sin tocar el repo real.

mk_repo() { # mk_repo [rama]
  FX="$TMP/fx"
  mkdir -p "$FX/scripts/lib" "$FX/.claude/hooks/lib" "$FX/.opencode/commands" "$FX/.claude" "$FX/docs"
  cp "$ROOT/scripts/validate-ci-local.sh" "$FX/scripts/"
  cp "$ROOT/scripts/lib/mock-env.sh" "$ROOT/scripts/lib/planning-completion.sh" "$FX/scripts/lib/"
  printf '#!/usr/bin/env bash\necho ok\n' > "$FX/scripts/coherence-gates.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/.claude/hooks/lib/gate-result.sh"
  for f in LICENSE README.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md; do echo x > "$FX/$f"; done
  printf '# Changelog\n## [1.1.0]\n## [1.0.0]\n' > "$FX/CHANGELOG.md"
  echo '{}' > "$FX/.claude/settings.json"
  git init -q -b main "$FX"
  git -C "$FX" add -A
  git -C "$FX" -c user.email=a@a -c user.name=a commit -q -m base
  if [[ "${1:-feature/x}" != main ]]; then
    git -C "$FX" branch "${1:-feature/x}"
    git -C "$FX" symbolic-ref HEAD "refs/heads/${1:-feature/x}"
  fi
  V="$FX/scripts/validate-ci-local.sh"
}

ci() { # ci [args] — ejecuta en el repo falso sin comprobaciones de frescura
  (cd "$FX" && SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_LOCK_DIRS_FOR_TESTS=' ' SAVIA_AUTHORITY_REPORT=off bash "$V" "$@")
}

@test "S03k ci: repo sano termina en exit 0 con 'safe to push'" {
  mk_repo
  run ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"safe to push"* ]]
  [[ "$output" == *"0 failed"* ]]
}

@test "S03k ci: estar en main falla con exit 1 y lo nombra" {
  mk_repo main
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL Branch: on main"* ]] || [[ "$output" == *"Branch: on main"* ]]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "S03k ci: master también cuenta como rama protegida" {
  mk_repo master
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Branch: on master"* ]]
}

@test "S03k ci: versiones duplicadas en CHANGELOG bloquean" {
  mk_repo
  printf '# C\n## [1.0.0]\n## [1.0.0]\n' > "$FX/CHANGELOG.md"
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate versions: 1.0.0"* ]]
}

@test "S03k ci: marcadores de conflicto en CHANGELOG bloquean" {
  mk_repo
  printf '# C\n%s HEAD\n## [1.0.0]\n' "<<<<<<<" > "$FX/CHANGELOG.md"
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"merge conflict markers"* ]]
}

@test "S03k ci: sin CHANGELOG bloquea" {
  mk_repo
  unlink "$FX/CHANGELOG.md"
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"CHANGELOG.md not found"* ]]
}

@test "S03k ci: CHANGELOG correcto informa el número de versiones" {
  mk_repo
  run ci
  [[ "$output" == *"CHANGELOG OK (2 versions)"* ]]
}

@test "S03k ci: fichero requerido ausente bloquea y --quick no lo comprueba" {
  mk_repo
  unlink "$FX/SECURITY.md"
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing: SECURITY.md"* ]]
  run ci --quick
  [ "$status" -eq 0 ]
  [[ "$output" != *"Missing: SECURITY.md"* ]]
}

@test "S03k ci: comando de más de 150 líneas bloquea; con 150 pasa" {
  mk_repo
  seq 1 150 > "$FX/.opencode/commands/ok.md"
  run ci
  [ "$status" -eq 0 ]
  seq 1 151 > "$FX/.opencode/commands/big.md"
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Size: .opencode/commands/big.md (151 lines)"* ]]
}

@test "S03k ci: frontmatter sin description bloquea; sin frontmatter cuenta como legado" {
  mk_repo
  printf -- '---\nname: x\n---\n' > "$FX/.opencode/commands/nodesc.md"
  printf 'sin frontmatter\n' > "$FX/.opencode/commands/legacy.md"
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"nodesc.md missing description"* ]]
  [[ "$output" != *"legacy.md missing"* ]]
}

@test "S03k ci: frontmatter completo y un legado pasan e informan 1 legado" {
  mk_repo
  printf -- '---\nname: x\ndescription: d\n---\n' > "$FX/.opencode/commands/good.md"
  printf 'legado\n' > "$FX/.opencode/commands/legacy.md"
  run ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"Frontmatter OK (1 legacy)"* ]]
}

@test "S03k ci: settings.json inválido bloquea; ausente solo avisa" {
  mk_repo
  echo '{rota' > "$FX/.claude/settings.json"
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.json invalid JSON"* ]]
  unlink "$FX/.claude/settings.json"
  run ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN settings.json not found"* ]]
}

@test "S03k ci: patrón de 52 caracteres alfanuméricos avisa sin bloquear" {
  mk_repo
  printf 'token %s\n' "$(printf 'a1%.0s' $(seq 1 26))" > "$FX/docs/leak.md"
  run ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"Possible secret pattern detected"* ]]
  [[ "$output" == *"1 warnings"* ]]
}

@test "S03k ci: líneas con 'example' no disparan el aviso de secretos" {
  mk_repo
  printf 'example %s\n' "$(printf 'a1%.0s' $(seq 1 26))" > "$FX/docs/ok.md"
  run ci
  [[ "$output" == *"No secrets detected"* ]]
}

@test "S03k ci: una comprobación de frescura fallida bloquea y cita cómo regenerar" {
  mk_repo
  run env SAVIA_FRESH_CHECKS_FOR_TESTS='art-ok|true|nada
art-mal|false|bash regenerar.sh' SAVIA_LOCK_DIRS_FOR_TESTS=' ' SAVIA_AUTHORITY_REPORT=off bash -c 'cd "$1" && bash "$2"' _ "$FX" "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Generado al día: art-ok"* ]]
  [[ "$output" == *"Generado desfasado: art-mal → regenerar: bash regenerar.sh"* ]]
}

@test "S03k ci: --quick omite solo la comprobación sam.py check" {
  mk_repo
  run env SAVIA_FRESH_CHECKS_FOR_TESTS='sam|python3 scripts/sam.py check|x
otro|false # scripts|y' SAVIA_LOCK_DIRS_FOR_TESTS=' ' SAVIA_AUTHORITY_REPORT=off bash -c 'cd "$1" && bash "$2" --quick' _ "$FX" "$V"
  [[ "$output" != *"Generado desfasado: sam"* ]]
  [[ "$output" == *"Generado desfasado: otro"* ]]
}

@test "S03k ci: lockfile ausente avisa; al día pasa; desfasado avisa" {
  mk_repo
  mkdir -p "$FX/pkg"
  echo '{"dependencies":{"a":"1"}}' > "$FX/pkg/package.json"
  lock() { env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_LOCK_DIRS_FOR_TESTS="$FX/pkg" SAVIA_AUTHORITY_REPORT=off bash -c 'cd "$1" && bash "$2"' _ "$FX" "$V"; }
  run lock
  [[ "$output" == *"Lockfile ausente"* ]]
  [ "$status" -eq 0 ]
  echo '{"packages":{"":{"dependencies":{"a":"1"}}}}' > "$FX/pkg/package-lock.json"
  run lock
  [[ "$output" == *"Lockfile al día"* ]]
  echo '{"packages":{"":{"dependencies":{"a":"2"}}}}' > "$FX/pkg/package-lock.json"
  run lock
  [[ "$output" == *"Lockfile desfasado"* ]]
  [ "$status" -eq 0 ]
}

@test "S03k ci: clean-state-only en repo sin cambios imprime PASS de checkout y worktrees" {
  mk_repo
  run env SAVIA_HANDOFF_FILE="$TMP/no-existe.md" bash "$V" --clean-state-only --repo "$FX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS Checkout principal limpio"* ]]
  [[ "$output" == *"PASS Worktrees agent/*: ninguno retirable"* ]]
  [[ "$output" == *"WARN Traspaso: no existe el traspaso privado"* ]]
}

@test "S03k ci: clean-state cuenta cambios sin seguimiento fuera de output/" {
  mk_repo
  mkdir -p "$FX/output"
  echo a > "$FX/output/ignorado.txt"
  echo b > "$FX/sucio1.txt"
  echo c > "$FX/sucio2.txt"
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"WARN Checkout principal: 2 cambios fuera de output/"* ]]
}

@test "S03k ci: clean-state solo en output/ sigue limpio" {
  mk_repo
  mkdir -p "$FX/output"
  echo a > "$FX/output/x.txt"
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"PASS Checkout principal limpio"* ]]
}

@test "S03k ci: clean-state sobre un directorio que no es git falla con exit 2" {
  mkdir -p "$TMP/vacio"
  run env GIT_CEILING_DIRECTORIES="$TMP" bash "$ROOT/scripts/validate-ci-local.sh" --clean-state-only --repo "$TMP/vacio"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no es un repositorio git"* ]]
}

@test "S03k ci: worktree agent/* ya integrado en main se marca retirable; con cambios o sin integrar no" {
  mk_repo
  git -C "$FX" branch agent/hecho
  git -C "$FX" worktree add -q "$TMP/wt-hecho" agent/hecho
  git -C "$FX" worktree add -q -b agent/pendiente "$TMP/wt-pend"
  echo nuevo > "$TMP/wt-pend/nuevo.txt"
  git -C "$TMP/wt-pend" add nuevo.txt
  git -C "$TMP/wt-pend" -c user.email=a@a -c user.name=a commit -q -m pendiente
  git -C "$FX" worktree add -q -b agent/sucio "$TMP/wt-sucio"
  echo sucio > "$TMP/wt-sucio/sucio.txt"
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"Worktree retirable: agent/hecho"* ]]
  [[ "$output" != *"Worktree retirable: agent/pendiente"* ]]
  [[ "$output" != *"Worktree retirable: agent/sucio"* ]]
  [[ "$output" != *"ninguno retirable"* ]]
}

@test "S03k ci: squash con cambios posteriores sigue contando como integrado (patch-id)" {
  mk_repo main
  git -C "$FX" worktree add -q -b agent/sq "$TMP/wt-sq"
  echo uno > "$TMP/wt-sq/f.txt"
  git -C "$TMP/wt-sq" add f.txt
  git -C "$TMP/wt-sq" -c user.email=a@a -c user.name=a commit -q -m rama
  # main recibe el mismo parche como commit propio y luego otro cambio en el fichero
  echo uno > "$FX/f.txt"
  git -C "$FX" add f.txt
  git -C "$FX" -c user.email=a@a -c user.name=a commit -q -m "squash (#9)"
  echo dos >> "$FX/f.txt"
  git -C "$FX" -c user.email=a@a -c user.name=a commit -qam "despues"
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"Worktree retirable: agent/sq"* ]]
}

@test "S03k ci: traspaso privado más viejo que un commit de main avisa; más nuevo pasa" {
  mk_repo
  H="$TMP/handoff.md"; echo h > "$H"
  touch -d '2 days ago' "$H"
  run env SAVIA_HANDOFF_FILE="$H" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"commit(s) en main desde la última actualización del traspaso privado"* ]]
  touch -d '+1 hour' "$H"
  run env SAVIA_HANDOFF_FILE="$H" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"PASS Traspaso al día"* ]]
}

@test "S03k ci: traspaso versionado en main se señala como estado interno" {
  mk_repo
  mkdir -p "$FX/docs/propuestas"
  echo x > "$FX/docs/propuestas/session-handoff.md"
  git -C "$FX" add -A
  git -C "$FX" -c user.email=a@a -c user.name=a commit -q -m versionado
  git -C "$FX" branch -f main HEAD
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"está versionado en"* ]]
}

@test "S03k ci: --clean-state añade las líneas de estado limpio al informe completo" {
  mk_repo
  run ci
  [[ "$output" != *"Checkout principal"* ]]
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_LOCK_DIRS_FOR_TESTS=' ' SAVIA_AUTHORITY_REPORT=off bash -c 'cd "$1" && bash "$2" --clean-state' _ "$FX" "$V"
  [[ "$output" == *"Checkout principal"* ]]
  [ "$status" -eq 0 ]
}

@test "S03k ci: gate-result en WARN se cuenta como aviso y no bloquea" {
  mk_repo
  printf '#!/usr/bin/env bash\necho "WARN gate unknown"\n' > "$FX/.claude/hooks/lib/gate-result.sh"
  run ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN gate unknown"* ]]
}

@test "S03k ci: coherence en advisory se resume en un aviso con el recuento" {
  mk_repo
  printf '#!/usr/bin/env bash\necho "WARN coherence a"\necho "WARN coherence b"\n' > "$FX/scripts/coherence-gates.sh"
  run ci
  [[ "$output" == *"Coherence: 2 gate(s) en advisory"* ]]
  [ "$status" -eq 0 ]
}

@test "S03k ci: informe de cobertura cuenta criterios débiles y ausentes por separado" {
  mk_repo
  jq -nc '{initiatives:[{id:"SE-A",completion:{merge_pr:1,acceptance_evidence:[
     {criterion:"A1",file:"x",authority:"simulada",authority_required:"real"},
     {criterion:"A2",file:"x"},
     {criterion:"A3",file:"x",authority:"real",authority_required:"real"}]}},
     {id:"SE-B"}]}' > "$TMP/state.json"
  run env SAVIA_PLANNING_STATE_FOR_TESTS="$TMP/state.json" SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_LOCK_DIRS_FOR_TESTS=' ' bash -c 'cd "$1" && bash "$2"' _ "$FX" "$V"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 criterios sin autoridad suficiente: 1 inferior a la requerida, 1 con autoridad ausente"* ]]
  [[ "$output" == *"SE-A · A1: autoridad simulada < requerida real"* ]]
  [[ "$output" != *"A3:"* ]]
}

@test "S03k ci: SAVIA_AUTHORITY_REPORT=off suprime el informe" {
  mk_repo
  run ci
  [[ "$output" != *"Cobertura no verificada"* ]]
}

@test "S03k ci: el resumen cuenta pasadas, fallos y avisos" {
  mk_repo
  unlink "$FX/.claude/settings.json"
  run ci
  [[ "$output" =~ Results:\ ([0-9]+)\ passed,\ 0\ failed,\ 1\ warnings ]]
  [ "${BASH_REMATCH[1]}" -ge 5 ]
}

@test "S03k ci: un directorio de lock sin package.json se ignora" {
  mk_repo
  mkdir -p "$FX/sinpkg"
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_LOCK_DIRS_FOR_TESTS="$FX/sinpkg" SAVIA_AUTHORITY_REPORT=off bash -c 'cd "$1" && bash "$2"' _ "$FX" "$V"
  [[ "$output" != *"Lockfile"* ]]
}

@test "S03k ci: un solo cambio sucio ya es WARN en el checkout principal" {
  mk_repo
  echo a > "$FX/uno.txt"
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"WARN Checkout principal: 1 cambios fuera de output/"* ]]
}

@test "S03k ci: rama agent/* sin commits propios y main avanzado se marca retirable" {
  mk_repo main
  git -C "$FX" branch agent/vieja
  echo n > "$FX/nuevo.txt"
  git -C "$FX" add nuevo.txt
  git -C "$FX" -c user.email=a@a -c user.name=a commit -q -m avanza
  git -C "$FX" worktree add -q "$TMP/wt-vieja" agent/vieja
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"Worktree retirable: agent/vieja"* ]]
}

@test "S03k ci: prefiere origin/main a main local para mirar el traspaso versionado" {
  mk_repo main
  mkdir -p "$FX/docs/propuestas"
  echo x > "$FX/docs/propuestas/session-handoff.md"
  git -C "$FX" add -A
  git -C "$FX" -c user.email=a@a -c user.name=a commit -q -m versionado
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
  git -C "$FX" update-ref refs/heads/main HEAD~1
  run env SAVIA_HANDOFF_FILE="$TMP/no.md" bash "$V" --clean-state-only --repo "$FX"
  [[ "$output" == *"está versionado en origin/main"* ]]
}
