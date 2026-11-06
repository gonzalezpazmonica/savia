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

mkdir -p "$FOCAL_DIR" || { echo "ERROR: no se pudo crear el directorio focal" >&2; exit 1; }

# ── Parse args ────────────────────────────────────────────────────────────────
NIDO=""
SET_INTERVAL=""
SHOW_LOAD=0
OVERRIDE_LOAD=0
INTERVAL_SET=0

_die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nido)
      [[ $# -ge 2 && -n "$2" ]] || _die "--nido requiere un valor"
      NIDO="$2"; shift 2 ;;
    --set-interval)
      [[ $# -ge 2 ]] || _die "--set-interval requiere un valor"
      SET_INTERVAL="$2"; INTERVAL_SET=1; shift 2 ;;
    --load)           SHOW_LOAD=1;       shift ;;
    --override-load)  OVERRIDE_LOAD=1;   shift ;;
    *)                _die "opción desconocida: $1" ;;
  esac
done

if [[ -n "$NIDO" ]]; then
  [[ "$NIDO" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]] || _die "nombre de nido no válido"
fi
if [[ $INTERVAL_SET -eq 1 ]]; then
  [[ "$SET_INTERVAL" =~ ^[1-9][0-9]{0,3}$ ]] || _die "el intervalo debe ser un entero entre 1 y 9999"
  [[ -n "$NIDO" ]] || _die "--set-interval requiere --nido"
fi

_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_now_epoch() { date +%s; }

_json_field() {
  local json="$1" key="$2"
  local val
  val=$(printf '%s' "$json" | grep -oP "\"${key}\"\\s*:\\s*\"\\K[^\"]*" 2>/dev/null || true)
  if [[ -z "$val" ]]; then
    val=$(printf '%s' "$json" | grep -oP "\"${key}\"\\s*:\\s*\\K(true|false|null|[0-9]+)" 2>/dev/null || true)
  fi
  printf '%s' "$val"
}

_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

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
      [[ $ep -ge $hour_ago && $ep -le $now_epoch ]] && (( switches++ )) || true
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

# Campos escalares del esquema focal: actualizar cada uno independientemente.
# Para insertar, quitar solo la última llave del objeto, no las llaves anidadas.
_set_field() {
  local key="$1" value="$2" pattern="$3" body
  if printf '%s' "$new_json" | grep -q "\"${key}\"[[:space:]]*:"; then
    printf '%s' "$new_json" | grep -qE "\"${key}\"[[:space:]]*:[[:space:]]*${pattern}[[:space:]]*([,}]|$)" || return 1
    new_json=$(printf '%s' "$new_json" | sed -E "s/\"${key}\"[[:space:]]*:[[:space:]]*${pattern}/\"${key}\": ${value}/") || return 1
  else
    [[ "$new_json" =~ ^[[:space:]]*\{(.*)\}[[:space:]]*$ ]] || return 1
    body="${BASH_REMATCH[1]}"
    if [[ "$body" =~ ^[[:space:]]*$ ]]; then
      new_json="{\"${key}\": ${value}}"
    else
      new_json="{${body},\"${key}\": ${value}}"
    fi
  fi
}

# ── Escritura serializada: leer y modificar bajo el mismo lock ─────────────────
if [[ -n "$NIDO" ]]; then
  STATE_FILE="${FOCAL_DIR}/${NIDO}.json"
  now=$(_now_iso)
  pid_val=$$
  (
    flock -w 5 200 || { echo "ERROR: flock timeout" >&2; exit 1; }
    new_json="{\"nido\":\"$NIDO\"}"
    if [[ -e "$STATE_FILE" ]]; then
      [[ -f "$STATE_FILE" ]] || _die "el estado focal no es un fichero"
      new_json=$(cat "$STATE_FILE") || _die "no se pudo leer el estado focal"
    fi
    _set_field updated_at "\"$now\"" '\"[^\"]*\"' || _die "no se pudo actualizar la fecha"
    if [[ $INTERVAL_SET -eq 1 ]]; then
      _set_field check_in_interval_min "$SET_INTERVAL" '[0-9]+' || _die "no se pudo actualizar el intervalo"
    else
      _set_field session_pid "$pid_val" '[0-9]+' || _die "no se pudo actualizar el pid"
    fi
    printf '%s\n' "$new_json" > "$STATE_FILE" || _die "no se pudo escribir el estado focal"
  ) 200>"$LOCK_FILE" || exit 1

  if [[ $INTERVAL_SET -eq 1 ]]; then
    echo "check_in_interval_min actualizado a ${SET_INTERVAL} para ${NIDO}"
  else
    echo "Check-in registrado para ${NIDO} — ${now}"
  fi
  exit 0
fi

echo "ERROR: especifica --nido <name>, --set-interval <n> --nido <name>, o --load" >&2
exit 1
