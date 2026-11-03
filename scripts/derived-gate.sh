#!/usr/bin/env bash
# derived-gate.sh — SE-501 G20 «Derivados fuera de la PR» y paso de CI «Derived paths absent».
# Falla si el diff de la PR (merge-base..HEAD) añade o modifica una ruta de la lista cerrada D
# (scripts/derived-paths.txt). Borrar D está permitido: es lo que hacen la migración y derived-drop.sh.
#
# Uso: derived-gate.sh [--base <ref>] [--range <a>..<b>]
#   --base   rama o commit base (por defecto origin/main); se usa su merge-base con HEAD.
#   --range  rango explícito (la CI pasa base_sha..HEAD sobre el commit de fusión).
# Salida: 0 PASS · 1 FAIL (nombra cada ruta) · 2 error (sin lista D, git no calcula el diff): fail-closed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/derived-paths.sh
source "$ROOT/scripts/lib/derived-paths.sh"

BASE="origin/main"; RANGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --range) RANGE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "derived-gate: argumento desconocido: $1" >&2; exit 2 ;;
  esac
done

derived_paths_load "$ROOT" || { echo "G20 ERROR: falta o está vacía scripts/derived-paths.txt" >&2; exit 2; }

if [[ -z "$RANGE" ]]; then
  mb=$(git -C "$ROOT" merge-base "$BASE" HEAD 2>/dev/null) || { echo "G20 ERROR: sin merge-base con $BASE" >&2; exit 2; }
  RANGE="$mb..HEAD"
fi
# --diff-filter=d: excluye borrados. -z: rutas sin escapar.
names=$(git -C "$ROOT" diff --name-only --no-renames --diff-filter=d -z "$RANGE" 2>/dev/null | tr '\0' '\n') \
  || { echo "G20 ERROR: git no pudo calcular el diff $RANGE" >&2; exit 2; }

bad=()
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  is_derived_path "$f" && bad+=("$f")
done <<<"$names"

if (( ${#bad[@]} )); then
  echo "G20 FAIL: la PR versiona derivados que se generan en local (SE-501):"
  printf '  %s\n' "${bad[@]}"
  echo "Arreglo: bash scripts/derived-drop.sh"
  exit 1
fi
echo "G20 PASS: ninguna ruta derivada en el diff ($RANGE)"
