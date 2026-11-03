#!/usr/bin/env bash
# derived-paths.sh — SE-501: lista cerrada de derivados (D) leída de scripts/derived-paths.txt.
# Uso: source este fichero y llama a derived_paths_load <raíz>; luego is_derived_path <ruta>.
# Comparación exacta o por prefijo de directorio (entradas acabadas en «/»). Nunca regex.

DERIVED_PATHS=()

# derived_paths_load <raíz> → 0 si la lista existe y no está vacía; 1 si no (fail-closed: quien la usa
# para decidir si algo es derivado no puede seguir sin ella).
derived_paths_load() {
  local f="${1:-.}/scripts/derived-paths.txt" l
  DERIVED_PATHS=()
  [[ -r "$f" ]] || return 1
  while IFS= read -r l || [[ -n "$l" ]]; do
    l="${l%$'\r'}"
    [[ -z "$l" || "$l" == \#* ]] && continue
    DERIVED_PATHS+=("$l")
  done < "$f"
  (( ${#DERIVED_PATHS[@]} > 0 ))
}

# is_derived_path <ruta> → 0 si la ruta es D.
is_derived_path() {
  local p="$1" d
  for d in "${DERIVED_PATHS[@]}"; do
    if [[ "$d" == */ ]]; then [[ "$p" == "$d"* ]] && return 0
    else [[ "$p" == "$d" ]] && return 0; fi
  done
  return 1
}

# derived_pathspecs → las entradas de D como pathspecs literales de git (un prefijo de directorio sin «/»).
derived_pathspecs() {
  local d
  for d in "${DERIVED_PATHS[@]}"; do printf ':(literal)%s\n' "${d%/}"; done
}
