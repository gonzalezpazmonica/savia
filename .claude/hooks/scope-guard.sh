#!/bin/bash
set -uo pipefail
# scope-guard.sh — Detecta ficheros modificados fuera del scope de la spec SDD activa
# SE-260 S1: Tambien detecta ficheros fuera del path-set congelado del Court.
# Usado por: settings.json (Stop hook)
# Exit codes: 0 = pass (con warning si aplica), 1 = bloqueo (solo en modo court activo)

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
GIT_TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
ROOT="${GIT_TOP:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Ficheros tracked modificados (staged + unstaged) respecto a HEAD.
# Tras un checkout recién hecho (actions/checkout, clone, pull) las entradas
# del índice quedan «racy»: git no puede fiarse del stat y `git diff` vuelve a
# leer y hashear cada fichero en CADA llamada, porque diff nunca reescribe el
# índice (~6000 ficheros, 100-500 ms en la CI). `update-index --refresh`
# persiste el stat verificado: el coste se paga una vez por checkout.
modified_files() {
  git -C "$1" update-index -q --refresh >/dev/null 2>&1 || true
  git -C "$1" diff HEAD --name-only 2>/dev/null || true
}

# ── SE-260 S1: Court mode — enforce frozen path-set during fix phase ──
CRC_FILE="$ROOT/.review.crc"
if [[ -f "$CRC_FILE" ]]; then
  # Check if review is in frozen/fix state
  if grep -q "status: frozen" "$CRC_FILE" 2>/dev/null; then
    # Extract path-set from .review.crc
    PATH_SET=$(python3 -c "
import yaml, sys
try:
    with open('$CRC_FILE') as f:
        crc = yaml.safe_load(f)
    paths = crc.get('paths', [])
    for p in paths:
        print(p)
except: pass
" 2>/dev/null || grep -oE '^\s+- .*' "$CRC_FILE" 2>/dev/null | sed 's/^\s*- //' || echo "")

    if [[ -n "$PATH_SET" ]]; then
      # Get current modified files (staged + unstaged)
      MODIFIED=$(modified_files "$ROOT")
      OUT_OF_COURT=""
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # Skip excluded patterns
        [[ "$f" =~ ^(CHANGELOG\.md|\.scm/|\.pr-summary\.md|output/receipts/) ]] && continue
        if ! echo "$PATH_SET" | grep -qF "$f"; then
          OUT_OF_COURT+="  $f\n"
        fi
      done <<< "$MODIFIED"

      if [[ -n "$OUT_OF_COURT" ]]; then
        echo "COURT SCOPE GUARD: Fix modifies paths outside frozen review path-set:" >&2
        echo -e "$OUT_OF_COURT" >&2
        echo "Fix rejected — path-set is frozen. Escalate to operator if expansion needed." >&2
        exit 1
      fi
    fi
  fi
fi
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

INPUT=$(cat)

PROJECT_ROOT="${GIT_TOP:-.}"

# Orden por coste: spec activa y ficheros declarados (baratos) antes que git
# (O(ficheros tracked)). Sin spec con ficheros declarados no hay nada que
# comparar y git no se ejecuta.
# Restrict search to known SDD locations + maxdepth 4 (specs live at projects/{slug}/specs/ or docs/specs/)
SEARCH_PATHS=()
for p in "$PROJECT_ROOT/projects" "$PROJECT_ROOT/docs/specs" "$PROJECT_ROOT/docs/propuestas"; do
  [[ -d "$p" ]] && SEARCH_PATHS+=("$p")
done

# Early exit: no spec dirs → nothing to verify
if [[ ${#SEARCH_PATHS[@]} -eq 0 ]]; then
  exit 0
fi

SPEC_FILE=""
if [[ -n "${SAVIA_TMP:-}" && -f "$SAVIA_TMP/.scope-guard-marker" ]]; then
  SPEC_FILE=$(find "${SEARCH_PATHS[@]}" -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name build -o -name dist -o -name target \) -prune -o \
    -name "*.spec.md" -newer "$SAVIA_TMP/.scope-guard-marker" -print -quit 2>/dev/null)
fi

if [ -z "$SPEC_FILE" ]; then
  SPEC_FILE=$(find "${SEARCH_PATHS[@]}" -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name build -o -name dist -o -name target \) -prune -o \
    -name "*.spec.md" -mmin -60 -print -quit 2>/dev/null)
fi

if [ -z "$SPEC_FILE" ] || [ ! -f "$SPEC_FILE" ]; then
  exit 0
fi

# Extract declared files in spec — bullet lines only to avoid prose false-matches
DECLARED=$(sed -n '/[Ff]icheros\|[Ff]iles to [Cc]reate/,/^## /p' "$SPEC_FILE" \
  | grep -E '^[[:space:]]*[-*]' \
  | grep -oE '[a-zA-Z0-9_./\-]+\.[a-z]{1,5}' \
  | sort -u)

if [ -z "$DECLARED" ]; then
  exit 0
fi

MODIFIED=$(modified_files "$PROJECT_ROOT" | sort -u | grep -v '^$' || true)

if [ -z "$MODIFIED" ]; then
  exit 0
fi

# Compare modified vs declared
OUT_OF_SCOPE=""
for FILE in $MODIFIED; do
  BASENAME=$(basename "$FILE")
  MATCH=0
  for DECL in $DECLARED; do
    DECL_BASE=$(basename "$DECL")
    if [ "$FILE" = "$DECL" ] || [ "$BASENAME" = "$DECL_BASE" ]; then
      MATCH=1
      break
    fi
    if echo "$FILE" | grep -qF "$DECL"; then
      MATCH=1
      break
    fi
  done
  if [ "$MATCH" -eq 0 ]; then
    case "$BASENAME" in
      *.spec.md|*.test.*|*Test*|*test*|*.md|*.json|*.yml|*.yaml) continue ;;
      .gitignore|Dockerfile|docker-compose*|*.csproj|*.sln|package.json) continue ;;
    esac
    case "$FILE" in
      */test/*|*/tests/*|*/Test/*|*/Tests/*|*/__tests__/*) continue ;;
      */agent-notes/*|*/adrs/*|*/specs/*|*/output/*) continue ;;
    esac
    OUT_OF_SCOPE="$OUT_OF_SCOPE\n  - $FILE"
  fi
done

if [ -n "$OUT_OF_SCOPE" ]; then
  echo "⚠️ SCOPE GUARD: Ficheros modificados FUERA del scope de la spec activa ($SPEC_FILE):" >&2
  echo -e "$OUT_OF_SCOPE" >&2
  echo "" >&2
  echo "Revisa si estos cambios son intencionales o si el agente expandió el alcance." >&2
  echo "Ficheros declarados en la spec: $(echo "$DECLARED" | tr '\n' ', ')" >&2
  exit 0
fi

exit 0
