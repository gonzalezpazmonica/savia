#!/usr/bin/env bash
# check-command-frontmatter.sh — Verifica YAML frontmatter en los comandos que recibe
# Regla: command-validation (convención pm-workspace)
# Verifica exactamente los ficheros que le pasa el runner (los del cambio: stage o rango de la PR). Antes
# filtraba además por `git diff --cached`, y en la CI (índice vacío) se saltaba todo y daba verde.
# Los ficheros de references/ no son comandos y no llevan frontmatter.
set -euo pipefail

VIOLATIONS=0

for file in "$@"; do
  [[ -f "$file" ]] || continue
  [[ "$file" =~ ^(\.claude|\.opencode)/commands/.+\.md$ ]] || continue
  [[ "$file" == */references/* ]] && continue

  # Debe empezar con ---
  first_line=$(head -1 "$file")
  if [[ "$first_line" != "---" ]]; then
    echo "⚠️  $file: comando sin frontmatter YAML"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [[ $VIOLATIONS -eq 0 ]]; then
  echo "✅ Frontmatter de comandos OK"
  exit 0
else
  exit 1
fi
