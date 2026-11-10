#!/usr/bin/env bash
# learning-recall-ablation.sh — SE-515 S1 (AC-5, sonda P10): recall apagado frente a encendido.
#
# Para cada caso ejecuta el inyector de recall del frontend dos veces, con SAVIA_LEARNING_RECALL=off
# y =on, y pasa el prompt y el contexto inyectado a un decisor externo. Cuenta en cuántos casos
# cambió la decisión. Cero cambios es un resultado válido.
#
# Usage:
#   learning-recall-ablation.sh --cases <casos.jsonl> --injector <ejecutable> --decider <ejecutable>
#                               [--root <dir>] [--out <filas.jsonl>]
#
# Inyector: el binding de recall de un frontend (o un envoltorio suyo). Recibe por stdin
#   {"content": prompt}, con SAVIA_WORKSPACE_DIR=<root> y cwd=<root>, y escribe JSON con
#   hookSpecificOutput.additionalContext. El arnés no sabe de qué frontend se trata.
# Casos (JSONL): {"case_id": "...", "prompt": "...", "control": false}
#   control=true marca un caso con criterio irrelevante: no debería cambiar (control negativo).
# Decisor: recibe por stdin {"case_id","prompt","context"} y escribe la decisión en la primera línea.
#
# Salida (stdout, una línea JSON): cases, emitting_cases, changed, changed_controls, errors, verdict.
#   verdict: cambio | sin efecto | sin muestra (ningún caso emitió criterio) | incompleto (decisor falló).
# Filas por caso (--out, legibles por S09): case_id, control, decision_off, decision_on, changed,
#   emitted_criteria, cost_ms_off, cost_ms_on, context_chars_on. Nunca el texto del prompt.
#
# Exit: 0 ok · 1 incompleto · 2 entrada inválida.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASES="" DECIDER="" INJECTOR="" TARGET_ROOT="$ROOT" OUT=""

usage() { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cases) [[ $# -ge 2 ]] || usage; CASES="$2"; shift 2 ;;
    --decider) [[ $# -ge 2 ]] || usage; DECIDER="$2"; shift 2 ;;
    --injector) [[ $# -ge 2 ]] || usage; INJECTOR="$2"; shift 2 ;;
    --root) [[ $# -ge 2 ]] || usage; TARGET_ROOT="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || usage; OUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

[[ -n "$CASES" && -r "$CASES" ]] || { echo "ERROR: --cases ilegible" >&2; exit 2; }
[[ -n "$DECIDER" && -x "$DECIDER" ]] || { echo "ERROR: --decider no ejecutable" >&2; exit 2; }
[[ -n "$INJECTOR" && -x "$INJECTOR" ]] || { echo "ERROR: --injector no ejecutable" >&2; exit 2; }
[[ -d "$TARGET_ROOT" ]] || { echo "ERROR: --root no es un directorio" >&2; exit 2; }
# El inyector corre con cwd=<root>: rutas absolutas para que una ruta relativa no cambie de sentido.
INJECTOR="$(realpath "$INJECTOR")"; DECIDER="$(realpath "$DECIDER")"

python3 - "$CASES" "$DECIDER" "$INJECTOR" "$TARGET_ROOT" "$OUT" <<'PY'
import json, os, re, subprocess, sys, tempfile, time

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
env_base = dict(os.environ, SAVIA_WORKSPACE_DIR=root,
                SCL_EMISSION_LOG=os.path.join(scratch, 'emission.jsonl'),
                SCL_RECALL_LOG=os.path.join(scratch, 'recall.jsonl'))

def context_for(prompt, recall):
    env = dict(env_base, SAVIA_LEARNING_RECALL=recall)
    proc = subprocess.run([injector], input=json.dumps({'content': prompt}), env=env, cwd=root,
                          capture_output=True, text=True, timeout=30)
    try:
        return json.loads(proc.stdout)['hookSpecificOutput']['additionalContext']
    except Exception:
        return ''

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
if errors:
    verdict = 'incompleto'
elif emitting == 0:
    verdict = 'sin muestra'
elif changed == 0:
    verdict = 'sin efecto'
else:
    verdict = 'cambio'
print(json.dumps({'cases': len(rows), 'emitting_cases': emitting, 'changed': changed,
                  'changed_controls': changed_controls, 'errors': errors, 'verdict': verdict},
                 ensure_ascii=False))
for name in os.listdir(scratch):
    os.unlink(os.path.join(scratch, name))
os.rmdir(scratch)
sys.exit(1 if errors else 0)
PY
