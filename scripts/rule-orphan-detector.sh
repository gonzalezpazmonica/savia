#!/usr/bin/env bash
# rule-orphan-detector.sh — SE-048 Slice 1 rule usage audit.
set -uo pipefail
#
# Para cada regla en `docs/rules/domain/*.md`, cuenta referencias reales
# en: .opencode/agents/, .opencode/skills/, .opencode/commands/, scripts/, tests/,
# docs/ (excluyendo la propia ruta), CLAUDE.md.
#
# Reporta reglas con ref_count=0 como "huérfanas" (candidate deprecate).
#
# Seed case: SPEC-121 handoff-convention → 0 agentes la usan.
#
# Usage:
#   rule-orphan-detector.sh
#   rule-orphan-detector.sh --min-refs 1 --json
#   rule-orphan-detector.sh --include-index   # incluye INDEX.md
#
# Exit codes:
#   0 — sin huérfanas (o --include-index con todas referenciadas)
#   1 — al menos 1 regla huérfana
#   2 — usage error
#
# Ref: SE-048, audit-arquitectura-20260420.md §SPEC-121
# Safety: read-only, set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MIN_REFS=1
JSON=0
INCLUDE_INDEX=0

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  --min-refs N       Minimum ref count (default 1 = fails on 0-ref rules)
  --include-index    Include INDEX.md files in scan (default: skip auto-generated)
  --json             JSON output

Cuenta referencias reales por rule en docs/rules/domain/*.md.
Reglas con <N referencias = huérfanas (candidate deprecate).

Ref: SE-048.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-refs)
      [[ $# -ge 2 ]] || { echo "ERROR: --min-refs needs a value" >&2; exit 2; }
      MIN_REFS="$2"; shift 2 ;;
    --include-index) INCLUDE_INDEX=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if ! [[ "$MIN_REFS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --min-refs must be non-negative integer" >&2; exit 2
fi

RULES_DIR="$PROJECT_ROOT/docs/rules/domain"
[[ ! -d "$RULES_DIR" ]] && { echo "ERROR: rules dir not found: $RULES_DIR" >&2; exit 2; }

# Scan paths
SCAN_PATHS=(
  "$PROJECT_ROOT/.claude/agents"
  "$PROJECT_ROOT/.claude/skills"
  "$PROJECT_ROOT/.claude/commands"
  "$PROJECT_ROOT/scripts"
  "$PROJECT_ROOT/tests"
  "$PROJECT_ROOT/docs"
  "$PROJECT_ROOT/CLAUDE.md"
)

# Collect rule files (skip archived rules — SE-096)
RULE_FILES=()
for f in "$RULES_DIR"/*.md; do
  [[ ! -f "$f" ]] && continue
  bn=$(basename "$f")
  [[ "$INCLUDE_INDEX" -eq 0 && "$bn" == "INDEX.md" ]] && continue
  # Skip rules marked archived: true in frontmatter
  if grep -qE '^archived: true' "$f" 2>/dev/null; then
    continue
  fi
  RULE_FILES+=("$f")
done

# Fail-closed: a scan over zero rules proves nothing, so it is not a PASS.
if [[ ${#RULE_FILES[@]} -eq 0 ]]; then
  echo "ERROR: no rules found in $RULES_DIR" >&2; exit 2
fi

# Count refs (searches for filename basename — the usual reference form)
count_refs() {
  local rule_file="$1"
  local bn
  bn=$(basename "$rule_file")
  # Reference could be "filename.md", "./filename.md", "domain/filename.md"
  local count=0
  local paths_args=()
  for p in "${SCAN_PATHS[@]}"; do
    [[ -e "$p" ]] && paths_args+=("$p")
  done

  if [[ ${#paths_args[@]} -eq 0 ]]; then
    echo 0; return
  fi

  # The basename must appear as a whole file name: "x.md" is not referenced by
  # "prefix-x.md" or "x.mdx", and the dot is literal, not a regex wildcard.
  local bn_re
  bn_re=$(printf '%s' "$bn" | sed 's/[][\.*^$()+?{}|]/\\&/g')
  # grep recursive, excluding the rule file itself
  count=$(grep -rE --include='*.md' --include='*.sh' --include='*.ts' --include='*.py' --include='*.yaml' --include='*.yml' --include='*.json' \
    -l "(^|[^A-Za-z0-9_.-])${bn_re}([^A-Za-z0-9_-]|\$)" "${paths_args[@]}" 2>/dev/null | grep -vxF "$rule_file" | wc -l)
  echo "${count:-0}"
}

ORPHANS=()
REFS=()
total=0
orphan_count=0

for rf in "${RULE_FILES[@]}"; do
  total=$((total + 1))
  refs=$(count_refs "$rf")
  rel=${rf#$PROJECT_ROOT/}
  REFS+=("$refs|$rel")
  if [[ "$refs" -lt "$MIN_REFS" ]]; then
    orphan_count=$((orphan_count + 1))
    ORPHANS+=("$refs|$rel")
  fi
done

VERDICT="PASS"
EXIT_CODE=0
if [[ "$orphan_count" -gt 0 ]]; then
  VERDICT="FAIL"
  EXIT_CODE=1
fi

if [[ "$JSON" -eq 1 ]]; then
  orph_json=""
  for o in "${ORPHANS[@]}"; do
    IFS='|' read -r r f <<< "$o"
    orph_json+="{\"refs\":$r,\"rule\":\"$f\"},"
  done
  orph_json="[${orph_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","total_rules":$total,"orphans":$orphan_count,"min_refs":$MIN_REFS,"orphan_list":$orph_json}
JSON
else
  echo "=== SE-048 Rule Orphan Detector ==="
  echo ""
  echo "Total rules:    $total"
  echo "Orphans:        $orphan_count (refs < $MIN_REFS)"
  echo ""
  if [[ ${#ORPHANS[@]} -gt 0 ]]; then
    echo "Orphan rules (candidate deprecate):"
    for o in "${ORPHANS[@]}"; do
      IFS='|' read -r r f <<< "$o"
      printf "  %3d refs  %s\n" "$r" "$f"
    done
    echo ""
  fi
  echo "VERDICT: $VERDICT"
  if [[ "$VERDICT" == "FAIL" ]]; then
    echo ""
    echo "Próximos pasos:"
    echo "  1. Para cada huérfana: decidir deprecate / integrate / leave-as-reference"
    echo "  2. Si deprecate: mover a docs/archive/rules/ + note"
    echo "  3. Si integrate: añadir references en agents/skills/scripts"
  fi
fi

exit $EXIT_CODE
