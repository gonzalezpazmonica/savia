#!/usr/bin/env bash
# learning-divergence.sh — SCL-004 L1: divergencia grafo-modelo como instrumento
# del bucle de aprendizaje.
#
# Mide la distancia entre lo que la cúpula SaviaLearning/Grafos de SaviaVaults
# AFIRMA sobre un tema y lo que el modelo DECLARÓ en su output. Divergencia alta
# → el modelo contradice/ignora el conocimiento persistido → propuesta de
# revisión (trigger divergence).
#
# Implementación determinista: extrae términos significativos (>=4 chars,
# sin stopwords) de ambos lados y computa la divergencia como
#   1 − (términos_intersectan / términos_grafo)
# 0 = modelo alineado con el grafo; 1 = modelo ignora el grafo.
#
# Usage:
#   learning-divergence.sh --claim "<declaracion del modelo>"
#     [--graph-text <texto del grafo>] [--graph-query <query para buscar en cupula>]
#     [--threshold <0-1>] [--propose] [--output-dir <dir>] [--json]
#
# Exit codes: 0 divergencia <= threshold, 1 divergencia > threshold (disparo),
#             2 usage
#
# Ref: docs/specs/SCL-004-labs-instrumentos.spec.md
# PURE_BASH — sin bindings de frontend.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAIM=""
GRAPH_TEXT=""
GRAPH_QUERY=""
THRESHOLD="${SCL_DIVERGENCE_THRESHOLD:-0.6}"
PROPOSE=false
JSON=false
OUTPUT_DIR="${SCL_PROPOSALS_DIR:-$ROOT/docs/learning-proposals}"
VAULT="${SCL_VAULT_DIR:-$ROOT/vaults/SaviaLearning}"

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claim) CLAIM="$2"; shift 2 ;;
    --graph-text) GRAPH_TEXT="$2"; shift 2 ;;
    --graph-query) GRAPH_QUERY="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --propose) PROPOSE=true; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --vault) VAULT="$2"; shift 2 ;;
    --json) JSON=true; shift ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

[[ -z "$CLAIM" ]] && usage

# ── Get graph text: from --graph-text, or search the dome ──
if [[ -z "$GRAPH_TEXT" && -n "$GRAPH_QUERY" ]]; then
  # Search the dome (BM25) and concat snippets as "what the graph affirms"
  GRAPH_TEXT=$(bash "$SCRIPT_DIR/learning-recall.sh" --query "$GRAPH_QUERY" --top 5 --min-score 1 --json 2>/dev/null \
    | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(' '.join(h.get('snippet','') for h in d.get('hits',[])))
except Exception:
    print('')" 2>/dev/null || echo "")
fi

# ── Compute divergence (deterministic) ──
DIVERGENCE=$(CLAIM="$CLAIM" GRAPH="$GRAPH_TEXT" python3 - <<'PY'
import os, re, sys

def tokens(text):
    # términos significativos: alfanuméricos >= 4 chars, minúsculas
    words = re.findall(r'[a-z0-9]{4,}', text.lower())
    stop = {'para','como','con','los','las','que','esta','este','esto','una','uno','del','por','una','cada','para','muy','solo','mas','menos','sobre','entre','tiene','debe','para'}
    return set(w for w in words if w not in stop)

claim_toks = tokens(os.environ.get('CLAIM',''))
graph_toks = tokens(os.environ.get('GRAPH',''))

if not graph_toks:
    print("1.0000")  # sin conocimiento en el grafo → divergencia máxima
elif not claim_toks:
    print("1.0000")
else:
    overlap = len(claim_toks & graph_toks)
    d = 1 - (overlap / len(graph_toks))
    print(f"{d:.4f}")
PY
)

# Clamp + compare
DIVERGENCE_NUM=$(awk -v d="$DIVERGENCE" 'BEGIN{ if (d<0) print 0; else if (d>1) print 1; else print d }')
TRIGGERED=false
if awk -v d="$DIVERGENCE_NUM" -v t="$THRESHOLD" 'BEGIN{exit !(d>t)}'; then
  TRIGGERED=true
fi

# ── Optionally propose a review (trigger divergence) ──
if $PROPOSE && $TRIGGERED; then
  PROP="$SCRIPT_DIR/learning-proposal.sh"
  if [[ -f "$PROP" ]]; then
    EVIDENCE_REF=""
    if [[ -n "$GRAPH_QUERY" ]]; then
      EVIDENCE_REF="$ROOT/vaults/SaviaLearning/learning"
    fi
    TS=$(date -u +%Y%m%d%H%M%S)
    echo "divergence-evidence" > "$OUTPUT_DIR/.divergence-$TS.ev"
    bash "$PROP" \
      --origin "Labs L1: divergencia grafo-modelo $DIVERGENCE_NUM > umbral $THRESHOLD" \
      --evidence "$OUTPUT_DIR/.divergence-$TS.ev" \
      --diagnosis "el modelo declaro algo que el grafo no respalda o contradice" \
      --change "revisar alineacion modelo-grafo" \
      --target criterio --trigger divergence \
      --output-dir "$OUTPUT_DIR" --graph-index "$ROOT/output/learning-loop/graph-index.jsonl" \
      >/dev/null 2>&1 || true
    rm -f "$OUTPUT_DIR/.divergence-$TS.ev"
  fi
fi

if $JSON; then
  printf '{"divergence":%s,"threshold":%s,"triggered":%s}\n' "$DIVERGENCE_NUM" "$THRESHOLD" "$TRIGGERED"
else
  echo "divergencia grafo-modelo: $DIVERGENCE_NUM (umbral $THRESHOLD)"
  if $TRIGGERED; then echo "veredicto: DIVERGENCIA (revisar alineacion)"; else echo "veredicto: ALINEADO"; fi
fi

[[ "$TRIGGERED" == "false" ]]
