#!/usr/bin/env bash
set -uo pipefail
# action-review.sh — SE-445 S3: revisor de acciones opt-in sobre Bash (PreToolUse).
#
# Doble opt-in (SPEC-186): SAVIA_ACTION_REVIEW=on Y SAVIA_ACTION_REVIEW_CONFIRMED=1 (lo exporta el
# lanzador autonomo solo con --confirm-autonomous). Sin ambas sale con 0 sin hacer nada.
# Logica, reglas y fail-closed en tiers 3/4: scripts/action-review.py y
# docs/rules/domain/action-review-policy.md. Exit 2 = bloqueo. Sin stdout al permitir.
# Uso: action-review.sh [--dry-run]  (payload JSON por stdin)

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

if [[ $DRY -eq 0 ]]; then
  case "${SAVIA_ACTION_REVIEW:-off}" in on|true|1) ;; *) exit 0 ;; esac
  [[ "${SAVIA_ACTION_REVIEW_CONFIRMED:-}" == "1" ]] || exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
REVIEWER="$PROJECT_DIR/scripts/action-review.py"
[[ -f "$REVIEWER" ]] || exit 0

exec python3 "$REVIEWER" "$@"
