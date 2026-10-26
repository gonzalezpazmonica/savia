#!/usr/bin/env bash
# contract-pin.sh — SE-369 Contract Digest Pins
# Versionado inmutable de contratos (hooks, settings, skills): cada contrato
# lleva su sha256 canónico publicado. Cambio de contrato = bump de versión + nuevo pin.
#
# Principios (SE-369):
#   1. Digest pin por contrato (sha256:<hex> del fichero).
#   2. Compat sin autoridad: las versiones previas se leen en modo compat
#      (authoritative=false) y NUNCA vuelven a ser canónicas.
#   3. Rechazo explícito: un consumidor con schema antiguo rechaza y nombra
#      el upgrade ("requiere upgrade a <versión>").
#   4. Aditivo estricto: campos nuevos OK; campos conocidos byte-idénticos
#      al encoding canónico (jq -S), si no → breaking, exige bump.
#   5. CRIT-001: todo local, catálogo en el repo.
#
# Uso:
#   contract-pin.sh pin <name> --path <file> [--version <v>]   # pinear/bump digest
#   contract-pin.sh check <name> [--path <file>]               # fichero == pin actual
#   contract-pin.sh compat <name> [--version <v>]              # versiones previas compat
#   contract-pin.sh accept <name> --schema <v>                 # gate de consumidor
#   contract-pin.sh additive-check --base <json> --new <json>  # cambio aditivo estricto
#   contract-pin.sh list                                       # listar contratos pineados
#   contract-pin.sh --validate                                 # consistencia del catálogo
#
# Catálogo: config/contract-digests.json (override: $CONTRACT_DIGESTS_FILE)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CATALOG="${CONTRACT_DIGESTS_FILE:-$REPO_ROOT/config/contract-digests.json}"
# shellcheck source=lib/os-detect.sh
source "$SCRIPT_DIR/lib/os-detect.sh"

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { echo "ERROR: $*" >&2; exit 1; }

require_jq() { command -v jq >/dev/null 2>&1 || die "jq requerido (SE-369)"; }
require_catalog() { [ -f "$CATALOG" ] || die "catálogo no encontrado: $CATALOG (usa 'pin' para crearlo)"; }
catalog_has_contract() {
  [ -f "$CATALOG" ] && [ "$(jq -r --arg n "$1" 'has($n)' "$CATALOG")" = "true" ]
}
is_int() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
digest_of() { printf 'sha256:%s' "$(sha256sum "$1" | cut -d' ' -f1)"; }

# ── pin ───────────────────────────────────────────────────────────────────────

cmd_pin() {
  local name="" path="" ver=""
  name="${1:-}"
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --path) path="${2:-}"; shift 2 ;;
      --version) ver="${2:-}"; shift 2 ;;
      *) die "pin: argumento desconocido: $1" ;;
    esac
  done
  [ -n "$name" ] || die "pin: <name> requerido"
  [ -n "$path" ] || die "pin: --path requerido"
  [ -f "$path" ] || die "pin: fichero no encontrado: $path"
  [ -z "$ver" ] || is_int "$ver" || die "pin: --version debe ser entero positivo"
  require_jq

  local dg
  dg="$(digest_of "$path")"
  mkdir -p "$(dirname "$CATALOG")"
  [ -f "$CATALOG" ] || printf '{}\n' > "$CATALOG"

  if catalog_has_contract "$name"; then
    local cur_dg max_ver new_ver tmp
    cur_dg="$(jq -r --arg n "$name" '.[$n].current.digest // ""' "$CATALOG")"
    if [ -n "$cur_dg" ] && [ "$cur_dg" = "$dg" ]; then
      echo "OK: $name ya pineado como current ($dg) — sin bump"
      return 0
    fi
    # Principio 2: una versión previa NUNCA recupera autoridad
    if jq -e --arg n "$name" --arg d "$dg" \
        '[(.[$n].previous // [])[] | select(.digest == $d)] | length > 0' \
        "$CATALOG" >/dev/null; then
      die "pin: el digest coincide con una versión previa de $name — una versión previa nunca recupera autoridad; el bump exige contenido nuevo"
    fi
    max_ver="$(jq -r --arg n "$name" \
      '([.[$n].current.version] + [.[$n].previous[]?.version] | map(select(. != null)) | max // 0)' \
      "$CATALOG")"
    new_ver=$((max_ver + 1))
    if [ -n "$ver" ]; then
      [ "$ver" -gt "$max_ver" ] || die "pin: --version $ver debe ser > $max_ver (una versión vieja nunca recupera autoridad)"
      new_ver="$ver"
    fi
    tmp="$(mktemp)"
    jq --arg n "$name" --arg d "$dg" --arg p "$path" --argjson v "$new_ver" '
      if (.[$n].current | type) == "object" then
        .[$n].previous = ((.[$n].previous // []) + [(.[$n].current + {compat: true, authoritative: false})])
      else
        .[$n].previous = (.[$n].previous // [])
      end
      | .[$n].current = {version: $v, digest: $d, path: $p}
    ' "$CATALOG" > "$tmp"
    mv "$tmp" "$CATALOG"
    echo "PINNED: $name v$new_ver ($dg) — current anterior movido a previous (compat, authoritative=false)"
  else
    local v=1 tmp
    [ -n "$ver" ] && v="$ver"
    tmp="$(mktemp)"
    jq --arg n "$name" --arg d "$dg" --arg p "$path" --argjson v "$v" \
      '.[$n] = {current: {version: $v, digest: $d, path: $p}, previous: []}' \
      "$CATALOG" > "$tmp"
    mv "$tmp" "$CATALOG"
    echo "PINNED: $name v$v ($dg) — contrato nuevo"
  fi
}

# ── check ─────────────────────────────────────────────────────────────────────

cmd_check() {
  local name="" path_override=""
  name="${1:-}"
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --path) path_override="${2:-}"; shift 2 ;;
      *) die "check: argumento desconocido: $1" ;;
    esac
  done
  [ -n "$name" ] || die "check: <name> requerido"
  require_jq
  require_catalog
  catalog_has_contract "$name" || die "check: contrato no pineado: $name"

  local cur path dg
  cur="$(jq -r --arg n "$name" '.[$n].current.digest // empty' "$CATALOG")"
  [ -n "$cur" ] || die "check: $name sin current"
  if [ -n "$path_override" ]; then
    path="$path_override"
  else
    path="$(jq -r --arg n "$name" '.[$n].current.path // empty' "$CATALOG")"
  fi
  [ -n "$path" ] || die "check: sin path (catálogo o --path)"

  if [ ! -f "$path" ]; then
    echo "FAIL: $name — fichero ausente: $path"
    return 1
  fi
  dg="$(digest_of "$path")"
  if [ "$dg" = "$cur" ]; then
    echo "OK: $name digest verificado ($dg)"
    return 0
  fi
  echo "FAIL: $name cambió sin bump (pin=$cur, actual=$dg). Ejecuta: contract-pin.sh pin $name --path $path"
  return 1
}

# ── compat ────────────────────────────────────────────────────────────────────

cmd_compat() {
  local name="" want=""
  name="${1:-}"
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) want="${2:-}"; shift 2 ;;
      *) die "compat: argumento desconocido: $1" ;;
    esac
  done
  [ -n "$name" ] || die "compat: <name> requerido"
  [ -z "$want" ] || is_int "$want" || die "compat: --version debe ser entero"
  require_jq
  require_catalog
  catalog_has_contract "$name" || die "compat: contrato no pineado: $name"

  if [ -n "$want" ]; then
    local cur_ver entry
    cur_ver="$(jq -r --arg n "$name" '.[$n].current.version // empty' "$CATALOG")"
    if [ -n "$cur_ver" ] && [ "$want" = "$cur_ver" ]; then
      echo "CURRENT: v$want es la versión canónica de $name (no previa)"
      return 0
    fi
    entry="$(jq -r --arg n "$name" --argjson v "$want" \
      '[(.[$n].previous // [])[] | select(.version == $v)][0] // empty' "$CATALOG")"
    if [ -z "$entry" ]; then
      echo "NO-COMPAT: $name v$want no está entre las versiones previas"
      return 1
    fi
    local compat auth
    compat="$(jq -r '.compat // false' <<<"$entry")"
    auth="$(jq -r '.authoritative // false' <<<"$entry")"
    if [ "$compat" = "true" ]; then
      echo "COMPAT: $name v$want legible en modo compat (authoritative=$auth) — nunca recupera autoridad"
      return 0
    fi
    echo "NO-COMPAT: $name v$want marcada compat=$compat"
    return 1
  fi

  local n
  n="$(jq -r --arg n "$name" '[(.[$n].previous // [])[]] | length' "$CATALOG")"
  echo "COMPAT: versiones previas de $name (compat, sin autoridad): $n"
  jq -r --arg n "$name" \
    '.[$n].previous[]? | "  v\(.version)\t\(.digest)\tcompat=\(.compat)\tauthoritative=\(.authoritative)"' \
    "$CATALOG"
  return 0
}

# ── accept (gate de consumidor, SE-369 §4.3) ─────────────────────────────────

cmd_accept() {
  local name="" schema=""
  name="${1:-}"
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --schema) schema="${2:-}"; shift 2 ;;
      *) die "accept: argumento desconocido: $1" ;;
    esac
  done
  [ -n "$name" ] || die "accept: <name> requerido"
  is_int "$schema" || die "accept: --schema entero requerido"
  require_jq
  require_catalog
  catalog_has_contract "$name" || die "accept: contrato no pineado: $name"

  local cur
  cur="$(jq -r --arg n "$name" '.[$n].current.version // empty' "$CATALOG")"
  [ -n "$cur" ] || die "accept: $name sin current"

  if [ "$schema" -lt "$cur" ]; then
    echo "RECHAZADO: consumidor $name con schema v$schema obsoleto (current v$cur) — requiere upgrade a $cur. No se interpretan campos nuevos a ciegas." >&2
    return 1
  fi
  if [ "$schema" -gt "$cur" ]; then
    echo "RECHAZADO: consumidor $name con schema v$schema desconocido para el catálogo (current v$cur) — actualiza el pin con 'pin'." >&2
    return 1
  fi
  echo "OK: consumidor $name v$schema == current v$cur"
  return 0
}

# ── additive-check (SE-369 principio 4) ───────────────────────────────────────

cmd_additive() {
  local base="" newf=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) base="${2:-}"; shift 2 ;;
      --new) newf="${2:-}"; shift 2 ;;
      *) die "additive-check: argumento desconocido: $1" ;;
    esac
  done
  [ -n "$base" ] || die "additive-check: --base requerido"
  [ -n "$newf" ] || die "additive-check: --new requerido"
  [ -f "$base" ] || die "additive-check: fichero no encontrado: $base"
  [ -f "$newf" ] || die "additive-check: fichero no encontrado: $newf"
  require_jq

  local t1 t2
  t1="$(mktemp)"
  t2="$(mktemp)"
  jq -S . "$base" > "$t1" 2>/dev/null || { rm -f "$t1" "$t2"; die "additive-check: base no es JSON válido"; }
  jq -S . "$newf" > "$t2" 2>/dev/null || { rm -f "$t1" "$t2"; die "additive-check: new no es JSON válido"; }

  # Canonical encoding (jq -S): comparación byte-idéntica por campo conocido
  local report
  report="$(jq -c -n --slurpfile b "$t1" --slurpfile n "$t2" '
    $b[0] as $B | $n[0] as $N
    | {missing: [($B | keys[]) as $k | select(($N | has($k)) | not) | $k],
       changed: [($B | keys[]) as $k | select($N | has($k)) |
                select(($B[$k] | tojson) != ($N[$k] | tojson)) | $k],
       added:   [($N | keys[]) as $k | select(($B | has($k)) | not) | $k]}
  ')"
  rm -f "$t1" "$t2"

  local missing changed added
  missing="$(jq -r '.missing | join(", ")' <<<"$report")"
  changed="$(jq -r '.changed | join(", ")' <<<"$report")"
  added="$(jq -r '.added | join(", ")' <<<"$report")"

  if [ -n "$missing" ] || [ -n "$changed" ]; then
    [ -n "$changed" ] && echo "BREAKING: campos conocidos modificados (no byte-idénticos al encoding canónico): $changed"
    [ -n "$missing" ] && echo "BREAKING: campos conocidos ausentes: $missing"
    echo "BREAKING: exige bump de versión (pin)"
    return 1
  fi
  echo "ADITIVO: campos conocidos byte-idénticos; añadidos: ${added:-ninguno}"
  return 0
}

# ── list ──────────────────────────────────────────────────────────────────────

cmd_list() {
  require_jq
  require_catalog
  echo "CONTRATOS pineados en $CATALOG:"
  jq -r 'to_entries[] | "  \(.key)\tv\(.value.current.version)\t\(.value.current.digest)\t\(.value.current.path)"' "$CATALOG"
}

# ── validate ──────────────────────────────────────────────────────────────────

cmd_validate() {
  require_jq
  require_catalog
  jq -e 'type == "object"' "$CATALOG" >/dev/null 2>&1 \
    || die "validate: catálogo no es un objeto JSON válido: $CATALOG"

  local violations=() count=0
  local name cur_type ver_type dg path pt pv pdg pc pa cv dups
  while IFS= read -r name; do
    count=$((count + 1))
    cur_type="$(jq -r --arg n "$name" '.[$n].current | type' "$CATALOG")"
    if [ "$cur_type" != "object" ]; then
      violations+=("$name: debe tener exactamente un current (objeto); encontrado: $cur_type")
      continue
    fi
    ver_type="$(jq -r --arg n "$name" '.[$n].current.version | type' "$CATALOG")"
    if [ "$ver_type" != "number" ]; then
      violations+=("$name: current.version debe ser número (encontrado: $ver_type)")
    fi
    dg="$(jq -r --arg n "$name" '.[$n].current.digest // ""' "$CATALOG")"
    [[ "$dg" =~ ^sha256:[0-9a-f]{64}$ ]] || violations+=("$name: current.digest malformado: '$dg'")
    path="$(jq -r --arg n "$name" '.[$n].current.path // ""' "$CATALOG")"
    [ -n "$path" ] || violations+=("$name: current.path ausente")

    pt="$(jq -r --arg n "$name" '.[$n].previous | type' "$CATALOG")"
    if [ "$pt" != "array" ]; then
      violations+=("$name: previous debe ser array (encontrado: $pt)")
    else
      while IFS=$'\t' read -r pv pdg pc pa; do
        [[ "$pv" =~ ^[0-9]+$ ]] || violations+=("$name: previous.version no numérico ($pv)")
        [[ "$pdg" =~ ^sha256:[0-9a-f]{64}$ ]] || violations+=("$name: previous.digest malformado ($pdg)")
        if [ "$pc" != "true" ]; then
          violations+=("$name: previous v$pv debe tener compat=true")
        fi
        if [ "$pa" != "false" ]; then
          violations+=("$name: previous v$pv debe tener authoritative=false (una versión vieja nunca recupera autoridad)")
        fi
        if [[ "$pv" =~ ^[0-9]+$ ]]; then
          cv="$(jq -r --arg n "$name" '.[$n].current.version' "$CATALOG")"
          [ "$pv" -lt "$cv" ] || violations+=("$name: previous v$pv >= current v$cv")
        fi
      done < <(jq -r --arg n "$name" \
        '(.[$n].previous // [])[] | [.version, (.digest // ""), ((.compat // false)|tostring), ((.authoritative // false)|tostring)] | @tsv' \
        "$CATALOG")
      dups="$(jq -r --arg n "$name" \
        '[(.[$n].previous // []) | map(.version) | group_by(.) | .[] | select(length > 1)] | length' \
        "$CATALOG")"
      if [ "$dups" != "0" ]; then
        violations+=("$name: versiones previous duplicadas")
      fi
    fi
  done < <(jq -r 'keys[]' "$CATALOG")

  if [ "${#violations[@]}" -gt 0 ]; then
    echo "INVALID: catálogo inconsistente (${#violations[@]} violaciones):"
    local v
    for v in "${violations[@]}"; do
      echo "  - $v"
    done
    return 1
  fi
  echo "VALID: catálogo consistente ($count contratos)"
  return 0
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  local cmd="${1:-}"
  if [ -z "$cmd" ]; then
    usage
    exit 1
  fi
  case "$cmd" in
    pin) shift; cmd_pin "$@" ;;
    check) shift; cmd_check "$@" ;;
    compat) shift; cmd_compat "$@" ;;
    accept) shift; cmd_accept "$@" ;;
    additive-check) shift; cmd_additive "$@" ;;
    list) shift; cmd_list "$@" ;;
    --validate|validate) shift; cmd_validate "$@" ;;
    help|-h|--help) usage ;;
    *) usage >&2; die "comando desconocido: $cmd" ;;
  esac
}

main "$@"
