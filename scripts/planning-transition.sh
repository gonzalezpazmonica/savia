#!/usr/bin/env bash
# SE-387 F / SE-396 P01 — inspect graduation readiness without mutating state.
# Usage: planning-transition.sh check <ID>
set -uo pipefail
ROOT="${REPO_ROOT:-$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)}"
STATE="$ROOT/docs/propuestas/planning-state.json"
MAIN_REF="${PLANNING_MAIN_REF:-origin/main}"
[[ "${1:-}" == "check" && -n "${2:-}" ]] || {
  echo "uso: planning-transition.sh check SE-NNN" >&2
  exit 1
}
ID="${2:-}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/planning-completion.sh"

jq -e --arg id "$ID" '.initiatives[]|select(.id==$id)' "$STATE" >/dev/null || { echo "FAIL: $ID no existe"; exit 1; }
ST=$(jq -r --arg id "$ID" '.initiatives[]|select(.id==$id)|.status' "$STATE")
[[ "$ST" == "IMPLEMENTING" ]] || {
  echo "NOT_READY: $ID está en estado $ST, no IMPLEMENTING"
  exit 1
}

COMPLETION=$(jq -c --arg id "$ID" '.initiatives[]|select(.id==$id)|.completion // null' "$STATE")
if ! planning_completion_shape_valid "$COMPLETION"; then
  echo "NOT_READY: falta completion.merge_pr o evidencia AC estructurada"
  exit 1
fi
if ! planning_acceptance_evidence_valid "$ROOT" "$COMPLETION"; then
  echo "NOT_READY: evidencia AC inválida"
  exit 1
fi

PR=$(jq -r '.merge_pr' <<<"$COMPLETION")
if ! planning_pr_merged "$ROOT" "$MAIN_REF" "$PR"; then
  echo "NOT_READY: PR #$PR no está mergeado en $MAIN_REF"
  exit 1
fi

echo "NEEDS_HUMAN_REVIEW: PR #$PR y evidencia AC verificados; cierre final requiere revisión humana"
