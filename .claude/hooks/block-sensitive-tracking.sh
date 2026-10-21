#!/bin/bash
set -uo pipefail
# block-sensitive-tracking.sh — SE-258 Slice 1
# Bloquea git add / Write / Edit de rutas declaradas N3+
# Perfil: security

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

# Master switch
if [[ "${SAVIA_SENSITIVE_TRACKING:-on}" == "off" ]]; then
  exit 0
fi

CONFIG="${CLAUDE_PROJECT_DIR:-.}/config/sensitive-paths.yaml"
if [[ ! -f "$CONFIG" ]]; then
  exit 0
fi

INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi

if ! command -v jq &>/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit block-sensitive-tracking
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL=""
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""

if [ "$TOOL" != "Edit" ] && [ "$TOOL" != "Write" ]; then
  exit 0
fi

[ -z "$FILE_PATH" ] && exit 0

ALLOWLIST_MATCH=0
while IFS= read -r line; do
  pattern=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*$//')
  [[ -z "$pattern" ]] && continue
  case "$FILE_PATH" in
    $pattern) ALLOWLIST_MATCH=1; break ;;
  esac
done < <(sed -n '/^allowlist:/,/^$/p' "$CONFIG" | grep '^[[:space:]]*-[[:space:]]' | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^"//; s/"$//' || true)

if [ "$ALLOWLIST_MATCH" -eq 1 ]; then
  exit 0
fi

# Extract patterns from all N-level sections individually to avoid false matches
# when new keys are added between levels and allowlist sections
BLOCKED=0
collect_level_paths() {
  local level="$1"
  sed -n "/^  ${level}:/,/^  [A-Za-z]/p" "$CONFIG" | grep '^[[:space:]]*-[[:space:]]' | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^"//; s/"$//'
}

for level in N4 N3 N2; do
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    case "$FILE_PATH" in
      $pattern)
        BLOCKED=1
        break 2
        ;;
    esac
  done < <(collect_level_paths "$level")
done

if [ "$BLOCKED" -eq 1 ]; then
  echo "BLOCKED [sensitive-tracking]: '$FILE_PATH' matches a protected path. This file must NOT be tracked in the public repo. If this is a test fixture, add the path to the allowlist in config/sensitive-paths.yaml." >&2
  exit 2
fi

exit 0
