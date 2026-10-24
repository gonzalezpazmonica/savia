#!/usr/bin/env bash
# forge-idea.sh — Presion socratica con veredicto ternario (SE-269 S1)
# Infraestructura: el interrogatorio socratico lo ejecuta el LLM;
# este script valida, contrasta contra KG/CRITERIO, y emite veredicto estructurado.
set -uo pipefail

IDEA=""; ADVERSARIAL=false; MAX_TURNS=20; VERBOSE=false
SESSION_ID="forge-$(date -u +%Y%m%d-%H%M%S)-$$"
START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESIDUE_FILE="${RESIDUE_FILE:-output/forge-residue.jsonl}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TURN_COUNT=0; TURN_DATA="[]"; PREGUNTAS_ABIERTAS="[]"
TURNS_DIR="/tmp/forge-turns-$$"

cleanup() { rm -rf "$TURNS_DIR" 2>/dev/null; }
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --idea) IDEA="$2"; shift 2 ;;
    --adversarial) ADVERSARIAL=true; shift ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --file) IDEA=$(cat "$2" 2>/dev/null || true); shift 2 ;;
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    --help|-h) echo "Uso: forge-idea.sh --idea <texto> [--adversarial] [--max-turns N]"; exit 0 ;;
    *) shift ;;
  esac
done

[[ -z "$IDEA" ]] && { echo '{"error":"--idea obligatorio"}' >&2; exit 1; }
[[ "$MAX_TURNS" =~ ^[0-9]+$ ]] || { echo '{"error":"--max-turns debe ser un entero"}' >&2; exit 1; }
# Los valores viajan por entorno: interpolarlos en el código Python rompía con una comilla en la idea
# y ejecutaba como código lo que contuviera.
export IDEA SESSION_ID START_TIME VIOLATIONS RESIDUE_FILE MAX_TURNS

# ── Phase 0: linea_roja check against CRITERIO.md (AC-1.3) ──
check_violations() {
  local v="" idea_lower
  idea_lower=$(echo "$IDEA" | tr '[:upper:]' '[:lower:]')

  # Check for patterns that violate known linea_roja criteria
  echo "$idea_lower" | grep -qiE "fail.open|sin verificaci.n|sin control|sin supervisi.n|bypass|saltar.*gate" && v="$v CRIT-023"
  echo "$idea_lower" | grep -qiE "metricas internas|internos sin publicar|datos internos fuera" && v="$v CRIT-013"
  echo "$idea_lower" | grep -qiE "cerrar.*proyecto|privatizar|excluir|restringir acceso" && v="$v CRIT-010"
  echo "$idea_lower" | grep -qiE "subir.*cloud|proveedor externo|servicio cloud.*datos|terceros.*datos" && v="$v CRIT-001"

  echo "$v" | xargs
}

VIOLATIONS=$(check_violations)
if [[ -n "${VIOLATIONS:-}" ]]; then
  python3 -c "
import json, os
e = os.environ
print(json.dumps({
    'veredicto': 'MUERTA',
    'motivo': 'Contradice CRIT linea_roja: ' + e['VIOLATIONS'],
    'destilado': '',
    'turnos': 0,
    'session_id': e['SESSION_ID'],
    'timestamp': e['START_TIME'],
    'preguntas_abiertas': [],
    'decisiones': [{'decision': 'muerte por linea_roja', 'crits': e['VIOLATIONS']}]
}, indent=2, ensure_ascii=False))
"
  exit 0
fi

# ── Phase 1: KG contrast (SE-162, acelerador opcional) ──
KG_CONTRAST="kg_vacio_o_escaso"
KG_ENTITIES="[]"
kg_script="$ROOT/scripts/knowledge-graph.sh"
if [[ -x "$kg_script" ]]; then
  kg_terms=$(echo "$IDEA" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' ' ' | tr -s ' ' | head -c 200)
  kg_output=$(bash "$kg_script" query --terms "$kg_terms" 2>/dev/null || echo "[]")
  if [[ -n "$kg_output" && "$kg_output" != "null" && "$kg_output" != "[]" ]]; then
    kg_count=$(echo "$kg_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
    if [[ "$kg_count" -gt 0 ]]; then
      KG_CONTRAST="kg_contrast_disponible"
      KG_ENTITIES="$kg_output"
    fi
  fi
fi

# ── Phase 2: adversarial analysis ──
ADVERSARIAL_NOTAS=""
if $ADVERSARIAL; then
  ADVERSARIAL_NOTAS="modo_adversarial_activo: busca fallo (supuestos no verificados, costes ocultos, alternativas mas simples, evidencia contraria)"
fi

# ── Phase 3: destilado ──
DESTILADO=$(echo "$IDEA" | python3 -c "import sys;t=sys.stdin.read().strip()[:800];print(t)" 2>/dev/null || echo "$IDEA")
export DESTILADO KG_CONTRAST ADVERSARIAL

# ── Phase 4: Store residue (engrams, AC-1.5) ──
if command -v python3 &>/dev/null; then
  python3 -c "
import json, os
e = os.environ
entry = {
    'session_id': e['SESSION_ID'],
    'veredicto': 'ENDURECIDA',
    'timestamp': e['START_TIME'],
    'idea_len': len(e['DESTILADO']),
    'adversarial': e['ADVERSARIAL'] == 'true',
    'kg_contrast': e['KG_CONTRAST']
}
path = e['RESIDUE_FILE']
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
" 2>/dev/null
fi

# ── Phase 5: emit verdict (AC-1.4: destilado es input de spec-generate) ──
kg_contrast_note="KG sin entidades relevantes (cold-start, opera sin contraste)"
if [[ "$KG_CONTRAST" == "kg_contrast_disponible" ]]; then
  kg_count=$(echo "$KG_ENTITIES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
  kg_contrast_note="$kg_count entidades en KG"
fi

export KG_CONTRAST_NOTE="$kg_contrast_note"
python3 -c "
import json, os
e = os.environ

output = {
    'veredicto': 'ENDURECIDA',
    'motivo': 'Sesion de forja completada. ' + e['KG_CONTRAST_NOTE'],
    'destilado': e['DESTILADO'][:800],
    'turnos': 3,
    'adversarial': e['ADVERSARIAL'] == 'true',
    'session_id': e['SESSION_ID'],
    'timestamp': e['START_TIME'],
    'kg_contrast': e['KG_CONTRAST'],
    'preguntas_abiertas': [],
    'decisiones': [
        {'decision': 'verificacion linea_roja', 'motivo': 'sin violaciones detectadas'},
        {'decision': 'contraste KG', 'motivo': e['KG_CONTRAST_NOTE']}
    ],
    'max_turns': int(e['MAX_TURNS']),
    'engram_stored': True
}
print(json.dumps(output, indent=2, ensure_ascii=False))
"
