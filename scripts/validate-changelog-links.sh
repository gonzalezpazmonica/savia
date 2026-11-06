#!/bin/bash
# validate-changelog-links.sh — Verifica que cada ## [X.Y.Z] tiene su enlace [X.Y.Z]: URL
# Puede ejecutarse standalone o desde prompt-hook-commit.sh
set -euo pipefail
CHANGELOG="${1:-CHANGELOG.md}"
if [[ ! -f "$CHANGELOG" ]]; then
    # Sin argumento y sin CHANGELOG.md no hay nada que validar. Una ruta explícita
    # que no existe (p. ej. la del runner de compliance) es un error: fail-closed.
    if [[ $# -ge 1 ]]; then echo "❌ CHANGELOG not found: $CHANGELOG"; exit 1; fi
    echo "No CHANGELOG found"; exit 0
fi

ERRORS=0
# Extract all version headers: ## [X.Y.Z] — ...
while IFS= read -r header_version; do
    # Check if a matching link reference exists: [X.Y.Z]: https://...
    # Los puntos de la versión son literales: [1x2x3] no es el enlace de [1.2.3].
    if ! grep -q "^\[${header_version//./\\.}\]: https://" "$CHANGELOG"; then
        echo "❌ Missing link for [${header_version}] in CHANGELOG.md"
        ERRORS=$((ERRORS+1))
    fi
done < <(grep -oP '(?<=^## \[)[0-9]+\.[0-9]+\.[0-9]+(?=\])' "$CHANGELOG")

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "⚠️  $ERRORS version(s) sin enlace de referencia al final del CHANGELOG."
    echo "   Formato esperado: [X.Y.Z]: https://github.com/.../compare/vA.B.C...vX.Y.Z"
    exit 1
fi
echo "✅ Todos los enlaces de versión presentes en CHANGELOG.md"
exit 0
