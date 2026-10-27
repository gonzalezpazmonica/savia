#!/usr/bin/env bash
set -uo pipefail
# protected-job-guard.sh — SPEC-161 PROTECTED_JOB_NAMES
# PreToolUse hook on Task tool.
# Blocks invocation of costly agents from autonomous loops unless override env is set.
# Fail-safe: YAML missing → exit 0 with WARN (never break interactive sessions).

SAVIA_ENV="$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
if [[ -r "$SAVIA_ENV" ]]; then
  source "$SAVIA_ENV"
fi
PROJECT_DIR="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

YAML="$PROJECT_DIR/.opencode/protected-jobs.yaml"

# Fail-safe: YAML missing → permit with WARN
if [[ ! -r "$YAML" ]]; then
  echo "[protected-job-guard] WARN: $YAML not found — guard inactive" >&2
  exit 0
fi

# Read hook input from stdin
INPUT=""
if [[ ! -t 0 ]]; then
  if command -v timeout >/dev/null 2>&1 && timeout --version >/dev/null 2>&1; then
    INPUT=$(timeout 3 cat 2>/dev/null) || true
  else
    INPUT=$(cat 2>/dev/null) || true
  fi
fi
[[ -z "$INPUT" ]] && exit 0

# Only apply to Task tool invocations
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[[ "$TOOL_NAME" != "Task" && "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
[[ -z "$SUBAGENT" ]] && exit 0

# Detect autonomous context
AUTONOMOUS=0
if [[ "${SAVIA_AUTONOMOUS_MODE:-0}" == "1" ]]; then
  AUTONOMOUS=1
elif [[ -n "${SAVIA_AUTONOMOUS_SKILL:-}" ]]; then
  AUTONOMOUS=1
elif [[ "${SAVIA_DELEGATION_DEPTH:-0}" -ge 1 ]]; then
  AUTONOMOUS=1
elif [[ -n "${SAVIA_LOOP_CONTEXT:-}" ]]; then
  # Los bucles autónomos (overnight-sprint-loop.sh y el auxiliar de recursión) exportan este contexto.
  AUTONOMOUS=1
fi
[[ "$AUTONOMOUS" -eq 0 ]] && exit 0

# Override gate: explicit human handle required
OVERRIDE_VAR=$(grep -E '^override_env:' "$YAML" | sed -E 's/^override_env:[[:space:]]*//')
OVERRIDE_VAR="${OVERRIDE_VAR:-SAVIA_PROTECTED_JOB_OVERRIDE}"
OVERRIDE_VALUE="${!OVERRIDE_VAR:-}"
if [[ -n "$OVERRIDE_VALUE" ]]; then
  echo "[protected-job-guard] OVERRIDE active ($OVERRIDE_VAR=$OVERRIDE_VALUE) — allowing $SUBAGENT" >&2
  exit 0
fi

# Extract protected_agents list from YAML (lines starting with "  - " under protected_agents)
PROTECTED=$(awk '
  /^protected_agents:/ { in_list=1; next }
  /^[a-z_]+:/ { in_list=0 }
  in_list && /^[[:space:]]*-[[:space:]]+/ { sub(/^[[:space:]]*-[[:space:]]+/, ""); print }
' "$YAML")

if printf '%s\n' "$PROTECTED" | grep -qxF "$SUBAGENT"; then
  cat >&2 <<MSG
BLOCKED [protected-job-guard]: agent '$SUBAGENT' is in PROTECTED_JOB_NAMES.
  Autonomous context detected (SAVIA_AUTONOMOUS_MODE=${SAVIA_AUTONOMOUS_MODE:-unset}, SAVIA_AUTONOMOUS_SKILL=${SAVIA_AUTONOMOUS_SKILL:-unset}, depth=${SAVIA_DELEGATION_DEPTH:-0}).
  Reason: costly agent (heavy tier) — running unsupervised burns 80-120k tokens per invocation.
  To override: export $OVERRIDE_VAR=@your-handle (requires explicit human consent).
  Allowlist: $PROJECT_DIR/.opencode/protected-jobs.yaml
  Spec: docs/propuestas/SPEC-161-protected-job-names.md
MSG
  exit 2
fi

exit 0
