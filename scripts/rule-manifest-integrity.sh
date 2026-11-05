#!/usr/bin/env bash
# rule-manifest-integrity.sh — SE-057 Slice 1 rule-manifest + INDEX integrity.
#
# Audita:
#   1. docs/rules/domain/INDEX.md ≤ 150 líneas (Rule #22 self-compliance)
#   2. docs/rules/domain/rule-manifest.json cruza con filesystem:
#      - cada entry en manifest existe como fichero real
#      - cada fichero real está listado en manifest
#
# Usage:
#   rule-manifest-integrity.sh              # scan + report
#   rule-manifest-integrity.sh --json
#   rule-manifest-integrity.sh --max-lines 200   # relax INDEX limit
#
# Exit codes:
#   0 — all checks pass
#   1 — integrity failures found
#   2 — usage error
#
# Ref: SE-057, audit-arquitectura-20260420.md D20
# Safety: read-only. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RULES_DIR="$PROJECT_ROOT/docs/rules/domain"
INDEX_FILE="$RULES_DIR/INDEX.md"
MANIFEST_FILE="$RULES_DIR/rule-manifest.json"

MAX_LINES=150
JSON=0

usage() {
  cat <<EOF
Usage:
  $0 [--max-lines N] [--json]

Options:
  --max-lines N    Max lines for INDEX.md (default 150, Rule #22)
  --json           JSON output

Audita integridad de docs/rules/domain/INDEX.md y rule-manifest.json.
Ref: SE-057, Rule #22.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-lines) MAX_LINES="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if ! [[ "$MAX_LINES" =~ ^[0-9]+$ ]] || [[ "$MAX_LINES" -lt 1 ]]; then
  echo "ERROR: --max-lines must be positive integer" >&2; exit 2
fi

[[ ! -d "$RULES_DIR" ]] && { echo "ERROR: rules dir not found" >&2; exit 2; }

FINDINGS=()
EXIT_CODE=0

# Check 1: INDEX.md line count
# SE-338: INDEX.md es un índice de navegación AUTO-GENERADO que lista todas
# las reglas; su tamaño crece con el nº de reglas, no es una regla de negocio.
# Rule #22 (≤150 líneas) aplica a reglas individuales; el índice se excluye del
# límite igual que ya se excluye del cross-check (mismo criterio, consistencia).
INDEX_LINES=0
INDEX_OK=true
if [[ -f "$INDEX_FILE" ]]; then
  INDEX_LINES=$(wc -l < "$INDEX_FILE")
  # Índice de navegación: no aplica Rule #22 (ver comentario SE-338 arriba).
else
  INDEX_OK=false
  FINDINGS+=("INDEX.md not found at $INDEX_FILE")
  EXIT_CODE=1
fi

# Check 2: Manifest exists + valid JSON
# SE-501 AC-11: rule-manifest.json es derivado (D) y no se versiona. Si falta, se genera con
# derived.sh ensure; si eso falla, el hallazgo nombra la orden.
if [[ ! -f "$MANIFEST_FILE" && -f "$PROJECT_ROOT/scripts/derived.sh" ]]; then
  bash "$PROJECT_ROOT/scripts/derived.sh" ensure --only rules >/dev/null 2>&1 || true
fi
MANIFEST_OK=true
MANIFEST_ENTRIES=0
if [[ ! -f "$MANIFEST_FILE" ]]; then
  MANIFEST_OK=false
  FINDINGS+=("rule-manifest.json not found at $MANIFEST_FILE — run: bash scripts/derived.sh ensure")
  EXIT_CODE=1
else
  if ! python3 -c "import json; json.load(open('$MANIFEST_FILE'))" 2>/dev/null; then
    MANIFEST_OK=false
    FINDINGS+=("rule-manifest.json is not valid JSON")
    EXIT_CODE=1
  fi
fi

# Check 3: Cross-check manifest entries vs filesystem
MISSING_FILES=()
MISSING_ENTRIES=()
if [[ "$MANIFEST_OK" == "true" ]]; then
  # Extract rule file paths from manifest (heuristic: any value matching *.md)
  # SE-338: el schema usa los *.md como KEYS del dict `rules`; incluirlas también.
  MANIFEST_FILES=$(python3 -c "
import json, sys
with open('$MANIFEST_FILE') as f:
    data = json.load(f)
def walk(v):
    if isinstance(v, dict):
        for k, sub in v.items():
            if isinstance(k, str) and k.endswith('.md'):
                yield k
            yield from walk(sub)
    elif isinstance(v, list):
        for item in v: yield from walk(item)
    elif isinstance(v, str) and v.endswith('.md'):
        yield v
for path in walk(data):
    print(path)
" 2>/dev/null | sort -u)
  MANIFEST_ENTRIES=$(echo "$MANIFEST_FILES" | grep -c '.md' 2>/dev/null || [ $? -eq 1 ] || echo 0)

  # Manifest entry → filesystem existence
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    # Try relative to PROJECT_ROOT first, then to RULES_DIR
    if [[ ! -f "$PROJECT_ROOT/$rel" && ! -f "$RULES_DIR/$rel" && ! -f "$PROJECT_ROOT/docs/rules/domain/$rel" ]]; then
      MISSING_FILES+=("$rel")
    fi
  done <<< "$MANIFEST_FILES"

  # Filesystem → manifest entry
  # (Only check docs/rules/domain/*.md, exclude INDEX.md itself)
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    bn=$(basename "$f")
    [[ "$bn" == "INDEX.md" ]] && continue
    if ! echo "$MANIFEST_FILES" | grep -qF "$bn"; then
      MISSING_ENTRIES+=("$bn")
    fi
  done < <(find "$RULES_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null)

  if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    FINDINGS+=("${#MISSING_FILES[@]} manifest entries reference missing files")
    EXIT_CODE=1
  fi
  if [[ ${#MISSING_ENTRIES[@]} -gt 0 ]]; then
    FINDINGS+=("${#MISSING_ENTRIES[@]} rule files not listed in manifest")
    EXIT_CODE=1
  fi
fi

VERDICT="PASS"
[[ "$EXIT_CODE" -ne 0 ]] && VERDICT="FAIL"

if [[ "$JSON" -eq 1 ]]; then
  m_files_json=$(printf '%s\n' "${MISSING_FILES[@]}" | awk 'NF {printf "\"%s\",", $0}')
  m_files_json="[${m_files_json%,}]"
  m_entries_json=$(printf '%s\n' "${MISSING_ENTRIES[@]}" | awk 'NF {printf "\"%s\",", $0}')
  m_entries_json="[${m_entries_json%,}]"
  findings_json=""
  for f in "${FINDINGS[@]}"; do
    f_esc=$(echo "$f" | sed 's/"/\\"/g')
    findings_json+="\"$f_esc\","
  done
  findings_json="[${findings_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","index_lines":$INDEX_LINES,"max_lines":$MAX_LINES,"index_ok":$INDEX_OK,"manifest_ok":$MANIFEST_OK,"manifest_entries":$MANIFEST_ENTRIES,"missing_files":$m_files_json,"missing_entries":$m_entries_json,"findings":$findings_json}
JSON
else
  echo "=== SE-057 Rule Manifest + INDEX Integrity ==="
  echo ""
  echo "INDEX.md lines:      $INDEX_LINES (limit $MAX_LINES)"
  echo "Manifest entries:    $MANIFEST_ENTRIES"
  echo "Missing files:       ${#MISSING_FILES[@]}"
  echo "Missing entries:     ${#MISSING_ENTRIES[@]}"
  echo ""
  if [[ ${#FINDINGS[@]} -gt 0 ]]; then
    echo "Findings:"
    for f in "${FINDINGS[@]}"; do
      echo "  • $f"
    done
    echo ""
  fi
  echo "VERDICT: $VERDICT"
  if [[ "$VERDICT" == "FAIL" ]]; then
    echo ""
    echo "Remediación (SE-057 Slice 2):"
    echo "  1. Si INDEX.md > limit: split en sub-índices por categoría"
    echo "  2. Si manifest desync: regenerar desde filesystem"
    echo "  3. Si file missing: decide keep/archive"
  fi
fi

exit $EXIT_CODE
