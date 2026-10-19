#!/usr/bin/env bash
# scripts/opencode-config-validate.sh — SE-253 Slice 1 errata
# Validates opencode.json against known schema keys for OpenCode >=1.16.
# Prevents regressions like the 'catalog' field (not recognized and caused
# server startup failure in 1.16.2).
#
# Usage:
#   ./scripts/opencode-config-validate.sh --check   # block unknown keys (CI)
#   ./scripts/opencode-config-validate.sh --warn    # warn only (pre-push)
#
# Exit codes:
#   0 — all keys valid (or no opencode.json found)
#   1 — unknown top-level keys found (--check mode)
#   2 — invalid JSON or usage error
#
# Environment:
#   OPENCODE_CONFIG="${OPENCODE_CONFIG:-opencode.json}"
set -euo pipefail

MODE="${1:---check}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-opencode.json}"

# ---------------------------------------------------------------------------
# Known valid top-level keys for OpenCode >=1.16
# Source: https://opencode.ai/docs/config/ + empirical verification
# ---------------------------------------------------------------------------
# These are the keys that OpenCode's config parser recognizes.
# Keys NOT in this list will cause silent or crash failures.
readonly VALID_KEYS=(
  '$schema'
  'model'
  'provider'
  'instructions'
  'agent'
  'command'
  'mcp'
  'plugin'
  'permission'
  'autoupdate'
  'snapshot'
  'share'
  'experimental'
  'watch'
  'formatter'
  'theme'
  'keybind'
  'tools'
  'rules'
  'policy'
  'lsp'
  'acp'
  'skill'
  'reference'
  'custom_tool'
  # --- OpenCode V2 (nativas) ---
  'default_agent'
  'permissions'
  'policies'
  'snapshots'
  'update'
  'media'
  'plugins'
  'references'
  'warming'
  'skills'
  'watcher'
  'tool_output'
  'worktree'
  'username'
  'enterprise'
  'server'
  'logLevel'
)

# Colors
RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 [--check|--warn]

Validates opencode.json top-level keys against the OpenCode V1 (>=1.16) and V2 schemas.

  --check   Exit 1 if unknown keys found (CI mode)
  --warn    Warn only, exit 0 (pre-push mode)

Environment:
  OPENCODE_CONFIG   Path to opencode.json (default: opencode.json)
EOF
}

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
if [[ "$MODE" != "--check" && "$MODE" != "--warn" ]]; then
  echo "ERROR: unknown mode '$MODE'" >&2
  usage
  exit 2
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if [[ ! -f "$OPENCODE_CONFIG" ]]; then
  echo "SKIP: $OPENCODE_CONFIG not found"
  exit 0
fi

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 required but not found" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Validate JSON syntax
# ---------------------------------------------------------------------------
if ! python3 -c "import json; json.load(open('$OPENCODE_CONFIG'))" 2>/dev/null; then
  echo -e "${RED}FAIL${NC}: $OPENCODE_CONFIG is not valid JSON"
  exit 2
fi

# ---------------------------------------------------------------------------
# Extract unique top-level keys (excluding $schema which is always valid)
# ---------------------------------------------------------------------------
readarray -t TOP_KEYS < <(
  python3 -c "
import json
with open('$OPENCODE_CONFIG') as f:
    d = json.load(f)
for k in sorted(d.keys()):
    print(k)
" 2>/dev/null
)

if [[ ${#TOP_KEYS[@]} -eq 0 ]]; then
  echo -e "${GRN}PASS${NC}: $OPENCODE_CONFIG is valid JSON with no keys"
  exit 0
fi

# Build lookup set
declare -A VALID_MAP
for key in "${VALID_KEYS[@]}"; do
  VALID_MAP["$key"]=1
done

UNKNOWN=()
WARNED=0
ERRORS=0

for key in "${TOP_KEYS[@]}"; do
  # Extensión propia de Savia (ignorada por V1 y V2; nunca se envía al proveedor).
  if [[ "$key" == x_savia_* ]]; then
    continue
  fi
  if [[ -z "${VALID_MAP[$key]:-}" ]]; then
    UNKNOWN+=("$key")
    ERRORS=$((ERRORS + 1))
    echo -e "${RED}UNKNOWN KEY${NC}: '$key' is not a recognized OpenCode config key"
    echo "  Valid keys: ${VALID_KEYS[*]}"
  fi
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "═══════════════════════════════════════════════════"
  echo -e "${RED}${ERRORS} unknown key(s)${NC} found in $OPENCODE_CONFIG"
  echo "These keys are NOT part of the OpenCode >=1.16 config schema."
  echo "They may cause silent failures or server crashes."
  if [[ "$MODE" == "--check" ]]; then
    echo "BLOCKED: remove unknown keys before merging."
    exit 1
  else
    echo "WARNING: fix before committing."
    exit 0
  fi
else
  echo -e "${GRN}PASS${NC}: all ${#TOP_KEYS[@]} top-level keys in $OPENCODE_CONFIG are valid"
fi
