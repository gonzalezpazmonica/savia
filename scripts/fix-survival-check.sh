#!/usr/bin/env bash
# fix-survival-check.sh — SPEC-188 F4 — Weekly fix survival audit
set -uo pipefail
#
# Scans git log for fix commits over the last N days, verifies each fix
# is still present in main (not reverted), and reports survival metrics.
#
# Usage:
#   bash scripts/fix-survival-check.sh [--days 7] [--json] [--branch main]
#
# Output JSON:
#   {
#     "week": "YYYY-WNN",
#     "checked_at": "ISO-8601",
#     "days_back": 7,
#     "fixes_total": N,
#     "fixes_survived": N,
#     "survival_rate": 0.XX,
#     "reverted": [{"commit": "abc123", "subject": "...", "reason": "revert detected"}]
#   }
#
# Cron example (weekly, Monday 06:00):
#   0 6 * * 1 cd /path/to/savia && bash scripts/fix-survival-check.sh --json
#
# Ref: SPEC-188 P4 — Diagnostic Quality Metrics
set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DAYS=7
JSON_MODE=false
BRANCH="main"

# ── Argument parsing ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --days)   DAYS="${2:-7}"; shift 2 ;;
    --json)   JSON_MODE=true; shift ;;
    --branch) BRANCH="${2:-main}"; shift 2 ;;
    *)        shift ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────
iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat())"; }
week_label() { date -u +"%G-W%V" 2>/dev/null || python3 -c "from datetime import date; d=date.today(); print(f'{d.isocalendar()[0]}-W{d.isocalendar()[1]:02d}')"; }
since_date() { date -u -d "$1 days ago" +"%Y-%m-%d" 2>/dev/null || python3 -c "from datetime import date, timedelta; print((date.today()-timedelta(days=$1)).isoformat())"; }

require_git() {
  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo '{"error":"not a git repository","fixes_total":0,"fixes_survived":0,"survival_rate":0}' >&2
    exit 1
  fi
}

require_git

SINCE=$(since_date "$DAYS")
CHECKED_AT=$(iso_now)
WEEK=$(week_label)

# ── Find fix commits in the last DAYS days ────────────────────────────────
# Match commits with subject starting with fix(, fix:, hotfix(, hotfix:, revert "fix
# BRANCH va como revisión: `--branches=main` sin comodín significa `refs/heads/main/*`
# y no devuelve nada, así que el recuento salía siempre en cero.
FIX_COMMITS=$(git -C "$REPO_ROOT" log \
  --since="$SINCE" \
  --format="%H %s" \
  "$BRANCH" -- \
  2>/dev/null \
  | grep -E '^[0-9a-f]{40} (fix[:(]|hotfix[:(]|bugfix[:(])' \
  | awk '{print $1}' \
  | head -200 \
  || true)

TOTAL=0
SURVIVED=0
REVERTED_LIST=""
WINDOW_BODIES=""
if [[ -n "$FIX_COMMITS" ]]; then
  WINDOW_BODIES=$(git -C "$REPO_ROOT" log --since="$SINCE" --format="%B" "$BRANCH" -- 2>/dev/null || true)
fi

if [[ -n "$FIX_COMMITS" ]]; then
  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    TOTAL=$((TOTAL + 1))

    SUBJECT=$(git -C "$REPO_ROOT" log -1 --format="%s" "$commit" 2>/dev/null || echo "unknown")

    # Check if a revert of this commit exists in the same window
    # A revert commit references the original SHA in its message: "Revert "...", "This reverts commit SHA"
    # `git revert` deja el SHA original en el cuerpo ("This reverts commit <sha>"),
    # no en el asunto: se busca ahí.
    REVERT_FOUND=$(printf '%s\n' "$WINDOW_BODIES" | grep -F "reverts commit ${commit}" || true)

    if [[ -n "$REVERT_FOUND" ]]; then
      # Reverted — did not survive
      SHORT="${commit:0:7}"
      SUBJECT_ESC=${SUBJECT//\\/\\\\}
      SUBJECT_ESC=${SUBJECT_ESC//\"/\\\"}
      REVERTED_LIST="${REVERTED_LIST}{\"commit\":\"${SHORT}\",\"subject\":\"${SUBJECT_ESC}\",\"reason\":\"revert detected\"},"
    else
      SURVIVED=$((SURVIVED + 1))
    fi
  done <<< "$FIX_COMMITS"
fi

# ── Compute survival rate ─────────────────────────────────────────────────
if [[ "$TOTAL" -eq 0 ]]; then
  RATE="1.0"
else
  RATE=$(python3 -c "print(round($SURVIVED / $TOTAL, 4))")
fi

# ── Strip trailing comma from reverted list ───────────────────────────────
REVERTED_ARRAY="[${REVERTED_LIST%,}]"

# ── Output ────────────────────────────────────────────────────────────────
OUTPUT="{\"week\":\"${WEEK}\",\"checked_at\":\"${CHECKED_AT}\",\"days_back\":${DAYS},\"fixes_total\":${TOTAL},\"fixes_survived\":${SURVIVED},\"survival_rate\":${RATE},\"reverted\":${REVERTED_ARRAY}}"

if $JSON_MODE; then
  echo "$OUTPUT" | python3 -m json.tool 2>/dev/null || echo "$OUTPUT"
else
  echo "Fix Survival Report — ${WEEK}"
  echo "  Period:   last ${DAYS} days (since ${SINCE})"
  echo "  Fixes:    ${SURVIVED}/${TOTAL} survived"
  echo "  Rate:     ${RATE}"
  if [[ "$REVERTED_LIST" != "" ]]; then
    echo "  Reverted:"
    echo "$REVERTED_ARRAY" | python3 -c "
import sys, json
for r in json.load(sys.stdin):
    print('    -', r['commit'], r['subject'][:60])
" 2>/dev/null || true
  fi
fi
