#!/usr/bin/env bash
# refresh-agent-maps.sh
#
# Refresca las cabeceras de los .acm de un proyecto contra el estado real
# local de sus repos (skill agent-code-map). No genera mapas nuevos ni
# calcula hash: solo marca la fecha de refresco, detecta checkouts vacios y
# reporta conteos de codigo por repo.
#
# Uso:
#   bash scripts/refresh-agent-maps.sh <slug>            # todos los repos del proyecto
#   bash scripts/refresh-agent-maps.sh <slug> <repo>     # solo un repo
#
# Salida:
#   stdout: JSON con resumen del refresh por repo
#           status por repo: refreshed | missing-acm | stale-no-checkout | missing-repo | error
#   stderr: progreso humano
#   files:  actualiza la cabecera de projects/{slug}_main/.agent-maps/repos/{repo}.acm
#           actualiza refreshed: en projects/{slug}_main/.agent-maps/INDEX.acm
#
# Exit codes:
#   0 — refresco completado
#   1 — falta el directorio de repos o de mapas, el repo pedido no existe
#       (missing-repo) o algun .acm/INDEX.acm no se pudo escribir (error);
#       en esos casos no se toca INDEX.acm ni se imprime "OK"
#   2 — argumentos invalidos (slug o repo con caracteres fuera de [A-Za-z0-9._-])

set -uo pipefail

SLUG="${1:?Uso: $0 <slug> [repo]}"
SINGLE_REPO="${2:-}"

# Validacion de argumentos: impedir path traversal fuera de projects/.
valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ && "$1" != *..* && "$1" != "." ]]
}
if ! valid_name "$SLUG"; then
  echo "ERROR: slug invalido '$SLUG' (solo [A-Za-z0-9._-], sin '..')" >&2
  exit 2
fi
if [[ -n "$SINGLE_REPO" ]] && ! valid_name "$SINGLE_REPO"; then
  echo "ERROR: repo invalido '$SINGLE_REPO' (solo [A-Za-z0-9._-], sin '..')" >&2
  exit 2
fi

# Resolver workspace root
WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ_ROOT="$WS_ROOT/projects/${SLUG}_main"
REPOS_DIR="$PROJ_ROOT/${SLUG}/repos"
MAPS_DIR="$PROJ_ROOT/.agent-maps/repos"
INDEX_FILE="$PROJ_ROOT/.agent-maps/INDEX.acm"

if [[ ! -d "$REPOS_DIR" ]]; then
  echo "ERROR: $REPOS_DIR no existe" >&2
  exit 1
fi
if [[ ! -d "$MAPS_DIR" ]]; then
  echo "ERROR: $MAPS_DIR no existe (crear los .acm iniciales segun .claude/skills/agent-code-map/SKILL.md)" >&2
  exit 1
fi

TODAY="$(date +%Y-%m-%d)"
NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# json_str: escapa una cadena para JSON (barra, comillas; controles -> espacio)
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="$(printf '%s' "$s" | tr '\000-\037' ' ')"
  printf '"%s"' "$s"
}

# atomic_rewrite <fichero> <orden...>: ejecuta `<orden> <fichero> > temporal`
# con un temporal unico en el mismo directorio y lo mueve encima con mv
# atomico, para que ejecuciones concurrentes no compartan temporal ni dejen
# ficheros a medias. Si no se puede escribir, avisa en stderr, conserva el
# original, elimina el temporal y devuelve 1 (el llamador lo reporta).
atomic_rewrite() {
  local file="$1" tmp
  shift
  tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || {
    echo "  ERROR no se pudo crear temporal junto a $file (sin permiso de escritura?)" >&2
    return 1
  }
  if "$@" "$file" > "$tmp" && mv -f "$tmp" "$file"; then
    return 0
  fi
  echo "  ERROR no se pudo reescribir $file; se conserva el original" >&2
  rm -f -- "$tmp"
  return 1
}

# rewrite_header <acm> <awk-program>: aplica el programa awk al .acm
rewrite_header() {
  atomic_rewrite "$1" awk -v today="$TODAY" "$2"
}

# Función: refrescar un repo individual
refresh_repo() {
  local repo="$1"
  local repo_dir="$REPOS_DIR/$repo"
  local acm_file repo_normalized cand_normalized cand
  # Estrategia robusta: comparar el nombre del repo contra los .acm existentes
  # ignorando case, guiones y underscores. El primer match es el válido.
  # Esto evita errores de naming convention (DotNet→dotnet, no dot-net).
  repo_normalized=$(echo "$repo" | tr -d '_-' | tr '[:upper:]' '[:lower:]')
  acm_file=""
  for cand in "$MAPS_DIR"/*.acm; do
    [[ -f "$cand" ]] || continue
    cand_normalized=$(basename "$cand" .acm | tr -d '_-' | tr '[:upper:]' '[:lower:]')
    if [[ "$cand_normalized" == "$repo_normalized" ]]; then
      acm_file="$cand"
      break
    fi
  done
  # Si no encuentra match, generar nombre por convención simple (lowercase + _→-)
  if [[ -z "$acm_file" ]]; then
    acm_file="$MAPS_DIR/$(echo "$repo" | tr '_' '-' | tr '[:upper:]' '[:lower:]').acm"
  fi

  if [[ ! -d "$repo_dir" ]]; then
    echo "  SKIP $repo: repo dir missing" >&2
    echo "{\"repo\":$(json_str "$repo"),\"status\":\"missing-repo\",\"acm\":$(json_str "$acm_file")}"
    return 1
  fi

  # Checkout local = alguna entrada distinta de .git (incluidas las ocultas)
  local entries
  entries=$(find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git 2>/dev/null | wc -l)
  if [[ "$entries" -eq 0 ]]; then
    # Solo .git: marcar la cabecera (solo la primera linea '> ', no las citas del cuerpo)
    local stale_status="stale-no-checkout"
    if [[ -f "$acm_file" ]]; then
      rewrite_header "$acm_file" '
        /^> / && !done { print "> hash: sha256:auto | generated: ?? | refreshed: " today " | status: stale-no-checkout (only .git, no source files)"; done=1; next }
        { print }' || stale_status="error"
    fi
    echo "{\"repo\":$(json_str "$repo"),\"status\":\"$stale_status\",\"acm\":$(json_str "$acm_file")}"
    [[ "$stale_status" != "error" ]]
    return
  fi

  # Última info git del propio repo (no de un repo padre); git trunca el
  # asunto respetando UTF-8.
  local last_commit="unknown" top
  top="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [[ -n "$top" && "$top" == "$(cd "$repo_dir" && pwd -P)" ]]; then
    last_commit=$(git -C "$repo_dir" log -1 --format='%ai %h %<(70,trunc)%s' 2>/dev/null) || last_commit=""
    last_commit="${last_commit%"${last_commit##*[![:space:]]}"}"
    [[ -n "$last_commit" ]] || last_commit="unknown"
  fi

  # Conteos de código
  local cs_count vue_count sql_count tf_count csproj_count controllers
  cs_count=$(find "$repo_dir" -maxdepth 6 -name "*.cs" 2>/dev/null | wc -l)
  vue_count=$(find "$repo_dir" -maxdepth 6 -name "*.vue" 2>/dev/null | wc -l)
  sql_count=$(find "$repo_dir" -maxdepth 6 -name "*.sql" 2>/dev/null | wc -l)
  tf_count=$(find "$repo_dir" -maxdepth 6 -name "*.tf" 2>/dev/null | wc -l)
  csproj_count=$(find "$repo_dir" -maxdepth 6 -name "*.csproj" 2>/dev/null | wc -l)
  controllers=$(find "$repo_dir" -path '*/Controllers/*.cs' 2>/dev/null | wc -l)

  local status="refreshed"
  if [[ -f "$acm_file" ]]; then
    # Cabecera = primera linea '> ': fija refreshed: <hoy>
    rewrite_header "$acm_file" '
      /^> / && !done {
        if ($0 ~ /refreshed:/) { gsub(/refreshed: [0-9?-]+/, "refreshed: " today) }
        else { $0 = $0 " | refreshed: " today }
        done=1
      }
      { print }' || status="error"
  else
    status="missing-acm"
  fi

  echo "{\"repo\":$(json_str "$repo"),\"status\":\"$status\",\"acm\":$(json_str "$acm_file"),\"counts\":{\"cs\":$cs_count,\"vue\":$vue_count,\"sql\":$sql_count,\"tf\":$tf_count,\"csproj\":$csproj_count,\"controllers\":$controllers},\"last_commit\":$(json_str "$last_commit")}"
  [[ "$status" != "error" ]]
}

# Iterar repos
RC=0
echo "=== refresh-agent-maps: slug=$SLUG ts=$NOW_TS ===" >&2
echo "{\"slug\":$(json_str "$SLUG"),\"ts\":\"$NOW_TS\",\"repos\":["
FIRST=1
if [[ -n "$SINGLE_REPO" ]]; then
  refresh_repo "$SINGLE_REPO" || RC=1
else
  for d in "$REPOS_DIR"/*; do
    [[ -d "$d" ]] || continue
    repo="$(basename "$d")"
    [[ "$repo" == ".git" ]] && continue
    if [[ "$FIRST" -eq 0 ]]; then echo ","; fi
    refresh_repo "$repo" || RC=1
    FIRST=0
  done
fi
echo "]}"

if [[ "$RC" -ne 0 ]]; then
  echo "ERROR refresh-agent-maps slug=$SLUG: algun repo termino en missing-repo o error (ver JSON); INDEX.acm sin tocar" >&2
  exit "$RC"
fi

# Actualizar timestamp en INDEX.acm (misma escritura atomica que los .acm)
if [[ -f "$INDEX_FILE" ]] && grep -q "refreshed:" "$INDEX_FILE" 2>/dev/null; then
  if ! atomic_rewrite "$INDEX_FILE" sed "s/refreshed: [0-9?-]\+/refreshed: $TODAY/g"; then
    echo "ERROR refresh-agent-maps slug=$SLUG: INDEX.acm no se pudo actualizar" >&2
    exit 1
  fi
fi

echo "OK refresh-agent-maps slug=$SLUG" >&2
