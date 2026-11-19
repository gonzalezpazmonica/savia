#!/usr/bin/env bash
# corporate-no-write-assert.sh — SE-271 S5: Assert no corp input → instance write
set -uo pipefail
#
# Usage:
#   scripts/corporate-no-write-assert.sh [--corp-registry PATH]
#
# Scans for remote input patterns that could modify instance config.
# Exit 0=clean, 1=found write path.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

cd "$REPO_ROOT"

FOUND=()
EXIT_CODE=0

SCAN_DIRS="scripts .opencode/hooks .opencode/plugins docs"
SCAN_EXTS="-name '*.sh' -o -name '*.ts' -o -name '*.py' -o -name '*.md'"

check_pattern() {
  local desc="$1" pat="$2"
  while IFS= read -r -d '' f; do
    [[ "$f" == *"no-write-assert"* ]] && continue
    [[ "$f" == *"corporate-attest"* ]] && continue
    if grep -qn "$pat" "$f" 2>/dev/null; then
      FOUND+=("$f:$desc")
      EXIT_CODE=1
    fi
  done < <(eval find "$SCAN_DIRS" -type f \( "$SCAN_EXTS" \) -print0 2>/dev/null)
}

# Pattern: fetch remote content and write to instance config
check_pattern "fetch+write-config" 'curl.*>.*settings\|wget.*-O.*config\|fetch.*>.*\.claude'
# Pattern: read remote then pipe to instance path
check_pattern "remote-pipe-instance" 'cat.*regist.*>.*config\|cat.*regist.*>.*settings'
# Pattern: remote execution (curl|bash pattern)
check_pattern "remote-exec" 'curl.*\|.*bash\|curl.*\|.*sh\|wget.*\|.*bash'
# Pattern: copy remote to local hooks/plugins
check_pattern "copy-remote-hooks" 'cp.*regist.*hooks\|cp.*regist.*plugins'
# Pattern: sync remote to local
check_pattern "sync-remote" 'rsync.*regist\|scp.*regist'
# Pattern: source remote into shell
check_pattern "source-remote" 'source.*regist\|\. .*regist'
# Pattern: git pull from remote registry
check_pattern "git-pull-registry" 'git.*pull.*regist\|git.*fetch.*regist'
# Pattern: Python remote read then write
check_pattern "py-remote-write" 'regist.*json\.dump\|regist.*\.write\|regist.*open.*w'
# Pattern: TS remote import then apply
check_pattern "ts-remote-import" 'regist.*import.*apply\|regist.*require.*apply'

if [[ $EXIT_CODE -eq 0 ]]; then
  echo '{"assertion":"no-write-path","status":"clean","paths":[]}'
else
  echo "ASSERTION FAILED: write path detected" >&2
  for fp in "${FOUND[@]}"; do
    echo "  $fp" >&2
  done
  printf '{"assertion":"no-write-path","status":"violated","paths":['
  sep=""
  for fp in "${FOUND[@]}"; do
    printf '%s"%s"' "$sep" "$fp"
    sep=", "
  done
  printf ']}\n'
fi

exit $EXIT_CODE
