#!/usr/bin/env bash
# check-readme-sync.sh — Verifica que README.md ≤ 150 líneas y que README.en.md existe si README.md cambia
# Regla: readme conventions (pm-workspace)
# Solo se miden los README que forman parte del cambio: un README que ya excedía el límite es deuda
# previa y no debe bloquear un commit que no lo toca (con el compliance-gate activo bloqueaba todos).
set -euo pipefail

VIOLATIONS=0
FILES_CHANGED=("$@")   # un argumento por fichero (con --all la lista no cabe en un solo argumento)

in_change() {  # in_change <ruta> → 0 si la ruta exacta aparece entre los ficheros del cambio
  local f
  for f in "${FILES_CHANGED[@]}"; do [[ "$f" == "$1" ]] && return 0; done
  return 1
}

# Check README size
for readme in README.md README.en.md; do
  [[ -f "$readme" ]] || continue
  in_change "$readme" || continue
  lines=$(wc -l < "$readme")
  if (( lines > 150 )); then
    echo "❌ $readme: $lines líneas (máx 150)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

# Si README.md cambió, README.en.md debería cambiar también (bilingual sync)
if in_change README.md && ! in_change README.en.md; then
  echo "⚠️  README.md modificado pero README.en.md no — ¿falta sincronizar traducción?"
  # Solo warning, no bloquea
fi

if [[ $VIOLATIONS -eq 0 ]]; then
  echo "✅ READMEs dentro de límites"
  exit 0
else
  exit 1
fi
