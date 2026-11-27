#!/usr/bin/env bash
set -uo pipefail
# court-turn-router.sh — SE-231 Adaptive Turn Routing for Code Review Court
#
# Given a findings JSON, classifies the dominant finding type and emits the
# minimal set of judges needed for the next review round.
#
# Usage:
#   bash scripts/court-turn-router.sh --findings <path> [--round <N>] [--max-round <M>]
#
# Output (stdout): one judge name per line
#
# Exit codes:
#   0 — list emitted
#   1 — file not found or JSON invalid
#   2 — usage error
#
# Ref: docs/rules/domain/court-turn-routing.md, SE-231

ALL_JUDGES=(
  security-judge
  correctness-judge
  architecture-judge
  cognitive-judge
  spec-judge
)

die()  { echo "ERROR: $*" >&2; exit 1; }
usage(){ echo "Usage: $0 --findings <path> [--round <N>] [--max-round <M>]" >&2; exit 2; }

FINDINGS_FILE=""
ROUND=1
MAX_ROUND=3

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings)   [[ -z "${2:-}" ]] && usage; FINDINGS_FILE="$2"; shift 2 ;;
    --round)      [[ -z "${2:-}" ]] && usage; ROUND="$2";         shift 2 ;;
    --max-round)  [[ -z "${2:-}" ]] && usage; MAX_ROUND="$2";     shift 2 ;;
    -h|--help)    usage ;;
    *)            echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -z "$FINDINGS_FILE" ]] && usage

# Sin ceros a la izquierda ni más de 6 dígitos: (( )) leería "010" como octal
# (8) y "08" como error, y un número enorme envolvería en 64 bits.
if [[ -n "$ROUND" ]] && ! [[ "$ROUND" =~ ^(0|[1-9][0-9]{0,5})$ ]]; then
  echo "ERROR: --round must be a non-negative integer, got: '$ROUND'" >&2
  exit 2
fi
if [[ -n "$MAX_ROUND" ]] && ! [[ "$MAX_ROUND" =~ ^(0|[1-9][0-9]{0,5})$ ]]; then
  echo "ERROR: --max-round must be a positive integer, got: '$MAX_ROUND'" >&2
  exit 2
fi

[[ -f "$FINDINGS_FILE" ]] || die "Findings file not found: $FINDINGS_FILE"

CONTENT=$(cat "$FINDINGS_FILE" 2>/dev/null) || die "Cannot read file: $FINDINGS_FILE"
[[ -z "$CONTENT" ]] && die "Findings file is empty: $FINDINGS_FILE"

LOWER=$(echo "$CONTENT" | tr '[:upper:]' '[:lower:]')

# Last-round override — always send all judges
if (( ROUND >= MAX_ROUND - 1 )); then
  printf '%s\n' "${ALL_JUDGES[@]}"
  exit 0
fi

is_security=0
is_architecture=0
is_logic=0
is_spec=0
is_naming=0

if echo "$LOWER" | grep -qiE 'injection|credential|owasp|pii|\bauth\b|xss|sql'; then
  is_security=1
fi

if echo "$LOWER" | grep -qiE 'coupling|layer|boundary|dependency|solid'; then
  is_architecture=1
fi

if echo "$LOWER" | grep -qiE 'edge.?case|null|exception|error.?path|off.?by.?one'; then
  is_logic=1
fi

if echo "$LOWER" | grep -qiE 'spec|acceptance.?criteria|requirement|dod'; then
  is_spec=1
fi

if echo "$LOWER" | grep -qiE 'naming|complexity|cognitive|debuggab'; then
  is_naming=1
fi

ACTIVE=$(( is_security + is_architecture + is_logic + is_spec + is_naming ))

if (( ACTIVE > 1 )); then
  printf '%s\n' "${ALL_JUDGES[@]}"
  exit 0
fi

if (( is_security )); then
  echo "security-judge"
  echo "correctness-judge"
elif (( is_architecture )); then
  echo "architecture-judge"
  echo "spec-judge"
elif (( is_logic )); then
  echo "correctness-judge"
  echo "cognitive-judge"
elif (( is_spec )); then
  echo "spec-judge"
  echo "correctness-judge"
elif (( is_naming )); then
  echo "cognitive-judge"
else
  # No keyword matched — conservative fallback: all judges
  printf '%s\n' "${ALL_JUDGES[@]}"
fi

exit 0
