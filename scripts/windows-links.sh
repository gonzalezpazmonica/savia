#!/bin/bash
# windows-links.sh — Materializa en Windows los enlaces Git (modo 120000).
# Uso: bash scripts/windows-links.sh [check|repair] [--quiet]
#
# Con core.symlinks=false, Git para Windows extrae cada enlace como un fichero de
# texto con la ruta destino (`.opencode/hooks` contiene "../.claude/hooks"). Todo
# lo que atraviesa esa ruta falla con "Not a directory": hooks de Claude Code,
# plugins de OpenCode, scripts y tests.
#
#   check  : informa del estado; exit 1 si algún enlace no está materializado.
#   repair : directorio → junction; fichero → hard link. Corrige junctions que
#            apuntan a otro clon. Marca skip-worktree para que git status siga
#            limpio. Idempotente.
#
# El destino se lee del índice (blob comprometido), nunca del fichero de trabajo,
# y debe ser una ruta relativa POSIX que resuelva dentro del repositorio. Un
# directorio real o un fichero con contenido ajeno en la ruta del enlace no se
# toca: se informa como conflicto.
# Fuera de Windows, o con symlinks nativos, es un no-op (exit 0).
# Sin subshells por entrada: en MSYS cada fork cuesta ~50-100 ms.
# Exit: 0 ok/no aplica · 1 enlaces pendientes o conflicto · 2 uso inválido.

set -uo pipefail

MODE=check QUIET=false
for arg in "$@"; do
  case "$arg" in
    check|repair) MODE="$arg" ;;
    --quiet) QUIET=true ;;
    *) echo "Uso: $0 [check|repair] [--quiet]" >&2; exit 2 ;;
  esac
done

say() { $QUIET || printf '%s\n' "$*"; }

case "${OSTYPE:-}" in
  msys*|cygwin*) ;;
  *) say "windows-links: no aplica (no es Windows)"; exit 0 ;;
esac

# Raíz = padre físico de scripts/ (también si se invoca vía .opencode/scripts).
_dir="${BASH_SOURCE[0]%/*}"; [ "$_dir" = "${BASH_SOURCE[0]}" ] && _dir=.
cd -P "$_dir/.." 2>/dev/null && [ -e .git ] || { echo "windows-links: fuera de un repositorio git" >&2; exit 2; }
ROOT="$PWD"

# mklink y rmdir son internos de cmd; sin conversión de argumentos MSYS para que
# las rutas Windows con espacios lleguen intactas.
win_cmd() { MSYS2_ARG_CONV_EXCL='*' cmd /c "$@" >/dev/null 2>&1; }

# Destino válido: no vacío, sin control/backslash/dos puntos, relativo y sin
# componentes vacíos. Los ".." se permiten; la pertenencia a ROOT se comprueba después.
valid_target() {
  local t="$1"
  [ -n "$t" ] || return 1
  [[ "$t" == *[[:cntrl:]]* || "$t" == *\\* || "$t" == *:* ]] && return 1
  case "$t" in /*|*//*|*/) return 1 ;; esac
  return 0
}

# Normalización léxica de una ruta absoluta (resuelve "." y ".."). Deja el resultado en NORM.
normalize() {
  local IFS=/ part out=()
  for part in $1; do
    case "$part" in
      ''|.) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  NORM="/${out[*]}"
}

# Ruta física (sin enlaces) de un directorio existente, sin subshell. Deja el resultado en PHYS.
physical_dir() { PHYS=""; cd -P "$1" 2>/dev/null && PHYS="$PWD"; cd "$ROOT"; }

inside_root() { case "$1" in "$ROOT"/*) return 0 ;; *) return 1 ;; esac; }

read_text() { TEXT=""; IFS= read -r -d '' TEXT < "$1" 2>/dev/null; }

# Inventario: enlaces del índice y sus destinos en una sola llamada a cat-file.
rels=() oids=()
while IFS= read -r -d '' entry; do
  meta="${entry%%$'\t'*}"; mode="${meta%% *}"; oid="${meta#* }"; stage="${oid#* }"; oid="${oid%% *}"
  [ "$mode" = "120000" ] && [ "$stage" = "0" ] || continue
  rels+=("${entry#*$'\t'}"); oids+=("$oid")
done < <(git ls-files -s -z | grep -z '^120000 ')
[ ${#rels[@]} -gt 0 ] || { say "windows-links: sin enlaces en el índice"; exit 0; }

targets=()
while IFS=' ' read -r _oid _type size; do
  LC_ALL=C IFS= read -r -N "$size" body; IFS= read -r _   # -N cuenta bytes solo en locale C
  targets+=("$body")
done < <(printf '%s\n' "${oids[@]}" | git cat-file --batch)

pending=0 repaired=0 conflicts=0
conflict() { say "CONFLICT $1: $2"; conflicts=$((conflicts+1)); }

for i in "${!rels[@]}"; do
  rel="${rels[$i]}" target="${targets[$i]:-}"
  link="$ROOT/$rel" parent="$ROOT/${rel%/*}"
  [ "$rel" = "${rel%/*}" ] && parent="$ROOT"

  valid_target "$target" || { conflict "$rel" "destino no permitido"; continue; }
  normalize "$parent/$target"; abs="$NORM"
  inside_root "$abs" || { conflict "$rel" "destino fuera del repositorio"; continue; }
  [ -e "$abs" ] || { say "SKIP     $rel: destino inexistente ($target)"; continue; }
  if [ -d "$abs" ]; then physical_dir "$abs"; abs_real="$PHYS"
  else physical_dir "${abs%/*}"; abs_real="$PHYS/${abs##*/}"
  fi
  inside_root "$abs_real" || { conflict "$rel" "destino resuelve fuera del repositorio"; continue; }

  if [ -d "$abs_real" ]; then
    if [ -L "$link" ]; then
      physical_dir "$link"
      if [ -n "$PHYS" ] && [ "$PHYS" = "$abs_real" ]; then state=ok; else state=stale; fi
    elif [ -d "$link" ]; then state=realdir
    elif [ -f "$link" ]; then
      read_text "$link"; if [ "$TEXT" = "$target" ]; then state=textlink; else state=foreign; fi
    else state=missing
    fi
  else
    if [ -L "$link" ]; then state=stale
    elif [ -f "$link" ]; then
      read_text "$link"
      if [ "$link" -ef "$abs_real" ]; then state=ok
      elif [ "$TEXT" = "$target" ] || cmp -s "$link" "$abs_real"; then state=textlink
      else state=foreign
      fi
    elif [ -e "$link" ]; then state=foreign
    else state=missing
    fi
  fi

  case "$state" in
    ok) [ "$MODE" = "repair" ] && git update-index --skip-worktree -- "$rel" 2>/dev/null; continue ;;
    realdir|foreign) conflict "$rel" "ocupado por contenido que no es el enlace; revisar a mano"; continue ;;
  esac
  if [ "$MODE" = "check" ]; then
    say "PENDING  $rel ($state) -> $target"; pending=$((pending+1)); continue
  fi

  link_w="$(cygpath -w "$link")" abs_w="$(cygpath -w "$abs_real")"
  case "$state" in
    stale)    win_cmd rmdir "$link_w" || rm -f "$link" ;;
    textlink) rm -f "$link" ;;
  esac
  if [ -d "$abs_real" ]; then win_cmd mklink /J "$link_w" "$abs_w"; else win_cmd mklink /H "$link_w" "$abs_w"; fi
  if [ -e "$link" ]; then
    git update-index --skip-worktree -- "$rel" 2>/dev/null
    say "REPAIRED $rel -> $target"; repaired=$((repaired+1))
  else
    # Restaurar el textlink para no dejar el árbol peor que estaba.
    git checkout -- "$rel" 2>/dev/null
    conflict "$rel" "no se pudo crear el enlace"
  fi
done

say "windows-links: repaired=$repaired pending=$pending conflicts=$conflicts"
[ $((pending + conflicts)) -eq 0 ]
