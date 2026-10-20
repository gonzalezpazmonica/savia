#!/usr/bin/env bash
# mock-env.sh — Reusable mock environment library for pm-workspace scripts
# Source this from any script that needs to run without external dependencies.
#
# Usage:
#   source "$(dirname "$0")/lib/mock-env.sh"
#   mock_init              # Set up mock environment
#   mock_azure_response    # Returns mock Azure DevOps JSON
#   mock_mcp_response      # Returns mock MCP server JSON
#   is_mock_mode           # Returns 0 if in mock mode

MOCK_MODE="${PM_MOCK:-false}"
MOCK_DATA_DIR="${PM_MOCK_DATA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/projects/sala-reservas/test-data}"

mock_init() {
  MOCK_MODE="true"
  export PM_MOCK="true"
  export PM_MOCK_DATA="$MOCK_DATA_DIR"
}

is_mock_mode() {
  [ "$MOCK_MODE" = "true" ]
}

mock_azure_response() {
  local endpoint="${1:-workitems}"
  local mock_file="$MOCK_DATA_DIR/mock-${endpoint}.json"
  if [ -f "$mock_file" ]; then
    cat "$mock_file"
  else
    echo '{"value": [], "count": 0}'
  fi
}

mock_mcp_response() {
  local tool="${1:-query}"
  echo "{\"mock\": true, \"tool\": \"$tool\", \"result\": {\"status\": \"ok\", \"data\": []}}"
}

mock_sprint_data() {
  cat << 'JSON'
{
  "id": "mock-sprint-42",
  "name": "Sprint 42",
  "startDate": "2026-03-01T00:00:00Z",
  "endDate": "2026-03-14T00:00:00Z",
  "state": "current",
  "workItems": {
    "total": 15,
    "completed": 8,
    "inProgress": 4,
    "todo": 3
  },
  "velocity": {
    "planned": 34,
    "completed": 21,
    "remaining": 13
  }
}
JSON
}

mock_team_data() {
  cat << 'JSON'
{
  "members": [
    {"name": "Dev A", "capacity": 6, "role": "developer"},
    {"name": "Dev B", "capacity": 6, "role": "developer"},
    {"name": "QA C", "capacity": 6, "role": "tester"},
    {"name": "PM D", "capacity": 4, "role": "pm"}
  ],
  "totalCapacity": 22,
  "sprintDays": 10
}
JSON
}

# Auto-detect mock mode from environment or --mock flag
for arg in "$@"; do
  [ "$arg" = "--mock" ] && mock_init
done

# git_env_clean — aísla el proceso del repo/config git del entorno.
# Un agente en un worktree exporta GIT_DIR/GIT_WORK_TREE; sin limpiar, `git init`/`git commit`
# de un test en un repo temporal operan sobre el repo real (commits "init", core.worktree).
# Uso: source scripts/lib/mock-env.sh; git_env_clean [--isolate-config]
git_env_clean() {
  local v
  for v in $(compgen -e | grep -E '^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|NAMESPACE|PREFIX|CEILING_DIRECTORIES|CONFIG|CONFIG_COUNT|CONFIG_PARAMETERS|CONFIG_KEY_[0-9]+|CONFIG_VALUE_[0-9]+)$'); do
    unset "$v"
  done
  if [[ "${1:-}" == "--isolate-config" ]]; then
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=s GIT_AUTHOR_EMAIL=s@s GIT_COMMITTER_NAME=s GIT_COMMITTER_EMAIL=s@s
  fi
}
