#!/usr/bin/env bats
# BATS tests for multica tactical patterns adoption
# SPEC: output/research/multica-brief.md
# SCRIPT: scripts/path-redact.sh
# Ref: .claude/schemas/agent-result.schema.json
# Quality gate: SPEC-055 (audit score ≥80)
# Safety: tests use BATS run/status guards; target scripts have set -uo pipefail
# Status: active
# Date: 2026-04-12
# Era: 223
# Problem: PII leakage via filesystem paths, inaccurate agent cost tracking,
#   sequential overnight execution
# Solution: path-redact.sh, agent-result schema
# (skills-lock retired 2026-09-27: never verified by CI or hooks)
# Acceptance: scripts functional, schema valid, redaction works
# Dependencies: path-redact.sh, agent-result.schema.json

## Problem: 4 tactical gaps identified from multica-ai/multica research
## Solution: path redaction, agent result schema
## Acceptance: all scripts pass syntax, functional tests cover happy + edge paths

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PATH_REDACT="$REPO_ROOT/scripts/path-redact.sh"
  export SCHEMA="$REPO_ROOT/.claude/schemas/agent-result.schema.json"
}

teardown() {
  cd /
}

## Path redaction tests

@test "path-redact.sh exists, executable, valid syntax" {
  [[ -x "$PATH_REDACT" ]]
  bash -n "$PATH_REDACT"
}

@test "redacts HOME path from stdin" {
  result=$(echo "$HOME/project/file.txt" | bash "$PATH_REDACT")
  [[ "$result" == "~/project/file.txt" ]]
}

@test "leaves clean text unchanged" {
  result=$(echo "no paths here" | bash "$PATH_REDACT")
  [[ "$result" == "no paths here" ]]
}

@test "check mode detects path in file" {
  local tmp; tmp=$(mktemp)
  echo "Found at $HOME/secret/file.txt" > "$tmp"
  run bash "$PATH_REDACT" --check "$tmp"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"FOUND"* ]]
  rm "$tmp"
}

@test "check mode passes for clean file" {
  local tmp; tmp=$(mktemp)
  echo "No paths here, just text" > "$tmp"
  run bash "$PATH_REDACT" --check "$tmp"
  [[ "$status" -eq 0 ]]
  rm "$tmp"
}

@test "redacts nonexistent file with error" {
  run bash "$PATH_REDACT" /nonexistent/path.txt
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"ERROR"* ]]
}

@test "empty stdin produces empty output" {
  result=$(echo "" | bash "$PATH_REDACT")
  [[ -z "$result" ]]
}

## Agent result schema tests

@test "agent-result schema exists and is valid JSON" {
  [[ -f "$SCHEMA" ]]
  python3 -c "import json; json.load(open('$SCHEMA'))"
}

@test "schema requires agent, status, timestamps, duration" {
  for field in agent status started_at finished_at duration_ms; do
    grep -q "\"$field\"" "$SCHEMA"
  done
}

@test "schema defines token tracking fields" {
  grep -q '"input"' "$SCHEMA"
  grep -q '"output"' "$SCHEMA"
  grep -q '"cache_read"' "$SCHEMA"
}

@test "schema status enum includes all 5 states" {
  for state in completed failed timeout aborted escalated; do
    grep -q "\"$state\"" "$SCHEMA"
  done
}

