#!/usr/bin/env bash
# scripts/savia-attest.sh — SE-255 Slice 6
# Genera atestacion semanal de lealtad: matriz nivel-N x destino.
# Uso: bash scripts/savia-attest.sh [--week YYYY-WW]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
[ "${1:-}" = "--week" ] && shift
WEEK="${1:-$(date +%Y-W%V)}"
# La semana forma parte de la ruta de salida: solo formato ISO, nada de `../`.
[[ "$WEEK" =~ ^[0-9]{4}-W[0-9]{2}$ ]] || { echo "ERROR: semana inválida '$WEEK' (esperado YYYY-Www)" >&2; exit 2; }
OUT="$ROOT/output/atestacion/${WEEK}.md"
mkdir -p "$(dirname "$OUT")"

# La anterior es la última semana estrictamente anterior en la cadena (nombres ISO ordenan por fecha).
# No se usa mtime: regenerar una semana vieja la haría apuntar a una posterior, y la de esta semana, a sí misma.
PREV=$(ls "$ROOT/output/atestacion/"*.md 2>/dev/null | sort | awk -v out="$OUT" '$0 < out' | tail -1 || true)
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

# Firma = checksum de integridad (sha256 sin clave, no prueba autoría) del cuerpo de arriba. Antes se calculaba sobre $OUT recién truncado por el
# heredoc: todas las atestaciones firmaban el hash del fichero vacío (e3b0c442...).
SIG=$(sha256sum "$BODY" | awk '{print $1}')
{
  cat "$BODY"
  printf '## Firma\n\nsha256 del cuerpo (todo lo anterior a esta sección):\n\n```\n%s\n```\n' "$SIG"
} > "$OUT"

echo "Atestacion generada: $OUT"
