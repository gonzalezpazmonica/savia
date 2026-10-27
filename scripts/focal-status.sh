#!/usr/bin/env bash
[[ -n "${LC_ALL:-}" ]] && { export LANG="$LC_ALL"; unset LC_ALL; }; export LC_NUMERIC=C  # punto decimal fijo (es_ES usa coma); LC_ALL anularía LC_NUMERIC
# focal-status.sh — Vista agregada de nidos activos (SE-230 Slice 1)
# Fuentes: ~/.savia/active-sessions.jsonl (SE-229) + ~/.savia/focal-state/*.json
# Usage: focal-status.sh [--summary]
set -o pipefail
# Note: set -u omitted because bash treats empty associative arrays as unset in some versions

SAVIA_DIR="${HOME}/.savia"
FOCAL_DIR="${SAVIA_DIR}/focal-state"
SESSIONS_FILE="${SAVIA_DIR}/active-sessions.jsonl"

# ── Crear directorio si no existe ─────────────────────────────────────────────
mkdir -p "$FOCAL_DIR"

SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

# ── Helpers: date sin python3, sin jq ────────────────────────────────────────
_now_epoch() { date +%s; }

_iso_to_epoch() {
  local iso="$1"
  # GNU date
  date -d "$iso" +%s 2>/dev/null && return
  # BSD date fallback
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || echo 0
}

_json_field() {
  # Lee un campo del JSON sin jq (opera en JSON plano o multilínea)
  local json="$1" key="$2"
  # Aplanar multilínea
  local flat
  flat=$(printf '%s' "$json" | tr -d '\n' | tr -s ' ')
  local val
  val=$(printf '%s' "$flat" | grep -oP "\"${key}\"\\s*:\\s*\"\\K[^\"]*" 2>/dev/null || true)
  if [[ -z "$val" ]]; then
    val=$(printf '%s' "$flat" | grep -oP "\"${key}\"\\s*:\\s*\\K(true|false|null|[0-9]+)" 2>/dev/null || true)
  fi
  printf '%s' "$val"
}

_json_nested() {
  # Lee next_human_decision.<key>
  local json="$1" key="$2"
  # Aplanar para poder hacer regex en una sola línea
  local flat
  flat=$(printf '%s' "$json" | tr -d '\n' | tr -s ' ')
  local block
  block=$(printf '%s' "$flat" | grep -oP '"next_human_decision"\s*:\s*\{[^}]*\}' 2>/dev/null || true)
  [[ -z "$block" ]] && return
  _json_field "$block" "$key"
}

_truncate() {
  local s="$1" n="${2:-30}"
  if [[ ${#s} -gt $n ]]; then
    printf '%s' "${s:0:$((n-1))}…"
  else
    printf '%s' "$s"
  fi
}

# ── Calcular LOAD para un nido ────────────────────────────────────────────────
_calc_load() {
  local nido="$1"
  local switch_log="${SAVIA_DIR}/.switch-log"
  local now_epoch; now_epoch=$(_now_epoch)
  local hour_ago=$(( now_epoch - 3600 ))

  local switches=0
  if [[ -f "$switch_log" ]]; then
    switches=$(awk -v cutoff="$hour_ago" '
      {
        # Parse ISO8601 timestamp from start of line
        ts_str = substr($0, 1, 20)
        # Remove trailing Z
        gsub("Z","", ts_str); gsub("T"," ", ts_str)
        # El log guarda UTC: sin "UTC" date lo leería en hora local y desplazaría la ventana
        cmd = "date -d \"" ts_str " UTC\" +%s 2>/dev/null"
        cmd | getline ep
        close(cmd)
        if (ep+0 >= cutoff) count++
      }
      END { print count+0 }
    ' "$switch_log" 2>/dev/null || echo 0)
  fi

  if [[ $switches -le 3 ]]; then
    echo "OK"
  elif [[ $switches -le 6 ]]; then
    echo "HIGH"
  else
    echo "OVERLOAD"
  fi
}

# ── Recopilar nidos ───────────────────────────────────────────────────────────
declare -A NIDO_JSON  # nido_name -> raw json
declare -A NIDO_SEEN  # dedup

# Primero desde focal-state/*.json
for f in "${FOCAL_DIR}"/*.json; do
  [[ -f "$f" ]] || continue
  json=$(cat "$f" 2>/dev/null) || continue
  [[ -z "$json" ]] && continue
  name=$(_json_field "$json" "nido")
  [[ -z "$name" ]] && name=$(basename "$f" .json)
  NIDO_JSON["$name"]="$json"
  NIDO_SEEN["$name"]=1
done

# Luego desde active-sessions.jsonl (SE-229) — solo añadir si no está ya en focal-state
if [[ -f "$SESSIONS_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    status_val=$(_json_field "$line" "status")
    [[ "$status_val" != "active" ]] && continue
    nido_val=$(_json_field "$line" "nido")
    [[ -z "$nido_val" ]] && continue
    [[ -n "${NIDO_SEEN[$nido_val]+_}" ]] && continue
    # Crear JSON mínimo para mostrar
    branch_val=$(_json_field "$line" "branch")
    hb_val=$(_json_field "$line" "heartbeat_at")
    minimal="{\"nido\":\"${nido_val}\",\"branch\":\"${branch_val}\",\"status\":\"active\",\"updated_at\":\"${hb_val}\",\"check_in_interval_min\":10}"
    NIDO_JSON["$nido_val"]="$minimal"
    NIDO_SEEN["$nido_val"]=1
  done < "$SESSIONS_FILE"
fi

TOTAL=${#NIDO_JSON[@]}

if [[ $TOTAL -eq 0 ]]; then
  if [[ $SUMMARY_MODE -eq 1 ]]; then
    echo "Focal: sin nidos activos"
  else
    echo "Sin nidos activos"
  fi
  exit 0
fi

now_epoch=$(_now_epoch)

# ── Construir tabla ───────────────────────────────────────────────────────────
ROWS=()
DECISIONS=()
BLOCKING_COUNT=0
URGENT_COUNT=0
NEXT_CHECKIN_NAME=""
NEXT_CHECKIN_MIN=99999

for name in "${!NIDO_JSON[@]}"; do
  json="${NIDO_JSON[$name]}"
  # Validar JSON mínimamente (debe tener al menos un campo)
  if ! printf '%s' "$json" | grep -q '"'; then
    continue
  fi

  branch=$(_json_field "$json" "branch")
  status=$(_json_field "$json" "status")
  [[ -z "$status" ]] && status="active"
  updated_at=$(_json_field "$json" "updated_at")
  interval=$(_json_field "$json" "check_in_interval_min")
  [[ -z "$interval" ]] && interval=10
  [[ "$interval" -le 0 ]] && interval=10

  # STALE check
  display_status="$status"
  if [[ -n "$updated_at" && "$status" != "done" && "$status" != "abandoned" ]]; then
    updated_epoch=$(_iso_to_epoch "$updated_at")
    stale_threshold=$(( interval * 2 * 60 ))
    age=$(( now_epoch - updated_epoch ))
    if [[ $age -gt $stale_threshold ]]; then
      display_status="[STALE]"
    fi
  fi

  # Check-in próximo
  if [[ -n "$updated_at" && "$display_status" != "[STALE]" ]]; then
    updated_epoch=$(_iso_to_epoch "$updated_at")
    next_in=$(( interval * 60 - (now_epoch - updated_epoch) ))
    next_min=$(( next_in / 60 ))
    if [[ $next_min -lt 0 ]]; then next_min=0; fi
    checkin_display="${next_min} min"
    if [[ $next_min -lt $NEXT_CHECKIN_MIN ]]; then
      NEXT_CHECKIN_MIN=$next_min
      NEXT_CHECKIN_NAME="$name"
    fi
  elif [[ "$display_status" == "done" ]]; then
    checkin_display="confirmado"
  else
    checkin_display="[!] $((age / 60)) min"
  fi

  # LOAD
  load=$(_calc_load "$name")

  branch_short=$(_truncate "$branch" 30)
  ROWS+=("$(printf '%-20s %-30s %-10s %-6s %s' "$name" "$branch_short" "$display_status" "$load" "$checkin_display")")

  # Decisiones pendientes
  nhd_block=$(_json_nested "$json" "blocking")
  nhd_urgency=$(_json_nested "$json" "urgency")
  nhd_cost=$(_json_nested "$json" "cognitive_cost")
  nhd_desc=$(_json_nested "$json" "description")
  nhd_type=$(_json_nested "$json" "type")
  nhd_created=$(_json_nested "$json" "created_at")

  if [[ -n "$nhd_desc" && "$display_status" != "[STALE]" ]]; then
    # Calcular age_min
    if [[ -n "$nhd_created" ]]; then
      nhd_epoch=$(_iso_to_epoch "$nhd_created")
      nhd_age_min=$(( (now_epoch - nhd_epoch) / 60 ))
    else
      nhd_age_min=0
    fi
    [[ -z "$nhd_cost" ]] && nhd_cost=2
    [[ -z "$nhd_urgency" ]] && nhd_urgency=0
    blocking_int=0
    [[ "$nhd_block" == "true" ]] && blocking_int=1

    priority=$(awk -v u="${nhd_urgency:-0}" -v b="$blocking_int" -v a="${nhd_age_min:-0}" -v c="${nhd_cost:-2}" \
      'BEGIN { p = (u*3) + (b*5) + (a*0.1) - (c*2); if (p<0) p=0; printf "%.1f", p }')

    label=""
    if [[ "$nhd_block" == "true" ]]; then
      label="[BLOCKING]"
      (( BLOCKING_COUNT++ )) || true
    else
      label="[URGENT]"
      (( URGENT_COUNT++ )) || true
    fi

    DECISIONS+=("${priority} ${name}: ${nhd_desc} ${label} cost:${nhd_cost} age:${nhd_age_min}min")
  fi
done

# ── Summary mode (una línea para banner) ─────────────────────────────────────
if [[ $SUMMARY_MODE -eq 1 ]]; then
  stale_count=0
  for name in "${!NIDO_JSON[@]}"; do
    json="${NIDO_JSON[$name]}"
    updated_at=$(_json_field "$json" "updated_at")
    interval=$(_json_field "$json" "check_in_interval_min")
    [[ -z "$interval" ]] && interval=10
    if [[ -n "$updated_at" ]]; then
      updated_epoch=$(_iso_to_epoch "$updated_at")
      stale_threshold=$(( interval * 2 * 60 ))
      age=$(( now_epoch - updated_epoch ))
      [[ $age -gt $stale_threshold ]] && (( stale_count++ )) || true
    fi
  done
  parts="Focal: ${TOTAL} nidos"
  [[ $BLOCKING_COUNT -gt 0 ]] && parts="${parts} · ${BLOCKING_COUNT} BLOCKING"
  [[ $stale_count -gt 0 ]] && parts="${parts} · ${stale_count} STALE"
  [[ -n "$NEXT_CHECKIN_NAME" ]] && parts="${parts} · próximo: ${NEXT_CHECKIN_NAME} ${NEXT_CHECKIN_MIN}min"
  echo "$parts"
  exit 0
fi

# ── Output completo ───────────────────────────────────────────────────────────
echo "FOCAL STATUS — $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "================================================"
printf '%-20s %-30s %-10s %-6s %s\n' "NIDO" "RAMA" "ESTADO" "LOAD" "CHECK-IN"
printf '%s\n' "$(printf '─%.0s' {1..80})"

for row in "${ROWS[@]}"; do
  echo "$row"
done

echo ""

# Decisiones pendientes ordenadas por prioridad (desc)
ndec=${#DECISIONS[@]}
if [[ $ndec -gt 0 ]]; then
  echo "DECISIONES PENDIENTES ($BLOCKING_COUNT BLOCKING, $URGENT_COUNT URGENT):"
  # Ordenar por prioridad (primer campo)
  sorted=$(printf '%s\n' "${DECISIONS[@]}" | sort -t' ' -k1 -rn)
  idx=1
  while IFS= read -r dec; do
    content="${dec#* }"  # quitar prioridad
    echo "  [$idx] $content"
    (( idx++ )) || true
  done <<< "$sorted"

  if [[ $BLOCKING_COUNT -ge 2 ]]; then
    echo ""
    echo "TRIAGE: ${BLOCKING_COUNT} BLOCKING activos. focal-dispatch.sh para gestionar en orden."
  fi
fi

echo ""
if [[ -n "$NEXT_CHECKIN_NAME" ]]; then
  echo "PROXIMO CHECK-IN: ${NEXT_CHECKIN_NAME} en ${NEXT_CHECKIN_MIN} min"
fi
echo "================================================"

exit 0
