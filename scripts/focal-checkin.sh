#!/usr/bin/env bash
# focal-checkin.sh — Check-in scheduling y señal de carga cognitiva (SE-230 Slice 3)
# Usage: focal-checkin.sh --nido <name>          — actualiza updated_at y session_pid
#        focal-checkin.sh --set-interval <n> --nido <name>  — actualiza check_in_interval_min
#        focal-checkin.sh --load                 — muestra señal LOAD
# Sin dependencias externas: solo bash + awk + date
set -uo pipefail

SAVIA_DIR="${HOME}/.savia"
FOCAL_DIR="${SAVIA_DIR}/focal-state"
SWITCH_LOG="${SAVIA_DIR}/.switch-log"
LOCK_FILE="${SAVIA_DIR}/focal-state.lock"

mkdir -p "$FOCAL_DIR"

# ── Parse args ────────────────────────────────────────────────────────────────
NIDO=""
SET_INTERVAL=""
SHOW_LOAD=0
OVERRIDE_LOAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nido)           NIDO="$2";         shift 2 ;;
    --set-interval)   SET_INTERVAL="$2"; shift 2 ;;
    --load)           SHOW_LOAD=1;       shift ;;
    --override-load)  OVERRIDE_LOAD=1;   shift ;;
    *)                shift ;;
  esac
done

_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_now_epoch() { date +%s; }

_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# S03n: el nombre del nido es un nombre de fichero dentro de focal-state (sin «/» ni «..»: antes
# `--nido ../../x` escribía fuera) y el intervalo un entero positivo (antes `x/` rompía el sed,
# dejaba el estado vacío y salía 0).
if [[ -n "$NIDO" && ! "$NIDO" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
  echo "ERROR: nombre de nido no válido: ${NIDO}" >&2
  exit 1
fi
if [[ -n "$SET_INTERVAL" && ! "$SET_INTERVAL" =~ ^[1-9][0-9]{0,3}$ ]]; then
  echo "ERROR: --set-interval requiere un entero entre 1 y 9999: ${SET_INTERVAL}" >&2
  exit 1
fi

# ── --load ────────────────────────────────────────────────────────────────────
if [[ $SHOW_LOAD -eq 1 ]]; then
  now_epoch=$(_now_epoch)
  hour_ago=$(( now_epoch - 3600 ))

  switches=0
  if [[ -f "$SWITCH_LOG" ]]; then
    # Contar entradas con timestamp en la última hora — bash puro sin subproceso en loop
    # Formato: 2026-06-27T21:34:00Z nidoA→nidoB
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ts_str="${line%% *}"
      # Normalizar ISO8601 para date -d (forzar UTC)
      ts_normalized="${ts_str//T/ }"
      ts_normalized="${ts_normalized%Z} UTC"
      ep=$(date -d "$ts_normalized" +%s 2>/dev/null || echo 0)
      [[ $ep -ge $hour_ago ]] && (( switches++ )) || true
    done < "$SWITCH_LOG"
  fi

  # Contar decisiones pendientes (nidos con next_human_decision no null)
  pending_decisions=0
  for f in "${FOCAL_DIR}"/*.json; do
    [[ -f "$f" ]] || continue
    json=$(cat "$f" 2>/dev/null) || continue
    [[ -z "$json" ]] && continue
    # Check si next_human_decision es null
    flat=$(printf '%s' "$json" | tr -d '\n' | tr -s ' ')
    nhd_null=$(printf '%s' "$flat" | grep -oP '"next_human_decision"\s*:\s*null' 2>/dev/null || true)
    [[ -n "$nhd_null" ]] && continue
    # Tiene next_human_decision con contenido
    nhd_desc=$(printf '%s' "$flat" | grep -oP '"next_human_decision"\s*:\s*\{[^}]*\}' 2>/dev/null || true)
    [[ -n "$nhd_desc" ]] && (( pending_decisions++ )) || true
  done

  # OVERLOAD: >6 switches/hora O >5 decisiones pendientes
  # HIGH: 3-5 switches/hora O 3-5 decisiones pendientes
  # OK: <=2 switches/hora Y <3 decisiones

  # El spec dice:
  # OK: cambios/hora ≤ 3 Y decisiones BLOCKING pendientes ≤ 1
  # HIGH: cambios/hora 4-6 O decisiones BLOCKING pendientes 2-3
  # OVERLOAD: cambios/hora > 6 O decisiones BLOCKING pendientes ≥ 4

  # Los tests piden: OK=0-2, HIGH=3-5 (4 switches→HIGH per test 6), OVERLOAD=6+ switches
  # Adaptamos a lo que especifica el prompt de implementación:
  # OK: 0-2 switches/hora, <3 decisiones
  # HIGH: 3-5 switches O 3-5 decisiones
  # OVERLOAD: >5 switches O >5 decisiones

  load="OK"
  if [[ $switches -gt 5 || $pending_decisions -gt 5 ]]; then
    load="OVERLOAD"
  elif [[ $switches -ge 3 || $pending_decisions -ge 3 ]]; then
    load="HIGH"
  fi

  echo "$load"
  exit 0
fi

# ── --set-interval + --nido ────────────────────────────────────────────────────
if [[ -n "$SET_INTERVAL" ]]; then
  if [[ -z "$NIDO" ]]; then
    echo "ERROR: --set-interval requiere --nido" >&2
    exit 1
  fi
  STATE_FILE="${FOCAL_DIR}/${NIDO}.json"

  existing_json="{}"
  if [[ -f "$STATE_FILE" ]]; then
    existing_json=$(cat "$STATE_FILE" 2>/dev/null) || existing_json="{}"
  fi

  # Actualizar check_in_interval_min en el JSON
  # Método: reconstruir con sed
  now=$(_now_iso)
  if printf '%s' "$existing_json" | grep -q '"check_in_interval_min"'; then
    new_json=$(printf '%s' "$existing_json" | sed "s/\"check_in_interval_min\":[[:space:]]*[0-9]*/\"check_in_interval_min\": ${SET_INTERVAL}/")
    new_json=$(printf '%s' "$new_json" | sed "s/\"updated_at\":[[:space:]]*\"[^\"]*\"/\"updated_at\": \"${now}\"/" )
  else
    # Insertar antes del cierre
    new_json=$(printf '%s' "$existing_json" | sed "s/}$/,\"check_in_interval_min\": ${SET_INTERVAL},\"updated_at\": \"${now}\"}/")
  fi

  (
    flock -w 5 200 || { echo "ERROR: flock timeout" >&2; exit 1; }
    printf '%s\n' "$new_json" > "$STATE_FILE"
  ) 200>"$LOCK_FILE" || exit 1  # el exit del subshell no sale del script: sin esto se informaba éxito

  echo "check_in_interval_min actualizado a ${SET_INTERVAL} para ${NIDO}"
  exit 0
fi

# ── --nido (heartbeat) ────────────────────────────────────────────────────────
if [[ -n "$NIDO" ]]; then
  STATE_FILE="${FOCAL_DIR}/${NIDO}.json"

  existing_json="{}"
  if [[ -f "$STATE_FILE" ]]; then
    existing_json=$(cat "$STATE_FILE" 2>/dev/null) || existing_json="{}"
  fi

  now=$(_now_iso)
  pid_val=$$

  if printf '%s' "$existing_json" | grep -q '"updated_at"'; then
    new_json=$(printf '%s' "$existing_json" | \
      sed "s/\"updated_at\":[[:space:]]*\"[^\"]*\"/\"updated_at\": \"${now}\"/" | \
      sed "s/\"session_pid\":[[:space:]]*[0-9]*/\"session_pid\": ${pid_val}/")
  elif printf '%s' "$existing_json" | grep -q '"nido"'; then
    new_json=$(printf '%s' "$existing_json" | sed "s/}$/,\"updated_at\": \"${now}\",\"session_pid\": ${pid_val}}/")
  else
    new_json="{\"nido\":\"$(_esc "$NIDO")\",\"updated_at\":\"${now}\",\"session_pid\":${pid_val}}"
  fi

  (
    flock -w 5 200 || { echo "ERROR: flock timeout" >&2; exit 1; }
    printf '%s\n' "$new_json" > "$STATE_FILE"
  ) 200>"$LOCK_FILE" || exit 1

  echo "Check-in registrado para ${NIDO} — ${now}"
  exit 0
fi

echo "ERROR: especifica --nido <name>, --set-interval <n> --nido <name>, o --load" >&2
exit 1
