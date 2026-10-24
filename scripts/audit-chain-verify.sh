#!/usr/bin/env bash
# audit-chain-verify.sh — SE-275 S1/S4 / SE-313 S6: verificación de integridad.
#
# Escanea output/audit/*.jsonl y verifica para cada cadena:
#   1. prev_hash consistency (cada entrada referencia el entry_hash anterior)
#   2. entry_hash consistency (el hash calculado coincide con el declarado)
#   3. signature HMAC si hay clave local (~/.savia/audit-key) — solo local
#
# Exit codes: 0 todas las cadenas íntegras, 1 alguna corrupta, 2 usage.
set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AUDIT_DIR="${1:-$REPO_ROOT/output/audit}"
KEY_FILE="${SAVIA_AUDIT_KEY:-$HOME/.savia/audit-key}"

[[ -d "$AUDIT_DIR" ]] || { echo "SKIP: no existe $AUDIT_DIR (sin cadenas)"; exit 0; }

HAS_KEY=0
[[ -f "$KEY_FILE" && -s "$KEY_FILE" ]] && HAS_KEY=1

FAILURES=0
FOUND=0

for chain_file in "$AUDIT_DIR"/*.jsonl; do
  [[ -f "$chain_file" ]] || continue
  CHAIN_ID="$(basename "$chain_file" .jsonl)"
  FOUND=$((FOUND + 1))
  PREV_HASH=""
  SEQ_EXPECT=1

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    SEQ_ACTUAL="$(printf '%s' "$line" | jq -r '.seq // empty' 2>/dev/null)"
    [[ -z "$SEQ_ACTUAL" || "$SEQ_ACTUAL" == "null" ]] && { echo "CORRUPT [$CHAIN_ID]: línea sin seq"; FAILURES=$((FAILURES+1)); continue; }
    if [[ "$SEQ_ACTUAL" != "$SEQ_EXPECT" ]]; then
      echo "CORRUPT [$CHAIN_ID]: seq salto (esperado $SEQ_EXPECT, actual $SEQ_ACTUAL)"
      FAILURES=$((FAILURES+1))
    fi
    SEQ_EXPECT=$((SEQ_EXPECT + 1))

    # 1. prev_hash consistency
    PREF="$(printf '%s' "$line" | jq -r '.prev_hash // empty' 2>/dev/null)"
    if [[ -n "$PREV_HASH" ]]; then
      if [[ "$PREF" != "$PREV_HASH" ]]; then
        echo "CORRUPT [$CHAIN_ID]: prev_hash roto en seq $SEQ_ACTUAL (esperado $PREV_HASH, actual $PREF)"
        FAILURES=$((FAILURES+1))
      fi
    fi

    # 2. entry_hash consistency (recalcular sin entry_hash y sin signature)
    #    jq -c añade newline final; el append hashea sin newline (printf '%s').
    CALC="$(printf '%s' "$line" | jq -c 'del(.entry_hash) | del(.signature)' 2>/dev/null | tr -d '\n' | sha256sum | cut -d' ' -f1)"
    DECL="$(printf '%s' "$line" | jq -r '.entry_hash // empty' 2>/dev/null | sed 's/^sha256://')"
    if [[ -z "$DECL" ]]; then
      # Una entrada sin entry_hash permitiría editarla sin dejar rastro.
      echo "CORRUPT [$CHAIN_ID]: entrada sin entry_hash en seq $SEQ_ACTUAL"
      FAILURES=$((FAILURES+1))
    elif [[ "$CALC" != "$DECL" ]]; then
      echo "CORRUPT [$CHAIN_ID]: entry_hash no coincide en seq $SEQ_ACTUAL"
      FAILURES=$((FAILURES+1))
    fi

    # 3. signature HMAC (solo si hay clave local)
    if [[ "$HAS_KEY" -eq 1 ]]; then
      SIG_DECL="$(printf '%s' "$line" | jq -r '.signature // empty' 2>/dev/null | sed 's/^hmac-sha256://')"
      if [[ -n "$SIG_DECL" ]]; then
        SIG_CALC="$(printf '%s' "$line" | jq -c 'del(.signature)' 2>/dev/null | tr -d '\n' | python3 -c "
import hmac, hashlib, sys
key = open('$KEY_FILE','rb').read().strip()
print(hmac.new(key, sys.stdin.read().encode(), hashlib.sha256).hexdigest())
" 2>/dev/null)"
        if [[ -n "$SIG_CALC" && "$SIG_DECL" != "$SIG_CALC" ]]; then
          echo "CORRUPT [$CHAIN_ID]: firma HMAC no coincide en seq $SEQ_ACTUAL"
          FAILURES=$((FAILURES+1))
        fi
      fi
    fi

    PREV_HASH="$(printf '%s' "$line" | jq -r '.entry_hash // empty' 2>/dev/null)"
  done < "$chain_file"
done

if [[ "$FOUND" -eq 0 ]]; then
  echo "OK: sin cadenas de auditoría activas"
  exit 0
fi

if [[ "$FAILURES" -eq 0 ]]; then
  echo "OK: $FOUND cadena(s) íntegra(s)"
  exit 0
else
  echo "FAIL: $FAILURES violación(es) de integridad en $FOUND cadena(s)"
  exit 1
fi
