#!/usr/bin/env bash
# spec-id-duplicates-check.sh — SE-044 Slice 1 spec ID uniqueness gate.
#
# Detecta duplicados de spec ID en `docs/propuestas/*.md` (YAML frontmatter
# `id:` field) y `docs/specs/*.spec.md` (ID en el nombre). Bloquea commits que
# introducen un segundo fichero con el mismo ID sin resolución explícita.
#
# Seed case: SPEC-110 existe en:
#   - SPEC-110-memoria-externa-canonica.md (Draft)
#   - SPEC-110-polyglot-developer.md (REJECTED)
#
# Usage:
#   spec-id-duplicates-check.sh              # scan + report
#   spec-id-duplicates-check.sh --staged     # only staged diff
#   spec-id-duplicates-check.sh --json
#
# Exit codes:
#   0 — no duplicates
#   1 — duplicates found
#   2 — usage error
#
# Ref: SE-044, audit-arquitectura-20260420.md D7/D21
# Safety: read-only. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="full"
JSON=0

usage() {
  cat <<EOF
Usage:
  $0 [--staged] [--json]

Options:
  --staged    Only check git-staged files in docs/propuestas/ and docs/specs/
  --json      JSON output

Detecta specs con mismo ID en docs/propuestas/ y docs/specs/.
Ref: SE-044, Rule #8 evidence trail.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged) MODE="staged"; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

PROPUESTAS_DIR="$PROJECT_ROOT/docs/propuestas"
SPECS_DIR="$PROJECT_ROOT/docs/specs"
[[ ! -d "$PROPUESTAS_DIR" && ! -d "$SPECS_DIR" ]] && {
  echo "ERROR: neither docs/propuestas nor docs/specs found" >&2
  exit 2
}

# Collect spec files
SPEC_FILES=()
case "$MODE" in
  staged)
    while IFS= read -r f; do
      [[ -f "$PROJECT_ROOT/$f" ]] && SPEC_FILES+=("$PROJECT_ROOT/$f")
    done < <(cd "$PROJECT_ROOT" && git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '^docs/(propuestas/.*\.md|specs/.*\.spec\.md)$')
    ;;
  full)
    while IFS= read -r f; do SPEC_FILES+=("$f"); done < <(
      find "$PROPUESTAS_DIR" -maxdepth 3 -name "*.md" -type f 2>/dev/null
      find "$SPECS_DIR" -maxdepth 1 -name "*.spec.md" -type f 2>/dev/null
    )
    ;;
esac

# Extract id field from YAML frontmatter
extract_id() {
  local f="$1"
  local base
  base=$(basename "$f")
  if [[ "$f" == "$SPECS_DIR/"* && "$base" =~ (SE-[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  awk 'NR==1 && $0=="---" {inside=1; next}
       inside && $0=="---" {exit}
       inside && /^id:/ {sub(/^id:[ \t]*/, ""); gsub(/^"|"$/, ""); print; exit}' "$f" 2>/dev/null
}

# Map id -> list of files
declare -A ID_FILES
for f in "${SPEC_FILES[@]}"; do
  id=$(extract_id "$f")
  [[ -z "$id" ]] && continue
  rel=${f#$PROJECT_ROOT/}
  if [[ -n "${ID_FILES[$id]:-}" ]]; then
    ID_FILES[$id]="${ID_FILES[$id]}|$rel"
  else
    ID_FILES[$id]="$rel"
  fi
done

# Historical collisions are frozen as exact path sets. They remain visible in
# repository history but do not permit another file to reuse those IDs.
declare -A ACCEPTED_DUPLICATES=(
  [SE-260]="docs/specs/SE-260-blast-radius.spec.md|docs/specs/SE-260-gentle-patterns.spec.md"
  [SE-334]="docs/specs/SE-334-telemetry-intelligence.spec.md|docs/specs/SE-334-vaults-scl-criteria-hardening.spec.md"
  [SE-348]="docs/propuestas/SE-348-resiliencia-baseline-capas.md|docs/specs/SE-348-integridad-savia.spec.md"
)

DUPES=()
for id in "${!ID_FILES[@]}"; do
  files="${ID_FILES[$id]}"
  if [[ "$files" == *"|"* ]]; then
    normalized=$(tr '|' '\n' <<< "$files" | sort | paste -sd '|' -)
    if [[ "${ACCEPTED_DUPLICATES[$id]:-}" != "$normalized" ]]; then
      DUPES+=("$id: $normalized")
    fi
  fi
done

EXIT_CODE=0
VERDICT="PASS"
if [[ ${#DUPES[@]} -gt 0 ]]; then
  VERDICT="FAIL"
  EXIT_CODE=1
fi

total=${#SPEC_FILES[@]}

if [[ "$JSON" -eq 1 ]]; then
  d_json=""
  for d in "${DUPES[@]}"; do
    id="${d%%:*}"
    files_raw="${d#*: }"
    files_arr=""
    IFS='|' read -ra files_list <<< "$files_raw"
    for f in "${files_list[@]}"; do
      files_arr+="\"$f\","
    done
    files_arr="[${files_arr%,}]"
    d_json+="{\"id\":\"$id\",\"files\":$files_arr},"
  done
  d_json="[${d_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","total_specs":$total,"duplicates_count":${#DUPES[@]},"mode":"$MODE","duplicates":$d_json}
JSON
else
  echo "=== SE-044 Spec ID Duplicates Check ==="
  echo ""
  echo "Mode:           $MODE"
  echo "Specs scanned:  $total"
  echo "Duplicates:     ${#DUPES[@]}"
  echo ""
  if [[ ${#DUPES[@]} -gt 0 ]]; then
    echo "Duplicate IDs:"
    for d in "${DUPES[@]}"; do
      id="${d%%:*}"
      files_raw="${d#*: }"
      echo "  • $id"
      IFS='|' read -ra files_list <<< "$files_raw"
      for f in "${files_list[@]}"; do
        echo "      - $f"
      done
    done
    echo ""
  fi
  echo "VERDICT: $VERDICT"
  if [[ "$VERDICT" == "FAIL" ]]; then
    echo ""
    echo "Resolución (SE-044 §action):"
    echo "  1. Decidir cual mantiene el ID original"
    echo "  2. Renumerar el otro (siguiente ID libre)"
    echo "  3. Registrar decisión en docs/decisions/adr-NNN.md"
    echo "  4. Actualizar referencias en CLAUDE.md y ROADMAP.md"
  fi
fi

exit $EXIT_CODE
