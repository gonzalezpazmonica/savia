#!/usr/bin/env bash
# f5-state.sh — SE-387 C/F5: máquina de estados exactly-once para pr.merge.
# Estados: reserved -> submitted (merge solicitado) -> closed (MERGED real).
# Reglas: closed => ALREADY_EXECUTED (exit 3). submitted/reserved => reanudable.
# PR-state real via `gh pr view` (stub-able en tests con PATH).
set -uo pipefail
DIR="${SAVIA_RESERVATIONS:-$HOME/.savia/reservations}"; mkdir -p "$DIR"
CMD="${1:-}"; OP="${2:-pr.merge}"; KEY="${3:-}"; F="$DIR/${OP}__${KEY}.json"

pr_state() { gh pr view "$KEY" --json state -q .state 2>/dev/null || echo ""; }

case "$CMD" in
  reserve)
    if [[ -f "$F" ]]; then
      st=$(jq -r .state "$F")
      if [[ "$st" == "closed" ]]; then echo "ALREADY_EXECUTED: $OP/$KEY closed — no se repite"; exit 3; fi
      # submitted/reserved: reanudar; si el PR ya está MERGED externamente, cerrar
      if [[ "$(pr_state)" == "MERGED" ]]; then "$0" close "$OP" "$KEY" >/dev/null; echo "ALREADY_EXECUTED: PR ya mergeado externamente"; exit 3; fi
      echo "resume: $OP/$KEY (state=$st) — completion permitida exactamente una vez"; exit 0
    fi
    printf '{"op":"%s","key":"%s","state":"reserved","ts":"%s"}\n' "$OP" "$KEY" "$(date -u +%FT%TZ)" > "$F"
    echo "reserved: $OP/$KEY"; exit 0 ;;
  mark_submitted)
    [[ -f "$F" ]] || { echo "FAIL: sin reservation"; exit 1; }
    jq -c '.state="submitted"' "$F" > "$F.tmp" && mv "$F.tmp" "$F"; echo "submitted: $OP/$KEY"; exit 0 ;;
  close)
    [[ -f "$F" ]] || { echo "FAIL: sin reservation"; exit 1; }
    jq -c '.state="closed" | .closed_at=(now|todate)' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
    echo "closed (receipt): $OP/$KEY"; exit 0 ;;
  status)
    [[ -f "$F" ]] && jq -r .state "$F" || echo "none"; exit 0 ;;
  *) echo "uso: f5-state.sh reserve|mark_submitted|close|status [op] [key]"; exit 1 ;;
esac
