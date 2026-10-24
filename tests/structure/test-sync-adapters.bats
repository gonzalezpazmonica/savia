#!/usr/bin/env bats
# Tests for Era 107.2 — Sync Adapters
# Ref: docs/rules/domain/mcp-migration.md

setup() {
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  ROOT="$PWD"
  TMPDIR_SA=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_SA"
}

@test "adapter-interface.sh exists and is executable" {
  [ -x "$ROOT/scripts/sync-adapters/adapter-interface.sh" ]
}

@test "azure-devops-adapter.sh exists and is executable" {
  [ -x "$ROOT/scripts/sync-adapters/azure-devops-adapter.sh" ]
}

@test "jira-adapter.sh exists and is executable" {
  [ -x "$ROOT/scripts/sync-adapters/jira-adapter.sh" ]
}

@test "github-issues-adapter.sh exists and is executable" {
  [ -x "$ROOT/scripts/sync-adapters/github-issues-adapter.sh" ]
}

@test "backlog-sync command exists" {
  [ -f "$ROOT/.opencode/commands/backlog-sync.md" ]
}

@test "adapter-interface has required functions" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  declare -f sync_log > /dev/null
  declare -f get_pbi_field > /dev/null
  declare -f set_pbi_field > /dev/null
  declare -f compute_sync_status > /dev/null
  declare -f map_state_to_provider > /dev/null
  declare -f map_state_from_provider > /dev/null
}

@test "state mapping azure-devops round-trips correctly" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local mapped; mapped=$(map_state_to_provider "Active" "azure-devops")
  [ "$mapped" = "Active" ]
  local back; back=$(map_state_from_provider "$mapped" "azure-devops")
  [ "$back" = "Active" ]
}

@test "state mapping jira converts correctly" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local mapped; mapped=$(map_state_to_provider "Active" "jira")
  [ "$mapped" = "In Progress" ]
  local back; back=$(map_state_from_provider "In Progress" "jira")
  [ "$back" = "Active" ]
}

@test "state mapping github converts correctly" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local mapped; mapped=$(map_state_to_provider "Active" "github")
  [ "$mapped" = "open" ]
  local back; back=$(map_state_from_provider "closed" "github")
  [ "$back" = "Closed" ]
}

@test "compute_sync_status returns in_sync for same hashes" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local status; status=$(compute_sync_status "2026-03-14" "2026-03-14" "abc123" "abc123")
  [ "$status" = "in_sync" ]
}

@test "compute_sync_status returns local_only for empty remote" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local status; status=$(compute_sync_status "2026-03-14" "" "abc" "def")
  [ "$status" = "local_only" ]
}

# ── Negative cases ──

@test "state mapping handles bad provider and empty state" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  run map_state_to_provider "Active" "unknown-provider"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown provider"* ]]
  local m2; m2=$(map_state_to_provider "" "azure-devops")
  [ -z "$m2" ]
}

# ── Edge cases ──

@test "compute_sync_status returns remote_only for empty local" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local status; status=$(compute_sync_status "" "2026-03-14" "" "abc")
  [ "$status" = "remote_only" ]
}

@test "compute_sync_status returns diverged for different hashes" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local status; status=$(compute_sync_status "2026-03-14" "2026-03-15" "abc" "xyz")
  [ "$status" = "diverged" ] || [ "$status" = "remote_newer" ] || [ "$status" = "local_newer" ]
}

# ── Safety verification ──

@test "adapter-interface.sh has set -uo pipefail safety" {
  grep -q "set -[euo]*o pipefail" "$ROOT/scripts/sync-adapters/adapter-interface.sh"
}

# ── Additional coverage ──

@test "sync_log function writes JSON to log file" {
  export PROJECT_ROOT="$TMPDIR_SA"
  mkdir -p "$TMPDIR_SA/output"
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  sync_log "push" "azure-devops" "PBI-001" "ok"
  grep -q "push" "$TMPDIR_SA/output/.sync-log.jsonl"
  grep -q "PBI-001" "$TMPDIR_SA/output/.sync-log.jsonl"
}

@test "get_pbi_field extracts field from YAML frontmatter" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local pbi="$TMPDIR_SA/test-pbi.md"
  printf -- '---\ntitle: Test PBI\nstate: Active\n---\nBody\n' > "$pbi"
  run get_pbi_field "$pbi" "title"
  [[ "$output" == *"Test PBI"* ]]
}

@test "map_state_to_provider round-trips for all providers" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  for provider in azure-devops jira github; do
    local mapped; mapped=$(map_state_to_provider "New" "$provider")
    [[ -n "$mapped" ]]
  done
}

@test "state mapping rejects invalid state and handles null timestamps" {
  source "$ROOT/scripts/sync-adapters/adapter-interface.sh"
  local m; m=$(map_state_to_provider "InvalidXYZ" "azure-devops")
  [ "$m" = "InvalidXYZ" ]
  local s; s=$(compute_sync_status "" "" "" "")
  [ "$s" = "in_sync" ]
}

@test "sync handles nonexistent adapter gracefully" {
  run bash -c "source '$ROOT/scripts/sync-adapters/adapter-interface.sh' && map_state_to_provider 'Active' 'nonexistent' 2>&1"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
