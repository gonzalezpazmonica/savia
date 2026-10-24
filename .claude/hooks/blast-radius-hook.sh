#!/usr/bin/env bash
set -uo pipefail
# blast-radius-hook.sh — SE-318 S3: hook pre-write de blast-radius.
#
# PreToolUse (matcher Edit|Write) en ficheros de código: invoca blast-radius
# en modo ligero y muestra "AFFECTED: N files" como advertencia. NUNCA bloquea.
#
# Invocación:
#   - como hook: JSON en stdin (tool_input.file_path)
#   - CLI directo (tests): --file <path>
#
# Exit: siempre 0 (advertencia, no gate). Ref: SE-318.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLAST="$SCRIPT_DIR/../../scripts/blast-radius.sh"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# Master switch (Rule #19-style): opt-in para no añadir latencia por defecto.
SAVIA_BLAST_RADIUS="${SAVIA_BLAST_RADIUS:-off}"
[[ "$SAVIA_BLAST_RADIUS" != "on" ]] && exit 0

INPUT_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) INPUT_PATH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$INPUT_PATH" ]]; then
  INPUT=""
  if INPUT=$(timeout 3 cat 2>/dev/null); then
    :
  fi
  if [[ -n "$INPUT" ]] && command -v jq &>/dev/null; then
    INPUT_PATH=$(printf '%s' "$INPUT" | jq -r '
      .tool_input.file_path //
      .tool_input.filePath //
      .tool_input.path //
      empty' 2>/dev/null) || INPUT_PATH=""
  fi
fi

# Sin path o fuera del repo → no-op
[[ -z "$INPUT_PATH" ]] && exit 0
[[ -z "$REPO_ROOT" ]] && exit 0
case "$INPUT_PATH" in
  /tmp/*|/var/*|/etc/*) exit 0 ;;
esac

# Solo ficheros de código (mismas extensiones que blast-radius)
case "$INPUT_PATH" in
  *.sh|*.py|*.ts|*.js|*.tsx|*.jsx|*.java|*.cs|*.go|*.rb|*.php|*.rs|*.vue|*.svelte|*.c|*.cpp|*.h|*.hpp) ;;
  *) exit 0 ;;
esac

# Time-box estricto: el hook nunca debe frenar la edición (max 5s).
# Consulta blast-radius de las definiciones presentes en el fichero editado.
# Solo avisa (exit 0) — nunca bloquea.
RELPATH="${INPUT_PATH#$REPO_ROOT/}"
total_affected=0
if [[ -f "$INPUT_PATH" ]] && command -v timeout >/dev/null 2>&1; then
  syms=$(timeout 4 bash -c "
    git -C '$REPO_ROOT' grep -hE '([[:space:]]|^)(def|func|function|class|fn|sub)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[a-zA-Z_][a-zA-Z0-9_]*\(\)' -- '$RELPATH' 2>/dev/null \
    | grep -oE '(def|func|function|class|fn|sub)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|[a-zA-Z_][a-zA-Z0-9_]*\(\)' \
    | sed -E 's/^(def|func|function|class|fn|sub)[[:space:]]+//; s/\(\)//' \
    | grep -vE '^(def|func|function|class|fn|sub)$' | sort -u" 2>/dev/null) || syms=""
  if [[ -n "$syms" ]]; then
    while IFS= read -r s; do
      [[ -z "$s" ]] && continue
      n=$(timeout 4 bash "$BLAST" --symbol "$s" 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['total'])" 2>/dev/null || echo "0")
      if [[ "${n:-0}" -gt 0 ]]; then
        echo "AFFECTED: '$s' → $n fichero(s) dependientes" >&2
        total_affected=$((total_affected + n))
      fi
    done <<< "$syms"
  fi
fi

if [[ "$total_affected" -eq 0 ]]; then
  echo "AFFECTED: usa 'scripts/blast-radius.sh --diff origin/main..HEAD' para ver el impacto del cambio (SE-318)" >&2
fi

exit 0
