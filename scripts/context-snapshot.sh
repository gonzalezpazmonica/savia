#!/usr/bin/env bash
# context-snapshot.sh — Save/load session context between sessions
# Saves: active project, branch, sprint, last commands, decisions.
# Usage: ./scripts/context-snapshot.sh save|load|status
# ─────────────────────────────────────────────────────────────────
set -uo pipefail
cat /dev/stdin > /dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
# CONTEXT_CACHE_DIR: solo para tests (aislar la escritura del snapshot en un tmp).
CACHE_DIR="${CONTEXT_CACHE_DIR:-${ROOT}/.claude/context-cache}"
SNAPSHOT="${CACHE_DIR}/last-session.json"
TTL_HOURS=24

mkdir -p "$CACHE_DIR" 2>/dev/null || true

# ── Check snapshot age ──
is_fresh() {
  [ -f "$SNAPSHOT" ] || return 1
  local now file_time age_hours
  now=$(date +%s)
  file_time=$(date -r "$SNAPSHOT" +%s 2>/dev/null || stat -c %Y "$SNAPSHOT" 2>/dev/null || echo 0)
  age_hours=$(( (now - file_time) / 3600 ))
  [ "$age_hours" -lt "$TTL_HOURS" ]
}

# ── Save snapshot ──
do_save() {
  local branch project sprint
  branch=$(git -C "$ROOT" branch --show-current 2>/dev/null || echo "unknown")
  project=$(basename "$(grep -l 'CLAUDE.md' "$ROOT"/projects/*/CLAUDE.md 2>/dev/null | head -1 | xargs dirname 2>/dev/null)" 2>/dev/null || echo "none")
  sprint=$(date +%Y-S%V)

  # Last 5 git commits as proxy for "last commands"
  local last_commits
  last_commits=$(git -C "$ROOT" log --oneline -5 2>/dev/null | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')

  cat > "$SNAPSHOT" <<EOJSON
{
  "timestamp": "$(date -Iseconds)",
  "branch": "${branch}",
  "project": "${project}",
  "sprint": "${sprint}",
  "last_activity": "${last_commits}",
  "model_tier": "${SAVIA_MODEL_TIER:-unknown}",
  "context_window": ${SAVIA_CONTEXT_WINDOW:-128000}
}
EOJSON
  echo "Snapshot saved: $SNAPSHOT"
}

# ── Load snapshot ──
do_load() {
  if ! is_fresh; then
    echo '{"status":"stale","message":"No fresh snapshot (>24h or missing)"}'
    return 0
  fi
  cat "$SNAPSHOT"
}

# ── Status ──
do_status() {
  if [ ! -f "$SNAPSHOT" ]; then
    echo "No snapshot found"
    return 0
  fi
  local age_hours now file_time
  now=$(date +%s)
  file_time=$(date -r "$SNAPSHOT" +%s 2>/dev/null || stat -c %Y "$SNAPSHOT" 2>/dev/null || echo 0)
  age_hours=$(( (now - file_time) / 3600 ))
  echo "Snapshot: ${SNAPSHOT}"
  echo "Age: ${age_hours}h (TTL: ${TTL_HOURS}h)"
  echo "Fresh: $(is_fresh && echo yes || echo no)"
}

case "${1:-status}" in
  save) do_save ;;
  load) do_load ;;
  status) do_status ;;
  *) echo "Usage: $0 save|load|status" >&2; exit 1 ;;
esac
