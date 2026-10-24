#!/usr/bin/env bash
# f5-state.sh — SE-387 C/F5: máquina de estados exactly-once para pr.merge.
# Estados: reserved -> submitted (merge solicitado) -> closed (MERGED real); release borra una reserva no consumada.
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
      real=$(pr_state)
      if [[ "$real" == "MERGED" ]]; then
        "$0" close "$OP" "$KEY" >/dev/null 2>&1
        echo "ALREADY_EXECUTED: efecto ya consumado (PR MERGED, receipt cerrado)"; exit 3
      fi
      if [[ "$st" == "submitted" && "$real" != "MERGED" ]]; then
        echo "resume: $OP/$KEY submitted y PR aún ${real:-pendiente} — NO se solicita otro efecto"
        exit 0
      fi
      echo "resume: $OP/$KEY (state=$st) — completion permitida exactamente una vez"; exit 0
    fi
    printf '{"op":"%s","key":"%s","state":"reserved","ts":"%s"}\n' "$OP" "$KEY" "$(date -u +%FT%TZ)" > "$F"
    echo "reserved: $OP/$KEY"; exit 0 ;;
  mark_submitted)
    [[ -f "$F" ]] || { echo "FAIL: sin reservation"; exit 1; }
    jq -c '.state="submitted"' "$F" > "$F.tmp" && mv "$F.tmp" "$F"; echo "submitted: $OP/$KEY"; exit 0 ;;
  close)
    [[ -f "$F" ]] || { echo "FAIL: sin reservation"; exit 1; }
    # SE-387 B (revisión operadora): close IMPOSIBLE si el estado remoto real no es MERGED.
    real=$(pr_state)
    if [[ "$real" != "MERGED" ]]; then
      echo "BLOCK: close de $OP/$KEY denegado — PR real=${real:-desconocido} (requerido: MERGED)"; exit 2
    fi
    jq -c '.state="closed" | .closed_at=(now|todate)' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
    echo "closed (receipt): $OP/$KEY"; exit 0 ;;
  release)
    # Efecto rechazado (p. ej. GitHub no aceptó el merge): la reserva se borra para que un merge
    # posterior ajeno no se tome por propio. Nunca sobre closed ni si el PR real ya está MERGED.
    [[ -f "$F" ]] || { echo "none: $OP/$KEY"; exit 0; }
    [[ "$(jq -r .state "$F")" == "closed" ]] && { echo "BLOCK: $OP/$KEY closed — no se libera"; exit 2; }
    [[ "$(pr_state)" == "MERGED" ]] && { echo "BLOCK: $OP/$KEY con PR MERGED — no se libera"; exit 2; }
    rm -f "$F"; echo "released: $OP/$KEY"; exit 0 ;;
  status)
    [[ -f "$F" ]] && jq -r .state "$F" || echo "none"; exit 0 ;;
  *) echo "uso: f5-state.sh reserve|mark_submitted|close|release|status [op] [key]"; exit 1 ;;
esac
