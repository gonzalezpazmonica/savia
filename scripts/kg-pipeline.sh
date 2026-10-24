#!/usr/bin/env bash
set -uo pipefail
# kg-pipeline.sh — Extract KG from digest output and persist to SaviaVaults

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTOR="$SCRIPT_DIR/kg-extract.py"
INPUT="${1:--}"
SOURCE="${2:-unknown}"

if [[ ! -f "$EXTRACTOR" ]]; then
  echo '{"error":"kg-extract.py not found"}' >&2
  exit 2
fi

TEXT=$(cat "$INPUT" 2>/dev/null || echo "")

if [[ -z "${TEXT//[[:space:]]/}" ]]; then
  echo '{"extracted":false,"reason":"empty input"}' 
  exit 0
fi

printf '%s\n' "$TEXT" | python3 "$EXTRACTOR" --mode deterministic --source "$SOURCE" --quality-gate 2>/dev/null || \
  echo '{"extracted":false,"error":"extraction failed"}'
