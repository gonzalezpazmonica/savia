#!/usr/bin/env bash
# workspace-health.sh — Comprehensive health dashboard for pm-workspace
# Aggregates all quality signals into a single health score.
#
# Usage: bash scripts/workspace-health.sh [--summary | --json | --ci] [--v2]
#   --v2    Enable CodeFlow-inspired extended dimensions (blast radius,
#           code ownership, dead code detection)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="--summary"
V2=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary|--json|--ci) MODE="$1"; shift ;;
    --v2) V2=true; shift ;;
    *) shift ;;
  esac
done

# ── Helper functions ──
count_glob() {
  local n=0
  for f in $1; do [ -e "$f" ] && n=$((n + 1)); done
  echo "$n"
}

pct() {
  local num=$1 den=$2
  if [ "$den" -eq 0 ]; then echo 0; return; fi
  echo $(( (num * 100) / den ))
}

grade() {
  local score=$1
  if [ "$score" -ge 90 ]; then echo "A"
  elif [ "$score" -ge 80 ]; then echo "B"
  elif [ "$score" -ge 70 ]; then echo "C"
  elif [ "$score" -ge 60 ]; then echo "D"
  else echo "F"
  fi
}

# ── Gather metrics ──

# 1. Component completeness
TOTAL_SKILLS=$(count_glob "$ROOT/.opencode/skills/*/")
SKILLS_WITH_MD=$(count_glob "$ROOT/.opencode/skills/*/SKILL.md")
SKILL_COMPLETENESS=$(pct "$SKILLS_WITH_MD" "$TOTAL_SKILLS")

TOTAL_COMMANDS=$(count_glob "$ROOT/.opencode/commands/*.md")
CMD_WITH_FM=0
for f in "$ROOT/.opencode/commands/"*.md; do
  [ -f "$f" ] || continue
  head -1 "$f" | grep -q "^---$" && CMD_WITH_FM=$((CMD_WITH_FM + 1))
done
CMD_COMPLETENESS=$(pct "$CMD_WITH_FM" "$TOTAL_COMMANDS")

# 2. Maturity distribution
STABLE=$(grep -rlE "^[[:space:]]*(savia\.)?maturity: stable" "$ROOT/.opencode/skills/"*/SKILL.md 2>/dev/null | wc -l)
BETA=$(grep -rlE "^[[:space:]]*(savia\.)?maturity: beta" "$ROOT/.opencode/skills/"*/SKILL.md 2>/dev/null | wc -l)
ALPHA=$(grep -rlE "^[[:space:]]*(savia\.)?maturity: alpha" "$ROOT/.opencode/skills/"*/SKILL.md 2>/dev/null | wc -l)
MATURITY_SCORE=$(pct "$((STABLE * 3 + BETA * 2 + ALPHA * 1))" "$((TOTAL_SKILLS * 3))")

# 3. Test coverage
TOTAL_HOOKS=$(count_glob "$ROOT/.opencode/hooks/*.sh")
TESTED_HOOKS=0
for h in "$ROOT/.opencode/hooks/"*.sh; do
  [ -f "$h" ] || continue
  name=$(basename "$h" .sh)
  ls "$ROOT"/tests/hooks/test-"$name"*.bats 2>/dev/null | grep -q . && TESTED_HOOKS=$((TESTED_HOOKS + 1))
done
TEST_COVERAGE=$(pct "$TESTED_HOOKS" "$TOTAL_HOOKS")

# 4. Security posture
SEC_FINDINGS=0
SEC_OUTPUT=$(bash "$ROOT/scripts/security-scan.sh" --ci 2>&1)
echo "$SEC_OUTPUT" | grep -q "FAIL" && SEC_FINDINGS=1
VULN_FINDINGS=0
VULN_OUTPUT=$(bash "$ROOT/scripts/vuln-scan.sh" --ci 2>&1)
echo "$VULN_OUTPUT" | grep -q "FAIL" && VULN_FINDINGS=1
SECURITY_SCORE=$( [ "$SEC_FINDINGS" -eq 0 ] && [ "$VULN_FINDINGS" -eq 0 ] && echo 100 || echo 50 )

# SE-105: GLM governance manifest check (non-blocking, advisory)
GLM_STATUS="skip"
if [[ -x "$ROOT/scripts/glm-validate.sh" ]]; then
  GLM_OUTPUT=$(cd "$ROOT" && bash "$ROOT/scripts/glm-validate.sh" 2>&1) || true
  echo "$GLM_OUTPUT" | grep -q "^FAIL" && GLM_STATUS="fail" || GLM_STATUS="pass"
fi

# 5. Documentation
DOCS_REQUIRED=("LICENSE" "README.md" "CHANGELOG.md" "CONTRIBUTING.md" "SECURITY.md" "docs/QUICK-START.md" "docs/ROADMAP.md")
DOCS_PRESENT=0
for d in "${DOCS_REQUIRED[@]}"; do
  [ -f "$ROOT/$d" ] && DOCS_PRESENT=$((DOCS_PRESENT + 1))
done
DOC_SCORE=$(pct "$DOCS_PRESENT" "${#DOCS_REQUIRED[@]}")

# 6. CI coverage
CI_FILES=$(count_glob "$ROOT/.github/workflows/*.yml")
CI_SCORE=$( [ "$CI_FILES" -ge 1 ] && echo 100 || echo 0 )

# ── V2: Extended dimensions (CodeFlow-inspired) ──
BLAST_SCORE=50
BLAST_WARN=false
TOP_FRAGILE=""
OWNERSHIP_SCORE=0
OWNERSHIP_WARN=false
DEAD_CODE_SCORE=100
DEAD_CODE_WARN=false
dead_funcs=0
total_funcs=0

if $V2; then

  # 7. Blast Radius — aggregate fragility of top-N most-referenced scripts
  BLAST_SCRIPT="$ROOT/scripts/blast-radius.sh"
  if [[ -x "$BLAST_SCRIPT" ]]; then
    max_blast=0
    fragile_files=""
    count=0
    for f in "$ROOT"/scripts/*.sh; do
      [[ $count -ge 3 ]] && break
      [[ ! -f "$f" ]] && continue
      local_f="${f#$ROOT/}"
      blast_out=$(bash "$BLAST_SCRIPT" --json --depth 1 "$local_f" 2>/dev/null || echo '{"risk_score":0}')
      risk=$(echo "$blast_out" | grep -oE '"risk_score": [0-9]+' | grep -oE '[0-9]+' || echo 0)
      impacted=$(echo "$blast_out" | grep -oE '"total_impacted": [0-9]+' | grep -oE '[0-9]+' || echo 0)
      if [[ "$impacted" -gt 0 ]]; then
        fragile_files="$fragile_files $local_f"
        count=$((count + 1))
      fi
      [[ "$risk" -gt "$max_blast" ]] && max_blast=$risk
    done
    BLAST_SCORE=$((100 - max_blast))
    [[ "$BLAST_SCORE" -lt 0 ]] && BLAST_SCORE=0
    TOP_FRAGILE="${fragile_files# }"
  else
    BLAST_WARN=true
  fi

  # 8. Code Ownership — diversity of git authors
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    total_tracked=0
    multi_author=0
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ "$f" =~ ^(vendor|node_modules|\.git|output)/ ]] && continue
      total_tracked=$((total_tracked + 1))
      authors=$(git -C "$ROOT" log --since="90 days ago" --format="%an" -- "$f" 2>/dev/null | sort -u | wc -l)
      [[ "$authors" -ge 2 ]] && multi_author=$((multi_author + 1))
      [[ $total_tracked -gt 200 ]] && break
    done < <(git -C "$ROOT" ls-files 2>/dev/null)
    if [[ "$total_tracked" -gt 0 ]]; then
      OWNERSHIP_SCORE=$(pct "$multi_author" "$total_tracked")
    fi
  else
    OWNERSHIP_WARN=true
  fi

  # 9. Dead Code — functions defined but never referenced (bash scripts only)
  # Una sola pasada: nº de scripts distintos que contienen cada palabra.
  declare -A WORD_FILES=()
  while read -r w c; do
    WORD_FILES["$w"]=$c
  done < <(awk 'FNR==1 { delete seen }
    { n = split($0, a, /[^_a-zA-Z0-9]+/)
      for (i = 1; i <= n; i++) { w = a[i]
        if (w != "" && !((w) in seen)) { seen[w] = 1; cnt[w]++ } } }
    END { for (w in cnt) print w, cnt[w] }' "$ROOT"/scripts/*.sh 2>/dev/null)
  for script in "$ROOT"/scripts/*.sh; do
    [[ ! -f "$script" ]] && continue
    while IFS= read -r line; do
      func_name=$(echo "$line" | sed -nE 's/^[[:space:]]*(function[[:space:]]+)?([_a-zA-Z][_a-zA-Z0-9]*)[[:space:]]*\(.*/\2/p')
      [[ -z "$func_name" ]] && continue
      total_funcs=$((total_funcs + 1))
      # el propio script que la define cuenta 1: refs externas = total - 1
      refs=$(( ${WORD_FILES[$func_name]:-1} - 1 ))
      [[ "$refs" -eq 0 ]] && dead_funcs=$((dead_funcs + 1))
    done < <(grep -E '^[[:space:]]*(function[[:space:]]+[_a-zA-Z][_a-zA-Z0-9]*|[_a-zA-Z][_a-zA-Z0-9]*[[:space:]]*\(\))' "$script" 2>/dev/null)
  done
  if [[ "$total_funcs" -gt 0 ]]; then
    dead_pct=$(pct "$dead_funcs" "$total_funcs")
    DEAD_CODE_SCORE=$((100 - dead_pct))
    [[ "$DEAD_CODE_SCORE" -lt 0 ]] && DEAD_CODE_SCORE=0
  fi

fi

# ── Calculate overall health ──
if $V2; then
  OVERALL=$(( (SKILL_COMPLETENESS * 15 + CMD_COMPLETENESS * 10 + MATURITY_SCORE * 10 + \
               TEST_COVERAGE * 15 + SECURITY_SCORE * 15 + DOC_SCORE * 10 + \
               BLAST_SCORE * 10 + OWNERSHIP_SCORE * 10 + DEAD_CODE_SCORE * 5) / 100 ))
else
  OVERALL=$(( (SKILL_COMPLETENESS * 20 + CMD_COMPLETENESS * 15 + MATURITY_SCORE * 15 + \
               TEST_COVERAGE * 20 + SECURITY_SCORE * 20 + DOC_SCORE * 10) / 100 ))
fi

# ── Output ──
if [ "$MODE" = "--json" ]; then
  if $V2; then
    cat <<JSON
{
  "generated": "$(date -Iseconds)",
  "version": 2,
  "overall": { "score": $OVERALL, "grade": "$(grade $OVERALL)" },
  "dimensions": {
    "skill_completeness": { "score": $SKILL_COMPLETENESS, "grade": "$(grade $SKILL_COMPLETENESS)", "detail": "$SKILLS_WITH_MD/$TOTAL_SKILLS skills have SKILL.md" },
    "command_completeness": { "score": $CMD_COMPLETENESS, "grade": "$(grade $CMD_COMPLETENESS)", "detail": "$CMD_WITH_FM/$TOTAL_COMMANDS commands have frontmatter" },
    "maturity": { "score": $MATURITY_SCORE, "grade": "$(grade $MATURITY_SCORE)", "stable": $STABLE, "beta": $BETA, "alpha": $ALPHA },
    "test_coverage": { "score": $TEST_COVERAGE, "grade": "$(grade $TEST_COVERAGE)", "tested": $TESTED_HOOKS, "total": $TOTAL_HOOKS },
    "security": { "score": $SECURITY_SCORE, "grade": "$(grade $SECURITY_SCORE)", "findings": $SEC_FINDINGS, "vulns": $VULN_FINDINGS },
    "documentation": { "score": $DOC_SCORE, "grade": "$(grade $DOC_SCORE)", "present": $DOCS_PRESENT, "required": ${#DOCS_REQUIRED[@]} },
    "blast_radius": { "score": $BLAST_SCORE, "grade": "$(grade $BLAST_SCORE)"$([ -n "$TOP_FRAGILE" ] && echo ", \"top_fragile_files\": \"$TOP_FRAGILE\"")$($BLAST_WARN && echo ", \"warning\": \"blast-radius.sh not found, using default\"") },
    "code_ownership": { "score": $OWNERSHIP_SCORE, "grade": "$(grade $OWNERSHIP_SCORE)"$($OWNERSHIP_WARN && echo ", \"warning\": \"no git repo, cannot measure\"") },
    "dead_code": { "score": $DEAD_CODE_SCORE, "grade": "$(grade $DEAD_CODE_SCORE)", "dead_functions": $dead_funcs, "total_functions": $total_funcs }
  }
}
JSON
  else
    cat <<JSON
{
  "generated": "$(date -Iseconds)",
  "overall": { "score": $OVERALL, "grade": "$(grade $OVERALL)" },
  "dimensions": {
    "skill_completeness": { "score": $SKILL_COMPLETENESS, "detail": "$SKILLS_WITH_MD/$TOTAL_SKILLS skills have SKILL.md" },
    "command_completeness": { "score": $CMD_COMPLETENESS, "detail": "$CMD_WITH_FM/$TOTAL_COMMANDS commands have frontmatter" },
    "maturity": { "score": $MATURITY_SCORE, "stable": $STABLE, "beta": $BETA, "alpha": $ALPHA },
    "test_coverage": { "score": $TEST_COVERAGE, "tested": $TESTED_HOOKS, "total": $TOTAL_HOOKS },
    "security": { "score": $SECURITY_SCORE, "findings": $SEC_FINDINGS, "vulns": $VULN_FINDINGS },
    "documentation": { "score": $DOC_SCORE, "present": $DOCS_PRESENT, "required": ${#DOCS_REQUIRED[@]} }
  }
}
JSON
  fi

elif [ "$MODE" = "--ci" ]; then
  echo "Workspace Health: $OVERALL% ($(grade $OVERALL))"
  if $V2; then
    echo "  Blast: $(grade $BLAST_SCORE) | Ownership: $(grade $OWNERSHIP_SCORE) | DeadCode: $(grade $DEAD_CODE_SCORE)"
  fi
  if [ "$OVERALL" -lt 60 ]; then
    echo "FAIL: Health score below 60%"
    exit 1
  fi
  echo "PASS: Health score $OVERALL% >= 60%"

else
  echo "═══════════════════════════════════════════════════════════════"
  if $V2; then
    echo "  Health Dashboard v2 — pm-workspace (CodeFlow-enhanced)"
  else
    echo "  Health Dashboard — pm-workspace"
  fi
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "  Overall Health: $OVERALL% ($(grade $OVERALL))"
  echo ""
  echo "  ┌──────────────────────────┬───────┬───────┐"
  echo "  │ Dimension                │ Score │ Grade │"
  echo "  ├──────────────────────────┼───────┼───────┤"
  printf "  │ %-24s │ %4d%% │   %s   │\n" "Skill completeness" "$SKILL_COMPLETENESS" "$(grade $SKILL_COMPLETENESS)"
  printf "  │ %-24s │ %4d%% │   %s   │\n" "Command completeness" "$CMD_COMPLETENESS" "$(grade $CMD_COMPLETENESS)"
  printf "  │ %-24s │ %4d%% │   %s   │\n" "Maturity distribution" "$MATURITY_SCORE" "$(grade $MATURITY_SCORE)"
  printf "  │ %-24s │ %4d%% │   %s   │\n" "Test coverage" "$TEST_COVERAGE" "$(grade $TEST_COVERAGE)"
  printf "  │ %-24s │ %4d%% │   %s   │\n" "Security posture" "$SECURITY_SCORE" "$(grade $SECURITY_SCORE)"
  printf "  │ %-24s │ %4d%% │   %s   │\n" "Documentation" "$DOC_SCORE" "$(grade $DOC_SCORE)"
  if $V2; then
    echo "  ├──────────────────────────┼───────┼───────┤"
    printf "  │ %-24s │ %4d%% │   %s   │\n" "Blast radius" "$BLAST_SCORE" "$(grade $BLAST_SCORE)"
    printf "  │ %-24s │ %4d%% │   %s   │\n" "Code ownership" "$OWNERSHIP_SCORE" "$(grade $OWNERSHIP_SCORE)"
    printf "  │ %-24s │ %4d%% │   %s   │\n" "Dead code" "$DEAD_CODE_SCORE" "$(grade $DEAD_CODE_SCORE)"
  fi
  echo "  └──────────────────────────┴───────┴───────┘"
  echo ""
  echo "  Components: $TOTAL_COMMANDS commands, $TOTAL_SKILLS skills,"
  echo "              $(count_glob "$ROOT/.opencode/agents/*.md") agents, $TOTAL_HOOKS hooks"
  echo "  GLM governance manifest: $GLM_STATUS"
  if $V2; then
    echo "  Top fragile: ${TOP_FRAGILE:-none}"
    echo "  Dead functions: $dead_funcs / $total_funcs"
  fi
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
fi
