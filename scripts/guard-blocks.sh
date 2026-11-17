#!/usr/bin/env bash
# guard-blocks.sh — registro local de bloqueos de guardas (SE-510 D2).
#
#   guard-blocks.sh record|mark|report …          → scripts/guard_blocks.py (detalle: --help)
#   guard-blocks.sh wrap --guard G [--event E] [--tool T] -- <orden del hook…>
#       Ejecuta el hook con la misma entrada (stdin). Reenvía stdout, stderr y el código
#       tal cual. Solo si sale 2 llama al registrador con la primera línea del mensaje:
#       el camino que pasa no lanza Python. Un fallo al registrar no cambia el veredicto.
#
# El registro se queda en output/ de esta máquina; nada sale fuera.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "${1:-}" == "wrap" ]] || exec python3 "$DIR/guard_blocks.py" "$@"
shift
guard="" event="PreToolUse" tool="Bash"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --guard) guard="${2:-}"; shift 2 ;;
    --event) event="${2:-}"; shift 2 ;;
    --tool) tool="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) echo "wrap: argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$guard" || $# -eq 0 ]]; then
  echo "uso: guard-blocks.sh wrap --guard G [--event E] [--tool T] -- <orden del hook…>" >&2
  exit 2
fi
raw=""
[[ -t 0 ]] || raw=$(cat)
err=$(mktemp) || { echo "BLOQUEADO [$guard]: sin fichero temporal para el hook" >&2; exit 2; }
trap 'rm -f "$err"' EXIT
printf '%s' "$raw" | "$@" 2>"$err"
rc=$?
cat "$err" >&2
if [[ $rc -eq 2 ]]; then
  reason=$(grep -m1 -v '^[[:space:]]*$' "$err" || true)
  printf '%s' "$raw" | python3 "$DIR/guard_blocks.py" record --guard "$guard" --event "$event" \
    --tool "$tool" --engine bash --reason "$reason" >/dev/null 2>&1 \
    || echo "AVISO: bloqueo de $guard no registrado en output/guard-blocks.jsonl" >&2
fi
exit "$rc"
