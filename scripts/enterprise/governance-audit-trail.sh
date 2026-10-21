#!/usr/bin/env bash
# governance-audit-trail.sh — SPEC-SE-006 Hash-chained Audit Trail for Governance & Compliance
set -uo pipefail
#
# Gestiona el audit trail encadenado por hashes para compliance Enterprise.
#
# Subcomandos:
#   append --tenant SLUG --actor USER --action ACTION [--spec SPEC]
#       → Añade una entrada JSONL canónica al trail del tenant (bajo lock)
#   verify --file PATH [--anchor HASH] [--tenant SLUG]
#       → Verifica formato canónico, enlace prev_hash, hash, orden temporal
#         y (con --tenant) que cada entrada sea de ese tenant
#   export --tenant SLUG --format md|json
#       → Exporta el trail para auditores externos
#   chain-status [--tenant SLUG]
#       → Muestra el último hash (para anclarlo fuera) y el nº de entradas
#
# Hash: sha256 de los campos ts, tenant, actor, action, spec y prev_hash,
# uno por línea (los campos no admiten saltos de línea, así la frontera entre
# campos no es ambigua). prev_hash es el hash hexadecimal de la entrada previa.
# Almacena: ${CLAUDE_ENTERPRISE_AUDIT_BASE:-.claude/enterprise/audit}/{tenant}/audit-trail.jsonl
#
# Límite honesto: sha256 sin clave. Quien pueda escribir el fichero puede
# recalcular la cadena entera. La detección de truncado o reescritura completa
# exige anclar fuera del fichero un hash publicado por chain-status y pasarlo
# a verify --anchor; el ancla solo protege hasta la entrada anclada.
#
# Reference: SPEC-SE-006 (docs/propuestas/savia-enterprise/SPEC-SE-006-governance-compliance.md)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AUDIT_BASE="${CLAUDE_ENTERPRISE_AUDIT_BASE:-${ROOT_DIR}/.claude/enterprise/audit}"
GENESIS="0000000000000000000000000000000000000000000000000000000000000000"
LOCK_TRIES="${AUDIT_LOCK_TRIES:-100}"   # x 0.1 s

# ── Helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
governance-audit-trail.sh — SPEC-SE-006 Hash-chained Audit Trail

Usage:
  governance-audit-trail.sh append --tenant SLUG --actor USER --action ACTION [--spec SPEC]
  governance-audit-trail.sh verify --file PATH [--anchor HASH] [--tenant SLUG]
  governance-audit-trail.sh export --tenant SLUG [--format md|json]
  governance-audit-trail.sh chain-status [--tenant SLUG]
  governance-audit-trail.sh --help

Subcommands:
  append        Add a hash-chained JSONL entry to the tenant audit trail
  verify        Verify canonical format and chain integrity (detect tampering).
                --anchor HASH fails if that previously published hash is no
                longer in the chain: detects truncation or rewrite of the
                entries up to the anchored one. Entries written after the
                last published anchor are not protected by it.
                --tenant SLUG fails if any entry belongs to another tenant
                (a trail copied into the wrong tenant directory).
  export        Export trail for external auditors (md or json format)
  chain-status  Show entry count and full last hash (publish it as anchor)

Field rules: tenant = [A-Za-z0-9][A-Za-z0-9._-]{0,63}; actor/action/spec =
1-256 chars without double quotes, backslashes or control characters.

Environment:
  CLAUDE_ENTERPRISE_AUDIT_BASE  Base directory of tenant trails
                                (default: .claude/enterprise/audit)

Integrity model: unkeyed sha256 chain. It detects edits, deletions and
insertions inside the chain; truncation or a full recomputation is only
detected against an anchor stored outside the trail. No digital signature.

Exit codes:
  0  success / chain intact
  1  tampering detected, empty trail, or runtime failure (lock, write, sha256)
  2  invalid arguments
USAGE
  exit 0
}

die()       { echo "ERROR: $*" >&2; exit 1; }
usage_err() { echo "ERROR: $*" >&2; exit 2; }

# Garantiza que un flag lleva valor: need_val "$#" "$1"
need_val() { [[ "$1" -ge 2 ]] || usage_err "$2 requires a value"; }

valid_tenant() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; }

# Campo libre: 1-256 caracteres, sin comillas, barra invertida ni controles.
valid_field() {
  local v="$1"
  [[ -n "$v" && "${#v}" -le 256 ]] || return 1
  [[ "$v" != *'"'* && "$v" != *'\'* ]] || return 1
  [[ ! "$v" =~ [[:cntrl:]] ]]
}

require_field() {  # $1=nombre $2=valor
  valid_field "$2" || usage_err "invalid --$1: 1-256 chars, no quotes, backslashes or control characters"
}

require_tenant() {
  valid_tenant "$1" || usage_err "invalid --tenant '$1': use [A-Za-z0-9][A-Za-z0-9._-]{0,63}"
}

# Marca de tiempo UTC con rangos de calendario plausibles (mes, día, hora...).
valid_ts() {
  [[ "$1" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$ ]]
}

# 0 si el fichero no contiene bytes NUL (read los descartaría sin avisar).
no_nul() {
  [[ "$(tr -d '\000' < "$1" | wc -c)" -eq "$(wc -c < "$1")" ]]
}

# sha256 hex de stdin; falla si no hay herramienta o la salida no es un hash.
sha256_stdin() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    out="$(shasum -a 256 | cut -d' ' -f1)"
  else
    echo "ERROR: no sha256 tool available (need sha256sum or shasum)" >&2
    return 1
  fi
  [[ "$out" =~ ^[0-9a-f]{64}$ ]] || { echo "ERROR: sha256 tool returned no hash" >&2; return 1; }
  printf '%s' "$out"
}

# Hash de una entrada: un campo por línea, spec vacío si no existe.
entry_hash() {  # ts tenant actor action spec prev
  printf '%s\n' "$1" "$2" "$3" "$4" "$5" "$6" | sha256_stdin
}

compose_line() {  # ts tenant actor action spec prev hash
  local spec_field=""
  [[ -n "$5" ]] && spec_field=",\"spec\":\"$5\""
  printf '{"ts":"%s","tenant":"%s","actor":"%s","action":"%s"%s,"prev_hash":"%s","hash":"sha256:%s"}' \
    "$1" "$2" "$3" "$4" "$spec_field" "$6" "$7"
}

# Forma canónica exacta, anclada en ambos extremos: rechaza claves duplicadas,
# campos extra, reordenados o basura alrededor del objeto.
# Rellena P_TS P_TENANT P_ACTOR P_ACTION P_SPEC P_PREV P_HASH.
CANON_RE='^\{"ts":"([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)","tenant":"([^"\\]*)","actor":"([^"\\]*)","action":"([^"\\]*)"(,"spec":"([^"\\]*)")?,"prev_hash":"([0-9a-f]{64})","hash":"sha256:([0-9a-f]{64})"\}$'

parse_line() {
  [[ "$1" =~ $CANON_RE ]] || return 1
  P_TS="${BASH_REMATCH[1]}"; P_TENANT="${BASH_REMATCH[2]}"
  P_ACTOR="${BASH_REMATCH[3]}"; P_ACTION="${BASH_REMATCH[4]}"
  P_SPEC="${BASH_REMATCH[6]:-}"; P_PREV="${BASH_REMATCH[7]}"; P_HASH="${BASH_REMATCH[8]}"
  valid_ts "$P_TS" && valid_tenant "$P_TENANT" && valid_field "$P_ACTOR" && valid_field "$P_ACTION" || return 1
  [[ -z "${BASH_REMATCH[5]:-}" ]] || valid_field "$P_SPEC"
}

# Último hash hex del trail en PREV_HASH (GENESIS si no existe o está vacío) y
# su marca de tiempo en PREV_TS. Devuelve 1 si la cola está corrupta o hay
# bytes NUL: nunca reinicia la cadena en silencio.
read_tail() {
  local trail_file="$1" last
  PREV_HASH="$GENESIS"; PREV_TS=""
  [[ -s "$trail_file" ]] || return 0
  no_nul "$trail_file" || return 1
  [[ "$(tail -c1 "$trail_file" | wc -l)" -eq 1 ]] || return 1
  last="$(tail -n 1 "$trail_file")"
  parse_line "$last" || return 1
  PREV_HASH="$P_HASH"; PREV_TS="$P_TS"
}

LOCK_DIR=""
# Lock = fichero creado con O_EXCL (noclobber del propio bash). No usa `mkdir`:
# el mkdir de uutils-coreutils (Ubuntu 25.10+) dejaba pasar a varios procesos
# a la vez y rompía la cadena (20 appends paralelos -> prev_hash cruzados).
release_lock() { [[ -n "$LOCK_DIR" ]] && unlink "$LOCK_DIR" 2>/dev/null; LOCK_DIR=""; }

acquire_lock() {
  local lock="$1.lock" i=0
  # Un create fallido es contención salvo que el directorio no sea escribible
  # (comprobar -e aquí tendría carrera con la liberación del otro proceso).
  [[ -w "$(dirname "$lock")" ]] || die "cannot create lock ${lock}: directory not writable"
  until ( set -C; printf '%s\n' "$$" > "$lock" ) 2>/dev/null; do
    i=$(( i + 1 ))
    [[ "$i" -ge "$LOCK_TRIES" ]] && die "lock busy: ${lock} (remove it only if no append is running)"
    sleep 0.1
  done
  LOCK_DIR="$lock"
  trap release_lock EXIT
}

# ── Subcommand: append ───────────────────────────────────────────────────────

cmd_append() {
  local tenant="" actor="" action="" spec=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tenant) need_val $# "$1"; tenant="$2"; shift 2 ;;
      --actor)  need_val $# "$1"; actor="$2";  shift 2 ;;
      --action) need_val $# "$1"; action="$2"; shift 2 ;;
      --spec)   need_val $# "$1"; spec="$2";   shift 2 ;;
      *) usage_err "append: unknown argument: $1" ;;
    esac
  done

  [[ -z "$tenant" ]] && usage_err "append: --tenant is required"
  [[ -z "$actor"  ]] && usage_err "append: --actor is required"
  [[ -z "$action" ]] && usage_err "append: --action is required"
  require_tenant "$tenant"
  require_field actor "$actor"
  require_field action "$action"
  [[ -z "$spec" ]] || require_field spec "$spec"

  local tenant_dir="${AUDIT_BASE}/${tenant}"
  mkdir -p "$tenant_dir" 2>/dev/null || die "cannot create ${tenant_dir}"
  local trail_file="${tenant_dir}/audit-trail.jsonl"

  acquire_lock "$trail_file"

  local ts prev_hash hash
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  read_tail "$trail_file" \
    || die "trail tail is malformed; run: $0 verify --file ${trail_file}"
  prev_hash="$PREV_HASH"
  # Orden temporal: verify lo exige, así que un reloj atrasado no escribe.
  [[ -z "$PREV_TS" || ! "$ts" < "$PREV_TS" ]] \
    || die "system clock (${ts}) is earlier than the last entry (${PREV_TS}); nothing appended"
  hash="$(entry_hash "$ts" "$tenant" "$actor" "$action" "$spec" "$prev_hash")" \
    || die "cannot compute sha256; nothing appended"

  local entry
  entry="$(compose_line "$ts" "$tenant" "$actor" "$action" "$spec" "$prev_hash" "$hash")"
  printf '%s\n' "$entry" >> "$trail_file" 2>/dev/null || die "cannot write ${trail_file}; nothing appended"
  release_lock

  echo "OK: appended to ${trail_file}"
  echo "    hash: sha256:${hash}"
}

# ── Subcommand: verify ───────────────────────────────────────────────────────

cmd_verify() {
  local file="" anchor="" tenant=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)   need_val $# "$1"; file="$2";   shift 2 ;;
      --anchor) need_val $# "$1"; anchor="$2"; shift 2 ;;
      --tenant) need_val $# "$1"; tenant="$2"; shift 2 ;;
      *) usage_err "verify: unknown argument: $1" ;;
    esac
  done

  [[ -z "$file" ]] && usage_err "verify: --file is required"
  [[ ! -f "$file" ]] && usage_err "verify: file not found: ${file}"
  if [[ -n "$anchor" ]]; then
    anchor="${anchor#sha256:}"
    [[ "$anchor" =~ ^[0-9a-f]{64}$ ]] || usage_err "verify: --anchor must be a sha256 hex hash"
  fi
  [[ -z "$tenant" ]] || require_tenant "$tenant"
  if ! no_nul "$file"; then
    echo "TAMPERED: file contains NUL bytes (verified bytes would differ from the bytes on disk)"
    echo "CHAIN FAIL: 1 integrity violation(s) detected"
    exit 1
  fi

  local line_num=0 tampered=0 anchor_found=0 expected
  local prev_hash="$GENESIS" prev_ts=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$(( line_num + 1 ))

    if ! parse_line "$line"; then
      echo "TAMPERED: line ${line_num} — not a canonical audit entry"
      tampered=$(( tampered + 1 ))
      prev_hash=""; prev_ts=""   # enlace desconocido: no se comprueba la siguiente
      continue
    fi

    if [[ -n "$prev_hash" && "$P_PREV" != "$prev_hash" ]]; then
      echo "TAMPERED: line ${line_num} — prev_hash mismatch (expected: ${prev_hash}, got: ${P_PREV})"
      tampered=$(( tampered + 1 ))
    fi

    expected="$(entry_hash "$P_TS" "$P_TENANT" "$P_ACTOR" "$P_ACTION" "$P_SPEC" "$P_PREV")" \
      || die "cannot compute sha256; verification not performed"
    if [[ "$P_HASH" != "$expected" ]]; then
      echo "TAMPERED: line ${line_num} — hash mismatch (expected: sha256:${expected}, got: sha256:${P_HASH})"
      tampered=$(( tampered + 1 ))
    fi

    if [[ -n "$prev_ts" && "$P_TS" < "$prev_ts" ]]; then
      echo "TAMPERED: line ${line_num} — timestamp goes backwards (${P_TS} < ${prev_ts})"
      tampered=$(( tampered + 1 ))
    fi
    if [[ -n "$tenant" && "$P_TENANT" != "$tenant" ]]; then
      echo "TAMPERED: line ${line_num} — entry belongs to tenant '${P_TENANT}', expected '${tenant}'"
      tampered=$(( tampered + 1 ))
    fi

    [[ "$P_HASH" == "$anchor" ]] && anchor_found=1
    prev_hash="$P_HASH"; prev_ts="$P_TS"
  done < "$file"

  echo "Verified ${line_num} entries in ${file}"
  if [[ "$line_num" -eq 0 ]]; then
    echo "CHAIN EMPTY: nothing to verify"
    exit 1
  fi
  if [[ -n "$anchor" && "$anchor_found" -eq 0 ]]; then
    echo "ANCHOR NOT FOUND: sha256:${anchor} is not in the chain (truncated or rewritten)"
    tampered=$(( tampered + 1 ))
  fi
  if [[ "$tampered" -eq 0 ]]; then
    echo "CHAIN OK: no tampering detected"
    exit 0
  fi
  echo "CHAIN FAIL: ${tampered} integrity violation(s) detected"
  exit 1
}

# ── Subcommand: export ───────────────────────────────────────────────────────

md_cell() { local v="${1//|/\\|}"; printf '%s' "$v"; }

cmd_export() {
  local tenant="" format="json"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tenant) need_val $# "$1"; tenant="$2"; shift 2 ;;
      --format) need_val $# "$1"; format="$2"; shift 2 ;;
      *) usage_err "export: unknown argument: $1" ;;
    esac
  done

  [[ -z "$tenant" ]] && usage_err "export: --tenant is required"
  require_tenant "$tenant"
  case "$format" in json|md) ;; *) usage_err "export: unknown format '${format}'. Use md or json." ;; esac

  local trail_file="${AUDIT_BASE}/${tenant}/audit-trail.jsonl"
  [[ ! -f "$trail_file" ]] && die "export: trail not found: ${trail_file}"

  if [[ "$format" == "json" ]]; then
    echo "["
    local first=1
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      [[ "$first" -eq 0 ]] && echo ","
      printf '%s' "$line"
      first=0
    done < "$trail_file"
    echo ""
    echo "]"
    return
  fi

  echo "# Audit Trail — Tenant: ${tenant}"
  echo ""
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "| Timestamp | Actor | Action | Spec | Hash |"
  echo "|-----------|-------|--------|------|------|"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if parse_line "$line"; then
      echo "| ${P_TS} | $(md_cell "$P_ACTOR") | $(md_cell "$P_ACTION") | $(md_cell "${P_SPEC:-—}") | \`${P_HASH:0:20}...\` |"
    else
      echo "| (non-canonical line — run verify) | | | | |"
    fi
  done < "$trail_file"
}

# ── Subcommand: chain-status ─────────────────────────────────────────────────

tail_hash_label() {
  if read_tail "$1"; then echo "sha256:${PREV_HASH}"; else echo "(malformed tail — run verify)"; fi
}

cmd_chain_status() {
  local tenant=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tenant) need_val $# "$1"; tenant="$2"; shift 2 ;;
      *) usage_err "chain-status: unknown argument: $1" ;;
    esac
  done

  # If no tenant given, show status for all tenants
  if [[ -z "$tenant" ]]; then
    if [[ ! -d "$AUDIT_BASE" ]]; then
      echo "No audit trails found (${AUDIT_BASE} does not exist)"
      exit 0
    fi
    for dir in "${AUDIT_BASE}"/*/; do
      [[ -d "$dir" ]] || continue
      local trail="${dir}audit-trail.jsonl"
      [[ -f "$trail" ]] || continue
      local count
      count="$(grep -c . "$trail")"
      echo "Tenant: $(basename "$dir") | entries: ${count} | last_hash: $(tail_hash_label "$trail")"
    done
    return
  fi

  require_tenant "$tenant"
  local trail_file="${AUDIT_BASE}/${tenant}/audit-trail.jsonl"
  if [[ ! -f "$trail_file" ]]; then
    echo "No trail found for tenant '${tenant}'"
    exit 0
  fi

  echo "Tenant:    ${tenant}"
  echo "File:      ${trail_file}"
  echo "Entries:   $(grep -c . "$trail_file")"
  echo "Last hash: $(tail_hash_label "$trail_file")"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  usage
fi

subcmd="$1"
shift

case "$subcmd" in
  append)       cmd_append "$@" ;;
  verify)       cmd_verify "$@" ;;
  export)       cmd_export "$@" ;;
  chain-status) cmd_chain_status "$@" ;;
  -h|--help)    usage ;;
  *) echo "ERROR: unknown subcommand: ${subcmd}" >&2
     echo "Run with --help for usage." >&2
     exit 2 ;;
esac
