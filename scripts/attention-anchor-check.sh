#!/usr/bin/env bash
# attention-anchor-check.sh — SE-080 pattern coverage verifier
set -uo pipefail
# Verifies that the 4 Genesis patterns (B8, B9, A7, A9) are each referenced
# in at least one file in the workspace.
#
# Output: JSON to stdout
#   {
#     "checked": 4,
#     "found": N,
#     "missing": ["B8", ...],
#     "details": { "B8": "file:line", ... }
#   }
#
# Exit codes:
#   0 — always (informational only)
#
# Spec: docs/propuestas/SE-080-attention-anchor-vocabulary.md
# Doc:  docs/rules/domain/attention-anchor.md
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANCHOR_DOC="$REPO_ROOT/docs/rules/domain/attention-anchor.md"

declare -A PATTERNS=(
  [B8]="B8"
  [B9]="B9"
  [A7]="A7"
  [A9]="A9"
)

declare -A FOUND_IN=()
declare -a MISSING=()

# ── Search each pattern in workspace ─────────────────────────────────────────
for pattern in B8 B9 A7 A9; do
  # El propio script cita los cuatro patrones en su cabecera: sin --exclude se
  # encontraba a sí mismo y el informe nunca podía listar un patrón como ausente.
  hit=$(grep -rl "$pattern" "$REPO_ROOT/docs" "$REPO_ROOT/scripts" "$REPO_ROOT/.opencode" \
        --include="*.md" --include="*.sh" --exclude="$(basename "${BASH_SOURCE[0]}")" 2>/dev/null \
        | grep -v '\.git' | head -1 || true)
  if [[ -n "$hit" ]]; then
    # Get first matching line number
    lineno=$(grep -n "$pattern" "$hit" 2>/dev/null | head -1 | cut -d: -f1 || echo "1")
    FOUND_IN[$pattern]="${hit#"$REPO_ROOT/"}:${lineno}"
  else
    MISSING+=("$pattern")
  fi
done

FOUND_COUNT=$(( 4 - ${#MISSING[@]} ))

# ── Build JSON ────────────────────────────────────────────────────────────────
python3 - <<PYEOF
import json

found_in = {}
$(for p in B8 B9 A7 A9; do
  if [[ -n "${FOUND_IN[$p]:-}" ]]; then
    echo "found_in['$p'] = '${FOUND_IN[$p]}'"
  fi
done)

missing = $(printf '%s\n' "${MISSING[@]:-}" | python3 -c "import json,sys; items=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(items))")

print(json.dumps({
    "checked": 4,
    "found": $FOUND_COUNT,
    "missing": missing,
    "details": found_in
}, indent=2))
PYEOF

exit 0
