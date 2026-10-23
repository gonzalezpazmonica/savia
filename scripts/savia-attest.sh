#!/usr/bin/env bash
# scripts/savia-attest.sh — SE-255 Slice 6
# Genera atestacion semanal de lealtad: matriz nivel-N x destino.
# Uso: bash scripts/savia-attest.sh [--week YYYY-WW]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
WEEK="${1:-$(date +%Y-W%V)}"
OUT="$ROOT/output/atestacion/${WEEK}.md"
mkdir -p "$(dirname "$OUT")"

# La anterior es la más reciente que no sea la de esta semana (si no, la cadena apunta a sí misma).
PREV=$(ls -t "$ROOT/output/atestacion/"*.md 2>/dev/null | grep -vxF "$OUT" | head -1 || echo "")
PREV_HASH=""
[ -n "$PREV" ] && PREV_HASH=$(sha256sum "$PREV" | awk '{print $1}')

BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT
cat > "$BODY" <<EOF
# Atestacion de lealtad — $WEEK

- **Principal unico:** operadora (verificable via sesiones activas)
- **Hash anterior:** ${PREV_HASH:-genesis}

## Matriz nivel-N x destino

| Nivel | Local (Ollama) | Cloud (DeepSeek) | Cloud (Anthropic) | Disco | Red externa |
|-------|-----------------|-------------------|--------------------|-------|-------------|
| N1    | —               | —                 | —                  | —     | —           |
| N2    | —               | —                 | —                  | —     | —           |
| N3    | —               | —                 | —                  | —     | —           |
| N4    | —               | —                 | —                  | —     | —           |

> Celdas se rellenan con telemetria de sesiones. N3+ jamas a cloud.

## Cero-exfiltracion

- Conexiones salientes observadas: [instrumentar]
- Allowlist declarada: [scenario.yaml]
- Delta (violaciones): 0

EOF

# Firma = sha256 del cuerpo de arriba. Antes se calculaba sobre $OUT recién truncado por el
# heredoc: todas las atestaciones firmaban el hash del fichero vacío (e3b0c442...).
SIG=$(sha256sum "$BODY" | awk '{print $1}')
{
  cat "$BODY"
  printf '## Firma\n\nsha256 del cuerpo (todo lo anterior a esta sección):\n\n```\n%s\n```\n' "$SIG"
} > "$OUT"

echo "Atestacion generada: $OUT"
