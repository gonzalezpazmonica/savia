#!/bin/bash
set -uo pipefail
# changelog-spec-field-check.sh — SE-258 Slice 4
# Verifica que entradas CHANGELOG.d tienen campo spec: y que el spec existe
# Modos: --check (exit 1 si falta), --warn (exit 0, solo aviso), default --check

MODE="${1:---check}"
if [[ "$MODE" != "--check" && "$MODE" != "--warn" ]]; then
  echo "Usage: $0 [--check|--warn]" >&2
  echo "  --check  exit 1 if issues found" >&2
  echo "  --warn   exit 0 but print issues" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_DIR="$REPO_ROOT/CHANGELOG.d"
if [[ ! -d "$CHANGELOG_DIR" ]]; then
  exit 0
fi
# Las specs viven en docs/specs, docs/propuestas (y subdirectorios) y en los
# dos archivos históricos. Solo se buscan los directorios que existan.
SPEC_ROOTS=()
for d in "$REPO_ROOT/docs/specs" "$REPO_ROOT/docs/propuestas" \
         "$REPO_ROOT/docs/specs-archive" "$REPO_ROOT/specs-archive"; do
  [[ -d "$d" ]] && SPEC_ROOTS+=("$d")
done

# spec_exists ID — 0 si hay un fichero cuyo nombre es exactamente el ID
# seguido de «-», «.md» o «.spec.md» (sin casar por prefijo: SE-25 ≠ SE-253).
spec_exists() {
  local id="$1"
  [[ ${#SPEC_ROOTS[@]} -eq 0 ]] && return 1
  find "${SPEC_ROOTS[@]}" -type f \( -iname "${id}-*.md" -o -iname "${id}.md" \
    -o -iname "${id}.spec.md" -o -iname "SPEC-${id}-*.md" \) -print -quit 2>/dev/null | grep -q .
}

ISSUES=0
for entry in "$CHANGELOG_DIR"/*.md; do
  [[ ! -f "$entry" ]] && continue
  basename=$(basename "$entry" .md)

  spec_id=""
  if grep -q '^spec:' "$entry"; then
    spec_id=$(grep '^spec:' "$entry" | head -1 | sed -e 's/^spec:[[:space:]]*//' -e 's/[[:space:]\r]*$//' -e "s/^[\"']//" -e "s/[\"']\$//")
  fi

  if [[ -z "$spec_id" ]]; then
    spec_match=$(echo "$basename" | grep -ioE '(^|[^a-z])se-?[0-9]+' || true)
    if [[ -n "$spec_match" ]]; then
      echo "ISSUE: $basename missing 'spec:' field in frontmatter"
      ISSUES=$((ISSUES + 1))
    fi
    continue
  fi

  found=0
  if [[ ! "$spec_id" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9][0-9A-Za-z.]*$ ]]; then
    echo "ISSUE: invalid spec id '${spec_id}' in CHANGELOG.d/$basename"
    ISSUES=$((ISSUES + 1))
    continue
  fi
  spec_exists "$spec_id" && found=1

  if [[ "$found" -eq 0 ]]; then
    echo "ISSUE: ${spec_id} referenced in CHANGELOG.d/$basename but spec file not found in docs/specs/, docs/propuestas/ or an archive"
    ISSUES=$((ISSUES + 1))
  fi
done

if [[ "$ISSUES" -eq 0 ]]; then
  echo "OK: all CHANGELOG.d entries have spec: field with existing spec files"
  exit 0
fi

echo ""
echo "Total issues: $ISSUES"
if [[ "$MODE" == "--warn" ]]; then
  echo "WARN: $ISSUES issue(s) found (non-blocking mode)"
  exit 0
fi

exit 1
