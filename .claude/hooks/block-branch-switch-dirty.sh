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

# Extract command + session cwd from hook JSON (two lines: command, cwd)
PARSED=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
cmd = d.get('tool_input', {}).get('command', '') or ''
print(cmd.replace(chr(10), ' '))
print(d.get('cwd', '') or '')
" 2>/dev/null)
COMMAND=$(echo "$PARSED" | sed -n '1p')
SESSION_CWD=$(echo "$PARSED" | sed -n '2p')
[[ -z "$COMMAND" ]] && exit 0

# Locate the branch-changing invocation itself: `git [-C <dir>] (checkout|switch) <args>`,
# each one with its OWN arguments (up to the next ; & |). Only THAT invocation's -C
# counts — a foreign `git -C X status` elsewhere in the command must not decide the
# target repo. A file restore is `git checkout [<opciones>] [<tree-ish>] -- <rutas>`:
# a standalone `--` followed by at least one path (`--merge`, `--ours` or a tree-ish
# before it included). It never moves HEAD, so it is skipped — but a restore earlier
# in the command does not excuse a later `git checkout <rama>`.
INVOCATION_RX='(^|[^[:alnum:]_./-])git[[:space:]]+(-C[[:space:]]+([^[:space:];&|]+)[[:space:]]+)?(checkout|switch)[[:space:]]+([^;&|]*)'
SCAN="$COMMAND"
CONSUMED=""
FOUND=0
while [[ "$SCAN" =~ $INVOCATION_RX ]]; do
  WHOLE="${BASH_REMATCH[0]}"
  GIT_C_DIR="${BASH_REMATCH[3]}"
  GIT_SUBCMD="${BASH_REMATCH[4]}"
  GIT_ARGS="${BASH_REMATCH[5]}"
  BEFORE="${SCAN%%"$WHOLE"*}"
  if [[ "$GIT_SUBCMD" == "checkout" && " $GIT_ARGS" =~ [[:space:]]--[[:space:]]+[^[:space:]] ]]; then
    CONSUMED+="$BEFORE$WHOLE"
    SCAN="${SCAN#*"$WHOLE"}"
    continue
  fi
  FOUND=1
  break
done
[[ $FOUND -eq 1 ]] || exit 0
PREFIX="$CONSUMED$BEFORE"   # text before the branch-changing git invocation

# Last `cd <dir> &&|;` BEFORE the git invocation (cd A && cd B && git switch → B)
CD_DIR=""
REST="$PREFIX"
while [[ "$REST" =~ (^|[[:space:]]|\&\&|\;)cd[[:space:]]+([^[:space:]\;\&\|]+)[[:space:]]*(\&\&|\;)(.*)$ ]]; do
  CD_DIR="${BASH_REMATCH[2]}"
  REST="${BASH_REMATCH[4]}"
done

# Resolve the repo the command actually targets. The hook's own cwd is the
# workspace, NOT necessarily the repo the command runs in (cd X && git switch).
# Priority: -C of the invocation > last cd before it > session cwd (hook JSON) > hook cwd.
FALLBACK_DIR="${SESSION_CWD:-$PWD}"
TARGET_DIR=""
if [[ -n "$GIT_C_DIR" ]]; then
  TARGET_DIR="$GIT_C_DIR"
elif [[ -n "$CD_DIR" ]]; then
  TARGET_DIR="$CD_DIR"
fi
# Strip surrounding quotes, expand ~ / $HOME, resolve relative to session cwd
TARGET_DIR="${TARGET_DIR%\"}"; TARGET_DIR="${TARGET_DIR#\"}"
TARGET_DIR="${TARGET_DIR%\'}"; TARGET_DIR="${TARGET_DIR#\'}"
TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
TARGET_DIR="${TARGET_DIR/#\$HOME/$HOME}"
# Anything we cannot expand statically ($VAR, $(...), backticks) → conservative fallback
if [[ "$TARGET_DIR" == *'$'* || "$TARGET_DIR" == *'`'* ]]; then
  TARGET_DIR=""
fi
if [[ -n "$TARGET_DIR" && "$TARGET_DIR" != /* ]]; then
  TARGET_DIR="$FALLBACK_DIR/$TARGET_DIR"
fi
# Unresolvable or non-existent target → fall back to the session cwd, never pass through
if [[ -z "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
  TARGET_DIR="$FALLBACK_DIR"
fi
[[ -d "$TARGET_DIR" ]] || exit 0

# Not a git repo → nothing to protect
TARGET_ROOT=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Check for uncommitted changes (tracked + untracked) IN THE TARGET REPO
DIRTY=$(git -C "$TARGET_DIR" status --porcelain 2>/dev/null | head -20)
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
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if [[ "$(cd "$TARGET_ROOT" && pwd -P)" == "$WORKSPACE_ROOT" && -f "$WORKSPACE_ROOT/.pr-summary.md" ]]; then
  rm -f "$WORKSPACE_ROOT/.pr-summary.md"
fi

exit 0
