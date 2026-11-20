#!/usr/bin/env bats
# Ref: docs/rules/domain/hook-profiles.md
# Tests for hook-profile.sh — Hook profile manager

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/hook-profile.sh"
  TMPDIR_HP=$(mktemp -d)
  export HOME="$TMPDIR_HP"
  unset SAVIA_HOOK_PROFILE
}

teardown() {
  rm -rf "$TMPDIR_HP"
}

@test "get returns standard as default" {
  run bash "$SCRIPT" get
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"standard"* ]]
  [[ "$output" == *"default"* ]]
}

@test "set minimal writes no file and says how to export" {
  run bash "$SCRIPT" set minimal
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"export SAVIA_HOOK_PROFILE=minimal"* ]]
  [[ ! -e "$TMPDIR_HP/.savia/hook-profile" ]]
  [[ -z "$(find "$TMPDIR_HP" -type f)" ]]
}

@test "set does not change what get reports" {
  bash "$SCRIPT" set strict
  run bash "$SCRIPT" get
  [[ "$output" == *"standard"* ]]
  [[ "$output" != *"strict"* ]]
}

@test "legacy profile file is ignored and flagged" {
  mkdir -p "$TMPDIR_HP/.savia"
  echo minimal > "$TMPDIR_HP/.savia/hook-profile"
  run bash "$SCRIPT" get
  [[ "$output" == *"standard (default)"* ]]
  [[ "$output" == *"is ignored"* ]]
}

@test "legacy file does not lower the real gate" {
  mkdir -p "$TMPDIR_HP/.savia"
  echo minimal > "$TMPDIR_HP/.savia/hook-profile"
  run bash -c 'source "'"$BATS_TEST_DIRNAME"'/../.claude/hooks/lib/profile-gate.sh"; echo "$SAVIA_HOOK_PROFILE"'
  [[ "$output" == "standard" ]]
}

@test "set invalid profile fails" {
  run bash "$SCRIPT" set bogus
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"unknown profile"* ]]
}

@test "set without name fails" {
  run bash "$SCRIPT" set
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"profile name required"* ]]
}

@test "env var is reported as the source" {
  export SAVIA_HOOK_PROFILE=ci
  run bash "$SCRIPT" get
  [[ "$output" == *"ci (env var)"* ]]
}

@test "list shows all 4 profiles" {
  run bash "$SCRIPT" list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"minimal"* ]]
  [[ "$output" == *"standard"* ]]
  [[ "$output" == *"strict"* ]]
  [[ "$output" == *"ci"* ]]
}

@test "help flag shows usage" {
  run bash "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage"* ]]
}

@test "unknown command fails with usage" {
  run bash "$SCRIPT" destroy
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Unknown command"* ]]
}

@test "set all 4 valid profiles succeeds" {
  for p in minimal standard strict ci; do
    run bash "$SCRIPT" set "$p"
    [[ "$status" -eq 0 ]]
  done
}

@test "script has safety flags" {
  head -5 "$SCRIPT" | grep -qE "set -[eu]o pipefail"
}

@test "edge: set with special chars in name fails" {
  run bash "$SCRIPT" set "mini;rm -rf"
  [[ "$status" -eq 1 ]]
}

@test "coverage: core functions exist" {
  grep -q "get_profile()" "$SCRIPT"
  grep -q "list_profiles()" "$SCRIPT"
  grep -q "set_profile()" "$SCRIPT"
}
