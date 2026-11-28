#!/bin/bash
# context-erosion-detect.sh — SE-270 S7: detect context collapse via volume erosion
# Compares context file versions over time.
# Detects volume loss without explicit item removal (context collapse symptom).
# Output path for reports: output/context-erosion-reports/
#
# Usage:
#   context-erosion-detect.sh --file output/session-action-log.jsonl
#   context-erosion-detect.sh --file .opencode/agents/architect/CLAUDE.md
#   context-erosion-detect.sh --snapshot-dir output/context-snapshots/
#   context-erosion-detect.sh --report
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
REPORT_DIR="${WORKSPACE}/output/context-erosion-reports"

EROSION_THRESHOLD_PCT="${CONTEXT_EROSION_THRESHOLD:-20}"
EROSION_MAX_WINDOW="${CONTEXT_EROSION_WINDOW:-7}"
TARGET_FILE=""
SNAPSHOT_DIR=""
REPORT_ONLY=false

log() { echo "[context-erosion] $*" >&2; }

usage() {
  cat <<USAGE
context-erosion-detect.sh — SE-270 S7: detect volume erosion in context files

Usage:
  context-erosion-detect.sh --file PATH           # monitor single file
  context-erosion-detect.sh --snapshot-dir PATH    # compare snapshots
  context-erosion-detect.sh --report               # show last report

Exit: 0 = no erosion, 1 = erosion detected
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) TARGET_FILE="${2:-}"; shift 2 ;;
    --snapshot-dir) SNAPSHOT_DIR="${2:-}"; shift 2 ;;
    --report) REPORT_ONLY=true; shift ;;
    --threshold) EROSION_THRESHOLD_PCT="${2:-$EROSION_THRESHOLD_PCT}"; shift 2 ;;
    --window) EROSION_MAX_WINDOW="${2:-$EROSION_MAX_WINDOW}"; shift 2 ;;
    --help|-h) usage ;;
    *) shift ;;
  esac
done

mkdir -p "$REPORT_DIR"
now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
report_date=$(date +"%Y%m%d" 2>/dev/null || echo "unknown")
report_file="$REPORT_DIR/erosion-${report_date}.json"
snapshot_file="$REPORT_DIR/snapshot-${report_date}.json"

# ── Report-only mode ───────────────────────────────────────────────────────────

if $REPORT_ONLY; then
  latest=$(ls -t "$REPORT_DIR"/erosion-*.json 2>/dev/null | head -1)
  if [[ -n "$latest" ]]; then
    cat "$latest"
  else
    echo "No erosion reports found in $REPORT_DIR" >&2
    exit 0
  fi
  exit 0
fi

# ── Snapshot capture ───────────────────────────────────────────────────────────

capture_snapshot() {
  local file="$1"
  local out="$2"
  if [[ ! -f "$file" ]]; then
    echo "{\"error\":\"file not found: $file\",\"ts\":\"$now_iso\"}" > "$out"
    return 0
  fi
  local lines
  lines=$(wc -l < "$file" 2>/dev/null || echo 0)
  local bytes
  bytes=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
  local md5
  md5=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1 || md5sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

  python3 -c "
import json
print(json.dumps({
    'ts': '$now_iso',
    'file': '$file',
    'lines': $lines,
    'bytes': $bytes,
    'md5': '$md5',
}))
" > "$out"
}

# ── Erosion detection ─────────────────────────────────────────────────────────

detect_erosion() {
  local file="$1"
  local threshold_pct="$2"
  local window_days="$3"

  if [[ ! -f "$file" ]]; then
    echo "{\"error\":\"no snapshots for $file\"}"
    return 1
  fi

  python3 - "$file" "$threshold_pct" "$window_days" "$now_iso" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

snapshot_dir = Path(sys.argv[1])
threshold = float(sys.argv[2])
window_days = int(sys.argv[3])
now_iso = sys.argv[4]

snapshots = []
for f in sorted(snapshot_dir.glob("snapshot-*.json")):
    try:
        with f.open() as fh:
            snapshots.append(json.load(fh))
    except (Exception,):
        continue

if len(snapshots) < 2:
    print(json.dumps({"error": "need at least 2 snapshots", "found": len(snapshots)}))
    sys.exit(1)

results = []
for i in range(1, len(snapshots)):
    prev = snapshots[i - 1]
    curr = snapshots[i]

    prev_bytes = prev.get("bytes", 0)
    curr_bytes = curr.get("bytes", 0)
    prev_lines = prev.get("lines", 0)
    curr_lines = curr.get("lines", 0)

    if prev_bytes == 0 or prev_lines == 0:
        continue

    byte_delta = prev_bytes - curr_bytes
    byte_pct = (byte_delta / prev_bytes) * 100 if prev_bytes else 0
    line_delta = prev_lines - curr_lines
    line_pct = (line_delta / prev_lines) * 100 if prev_lines else 0

    # Detect "silent" erosion: volume loss without explicit removal markers
    # (e.g., file shrunk but no corresponding delete/archival commit message)
    is_silent = prev.get("md5") != curr.get("md5")

    if byte_pct >= threshold or line_pct >= threshold:
        results.append({
            "from_ts": prev.get("ts"),
            "to_ts": curr.get("ts"),
            "file": curr.get("file"),
            "bytes_before": prev_bytes,
            "bytes_after": curr_bytes,
            "byte_delta": byte_delta,
            "byte_pct": round(byte_pct, 1),
            "lines_before": prev_lines,
            "lines_after": curr_lines,
            "line_delta": line_delta,
            "line_pct": round(line_pct, 1),
            "md5_changed": is_silent,
            "erosion_type": "collapse" if is_silent and line_pct >= threshold * 2 else "erosion",
        })

output = {
    "ts": now_iso,
    "threshold_pct": threshold,
    "snapshots_compared": len(snapshots),
    "erosions_detected": len(results),
    "erosions": results,
}

print(json.dumps(output, indent=2, ensure_ascii=False))
PY
}

# ── Single file monitoring ─────────────────────────────────────────────────────

if [[ -n "$TARGET_FILE" ]]; then
  mkdir -p "$REPORT_DIR"
  capture_snapshot "$TARGET_FILE" "$snapshot_file"
  detect_erosion "$REPORT_DIR" "$EROSION_THRESHOLD_PCT" "$EROSION_MAX_WINDOW" > "$report_file"

  erosion_count=$(python3 -c "import sys; import json; d=json.load(open(sys.argv[1])); print(d.get('erosions_detected',0))" "$report_file" 2>/dev/null || echo 0)

  if [[ "$erosion_count" -gt 0 ]]; then
    echo "EROSION DETECTED: $erosion_count volume losses exceeding ${EROSION_THRESHOLD_PCT}%"
    cat "$report_file"
    exit 1
  else
    echo "No erosion detected for $TARGET_FILE"
    cat "$report_file"
    exit 0
  fi
fi

# ── Snapshot directory comparison ──────────────────────────────────────────────

if [[ -n "$SNAPSHOT_DIR" ]]; then
  detect_erosion "$SNAPSHOT_DIR" "$EROSION_THRESHOLD_PCT" "$EROSION_MAX_WINDOW" > "$report_file"

  erosion_count=$(python3 -c "import sys; import json; d=json.load(open(sys.argv[1])); print(d.get('erosions_detected',0))" "$report_file" 2>/dev/null || echo 0)

  if [[ "$erosion_count" -gt 0 ]]; then
    echo "EROSION DETECTED: $erosion_count instances"
    cat "$report_file"
    exit 1
  else
    echo "No erosion detected in $SNAPSHOT_DIR ($(ls "$SNAPSHOT_DIR"/snapshot-*.json 2>/dev/null | wc -l) snapshots)"
    cat "$report_file"
    exit 0
  fi
fi

# ── Default: scan recent context files ─────────────────────────────────────────

log "No --file or --snapshot-dir specified. Scanning key context files..."

files_to_check=(
  "$WORKSPACE/.opencode/agents"
  "$WORKSPACE/.opencode/skills"
  "$WORKSPACE/docs"
)

all_erosions=0
for dir in "${files_to_check[@]}"; do
  if [[ -d "$dir" ]]; then
    log "checking: $dir"
    # Count significant files per dir as proxy for context volume
    md_count=$(find "$dir" -name "*.md" -type f 2>/dev/null | wc -l)
    echo "  $dir: $md_count .md files"
  fi
done

echo "{\"ts\":\"$now_iso\",\"checked_dirs\":${#files_to_check[@]},\"erosions\":$all_erosions}" > "$report_file"
echo "Snapshots saved to: $REPORT_DIR"

exit 0
