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
    bash -c 'source "$1/scripts/lib/git-env-clean.sh"; git_env_clean --isolate-config; env | grep -E "^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|CONFIG_COUNT)="; echo "G=$GIT_CONFIG_GLOBAL"' _ "$ROOT"
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
