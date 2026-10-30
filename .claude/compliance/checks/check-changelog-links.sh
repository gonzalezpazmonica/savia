#!/usr/bin/env bash
# check-changelog-links.sh — Verifica que cada versión en CHANGELOG.md tenga link de comparación
# Regla: changelog-enforcement.md → "Link de comparación al final del fichero"
set -euo pipefail

FILE="${1:-CHANGELOG.md}"
[[ -f "$FILE" ]] || { echo "⚠️  $FILE no encontrado"; exit 0; }

VIOLATIONS=0

# Extraer versiones del heading
mapfile -t HEADINGS < <(grep -oP '(?<=^## \[)[0-9]+\.[0-9]+\.[0-9]+' "$FILE")

# Extraer versiones con link de comparación
mapfile -t LINKS < <(grep -oP '(?<=^\[)[0-9]+\.[0-9]+\.[0-9]+(?=\]: https://github\.com/)' "$FILE")

for version in "${HEADINGS[@]}"; do
  found=false
  for link in "${LINKS[@]}"; do
    if [[ "$version" == "$link" ]]; then
      found=true
      break
    fi
  done
  if ! $found; then
    echo "❌ Versión [$version] sin link de comparación al final del CHANGELOG"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [[ $VIOLATIONS -eq 0 ]]; then
  echo "✅ Todas las versiones tienen link de comparación"
  exit 0
else
  echo "💡 Añadir al final: [$version]: https://github.com/.../compare/vAnterior...v$version"
  exit 1
fi
