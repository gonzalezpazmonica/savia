#!/bin/bash
# agent-hook-runner.sh — SE-202: semantic LLM gate for hooks
# Inspired by OpenHands agent-based hook pattern
# Ref: docs/propuestas/SE-202-agent-hooks.md
set -uo pipefail

TIMEOUT=${SAVIA_AGENT_HOOK_TIMEOUT:-30}
FAIL_OPEN=${SAVIA_AGENT_HOOK_FAIL_OPEN:-true}
LOG_FILE="${PROJECT_ROOT:-$(pwd)}/output/agent-hook-decisions.jsonl"

# ── Argument parsing ────────────────────────────────────────────────────────

AGENT_NAME=""
EVENT_JSON=""
DRY_RUN=false
LIST_AGENTS=false

usage() {
  echo "Usage: agent-hook-runner.sh --agent <name> --event <JSON>" >&2
  echo "" >&2
  echo "  --agent <name>    Agent name from .opencode/agents/" >&2
  echo "  --event <JSON>    Event JSON string (tool name + input)" >&2
  echo "  --dry-run         Show what would be sent to agent, no execution" >&2
  echo "  --list-agents     List available agents for hooks" >&2
  echo "" >&2
  echo "Env vars:" >&2
  echo "  SAVIA_AGENT_HOOK_TIMEOUT    Seconds before timeout (default: 30)" >&2
  echo "  SAVIA_AGENT_HOOK_FAIL_OPEN  true=allow on failure (default: true)" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT_NAME="${2:-}"
      shift 2
      ;;
    --event)
      EVENT_JSON="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --list-agents)
      LIST_AGENTS=true
      shift
      ;;
    -*)
      echo "ERROR: Unknown flag: $1" >&2
      usage
      ;;
    *)
      shift
      ;;
  esac
done

REPO_ROOT="${PROJECT_ROOT:-$(pwd)}"
AGENTS_DIR="$REPO_ROOT/.opencode/agents"

# ── List agents mode ────────────────────────────────────────────────────────

if [[ "$LIST_AGENTS" == true ]]; then
  echo "Available agents for hooks (from $AGENTS_DIR):"
  if [[ -d "$AGENTS_DIR" ]]; then
    for f in "$AGENTS_DIR"/*.md; do
      [[ -f "$f" ]] || continue
      name="$(basename "$f" .md)"
      desc="$(grep -m1 '^description:' "$f" 2>/dev/null | sed 's/^description: *//' | head -c 80 || echo "(no description)")"
      echo "  $name — $desc"
    done
  else
    echo "  (agents directory not found: $AGENTS_DIR)"
  fi
  exit 0
fi

# ── Dry-run mode ─────────────────────────────────────────────────────────────

if [[ "$DRY_RUN" == true ]]; then
  if [[ -z "$AGENT_NAME" ]]; then
    echo "ERROR: --agent required for --dry-run" >&2
    exit 1
  fi
  echo "=== DRY-RUN: agent-hook-runner (SE-202) ==="
  echo "Agent  : $AGENT_NAME"
  echo "Event  : ${EVENT_JSON:-(not provided)}"
  echo "Timeout: ${TIMEOUT}s"
  echo "FailOpen: $FAIL_OPEN"
  echo ""
  echo "Would send to agent:"
  echo "  You are a hook gate agent. Evaluate the following tool event and"
  echo "  return JSON: {\"decision\": \"allow\"|\"deny\", \"reason\": \"...\"}"
  echo "  Event: $EVENT_JSON"
  echo ""
  echo "(No agent invoked — dry-run mode)"
  exit 0
fi

# ── Validation ──────────────────────────────────────────────────────────────

if [[ -z "$AGENT_NAME" ]]; then
  echo "ERROR: --agent <name> required" >&2
  usage
fi

if [[ -z "$EVENT_JSON" ]]; then
  echo "ERROR: --event <JSON> required" >&2
  usage
fi

# Validate JSON is parseable
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c "import json, sys; json.loads(sys.argv[1])" "$EVENT_JSON" 2>/dev/null; then
    echo "ERROR: --event value is not valid JSON: $EVENT_JSON" >&2
    exit 1
  fi
fi

# ── Extract event fields ─────────────────────────────────────────────────────

TOOL_NAME=""
TOOL_INPUT=""

if command -v python3 >/dev/null 2>&1; then
  TOOL_NAME=$(python3 -c "
import json, sys
try:
    e = json.loads(sys.argv[1])
    print(e.get('tool', e.get('tool_name', '')) )
except:
    print('')
" "$EVENT_JSON" 2>/dev/null)
  TOOL_INPUT=$(python3 -c "
import json, sys
try:
    e = json.loads(sys.argv[1])
    inp = e.get('input', e.get('tool_input', e.get('command', '')))
    print(inp if isinstance(inp, str) else json.dumps(inp))
except:
    print('')
" "$EVENT_JSON" 2>/dev/null)
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_MS=$(date +%s%3N 2>/dev/null || echo "0")

# ── Agent invocation ─────────────────────────────────────────────────────────

AGENT_FILE="$AGENTS_DIR/${AGENT_NAME}.md"
AGENT_AVAILABLE=false
[[ -f "$AGENT_FILE" ]] && AGENT_AVAILABLE=true

DECISION="allow"
REASON="agent_not_invoked"

_emit_decision() {
  local decision="$1"
  local reason="$2"
  local end_ms
  end_ms=$(date +%s%3N 2>/dev/null || echo "0")
  local duration_ms=$(( end_ms - START_MS ))

  echo "{\"decision\":\"$decision\",\"reason\":\"$reason\",\"agent\":\"$AGENT_NAME\",\"timestamp\":\"$TIMESTAMP\"}"

  # Log to output file
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"agent\":\"$AGENT_NAME\",\"tool\":\"$TOOL_NAME\",\"decision\":\"$decision\",\"reason\":\"$reason\",\"duration_ms\":$duration_ms}" >> "$LOG_FILE"
}

# Try to invoke agent via opencode or claude
INVOKE_CMD=""
if command -v opencode >/dev/null 2>&1; then
  INVOKE_CMD="opencode"
elif command -v claude >/dev/null 2>&1; then
  INVOKE_CMD="claude"
fi

if [[ "$AGENT_AVAILABLE" == false ]]; then
  # Agent file not found — apply failopen policy
  if [[ "$FAIL_OPEN" == "true" ]]; then
    echo "WARN: agent '$AGENT_NAME' not found, FAIL_OPEN=true → allow" >&2
    _emit_decision "allow" "agent_not_found_fail_open"
    exit 0
  else
    echo "ERROR: agent '$AGENT_NAME' not found, FAIL_OPEN=false → deny" >&2
    _emit_decision "deny" "agent_not_found_fail_closed"
    exit 2
  fi
fi

if [[ -z "$INVOKE_CMD" ]]; then
  # No LLM CLI available — apply failopen policy
  if [[ "$FAIL_OPEN" == "true" ]]; then
    echo "WARN: no LLM CLI available (opencode/claude), FAIL_OPEN=true → allow" >&2
    _emit_decision "allow" "no_llm_cli_fail_open"
    exit 0
  else
    echo "ERROR: no LLM CLI available, FAIL_OPEN=false → deny" >&2
    _emit_decision "deny" "no_llm_cli_fail_closed"
    exit 2
  fi
fi

# Build prompt for agent
AGENT_PROMPT="You are a security hook gate agent (SE-202).
Evaluate the following tool event and respond ONLY with JSON.

Response format: {\"decision\": \"allow\" or \"deny\", \"reason\": \"brief explanation\"}

Event JSON:
$EVENT_JSON

Tool: $TOOL_NAME
Input: $TOOL_INPUT

Rules:
- deny if the tool call looks destructive, leaks credentials, or violates security policy
- allow if the tool call is safe and within normal operation
- Keep reason under 120 characters"

# Invoke with timeout
RAW_RESPONSE=""
INVOKE_EXIT=0

if [[ "$INVOKE_CMD" == "opencode" ]]; then
  # `run` is non-interactive by default in OpenCode 1 (`--interactive` is opt-in) and in 2; neither knows
  # `--no-interactive`. In 2, `run` talks to the per-user background service unless `--standalone` is given,
  # which would share session, database and credentials with every other project: use a private server.
  OC_RUN_ARGS=(run)
  if opencode run --help 2>&1 | grep -q -- '--standalone'; then OC_RUN_ARGS+=(--standalone); fi
  RAW_RESPONSE=$(timeout "$TIMEOUT" opencode "${OC_RUN_ARGS[@]}" "$AGENT_PROMPT" 2>/dev/null) || INVOKE_EXIT=$?
elif [[ "$INVOKE_CMD" == "claude" ]]; then
  RAW_RESPONSE=$(timeout "$TIMEOUT" claude -p "$AGENT_PROMPT" 2>/dev/null) || INVOKE_EXIT=$?
fi

# Timeout or error
if [[ $INVOKE_EXIT -eq 124 ]] || [[ $INVOKE_EXIT -ne 0 && -z "$RAW_RESPONSE" ]]; then
  echo "WARN: agent '$AGENT_NAME' timed out or failed (exit $INVOKE_EXIT), FAIL_OPEN=$FAIL_OPEN" >&2
  if [[ "$FAIL_OPEN" == "true" ]]; then
    _emit_decision "allow" "agent_timeout_fail_open"
    exit 0
  else
    _emit_decision "deny" "agent_timeout_fail_closed"
    exit 2
  fi
fi

# Parse JSON response from agent
if command -v python3 >/dev/null 2>&1; then
  PARSED=$(python3 -c "
import json, sys, re

raw = sys.argv[1]
# Try to extract JSON object from response
m = re.search(r'\{[^{}]*\"decision\"[^{}]*\}', raw, re.DOTALL)
if m:
    try:
        obj = json.loads(m.group())
        d = obj.get('decision', 'allow').lower().strip()
        r = obj.get('reason', 'agent_response')
        # Normalize
        if d not in ('allow', 'deny'):
            d = 'allow'
        print(d + '||' + r)
        sys.exit(0)
    except:
        pass
# Fallback: check for deny keyword
if re.search(r'\bdeny\b', raw, re.IGNORECASE):
    print('deny||agent_denied')
else:
    print('allow||agent_allowed')
" "$RAW_RESPONSE" 2>/dev/null)

  DECISION="${PARSED%%||*}"
  REASON="${PARSED##*||}"
else
  # No python3 — simple grep fallback
  if echo "$RAW_RESPONSE" | grep -qi '"decision".*"deny"\|deny'; then
    DECISION="deny"
    REASON="agent_denied"
  else
    DECISION="allow"
    REASON="agent_allowed"
  fi
fi

# Emit and exit
_emit_decision "$DECISION" "$REASON"

if [[ "$DECISION" == "deny" ]]; then
  exit 2
else
  exit 0
fi
