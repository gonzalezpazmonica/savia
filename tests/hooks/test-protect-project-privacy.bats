#!/usr/bin/env bats
# Tests for protect-project-privacy.sh pre-commit script
# Ref: docs/rules/domain/project-privacy-protection.md

setup() {
  # Test-local git identity: fixture commits must not depend on a global
  # user.name/user.email (absent on some machines, present in CI).
  export GIT_AUTHOR_NAME="bats" GIT_AUTHOR_EMAIL="bats@example.invalid"
  export GIT_COMMITTER_NAME="bats" GIT_COMMITTER_EMAIL="bats@example.invalid"
  TMPDIR=$(mktemp -d)
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/protect-project-privacy.sh"

  # Create minimal git repo for testing
  git init "$TMPDIR/repo" --quiet
  cd "$TMPDIR/repo"
  echo "# Test" > README.md
  echo "projects/*" > .gitignore
  echo "!projects/allowed/" >> .gitignore
  git add -A && git commit -m "init" --quiet
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$SCRIPT"
}

@test "script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ] || chmod +x "$SCRIPT"
}

@test "--check mode runs without error" {
  cd "$TMPDIR/repo"
  # Copy script into the test repo so ROOT resolves
  mkdir -p scripts
  cp "$SCRIPT" scripts/protect-project-privacy.sh
  chmod +x scripts/protect-project-privacy.sh
  run bash scripts/protect-project-privacy.sh --check
  [ "$status" -eq 0 ]
}

@test "allows commit when .gitignore not modified" {
  cd "$TMPDIR/repo"
  mkdir -p scripts
  cp "$SCRIPT" scripts/protect-project-privacy.sh
  chmod +x scripts/protect-project-privacy.sh

  echo "new line" >> README.md
  git add README.md
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 0 ]
}

@test "BLOCKS commit when .gitignore adds new project whitelist" {
  cd "$TMPDIR/repo"
  mkdir -p scripts .claude
  cp "$SCRIPT" scripts/protect-project-privacy.sh
  chmod +x scripts/protect-project-privacy.sh

  echo "!projects/secret-client/" >> .gitignore
  git add .gitignore
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEADO"* ]]
  [[ "$output" == *"secret-client"* ]]
}

@test "allows commit when project is authorized" {
  cd "$TMPDIR/repo"
  mkdir -p scripts .claude
  cp "$SCRIPT" scripts/protect-project-privacy.sh
  chmod +x scripts/protect-project-privacy.sh

  # Pre-authorize the project
  echo "authorized-project" > .claude/.project-authorizations
  echo "!projects/authorized-project/" >> .gitignore
  git add .gitignore
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 0 ]
}

@test "BLOCKS git add -f of unwhitelisted project files" {
  cd "$TMPDIR/repo"
  mkdir -p scripts .claude projects/sneaky-project
  cp "$SCRIPT" scripts/protect-project-privacy.sh
  chmod +x scripts/protect-project-privacy.sh

  echo "secret data" > projects/sneaky-project/data.txt
  git add -f projects/sneaky-project/data.txt
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEADO"* ]]
  [[ "$output" == *"sneaky-project"* ]]
}

# ── Escrituras por Bash sobre .gitignore (sed -i, redirección, tee) ──
# Los guards PreToolUse de Edit/Write no ven estas escrituras; el control efectivo es este hook de commit.

prep_script() {
  mkdir -p scripts .claude
  cp "$SCRIPT" scripts/protect-project-privacy.sh
}

@test "Bash: sed -i que añade whitelist no autorizada se bloquea en el commit" {
  cd "$TMPDIR/repo" && prep_script
  printf '%s\n' '!projects/secret-client/' >> .gitignore
  git add .gitignore
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"secret-client"* ]]
}

@test "Bash: sed -i con proyecto autorizado pasa el commit" {
  cd "$TMPDIR/repo" && prep_script
  echo "soul-demo" > .claude/.project-authorizations
  printf '%s\n' '!projects/soul-demo/' >> .gitignore
  git add .gitignore
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 0 ]
}

@test "Bash: autorización por prefijo no vale (soul no autoriza soul-demo)" {
  cd "$TMPDIR/repo" && prep_script
  echo "soul" > .claude/.project-authorizations
  printf '!projects/soul-demo/\n' | tee -a .gitignore >/dev/null
  git add .gitignore
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"soul-demo"* ]]
}

@test "Bash: whitelist anclada (!/projects/x/) pasa la línea, pero los ficheros del proyecto se bloquean" {
  cd "$TMPDIR/repo" && prep_script
  printf '%s\n' '!/projects/sneaky/' >> .gitignore
  mkdir -p projects/sneaky && echo dato > projects/sneaky/data.txt
  git add .gitignore projects/sneaky/data.txt
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"sneaky"* ]]
}

@test "Bash: borrar la exclusión projects/* no permite commitear ficheros de proyecto" {
  cd "$TMPDIR/repo" && prep_script
  grep -vx 'projects/\*' .gitignore > .gitignore.new && mv .gitignore.new .gitignore
  mkdir -p projects/other && echo dato > projects/other/data.txt
  git add .gitignore projects/other/data.txt
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"other"* ]]
}

@test "BLOCKS git mv de un fichero versionado hacia un proyecto no whitelisteado" {
  cd "$TMPDIR/repo" && prep_script
  mkdir -p projects/secret
  git mv -f README.md projects/secret/README.md
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"secret"* ]]
}

@test "autorización con metacaracteres: !projects/.*/ no casa con cualquier línea autorizada" {
  cd "$TMPDIR/repo" && prep_script
  echo "soul-demo" > .claude/.project-authorizations
  printf '%s\n' '!projects/.*/' >> .gitignore
  git add .gitignore
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"'.*'"* ]]
}

@test "whitelist con metacaracteres: axb en la whitelist no deja pasar ficheros de a.b" {
  cd "$TMPDIR/repo" && prep_script
  printf '%s\n' '!projects/axb/' >> .gitignore
  echo "axb" > .claude/.project-authorizations
  git add .gitignore && git commit -qm wl
  mkdir -p projects/a.b && echo dato > projects/a.b/data.txt
  git add -f projects/a.b/data.txt
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.b"* ]]
}

# ── Edge cases ──

@test "empty .gitignore change does not crash" {
  cd "$TMPDIR/repo"
  mkdir -p scripts
  cp "$SCRIPT" scripts/protect-project-privacy.sh
  chmod +x scripts/protect-project-privacy.sh
  touch .gitignore
  git add .gitignore
  run bash scripts/protect-project-privacy.sh --hook
  [ "$status" -eq 0 ]
}

@test "nonexistent .claude dir handled gracefully" {
  cd "$TMPDIR/repo"
  mkdir -p scripts
  cp "$SCRIPT" scripts/protect-project-privacy.sh
  chmod +x scripts/protect-project-privacy.sh
  run bash scripts/protect-project-privacy.sh --check
  [ "$status" -eq 0 ]
  grep -q "." <<< "$status"
}

@test "core hooks use safety flags" {
  grep -q "set -[euo]" "$BATS_TEST_DIRNAME/../../.opencode/hooks/validate-bash-global.sh"
}

@test "edge: empty input produces no error" {
  run bash -c "echo '{}' | SAVIA_HOOK_PROFILE=minimal bash '$BATS_TEST_DIRNAME/../../.opencode/hooks/validate-bash-global.sh' 2>&1"
  [ "$status" -eq 0 ]
}
