#!/usr/bin/env bash
# corporate-monotonicity-gate.sh — SE-271 S1
# Compares a candidate corporate body against the constitution and ethical floor.
# Rejects if body tries to relax invariants. Records attempts in ledger.
# Exit 0=clean, exit 1=rejected, exit 2=usage error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONSTITUTION="${CONSTITUTION:-$REPO_ROOT/.claude/CONSTITUCION.md}"
CRITERIO="${CRITERIO:-$REPO_ROOT/CRITERIO.md}"
LEDGER_DIR="${LEDGER_DIR:-$REPO_ROOT/data/corporate}"
LEDGER="${LEDGER:-$LEDGER_DIR/monotonicity-ledger.jsonl}"

# Minúsculas y sin tildes: «excepción», «exceptúa» o «no aplicará» deben contar como «excepcion»,
# «exceptua» y «no aplicara». Sin esto, el texto en español correcto esquivaba las señales.
FOLD_PY='import unicodedata
def fold(t): return "".join(c for c in unicodedata.normalize("NFKD", str(t).lower()) if not unicodedata.combining(c))'

usage() {
  cat <<EOF
Usage: $(basename "$0") <body.card.json>

Compares a candidate corporate criterion body against the constitution
and the ethical floor (CRIT-026, CRIT-027). Rejects if the body attempts
to relax any invariant.

Arguments:
  body.card.json   Path to the corporate body card to validate.

Exit codes:
  0   Body passes monotonicity gate.
  1   Body rejected — attempts to relax invariant.
  2   Usage error (missing arg, file not found, invalid JSON).
EOF
  exit 2
}

# ── helpers ──────────────────────────────────────────────────────────────

log_rejection() {
  local body_id="$1"
  local entry_id="$2"
  local reason="$3"
  local violated="$4"

  mkdir -p "$LEDGER_DIR"

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local body_hash
  body_hash=$(sha256sum "$CANDIDATE" 2>/dev/null | awk '{print $1}' || echo "unknown")

  local prev_hash="genesis"
  if [[ -f "$LEDGER" && -s "$LEDGER" ]]; then
    prev_hash=$(sha256sum "$LEDGER" | awk '{print $1}')
  fi

  # Valores por entorno, no interpolados en el código Python: comillas, barras o saltos de línea
  # en body_id o en el motivo no deben impedir que quede constancia del rechazo.
  B_ID="$body_id" E_ID="$entry_id" REASON="$reason" VIOLATED="$violated" \
  B_HASH="$body_hash" PREV="$prev_hash" TS="$ts" python3 -c "
import json, os
e = os.environ
print(json.dumps({'body_id': e['B_ID'], 'entry_id': e['E_ID'], 'reason': e['REASON'],
                  'violated': e['VIOLATED'], 'body_hash': e['B_HASH'],
                  'prev_ledger_hash': e['PREV'], 'timestamp': e['TS']}, ensure_ascii=False))
" >> "$LEDGER" 2>/dev/null || touch "$LEDGER"
}

# ── gate checks ───────────────────────────────────────────────────────────

check_entry() {
  local entry_json="$1"
  local body_id="$2"
  local idx="$3"
  local has_error=0

  local entry_id dureza principio contraejemplo
  # id normalizado (espacios y mayúsculas): " crit-026" no debe esquivar el suelo ético inmune.
  entry_id=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('id','UNKNOWN')).strip().upper())" 2>/dev/null || echo "UNKNOWN")
  dureza=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('dureza',''))" 2>/dev/null || echo "")
  principio=$(echo "$entry_json" | python3 -c "$FOLD_PY"$'\n'"import json,sys; d=json.load(sys.stdin); print(fold(d.get('principio','')))" 2>/dev/null || echo "")
  contraejemplo=$(echo "$entry_json" | python3 -c "$FOLD_PY"$'\n'"import json,sys; d=json.load(sys.stdin); print(fold(d.get('contraejemplo','')))" 2>/dev/null || echo "")

  echo "  [$idx] $entry_id (dureza=$dureza)"

  # CRIT-026 and CRIT-027 are immune to adoption — any attempt to modify them
  if [[ "$entry_id" =~ ^CRIT-(026|027)$ ]]; then
    log_rejection "$body_id" "$entry_id" \
      "Entry targets immune criterion — ethical floor cannot be adopted, modified, or overridden" \
      "CRIT-026/027 ethical floor (corporate-model.md S4.2)"
    echo "    REJECTED: targets immune ethical floor entry"
    return 1
  fi

  # Check dureza: corporate body entry cannot have lower severity than
  # what the constitution/ethical floor establishes.
  # linea_roja = 3, preferencia = 2, estilo = 1
  local dureza_num
  case "$dureza" in
    linea_roja) dureza_num=3 ;;
    preferencia) dureza_num=2 ;;
    estilo) dureza_num=1 ;;
    *) dureza_num=0 ;;
  esac

  # If entry has existing_dureza, check monotonicity
  local existing_dureza existing_num
  existing_dureza=$(echo "$entry_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('existing_dureza',''))" 2>/dev/null || echo "")
  if [[ -n "$existing_dureza" ]]; then
    case "$existing_dureza" in
      linea_roja) existing_num=3 ;;
      preferencia) existing_num=2 ;;
      estilo) existing_num=1 ;;
      *) existing_num=0 ;;
    esac
    if [[ "$dureza_num" -lt "$existing_num" ]]; then
      log_rejection "$body_id" "$entry_id" \
        "Dureza monotonicity violated: existing=$existing_dureza ($existing_num), proposed=$dureza ($dureza_num)" \
        "Monotonicity invariant S3.1"
      echo "    REJECTED: dureza downgrade ($existing_dureza -> $dureza)"
      return 1
    fi
  fi

  # Check for relaxation signals in principle and contraejemplo
  local combined="$principio $contraejemplo"
  local relaxation_signal=""
  for word in "permit" "permitir" "permitido" "excepcion" "excepcionalmente" "salvo" "excepto"; do
    if echo "$combined" | grep -q "$word"; then
      relaxation_signal="$word"
      break
    fi
  done

  if [[ -n "$relaxation_signal" ]]; then
    # Context check: is the signal creating a loophole?
    local loopsignal
    loopsignal=$(echo "$combined" | python3 -c "
import sys
text = sys.stdin.read()
if any(w in text for w in ['no aplica', 'no aplicara', 'excluye', 'exceptua']):
    print('loophole')
elif any(w in text for w in ['no debe', 'no debe ser', 'esta prohibido', 'nunca']):
    print('safe')
else:
    print('ambiguous')
" 2>/dev/null || echo "ambiguous")

    if [[ "$loopsignal" == "loophole" || "$loopsignal" == "ambiguous" ]]; then
      log_rejection "$body_id" "$entry_id" \
        "Detected relaxation signal '$relaxation_signal' in principle/contraejemplo — context: $loopsignal" \
        "Prohibition ecosystem (CONSTITUCION.md T3, CRIT-026, CRIT-027)"
      echo "    REJECTED: relaxation signal '$relaxation_signal' ($loopsignal)"
      return 1
    fi
  fi

  echo "    OK"
  return 0
}

# ── main ──────────────────────────────────────────────────────────────────

main() {
  if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing body.card.json argument." >&2
    usage
  fi

  CANDIDATE="$1"

  if [[ ! -f "$CANDIDATE" ]]; then
    echo "ERROR: Body card not found: $CANDIDATE" >&2
    exit 2
  fi

  if ! python3 -c "import json; json.load(open('$CANDIDATE')); print('OK')" 2>/dev/null | grep -q OK; then
    echo "ERROR: Body card is not valid JSON: $CANDIDATE" >&2
    exit 2
  fi

  # Estructura: las entradas deben ser una lista de objetos. Antes, un objeto o una lista de cadenas
  # (p. ej. ["CRIT-026"]) se saltaba sin comprobar y el gate daba PASS.
  local shape
  shape=$(python3 -c "
import json, sys
card = json.load(open(sys.argv[1]))
if not isinstance(card, dict): print('card'); sys.exit()
entries = card.get('entries', card.get('criterios', []))
if not isinstance(entries, list): print('entries'); sys.exit()
bad = [i for i, e in enumerate(entries) if not isinstance(e, dict)]
print('entry:%d' % bad[0] if bad else 'ok')
" "$CANDIDATE" 2>/dev/null || echo "error")
  if [[ "$shape" != "ok" ]]; then
    echo "ERROR: Body card has invalid structure ($shape): entries must be a list of objects." >&2
    exit 2
  fi

  local body_id body_version entry_count
  body_id=$(python3 -c "import json; d=json.load(open('$CANDIDATE')); print(d.get('body_id','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  body_version=$(python3 -c "import json; d=json.load(open('$CANDIDATE')); print(d.get('version','0'))" 2>/dev/null || echo "0")
  entry_count=$(python3 -c "
import json
card=json.load(open('$CANDIDATE'))
entries=card.get('entries',card.get('criterios',[]))
print(len(entries))
" 2>/dev/null || echo "0")

  echo "=== Monotonicity Gate ==="
  echo "Body: $body_id v$body_version"
  echo "Candidate: $CANDIDATE"
  echo "Entries: $entry_count"
  echo ""

  if [[ "$entry_count" -eq 0 ]]; then
    echo "RESULT: PASS (no entries to check)"
    exit 0
  fi

  local has_errors=0

  for i in $(seq 0 $((entry_count - 1))); do
    local entry_json
    entry_json=$(python3 -c "
import json
card=json.load(open('$CANDIDATE'))
entries=card.get('entries',card.get('criterios',[]))
if $i < len(entries):
    print(json.dumps(entries[$i],ensure_ascii=False))
" 2>/dev/null)

    if [[ -z "$entry_json" ]]; then
      continue
    fi

    if ! check_entry "$entry_json" "$body_id" "$i"; then
      has_errors=1
    fi
  done

  echo ""
  if [[ "$has_errors" -eq 0 ]]; then
    echo "RESULT: PASS — body respects monotonicity invariants."
    exit 0
  else
    echo "RESULT: REJECTED — body attempts to relax invariants."
    echo "Rejection record: $LEDGER"
    exit 1
  fi
}

main "$@"
