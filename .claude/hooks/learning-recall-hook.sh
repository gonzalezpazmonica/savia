#!/usr/bin/env bash
# SCL-003/SCL-008 — inject only human-authorized criteria at prompt submit.
# SE-515 S1 — recall trazado: cada consulta deja en SCL_EMISSION_LOG una fila
# `start` (emitted=false) antes de llamar al recall y una fila `end` con los
# criterios emitidos y el motivo. Si el hook muere sin terminar, queda la fila
# `start`: nunca hay ausencia de fila. Solo ids y hashes, nunca el prompt.
# SAVIA_LEARNING_APPLIED=off desactiva el registro (comportamiento anterior).
set -uo pipefail

[[ "${SAVIA_LEARNING_RECALL:-on}" == "on" ]] || exit 0
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
RECALL_SCRIPT="$REPO_ROOT/scripts/learning-recall.sh"
[[ -f "$RECALL_SCRIPT" ]] || exit 0

USER_INPUT=$(cat 2>/dev/null || true)
[[ -n "$USER_INPUT" ]] || exit 0
INPUT_TEXT=$(SCL_INPUT="$USER_INPUT" python3 - <<'PY' 2>/dev/null || true
import json, os
try:
    data = json.loads(os.environ['SCL_INPUT'])
except Exception:
    raise SystemExit
for key in ('content', 'prompt_text'):
    value = data.get(key)
    if isinstance(value, str):
        print(value)
        break
PY
)
[[ -n "$INPUT_TEXT" && ${#INPUT_TEXT} -ge 8 && "$INPUT_TEXT" != /* ]] || exit 0
echo "$INPUT_TEXT" | grep -qiE '^(s[ií]|no|ok|vale|claro|hecho|listo|adelante|gracias|y|n)$' && exit 0

TRACE=false
[[ "${SAVIA_LEARNING_APPLIED:-on}" == "off" ]] || TRACE=true
EMISSION_LOG="${SCL_EMISSION_LOG:-$REPO_ROOT/output/learning-loop/recall-emission.jsonl}"
EVENT_ID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)"
QUERY_HASH="$(printf '%s' "$INPUT_TEXT" | sha256sum | cut -d' ' -f1)"

# trace PHASE EMITTED REASON CRITERIA_JSON — una fila sin contenido del prompt.
trace() {
  $TRACE || return 0
  mkdir -p "$(dirname "$EMISSION_LOG")" 2>/dev/null || return 0
  SCL_PHASE="$1" SCL_EMITTED="$2" SCL_REASON="$3" SCL_CRITERIA="$4" \
  SCL_EVENT="$EVENT_ID" SCL_QHASH="$QUERY_HASH" python3 - "$EMISSION_LOG" <<'PY' 2>/dev/null || true
import datetime, json, os, sys
row = {
    'ts': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'event_id': os.environ['SCL_EVENT'],
    'frontend': 'claude',
    'query_hash': os.environ['SCL_QHASH'],
    'phase': os.environ['SCL_PHASE'],
    'emitted': os.environ['SCL_EMITTED'] == 'true',
    'criteria': json.loads(os.environ['SCL_CRITERIA']),
    'reason': os.environ['SCL_REASON'],
}
with open(sys.argv[1], 'a', encoding='utf-8') as handle:
    handle.write(json.dumps(row, separators=(',', ':')) + '\n')
PY
}

trace start false started '[]'

ARGS=(--query "$INPUT_TEXT" --top 3 --min-score 10 --mode effective --json)
[[ -n "${SCL_CRITERIO_PATH:-}" ]] && ARGS+=(--criterio "$SCL_CRITERIO_PATH")
LEARNINGS=$(timeout "${SCL_RECALL_TIMEOUT_S:-4}" bash "$RECALL_SCRIPT" "${ARGS[@]}" 2>/dev/null)
RC=$?
if (( RC != 0 )); then
  case "$RC" in
    124) trace end false timeout '[]' ;;
    3) trace end false unavailable '[]' ;;
    *) trace end false error '[]' ;;
  esac
  exit 0
fi

PARSED=$(SCL_LEARNINGS="$LEARNINGS" python3 - <<'PY' 2>/dev/null
import json, os
try:
    hits = json.loads(os.environ['SCL_LEARNINGS']).get('effective_hits', [])
    if not isinstance(hits, list):
        raise ValueError
except Exception:
    print(json.dumps({'reason': 'bad_output'}))
    raise SystemExit
if not hits:
    print(json.dumps({'reason': 'no_hits'}))
    raise SystemExit
hits = hits[:3]
lines = ['## Criterios humanos aplicables', '']
for hit in hits:
    lines.append(f"- [{hit['criterion_id']}] {hit['principle']}")
payload = {'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': '\n'.join(lines)}}
print(json.dumps({'reason': 'emitted', 'criteria': [h['criterion_id'] for h in hits], 'payload': payload}, ensure_ascii=False))
PY
)
REASON=$(jq -r '.reason // "bad_output"' <<<"$PARSED" 2>/dev/null)
[[ -n "$REASON" ]] || REASON=bad_output
if [[ "$REASON" != "emitted" ]]; then
  trace end false "$REASON" '[]'
  exit 0
fi
if jq -c '.payload' <<<"$PARSED" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), ensure_ascii=False))'; then
  trace end true emitted "$(jq -c '.criteria' <<<"$PARSED")"
else
  trace end false write_failed '[]'
fi
exit 0
