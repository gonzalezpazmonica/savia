#!/usr/bin/env bats
# SE-487 R1-R3 — clon limpio neutral: los ficheros versionados que se cargan al
# arrancar no llevan datos de ninguna persona; la identidad la inyecta el
# arranque desde el perfil local gitignored.
# Ref: docs/specs/SE-487-clean-clone-neutral-and-windows.spec.md (AC-1, AC-2, AC-3)
#
# SE487_SESSION_INIT permite probar una copia parcheada del hook antes de aplicarla.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  REPO="$(pwd)"
  GUARD="$REPO/scripts/clean-clone-guard.sh"
  GENERATOR="$REPO/scripts/generate-critical-facts.sh"
  HOOK="${SE487_SESSION_INIT:-$REPO/.claude/hooks/session-init.sh}"
  TMP="$(mktemp -d)"
  export TMPDIR="$TMP"
}

teardown() {
  rm -rf "$TMP"
}

# fixture_tree DIR — árbol de arranque mínimo y limpio con un perfil local «zz-fixture».
fixture_tree() {
  local d="$1"
  mkdir -p "$d/docs" "$d/.claude/profiles/users/template" "$d/.claude/profiles/users/zz-fixture"
  printf '# W\n@docs/critical-facts.md\n@docs/extra.md\n' > "$d/CLAUDE.md"
  cp "$REPO/docs/critical-facts.md" "$d/docs/critical-facts.md"
  echo "Regla sin datos de nadie." > "$d/docs/extra.md"
  printf 'name: "Quetzal Fixturina"\n' > "$d/.claude/profiles/users/zz-fixture/identity.md"
}

# run_hook CWD — ejecuta el arranque desde CWD con HOME aislado; deja OUT y STATUS.
run_hook() {
  mkdir -p "$TMP/home"
  OUT=$(cd "$1" && HOME="$TMP/home" CLAUDE_PROJECT_DIR="$REPO" \
    OLLAMA_URL="http://127.0.0.1:9" SAVIA_SHIELD_PORT=9 SAVIA_SHIELD_PROXY_PORT=9 \
    SAVIA_PROBE_STATE="$TMP/probes.state" bash "$HOOK" </dev/null 2>/dev/null)
  STATUS=$?
}

# ── R3 / AC-3: guardia ───────────────────────────────────────────────────────

@test "AC-3: guard passes on the real versioned tree" {
  run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS clean-clone-guard"* ]]
}

@test "AC-3: guard passes on a clean fixture with a local profile present" {
  fixture_tree "$TMP/t"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 0 ]
}

@test "AC-3 negative: slug of a local profile injected in critical-facts fails" {
  fixture_tree "$TMP/t"
  echo '- **Usuario activo**: zz-fixture' >> "$TMP/t/docs/critical-facts.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/critical-facts.md"* ]]
  # El informe no repite el dato personal en los logs de la CI.
  [[ "$output" != *"zz-fixture"* ]]
}

@test "AC-3 negative: local profile name inside an @import fails" {
  fixture_tree "$TMP/t"
  echo "Hola, Quetzal Fixturina." >> "$TMP/t/docs/extra.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/extra.md"* ]]
}

@test "AC-3 negative: /home/<name>/ path in CLAUDE.md fails without local profiles" {
  fixture_tree "$TMP/t"
  rm -rf "$TMP/t/.claude/profiles/users/zz-fixture"
  echo 'ANDROID_HOME=/home/someone/Android/Sdk' >> "$TMP/t/CLAUDE.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE.md: ruta personal"* ]]
}

@test "AC-3 negative: C:\\Users\\<name>\\ path in AGENTS.md fails" {
  fixture_tree "$TMP/t"
  printf 'bash en C:\\Users\\someone\\AppData\\git\n' > "$TMP/t/AGENTS.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AGENTS.md: ruta personal"* ]]
}

@test "AC-3 negative: old generator format fails even without local profiles (CI)" {
  fixture_tree "$TMP/t"
  rm -rf "$TMP/t/.claude/profiles/users/zz-fixture"
  echo '- **Usuario activo**: x · profile slug `x` · activated 2026-07-13T16:35:00+02:00' >> "$TMP/t/docs/critical-facts.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 1 ]
}

@test "edge: placeholder paths like /home/<usuaria>/ are not personal data" {
  fixture_tree "$TMP/t"
  echo 'Ejemplo: /home/<usuaria>/Android/Sdk' >> "$TMP/t/CLAUDE.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 0 ]
}

@test "edge: the template profile is never treated as personal data" {
  fixture_tree "$TMP/t"
  echo "Copia el perfil template." >> "$TMP/t/CLAUDE.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 0 ]
}

@test "fail-closed: missing CLAUDE.md is an error, not a pass" {
  fixture_tree "$TMP/t"
  rm -f "$TMP/t/CLAUDE.md"
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 2 ]
}

@test "fail-closed: unknown argument is an error" {
  run bash "$GUARD" --nope
  [ "$status" -eq 2 ]
}

# ── R1: generador ─────────────────────────────────────────────────────────────

@test "R1: generator ignores the local profile and preferences" {
  fixture_tree "$TMP/t"
  printf 'active_slug: "zz-fixture"\nactivated_at: "2031-01-02T03:04:05Z"\n' > "$TMP/t/.claude/profiles/active-user.md"
  mkdir -p "$TMP/home/.savia"
  echo 'frontend: zzfrontend' > "$TMP/home/.savia/preferences.yaml"
  run bash -c "cd '$TMP/t' && HOME='$TMP/home' bash '$GENERATOR'"
  [ "$status" -eq 0 ]
  run grep -E 'zz-fixture|2031-01-02|zzfrontend' "$TMP/t/docs/critical-facts.md"
  [ "$status" -eq 1 ]
  run bash "$GUARD" --root "$TMP/t"
  [ "$status" -eq 0 ]
}

@test "R2: CLAUDE.md Savia Mobile uses variables and points to CLAUDE.local.md" {
  section="$(sed -n '/^## Savia Mobile/,/^## /p' CLAUDE.md)"
  [[ "$section" == *'$ANDROID_HOME'* ]]
  [[ "$section" == *"CLAUDE.local.md"* ]]
  [[ "$section" != *"/home/"* ]]
}

# ── AC-1 / AC-2: arranque ─────────────────────────────────────────────────────

@test "AC-1: without a local profile the startup says it does not know who you are" {
  mkdir -p "$TMP/clean"
  run_hook "$TMP/clean"
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" == *"Sin perfil: no sé quién eres"* ]]
  [[ "$OUT" == *"/profile-setup"* ]]
  [[ "$OUT" != *"Perfil: "* ]]
}

@test "AC-2: with a fixture profile the startup injects its slug and writes nothing versioned" {
  fixture_tree "$TMP/t"
  printf 'active_slug: "zz-fixture"\n' > "$TMP/t/.claude/profiles/active-user.md"
  before="$(git -C "$REPO" status --porcelain)"
  run_hook "$TMP/t"
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" == *"Perfil: Quetzal Fixturina · slug zz-fixture"* ]]
  [[ "$OUT" != *"Sin perfil"* ]]
  [ "$(git -C "$REPO" status --porcelain)" = "$before" ]
}

@test "AC-2 negative: an unsafe slug is not injected (JSON stays valid)" {
  fixture_tree "$TMP/t"
  # Un directorio «a\x» existe: sin el filtro, «\x» rompería el JSON del contexto.
  mkdir -p "$TMP/t/.claude/profiles/users/a\\x"
  printf 'active_slug: "a\\x"\n' > "$TMP/t/.claude/profiles/active-user.md"
  run_hook "$TMP/t"
  [[ "$OUT" == *"Sin perfil: no sé quién eres"* ]]
  python3 -c 'import json,sys; json.loads(sys.argv[1])' "$OUT"
}
