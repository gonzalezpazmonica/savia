#!/usr/bin/env bash
# overnight-handoff-digest.sh — SE-471: relevo nocturno con evidencia (declarado / validado / aceptado), solo lectura.
# Uso: bash scripts/overnight-handoff-digest.sh --runs-dir <dir> [--since <ISO>] [--log <fichero>]
#                                              [--online] [--max-decisions 7] [--format md|json]
# Lee <dir>/<nombre>/done y, con --online, `gh pr view` para URL de PR en allowlist. Nunca escribe fuera de stdout.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 no disponible" >&2; exit 2; }
# -I: aislado (no carga módulos del cwd); -B: sin .pyc (solo lectura).
exec python3 -I -B "$here/overnight_handoff_digest.py" "$@"
