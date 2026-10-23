#!/usr/bin/env bash
set -euo pipefail
# ci-select-bats.sh — Dynamic BATS test selector based on changed files
#
# Usage:
#   ci-select-bats.sh [--base <ref>] [--verbose]
#
# Exit codes:
#   0 → tests selected (prints space-separated list of .bats file names)
#   1 → FULL suite needed (too many changes)
#   2 → error

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BATS_DIR="$ROOT/tests/bats"
DEPS_FILE="$BATS_DIR/.deps.json"
BASE_REF="origin/main"
VERBOSE=false
FULL_THRESHOLD="${SAVIA_BATS_FULL_THRESHOLD_PCT:-30}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_REF="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=true; shift ;;
    *) shift ;;
  esac
done

log() { $VERBOSE && echo "$@" >&2 || true; }

if [[ ! -f "$DEPS_FILE" ]]; then
  echo "ERROR: .deps.json not found. Run: bash scripts/ci-bats-deps.sh --generate" >&2
  echo "FULL"
  exit 1
fi

if ! git rev-parse "$BASE_REF" >/dev/null 2>&1; then
  log "WARNING: $BASE_REF not found, falling back to HEAD~1"
  CHANGED=$(git diff --name-only HEAD~1 2>/dev/null || true)
else
  CHANGED=$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true)
fi

PR_BASE=$(git merge-base HEAD "$BASE_REF" 2>/dev/null || echo "")
if [[ -n "$PR_BASE" ]]; then
  CHANGED=$(git diff --name-only "$PR_BASE" HEAD 2>/dev/null || true)
  log "Using merge-base: $PR_BASE"
fi

if [[ -z "${CHANGED// /}" ]]; then
  log "No file changes detected"
  SELECTED=$(python3 -c "import json; print(' '.join(json.load(open('$DEPS_FILE'))['core_tests']))")
  echo "$SELECTED"
  exit 0
fi

log "Changed files:"
$VERBOSE && echo "$CHANGED" | sed 's/^/  /' >&2

TOTAL_TESTS=$(python3 -c "import json; print(json.load(open('$DEPS_FILE'))['total_tests'])")
SELECTED=""

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  matched=$(python3 -c "
import fnmatch, json, sys
deps = json.load(open('$DEPS_FILE'))
f = sys.argv[1].strip()
tests = set()

if f in deps.get('mappings', {}):
    tests.update(deps['mappings'][f])

for d, dt in deps.get('dir_rules', {}).items():
    if f == d or f.startswith(d.rstrip('/') + '/'):
        tests.update(dt)

for pattern, pt in deps.get('mappings', {}).items():
    if '*' in pattern and fnmatch.fnmatchcase(f, pattern):
        tests.update(pt)

for t in sorted(tests):
    print(t)
" "$file")

  if [[ -n "$matched" ]]; then
    while IFS= read -r t; do
      [[ -n "$t" ]] && SELECTED="$SELECTED $t"
    done <<< "$matched"
  fi
done <<< "$CHANGED"

CORE=$(python3 -c "import json; print(' '.join(json.load(open('$DEPS_FILE'))['core_tests']))")
SELECTED="$SELECTED $CORE"

SELECTED=$(echo "$SELECTED" | tr ' ' '\n' | sort -u | tr '\n' ' ')
SELECTED="${SELECTED## }"; SELECTED="${SELECTED%% }"

SELECTED_COUNT=$(echo "$SELECTED" | wc -w)

if [[ "$SELECTED_COUNT" -eq 0 ]]; then
  log "No tests matched, running core only"
  echo "$CORE"
  exit 0
fi

if [[ "$SELECTED_COUNT" -gt $(( TOTAL_TESTS * FULL_THRESHOLD / 100 )) ]]; then
  log "Threshold: $SELECTED_COUNT/$TOTAL_TESTS tests selected (>${FULL_THRESHOLD}%)"
  echo "FULL"
  exit 1
fi

log "Selected $SELECTED_COUNT/$TOTAL_TESTS tests"
echo "$SELECTED"
