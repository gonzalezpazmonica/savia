#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
# skill-suggest.sh — Proactive skill suggestion hook (SE-276)
#
# Lightweight frontend to the intent dispatch table (docs/RESOLVER.md).
# Runs in <500ms on UserPromptSubmit. Emits inline suggestion
# if a skill matches the user's intent and is not already loaded.
#
# Reference: docs/RESOLVER.md (the dispatch agent of SPEC-166 was retired in SE-527 S1)
# Reference: SE-276 spec

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_FILE="${STATE_FILE:-${ROOT}/output/skill-suggest-state.json}"
MODE="suggest"

usage() {
  cat <<USG
Usage: skill-suggest.sh --prompt "<user prompt>" [--loaded-skills "<skill1,skill2>"] [--test]

Options:
  --prompt TEXT        User prompt to analyze (first 500 chars)
  --loaded-skills LIST Comma-separated list of currently loaded skill ids
  --test               Dry-run mode: print to stdout instead of state file

State file: $STATE_FILE
USG
}

PROMPT=""
LOADED_SKILLS=""
TEST_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="$2"; shift 2 ;;
    --loaded-skills) LOADED_SKILLS="$2"; shift 2 ;;
    --test) TEST_MODE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -z "$PROMPT" ]] && { echo "ERROR: --prompt required" >&2; exit 1; }

# --- State management ---
read_state() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo '{"consecutive_ignored":0,"silence_until_turn":0,"turn_counter":0}'
  fi
}

write_state() {
  local state="$1"
  if $TEST_MODE; then
    echo "[state] $state" >&2
  else
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$state" > "$STATE_FILE"
  fi
}

# --- Dispatch table (subset of docs/RESOLVER.md intents) ---
# Format: "pattern1|pattern2|..." → "skill_id"
# Only suggest skills (not agents). Skills that always require explicit
# invocation (overnight-sprint, code-improvement-loop) are excluded.
declare -A DISPATCH_TABLE=(
  ["informe semanal|weekly report|estado semanal|informe de estado|reporte semanal"]="weekly-report"
  ["sprint|velocity|backlog|burndown|sprint management|capacidad|capacity"]="sprint-management"
  ["spec|feature|pbi|implementar spec|nueva feature|sdd"]="spec-driven-development"
  ["test|coverage|bats|unit test|test unitario|integration test"]="test-architect"
  ["security|owasp|cve|vulnerabilidad|pentest|auditoria seguridad"]="adversarial-security"
  ["deploy|infra|terraform|docker|bicep|infraestructura|cloud"]="diagram-generation"
  ["drift|sync|audit|convergencia|auditoria repo"]="workspace-integrity"
  ["memory|recall|save|recordar|memoria|consolidar"]="savia-memory"
  ["diagram|diagrama|mermaid|arquitectura diagrama"]="diagram-generation"
  ["onboard|nuevo dev|nuevo miembro|incorporacion dev"]="onboarding-dev"
  ["cupula|cúpula|context dome|dome|vaults|vault|savia vaults|savia-vaults|federate dome|federar cupula|confidencialidad vault|backup cupula|backup dome|backup vaults"]="savia-vaults"
  ["weekly report|daily|scrum|ceremonia"]="weekly-report"
  ["legal|compliance|rgpd|gdpr|lopd|normativa"]="legal-compliance"
  ["meeting|reunion|transcripcion|acta|minuta"]="meeting-transcript-extract"
  ["excel|xlsx|csv|spreadsheet|hoja calculo"]="excel-digest"
  ["pdf|documento pdf"]="pdf-digest"
  ["docx|word|documento word"]="word-digest"
  ["pptx|powerpoint|presentacion"]="pptx-digest"
  ["bus factor|bus-factor|conocimiento tactico"]="bus-factor-analysis"
  ["coste|budget|presupuesto|timesheet|factura"]="cost-management"
  ["ios|android|swift|kotlin|flutter|mobile"]="mobile-security-scanner"
)

# --- Core matching logic ---
find_match() {
  local prompt_lower
  prompt_lower=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | cut -c1-500)

  local best_skill="" best_score=0 best_pattern=""

  for pattern_list in "${!DISPATCH_TABLE[@]}"; do
    local skill="${DISPATCH_TABLE[$pattern_list]}"

    # Skip already loaded skills
    if [[ -n "$LOADED_SKILLS" ]] && echo "$LOADED_SKILLS" | tr ',' '\n' | grep -qxF "$skill"; then
      continue
    fi

    # Count keyword matches in prompt
    local matches=0 total=0
    IFS='|' read -ra KEYWORDS <<< "$pattern_list"
    for kw in "${KEYWORDS[@]}"; do
      total=$((total + 1))
      if echo "$prompt_lower" | grep -qF "$kw"; then
        matches=$((matches + 1))
      fi
    done

    [[ $total -eq 0 ]] && continue
    local score=$((matches * 100 / total))

    # Require at least one keyword match
    if [[ $matches -gt 0 ]] && [[ $score -gt "$best_score" ]]; then
      best_score=$score
      best_skill="$skill"
      best_pattern="$pattern_list"
    fi
  done

  # Threshold: need at least 1 keyword match (any match qualifies)
  if [[ $best_score -lt 1 ]]; then
    echo ""
    return
  fi

  echo "$best_skill"
}

# --- Silence mode management ---
check_silence() {
  local state
  state=$(read_state)
  local silence_until turn_counter consecutive
  silence_until=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('silence_until_turn',0))" 2>/dev/null || echo 0)
  turn_counter=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('turn_counter',0))" 2>/dev/null || echo 0)

  if [[ "$turn_counter" -lt "$silence_until" ]]; then
    return 1  # silenced
  fi
  return 0  # not silenced
}

record_suggestion() {
  local state new_turn
  state=$(read_state)
  new_turn=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('turn_counter',0)+1)" 2>/dev/null || echo 1)

  # Always increment turn counter
  state=$(echo "$state" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['turn_counter'] = $new_turn
print(json.dumps(d))
" 2>/dev/null)
  write_state "$state"
}

record_ignored() {
  local state consecutive new_silence
  state=$(read_state)
  consecutive=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('consecutive_ignored',0)+1)" 2>/dev/null || echo 1)

  state=$(echo "$state" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['consecutive_ignored'] = $consecutive
if d['consecutive_ignored'] >= 3:
    d['silence_until_turn'] = d.get('turn_counter', 0) + 10
    d['consecutive_ignored'] = 0
print(json.dumps(d))
" 2>/dev/null)
  write_state "$state"
}

reset_ignored() {
  local state
  state=$(read_state)
  state=$(echo "$state" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['consecutive_ignored'] = 0
# If past silence period, clear it
if d.get('turn_counter',0) >= d.get('silence_until_turn',0):
    d['silence_until_turn'] = 0
print(json.dumps(d))
" 2>/dev/null)
  write_state "$state"
}

# --- Main ---
if ! check_silence; then
  # We're in silence mode — don't suggest, but still increment turn
  record_suggestion
  exit 0
fi

record_suggestion
SUGGESTION=$(find_match)

if $TEST_MODE; then
  if [[ -n "$SUGGESTION" ]]; then
    echo "$SUGGESTION"
  fi
  exit 0
fi

# Output to stderr so it doesn't pollute hook stdout
if [[ -n "$SUGGESTION" ]]; then
  echo "skill-suggest: $SUGGESTION" >&2
fi
