#!/usr/bin/env bash
# scripts/language-boundary-check.sh — SE-253 Slice 7
# Emite WARNING para scripts .sh nuevos con >=5 usos de jq
# Modos: --warn (default, exit 0), --check (exit 1 si violaciones)
#
# Uso:
#   scripts/language-boundary-check.sh             # lee staged, modo --warn
#   scripts/language-boundary-check.sh --warn      # explícito, exit 0 siempre
#   scripts/language-boundary-check.sh --check     # exit 1 si hay violaciones
#   scripts/language-boundary-check.sh file.sh ... # analiza ficheros explícitos

set -euo pipefail

MODE="warn"
EXPLICIT_FILES=()
VIOLATIONS=0

# ── Parse args ────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --warn)  MODE="warn"  ;;
    --check) MODE="check" ;;
    *.sh)    EXPLICIT_FILES+=("$arg") ;;
    *)       echo "Opción desconocida: $arg"; exit 2 ;;
  esac
done

# ── Determinar ficheros a analizar ────────────────────────────────────────────
if [[ ${#EXPLICIT_FILES[@]} -gt 0 ]]; then
  FILES=("${EXPLICIT_FILES[@]}")
else
  # Solo scripts NUEVOS en staged (la regla aplica a código nuevo). git da las
  # rutas relativas a la raíz del repo: se anteponen para que funcione desde
  # cualquier subdirectorio.
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$top" ]]; then
    # Nuevo = añadido (A) o renombrado con cambios (R<100): un script reescrito
    # que git detecta como renombrado no escapa a la regla. Un renombrado puro
    # (R100) no añade código y no cuenta.
    mapfile -t FILES < <(git diff --cached --name-status --diff-filter=AR 2>/dev/null \
      | awk -F'\t' '$1 == "A" { print $2 } $1 ~ /^R/ && $1 != "R100" { print $3 }' \
      | grep '\.sh$' || true)
    [[ ${#FILES[@]} -gt 0 ]] && FILES=("${FILES[@]/#/$top/}")
  else
    FILES=()
  fi
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  exit 0
fi

# ── Excepciones: scripts de arranque que pueden usar jq legítimamente ─────────
is_exception() {
  local f
  f=$(basename "$1")
  [[ "$f" == install-*.sh || "$f" == setup.sh || "$f" == setup-*.sh ]]
}

# ── Análisis ──────────────────────────────────────────────────────────────────
for file in "${FILES[@]}"; do
  [[ -f "$file" ]] || continue
  is_exception "$file" && continue

  # Usos, no líneas: «jq . a | jq .r» son dos usos (la regla incluye pipes).
  count=$({ grep -o '\bjq\b' "$file" 2>/dev/null || true; } | wc -l)
  if [[ "$count" -ge 5 ]]; then
    echo "WARN [language-boundary]: $file tiene $count usos de jq — considera Python (SE-253)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

# ── Exit code ─────────────────────────────────────────────────────────────────
if [[ "$MODE" == "check" && "$VIOLATIONS" -gt 0 ]]; then
  exit 1
fi
exit 0
