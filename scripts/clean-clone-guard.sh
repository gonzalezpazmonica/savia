#!/usr/bin/env bash
# scripts/clean-clone-guard.sh — SE-487 R3: los ficheros versionados que se cargan
# al arrancar no llevan datos de ninguna persona.
#
# Revisa CLAUDE.md, sus @imports versionados, AGENTS.md, .opencode/CLAUDE.md y
# docs/critical-facts.md. Falla si alguno contiene:
#   - un slug de .claude/profiles/users/* distinto de «template» (perfiles locales);
#   - el nombre (identity.md → name:) de esos perfiles locales;
#   - una ruta personal: /home/<x>/, /Users/<x>/ o C:\Users\<x>\;
#   - restos del generador antiguo de critical-facts («profile slug `x`», «activated AAAA-»).
# Las dos últimas reglas no dependen de datos locales: funcionan igual en la CI.
#
# Uso: bash scripts/clean-clone-guard.sh [--root DIR]
# Salida: 0 limpio · 1 hallazgos · 2 error (fichero obligatorio ausente, uso).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; exit 2 ;;
  esac
  shift
done
[[ -d "$ROOT" ]] || { echo "ERROR: --root no es un directorio: $ROOT" >&2; exit 2; }
cd "$ROOT" || exit 2

# ── Ficheros de arranque ─────────────────────────────────────────────────────
REQUIRED=(CLAUDE.md docs/critical-facts.md)
OPTIONAL=(AGENTS.md .opencode/CLAUDE.md)
for f in "${REQUIRED[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: falta el fichero de arranque $f" >&2; exit 2; }
done

is_git=false
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

FOUND=0
report() { echo "FAIL $1: $2"; FOUND=$((FOUND+1)); }

for f in "${FILES[@]}"; do
  for t in "${TERMS[@]}"; do
    if grep -qiwF -- "$t" "$f"; then
      report "$f" "contiene un dato de un perfil local (slug o nombre de .claude/profiles/users/)"
    fi
  done
  while IFS= read -r hit; do
    report "$f" "ruta personal ${hit}"
  done < <(grep -noE '/home/[A-Za-z0-9._-]+/|/Users/[A-Za-z0-9._-]+/|[A-Za-z]:\\+Users\\+[A-Za-z0-9._ -]+\\' "$f" 2>/dev/null | cut -d: -f1 | sed 's/^/en la línea /')
  if grep -qE 'profile slug `|activated [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f"; then
    report "$f" "identidad de una persona activa (formato del generador antiguo de critical-facts)"
  fi
done

if [[ "$FOUND" -gt 0 ]]; then
  echo "clean-clone-guard: $FOUND hallazgo(s). Los datos de la persona van en ficheros locales gitignored (CLAUDE.local.md, perfil activo)." >&2
  exit 1
fi
echo "PASS clean-clone-guard: ${#FILES[@]} ficheros de arranque sin datos personales"
exit 0
