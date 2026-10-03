#!/usr/bin/env bash
set -uo pipefail

# legalize-es.sh — Gestión del corpus legislativo español (legalize-es)
# Funciones: install, update, status, search, search-article, history, check-status
#
# Exit codes:
#   0 resultado encontrado / operación correcta
#   1 sin resultados, norma o artículo inexistente, fallo de git
#   2 uso o argumento inválido (término vacío, ámbito o identificador no válidos)
#   3 corpus no disponible (sin fuente no se puede evaluar cumplimiento)

LEGALIZE_ES_DEFAULT_PATH="${LEGALIZE_ES_PATH:-$HOME/.savia/legalize-es}"
LEGALIZE_ES_REPO="https://github.com/legalize-dev/legalize-es.git"
SEARCH_LIMIT=20

usage() {
  cat <<'EOF'
Uso: legalize-es.sh <comando> [opciones]

Comandos:
  install              Clonar legalize-es en $LEGALIZE_ES_PATH
  update               Actualizar legislación (git pull)
  status               Mostrar estado del corpus
  search <término> [es|es-{ccaa}]
                       Buscar el término literal en normas vigentes,
                       ordenadas por rango (máximo 20)
  search-article <BOE-ID> <artículo>
                       Extraer un artículo ("Artículo 13", "13", "13 bis")
                       o un encabezado ("Disposición adicional primera")
  history <BOE-ID>     Historial de reformas de una norma
  check-status <BOE-ID> Verificar si una norma está vigente o derogada

Exit codes: 0 encontrado · 1 sin resultados/no encontrado · 2 uso inválido
            3 corpus no disponible

Variables de entorno:
  LEGALIZE_ES_PATH     Ruta del corpus (default: ~/.savia/legalize-es)
EOF
}

err() { echo "ERROR: $*" >&2; }

# El corpus existe si hay normas estatales en es/.
require_corpus() {
  if [[ ! -d "$LEGALIZE_ES_DEFAULT_PATH/es" ]]; then
    err "legalize-es no instalado en $LEGALIZE_ES_DEFAULT_PATH (falta es/)."
    err "Sin corpus no hay fuente: no se puede afirmar cumplimiento."
    err "Instalar con: bash scripts/legalize-es.sh install"
    exit 3
  fi
}

# Identificadores tipo BOE-A-2018-16673: sin comodines, barras ni puntos.
validate_id() {
  local id="$1"
  if [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
    err "Identificador no válido: '$id' (esperado p. ej. BOE-A-2018-16673)"
    exit 2
  fi
}

find_norm() {
  find "$LEGALIZE_ES_DEFAULT_PATH" -path "$LEGALIZE_ES_DEFAULT_PATH/.git" -prune \
    -o -type f -name "$1.md" -print 2>/dev/null | head -1
}

# Valor de un campo del frontmatter YAML (solo entre los delimitadores ---).
fm_field() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
      if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      print v; exit
    }' "$file" 2>/dev/null
}

# Prioridad por rango normativo (menor = mayor rango).
rank_priority() {
  case "$1" in
    constitucion) echo 1 ;;
    ley_organica) echo 2 ;;
    ley) echo 3 ;;
    real_decreto_ley|real_decreto_legislativo) echo 4 ;;
    real_decreto) echo 5 ;;
    orden) echo 6 ;;
    resolucion) echo 7 ;;
    *) echo 9 ;;
  esac
}

cmd_install() {
  if [[ -d "$LEGALIZE_ES_DEFAULT_PATH/.git" ]]; then
    echo "legalize-es ya instalado en $LEGALIZE_ES_DEFAULT_PATH"
    echo "   Usa 'legalize-es.sh update' para actualizar."
    return 0
  fi

  echo "Clonando legalize-es (solo último commit)..."
  mkdir -p "$(dirname "$LEGALIZE_ES_DEFAULT_PATH")"
  if git clone --depth=1 "$LEGALIZE_ES_REPO" "$LEGALIZE_ES_DEFAULT_PATH" 2>&1; then
    local count
    count=$(find "$LEGALIZE_ES_DEFAULT_PATH/es" -name "*.md" 2>/dev/null | wc -l)
    echo "Instalado: $count normas estatales disponibles"
  else
    err "Error al clonar. Verifica conexión a internet."
    return 1
  fi
}

cmd_update() {
  if [[ ! -d "$LEGALIZE_ES_DEFAULT_PATH/.git" ]]; then
    err "legalize-es no instalado como repositorio git. Ejecuta: legalize-es.sh install"
    return 3
  fi

  echo "Actualizando legislación..."
  if ! git -C "$LEGALIZE_ES_DEFAULT_PATH" pull --ff-only 2>&1; then
    err "git pull falló en $LEGALIZE_ES_DEFAULT_PATH"
    return 1
  fi
  local last_commit
  last_commit=$(git -C "$LEGALIZE_ES_DEFAULT_PATH" log -1 --format="%ci — %s" 2>/dev/null)
  echo "Actualizado. Último commit: $last_commit"
}

cmd_status() {
  require_corpus

  local state_count ccaa_count last_commit disk_usage
  state_count=$(find "$LEGALIZE_ES_DEFAULT_PATH/es" -name "*.md" 2>/dev/null | wc -l)
  ccaa_count=$(find "$LEGALIZE_ES_DEFAULT_PATH" -maxdepth 1 -type d -name "es-*" 2>/dev/null | wc -l)
  last_commit=$(git -C "$LEGALIZE_ES_DEFAULT_PATH" log -1 --format="%ci" 2>/dev/null)
  disk_usage=$(du -sh "$LEGALIZE_ES_DEFAULT_PATH" 2>/dev/null | cut -f1)

  echo "legalize-es — Estado"
  echo "   Ruta: $LEGALIZE_ES_DEFAULT_PATH"
  echo "   Normas estatales: $state_count"
  echo "   Comunidades autónomas: $ccaa_count"
  echo "   Último commit BOE: ${last_commit:-desconocido (sin historial git)}"
  echo "   Espacio en disco: $disk_usage"
}

cmd_search() {
  local term="$1" scope="${2:-es}"
  if [[ -z "$term" ]]; then
    err "Falta término de búsqueda. Uso: legalize-es.sh search \"término\" [es|es-{ccaa}]"
    exit 2
  fi
  require_corpus
  if [[ ! "$scope" =~ ^es(-[a-z]{2,3})?$ || ! -d "$LEGALIZE_ES_DEFAULT_PATH/$scope" ]]; then
    err "Ámbito no válido o inexistente en el corpus: '$scope' (usa es o es-{ccaa})"
    exit 2
  fi

  echo "Buscando \"$term\" en $scope/ (literal, solo normas vigentes)..."

  # Término literal (-F) y protegido de opciones (-e). Vigencia leída del
  # frontmatter, no del cuerpo. Resultado ordenado por rango normativo.
  local results
  results=$(grep -rlF -i --include="*.md" -e "$term" "$LEGALIZE_ES_DEFAULT_PATH/$scope/" 2>/dev/null \
    | while IFS= read -r file; do
        [[ "$(fm_field "$file" status)" == "in_force" ]] || continue
        title=$(fm_field "$file" title)
        boe_id=$(fm_field "$file" identifier)
        [[ -n "$boe_id" ]] || boe_id=$(basename "$file" .md)
        rank=$(fm_field "$file" rank)
        printf '%s\t%s\t  %s — %s [%s]\n' "$(rank_priority "$rank")" "$boe_id" "$boe_id" "$title" "${rank:-rango desconocido}"
      done | sort -t$'\t' -k1,1n -k2,2 | cut -f3-)

  local total=0
  [[ -n "$results" ]] && total=$(printf '%s\n' "$results" | wc -l)

  if [[ "$total" -eq 0 ]]; then
    echo "Sin resultados vigentes para \"$term\" en $scope/."
    echo "Sin fuente: no afirmar cumplimiento ni citar normas por este término."
    exit 1
  fi

  printf '%s\n' "$results" | head -n "$SEARCH_LIMIT"
  if [[ "$total" -gt "$SEARCH_LIMIT" ]]; then
    echo "  (mostrando $SEARCH_LIMIT de $total; refina el término)"
  fi
  echo ""
  echo "Para ver artículos: legalize-es.sh search-article <BOE-ID> <artículo>"
}

cmd_search_article() {
  local boe_id="$1" article="$2"
  if [[ -z "$boe_id" || -z "$article" ]]; then
    err "Uso: legalize-es.sh search-article BOE-A-2018-16673 \"Artículo 13\""
    exit 2
  fi
  validate_id "$boe_id"
  require_corpus

  local file
  file=$(find_norm "$boe_id")
  if [[ -z "$file" ]]; then
    err "Norma $boe_id no encontrada en el corpus"
    exit 1
  fi

  # "Artículo 13", "Art. 13", "13", "13 bis" -> número; otro texto -> encabezado literal.
  local num="" heading=""
  num=$(printf '%s' "$article" | sed -E 's/^[[:space:]]*([Aa]rt(í|i)culo|[Aa]rt\.?)[[:space:]]*//; s/[[:space:]]*\.?[[:space:]]*$//')
  if [[ ! "$num" =~ ^[0-9] ]]; then
    num=""
    heading="$article"
  fi

  # Desde el encabezado exacto del artículo hasta el siguiente encabezado.
  local body
  body=$(awk -v num="$num" -v heading="$heading" '
    function strip(s) { sub(/^#+[ \t]+/, "", s); return s }
    /^#/ {
      if (found) exit
      h = strip($0)
      if (num != "") {
        if (index(h, "Artículo " num) == 1 || index(h, "Articulo " num) == 1) {
          rest = substr(h, index(h, " ") + 1 + length(num))
          if (rest == "" || substr(rest, 1, 1) == ".") found = 1
        }
      } else if (index(tolower(h), tolower(heading)) == 1) {
        found = 1
      }
    }
    found { print }' "$file")

  if [[ -z "$body" ]]; then
    err "Artículo '$article' no encontrado en $boe_id. No citarlo."
    exit 1
  fi

  fm_field "$file" title
  echo "---"
  printf '%s\n' "$body"
}

cmd_history() {
  local boe_id="$1"
  if [[ -z "$boe_id" ]]; then
    err "Uso: legalize-es.sh history BOE-A-2018-16673"
    exit 2
  fi
  validate_id "$boe_id"
  require_corpus

  local file
  file=$(find_norm "$boe_id")
  if [[ -z "$file" ]]; then
    err "Norma $boe_id no encontrada en el corpus"
    exit 1
  fi
  if ! git -C "$LEGALIZE_ES_DEFAULT_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    err "Corpus sin historial git en $LEGALIZE_ES_DEFAULT_PATH: no se pueden verificar reformas."
    exit 1
  fi

  echo "Historial de reformas: $boe_id"
  echo "   $(fm_field "$file" title)"
  echo "---"
  if [[ -f "$LEGALIZE_ES_DEFAULT_PATH/.git/shallow" ]]; then
    echo "AVISO: clone superficial — solo último commit disponible."
    echo "   Para historial completo: git -C \"$LEGALIZE_ES_DEFAULT_PATH\" fetch --unshallow"
    echo ""
  fi
  # git log con fecha BOE real (fecha del commit = fecha de publicación BOE)
  git -C "$LEGALIZE_ES_DEFAULT_PATH" log --format="%ci | %s" -- "${file#"$LEGALIZE_ES_DEFAULT_PATH"/}" 2>/dev/null | head -20
}

cmd_check_status() {
  local boe_id="$1"
  if [[ -z "$boe_id" ]]; then
    err "Uso: legalize-es.sh check-status BOE-A-2018-16673"
    exit 2
  fi
  validate_id "$boe_id"
  require_corpus

  local file
  file=$(find_norm "$boe_id")
  if [[ -z "$file" ]]; then
    err "Norma $boe_id no encontrada en el corpus"
    exit 1
  fi

  local title status rank last_updated status_label
  title=$(fm_field "$file" title)
  status=$(fm_field "$file" status)
  rank=$(fm_field "$file" rank)
  last_updated=$(fm_field "$file" last_updated)

  case "$status" in
    in_force) status_label="VIGENTE" ;;
    repealed) status_label="DEROGADA" ;;
    "")       status_label="DESCONOCIDO (sin campo status: no afirmar vigencia)" ;;
    *)        status_label="DESCONOCIDO ($status)" ;;
  esac

  echo "$boe_id"
  echo "   Título: $title"
  echo "   Estado: $status_label"
  echo "   Rango: $rank"
  echo "   Última actualización: $last_updated"
}

# --- Main ---
case "${1:-}" in
  install)        cmd_install ;;
  update)         cmd_update ;;
  status)         cmd_status ;;
  search)         cmd_search "${2:-}" "${3:-es}" ;;
  search-article) cmd_search_article "${2:-}" "${3:-}" ;;
  history)        cmd_history "${2:-}" ;;
  check-status)   cmd_check_status "${2:-}" ;;
  help|-h|--help) usage; exit 0 ;;
  *)              usage >&2; exit 2 ;;
esac
