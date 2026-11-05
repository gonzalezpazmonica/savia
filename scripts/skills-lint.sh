#!/usr/bin/env bash
# skills-lint.sh — SE-270 Slice 1 — Skill description routing rule validator
#
# For each SKILL.md in .opencode/skills/*/ checks:
#   1. Description length (target 200-400 chars, warn <150 or >500)
#   2. Description contains trigger phrases (action verbs for user intent)
#   3. Description declares expected inputs and outputs (consumes/produces)
#   4. YAML frontmatter has name and description fields
#
# Usage:
#   bash scripts/skills-lint.sh                # table output, exit 1 on issues
#   bash scripts/skills-lint.sh --json         # JSON output
#   bash scripts/skills-lint.sh --skill NAME   # single skill
#
# Exit 0 if no issues (all OK), exit 1 if WARN or FAIL issues found.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -n "${SAVIA_SKILLS_DIR:-}" ]]; then
  SKILLS_DIR="$SAVIA_SKILLS_DIR"
else
  SKILLS_DIR="$(cd -P "$ROOT/.opencode/skills" && pwd)"
fi

MODE_JSON=false
FILTER_SKILL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)  MODE_JSON=true ;;
    --skill) shift; FILTER_SKILL="${1:-}" ;;
    --help|-h)
      sed -n '2,14p' "$0" | sed 's/^# //'
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

count_pass=0
count_warn=0
count_fail=0
count_total=0
results_json=()

# ── Parse all skills via python3 (handles YAML block scalars properly) ─────────
parse_all_skills() {
  python3 -c "
import os, json, sys, re

SKILLS_DIR = '$SKILLS_DIR'
results = []

TRIGGER_PATTERNS = [
    'Usar cuando', 'Use when', 'Detecta', 'Detects', 'Analiza', 'Analyzes',
    'Genera', 'Generates', 'Extrae', 'Extracts', 'Verifica', 'Verifies',
    'Valida', 'Validates', 'Escanea', 'Scans', 'Redacta', 'Drafts',
    'Crea', 'Creates', 'Diseña', 'Designs', 'Implementa', 'Implements',
    'Audita', 'Audits', 'Mapea', 'Maps', 'Gestiona', 'Manages',
    'Construye', 'Builds', 'Evalúa', 'Evaluates', 'Revisa', 'Reviews',
    'Strips', 'Elevates', 'Mapear', 'Captura',
]

for d in sorted(os.listdir(SKILLS_DIR)):
    if d == '_template':
        continue
    md = os.path.join(SKILLS_DIR, d, 'SKILL.md')
    reasons = []
    status = 'OK'

    if not os.path.isfile(md):
        results.append({'skill': d, 'status': 'FAIL', 'reasons': ['SKILL.md missing']})
        continue

    with open(md) as f:
        content = f.read()

    parts = content.split('---', 2)
    fm = {}
    if len(parts) >= 3:
        try:
            import yaml
            fm = yaml.safe_load(parts[1]) or {}
        except Exception:
            pass

    has_name = 'name' in fm
    has_desc = 'description' in fm

    if not has_name:
        status = 'FAIL'
        reasons.append(\"missing frontmatter 'name'\")
    if not has_desc:
        status = 'FAIL'
        reasons.append(\"missing frontmatter 'description'\")

    if has_desc:
        desc = str(fm['description']).strip()
        desc_len = len(desc)

        if desc_len < 150:
            reasons.append(f'description too short ({desc_len} chars, target 200-400)')
        elif desc_len > 500:
            reasons.append(f'description too long ({desc_len} chars, max 500)')

        has_trigger = False
        for p in TRIGGER_PATTERNS:
            if p.lower() in desc.lower():
                has_trigger = True
                break
        if not has_trigger:
            reasons.append('no trigger phrase found (add Usar cuando/Use when/etc)')

        # SE-333 dual-read: canonical metadata.savia.consumes/produces first
        meta = fm.get('metadata') or {}
        has_consumes = bool(
            (fm.get('consumes') not in (None, [], ''))
            or (meta.get('savia.consumes') not in (None, '', []))
        )
        has_produces = bool(
            (fm.get('produces') not in (None, [], ''))
            or (meta.get('savia.produces') not in (None, '', []))
        )

        if not has_consumes and not has_produces:
            reasons.append('no consumes/produces declared in frontmatter (SE-152)')
        elif not has_consumes:
            reasons.append('no consumes declared in frontmatter')
        elif not has_produces:
            reasons.append('no produces declared in frontmatter')

    if status == 'OK' and reasons:
        status = 'WARN'

    if status == 'OK':
        reasons.append('')

    results.append({'skill': d, 'status': status, 'reasons': reasons})

print(json.dumps(results, ensure_ascii=False))
" 2>/dev/null
}

# ── Build skill list ───────────────────────────────────────────────────────────
if [[ -n "$FILTER_SKILL" ]]; then
  target_dir="$SKILLS_DIR/$FILTER_SKILL"
  if [[ ! -d "$target_dir" ]]; then
    echo "FAIL: skill '${FILTER_SKILL}' not found in ${SKILLS_DIR}" >&2
    exit 1
  fi
fi

# ── Run lint via python3 ───────────────────────────────────────────────────────
lint_results="$(parse_all_skills)"
if [[ -z "$lint_results" ]]; then
  echo "ERROR: failed to parse skills" >&2
  exit 1
fi

# ── Process results ────────────────────────────────────────────────────────────
if ! $MODE_JSON; then
  printf "%-42s  %-6s  %s\n" "SKILL" "STATUS" "ISSUES"
  printf '%0.s-' {1..100}
  echo
fi

while IFS= read -r line; do
  skill_name=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['skill'])")
  skill_status=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  skill_reasons=$(echo "$line" | python3 -c "import json,sys; r=json.load(sys.stdin)['reasons']; print('; '.join([x for x in r if x]) if any(r) else '-')")

  # Filter if --skill specified
  if [[ -n "$FILTER_SKILL" && "$skill_name" != "$FILTER_SKILL" ]]; then
    continue
  fi

  count_total=$((count_total + 1))
  case "$skill_status" in
    OK)   count_pass=$((count_pass + 1)) ;;
    WARN) count_warn=$((count_warn + 1)) ;;
    FAIL) count_fail=$((count_fail + 1)) ;;
  esac

  if $MODE_JSON; then
    reason_json="${skill_reasons//\"/\\\"}"
    results_json+=("{\"skill\":\"$skill_name\",\"status\":\"$skill_status\",\"reasons\":\"$reason_json\"}")
  else
    printf "%-42s  %-6s  %s\n" "$skill_name" "$skill_status" "$skill_reasons"
  fi
done < <(echo "$lint_results" | python3 -c "import json,sys; [print(json.dumps(r,ensure_ascii=False)) for r in json.load(sys.stdin)]" 2>/dev/null)

# ── Summary ────────────────────────────────────────────────────────────────────
summary="PASS: ${count_pass} | WARN: ${count_warn} | FAIL: ${count_fail} | TOTAL: ${count_total}"

if $MODE_JSON; then
  echo "["
  for i in "${!results_json[@]}"; do
    if [[ $i -lt $((${#results_json[@]} - 1)) ]]; then
      echo "  ${results_json[$i]},"
    else
      echo "  ${results_json[$i]}"
    fi
  done
  echo "]"
  echo "$summary" >&2
else
  printf '%0.s-' {1..100}
  echo
  echo "$summary"
fi

[[ "$count_fail" -gt 0 || "$count_warn" -gt 0 ]] && exit 1 || exit 0
