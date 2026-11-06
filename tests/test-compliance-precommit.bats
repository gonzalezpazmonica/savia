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

# ── S03r: privacidad de proyectos y enlaces del CHANGELOG, por comportamiento ──
# Ref: docs/rules/domain/critical-rules-extended.md (privacidad de proyectos),
# SE-491 (autorizaciones, PROPOSED) y changelog-enforcement.md. Se ejecutan los
# scripts reales en el repo temporal de setup(); git es real, no hay simulación.

ppp() { (cd "$R" && bash scripts/protect-project-privacy.sh "$@"); }

whitelist_base() {  # .gitignore con projects/* ignorado y un proyecto público
  printf 'projects/*\n!projects/public/\n' > "$R/.gitignore"
  git -C "$R" add .gitignore && git -C "$R" -c core.hooksPath=/dev/null commit -q -m gi
}

@test "privacy: protect-project-privacy.sh declares set -uo pipefail" {
  grep -q '^set -uo pipefail' "$ROOT/scripts/protect-project-privacy.sh"
}

@test "privacy: files of a whitelisted project pass the hook" {
  whitelist_base
  mkdir -p "$R/projects/public"; echo x > "$R/projects/public/a.md"
  git -C "$R" add projects/public/a.md
  run ppp --hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "privacy: force-added file of a non-whitelisted project is blocked" {
  whitelist_base
  mkdir -p "$R/projects/secret"; echo x > "$R/projects/secret/a.md"
  git -C "$R" add -f projects/secret/a.md
  run ppp --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEADO"*"'secret'"*"NO está en el whitelist"* ]]
}

@test "privacy: non-ASCII project name is blocked too (quotePath bypass)" {
  # Antes: git entrecomillaba la ruta ("projects/cl\303\257ente/a.md"), no casaba
  # con ^projects/ y el hook dejaba pasar el proyecto con exit 0.
  whitelist_base
  mkdir -p "$R/projects/clïente"; echo x > "$R/projects/clïente/a.md"
  git -C "$R" add -f "projects/clïente/a.md"
  run ppp --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"'clïente'"* ]]
}

@test "privacy: the real pre-commit rejects the non-ASCII project commit" {
  whitelist_base
  mkdir -p "$R/projects/clïente"; echo x > "$R/projects/clïente/a.md"
  git -C "$R" add -f "projects/clïente/a.md"
  run git -C "$R" commit -m leak
  [ "$status" -ne 0 ]
  run git -C "$R" log --oneline -1 --format=%s
  [ "$output" = "gi" ]
}

@test "privacy: project whose name is a prefix of a whitelisted one is blocked" {
  whitelist_base
  mkdir -p "$R/projects/pub"; echo x > "$R/projects/pub/a.md"
  git -C "$R" add -f projects/pub/a.md
  run ppp --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"'pub'"* ]]
}

@test "privacy: git mv into an ignored project dir is blocked (rename)" {
  whitelist_base
  echo x > "$R/doc.md"; git -C "$R" add doc.md; git -C "$R" -c core.hooksPath=/dev/null commit -q -m doc
  mkdir -p "$R/projects/secret"
  git -C "$R" mv doc.md projects/secret/doc.md
  run ppp --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"'secret'"* ]]
}

@test "privacy: deleting files of an ignored project is not blocked" {
  mkdir -p "$R/projects/old"; echo x > "$R/projects/old/a.md"
  git -C "$R" add projects/old/a.md; git -C "$R" -c core.hooksPath=/dev/null commit -q -m old
  whitelist_base
  git -C "$R" rm -q projects/old/a.md
  run ppp --hook
  [ "$status" -eq 0 ]
}

@test "privacy: new unauthorized whitelist line in .gitignore is blocked" {
  whitelist_base
  printf '!projects/secret/\n' >> "$R/.gitignore"; git -C "$R" add .gitignore
  run ppp --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"whitelist de .gitignore sin autorización"*"!projects/secret/"* ]]
}

@test "privacy: leading-slash whitelist line is blocked (anchored form bypass)" {
  # Antes: «!/projects/secret/» no casaba con ^+!projects/ y pasaba con exit 0.
  whitelist_base
  printf '!/projects/secret/\n' >> "$R/.gitignore"; git -C "$R" add .gitignore
  run ppp --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"proyecto 'secret'"* ]]
}

@test "privacy: authorized project may be whitelisted, in any whitelist form" {
  whitelist_base
  mkdir -p "$R/.claude"; echo secret > "$R/.claude/.project-authorizations"
  printf '!/projects/secret/**\n' >> "$R/.gitignore"; git -C "$R" add .gitignore
  run ppp --hook
  [ "$status" -eq 0 ]
}

@test "privacy: authorization is exact, not a prefix or substring match" {
  whitelist_base
  mkdir -p "$R/.claude"; echo secret-public > "$R/.claude/.project-authorizations"
  printf '!projects/secret/\n' >> "$R/.gitignore"; git -C "$R" add .gitignore
  run ppp --hook
  [ "$status" -eq 1 ]
}

@test "privacy: leading-slash whitelisted project counts as whitelisted for its files" {
  printf 'projects/*\n!/projects/pub2/\n' > "$R/.gitignore"
  git -C "$R" add .gitignore && git -C "$R" -c core.hooksPath=/dev/null commit -q -m gi
  mkdir -p "$R/projects/pub2"; echo x > "$R/projects/pub2/a.md"
  git -C "$R" add projects/pub2/a.md
  run ppp --hook
  [ "$status" -eq 0 ]
}

@test "privacy: removed whitelist line in .gitignore is not a publication" {
  whitelist_base
  printf 'projects/*\n' > "$R/.gitignore"; git -C "$R" add .gitignore
  run ppp --hook
  [ "$status" -eq 0 ]
}

@test "privacy: --check lists whitelist with authorization state and exits 0" {
  printf 'projects/*\n!projects/a/\n!projects/b/\n' > "$R/.gitignore"
  mkdir -p "$R/.claude"; echo a > "$R/.claude/.project-authorizations"
  run ppp --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"a (autorizado)"* ]]
  [[ "$output" == *"b (en whitelist pero sin autorización explícita)"* ]]
}

@test "privacy: --check with no authorizations file says (ninguna)" {
  printf 'projects/*\n' > "$R/.gitignore"
  run ppp --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"(ninguna)"* ]]
}

@test "privacy: --authorize without project name fails with usage" {
  run ppp --authorize
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
  [ ! -e "$R/.claude/.project-authorizations" ]
}

@test "privacy: --authorize with a wrong confirmation is rejected and writes nothing" {
  run bash -c 'cd "$1" && echo "si" | bash scripts/protect-project-privacy.sh --authorize demo' _ "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Autorización cancelada"* ]]
  [ ! -e "$R/.claude/.project-authorizations" ]
}

@test "privacy: --authorize with SÍ PÚBLICO records the exact project name" {
  run bash -c 'cd "$1" && printf "SÍ PÚBLICO\n" | bash scripts/protect-project-privacy.sh --authorize demo' _ "$R"
  [ "$status" -eq 0 ]
  [ "$(cat "$R/.claude/.project-authorizations")" = "demo" ]
}

cl() { printf '%b' "$1" > "$BATS_TEST_TMPDIR/CH.md"; run bash "$ROOT/scripts/validate-changelog-links.sh" "$BATS_TEST_TMPDIR/CH.md"; }

@test "changelog: every version with its link passes" {
  cl '## [1.2.0] — b\n## [1.1.0] — a\n\n[1.2.0]: https://x/compare/v1.1.0...v1.2.0\n[1.1.0]: https://x/r/v1.1.0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Todos los enlaces"* ]]
}

@test "changelog: missing link fails with exit 1 and names the version" {
  cl '## [1.2.0] — b\n## [1.1.0] — a\n\n[1.1.0]: https://x/r/v1.1.0\n'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing link for [1.2.0]"* ]]
  [[ "$output" == *"1 version(s)"* ]]
  [[ "$output" != *"[1.1.0] in"* ]]
}

@test "changelog: dots are literal, [1x2x3] is not the link of [1.2.3]" {
  # Antes: la versión iba como regex y «.» casaba con cualquier carácter.
  cl '## [1.2.3] — a\n\n[1x2x3]: https://x\n'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing link for [1.2.3]"* ]]
}

@test "changelog: link must start the line and use https" {
  cl '## [1.0.0] — a\n\nsee [1.0.0]: https://x\n[1.0.0]: http://x\n'
  [ "$status" -eq 1 ]
}

@test "changelog: counts every missing version, boundary of two errors" {
  cl '## [2.0.0]\n## [1.0.0]\n## [0.1.0]\n\n[0.1.0]: https://x\n'
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 version(s)"* ]]
}

@test "changelog: empty changelog without versions passes" {
  cl ''
  [ "$status" -eq 0 ]
}

@test "changelog: explicit path that does not exist fails closed" {
  # Antes: «No CHANGELOG found» y exit 0, aunque el runner pasa la ruta explícita.
  run bash "$ROOT/scripts/validate-changelog-links.sh" "$BATS_TEST_TMPDIR/nonexistent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CHANGELOG not found"* ]]
}

@test "changelog: no argument and no CHANGELOG.md in cwd passes with a notice" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$ROOT/scripts/validate-changelog-links.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No CHANGELOG found"* ]]
}

@test "changelog: the compliance runner blocks a staged CHANGELOG with a missing link" {
  printf '## [9.9.9] — x\n' > "$R/CHANGELOG.md"; git -C "$R" add CHANGELOG.md
  run git -C "$R" commit -m cl
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing link for [9.9.9]"* ]]
}

@test "changelog: a version header only counts at the start of the line" {
  cl 'texto ## [3.0.0] citado\n## [1.0.0]\n\n[1.0.0]: https://x\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"3.0.0"* ]]
}
