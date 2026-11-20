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
    --guard|--event|--tool)
      # Sin valor, `shift 2` fallaba y el bucle no avanzaba nunca (sin set -e).
      [[ $# -ge 2 ]] || { echo "wrap: $1 sin valor" >&2; exit 2; }
      case "$1" in --guard) guard="$2" ;; --event) event="$2" ;; --tool) tool="$2" ;; esac
      shift 2 ;;
    --) shift; break ;;
    *) echo "wrap: argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$guard" || $# -eq 0 ]]; then
  echo "uso: guard-blocks.sh wrap --guard G [--event E] [--tool T] -- <orden del hook…>" >&2
  exit 2
fi
# La entrada va a un fichero, no a una variable ni a un pipe: así el hook recibe los mismos
# bytes (salto final y NUL incluidos) y un hook que no lee stdin no provoca SIGPIPE (141)
# con entradas grandes, que con pipefail cambiaría el código que se reenvía.
inp=$(mktemp) && err=$(mktemp) || { echo "BLOQUEADO [$guard]: sin fichero temporal para el hook" >&2; exit 2; }
trap 'rm -f "$inp" "$err"' EXIT
[[ -t 0 ]] || cat >"$inp"
"$@" <"$inp" 2>"$err"
rc=$?
cat "$err" >&2
if [[ $rc -eq 2 ]]; then
  reason=$(grep -m1 -v '^[[:space:]]*$' "$err" || true)
  # El motivo puede citar lo detectado: por el entorno (solo la dueña), no por argv (/proc).
  SAVIA_GUARD_BLOCK_REASON="$reason" python3 "$DIR/guard_blocks.py" record --guard "$guard" \
    --event "$event" --tool "$tool" --engine bash <"$inp" >/dev/null 2>&1 \
    || echo "AVISO: bloqueo de $guard no registrado en output/guard-blocks.jsonl" >&2
fi
exit "$rc"
