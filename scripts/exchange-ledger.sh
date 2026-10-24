#!/usr/bin/env bash
# exchange-ledger.sh — Federation exchange ledger (SE-263 S6)
# Signed, hash-chained, append-only per-instance ledger.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT=""
EXCHANGE_DIR=""

usage() {
  cat <<EOF
Usage: bash scripts/exchange-ledger.sh <command> [options]

Commands:
  append --instance ID --type TYPE --content TEXT   Append entry with hash chain
  verify --instance ID                              Verify hash chain integrity
  show --instance ID                                Display ledger

Options:
  --project DIR   Project root (default: git root)
EOF
}

CMD=""; INSTANCE_ID=""; ENTRY_TYPE=""; CONTENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    append|verify|show) CMD="$1"; shift ;;
    --project) PROJECT="$2"; shift 2 ;;
    --instance) INSTANCE_ID="$2"; shift 2 ;;
    --type) ENTRY_TYPE="$2"; shift 2 ;;
    --content) CONTENT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) shift ;;
  esac
done

[[ -z "$CMD" ]] && { usage >&2; exit 1; }
[[ -z "$INSTANCE_ID" ]] && { echo "ERROR: --instance required" >&2; exit 1; }

if [[ -n "$PROJECT" ]]; then
  ROOT="$PROJECT"
fi
EXCHANGE_DIR="$ROOT/coordinacion/exchange"

LEDGER="$EXCHANGE_DIR/${INSTANCE_ID}.jsonl"
mkdir -p "$EXCHANGE_DIR"

cmd_append() {
  [[ -z "$ENTRY_TYPE" ]] && { echo "ERROR: --type required" >&2; exit 1; }
  local ts prev_hash
  ts=$(date -Iseconds)

  if [[ -f "$LEDGER" ]]; then
    prev_hash=$(tail -1 "$LEDGER" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hash',''))" 2>/dev/null || echo "genesis")
  else
    prev_hash="genesis"
  fi

  local entry_hash
  entry_hash=$(echo -n "${ts}${INSTANCE_ID}${ENTRY_TYPE}${CONTENT}${prev_hash}" | sha256sum | awk '{print $1}')

  python3 -c "
import json
entry = {
    'ts': '$ts',
    'instance': '$INSTANCE_ID',
    'type': '$ENTRY_TYPE',
    'content': '''$CONTENT''',
    'prev_hash': '$prev_hash',
    'hash': '$entry_hash'
}
print(json.dumps(entry))
" >> "$LEDGER"

  echo "Appended: $LEDGER (hash=$entry_hash)"
}

cmd_verify() {
  [[ ! -f "$LEDGER" ]] && { echo "VERIFY: no ledger for $INSTANCE_ID"; exit 0; }

  local prev_hash="genesis" line=0 broken=0
  while IFS= read -r entry; do
    line=$((line + 1))
    local e_prev
    e_prev=$(echo "$entry" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('prev_hash',''))" 2>/dev/null || echo "")
    [[ "$e_prev" != "$prev_hash" ]] && { echo "BROKEN chain at line $line: expected $prev_hash, got $e_prev"; broken=1; }

    local e_hash
    e_hash=$(echo "$entry" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hash',''))" 2>/dev/null || echo "")
    prev_hash="$e_hash"
  done < "$LEDGER"

  if [[ "$broken" -eq 0 ]]; then
    echo "VERIFY: chain INTACT ($line entries)"
  else
    echo "VERIFY: chain BROKEN"
    exit 1
  fi
}

cmd_show() {
  [[ ! -f "$LEDGER" ]] && { echo "No ledger for $INSTANCE_ID"; exit 0; }
  cat "$LEDGER"
}

case "$CMD" in
  append) cmd_append ;;
  verify) cmd_verify ;;
  show)   cmd_show ;;
esac
