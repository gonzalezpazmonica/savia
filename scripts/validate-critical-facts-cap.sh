#!/usr/bin/env bash
# scripts/validate-critical-facts-cap.sh
# SPEC-185: Validates docs/critical-facts.md is <= 150 tokens between markers.
# Exit 1 if cap exceeded; exit 0 if under cap.
# Token approximation: words * 1.3 (good for Spanish/English mixed text).
#
# --clean-clone [--root DIR] — SE-487 R3: los ficheros versionados que se cargan
# al arrancar no llevan datos de ninguna persona. Revisa CLAUDE.md, sus @imports
# versionados, AGENTS.md, .opencode/CLAUDE.md y docs/critical-facts.md. Falla si
# alguno contiene:
#   - un slug de .claude/profiles/users/* distinto de «template» (perfiles locales);
#   - el nombre (identity.md → name:) de esos perfiles locales;
#   - una ruta personal: /home/<x>/, /Users/<x>/ o C:\Users\<x>\;
#   - restos del generador antiguo de critical-facts («profile slug `x`», «activated AAAA-»).
# Las dos últimas reglas no dependen de datos locales: funcionan igual en la CI.
# Fuera de un repo git se revisan todos los @imports existentes.
# Salida: 0 limpio · 1 hallazgos · 2 error (fichero obligatorio ausente, uso).

set -uo pipefail

# ── SE-487: modo --clean-clone ───────────────────────────────────────────────
_cc_report() { echo "FAIL $1: $2"; FOUND=$((FOUND+1)); }
clean_clone_guard() {
  local ROOT f imp d slug name t hit is_git=false FOUND=0
  local -a REQUIRED OPTIONAL FILES TERMS
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) ROOT="${2:-}"; shift ;;
      *) echo "ERROR: argumento desconocido: $1" >&2; return 2 ;;
    esac
    shift
  done
  [[ -d "$ROOT" ]] || { echo "ERROR: --root no es un directorio: $ROOT" >&2; return 2; }
  cd "$ROOT" || return 2

  # ── Ficheros de arranque ─────────────────────────────────────────────────────
  REQUIRED=(CLAUDE.md docs/critical-facts.md)
  OPTIONAL=(AGENTS.md .opencode/CLAUDE.md)
  for f in "${REQUIRED[@]}"; do
    [[ -f "$f" ]] || { echo "ERROR: falta el fichero de arranque $f" >&2; return 2; }
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_git=true

  FILES=("${REQUIRED[@]}")
  for f in "${OPTIONAL[@]}"; do [[ -f "$f" ]] && FILES+=("$f"); done
  # @imports de CLAUDE.md: los gitignored (perfil activo, memoria local) son locales por diseño.
  while IFS= read -r imp; do
    [[ -f "$imp" ]] || continue
    if $is_git && git check-ignore -q "$imp" 2>/dev/null; then continue; fi
    [[ " ${FILES[*]} " == *" $imp "* ]] && continue
    FILES+=("$imp")
  done < <(sed -n 's/^@\([^[:space:]]*\).*/\1/p' CLAUDE.md)

  # ── Datos de perfiles locales ────────────────────────────────────────────────
  TERMS=()
  if [[ -d .claude/profiles/users ]]; then
    for d in .claude/profiles/users/*/; do
      [[ -d "$d" ]] || continue
      slug="$(basename "$d")"
      [[ "$slug" == "template" ]] && continue
      TERMS+=("$slug")
      name="$(awk '/^name:/{sub(/^name:[[:space:]]*/,""); gsub(/["]/,""); print; exit}' "$d/identity.md" 2>/dev/null)"
      [[ -n "$name" ]] && TERMS+=("$name")
    done
  fi

  for f in "${FILES[@]}"; do
    for t in ${TERMS[@]+"${TERMS[@]}"}; do
      if grep -qiwF -- "$t" "$f"; then
        _cc_report "$f" "contiene un dato de un perfil local (slug o nombre de .claude/profiles/users/)"
      fi
    done
    while IFS= read -r hit; do
      _cc_report "$f" "ruta personal ${hit}"
    done < <(grep -noE '/home/[A-Za-z0-9._-]+/|/Users/[A-Za-z0-9._-]+/|[A-Za-z]:\\+Users\\+[A-Za-z0-9._ -]+\\' "$f" 2>/dev/null | cut -d: -f1 | sed 's/^/en la línea /')
    if grep -qE 'profile slug `|activated [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f"; then
      _cc_report "$f" "identidad de una persona activa (formato del generador antiguo de critical-facts)"
    fi
  done

  if [[ "$FOUND" -gt 0 ]]; then
    echo "clean-clone: $FOUND hallazgo(s). Los datos de la persona van en ficheros locales gitignored (CLAUDE.local.md, perfil activo)." >&2
    return 1
  fi
  echo "PASS clean-clone: ${#FILES[@]} ficheros de arranque sin datos personales"
  return 0
}

if [[ "${1:-}" == "--clean-clone" ]]; then
  shift
  clean_clone_guard "$@"
  exit $?
fi

FILE="${1:-docs/critical-facts.md}"
CAP="${CRITICAL_FACTS_TOKEN_CAP:-150}"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: $FILE not found" >&2
  exit 1
fi

# Verify markers exist
if ! grep -q "CRITICAL_FACTS_START" "$FILE" || ! grep -q "CRITICAL_FACTS_END" "$FILE"; then
  echo "ERROR: markers <!-- CRITICAL_FACTS_START --> / <!-- CRITICAL_FACTS_END --> not found in $FILE" >&2
  exit 1
fi

# Extract content between markers
CONTENT=$(awk '/<!-- CRITICAL_FACTS_START -->/{flag=1; next} /<!-- CRITICAL_FACTS_END -->/{flag=0} flag' "$FILE")

WORDS=$(echo "$CONTENT" | wc -w)
# Approximate token count: words * 1.3 (rounded up via integer math)
TOKENS=$(( (WORDS * 13 + 9) / 10 ))

if [[ "$TOKENS" -gt "$CAP" ]]; then
  echo "FAIL: $FILE has ~$TOKENS tokens ($WORDS words), cap=$CAP" >&2
  echo ""
  echo "Suggested removals (lowest priority first):"
  echo "  - Drop 'Tono' line if Rule 24 already in CLAUDE.md"
  echo "  - Compress 'Gates inmutables' to ID-only refs"
  echo "  - Remove 'Frontend' if not relevant to current task"
  exit 1
fi

echo "OK: $FILE = ~$TOKENS tokens ($WORDS words), cap=$CAP"
exit 0
