#!/usr/bin/env bash
set -uo pipefail
# court-review.sh — Code Review Court orchestration helper
#
# Validates batch size, computes per-file SHA-256, builds the .review.crc
# skeleton. The actual judge invocation is done by the court-orchestrator
# agent; this script handles the deterministic parts.
#
# Usage:
#   bash scripts/court-review.sh check          # batch-size gate only
#   bash scripts/court-review.sh skeleton       # generate .review.crc skeleton
#   bash scripts/court-review.sh score C H M L  # compute score from counts
#   bash scripts/court-review.sh hash FILE      # SHA-256 of a file
#   bash scripts/court-review.sh validate FILE  # SE-404: ≤ COURT_MAX_FIX_ROUNDS (1) fix rounds

COURT_MAX_LOC="${COURT_MAX_LOC:-400}"
COURT_SCORE_PASS="${COURT_SCORE_PASS:-90}"
COURT_SCORE_CONDITIONAL="${COURT_SCORE_CONDITIONAL:-70}"

die() { echo "ERROR: $*" >&2; exit 1; }

# Enteros no negativos validados ANTES de cualquier contexto aritmético:
# $(( )) y [[ -gt ]] evalúan subíndices, así que "HOME[$(cmd)]" ejecutaría cmd.
# Bash además envuelve en 64 bits sin aviso, así que la regex acota a 6 dígitos
# sin ceros a la izquierda (evita la base octal de "08"); solo entonces se
# compara con el máximo. Mismo criterio que coherence-court.sh. Sale con 2.
COURT_COUNT_MAX=999999
_require_uint() {
  local name="$1" value="$2" max="${3:-$COURT_COUNT_MAX}"
  if ! [[ "$value" =~ ^(0|[1-9][0-9]{0,5})$ ]]; then
    echo "ERROR: $name must be an integer 0-$max without leading zeros: '$value'" >&2
    exit 2
  fi
  if [[ "$value" -gt "$max" ]]; then
    echo "ERROR: $name out of range 0-$max: '$value'" >&2
    exit 2
  fi
}

cmd_check() {
  _require_uint COURT_MAX_LOC "$COURT_MAX_LOC"
  local loc
  loc=$(git diff origin/main..HEAD --stat 2>/dev/null | tail -1 | grep -oP '[0-9]+ insertion' | grep -oP '[0-9]+') || loc=0
  local del
  del=$(git diff origin/main..HEAD --stat 2>/dev/null | tail -1 | grep -oP '[0-9]+ deletion' | grep -oP '[0-9]+') || del=0
  local total=$((loc + del))

  if [[ "$total" -gt "$COURT_MAX_LOC" ]]; then
    echo "FAIL: diff is $total LOC (max $COURT_MAX_LOC)"
    echo "Split the PR into smaller slices. Human review quality degrades"
    echo "sharply above $COURT_MAX_LOC LOC (SmartBear/Cisco)."
    echo ""
    echo "Changed files:"
    git diff origin/main..HEAD --stat 2>/dev/null | head -20
    exit 1
  fi
  echo "PASS: $total LOC (max $COURT_MAX_LOC)"
}

cmd_skeleton() {
  local branch
  branch=$(git branch --show-current 2>/dev/null) || branch="unknown"
  local review_id
  review_id="CRC-$(date +%Y-%m%d)-001"
  local files_json=""

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local sha
    sha=$(sha256sum "$file" 2>/dev/null | awk '{print $1}') || sha="unknown"
    files_json="${files_json}  - path: \"$file\"\n    sha256: \"$sha\"\n    findings: []\n    status: \"pending\"\n"
  done < <(git diff origin/main..HEAD --name-only 2>/dev/null)

  cat <<EOF
---
review_id: "$review_id"
pr_ref: ""
branch: "$branch"
spec_ref: null
reviewed_at: "$(date -Iseconds)"
review_round: 1
batch_size:
  total_loc: $(git diff origin/main..HEAD --stat 2>/dev/null | tail -1 | grep -oP '[0-9]+ insertion' | grep -oP '[0-9]+' || echo 0)
  max_loc: $COURT_MAX_LOC
  status: "pass"
judges:
  correctness: { verdict: "pending", findings_count: 0 }
  architecture: { verdict: "pending", findings_count: 0 }
  security: { verdict: "pending", findings_count: 0 }
  cognitive: { verdict: "pending", findings_count: 0 }
  spec: { verdict: "pending", findings_count: 0 }
consolidated:
  verdict: "pending"
  total_findings: 0
  blocking: 0
  advisory: 0
  score: 0
files:
$(echo -e "$files_json")
rounds: []
signature:
  hash: ""
  reviewed_by: "code-review-court-v1"
---
EOF
}

cmd_score() {
  local c="${1-0}" h="${2-0}" m="${3-0}" l="${4-0}"
  _require_uint C "$c"; _require_uint H "$h"; _require_uint M "$m"; _require_uint L "$l"
  _require_uint COURT_SCORE_PASS "$COURT_SCORE_PASS" 100
  _require_uint COURT_SCORE_CONDITIONAL "$COURT_SCORE_CONDITIONAL" 100
  local score=$((100 - c * 25 - h * 10 - m * 3 - l * 1))
  [[ "$score" -lt 0 ]] && score=0

  local verdict
  if [[ "$score" -ge "$COURT_SCORE_PASS" ]]; then
    verdict="pass"
  elif [[ "$score" -ge "$COURT_SCORE_CONDITIONAL" ]]; then
    verdict="conditional"
  else
    verdict="fail"
  fi

  echo "score=$score verdict=$verdict (C=$c H=$h M=$m L=$l)"
}

cmd_validate() {
  # SE-404 AC8: one bounded fix round per review. A second round means the
  # candidate changed again: close this review and open a new .review.crc
  # with previous_review: <sha256 of this one>.
  local file="${1:-}"
  [[ -z "$file" ]] && { echo "Usage: court-review.sh validate FILE" >&2; exit 2; }
  [[ -f "$file" ]] || { echo "ERROR: not found: $file" >&2; exit 2; }
  local max="${COURT_MAX_FIX_ROUNDS:-1}"
  _require_uint COURT_MAX_FIX_ROUNDS "$max"
  local n
  n=$(awk '/^rounds:/{inr=1; next} inr && /^[^ ]/{inr=0} inr && /^  - /{c++} END{print c+0}' "$file")
  if [[ "$n" -gt "$max" ]]; then
    echo "FAIL: $n fix rounds in $(basename "$file") (max $max). Close this review and open a new review with previous_review: $(sha256sum "$file" | cut -c1-16)…"
    exit 1
  fi
  echo "PASS: $n fix round(s) (max $max)"
}

cmd_hash() {
  local file="${1:-}"
  [[ -z "$file" ]] && die "Usage: court-review.sh hash FILE"
  [[ -f "$file" ]] || die "File not found: $file"
  sha256sum "$file" | awk '{print $1}'
}

case "${1:-}" in
  check)    cmd_check ;;
  skeleton) cmd_skeleton ;;
  score)    shift; cmd_score "$@" ;;
  hash)     shift; cmd_hash "$@" ;;
  validate) shift; cmd_validate "$@" ;;
  *)        echo "Usage: court-review.sh {check|skeleton|score|hash}" ;;
esac
