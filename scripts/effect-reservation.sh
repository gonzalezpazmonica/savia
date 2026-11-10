#!/usr/bin/env bash
# SE-387 C/F5 — Exactly-once effects: intent -> reservation -> gate -> execute -> receipt -> close.
# Uso: effect-reservation.sh reserve <op> <idempotency_key> | close <op> <key> | status <op> <key>
set -uo pipefail
CMD="${1:-}"; OP="${2:-}"; KEY="${3:-}"
# SE-493 S1: contrato deprecado (H1). Ninguna op distinta de pr.merge puede reutilizarlo.
case "$CMD" in reserve|close|status)
  if [[ "$OP" != "pr.merge" ]]; then echo "BLOCK: op '$OP' no admitida en effect-reservation.sh (solo pr.merge; SE-493)" >&2; exit 2; fi ;;
esac
DIR="${SAVIA_RESERVATIONS:-$HOME/.savia/reservations}"; mkdir -p "$DIR"
F="$DIR/${OP}__${KEY}.json"
case "$CMD" in
  reserve)
    if [[ -f "$F" ]]; then
      st=$(jq -r .state "$F")
      if [[ "$st" == "closed" ]]; then
        echo "ALREADY_EXECUTED: efecto $OP/$KEY en estado $st — no se repite"; exit 3
      fi
      echo "reservation: $OP/$KEY (resume tras crash, estado=$st) — effect exactly-once"
      exit 0
    fi
    printf '{"op":"%s","key":"%s","state":"reserved","ts":"%s"}\n' "$OP" "$KEY" "$(date -u +%FT%TZ)" > "$F"
    echo "reservation: $OP/$KEY (reserved)";;
  close)
    jq -c --arg st closed --arg ts "$(date -u +%FT%TZ)" '.state=$st | .closed_at=$ts' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
    echo "receipt: $OP/$KEY closed";;
  status) jq -r .state "$F" 2>/dev/null || echo "none";;
  *) echo "uso: reserve|close|status <op> <key>"; exit 1;;
esac
