#!/usr/bin/env bash
# judge-calibration.sh — FP/FN tracking para jueces adversariales (SE-269 S4)
# Uso: bash scripts/judge-calibration.sh --report <juez>
#      bash scripts/judge-calibration.sh --dispose <hallazgo-id> <disposicion> [juez]
#      bash scripts/judge-calibration.sh --fn-record <hallazgo-id> <juez> <descripcion>
# Disposiciones: aceptado | descartado-nimiedad | descartado-malentendido | descartado-inexistente
# FN = falso negativo: fallo que escapo a produccion y un juez debio detectar
set -uo pipefail

CALIBRATION_FILE="${CALIBRATION_FILE:-output/judge-calibration.jsonl}"
FN_FILE="${FN_FILE:-output/judge-false-negatives.jsonl}"
DEGRADATION_FILE="${DEGRADATION_FILE:-output/judge-degradation.jsonl}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_JUDGE=""
DISPOSE_ID=""
DISPOSE_VALUE=""
DISPOSE_JUDGE=""
OP=""

# Los argumentos faltantes quedan vacíos (set -u) y cada operación valida los suyos.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) OP="report"; REPORT_JUDGE="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
    --dispose) OP="dispose"; DISPOSE_ID="${2:-}"; DISPOSE_VALUE="${3:-}"; shift $(( $# < 3 ? $# : 3 ))
      # juez opcional (4.º argumento): sin él la disposición no cuenta en --report/--publish por juez
      if [[ $# -gt 0 && "$1" != --* ]]; then DISPOSE_JUDGE="$1"; shift; fi ;;
    --fn-record) OP="fn-record"; FN_ID="${2:-}"; FN_JUDGE="${3:-}"; FN_DESC="${4:-}"; shift $(( $# < 4 ? $# : 4 )) ;;
    --degrade) OP="degrade"; DEGRADE_JUDGE="${2:-}"; DEGRADE_REASON="${3:-}"; shift $(( $# < 3 ? $# : 3 )) ;;
    --restore) OP="restore"; RESTORE_JUDGE="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
    --publish) OP="publish"; PUBLISH_JUDGE="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
    --help|-h) echo "Uso: judge-calibration.sh --report <juez> | --dispose <id> <disp> [juez] | --fn-record <id> <juez> <desc> | --publish <juez>"; exit 0 ;;
    *) shift ;;
  esac
done


mkdir -p "$(dirname "$CALIBRATION_FILE")" 2>/dev/null || true

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Los valores de usuario viajan por entorno: nunca se interpolan en código Python.
export NOW CALIBRATION_FILE FN_FILE DEGRADATION_FILE
export JC_USER="${USER:-unknown}"

# ── Operation: dispose a finding (AC-4.1: one key per finding) ──
if [[ "$OP" == "dispose" ]]; then
  [[ -z "$DISPOSE_ID" || -z "$DISPOSE_VALUE" ]] && { echo '{"error":"--dispose requiere id y disposicion"}' >&2; exit 1; }
  valid_disps="aceptado descartado-nimiedad descartado-malentendido descartado-inexistente"
  # coincidencia exacta: grep -w aceptaba prefijos como "descartado" (el guion separa palabras)
  disp_ok=0
  for d in $valid_disps; do [[ "$d" == "$DISPOSE_VALUE" ]] && disp_ok=1; done
  if [[ "$disp_ok" -ne 1 ]]; then
    echo "{\"error\":\"disposicion invalida: $DISPOSE_VALUE. Validas: $valid_disps\"}" >&2
    exit 1
  fi
  JC_ID="$DISPOSE_ID" JC_VALUE="$DISPOSE_VALUE" JC_JUDGE="$DISPOSE_JUDGE" python3 - <<'PY'
import json, os
entry = {
    'hallazgo_id': os.environ['JC_ID'],
    'disposicion': os.environ['JC_VALUE'],
    'timestamp': os.environ['NOW'],
    'disposed_by': os.environ['JC_USER'],
}
if os.environ.get('JC_JUDGE'):
    entry['juez'] = os.environ['JC_JUDGE']
path = os.environ['CALIBRATION_FILE']
os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
with open(path, 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
print(json.dumps({'status': 'disposed', 'id': os.environ['JC_ID'], 'value': os.environ['JC_VALUE']}))
PY
  exit $?
fi

# ── Operation: record a false negative (AC-4.4: anti-Goodhart) ──
if [[ "$OP" == "fn-record" ]]; then
  [[ -z "${FN_ID:-}" || -z "${FN_JUDGE:-}" ]] && { echo '{"error":"--fn-record requiere id, juez, y descripcion"}' >&2; exit 1; }
  mkdir -p "$(dirname "$FN_FILE")" 2>/dev/null || true
  JC_ID="$FN_ID" JC_JUDGE="$FN_JUDGE" JC_DESC="${FN_DESC:-}" python3 - <<'PY'
import json, os
entry = {
    'fn_id': os.environ['JC_ID'],
    'juez': os.environ['JC_JUDGE'],
    'descripcion': os.environ['JC_DESC'],
    'timestamp': os.environ['NOW'],
    'recorded_by': os.environ['JC_USER'],
}
path = os.environ['FN_FILE']
os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
with open(path, 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
print(json.dumps({'status': 'fn_recorded', 'id': os.environ['JC_ID'], 'juez': os.environ['JC_JUDGE']}))
PY
  exit $?
fi

# ── Operation: degrade judge to advisor mode (AC-4.3) ──
if [[ "$OP" == "degrade" ]]; then
  [[ -z "${DEGRADE_JUDGE:-}" ]] && { echo '{"error":"--degrade requiere juez y motivo"}' >&2; exit 1; }
  mkdir -p "$(dirname "$DEGRADATION_FILE")" 2>/dev/null || true
  JC_JUDGE="$DEGRADE_JUDGE" JC_REASON="${DEGRADE_REASON:-FP elevado}" python3 - <<'PY'
import json, os
entry = {
    'juez': os.environ['JC_JUDGE'],
    'accion': 'degrade',
    'modo_destino': 'asesor',
    'motivo': os.environ['JC_REASON'],
    'timestamp': os.environ['NOW'],
}
path = os.environ['DEGRADATION_FILE']
os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
with open(path, 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
print(json.dumps({'status': 'degraded', 'juez': os.environ['JC_JUDGE'], 'modo': 'asesor'}))
PY
  exit $?
fi

# ── Operation: restore judge (AC-4.3) ──
if [[ "$OP" == "restore" ]]; then
  [[ -z "${RESTORE_JUDGE:-}" ]] && { echo '{"error":"--restore requiere juez"}' >&2; exit 1; }
  mkdir -p "$(dirname "$DEGRADATION_FILE")" 2>/dev/null || true
  JC_JUDGE="$RESTORE_JUDGE" python3 - <<'PY'
import json, os
entry = {
    'juez': os.environ['JC_JUDGE'],
    'accion': 'restore',
    'modo_destino': 'activo',
    'motivo': 'recalibrado',
    'timestamp': os.environ['NOW'],
}
path = os.environ['DEGRADATION_FILE']
os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
with open(path, 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
print(json.dumps({'status': 'restored', 'juez': os.environ['JC_JUDGE'], 'modo': 'activo'}))
PY
  exit $?
fi

# Carga común de FP/FN para publish y report (el filtro por juez; 'all' = todos)
JC_LOADER='
import json, os, sys
judge = os.environ["JC_JUDGE"]
def load(path):
    out = []
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line: continue
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if e.get("juez") == judge or judge == "all":
                    out.append(e)
    return out
fp_entries = load(os.environ["CALIBRATION_FILE"])
fn_entries = load(os.environ["FN_FILE"])
fp_cats = ["descartado-nimiedad", "descartado-malentendido", "descartado-inexistente"]
fp = sum(1 for e in fp_entries if e.get("disposicion") in fp_cats)
accepted = sum(1 for e in fp_entries if e.get("disposicion") == "aceptado")
'

# ── Operation: publish FP+FN rates (AC-4.5: anti-Goodhart — both together or neither) ──
if [[ "$OP" == "publish" ]]; then
  [[ -z "${PUBLISH_JUDGE:-}" ]] && { echo '{"error":"--publish requiere juez"}' >&2; exit 1; }
  JC_JUDGE="$PUBLISH_JUDGE" python3 -c "$JC_LOADER"'
total = len(fp_entries)
fn_count = len(fn_entries)
# N threshold (AC-4.2: N>=25)
if total < 25:
    print(json.dumps({
        "juez": judge,
        "status": "sin_datos_suficientes",
        "fp_N": total,
        "fn_N": fn_count,
        "message": "Se requieren >=25 disposiciones antes de publicar tasas",
    }, indent=2))
    sys.exit(0)
# Anti-Goodhart gate (AC-4.5): FP se publica con FN; sin FN lleva nota de cold-start
fp_rate = round(fp * 100.0 / total, 1)
print(json.dumps({
    "juez": judge,
    "status": "datos_publicados",
    "fp_N": total,
    "fp_count": fp,
    "fp_rate_pct": fp_rate,
    "aceptados": accepted,
    "fn_N": fn_count,
    "fn_status": "fn_registrados" if fn_count > 0 else "sin_datos_fn",
    "modo_actual": "activo",
    "timestamp": os.environ["NOW"],
    "nota_anti_goodhart": "FP y FN se publican conjuntamente. Si FN no tiene datos, FP se publica igual con nota de cold-start.",
}, indent=2))
' 2>/dev/null
  exit $?
fi

# ── Operation: report FP/FN rates for a judge (legacy) ──
if [[ "$OP" == "report" || -z "$OP" ]]; then
  JC_JUDGE="${REPORT_JUDGE:-all}" python3 -c "$JC_LOADER"'
total = len(fp_entries)
if total == 0:
    print(json.dumps({"juez": judge, "status": "sin_datos", "N": 0, "fn_N": len(fn_entries)}, indent=2))
    sys.exit(0)
if total < 25:
    print(json.dumps({
        "juez": judge,
        "status": "sin_datos",
        "N": total,
        "fn_N": len(fn_entries),
        "message": f"N<25 (actual={total}) — se requieren 25 disposiciones antes de publicar tasa",
    }, indent=2))
    sys.exit(0)
fp_rate = round(fp * 100.0 / total, 1)
print(json.dumps({
    "juez": judge,
    "N": total,
    "aceptados": accepted,
    "falsos_positivos": fp,
    "fp_rate_pct": fp_rate,
    "falsos_negativos": len(fn_entries),
    "fn_status": "registrados" if len(fn_entries) > 0 else "sin_datos_fn",
    "status": "datos_suficientes",
    "timestamp": os.environ["NOW"],
    "nota_anti_goodhart": "FP y FN se publican conjuntamente",
}, indent=2))
' 2>/dev/null
  exit $?
fi

echo "Uso: judge-calibration.sh --report <juez> | --dispose <id> <disp> [juez] | --fn-record <id> <juez> <desc> | --publish <juez>"
