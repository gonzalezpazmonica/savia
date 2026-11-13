#!/usr/bin/env bash
set -uo pipefail
# SCL-003/SCL-008 — inject only human-authorized criteria at prompt submit.
# SE-515 S1 — recall trazado: cada consulta deja en SCL_EMISSION_LOG una fila
# `start` (emitted=false) antes de llamar al recall y una fila `end` con los
# criterios emitidos y el motivo. Si el hook muere sin terminar, queda la fila
# `start`: nunca hay ausencia de fila. Solo ids y hashes, nunca el prompt.
# Sin fila escrita no se emite: si falla la fila `start` o la `end` emitted=true,
# el hook no inyecta nada (refutación Codex PR #1523). La fila `end` se escribe
# antes de emitir; si la emisión falla después, se añade otra `end` write_failed.
# SAVIA_LEARNING_APPLIED=off desactiva el registro (comportamiento anterior, sin jq).

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
# Exit 0 si la fila quedó escrita (o el registro está apagado); 1 si no.
trace() {
  $TRACE || return 0
  mkdir -p "$(dirname "$EMISSION_LOG")" 2>/dev/null || return 1
  SCL_PHASE="$1" SCL_EMITTED="$2" SCL_REASON="$3" SCL_CRITERIA="$4" \
  SCL_EVENT="$EVENT_ID" SCL_QHASH="$QUERY_HASH" python3 - "$EMISSION_LOG" <<'PY' 2>/dev/null
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

if ! trace start false started '[]'; then
  echo "learning-recall-hook: no se pudo escribir la fila de emisión; no se inyectan criterios" >&2
  exit 0
fi

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

# Una sola pasada en python: motivo, criterios y payload (sin jq en la ruta funcional).
PARSED=$(SCL_LEARNINGS="$LEARNINGS" python3 - <<'PY' 2>/dev/null
import json, os
def out(reason, criteria=None, payload=None):
    print(reason)
    print(json.dumps(criteria or []))
    print(json.dumps(payload, ensure_ascii=False) if payload else '')
    raise SystemExit
try:
    hits = json.loads(os.environ['SCL_LEARNINGS']).get('effective_hits', [])
    if not isinstance(hits, list):
        raise ValueError
    for hit in hits:
        if not (isinstance(hit, dict) and isinstance(hit.get('criterion_id'), str) and hit['criterion_id']
                and isinstance(hit.get('principle'), str)):
            raise ValueError
except Exception:
    out('bad_output')
if not hits:
    out('no_hits')
hits = hits[:3]
lines = ['## Criterios humanos aplicables', '']
for hit in hits:
    lines.append(f"- [{hit['criterion_id']}] {hit['principle']}")
payload = {'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': '\n'.join(lines)}}
out('emitted', [h['criterion_id'] for h in hits], payload)
PY
)
REASON=$(sed -n 1p <<<"$PARSED")
CRITERIA=$(sed -n 2p <<<"$PARSED")
PAYLOAD=$(sed -n 3p <<<"$PARSED")
[[ -n "$REASON" ]] || REASON=bad_output
if [[ "$REASON" != "emitted" || -z "$PAYLOAD" ]]; then
  [[ "$REASON" == "emitted" ]] && REASON=bad_output
  trace end false "$REASON" '[]'
  exit 0
fi
# Primero la evidencia, después la emisión.
if ! trace end true emitted "$CRITERIA"; then
  echo "learning-recall-hook: no se pudo escribir la fila de emisión; no se inyectan criterios" >&2
  exit 0
fi
printf '%s\n' "$PAYLOAD" || trace end false write_failed '[]'
exit 0
