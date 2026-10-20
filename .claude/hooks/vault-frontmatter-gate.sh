#!/usr/bin/env bash
set -uo pipefail
# vault-frontmatter-gate.sh — SPEC-PROJECT-UPDATE F1 + SPEC-128 Slice 1 (fusion)
#
# PreToolUse hook for Edit/Write/MultiEdit. Validates frontmatter on markdown
# files written under any per-project vault, AND enforces N4 isolation
# (cross-project block + N1-in-vault block).
#
# Path scope (gate ACTS on):
#   projects/{slug}_main/{slug}-{user}/vault/**/*.md
#   projects/{slug}/vault/**/*.md
#
# Out of scope (gate is a no-op):
#   - non-vault paths
#   - non-.md files
#   - PROJECT_TEMPLATE/vault/* (template files, intentionally placeholder)
#   - vault/.obsidian/* (Obsidian internals)
#   - vault/README.md (root README, no frontmatter required)
#   - tool inputs without file_path
#
# Validation delegated to scripts/vault-validate.py (rich schema, 10 entity_types,
# title required, per-entity enums, N1-in-vault block, cross-project slug check).
#
# Exit codes:
#   0  — pass (out of scope OR valid frontmatter)
#   2  — BLOCK (frontmatter invalid; stderr explains why)
#
# Opt-out: SAVIA_VAULT_GATE_ENABLED=false  (parity with data-sovereignty-gate.sh)
#
# Refs:
#   - docs/specs/SPEC-PROJECT-UPDATE.spec.md §3.5 (frontmatter schema)
#   - docs/rules/domain/vault-frontmatter-spec.md (SPEC-128 isolation rules)

# Load workspace dir (CLAUDE_PROJECT_DIR / OPENCODE_PROJECT_DIR / fallback).
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SH="$HOOK_DIR/../../scripts/savia-env.sh"
if [[ -f "$ENV_SH" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_SH"
fi
WORKSPACE="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

# Opt-out switch.
[[ "${SAVIA_VAULT_GATE_ENABLED:-true}" == "false" ]] && exit 0

VALIDATOR="$WORKSPACE/scripts/vault-validate.py"
[[ -x "$VALIDATOR" || -f "$VALIDATOR" ]] || exit 0   # no validator → no-op

# Read PreToolUse JSON from stdin (best-effort; never block on read).
INPUT=""
if [[ ! -t 0 ]]; then
  if command -v timeout >/dev/null 2>&1 && timeout --version >/dev/null 2>&1; then
    INPUT=$(timeout 3 cat 2>/dev/null) || true
  else
    INPUT=$(cat 2>/dev/null) || true
  fi
fi
[[ -z "$INPUT" ]] && exit 0

command -v jq >/dev/null 2>&1 || { source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit vault-frontmatter-gate; }

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE_PATH" ]] && exit 0

# Normalize path (resolve ../ + Windows backslashes).
NORM_PATH="$FILE_PATH"
if command -v python3 >/dev/null 2>&1; then
  NORM_PATH=$(python3 -c "import os,sys;print(os.path.normpath(sys.argv[1]).replace(chr(92),'/'))" "$FILE_PATH" 2>/dev/null) || NORM_PATH="$FILE_PATH"
fi

# Scope: only act on .md / .markdown
case "$NORM_PATH" in
  *.md|*.markdown) ;;
  *) exit 0 ;;
esac

# Scope: only act under projects/*/vault/
case "$NORM_PATH" in
  */projects/*/vault/*|projects/*/vault/*) ;;
  *) exit 0 ;;
esac

# SPEC-128 exemptions (path-based, no validation needed).
case "$NORM_PATH" in
  */PROJECT_TEMPLATE/vault/*|PROJECT_TEMPLATE/vault/*) exit 0 ;;
  */vault/.obsidian/*)                                  exit 0 ;;
  */vault/README.md)                                    exit 0 ;;
esac

# Resolve content from tool_input. Edit gives `new_string` (post-edit text);
# Write/MultiEdit give `content`. We validate the post-write text.
CONTENT=$(printf '%s' "$INPUT" | jq -r '
  (.tool_input.content // .tool_input.new_string // .tool_input.text // "")
' 2>/dev/null) || exit 0

# Empty content (e.g. delete) → nothing to validate.
[[ -z "$CONTENT" ]] && exit 0

# Pass content via stdin to the validator with the path hint for inference.
# vault-validate.py infers expected_slug from path → enables cross-project
# block + N1-in-vault block automatically.
if ! command -v python3 >/dev/null 2>&1; then
  exit 0   # python3 absent → no-op (cannot validate)
fi

VALIDATOR_OUT=$(printf '%s' "$CONTENT" | python3 "$VALIDATOR" \
  --check-text - --path "$NORM_PATH" --quiet 2>&1)
RC=$?

if [[ $RC -eq 0 ]]; then
  exit 0
fi

# Block: emit a clear, actionable message on stderr.
{
  echo "BLOCKED [vault-frontmatter-gate]: invalid frontmatter at $NORM_PATH"
  echo "$VALIDATOR_OUT" | sed 's/^/  /'
  echo ""
  echo "Required frontmatter (vault holds only N2-N4b, never N1):"
  echo "  ---"
  echo "  confidentiality: N2|N3|N4|N4b"
  echo "  project: <slug>"
  echo "  entity_type: pbi|decision|meeting|person|risk|spec|session|digest|moc|inbox"
  echo "  title: <title>"
  echo "  created: YYYY-MM-DD"
  echo "  updated: YYYY-MM-DD"
  echo "  ---"
  echo ""
  echo "Templates: projects/{slug}_main/{slug}-{user}/vault/templates/{entity_type}.md"
  echo "Refs: docs/specs/SPEC-PROJECT-UPDATE.spec.md §3.5, docs/rules/domain/vault-frontmatter-spec.md"
} >&2
exit 2
