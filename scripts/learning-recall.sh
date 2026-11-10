#!/usr/bin/env bash
# learning-recall.sh — SCL-003/SCL-008: authority-filtered SaviaLearning recall.
# SE-515 S1: la fila del log lleva los criterios devueltos (`returned_criteria`)
# y el resultado (`outcome`: ok | no_vault | no_cli), también cuando sale con 3.
# SAVIA_LEARNING_APPLIED=off conserva el formato y las salidas anteriores.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

QUERY=""
TOP=5
MIN_SCORE="${SCL_RECALL_MIN_SCORE:-5}"
MODE="shadow"
VAULT="${SCL_VAULT_DIR:-$ROOT/vaults/SaviaLearning}"
CRITERIO="${SCL_CRITERIO_PATH:-$ROOT/CRITERIO.md}"
NODE_BIN="${SCL_NODE_PATH:-}"
JSON=false
HYBRID=false
RECALL_LOG="${SCL_RECALL_LOG:-$ROOT/output/learning-loop/recall.jsonl}"

usage() {
  echo "Usage: learning-recall.sh --query <text> [--top 1..20] [--min-score N] [--mode shadow|effective] [--criterio path] [--vault path] [--json]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query) [[ $# -ge 2 ]] || usage; QUERY="$2"; shift 2 ;;
    --top) [[ $# -ge 2 ]] || usage; TOP="$2"; shift 2 ;;
    --min-score) [[ $# -ge 2 ]] || usage; MIN_SCORE="$2"; shift 2 ;;
    --mode) [[ $# -ge 2 ]] || usage; MODE="$2"; shift 2 ;;
    --criterio) [[ $# -ge 2 ]] || usage; CRITERIO="$2"; shift 2 ;;
    --vault) [[ $# -ge 2 ]] || usage; VAULT="$2"; shift 2 ;;
    --node-path) [[ $# -ge 2 ]] || usage; NODE_BIN="$2"; shift 2 ;;
    --json) JSON=true; shift ;;
    --hybrid) HYBRID=true; shift ;;
    --recall-log) [[ $# -ge 2 ]] || usage; RECALL_LOG="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

[[ -n "$QUERY" ]] || usage
[[ "$TOP" =~ ^[0-9]+$ ]] && (( TOP >= 1 && TOP <= 20 )) || usage
[[ "$MIN_SCORE" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
[[ "$MODE" == "shadow" || "$MODE" == "effective" ]] || usage

TRACE=true
[[ "${SAVIA_LEARNING_APPLIED:-on}" == "off" ]] && TRACE=false
QUERY_HASH=$(printf '%s' "$QUERY" | sha256sum | cut -d' ' -f1)

# log_row OUTCOME RESULT_JSON — una fila por consulta; nunca el texto de la consulta.
log_row() {
  mkdir -p "$(dirname "$RECALL_LOG")" 2>/dev/null || return 0
  SCL_OUTCOME="$1" SCL_RESULT="$2" SCL_QUERY_HASH="$QUERY_HASH" SCL_TRACE="$TRACE" python3 - "$RECALL_LOG" <<'PY' 2>/dev/null || true
import datetime, json, os, sys
d = json.loads(os.environ['SCL_RESULT'])
entry = {'ts': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), 'query_hash': os.environ['SCL_QUERY_HASH'], 'mode': d['mode'], 'effective_hits': len(d['effective_hits']), 'shadow_hits': d['shadow_hits'], 'rejected_hits': d['rejected_hits'], 'proposal_ids': d['proposal_ids']}
if os.environ['SCL_TRACE'] == 'true':
    entry['returned_criteria'] = [hit['criterion_id'] for hit in d['effective_hits']]
    entry['outcome'] = os.environ['SCL_OUTCOME']
with open(sys.argv[1], 'a', encoding='utf-8') as handle:
    handle.write(json.dumps(entry, separators=(',', ':')) + '\n')
PY
}
empty_result() { printf '{"mode":"%s","effective_hits":[],"shadow_hits":0,"rejected_hits":0,"proposal_ids":[]}' "$MODE"; }

if [[ ! -d "$VAULT" || ! -f "$CRITERIO" ]]; then
  $TRACE && log_row no_vault "$(empty_result)"
  exit 3
fi

if [[ -z "$NODE_BIN" ]]; then
  for cand in "$HOME/.nvm/versions/node"/*/bin/node /usr/local/bin/node /usr/bin/node; do
    [[ -x "$cand" ]] && { NODE_BIN="$cand"; break; }
  done
fi
CLI="${SCL_VAULT_CLI:-$ROOT/projects/savia-vaults/dist/cli/index.js}"
if [[ -z "$NODE_BIN" || ! -f "$CLI" ]]; then
  $TRACE && log_row no_cli "$(empty_result)"
  exit 3
fi

if $HYBRID; then
  SEARCH_OUT=$(python3 - "$VAULT/learning" <<'PY'
import json, os, sys
d = sys.argv[1]
rows = []
if not os.path.isdir(d):
    print('[]')
    raise SystemExit
for f in sorted(os.listdir(d)):
    if not f.endswith('.md'):
        continue
    path = f"learning/{f}"
    try:
        text = open(os.path.join(d, f), encoding='utf-8').read()
    except Exception:
        text = ""
    rows.append({"path": path, "score": 0, "snippet": text})
print(json.dumps(rows))
PY
  ) || SEARCH_OUT="[]"

  if [[ -f "$SCRIPT_DIR/learning-hybrid.py" && "$SEARCH_OUT" != "[]" ]]; then
    PAYLOAD=$(SCL_QUERY="$QUERY" python3 - "$SEARCH_OUT" <<'PY'
import json, os, sys
rows = json.loads(sys.argv[1])
print(json.dumps({'query': os.environ['SCL_QUERY'], 'docs': [{'path': row['path'], 'text': row['snippet']} for row in rows]}))
PY
    )
    HYBRID_OUT=$(SCL_VENV_PYTHON="${SCL_VENV_PYTHON:-$HOME/.savia/venv/bin/python}" python3 "$SCRIPT_DIR/learning-hybrid.py" <<< "$PAYLOAD" 2>/dev/null) || HYBRID_OUT=""
    if [[ -n "$HYBRID_OUT" ]]; then
      SEARCH_OUT=$(python3 - "$HYBRID_OUT" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
print(json.dumps([{'path': hit['path'], 'score': hit.get('score', 0)} for hit in data.get('hits', [])]))
PY
      ) || SEARCH_OUT="[]"
    fi
  fi
else
  SEARCH_OUT=$("$NODE_BIN" "$CLI" search "$QUERY" --path "$VAULT" --json 2>/dev/null) || SEARCH_OUT="[]"
fi
[[ -n "$SEARCH_OUT" ]] || SEARCH_OUT="[]"

RESULT=$(SCL_TOP="$TOP" SCL_MIN_SCORE="$MIN_SCORE" SCL_MODE="$MODE" SCL_VAULT="$VAULT" SCL_CRITERIO="$CRITERIO" SCL_HYBRID="$HYBRID" python3 - "$SEARCH_OUT" <<'PY'
import json, os, pathlib, re, sys
try:
    results = json.loads(sys.argv[1])
except Exception:
    results = []
if not isinstance(results, list):
    results = []

top = int(os.environ['SCL_TOP'])
minimum = float(os.environ['SCL_MIN_SCORE'])
hybrid = os.environ['SCL_HYBRID'] == 'true'
mode = os.environ['SCL_MODE']
vault = pathlib.Path(os.environ['SCL_VAULT']).resolve()
criterio_text = pathlib.Path(os.environ['SCL_CRITERIO']).read_text(encoding='utf-8')

criteria = {}
matches = list(re.finditer(r'(?m)^CRIT-(\d{3})\s+[^\n]*$', criterio_text))
for index, match in enumerate(matches):
    block = criterio_text[match.start():matches[index + 1].start() if index + 1 < len(matches) else len(criterio_text)]
    principle = re.search(r'(?m)^\s*principio:\s*(.+)$', block)
    provenance = re.search(r'(?m)^\s*provenance:\s*(\S+)\s*$', block)
    if principle and provenance:
        criteria[f"CRIT-{match.group(1)}"] = (principle.group(1).strip(), provenance.group(1))

effective = []
shadow = 0
rejected = 0
proposal_ids = []
seen_criteria = set()
for row in results[:top]:
    try:
        score = float(row.get('score', 0))
    except (TypeError, ValueError):
        score = 0
    if (not hybrid and score < minimum) or (hybrid and score <= 0):
        continue
    raw_path = row.get('path') or row.get('source') or ''
    path = pathlib.Path(raw_path)
    if not path.is_absolute():
        path = vault / path
    try:
        path = path.resolve()
        if os.path.commonpath((vault, path)) != str(vault):
            rejected += 1
            continue
        note = path.read_text(encoding='utf-8')
    except (OSError, UnicodeError):
        rejected += 1
        continue
    def field(name):
        found = re.search(rf'(?m)^\s*{re.escape(name)}:\s*(.*?)\s*$', note)
        return found.group(1) if found else ''
    proposal_id = field('id')
    if proposal_id:
        proposal_ids.append(proposal_id)
    provenance = field('provenance')
    lifecycle = field('lifecycle')
    target = field('target')
    criterion_id = field('criterion_id')
    if provenance == 'INFERRED' or lifecycle == 'proposed':
        shadow += 1
        continue
    criterion = criteria.get(criterion_id)
    authorized = target == 'criterio' and lifecycle == 'active' and provenance == 'human_authored' and criterion and criterion[1] == 'human_authored'
    if not authorized:
        rejected += 1
        continue
    if mode == 'shadow':
        shadow += 1
        continue
    if criterion_id in seen_criteria:
        continue
    seen_criteria.add(criterion_id)
    effective.append({'proposal_id': proposal_id, 'criterion_id': criterion_id, 'score': score, 'principle': criterion[0]})
    if len(effective) == 3:
        break

effective.sort(key=lambda hit: (-hit['score'], hit['criterion_id']))
print(json.dumps({'mode': mode, 'effective_hits': effective, 'shadow_hits': shadow, 'rejected_hits': rejected, 'proposal_ids': sorted(set(proposal_ids))}, ensure_ascii=False))
PY
)
OUTCOME=ok
[[ -n "$RESULT" ]] || { RESULT='{"mode":"shadow","effective_hits":[],"shadow_hits":0,"rejected_hits":0,"proposal_ids":[]}'; OUTCOME=error; }

log_row "$OUTCOME" "$RESULT"

if $JSON; then
  SCL_RESULT="$RESULT" SCL_QUERY="$QUERY" python3 - <<'PY'
import json, os
d = json.loads(os.environ['SCL_RESULT'])
d = {'query': os.environ['SCL_QUERY'], **d}
d.pop('proposal_ids', None)
print(json.dumps(d, ensure_ascii=False))
PY
elif [[ "$MODE" == "effective" ]]; then
  SCL_RESULT="$RESULT" python3 - <<'PY'
import json, os
for hit in json.loads(os.environ['SCL_RESULT'])['effective_hits']:
    print(f"- [{hit['criterion_id']}] {hit['principle']}")
PY
fi
exit 0
