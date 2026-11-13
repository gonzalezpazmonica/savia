#!/usr/bin/env bash
# learning-recall.sh — SCL-003/SCL-008: authority-filtered SaviaLearning recall.
# SE-515 S1: la fila del log lleva los criterios devueltos (`returned_criteria`)
# y el resultado (`outcome`: ok | no_vault | no_cli | error), también cuando sale con 3.
# Exit: 0 ok (con o sin aciertos) · 2 uso · 3 sin cúpula o sin CLI · 4 error del buscador o
# salida ilegible (con SAVIA_LEARNING_APPLIED=off sale 0 y vacío, como antes).
# SAVIA_LEARNING_APPLIED=off conserva el formato y las salidas anteriores.
# Subcomando `ablation`: sonda P10 de SE-515 (ver abajo).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── SE-515 S1 (AC-5, sonda P10): learning-recall.sh ablation ─────────────────
# Recall apagado frente a encendido sobre los mismos casos. Para cada caso ejecuta el inyector de
# recall del frontend con SAVIA_LEARNING_RECALL=off y =on y pasa prompt y contexto a un decisor
# externo. Cuenta en cuántos casos cambió la decisión; cero cambios es un resultado válido.
#   learning-recall.sh ablation --cases <casos.jsonl> --injector <ejec> --decider <ejec>
#                               [--root <dir>] [--out <filas.jsonl>]
#   Tope por llamada al inyector: SCL_ABLATION_INJECTOR_TIMEOUT_S (30 s).
# Casos (JSONL): {"case_id","prompt","control"}; control=true es control negativo.
# Inyector: recibe {"content": prompt} por stdin con SAVIA_WORKSPACE_DIR=<root> y cwd=<root>, y
#   escribe JSON con hookSpecificOutput.additionalContext (stdout vacío = no emitió). No se nombra
#   ningún frontend. Fallo del inyector (cuenta en errors, nunca como «no emitió»): tope, exit != 0,
#   stdout sin additionalContext, o evento de su log de emisión (SCL_EMISSION_LOG) sin fila `end` o
#   terminado en error | timeout | bad_output | write_failed, o contexto emitido con el recall
#   encendido sin ninguna fila `end` emitted=true (emisión sin evidencia, AC-3).
# Decisor: recibe {"case_id","prompt","context"} por stdin; primera línea = decisión.
# Salida: cases, emitting_cases, changed, changed_controls, errors, verdict
#   (cambio | sin efecto | sin muestra | ruido | incompleto); ruido = cambió un control negativo.
#   --out: filas por caso legibles por S09 (case_id, control, decision_off, decision_on, changed,
#   injector_failed, emitted_criteria, cost_ms_off, cost_ms_on, context_chars_on), nunca el texto
#   del prompt. Exit: 0 · 1 incompleto o ruido · 2 entrada.
ablation_usage() { echo "Usage: learning-recall.sh ablation --cases F --injector X --decider X [--root D] [--out F]" >&2; exit 2; }
ablation() {
  local CASES="" DECIDER="" INJECTOR="" TARGET_ROOT="$ROOT" OUT=""


  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cases) [[ $# -ge 2 ]] || ablation_usage; CASES="$2"; shift 2 ;;
      --decider) [[ $# -ge 2 ]] || ablation_usage; DECIDER="$2"; shift 2 ;;
      --injector) [[ $# -ge 2 ]] || ablation_usage; INJECTOR="$2"; shift 2 ;;
      --root) [[ $# -ge 2 ]] || ablation_usage; TARGET_ROOT="$2"; shift 2 ;;
      --out) [[ $# -ge 2 ]] || ablation_usage; OUT="$2"; shift 2 ;;
      *) ablation_usage ;;
    esac
  done

  [[ -n "$CASES" && -r "$CASES" ]] || { echo "ERROR: --cases ilegible" >&2; exit 2; }
  [[ -n "$DECIDER" && -x "$DECIDER" ]] || { echo "ERROR: --decider no ejecutable" >&2; exit 2; }
  [[ -n "$INJECTOR" && -x "$INJECTOR" ]] || { echo "ERROR: --injector no ejecutable" >&2; exit 2; }
  [[ -d "$TARGET_ROOT" ]] || { echo "ERROR: --root no es un directorio" >&2; exit 2; }
  # El inyector corre con cwd=<root>: rutas absolutas para que una ruta relativa no cambie de sentido.
  INJECTOR="$(realpath "$INJECTOR")"; DECIDER="$(realpath "$DECIDER")"

  python3 - "$CASES" "$DECIDER" "$INJECTOR" "$TARGET_ROOT" "$OUT" <<'PY'
import atexit, json, os, re, shutil, subprocess, sys, tempfile, time

cases_file, decider, injector, root, out = sys.argv[1:6]
try:
    cases = [json.loads(line) for line in open(cases_file, encoding='utf-8') if line.strip()]
    for c in cases:
        if not isinstance(c.get('case_id'), str) or not isinstance(c.get('prompt'), str):
            raise ValueError
except Exception:
    print(json.dumps({'error': 'casos inválidos'}))
    sys.exit(2)

scratch = tempfile.mkdtemp(prefix='p10-')
atexit.register(shutil.rmtree, scratch, True)  # también si algo aborta con excepción
env_base = dict(os.environ, SAVIA_WORKSPACE_DIR=root,
                SCL_RECALL_LOG=os.path.join(scratch, 'recall.jsonl'))

# Fallos del inyector que el log de emisión de S1 declara (fila `end` con este motivo).
INJECTOR_FAILURES = {'error', 'timeout', 'bad_output', 'write_failed'}
calls = 0
injector_timeout = float(os.environ.get('SCL_ABLATION_INJECTOR_TIMEOUT_S', '30'))

def context_for(prompt, recall):
    """Contexto inyectado ('' si el inyector no emitió) o None si el inyector falló.
    Fallo: excepción o tope, exit != 0, stdout no vacío sin hookSpecificOutput.additionalContext
    de tipo texto, o un evento del log de emisión sin fila `end` o terminado con un motivo de fallo."""
    global calls
    calls += 1
    log = os.path.join(scratch, f'emission-{calls}.jsonl')
    env = dict(env_base, SAVIA_LEARNING_RECALL=recall, SCL_EMISSION_LOG=log)
    try:
        proc = subprocess.run([injector], input=json.dumps({'content': prompt}), env=env, cwd=root,
                              capture_output=True, text=True, timeout=injector_timeout)
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    context = ''
    if proc.stdout.strip():
        try:
            context = json.loads(proc.stdout)['hookSpecificOutput']['additionalContext']
        except Exception:
            return None
        if not isinstance(context, str):
            return None
    if os.path.exists(log):
        try:
            events = {}
            for line in open(log, encoding='utf-8'):
                if line.strip():
                    row = json.loads(line)
                    events.setdefault(row['event_id'], []).append(row)
        except Exception:
            return None
        for evt in events.values():
            ends = [r for r in evt if r.get('phase') == 'end']
            if not ends or ends[-1].get('reason') in INJECTOR_FAILURES:
                return None
    # Refutación Codex (PR #1523): con el recall encendido, un contexto emitido sin su fila `end`
    # emitted=true es una emisión sin evidencia (AC-3); cuenta como fallo, no como emisión válida.
    if context and recall == 'on':
        ends = [r for evt in events.values() for r in evt if r.get('phase') == 'end'] if os.path.exists(log) else []
        if not any(r.get('emitted') is True for r in ends):
            return None
    return context

def decide(case, context):
    started = time.monotonic()
    payload = json.dumps({'case_id': case['case_id'], 'prompt': case['prompt'], 'context': context})
    try:
        proc = subprocess.run([decider], input=payload, capture_output=True, text=True, timeout=300)
    except Exception:
        return None, int((time.monotonic() - started) * 1000)
    elapsed = int((time.monotonic() - started) * 1000)
    lines = proc.stdout.strip().splitlines()
    if proc.returncode != 0 or not lines:
        return None, elapsed
    return lines[0].strip(), elapsed

rows, errors = [], 0
for case in cases:
    ctx_off = context_for(case['prompt'], 'off')
    ctx_on = context_for(case['prompt'], 'on')
    injector_failed = ctx_off is None or ctx_on is None
    if injector_failed:
        d_off = d_on = None
        ms_off = ms_on = 0
        ctx_on = ctx_on or ''
    else:
        d_off, ms_off = decide(case, ctx_off)
        d_on, ms_on = decide(case, ctx_on)
    if d_off is None or d_on is None:
        errors += 1
    rows.append({
        'case_id': case['case_id'],
        'control': bool(case.get('control', False)),
        'decision_off': d_off,
        'decision_on': d_on,
        'changed': d_off is not None and d_on is not None and d_off != d_on,
        'injector_failed': injector_failed,
        'emitted_criteria': re.findall(r'^- \[([^\]]+)\]', ctx_on, re.M),
        'cost_ms_off': ms_off,
        'cost_ms_on': ms_on,
        'context_chars_on': len(ctx_on),
    })

if out:
    with open(out, 'w', encoding='utf-8') as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + '\n')

emitting = sum(1 for r in rows if r['emitted_criteria'])
changed = sum(1 for r in rows if r['changed'] and not r['control'])
changed_controls = sum(1 for r in rows if r['changed'] and r['control'])
# Un control negativo que cambia de decisión invalida la medida: el decisor no es estable.
if errors:
    verdict = 'incompleto'
elif changed_controls:
    verdict = 'ruido'
elif emitting == 0:
    verdict = 'sin muestra'
elif changed == 0:
    verdict = 'sin efecto'
else:
    verdict = 'cambio'
print(json.dumps({'cases': len(rows), 'emitting_cases': emitting, 'changed': changed,
                  'changed_controls': changed_controls, 'errors': errors, 'verdict': verdict},
                 ensure_ascii=False))
sys.exit(1 if verdict in ('incompleto', 'ruido') else 0)
PY
}

if [[ "${1:-}" == "ablation" ]]; then
  shift
  ablation "$@"
  exit $?
fi

QUERY=""
TOP=5
MIN_SCORE="${SCL_RECALL_MIN_SCORE:-5}"
MODE="shadow"
VAULT="${SCL_VAULT_DIR:-$ROOT/vaults/SaviaLearning}"
CRITERIO="${SCL_CRITERIO_PATH:-$ROOT/CRITERIO.md}"
NODE_BIN="${SCL_NODE_PATH:-}"
JSON=false
HYBRID=false
SEARCH_FAILED=false
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
  # Refutación Codex (PR #1523): un buscador que falla o devuelve algo que no es una lista JSON
  # es un error, no «sin aciertos». Se registra outcome=error y sale con 4 (interruptor off: como antes).
  SEARCH_OUT=$("$NODE_BIN" "$CLI" search "$QUERY" --path "$VAULT" --json 2>/dev/null) || { SEARCH_OUT="[]"; SEARCH_FAILED=true; }
  if ! $SEARCH_FAILED && ! python3 -c 'import json,sys; sys.exit(0 if isinstance(json.loads(sys.argv[1]), list) else 1)' "$SEARCH_OUT" 2>/dev/null; then
    SEARCH_OUT="[]"; SEARCH_FAILED=true
  fi
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
[[ -n "$RESULT" ]] || { RESULT="$(empty_result)"; OUTCOME=error; }
$SEARCH_FAILED && { RESULT="$(empty_result)"; OUTCOME=error; }

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
[[ "$OUTCOME" == "error" ]] && $TRACE && exit 4
exit 0
