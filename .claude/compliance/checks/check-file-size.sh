#!/usr/bin/env bash
# check-file-size.sh — Verifica que ficheros .md y .sh no excedan 150 líneas
# Regla: file-size-limit (convención pm-workspace: commands ≤150, rules ≤150)
# Excluye: CHANGELOG.md, docs/ largos históricos, projects/
set -euo pipefail

MAX_LINES=150
VIOLATIONS=0

EXCLUDES="CHANGELOG.md|ACKNOWLEDGMENTS.md|projects/|node_modules/|\.git/|rules/languages/|/references/"

for file in "$@"; do
  [[ -f "$file" ]] || continue
  [[ "$file" =~ $EXCLUDES ]] && continue
  # Solo .md en .opencode/commands/, docs/rules/, .opencode/skills/
  if [[ "$file" =~ (\.claude/(commands|skills)|docs/rules)/.+\.md$ ]]; then
    lines=$(wc -l < "$file")
    if (( lines > MAX_LINES )); then
      echo "❌ $file: $lines líneas (máx $MAX_LINES)"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
done

if [[ $VIOLATIONS -eq 0 ]]; then
  echo "✅ Todos los ficheros dentro del límite de $MAX_LINES líneas"
  exit 0
else
  exit 1
fi
