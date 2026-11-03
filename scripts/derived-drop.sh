#!/usr/bin/env bash
# derived-drop.sh — SE-501: saca los derivados (D) del diff de la PR con un único commit.
# Cada ruta de D que la rama tiene distinta de la base vuelve al estado de la base: si la base la tiene,
# se restaura su contenido; si no (tras el corte, D no se versiona), se quita del índice y el fichero
# local se conserva (está en .gitignore). No toca ninguna ruta fuera de D.
#
# Uso: derived-drop.sh [--base <ref>]   (por defecto origin/main)
# Salida: 0 commit creado o nada que hacer · 1 el índice tenía cambios ajenos (no mezcla) · 2 error.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/derived-paths.sh
source "$ROOT/scripts/lib/derived-paths.sh"
BASE="origin/main"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "derived-drop: argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
derived_paths_load "$ROOT" || { echo "derived-drop: falta scripts/derived-paths.txt" >&2; exit 2; }
G() { git -C "$ROOT" "$@"; }
G rev-parse -q --verify "$BASE^{commit}" >/dev/null || { echo "derived-drop: base desconocida: $BASE" >&2; exit 2; }
G diff --cached --quiet || { echo "derived-drop: el índice tiene cambios; haz commit o retíralos antes" >&2; exit 1; }

mapfile -t specs < <(derived_pathspecs)
# Rutas de D que difieren entre la base y HEAD (incluye las que la base ya no versiona).
mapfile -t paths < <(G diff --name-only --no-renames "$BASE" HEAD -- "${specs[@]}" 2>/dev/null)
todo=()
for p in "${paths[@]}"; do [[ -n "$p" ]] && is_derived_path "$p" && todo+=("$p"); done
(( ${#todo[@]} )) || { echo "derived-drop: la rama no difiere de $BASE en ninguna ruta derivada"; exit 0; }

for p in "${todo[@]}"; do
  if G cat-file -e "$BASE:$p" 2>/dev/null; then
    G checkout -q "$BASE" -- "$p" || exit 2
  elif G cat-file -e "HEAD:$p" 2>/dev/null; then
    G rm -q --cached -- "$p" || exit 2
  fi
done
G diff --cached --quiet && { echo "derived-drop: nada que commitear"; exit 0; }
G commit -q -m "chore(derived): saca los derivados del diff de la PR (SE-501)" \
  -m "Generado por scripts/derived-drop.sh: solo toca rutas de scripts/derived-paths.txt." || exit 2
echo "derived-drop: commit $(G rev-parse --short HEAD) con ${#todo[@]} ruta(s) derivada(s)"
