#!/usr/bin/env bash
# =============================================================================
# azdevops-queries.sh — Queries frecuentes de Azure DevOps
# =============================================================================
# Uso: ./scripts/azdevops-queries.sh <comando> [opciones]
# Requiere: az cli con extensión devops, jq
#
# NOTA: Las funciones CRUD (sprint, items, board, update, batch) tienen
# equivalente MCP y los comandos de pm-workspace las usan via MCP tools.
# Este script se mantiene para funciones sin equivalente MCP:
#   - burndown    → Analytics OData (no cubierto por MCP)
#   - capacities  → Work API capacities (no cubierto por MCP)
#   - velocity    → Cálculo híbrido (MCP + OData)
# Ver: docs/rules/domain/mcp-migration.md para detalle de la migración.
# =============================================================================

set -euo pipefail

# ── CONSTANTES (editar según tu entorno) ─────────────────────────────────────
ORG_URL="${AZURE_DEVOPS_ORG_URL:-https://dev.azure.com/MI-ORGANIZACION}"
PAT_FILE="${AZURE_DEVOPS_PAT_FILE:-$HOME/.azure/devops-pat}"
API_VERSION="${AZURE_DEVOPS_API_VERSION:-7.1}"
DEFAULT_PROJECT="${AZURE_DEVOPS_DEFAULT_PROJECT:-ProyectoAlpha}"
DEFAULT_TEAM="${AZURE_DEVOPS_DEFAULT_TEAM:-ProyectoAlpha Team}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# ── HELPERS ───────────────────────────────────────────────────────────────────
log()   { echo "[$(date '+%H:%M:%S')] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

check_dependencies() {
  command -v az >/dev/null 2>&1 || error "az cli no encontrado. Instalar: https://aka.ms/installazurecliwindows"
  command -v jq >/dev/null 2>&1 || error "jq no encontrado. Instalar: apt install jq / brew install jq"
  [[ -f "$PAT_FILE" ]] || error "PAT no encontrado en $PAT_FILE. Crear el fichero con el PAT de Azure DevOps."
}

auth_header() {
  local pat
  pat=$(cat "$PAT_FILE")
  echo "Authorization: Basic $(echo -n ":$pat" | base64)"
}

configure_az() {
  local project="${1:-$DEFAULT_PROJECT}"
  export AZURE_DEVOPS_EXT_PAT
  AZURE_DEVOPS_EXT_PAT=$(cat "$PAT_FILE")
  az devops configure --defaults organization="$ORG_URL" project="$project" --output none
}

# ── FUNCIÓN: Obtener sprint actual ────────────────────────────────────────────
get_current_sprint() {
  local project="${1:-$DEFAULT_PROJECT}"
  local team="${2:-$DEFAULT_TEAM}"
  configure_az "$project"

  log "Obteniendo sprint actual de '$team' en '$project'..."
  az boards iteration team list \
    --project "$project" \
    --team "$team" \
    --timeframe current \
    --output json | jq '.value[0] | {
      id: .id,
      name: .name,
      startDate: (.attributes.startDate | split("T")[0]),
      endDate: (.attributes.finishDate | split("T")[0]),
      path: .path
    }'
}

# ── FUNCIÓN: Items del sprint actual ─────────────────────────────────────────
get_sprint_items() {
  local project="${1:-$DEFAULT_PROJECT}"
  local team="${2:-$DEFAULT_TEAM}"
  configure_az "$project"

  log "Obteniendo work items del sprint actual..."
  # SE-031 slice 3 v2: WIQL vive en .claude/queries/azure-devops/sprint-items-detailed.wiql
  # jq encodea el string en JSON de forma segura (evita escape-hell con backslashes).
  local raw_query wiql
  raw_query=$(bash "$(dirname "${BASH_SOURCE[0]}")/query-lib-resolve.sh" \
    --id sprint-items-detailed \
    --param project="$project" \
    --param team="$team")
  wiql=$(jq -n --arg q "$raw_query" '{query: $q}')

  # Obtener IDs
  local ids
  ids=$(curl -s -X POST \
    "$ORG_URL/$project/_apis/wit/wiql?api-version=$API_VERSION" \
    -H "$(auth_header)" \
    -H "Content-Type: application/json" \
    -d "$wiql" | jq '[.workItems[].id] | join(",")' -r)

  if [[ -z "$ids" ]]; then
    log "No se encontraron work items en el sprint actual."
    echo "[]"
    return
  fi

  # Obtener detalles
  curl -s \
    "$ORG_URL/$project/_apis/wit/workitems?ids=$ids&\$expand=fields&api-version=$API_VERSION" \
    -H "$(auth_header)" | jq '.value[] | {
      id: .id,
      tipo: .fields["System.WorkItemType"],
      titulo: .fields["System.Title"],
      estado: .fields["System.State"],
      asignado: .fields["System.AssignedTo"].displayName,
      sp: .fields["Microsoft.VSTS.Scheduling.StoryPoints"],
      completado_h: .fields["Microsoft.VSTS.Scheduling.CompletedWork"],
      restante_h: .fields["Microsoft.VSTS.Scheduling.RemainingWork"],
      actividad: .fields["Microsoft.VSTS.Common.Activity"]
    }'
}

# ── FUNCIÓN: Calcular burndown ────────────────────────────────────────────────
get_burndown_data() {
  local project="${1:-$DEFAULT_PROJECT}"
  local team="${2:-$DEFAULT_TEAM}"

  log "Calculando datos de burndown..."
  # Obtener sprint info
  local sprint_info
  sprint_info=$(get_current_sprint "$project" "$team")
  local iter_path
  iter_path=$(echo "$sprint_info" | jq -r '.path')

  # Obtener items con remaining work agrupado por día via Analytics OData
  curl -s \
    "$ORG_URL/$project/_odata/v4.0-preview/WorkItemSnapshot?\$filter=IterationPath eq '$iter_path' and WorkItemType ne 'Epic' and WorkItemType ne 'Feature'&\$select=WorkItemId,RemainingWork,DateValue&\$orderby=DateValue asc" \
    -H "$(auth_header)" | jq '[.value[] | {fecha: .DateValue[:10], remaining: .RemainingWork}] | group_by(.fecha) | map({fecha: .[0].fecha, remaining_total: map(.remaining) | add})'
}

# ── FUNCIÓN: Capacidades del equipo ──────────────────────────────────────────
get_team_capacities() {
  local project="${1:-$DEFAULT_PROJECT}"
  local team="${2:-$DEFAULT_TEAM}"
  configure_az "$project"

  log "Obteniendo capacidades del sprint actual..."
  local iter_id
  iter_id=$(az boards iteration team list \
    --project "$project" \
    --team "$team" \
    --timeframe current \
    --output json | jq -r '.value[0].id')

  curl -s \
    "$ORG_URL/$project/$team/_apis/work/teamsettings/iterations/$iter_id/capacities?api-version=$API_VERSION" \
    -H "$(auth_header)" | jq '.value[] | {
      persona: .teamMember.displayName,
      email: .teamMember.uniqueName,
      actividades: .activities,
      dias_off: .daysOff
    }'
}

# ── FUNCIÓN: Velocity histórica ───────────────────────────────────────────────
get_velocity_history() {
  local project="${1:-$DEFAULT_PROJECT}"
  local team="${2:-$DEFAULT_TEAM}"
  local num_sprints="${3:-5}"
  configure_az "$project"

  log "Calculando velocity de los últimos $num_sprints sprints..."
  # Obtener sprints pasados
  az boards iteration team list \
    --project "$project" \
    --team "$team" \
    --output json | jq --argjson n "$num_sprints" \
    '[.value[] | select(.attributes.timeFrame == "past")] | sort_by(.attributes.startDate) | reverse | .[0:$n] | reverse | .[] | {nombre: .name, id: .id, inicio: (.attributes.startDate[:10]), fin: (.attributes.finishDate[:10])}'
}

# ── FUNCIÓN: Status del board (WIP por columna) ───────────────────────────────
get_board_status() {
  local project="${1:-$DEFAULT_PROJECT}"
  local team="${2:-$DEFAULT_TEAM}"
  configure_az "$project"

  log "Obteniendo estado del board..."
  # SE-031 slice 3 v2: WIQL vive en .claude/queries/azure-devops/board-status-not-done.wiql
  local raw_query wiql
  raw_query=$(bash "$(dirname "${BASH_SOURCE[0]}")/query-lib-resolve.sh" \
    --id board-status-not-done \
    --param project="$project" \
    --param team="$team")
  wiql=$(jq -n --arg q "$raw_query" '{query: $q}')

  local ids
  ids=$(curl -s -X POST \
    "$ORG_URL/$project/_apis/wit/wiql?api-version=$API_VERSION" \
    -H "$(auth_header)" \
    -H "Content-Type: application/json" \
    -d "$wiql" | jq '[.workItems[].id] | join(",")' -r)

  if [[ -z "$ids" ]]; then
    echo "No hay items activos en el sprint."
    return
  fi

  curl -s \
    "$ORG_URL/$project/_apis/wit/workitems?ids=$ids&api-version=$API_VERSION" \
    -H "$(auth_header)" | jq '[.value[] | {
      id: .id,
      titulo: .fields["System.Title"],
      estado: .fields["System.State"],
      asignado: .fields["System.AssignedTo"].displayName,
      modificado: .fields["System.ChangedDate"][:10]
    }] | group_by(.estado) | map({estado: .[0].estado, count: length, items: .})'
}

# ── FUNCIÓN: Batch get work items ─────────────────────────────────────────────
batch_get_workitems() {
  # Obtiene detalles de una lista de IDs en lotes de 200
  local project="${1:-$DEFAULT_PROJECT}"
  local ids_file="${2:-/tmp/sprint-ids.json}"

  log "Obteniendo detalles de work items en batch..."
  local ids
  ids=$(cat "$ids_file" | tr '\n' ',')
  local fields="System.Id,System.Title,System.State,System.AssignedTo,System.WorkItemType,Microsoft.VSTS.Scheduling.OriginalEstimate,Microsoft.VSTS.Scheduling.CompletedWork,Microsoft.VSTS.Scheduling.RemainingWork,Microsoft.VSTS.Common.Activity,System.IterationPath"

  curl -s \
    "$ORG_URL/$project/_apis/wit/workitems?ids=${ids%,}&fields=$fields&api-version=$API_VERSION" \
    -H "$(auth_header)" | jq '.value'
}

# ── FUNCIÓN: Actualizar work item ─────────────────────────────────────────────
update_workitem() {
  # Uso: update_workitem <proyecto> <id> <campo> <valor>
  local project="${1:-$DEFAULT_PROJECT}"
  local item_id="$2"
  local field="$3"
  local value="$4"
  configure_az "$project"

  log "Actualizando item $item_id: $field = $value"
  az boards work-item update \
    --id "$item_id" \
    --fields "$field=$value" \
    --output json | jq '{id: .id, campo: "'$field'", nuevoValor: "'$value'"}'
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
main() {
  check_dependencies

  local comando="${1:-help}"
  shift || true

  case "$comando" in
    sprint)         get_current_sprint "$@" ;;
    items)          get_sprint_items "$@" ;;
    burndown)       get_burndown_data "$@" ;;
    capacities)     get_team_capacities "$@" ;;
    velocity)       get_velocity_history "$@" ;;
    board)          get_board_status "$@" ;;
    batch)          batch_get_workitems "$@" ;;
    update)         update_workitem "$@" ;;
    help|*)
      cat <<HELP
Uso: $0 <comando> [proyecto] [equipo] [opciones]

Comandos disponibles:
  sprint       Obtener información del sprint actual
  items        Listar work items del sprint actual con horas
  burndown     Datos de burndown del sprint (requiere Analytics)
  capacities   Capacidades del equipo para el sprint actual
  velocity     Velocity histórica de los últimos N sprints
  board        Estado del board: items por columna/estado
  batch        Obtener detalles de work items en batch (desde fichero de IDs)
  update       Actualizar un campo de un work item

Variables de entorno requeridas:
  AZURE_DEVOPS_ORG_URL      URL de la organización
  AZURE_DEVOPS_PAT_FILE     Ruta al fichero con el PAT
  AZURE_DEVOPS_DEFAULT_PROJECT  Proyecto por defecto
  AZURE_DEVOPS_DEFAULT_TEAM     Equipo por defecto

Ejemplos:
  $0 sprint ProyectoAlpha "ProyectoAlpha Team"
  $0 items ProyectoAlpha
  $0 velocity ProyectoAlpha "ProyectoAlpha Team" 5
  $0 update ProyectoAlpha 1234 "Microsoft.VSTS.Scheduling.RemainingWork" 4
HELP
      ;;
  esac
}

main "$@"
