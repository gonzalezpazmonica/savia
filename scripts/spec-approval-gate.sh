#!/usr/bin/env bash
# spec-approval-gate.sh — SE-051 Slice 1 Rule #8 enforcement gate.
#
# Detecta nuevos scripts/agents/skills que están respaldados por un spec
# en `docs/propuestas/` cuyo status sigue siendo PROPOSED/Draft. Rule #8:
# "NUNCA agente sin Spec aprobada".
#
# Trigger típicos:
#   - Pre-commit (staged files)
#   - CI gate sobre diff contra main
#   - Scan full workspace para auditoría
#
# Detección:
#   - Para cada script/agent/skill modificado o añadido, busca referencia
#     a SPEC-XXX o SE-XXX en header/ruta/frontmatter.
#   - Si el spec referenciado existe en docs/propuestas/ con status
#     distinto de APPROVED/ACCEPTED/Implemented → FAIL.
#   - Si el archivo referencia spec PROPOSED, bloquea commit.
#
# Usage:
#   spec-approval-gate.sh                      # scan full workspace
#   spec-approval-gate.sh --staged             # only staged files
#   spec-approval-gate.sh --against main       # diff vs main
#   spec-approval-gate.sh --json
#   spec-approval-gate.sh --allow-spec SE-999  # allow-list para bootstrap
#
# Exit codes:
#   0 — all files reference APPROVED specs (or no spec link)
#   1 — at least one file references non-approved spec
#   2 — usage error
#
# Ref: SE-051, Rule #8 autonomous-safety
# Safety: read-only, set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="full"
AGAINST="main"
JSON=0
ALLOW_LIST=()

APPROVED_STATUSES=("APPROVED" "ACCEPTED" "IMPLEMENTING" "IN_PROGRESS"
                   "Implemented" "IMPLEMENTED" "DONE" "Done")

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  --staged              Check only git-staged files
  --against BRANCH      Check diff against BRANCH (default main)
  --allow-spec ID       Allow a specific SPEC-ID / SE-ID as bootstrap exception
  --json                JSON output

Detecta scripts/agents/skills que linkean a specs no aprobadas (Rule #8).
Ref: SE-051, docs/rules/domain/autonomous-safety.md.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged) MODE="staged"; shift ;;
    --against) MODE="against"; AGAINST="$2"; shift 2 ;;
    --allow-spec) ALLOW_LIST+=("$2"); shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Collect files to audit
FILES=()
case "$MODE" in
  staged)
    while IFS= read -r f; do
      [[ -f "$PROJECT_ROOT/$f" ]] && FILES+=("$PROJECT_ROOT/$f")
    done < <(cd "$PROJECT_ROOT" && git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '^(scripts/|\.opencode/agents/|\.opencode/skills/)')
    ;;
  against)
    while IFS= read -r f; do
      [[ -f "$PROJECT_ROOT/$f" ]] && FILES+=("$PROJECT_ROOT/$f")
    done < <(cd "$PROJECT_ROOT" && git diff --name-only "$AGAINST" HEAD --diff-filter=ACM 2>/dev/null | grep -E '^(scripts/|\.opencode/agents/|\.opencode/skills/)')
    ;;
  full)
    while IFS= read -r f; do FILES+=("$f"); done < <(find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/.claude/agents" "$PROJECT_ROOT/.claude/skills" -type f \( -name "*.sh" -o -name "*.md" \) 2>/dev/null)
    ;;
esac

# Extract spec ID from file (scans first 30 lines for SPEC-XXX or SE-XXX)
extract_spec() {
  local f="$1"
  head -30 "$f" 2>/dev/null | grep -oE '(SPEC|SE)-[0-9]+[a-z]?' | head -1
}

extract_spec_reference() {
  local f="$1"
  head -30 "$f" 2>/dev/null \
    | grep -oE '(docs/(propuestas|specs)|projects/[^/]+/specs)/[A-Za-z0-9._/-]+\.md' \
    | head -1
}

# Get status of spec
spec_status() {
  local id="$1" reference="${2:-}"
  local sf result status
  local resolver="$PROJECT_ROOT/scripts/spec-resolve.sh"
  if [[ -n "$reference" ]]; then
    result=$(bash "$resolver" --root "$PROJECT_ROOT" --id "$id" \
      --reference "$reference" 2>&1)
  else
    result=$(bash "$resolver" --root "$PROJECT_ROOT" --id "$id" 2>&1)
  fi
  status=$?
  case "$status" in
    0) sf="$result" ;;
    1) echo "NOT_FOUND"; return ;;
    3) echo "AMBIGUOUS"; return ;;
    *) echo "UNKNOWN"; return ;;
  esac
  # Try YAML frontmatter
  local yaml_status
  yaml_status=$(awk 'NR==1{if($0=="---") f=1; next} f && /^status:/{print $2; exit} f && /^---$/{exit}' "$sf" 2>/dev/null | tr -d '"')
  if [[ -z "$yaml_status" ]]; then
    # Try Markdown fields such as "**Status:** IMPLEMENTED".
    yaml_status=$(sed -nE 's/^[[:space:]]*(\*\*)?(Status|Estado):(\*\*)?[[:space:]]*([A-Za-z_]+).*/\4/p' "$sf" 2>/dev/null | head -1)
  fi
  echo "${yaml_status:-UNKNOWN}"
}

# Check if a value is in an array
in_array() {
  local needle="$1"; shift
  local hay
  for hay in "$@"; do [[ "$hay" == "$needle" ]] && return 0; done
  return 1
}

VIOLATIONS=()
total=0
scanned=0

for f in "${FILES[@]}"; do
  total=$((total + 1))
  rel=${f#$PROJECT_ROOT/}

  spec_id=$(extract_spec "$f")
  [[ -z "$spec_id" ]] && continue
  scanned=$((scanned + 1))

  # Allow-list
  if in_array "$spec_id" "${ALLOW_LIST[@]}"; then
    continue
  fi

  spec_reference=$(extract_spec_reference "$f")
  status=$(spec_status "$spec_id" "$spec_reference")

  # Approved?
  if in_array "$status" "${APPROVED_STATUSES[@]}"; then
    continue
  fi

  # Not approved → violation
  VIOLATIONS+=("$rel|$spec_id|$status")
done

EXIT_CODE=0
VERDICT="PASS"
if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  VERDICT="FAIL"
  EXIT_CODE=1
fi

if [[ "$JSON" -eq 1 ]]; then
  v_json=""
  for v in "${VIOLATIONS[@]}"; do
    IFS='|' read -r file spec status <<< "$v"
    v_json+="{\"file\":\"$file\",\"spec\":\"$spec\",\"status\":\"$status\"},"
  done
  v_json="[${v_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","total_files":$total,"with_spec_link":$scanned,"violations":${#VIOLATIONS[@]},"mode":"$MODE","violation_list":$v_json}
JSON
else
  echo "=== SE-051 Spec Approval Gate (Rule #8) ==="
  echo ""
  echo "Mode:             $MODE"
  echo "Files scanned:    $total"
  echo "With spec link:   $scanned"
  echo "Violations:       ${#VIOLATIONS[@]}"
  echo ""
  if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "Files linking to non-approved specs:"
    for v in "${VIOLATIONS[@]}"; do
      IFS='|' read -r file spec status <<< "$v"
      echo "  • $file → $spec (status: $status)"
    done
    echo ""
  fi
  echo "VERDICT: $VERDICT"
  if [[ "$VERDICT" == "FAIL" ]]; then
    echo ""
    echo "Rule #8: NUNCA agente sin Spec aprobada."
    echo "Acciones posibles:"
    echo "  1. Aprobar el spec (status: APPROVED) antes de mergear"
    echo "  2. Revertir el código hasta que el spec esté aprobado"
    echo "  3. Use --allow-spec SPEC-ID solo para bootstrap justificado"
  fi
fi

exit $EXIT_CODE
