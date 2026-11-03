#!/usr/bin/env bash
# derived.sh — SE-501 (opción B): los derivados (D) no se versionan; se generan bajo demanda.
#
# Uso:
#   derived.sh ensure [--only scm|rules]   genera D en el árbol de trabajo si falta o está desfasado.
#   derived.sh verify [--only scm|rules]   CI: los generadores terminan con 0, su salida pasa su
#                                          validación interna y dos ejecuciones dan la misma salida
#                                          en forma canónica (derived_canon.py). No versiona nada.
#   derived.sh key [--only scm|rules]      imprime la clave de frescura (diagnóstico).
#   derived.sh gate [--base <ref>|--range <a>..<b>] [--repo <dir>]
#                                          G20 y paso de CI «Derived paths absent»: FAIL (1) si el diff de la
#                                          PR añade o modifica una ruta de D, y la nombra. Borrar D pasa.
#                                          La lista D sale de este script; --repo es el repo que se audita
#                                          (la CI ejecuta el derived.sh de la base). Error: 2 (fail-closed).
#
# Grupos (orden fijo: rules antes que scm):
#   rules  rule-manifest-generate.sh + rules-index-generate.sh → docs/rules/INDEX.md, rule-manifest.json
#   scm    generate-capability-map.py + sam.py generate        → .scm/{sam,registry,resources}.json, INDEX.scm, views/, reports/, categories/
#
# Clave de frescura (en <grupo>/.derived-stamp, ignorado por git):
#   sha256(HEAD + HEAD^{tree} + git status --porcelain=v1 -z sin D + hash del contenido de cada fichero
#          listado + blobs de los generadores [+ salidas de rules, para scm]).
#   El sello guarda además un resumen de las salidas del grupo (stamp_body): una salida borrada o editada
#   a mano, también dentro de views/, reports/ o categories/, invalida el sello.
#   Mismo sello y salidas requeridas presentes ⇒ no se ejecuta ningún generador.
# Salida: 0 bien · 1 fallo de generación o de verificación · 2 uso o entorno (fail-closed).
# Importable: «source scripts/derived.sh» solo define la lista cerrada D (derived_paths_load,
# is_derived_path, derived_pathspecs) y vuelve; no fija opciones ni variables del llamante.

# ── Lista cerrada D (scripts/derived-paths.txt) ─────────────────────────────
# Comparación exacta o por prefijo de directorio (entradas acabadas en «/»). Nunca regex.

DERIVED_PATHS=()

# derived_paths_load <raíz> → 0 si la lista existe y no está vacía; 1 si no (fail-closed: quien la usa
# para decidir si algo es derivado no puede seguir sin ella).
derived_paths_load() {
  local f="${1:-.}/scripts/derived-paths.txt" l
  DERIVED_PATHS=()
  [[ -r "$f" ]] || return 1
  while IFS= read -r l || [[ -n "$l" ]]; do
    l="${l%$'\r'}"
    [[ -z "$l" || "$l" == \#* ]] && continue
    DERIVED_PATHS+=("$l")
  done < "$f"
  (( ${#DERIVED_PATHS[@]} > 0 ))
}

# is_derived_path <ruta> → 0 si la ruta es D.
is_derived_path() {
  local p="$1" d
  for d in "${DERIVED_PATHS[@]}"; do
    if [[ "$d" == */ ]]; then [[ "$p" == "$d"* ]] && return 0
    else [[ "$p" == "$d" ]] && return 0; fi
  done
  return 1
}

# derived_pathspecs → las entradas de D como pathspecs literales de git (un prefijo de directorio sin «/»).
derived_pathspecs() {
  local d
  for d in "${DERIVED_PATHS[@]}"; do printf ':(literal)%s\n' "${d%/}"; done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "derived: $1" >&2; exit "${2:-2}"; }

group_gens() {  # generadores obligatorios del grupo
  case "$1" in
    rules) echo "scripts/rule-manifest-generate.sh scripts/rules-index-generate.sh" ;;
    scm)   echo "scripts/generate-capability-map.py scripts/sam.py" ;;
  esac
}
group_code() {  # código que entra en la clave (generadores y sus módulos)
  case "$1" in
    rules) echo "scripts/rule-manifest-generate.sh scripts/rules-index-generate.sh" ;;
    scm)   echo "scripts/generate-capability-map.py scripts/sam.py scripts/sam_model.py scripts/sam_surface.py scripts/sam_trace.py" ;;
  esac
}
group_required() {  # salidas que deben existir tras generar
  case "$1" in
    rules) echo "docs/rules/INDEX.md docs/rules/domain/rule-manifest.json" ;;
    scm)   echo ".scm/sam.json .scm/registry.json .scm/INDEX.scm" ;;
  esac
}
group_stamp() { case "$1" in rules) echo "docs/rules/.derived-stamp" ;; scm) echo ".scm/.derived-stamp" ;; esac; }
group_prefix() { case "$1" in rules) echo "docs/rules/" ;; scm) echo ".scm/" ;; esac; }

group_outputs() {  # group_outputs <grupo> → ficheros de D del grupo presentes en el árbol, ordenados
  local pre d f
  pre=$(group_prefix "$1")
  for d in "${DERIVED_PATHS[@]}"; do
    [[ "$d" == "$pre"* ]] || continue
    if [[ "$d" == */ ]]; then
      [[ -d "$ROOT/$d" ]] && (cd "$ROOT" && find "${d%/}" -type f -print)
    else
      [[ -f "$ROOT/$d" ]] && echo "$d"
    fi
  done | LC_ALL=C sort
  return 0
}

run_gens() {  # run_gens <grupo> → 0 si todos los generadores terminan con 0
  case "$1" in
    rules)
      (cd "$ROOT" && bash scripts/rule-manifest-generate.sh >/dev/null && bash scripts/rules-index-generate.sh >/dev/null) ;;
    scm)
      (cd "$ROOT" && python3 scripts/generate-capability-map.py >/dev/null && python3 scripts/sam.py generate >/dev/null) ;;
  esac
}

preflight() {  # preflight <grupo> → falla cerrado si falta git, python3 o un generador
  local g
  command -v git >/dev/null || die "falta git"
  command -v python3 >/dev/null || die "falta python3"
  git -C "$ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1 || die "$ROOT no es un repositorio git con HEAD"
  for g in $(group_gens "$1"); do
    [[ -f "$ROOT/$g" ]] || { echo "derived: falta el generador $g" >&2; return 1; }
  done
}

key() {  # key <grupo> → clave de frescura
  local g specs=() f xy
  mapfile -t specs < <(derived_pathspecs | sed 's/^:(literal)/:(exclude,literal)/')
  {
    echo "group $1"
    echo "head $(git -C "$ROOT" rev-parse HEAD)"
    echo "tree $(git -C "$ROOT" rev-parse 'HEAD^{tree}')"
    git -C "$ROOT" status --porcelain=v1 -z --untracked-files=all -- . "${specs[@]}" 2>/dev/null
    echo
    # Entradas -z: «XY ruta\0»; en renombrados y copias (X o Y = R/C) sigue la ruta de origen sin prefijo,
    # que se consume aparte. Rutas con espacios o saltos de línea llegan intactas.
    git -C "$ROOT" status --porcelain=v1 -z --untracked-files=all -- . "${specs[@]}" 2>/dev/null \
      | while IFS= read -r -d '' f; do
          xy=${f:0:2}; f=${f:3}
          [[ "$xy" == *[RC]* ]] && IFS= read -r -d '' _
          [[ -f "$ROOT/$f" && ! -L "$ROOT/$f" ]] && printf '%s %s\n' "$(git -C "$ROOT" hash-object -- "$f")" "$f"
        done
    for g in $(group_code "$1"); do
      [[ -f "$ROOT/$g" ]] && printf 'gen %s %s\n' "$(git -C "$ROOT" hash-object -- "$g")" "$g"
    done
    if [[ "$1" == scm ]]; then
      for f in $(group_required rules); do [[ -f "$ROOT/$f" ]] && printf 'in %s %s\n' "$(git -C "$ROOT" hash-object -- "$f")" "$f"; done
    fi
  } | sha256sum | cut -d' ' -f1
}

outputs_present() { local f; for f in $(group_required "$1"); do [[ -f "$ROOT/$f" ]] || return 1; done; }

# stamp_body <grupo> → clave de entradas + resumen de las salidas presentes. Si alguien borra o edita a mano
# una salida (también en views/, reports/ o categories/), el sello deja de coincidir y ensure regenera.
stamp_body() {
  local f
  key "$1"
  printf 'out '
  group_outputs "$1" | while IFS= read -r f; do printf '%s %s\n' "$(sha256sum < "$ROOT/$f" | cut -d' ' -f1)" "$f"; done \
    | sha256sum | cut -d' ' -f1
}

ensure_group() {  # ensure_group <grupo>
  local st k
  preflight "$1" || return 1
  st="$ROOT/$(group_stamp "$1")"
  k=$(stamp_body "$1")
  if outputs_present "$1" && [[ -f "$st" && "$(cat "$st")" == "$k" ]]; then return 0; fi
  run_gens "$1" || { echo "derived: falló la generación de $1" >&2; rm -f "$st"; return 1; }
  outputs_present "$1" || { echo "derived: $1 no produjo todas sus salidas" >&2; rm -f "$st"; return 1; }
  mkdir -p "$(dirname "$st")"
  stamp_body "$1" > "$st"
  echo "derived: $1 generado"
}

# Salidas que el propio generador relee en la siguiente ejecución: sam_model._input_records conserva el
# source_commit de un sam.json previo cuyo contenido coincide. Para medir determinismo, cada ejecución de
# verify parte sin él (se aparta al temporal): así es como genera un clon nuevo. Si una ejecución falla y
# no deja el fichero, al salir se restaura el apartado (restore_prior): verify nunca lo pierde.
group_prior() { case "$1" in scm) echo ".scm/sam.json" ;; esac; }
set_aside_prior() {  # set_aside_prior <grupo> <dir>
  local f
  for f in $(group_prior "$1"); do
    [[ -f "$ROOT/$f" ]] || continue
    mkdir -p "$2/prior/$(dirname "$f")" && mv "$ROOT/$f" "$2/prior/$f" || return 1
  done
}

restore_prior() {  # restore_prior <grupo> <dir> → devuelve al árbol lo apartado que el árbol ya no tiene
  local f
  for f in $(group_prior "$1"); do
    [[ -f "$2/prior/$f" && ! -e "$ROOT/$f" ]] || continue
    mkdir -p "$ROOT/$(dirname "$f")" && cp "$2/prior/$f" "$ROOT/$f"
  done
  return 0
}

snapshot() {  # snapshot <grupo> <dir>
  local f
  group_outputs "$1" > "$2/.list"
  while IFS= read -r f; do mkdir -p "$2/$(dirname "$f")" && cp "$ROOT/$f" "$2/$f" || return 1; done < "$2/.list"
}

verify_group() {  # verify_group <grupo> → 0 generación correcta, válida y determinista
  local t f rc=0 out
  preflight "$1" || return 1
  t=$(mktemp -d) || return 2
  # shellcheck disable=SC2064
  trap "restore_prior '$1' '$t/a'; rm -rf '$t'; trap - RETURN" RETURN
  mkdir -p "$t/a" "$t/b"
  set_aside_prior "$1" "$t/a" || return 1
  run_gens "$1" || { echo "FAIL $1: un generador terminó con ≠ 0"; return 1; }
  outputs_present "$1" || { echo "FAIL $1: faltan salidas tras generar"; return 1; }
  while IFS= read -r f; do
    python3 "$ROOT/scripts/derived_canon.py" validate "$f" "$ROOT/$f" || { echo "FAIL $1: $f no pasa su validación"; rc=1; }
  done < <(group_outputs "$1")
  if [[ "$1" == scm ]]; then
    out=$(cd "$ROOT" && python3 scripts/sam.py check 2>&1)
    [[ "$out" == *"SAM: FRESH"* ]] || { echo "FAIL scm: sam.py check sobre lo generado: $out"; rc=1; }
  fi
  snapshot "$1" "$t/a" || return 1
  set_aside_prior "$1" "$t/b" || return 1
  run_gens "$1" || { echo "FAIL $1: la segunda ejecución terminó con ≠ 0"; return 1; }
  snapshot "$1" "$t/b" || return 1
  cmp -s "$t/a/.list" "$t/b/.list" || { echo "FAIL $1: las dos ejecuciones producen ficheros distintos"; return 1; }
  while IFS= read -r f; do
    python3 "$ROOT/scripts/derived_canon.py" same "$f" "$t/a/$f" "$t/b/$f" \
      || { echo "FAIL $1: $f no es determinista (forma canónica)"; rc=1; }
  done < "$t/a/.list"
  (( rc == 0 )) && echo "PASS $1: generación correcta, válida y determinista ($(wc -l < "$t/a/.list") ficheros)"
  return $rc
}

gate_cmd() {  # gate_cmd [--base <ref>] [--range <a>..<b>] [--repo <dir>]
  local base="origin/main" range="" repo="$ROOT" mb names f bad=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) base="${2:-}"; shift 2 ;;
      --range) range="${2:-}"; shift 2 ;;
      --repo) repo="$(cd "${2:-}" 2>/dev/null && pwd)" || die "G20 ERROR: --repo ilegible"; shift 2 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
  derived_paths_load "$ROOT" || die "G20 ERROR: falta o está vacía scripts/derived-paths.txt"
  if [[ -z "$range" ]]; then
    mb=$(git -C "$repo" merge-base "$base" HEAD 2>/dev/null) || die "G20 ERROR: sin merge-base con $base"
    range="$mb..HEAD"
  fi
  # --diff-filter=d: excluye borrados. -z: rutas sin escapar.
  names=$(git -C "$repo" diff --name-only --no-renames --diff-filter=d -z "$range" 2>/dev/null | tr '\0' '\n') \
    || die "G20 ERROR: git no pudo calcular el diff $range"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    is_derived_path "$f" && bad+=("$f")
  done <<<"$names"
  if (( ${#bad[@]} )); then
    echo "G20 FAIL: la PR versiona derivados que se generan en local (SE-501):"
    printf '  %s\n' "${bad[@]}"
    echo "Arreglo: bash scripts/derived-drop.sh"
    return 1
  fi
  echo "G20 PASS: ninguna ruta derivada en el diff ($range)"
}

CMD="${1:-}"; shift || true
[[ "$CMD" == gate ]] && { gate_cmd "$@"; exit $?; }
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    *) die "argumento desconocido: $1" ;;
  esac
done
case "$ONLY" in ""|scm|rules) ;; *) die "--only admite scm o rules" ;; esac
GROUPS_SEL="rules scm"; [[ -n "$ONLY" ]] && GROUPS_SEL="$ONLY"
derived_paths_load "$ROOT" || die "falta o está vacía scripts/derived-paths.txt"

rc=0
lock() {  # Un solo ensure/verify a la vez por árbol (session-init en segundo plano, lectores, CI en paralelo).
  # El cerrojo vive en el directorio de git: dentro del árbol cambiaría la clave de frescura.
  command -v flock >/dev/null || return 0
  local lk
  lk=$(git -C "$ROOT" rev-parse --path-format=absolute --git-path savia-derived.lock 2>/dev/null) || die "sin directorio de git"
  exec 9>"$lk" || die "no se puede abrir el cerrojo $lk"
  flock -w 300 9 || die "otro derived.sh no terminó en 300 s" 1
}

case "$CMD" in
  ensure)
    lock
    for g in $GROUPS_SEL; do ensure_group "$g" || rc=1; done ;;
  verify)
    lock
    for g in $GROUPS_SEL; do verify_group "$g" || rc=1; done ;;
  key)
    for g in $GROUPS_SEL; do echo "$g $(key "$g")"; done ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
exit $rc
