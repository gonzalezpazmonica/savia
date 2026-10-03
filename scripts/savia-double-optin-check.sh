#!/usr/bin/env bash
# savia-double-optin-check.sh — SPEC-186 (Era 199 Wave 1)
#
# Double opt-in gate for autonomous skills. Requires BOTH:
#   1. A persistent environment variable (e.g. OVERNIGHT_SPRINT_ENABLED=true)
#   2. The explicit flag --confirm-autonomous in the invocation
#
# Closes the vector of accidental activation by inherited env vars in
# persistent shells or CI runners.
#
# Usage:
#   bash scripts/savia-double-optin-check.sh --skill <name> [--confirm-autonomous] [...]
#
# Skills covered:
#   overnight-sprint        -> OVERNIGHT_SPRINT_ENABLED
#   code-improvement-loop   -> CODE_IMPROVEMENT_LOOP_ENABLED
#   adversarial-security    -> ADVERSARIAL_SECURITY_ENABLED
#   tech-research-agent     -> TECH_RESEARCH_AGENT_ENABLED
#   savia-dual              -> SAVIA_DUAL_FAILOVER_ENABLED
#
# Exit codes:
#   0  both confirmations present (or test bypass active)
#   1  missing env var, missing flag, or both
#   2  invalid invocation (missing --skill, unknown skill, bad arg)
#
# Test bypass: SAVIA_TESTING=1 + BATS_TEST_NAME set -> exit 0 silently.
# Ref: SPEC-186 (Era 199), autonomous-safety.md

set -uo pipefail

VERSION="1.0.0"
# Rutas ancladas a la raíz del repo, nunca al cwd: un scripts/operator-grant.sh
# plantado en el directorio de trabajo concedería el factor "intent".
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_LOG="${SAVIA_OPTIN_AUDIT_LOG:-$REPO_ROOT/output/agent-runs/optin-audit.log}"

usage() {
  cat <<'USAGE'
Usage: savia-double-optin-check.sh --skill <name> [--confirm-autonomous] [extra args ignored]

Required:
  --skill <name>         Skill name. One of: overnight-sprint, code-improvement-loop,
                         adversarial-security, tech-research-agent, savia-dual.

Confirmation factors (BOTH required for exit 0):
  --confirm-autonomous   Explicit flag confirming autonomous run.
  ENV VAR                Skill-specific (uppercase + _ENABLED). Must equal "true".

Other:
  --help                 Show this message.
  --version              Show version.

Exit: 0 ok | 1 missing factor | 2 invalid invocation
USAGE
}

# Map skill name -> env var name.
env_var_for_skill() {
  case "$1" in
    overnight-sprint)       echo "OVERNIGHT_SPRINT_ENABLED" ;;
    code-improvement-loop)  echo "CODE_IMPROVEMENT_LOOP_ENABLED" ;;
    adversarial-security)   echo "ADVERSARIAL_SECURITY_ENABLED" ;;
    tech-research-agent)    echo "TECH_RESEARCH_AGENT_ENABLED" ;;
    savia-dual)             echo "SAVIA_DUAL_FAILOVER_ENABLED" ;;
    *) return 1 ;;
  esac
}

# Parse args. Unknown args are tolerated (passthrough from caller).
SKILL=""
HAS_FLAG=0
EXPECT_SKILL_VALUE=0
for arg in "$@"; do
  if [[ $EXPECT_SKILL_VALUE -eq 1 ]]; then
    SKILL="$arg"
    EXPECT_SKILL_VALUE=0
    continue
  fi
  case "$arg" in
    --help)                usage; exit 0 ;;
    --version)             echo "$VERSION"; exit 0 ;;
    --skill)               EXPECT_SKILL_VALUE=1 ;;
    --skill=*)             SKILL="${arg#--skill=}" ;;
    --confirm-autonomous)  HAS_FLAG=1 ;;
    *) ;;
  esac
done

if [[ -z "$SKILL" ]]; then
  echo "ERROR: --skill <name> is required" >&2
  usage >&2
  exit 2
fi

ENV_NAME="$(env_var_for_skill "$SKILL")" || {
  echo "ERROR: unknown skill '$SKILL'. See --help for list." >&2
  exit 2
}

# Test bypass: ONLY when SAVIA_TESTING=1 AND running inside BATS.
if [[ "${SAVIA_TESTING:-0}" == "1" && -n "${BATS_TEST_NAME:-}" ]]; then
  exit 0
fi

# Resolve env var value via indirection.
ENV_VAL="${!ENV_NAME:-}"

HAS_ENV=0
if [[ "$ENV_VAL" == "true" ]]; then
  HAS_ENV=1
fi

# SE-343: factor 1 ("intent") is also satisfied by a valid operator grant
# issued on the operator's express request (no manual env-var setup needed).
# Scopes map: skill X -> autonomy:X.
if [[ $HAS_ENV -eq 0 ]]; then
  GRANT_SCOPE="autonomy:${SKILL}"
  if bash "$REPO_ROOT/scripts/operator-grant.sh" check --scope "$GRANT_SCOPE" >/dev/null 2>&1; then
    HAS_ENV=1
  fi
fi

# Audit logging (best-effort, never fail the gate on log errors).
log_attempt() {
  local verdict="$1"
  local ts user
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
  user="${USER:-unknown}"
  local dir
  dir="$(dirname "$AUDIT_LOG")"
  if mkdir -p "$dir" 2>/dev/null; then
    printf '%s\t%s\t%s\tenv=%d\tflag=%d\tverdict=%s\n' \
      "$ts" "$user" "$SKILL" "$HAS_ENV" "$HAS_FLAG" "$verdict" \
      >> "$AUDIT_LOG" 2>/dev/null || true
  fi
}

if [[ $HAS_ENV -eq 1 && $HAS_FLAG -eq 1 ]]; then
  log_attempt "ok"
  exit 0
fi

# At least one factor missing -> emit precise error.
{
  echo "ERROR: Doble opt-in requerido."
  echo "  Razon: prevenir activacion accidental de skill autonoma '$SKILL'."
  echo
  if [[ $HAS_ENV -eq 0 ]]; then
    echo "  [FALTA] Variable de entorno: $ENV_NAME=true"
  else
    echo "  [OK]    Variable de entorno: $ENV_NAME=true"
  fi
  if [[ $HAS_FLAG -eq 0 ]]; then
    echo "  [FALTA] Flag explicito: --confirm-autonomous"
  else
    echo "  [OK]    Flag explicito: --confirm-autonomous"
  fi
  echo
  echo "  Ambos factores son obligatorios. Aborto."
} >&2

log_attempt "denied"
exit 1
