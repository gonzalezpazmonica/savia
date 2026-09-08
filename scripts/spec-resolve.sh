#!/usr/bin/env bash
# Deterministic spec resolver shared by governance gates.
# Ref: docs/propuestas/SE-315-scope-creep-gate.md (AC-S3.5..AC-S3.7)
set -uo pipefail

ROOT=""
ID=""
REFERENCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --id) ID="${2:-}"; shift 2 ;;
    --reference) REFERENCE="${2:-}"; shift 2 ;;
    *) echo "Usage: $0 --root PATH --id SE-NNN [--reference PATH]"; exit 2 ;;
  esac
done

[[ -n "$ROOT" && -n "$ID" ]] || {
  echo "Usage: $0 --root PATH --id SE-NNN [--reference PATH]"
  exit 2
}
[[ "$ID" =~ ^(SE|SPEC)-[0-9]+[a-z]?$ ]] || {
  echo "INVALID_ID: $ID"
  exit 2
}
ROOT="${ROOT%/}"

if [[ -n "$REFERENCE" ]]; then
  case "$REFERENCE" in
    /*|*../*|../*|*/..)
      echo "INVALID_REFERENCE: $REFERENCE"
      exit 2
      ;;
    docs/propuestas/*.md|docs/specs/*.md|projects/*/specs/*.md) ;;
    *)
      echo "INVALID_REFERENCE: $REFERENCE"
      exit 2
      ;;
  esac
  reference_name=$(basename "$REFERENCE")
  [[ "$reference_name" == "$ID-"* || "$reference_name" == "$ID.md" ]] || {
    echo "REFERENCE_ID_MISMATCH: $REFERENCE"
    exit 2
  }
  [[ -f "$ROOT/$REFERENCE" ]] || {
    echo "NOT_FOUND: $REFERENCE"
    exit 1
  }
  echo "$ROOT/$REFERENCE"
  exit 0
fi

matches=()
while IFS= read -r candidate; do
  [[ -n "$candidate" ]] && matches+=("$candidate")
done < <(
  find "$ROOT/docs/propuestas" "$ROOT/docs/specs" "$ROOT/projects" \
    -type f -name "$ID-*.md" 2>/dev/null \
    | awk -v root="$ROOT/" '
        index($0, root "docs/propuestas/") == 1 ||
        index($0, root "docs/specs/") == 1 ||
        ($0 ~ ("^" root "projects/[^/]+/specs/[^/]+$"))
      ' \
    | sort -u
)

case "${#matches[@]}" in
  0) echo "NOT_FOUND: $ID"; exit 1 ;;
  1) echo "${matches[0]}"; exit 0 ;;
  *) echo "AMBIGUOUS: $ID (${#matches[@]} matches)"; exit 3 ;;
esac
