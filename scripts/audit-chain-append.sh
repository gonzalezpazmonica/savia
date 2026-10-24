#!/usr/bin/env bash
# audit-chain-append.sh — SE-275 S1 / SE-313 S6: hash-chained audit trail.
#
# Añade una entrada a una cadena de auditoría con prev_hash encadenado y
# firma HMAC-SHA256 (clave local ~/.savia/audit-key). Modificar cualquier
# entrada invalida todos los prev_hash subsiguientes.
#
# Uso:
#   audit-chain-append.sh <chain_id> <agent> <action> \
#     [--input <file|hash>] [--output <file|hash>] [key=value ...]
#
# Ejemplo:
#   audit-chain-append.sh court-20260809-001 correctness-judge verdict \
#     --input spec.md --output .review.crc severity=blocker
#
# Exit codes: 0 ok, 1 cadena corrupta, 2 usage, 3 sin clave de firma.
set -uo pipefail

CHAIN_ID="${1:-}"
AGENT="${2:-}"
ACTION="${3:-}"
[[ -z "$CHAIN_ID" || -z "$AGENT" || -z "$ACTION" ]] && {
  echo "usage: audit-chain-append.sh <chain_id> <agent> <action> [--input <f>] [--output <f>] [k=v ...]" >&2
  exit 2
}
shift 3

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AUDIT_DIR="$REPO_ROOT/output/audit"
CHAIN_FILE="$AUDIT_DIR/${CHAIN_ID}.jsonl"
mkdir -p "$AUDIT_DIR" 2>/dev/null || true

KEY_FILE="${SAVIA_AUDIT_KEY:-$HOME/.savia/audit-key}"
HAS_KEY=0
[[ -f "$KEY_FILE" && -s "$KEY_FILE" ]] && HAS_KEY=1

INPUT_REF=""; OUTPUT_REF=""
TIER="mid"
ATTRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)  INPUT_REF="$2"; shift 2 ;;
    --output) OUTPUT_REF="$2"; shift 2 ;;
    --tier)   TIER="$2"; shift 2 ;;
    --) shift ;;
    *)
      if [[ "$1" == tier=* ]]; then
        TIER="${1#tier=}"
      else
        ATTRS+=("$1")
      fi
      shift ;;
  esac
done

# ── Hash helpers ──────────────────────────────────────────────────────────────
hash_of() {
  local ref="$1"
  if [[ -f "$ref" ]]; then
    sha256sum "$ref" 2>/dev/null | cut -d' ' -f1
  elif [[ "$ref" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "${ref#sha256:}"
  else
    printf '%s' "$ref" | sha256sum | cut -d' ' -f1
  fi
}

INPUT_HASH=""; [[ -n "$INPUT_REF" ]]  && INPUT_HASH="$(hash_of "$INPUT_REF")"
OUTPUT_HASH=""; [[ -n "$OUTPUT_REF" ]] && OUTPUT_HASH="$(hash_of "$OUTPUT_REF")"

# ── Previous hash (última entrada de la cadena, si existe) ───────────────────
PREV_HASH="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  # sha256 de ""
if [[ -f "$CHAIN_FILE" ]]; then
  LAST="$(tail -n1 "$CHAIN_FILE" 2>/dev/null)"
  if [[ -n "$LAST" ]]; then
    PREV_HASH="$(printf '%s' "$LAST" | jq -r '.entry_hash // empty' 2>/dev/null)"
    # Si la última entrada no tiene entry_hash, la cadena está corrupta.
    if [[ -z "$PREV_HASH" || "$PREV_HASH" == "null" ]]; then
      echo "ERROR: cadena $CHAIN_ID corrupta (última entrada sin entry_hash)" >&2
      exit 1
    fi
  fi
fi

SEQ=1
[[ -f "$CHAIN_FILE" ]] && SEQ=$(($(wc -l < "$CHAIN_FILE") + 1))

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ENTRY_BODY=$(jq -nc \
  --arg chain_id "$CHAIN_ID" --arg seq "$SEQ" --arg prev_hash "$PREV_HASH" \
  --arg agent "$AGENT" --arg tier "$TIER" --arg action "$ACTION" --arg ts "$TS" \
  --arg input_hash "${INPUT_HASH:+sha256:$INPUT_HASH}" --arg output_hash "${OUTPUT_HASH:+sha256:$OUTPUT_HASH}" \
  '{chain_id:$chain_id, seq:($seq|tonumber), prev_hash:$prev_hash, agent:$agent,
    agent_tier:$tier, action:$action, timestamp:$ts,
    input_hash:$input_hash, output_hash:$output_hash}')

# Atributos extra (solo claves alfanuméricas planas)
if [[ ${#ATTRS[@]} -gt 0 ]]; then
  EXTRA="{}"
  for kv in "${ATTRS[@]}"; do
    K="${kv%%=*}"; V="${kv#*=}"
    case "$K" in
      tier|chain_id|seq|prev_hash|agent|action|timestamp|input_hash|output_hash|entry_hash|signature) continue ;;
    esac
    EXTRA="$(jq -c --arg k "$K" --arg v "$V" '.[$k]=$v' <<< "$EXTRA")"
  done
  ENTRY_BODY="$(jq -c '. * '"$EXTRA"'' <<< "$ENTRY_BODY")"
fi

# ── entry_hash: hash de todo el cuerpo (encadena) ────────────────────────────
ENTRY_HASH="$(printf '%s' "$ENTRY_BODY" | sha256sum | cut -d' ' -f1)"
ENTRY_BODY="$(jq -c --arg eh "sha256:$ENTRY_HASH" '. + {entry_hash:$eh}' <<< "$ENTRY_BODY")"

# ── Firma HMAC-SHA256 (opcional, local) ──────────────────────────────────────
SIG=""
if [[ "$HAS_KEY" -eq 1 ]]; then
  SIG="$(printf '%s' "$ENTRY_BODY" | python3 -c "
import hmac, hashlib, sys
key = open('$KEY_FILE','rb').read().strip()
body = sys.stdin.read().encode()
print(hmac.new(key, body, hashlib.sha256).hexdigest())
" 2>/dev/null)"
  [[ -n "$SIG" ]] && ENTRY_BODY="$(jq -c --arg s "hmac-sha256:$SIG" '. + {signature:$s}' <<< "$ENTRY_BODY")"
fi

printf '%s\n' "$ENTRY_BODY" >> "$CHAIN_FILE"
echo "$CHAIN_FILE"
exit 0
