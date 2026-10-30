#!/usr/bin/env bash
set -uo pipefail
# session-end-snapshot.sh — Save context snapshot at session end
# Hook: Stop event. Runs when Claude session ends.
# PERF: optimized 2026-05-07 — fire-and-forget background, return immediately
# ─────────────────────────────────────────────────────────────────

ERR_LOG="$HOME/.savia/hook-errors.log"
trap 'echo "[$(date +%H:%M:%S)] session-end-snapshot: $BASH_COMMAND failed (line $LINENO)" >> "$ERR_LOG" 2>/dev/null' ERR

# Drain stdin with builtins (no cat/dirname forks: hook latency ratchet, SLA 20 ms).
read -r -d '' _ 2>/dev/null || true

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="${SCRIPT_DIR}/.."
# Derive SCRIPTS_DIR for SE-230 integration
SCRIPTS_DIR="${ROOT}/scripts"

SNAPSHOT_SCRIPT=""
for spath in "$ROOT/scripts/context-snapshot.sh" "./scripts/context-snapshot.sh"; do
  if [ -x "$spath" ]; then
    SNAPSHOT_SCRIPT="$spath"
    break
  fi
done

# Fire-and-forget: snapshot writes to disk async, hook returns immediately.
# Stop hook latency is observable to user; snapshot work is best-effort.
if [ -n "$SNAPSHOT_SCRIPT" ]; then
  ( bash "$SNAPSHOT_SCRIPT" save < /dev/null > /dev/null 2>&1 ) & disown
fi

# SE-230: guardar estado focal al cerrar
if [ -n "${SAVIA_NIDO:-}" ]; then
  ( bash "$SCRIPTS_DIR/focal-switch.sh" --save-only --nido "$SAVIA_NIDO" > /dev/null 2>&1 ) & disown
fi

exit 0
