#!/usr/bin/env bash
# Controlled local READ/SAFE_BASH corpus for SE-397 F4.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
EVENTS=""

usage() {
  echo "Usage: $0 --events <jsonl>"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --events) EVENTS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$EVENTS" ]] || { echo "ERROR: --events is required" >&2; exit 2; }
if [[ -L "$EVENTS" || ( -e "$EVENTS" && ! -f "$EVENTS" ) ]]; then
  echo "ERROR: unsafe events target" >&2
  exit 2
fi
mkdir -p "$(dirname "$EVENTS")"
: > "$EVENTS"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# The corpus has no user-selected command and no network-capable code path.
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY='*' SAVIA_NETWORK_DISABLED=1

MODEL_REVISION="$(python3 - "$ROOT/.scm/sam.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["model_revision"])
PY
)"
EMITTER="$ROOT/scripts/otel-emit.sh"
HOOK="$ROOT/.opencode/hooks/validate-bash-global.sh"
READ_ROOT="$TMP_DIR/read-repo"

cp -R "$ROOT/tests/fixtures/sam/valid" "$READ_ROOT"
git -C "$READ_ROOT" init -q
git -C "$READ_ROOT" -c user.name='F4 Corpus' -c user.email='f4-corpus@localhost' \
  add .
git -C "$READ_ROOT" -c user.name='F4 Corpus' -c user.email='f4-corpus@localhost' \
  commit -qm fixture
python3 "$ROOT/scripts/sam.py" generate --root "$READ_ROOT" >/dev/null

python3 - "$ROOT/.claude/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1], encoding="utf-8"))
commands = [
    hook.get("command", "")
    for groups in settings.get("hooks", {}).values()
    for group in groups
    for hook in group.get("hooks", [])
]
if not any("validate-bash-global.sh" in command for command in commands):
    raise SystemExit("registered hook missing")
PY

emit() {
  local trace_id="$1"
  shift
  SAVIA_TELEMETRY_FILE="$EVENTS" \
    SAVIA_TRACEPARENT="00-${trace_id}-aaaaaaaaaaaaaaaa-01" \
    "$EMITTER" "$@"
}

elapsed_ms() {
  local started="$1" ended="$2"
  echo $(( (ended - started) / 1000000 ))
}

# READ: execute the real read-only SAM query path.
READ_OPERATION="11111111111111111111111111111111"
READ_TRACE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
emit "$READ_TRACE" operation.started \
  operation_id="$READ_OPERATION" request_id=null flow_id=flow:read \
  model_revision="$MODEL_REVISION" frontend_id=f4-corpus sequence=0 outcome=unknown
start_ns="$(date +%s%N)"
python3 "$ROOT/scripts/sam.py" query --root "$READ_ROOT" --node flow:read \
  > "$TMP_DIR/read-result.json"
python3 - "$TMP_DIR/read-result.json" <<'PY'
import json, sys
if json.load(open(sys.argv[1], encoding="utf-8")).get("status") != "FOUND":
    raise SystemExit("READ command did not execute")
PY
end_ns="$(date +%s%N)"
read_ms="$(elapsed_ms "$start_ns" "$end_ns")"
emit "$READ_TRACE" operation.segment \
  operation_id="$READ_OPERATION" request_id=null flow_id=flow:read \
  model_revision="$MODEL_REVISION" frontend_id=f4-corpus sequence=1 \
  phase=EXECUTION architecture_node_id=component:sam-generator \
  duration_ms="$read_ms" evidence_ref=null
emit "$READ_TRACE" operation.completed \
  operation_id="$READ_OPERATION" request_id=null flow_id=flow:read \
  model_revision="$MODEL_REVISION" frontend_id=f4-corpus sequence=2 \
  duration_ms="$read_ms" outcome=success

# SAFE_BASH: pass a fixed harmless command through a registered security hook,
# then execute it into the private temporary directory.
BASH_OPERATION="22222222222222222222222222222222"
BASH_TRACE="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
emit "$BASH_TRACE" operation.started \
  operation_id="$BASH_OPERATION" request_id=null flow_id=flow:bash \
  model_revision="$MODEL_REVISION" frontend_id=f4-corpus sequence=0 outcome=unknown
hook_start="$(date +%s%N)"
printf '%s\n' '{"tool_input":{"command":"printf safe-bash-executed"}}' | \
  CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK"
hook_end="$(date +%s%N)"
hook_ms="$(elapsed_ms "$hook_start" "$hook_end")"
emit "$BASH_TRACE" operation.segment \
  operation_id="$BASH_OPERATION" request_id=null flow_id=flow:bash \
  model_revision="$MODEL_REVISION" frontend_id=f4-corpus sequence=1 \
  phase=GOVERNANCE architecture_node_id=flow:bash \
  duration_ms="$hook_ms" evidence_ref=null

command_start="$(date +%s%N)"
printf '%s\n' 'safe-bash-executed' > "$TMP_DIR/safe-bash.marker"
grep -qx 'safe-bash-executed' "$TMP_DIR/safe-bash.marker"
command_end="$(date +%s%N)"
command_ms="$(elapsed_ms "$command_start" "$command_end")"
emit "$BASH_TRACE" operation.segment \
  operation_id="$BASH_OPERATION" request_id=null flow_id=flow:bash \
  model_revision="$MODEL_REVISION" frontend_id=f4-corpus sequence=2 \
  phase=EXECUTION architecture_node_id=flow:bash \
  duration_ms="$command_ms" evidence_ref=null
emit "$BASH_TRACE" operation.completed \
  operation_id="$BASH_OPERATION" request_id=null flow_id=flow:bash \
  model_revision="$MODEL_REVISION" frontend_id=f4-corpus sequence=3 \
  duration_ms="$((hook_ms + command_ms))" outcome=success

echo "READ_COMMAND_EXECUTED=1"
echo "SAFE_BASH_COMMAND_EXECUTED=1"
echo "REGISTERED_HOOK_EXECUTED=1"
