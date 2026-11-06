#!/usr/bin/env bash
# plan-diff-check.sh — SE-358: verifica que el diff respeta el plan.md.
# set -uo pipefail
#
# Comprueba que los archivos modificados en un diff están dentro de los
# listados en plan.md ("Files that change"). Un archivo fuera del plan es
# señal de scope creep silencioso o divergencia plan↔código.
#
# Uso:
#   plan-diff-check.sh --plan plan.md --files "a.py b.py" [--mode warn|block]
#   plan-diff-check.sh --plan plan.md --diff <(git diff --name-only)
#
# --mode warn (default): exit 0, imprime WARN de archivos divergentes
# --mode block: exit 2 si hay archivos fuera del plan
#
# --diff FILE: lee los ficheros cambiados de FILE (uno por línea).
# Si plan.md no existe o no se puede leer → fail-soft (WARN, exit 0) salvo
# --strict (exit 2), según AC-4 de SE-358.
# Ref: SE-358 — plan.md verificado (sync hook plan↔diff)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN=""
FILES_INPUT=""
MODE="warn"
STRICT=0

usage() { echo "Uso: plan-diff-check.sh --plan plan.md (--files 'a b' | --diff FILE) [--mode warn|block] [--strict]" >&2; exit 1; }

while [[ $# -gt 0 ]]; do case "$1" in
  --plan) [[ $# -ge 2 ]] || usage; PLAN="$2"; shift 2 ;;
  --files) [[ $# -ge 2 ]] || usage; FILES_INPUT="$2"; shift 2 ;;
  --diff)
    [[ $# -ge 2 && -r "$2" ]] || { echo "ERROR: --diff requiere un fichero legible" >&2; exit 1; }
    FILES_INPUT="$(tr '\n' ' ' < "$2")"; shift 2 ;;
  --mode) [[ $# -ge 2 ]] || usage; MODE="$2"; shift 2 ;;
  --strict) STRICT=1; shift ;;
  *) echo "ERROR: argumento desconocido: $1" >&2; usage ;;
esac; done

[[ "$MODE" == "warn" || "$MODE" == "block" ]] || { echo "ERROR: --mode debe ser warn o block" >&2; exit 1; }
[[ -z "$PLAN" || -z "${FILES_INPUT// /}" ]] && usage
soft_exit() { [[ "$STRICT" -eq 1 ]] && exit 2; exit 0; }
[[ -f "$PLAN" ]] || { echo "WARN: plan.md no existe ($PLAN) — fail-soft." >&2; soft_exit; }

# Extraer archivos del plan (del validador, por ruta absoluta: no depende del cwd)
PLANNED=$(python3 "$SCRIPT_DIR/plan-validate.py" --plan "$PLAN" --files 2>/dev/null || true)
if [[ -z "$PLANNED" ]]; then
  echo "WARN: no se pudieron extraer archivos de $PLAN (¿malformado?)" >&2
  soft_exit
fi

# Normalizar: cada archivo cambiado debe estar en el plan (o ser docs/plan)
DIVERGENT=""
for f in $FILES_INPUT; do
  case "$f" in
    plan.md|docs/specs/*|CHANGELOG.d/*|.confidentiality-signature|.scm/*)
      continue ;;  # artefactos del proceso, no son divergencia
  esac
  if ! echo "$PLANNED" | grep -qxF "$f"; then
    DIVERGENT="$DIVERGENT $f"
  fi
done

if [[ -n "$DIVERGENT" ]]; then
  echo "WARN [SE-358]: archivos fuera del plan.md:$DIVERGENT" >&2
  [[ "$MODE" == "block" ]] && exit 2
fi

exit 0
