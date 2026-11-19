#!/usr/bin/env bats
# Ref: SE-273 S3 — Egress control
# Spec: docs/propuestas/SE-273-contencion-trayectoria.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMPDIR=$(mktemp -d)
  # Isolation: scripts log to PROJECT_ROOT/output. A temp root (with the real
  # config/ linked) keeps test egress denials and profiles out of the live logs
  # that real sessions read.
  export PROJECT_ROOT="$TMPDIR/root"
  mkdir -p "$PROJECT_ROOT/output"
  ln -s "$REPO_ROOT/config" "$PROJECT_ROOT/config"
}

teardown() {
  rm -rf "$TMPDIR"
}

# ═══════════════════════════════════════════════════════════════════
# S3: Egress control
# ═══════════════════════════════════════════════════════════════════

@test "S3/AC-3.1: egress-gate blocks unknown domain" {
  run bash "$REPO_ROOT/scripts/egress-gate.sh" check "evil.example.com"
  [ "$status" -ne 0 ]
}

@test "S3/AC-3.1: egress-gate allows known domain (github.com)" {
  run bash "$REPO_ROOT/scripts/egress-gate.sh" check "github.com"
  [ "$status" -eq 0 ]
}

@test "S3/AC-3.5: isolated mode blocks all egress" {
  SAVIA_ISOLATED_MODE=1 run bash "$REPO_ROOT/scripts/egress-gate.sh" check "github.com"
  [ "$status" -ne 0 ]
}

@test "S3: egress-gate status command works" {
  run bash "$REPO_ROOT/scripts/egress-gate.sh" status
  [ "$status" -eq 0 ]
}

@test "S3: egress-gate propose command works" {
  run bash "$REPO_ROOT/scripts/egress-gate.sh" propose "docs.example.com" "test documentation"
  [ "$status" -eq 0 ]
}

@test "isolation: egress denials land in the temp root, not the repo output logs" {
  before=$(cat "$REPO_ROOT/output/egress-denials.jsonl" 2>/dev/null | sha256sum)
  run bash "$REPO_ROOT/scripts/egress-gate.sh" check "evil.example.com"
  [ -s "$PROJECT_ROOT/output/egress-denials.jsonl" ]
  [ "$(cat "$REPO_ROOT/output/egress-denials.jsonl" 2>/dev/null | sha256sum)" = "$before" ]
}

@test "empty: egress check with an empty domain exits 2 with usage" {
  run bash "$REPO_ROOT/scripts/egress-gate.sh" check ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "safety: egress-gate runs under set -uo pipefail" {
  head -3 "$REPO_ROOT/scripts/egress-gate.sh" | grep -q 'set -uo pipefail'
}
