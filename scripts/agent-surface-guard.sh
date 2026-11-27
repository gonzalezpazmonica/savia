#!/usr/bin/env bash
# agent-surface-guard.sh — SE-217 Slice 3: declared editable surface for agent runs
# Ref: docs/propuestas/SE-217-autoresearch-patterns.md
set -uo pipefail

# ── Path resolution ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}}}"
EVO_DIR="${SAVIA_EVO_DIR:-${WORKSPACE_DIR}/.evo}"

# ── Default surface (safe) ────────────────────────────────────────────────────
DEFAULT_EDITABLE="output/ projects/ tests/"
DEFAULT_READONLY="CLAUDE.md opencode.json .claude/ scripts/ docs/rules/"
DEFAULT_FORBIDDEN=".git/ .confidentiality-signature .claude/settings.json"

# ── Helpers ──────────────────────────────────────────────────────────────────
_now()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_usage() {
  cat >&2 <<'EOF'
Usage:
  agent-surface-guard.sh declare --run-id ID --editable "..." --readonly "..." --forbidden "..."
  agent-surface-guard.sh verify [--run-id ID]
  agent-surface-guard.sh context --run-id ID
  agent-surface-guard.sh list
EOF
  exit 1
}

# Check whether a file path matches any pattern in a space-separated list.
# Patterns ending in / are treated as directory prefixes.
_matches_surface() {
  local file="$1"
  local patterns="$2"
  local p
  for p in $patterns; do
    local pbase="${p%/}"
    if [[ "$file" == "$pbase" || "$file" == "$pbase/"* ]]; then
      return 0
    fi
  done
  return 1
}

# ── Subcommand: declare ───────────────────────────────────────────────────────
cmd_declare() {
  local run_id="" editable="" readonly_list="" forbidden=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id)    run_id="$2";        shift 2 ;;
      --editable)  editable="$2";      shift 2 ;;
      --readonly)  readonly_list="$2"; shift 2 ;;
      --forbidden) forbidden="$2";     shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; _usage ;;
    esac
  done

  if [[ -z "$run_id" ]]; then
    echo "ERROR: --run-id is required for declare" >&2
    exit 1
  fi

  local run_dir="${EVO_DIR}/${run_id}"
  mkdir -p "$run_dir"

  # Build a JSON array from a space-separated string
  _to_json_array() {
    local input="$1"
    local items=()
    # Read words; handle empty input gracefully
    if [[ -n "$input" ]]; then
      read -ra items <<< "$input"
    fi
    local json="["
    local first=1
    local item
    for item in "${items[@]+"${items[@]}"}"; do
      [[ -z "$item" ]] && continue
      [[ $first -eq 1 ]] && first=0 || json+=","
      json+="\"${item}\""
    done
    json+="]"
    printf '%s' "$json"
  }

  local editable_json readonly_json forbidden_json
  editable_json="$(_to_json_array "${editable:-}")"
  readonly_json="$(_to_json_array "${readonly_list:-}")"
  forbidden_json="$(_to_json_array "${forbidden:-}")"
  local ts
  ts="$(_now)"

  printf '{\n  "run_id": "%s",\n  "declared_at": "%s",\n  "editable": %s,\n  "readonly": %s,\n  "forbidden": %s\n}\n' \
    "$run_id" "$ts" "$editable_json" "$readonly_json" "$forbidden_json" \
    > "${run_dir}/surface.json"

  echo "Surface declared for run '${run_id}' -> ${run_dir}/surface.json"
}

# ── Subcommand: verify ────────────────────────────────────────────────────────
cmd_verify() {
  local run_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; _usage ;;
    esac
  done

  local editable readonly_list forbidden

  if [[ -z "$run_id" ]]; then
    editable="$DEFAULT_EDITABLE"
    readonly_list="$DEFAULT_READONLY"
    forbidden="$DEFAULT_FORBIDDEN"
  else
    local surface_file="${EVO_DIR}/${run_id}/surface.json"
    if [[ ! -f "$surface_file" ]]; then
      echo "ERROR: No surface.json found for run '${run_id}' at ${surface_file}" >&2
      exit 1
    fi
    editable="$(python3 -c "
import json
d = json.load(open('${surface_file}'))
print(' '.join(d.get('editable', [])))
")"
    readonly_list="$(python3 -c "
import json
d = json.load(open('${surface_file}'))
print(' '.join(d.get('readonly', [])))
")"
    forbidden="$(python3 -c "
import json
d = json.load(open('${surface_file}'))
print(' '.join(d.get('forbidden', [])))
")"
  fi

  local staged_files
  staged_files="$(git -C "$WORKSPACE_DIR" diff --cached --name-only 2>/dev/null || true)"

  if [[ -z "$staged_files" ]]; then
    exit 0
  fi

  local exit_code=0
  local file

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    if _matches_surface "$file" "$forbidden"; then
      echo "SURFACE VIOLATION: '${file}' is in FORBIDDEN surface" >&2
      exit_code=1
      continue
    fi

    # READONLY has precedence over EDITABLE
    if _matches_surface "$file" "$readonly_list"; then
      echo "SURFACE VIOLATION: '${file}' is in READONLY surface" >&2
      exit_code=1
      continue
    fi

    if ! _matches_surface "$file" "$editable"; then
      echo "SURFACE VIOLATION: '${file}' is not in any declared EDITABLE surface" >&2
      exit_code=1
    fi

  done <<< "$staged_files"

  exit $exit_code
}

# ── Subcommand: context ───────────────────────────────────────────────────────
cmd_context() {
  local run_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; _usage ;;
    esac
  done

  if [[ -z "$run_id" ]]; then
    echo "ERROR: --run-id is required for context" >&2
    exit 1
  fi

  local surface_file="${EVO_DIR}/${run_id}/surface.json"
  if [[ ! -f "$surface_file" ]]; then
    echo "ERROR: No surface.json found for run '${run_id}' at ${surface_file}" >&2
    exit 1
  fi

  python3 - "$surface_file" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
editable  = ", ".join(d.get("editable", []))  or "(none)"
readonly  = ", ".join(d.get("readonly", []))  or "(none)"
forbidden = ", ".join(d.get("forbidden", [])) or "(none)"
print("## Superficie de edicion")
print(f"EDITABLE:  {editable}")
print(f"READ-ONLY: {readonly}")
print(f"FORBIDDEN: {forbidden}")
PYEOF
}

# ── Subcommand: list ──────────────────────────────────────────────────────────
cmd_list() {
  if [[ ! -d "$EVO_DIR" ]]; then
    echo "(no surfaces declared yet)"
    return
  fi

  local found=0
  local surface_file
  for surface_file in "${EVO_DIR}"/*/surface.json; do
    [[ -f "$surface_file" ]] || continue
    found=1
    local run_id declared_at
    # The path goes in as argv: a directory name under .evo is never Python source.
    run_id="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("run_id","?"))' "$surface_file")"
    declared_at="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("declared_at","?"))' "$surface_file")"
    printf '%s  %s\n' "$run_id" "$declared_at"
  done

  if [[ $found -eq 0 ]]; then
    echo "(no surfaces declared yet)"
  fi
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
SUBCMD="${1:-}"
[[ -z "$SUBCMD" ]] && _usage
shift

case "$SUBCMD" in
  declare) cmd_declare "$@" ;;
  verify)  cmd_verify  "$@" ;;
  context) cmd_context "$@" ;;
  list)    cmd_list    "$@" ;;
  *)
    echo "ERROR: Unknown subcommand: '${SUBCMD}'" >&2
    _usage
    ;;
esac
