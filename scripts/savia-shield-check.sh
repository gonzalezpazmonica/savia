#!/usr/bin/env bash
# savia-shield-check.sh — SPEC-OC-01
set -uo pipefail
#
# Verifica el estado del Savia Shield para sesiones OpenCode.
# Detecta si los plugins de sovereignty están activos, que el hook
# context-sanitize-input.sh existe, y que block-credential-leak está
# registrado en la configuración de plugins.
#
# Output (--json): JSON a stdout
#   {"shield_status":"active|partial|inactive","components":[...],"missing":[...]}
#
# Exit codes:
#   0 — shield active (all components found)
#   1 — shield partial (some components missing)
#   2 — shield inactive (critical components missing)
#
# Usage:
#   bash scripts/savia-shield-check.sh
#   bash scripts/savia-shield-check.sh --json
#
# Reference: SPEC-OC-01, docs/rules/domain/savia-shield-opencode.md

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_CANDIDATE="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-"$SCRIPT_DIR/.."}}}"
if ! WORKSPACE_DIR="$(cd "$WS_CANDIDATE" 2>/dev/null && pwd)" || [[ -z "$WORKSPACE_DIR" ]]; then
  echo "ERROR: workspace directory not found: $WS_CANDIDATE" >&2
  exit 2
fi

JSON_MODE=0
[[ "${1:-}" == "--json" ]] && JSON_MODE=1

# ── Component definitions ─────────────────────────────────────────────────────

declare -a COMPONENTS=()
declare -a MISSING=()

check_component() {
  local name="$1" path="$2" critical="${3:-false}"
  if [[ -f "$path" ]]; then
    COMPONENTS+=("$name")
  else
    MISSING+=("$name")
  fi
}

# ── Check 1: data-sovereignty-gate.ts ────────────────────────────────────────
check_component \
  "data-sovereignty-gate" \
  "$WORKSPACE_DIR/.opencode/plugins/guards/data-sovereignty-gate.ts" \
  "true"

# ── Check 2: data-sovereignty-audit.ts ───────────────────────────────────────
check_component \
  "data-sovereignty-audit" \
  "$WORKSPACE_DIR/.opencode/plugins/guards/data-sovereignty-audit.ts" \
  "true"

# ── Check 3: sovereignty-patterns.ts (lib) ───────────────────────────────────
check_component \
  "sovereignty-patterns" \
  "$WORKSPACE_DIR/.opencode/plugins/lib/sovereignty-patterns.ts" \
  "true"

# ── Check 4: block-credential-leak.ts ────────────────────────────────────────
check_component \
  "block-credential-leak" \
  "$WORKSPACE_DIR/.opencode/plugins/guards/block-credential-leak.ts" \
  "true"

# ── Check 5: context-sanitize-input.sh (OpenCode hook) ───────────────────────
check_component \
  "context-sanitize-input" \
  "$WORKSPACE_DIR/.opencode/hooks/context-sanitize-input.sh" \
  "true"

# ── Check 6: savia-foundation.ts wires the guards ────────────────────────────
# «Cableado» = el guard figura como elemento de una lista de guards (línea con
# solo el identificador). Un import o un comentario no bastan: un guard
# importado pero retirado de BEFORE_GUARDS no protege nada.
FOUNDATION="$WORKSPACE_DIR/.opencode/plugins/savia-foundation.ts"
guard_registered() {
  [[ -f "$FOUNDATION" ]] && grep -qE "^[[:space:]]*$1,?[[:space:]]*(//.*)?$" "$FOUNDATION" 2>/dev/null
}
if guard_registered "dataSovereigntyGate"; then
  COMPONENTS+=("savia-foundation-wired")
else
  MISSING+=("savia-foundation-wired")
fi

# ── Check 7: block-credential-leak referenced in settings/plugin wiring ──────
# The foundation plugin imports blockCredentialLeak — verify it's wired
if guard_registered "blockCredentialLeak"; then
  COMPONENTS+=("block-credential-leak-wired")
else
  MISSING+=("block-credential-leak-wired")
fi

# ── Check 8: savia-shield-opencode.md documentation ─────────────────────────
check_component \
  "savia-shield-opencode-doc" \
  "$WORKSPACE_DIR/docs/rules/domain/savia-shield-opencode.md" \
  "false"

# ── Determine shield status ───────────────────────────────────────────────────

CRITICAL_COMPONENTS=(
  "data-sovereignty-gate"
  "data-sovereignty-audit"
  "sovereignty-patterns"
  "block-credential-leak"
  "context-sanitize-input"
  "savia-foundation-wired"
  "block-credential-leak-wired"
)

CRITICAL_MISSING=0
for c in "${CRITICAL_COMPONENTS[@]}"; do
  found=0
  for comp in ${COMPONENTS[@]+"${COMPONENTS[@]}"}; do
    [[ "$comp" == "$c" ]] && found=1 && break
  done
  (( found == 0 )) && CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
done

if (( CRITICAL_MISSING == 0 && ${#MISSING[@]} == 0 )); then
  STATUS="active"
  EXIT_CODE=0
elif (( CRITICAL_MISSING == 0 )); then
  STATUS="partial"
  EXIT_CODE=1
else
  STATUS="inactive"
  EXIT_CODE=2
fi

# ── Output ────────────────────────────────────────────────────────────────────

if (( JSON_MODE == 1 )); then
  # Build JSON arrays
  comp_json="["
  first=1
  for c in ${COMPONENTS[@]+"${COMPONENTS[@]}"}; do
    (( first )) || comp_json+=","
    comp_json+="\"$c\""
    first=0
  done
  comp_json+="]"

  miss_json="["
  first=1
  for m in ${MISSING[@]+"${MISSING[@]}"}; do
    (( first )) || miss_json+=","
    miss_json+="\"$m\""
    first=0
  done
  miss_json+="]"

  printf '{"shield_status":"%s","components":%s,"missing":%s}\n' \
    "$STATUS" "$comp_json" "$miss_json"
else
  printf 'Savia Shield Status: %s\n' "$STATUS"
  printf 'Components found (%d):\n' "${#COMPONENTS[@]}"
  for c in ${COMPONENTS[@]+"${COMPONENTS[@]}"}; do
    printf '  + %s\n' "$c"
  done
  if (( ${#MISSING[@]} > 0 )); then
    printf 'Missing (%d):\n' "${#MISSING[@]}"
    for m in "${MISSING[@]}"; do
      printf '  - %s\n' "$m"
    done
  fi
fi

exit "$EXIT_CODE"
