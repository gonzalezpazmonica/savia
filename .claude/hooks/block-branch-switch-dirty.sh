#!/usr/bin/env bash
# block-branch-switch-dirty.sh — Prevent branch switch with uncommitted changes
# Tier: security (always active — protects against data loss)
# PreToolUse on Bash — intercepts git checkout/switch commands
set -uo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

# Read hook input
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(timeout 3 cat 2>/dev/null) || true
fi
[[ -z "$INPUT" ]] && exit 0

# Preserve newlines: each invocation has its own arguments and destination.
# The shared lexer distinguishes git checkout -- paths from branch changes,
# including redirections, comments and quoted -C paths.
COMMAND=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
cmd = d.get("tool_input", {}).get("command", "") or ""
if not isinstance(cmd, str): raise ValueError("command")
sys.stdout.write(cmd)
' 2>/dev/null) || { echo "BLOQUEADO: entrada de hook inválida." >&2; exit 2; }
[[ -z "$COMMAND" ]] && exit 0
SESSION_CWD=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
cwd = json.load(sys.stdin).get("cwd", "") or ""
if not isinstance(cwd, str): raise ValueError("cwd")
sys.stdout.write(cwd)
' 2>/dev/null) || { echo "BLOQUEADO: cwd de hook inválido." >&2; exit 2; }
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TARGETS=$(printf '%s' "$COMMAND" | timeout 5 python3   "$WORKSPACE_ROOT/scripts/lib/git_op_targets.py" --switch "${SESSION_CWD:-$PWD}" 2>/dev/null) || {
  echo "BLOQUEADO: no se pudo resolver el destino del cambio de rama." >&2; exit 2;
}
[[ -z "$TARGETS" ]] && exit 0
CLEAR_SUMMARY=0
DIRTY=""
while IFS= read -r TARGET; do
  [[ "$TARGET" == $'switch\t'* ]] || {
    echo "BLOQUEADO: destino de cambio de rama inválido." >&2; exit 2;
  }
  TARGET_DIR="${TARGET#*$'\t'}"
  [[ -n "$TARGET_DIR" ]] || {
    echo "BLOQUEADO: destino de cambio de rama desconocido." >&2; exit 2;
  }
  [[ -d "$TARGET_DIR" ]] || continue
  TARGET_ROOT=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null) || continue
  DIRTY=$(git -C "$TARGET_DIR" status --porcelain 2>/dev/null) || {
    echo "BLOQUEADO: no se pudo comprobar el estado del repo." >&2; exit 2;
  }
  [[ -n "$DIRTY" ]] && break
  if [[ "$(cd "$TARGET_ROOT" && pwd -P)" == "$WORKSPACE_ROOT" ]]; then
    CLEAR_SUMMARY=1
  fi
done <<< "$TARGETS"
if [[ -n "$DIRTY" ]]; then
  # grep -c prints the count even when it is 0 (and exits 1) — never append a second "0"
  TRACKED=$(echo "$DIRTY" | grep -cE '^ M| ^M|^MM|^A |^D ' || true)
  UNTRACKED=$(echo "$DIRTY" | grep -c '^??' || true)

  echo "BLOQUEADO: Cambio de rama con cambios sin commitear." >&2
  echo "" >&2
  echo "  Repo: $TARGET_ROOT" >&2
  echo "  Ficheros modificados: $TRACKED" >&2
  echo "  Ficheros sin rastrear: $UNTRACKED" >&2
  echo "" >&2
  echo "  Opciones:" >&2
  echo "    1. git add + git commit (recomendado)" >&2
  echo "    2. git stash -u (temporal)" >&2
  echo "" >&2
  echo "  NUNCA cambiar de rama sin guardar los cambios." >&2
  exit 2
fi

# SE-300: clear stale per-branch PR summary on legitimate branch switch so a
# previous PR's natural-language paragraph does not leak into the next PR body.
# Only when the switch happens in THIS workspace — never touch another repo's state.
if [[ "$CLEAR_SUMMARY" -eq 1 && -f "$WORKSPACE_ROOT/.pr-summary.md" ]]; then
  rm -f "$WORKSPACE_ROOT/.pr-summary.md"
fi

exit 0
