#!/usr/bin/env bash
# pre-tribunal-gates.sh — SE-251: deterministic pre-tribunal gates
#
# Usage:
#   bash scripts/pre-tribunal-gates.sh --decision <merge|deploy|devops> --context <json>
#   bash scripts/pre-tribunal-gates.sh --help
#
# Exit codes:
#   0  PASS — all gates passed, tribunal can be invoked
#   1  BLOCK — a gate failed, escalate to human
#   2  SKIP — decision type not classified as critical, normal flow
#
# Output JSON:
#   {"gate":"G1","verdict":"BLOCK","reason":"...","escalate_to":"human"}
#   {"gate":"ALL","verdict":"PASS","reason":"all gates passed"}
#
# Reference: SE-251 docs/propuestas/SE-251-hard-gates-pre-tribunal.md

set -uo pipefail

DECISION=""
CONTEXT_JSON="{}"
PRETRIBUNAL_GATES_ENABLED="${PRETRIBUNAL_GATES_ENABLED:-true}"
RISK_GATE_THRESHOLD="${RISK_GATE_THRESHOLD:-0.8}"
SPEC_GATE_ENABLED="${SPEC_GATE_ENABLED:-true}"
RISK_SCORING_SCRIPT="scripts/risk-scoring.sh"
SAVIA_ENV_SCRIPT="scripts/savia-env.sh"

show_usage() {
  cat <<USG
Usage: pre-tribunal-gates.sh --decision <type> [--context <json>] [OPTIONS]

SE-251: Deterministic pre-tribunal gates for high-impact decisions.

Decision types:
  merge    PR merge to main/develop
  deploy   Infrastructure deployment
  devops   Write to Azure DevOps (PBI, sprint changes)

Options:
  --decision <type>     Decision type (required)
  --context <json>      JSON context with keys: spec_status, risk_score, source_branch, target_branch
  --help, -h            Show this help

Exit codes:
  0  PASS — proceed with tribunal
  1  BLOCK — escalate to human, skip tribunal
  2  SKIP — decision not critical, normal flow

Environment:
  PRETRIBUNAL_GATES_ENABLED=true   Set to false to disable all gates (tests)
  RISK_GATE_THRESHOLD=0.8          G3 risk score threshold
  SPEC_GATE_ENABLED=true           Set to false for projects without mandatory specs

Examples:
  pre-tribunal-gates.sh --decision merge --context '{"spec_status":"APPROVED","source_branch":"nido/se248"}'
  pre-tribunal-gates.sh --decision deploy --context '{"risk_score":0.9}'
  pre-tribunal-gates.sh --decision unknown-type
USG
}

emit_result() {
  local gate="$1" verdict="$2" reason="$3"
  printf '{"gate":"%s","verdict":"%s","reason":"%s","escalate_to":"%s"}\n' \
    "$gate" "$verdict" "$reason" "$([ "$verdict" = "BLOCK" ] && echo "human" || echo "none")"
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decision)  DECISION="${2:-}"; shift 2 ;;
    --context)   CONTEXT_JSON="${2:-{}}"; shift 2 ;;
    --help|-h)   show_usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; show_usage >&2; exit 1 ;;
  esac
done

if [[ -z "$DECISION" ]]; then
  echo "ERROR: --decision is required" >&2
  show_usage >&2
  exit 1
fi

# SKIP if disabled
if [[ "$PRETRIBUNAL_GATES_ENABLED" == "false" ]]; then
  emit_result "ALL" "PASS" "gates disabled via PRETRIBUNAL_GATES_ENABLED=false"
  exit 0
fi

# SKIP for unrecognized decision types
case "$DECISION" in
  merge|deploy|devops) ;;
  *)
    emit_result "SKIP" "SKIP" "decision type '$DECISION' not classified as critical"
    exit 2
    ;;
esac

# Helper: extract JSON field (bash-only, no jq required)
json_field() {
  local json="$1" field="$2"
  echo "$json" | grep -oP "\"${field}\"\\s*:\\s*\"?[^,}\"]+\"?" | grep -oP ':\s*"?\K[^,"}\s]+' | head -1
}

# ── G1: Spec Approval Gate ────────────────────────────────────────────────────
if [[ "$SPEC_GATE_ENABLED" == "true" && "$DECISION" == "merge" ]]; then
  spec_status=$(json_field "$CONTEXT_JSON" "spec_status")
  if [[ -n "$spec_status" ]]; then
    case "$spec_status" in
      APPROVED|IMPLEMENTED) ;;  # pass
      PROPOSED|DRAFT|NONE|"")
        emit_result "G1" "BLOCK" "spec_status=$spec_status — feature requires APPROVED spec before merge"
        exit 1
        ;;
    esac
  fi
fi

# ── G2: Autonomous Reviewer Gate ─────────────────────────────────────────────
if [[ -f "$SAVIA_ENV_SCRIPT" ]]; then
  reviewer=$(bash "$SAVIA_ENV_SCRIPT" reviewer 2>/dev/null || true)
  if [[ -z "$reviewer" || "$reviewer" == '""' || "$reviewer" == "''" ]]; then
    emit_result "G2" "BLOCK" "AUTONOMOUS_REVIEWER unresolvable — cannot proceed without reviewer"
    exit 1
  fi
fi

# ── G3: Risk Score Gate ───────────────────────────────────────────────────────
risk_score=$(json_field "$CONTEXT_JSON" "risk_score")
if [[ -n "$risk_score" ]]; then
  # Compare floats using python3 (bash can't do float comparison natively)
  # Values go in as argv, never inside the Python source (they come from --context).
  if python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)' \
      "$risk_score" "$RISK_GATE_THRESHOLD" 2>/dev/null; then
    emit_result "G3" "BLOCK" "risk_score=$risk_score > threshold=$RISK_GATE_THRESHOLD"
    exit 1
  fi
fi

# ── G4: Branch Safety Gate ───────────────────────────────────────────────────
if [[ "$DECISION" == "merge" ]]; then
  source_branch=$(json_field "$CONTEXT_JSON" "source_branch")
  target_branch=$(json_field "$CONTEXT_JSON" "target_branch")
  if [[ -n "$target_branch" && -n "$source_branch" ]]; then
    case "$target_branch" in
      main|develop|master)
        if ! echo "$source_branch" | grep -qE "^(agent/|nido/|hotfix/)"; then
          emit_result "G4" "BLOCK" "source_branch=$source_branch not in (agent/|nido/|hotfix/) — unsafe merge to $target_branch"
          exit 1
        fi
        ;;
    esac
  fi
fi

# ── ALL PASS ─────────────────────────────────────────────────────────────────
emit_result "ALL" "PASS" "all gates passed"
exit 0
