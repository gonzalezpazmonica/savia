#!/usr/bin/env bash
set -uo pipefail
# spec-quality-auditor.sh — Deterministic quality scorer for SDD specs
# Scores specs 0-100 against 9 criteria. No LLM. JSON output.
# Usage: bash scripts/spec-quality-auditor.sh <spec.md> [--batch DIR] [--min-score N]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_SCORE="${MIN_SCORE:-0}"
BATCH_DIR=""
FILE=""

[[ $# -eq 0 ]] && { echo "Usage: $0 <spec.md> [--batch DIR] [--min-score N]" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch) BATCH_DIR="$2"; shift 2 ;;
    --min-score) MIN_SCORE="$2"; shift 2 ;;
    --help|-h) echo "Usage: $0 <spec.md> [--batch DIR] [--min-score N]"; exit 0 ;;
    *) FILE="$1"; shift ;;
  esac
done

score_spec() {
  local file="$1"
  [[ ! -f "$file" ]] && echo '{"error":"file not found"}' && return

  local lines
  lines=$(wc -l < "$file")
  local name
  name=$(basename "$file")

  # C1: Header (10 pts) — has title with SPEC number
  local c1=0
  grep -qiE '^#.*SPEC-[0-9]+' "$file" && c1=10 || {
    grep -qiE '^#' "$file" && c1=5
  }

  # C2: Metadata (10 pts) — Status, Date, Author/Era
  local c2=0
  grep -qiE '(status|estado)\s*[:=]' "$file" && ((c2+=4)) || true
  grep -qiE '(date|fecha)\s*[:=]|[0-9]{4}-[0-9]{2}-[0-9]{2}' "$file" && ((c2+=3)) || true
  grep -qiE '(author|era|autor)\s*[:=]' "$file" && ((c2+=3)) || true

  # C3: Problem statement (15 pts)
  local c3=0
  grep -qiE '^##.*problem|^##.*problema' "$file" && c3=15 || {
    grep -qiE 'problem|issue|challenge|problema' "$file" && c3=8
  }

  # C4: Solution (15 pts)
  local c4=0
  grep -qiE '^##.*solution|^##.*soluci' "$file" && c4=15 || {
    grep -qiE 'solution|approach|propuesta|soluci' "$file" && c4=8
  }

  # C5: Acceptance criteria (15 pts) — measurable, testable
  local c5=0
  local ac_count
  ac_count=$(grep -ciE '(acceptance|criterio|criteria|AC-[0-9]|given.*when.*then|\- \[[ x]\])' "$file" || true)
  [[ -z "$ac_count" ]] && ac_count=0
  [[ $ac_count -ge 3 ]] && c5=15 || { [[ $ac_count -ge 1 ]] && c5=8; }

  # C6: Effort estimation (10 pts)
  local c6=0
  grep -qiE '(effort|esfuerzo|estimat|hours|horas|story.points|SP\b|[0-9]+h\b)' "$file" && c6=10

  # C7: Dependencies (5 pts)
  local c7=0
  grep -qiE '(depend|require|prerequis|SPEC-[0-9]+|blocker)' "$file" && c7=5

  # C8: Testability (10 pts) — mentions tests, verification
  local c8=0
  grep -qiE '(test|verificat|validat|assert|expect|bats|jest|pytest)' "$file" && c8=10

  # C9: Clarity (10 pts) — not too short, not too long, has structure
  local c9=0
  local section_count
  section_count=$(grep -c '^##' "$file" || true)
  [[ -z "$section_count" ]] && section_count=0
  [[ $lines -ge 20 && $lines -le 200 ]] && ((c9+=5)) || true
  [[ $section_count -ge 3 ]] && ((c9+=5)) || { [[ $section_count -ge 2 ]] && ((c9+=3)) || true; }

  local total=$((c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8 + c9))
  local certified=false
  [[ $total -ge 80 ]] && certified=true

  printf '{"file":"%s","total":%d,"certified":%s,"criteria":{"header":%d,"metadata":%d,"problem":%d,"solution":%d,"acceptance":%d,"effort":%d,"dependencies":%d,"testability":%d,"clarity":%d},"lines":%d}\n' \
    "$name" "$total" "$certified" "$c1" "$c2" "$c3" "$c4" "$c5" "$c6" "$c7" "$c8" "$c9" "$lines"
}

# ── Main ──

if [[ -n "$BATCH_DIR" ]]; then
  total=0; passed=0; failed=0
  while IFS= read -r -d '' spec; do
    result=$(score_spec "$spec")
    score=$(echo "$result" | grep -oP '"total":\K[0-9]+')
    ((total++)) || true
    if [[ $score -ge $MIN_SCORE ]]; then
      ((passed++)) || true
    else
      ((failed++)) || true
      echo "$result"
    fi
  done < <(find "$BATCH_DIR" -name 'SPEC-*.md' -type f -print0)
  echo "{\"batch\":true,\"total\":$total,\"passed\":$passed,\"failed\":$failed,\"min_score\":$MIN_SCORE}"
elif [[ -n "$FILE" ]]; then
  score_spec "$FILE"
else
  echo "Error: provide file or --batch DIR" >&2
  exit 1
fi
