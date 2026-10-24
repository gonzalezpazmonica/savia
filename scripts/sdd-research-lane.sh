#!/usr/bin/env bash
# sdd-research-lane.sh — SE-370: SDD Research lane — investigación auditable
# como fase del flujo spec→código.
#
# Ref: docs/specs/SE-370-sdd-research-lane.spec.md
# CRIT-001: research local. La lane NUNCA registra datos N3+ (filtro por
# nivel): el artefacto vive en repo versionado, solo admiten niveles N1/N2.
#
# Artefacto: docs/specs/<change>/research.md (formato sección 4 de la spec).
# El estado de la lane vive en el propio artefacto:
#   abierta  = artefacto existe y NO tiene línea `- cerrado:`
#   cerrada  = artefacto tiene línea `- cerrado:` (gate pasado)
#
# Uso:
#   sdd-research-lane.sh select <change> --grant documentation|open-web
#   sdd-research-lane.sh log <change> --claim "..." [--source <ref>] \
#                          [--fetched ISO] [--level N1|N2]
#   sdd-research-lane.sh contradict <change> --a <ref> --b <ref>
#   sdd-research-lane.sh close <change>
#   sdd-research-lane.sh validate <change>      # alias: --validate <change>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Override para tests herméticos; por defecto el artefacto vive bajo docs/specs
# (AC-5: docs/specs/<change>/research.md).
SPECS_DIR="${SDD_RESEARCH_SPECS_DIR:-$REPO_ROOT/docs/specs}"

_die() { echo "ERROR: $*" >&2; exit 1; }
_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_today() { date -u +"%Y-%m-%d"; }

research_path() { printf '%s/%s/research.md' "$SPECS_DIR" "$1"; }

artifact_exists() { [[ -f "$(research_path "$1")" ]]; }

lane_open() {
  artifact_exists "$1" || return 1
  ! grep -q '^- cerrado:' "$(research_path "$1")"
}

level_num() {
  case "$1" in
    N1) echo 1 ;;
    N2) echo 2 ;;
    N3) echo 3 ;;
    N4) echo 4 ;;
    N4b) echo 5 ;;
    *) echo -1 ;;
  esac
}

# Inserta <line> al final de la sección <heading>, eliminando <placeholder>
# si aún no había entradas. Uso: _append_to_section <file> <heading> <placeholder> <line>
_append_to_section() {
  local file="$1" heading="$2" placeholder="$3" line="$4"
  awk -v heading="$heading" -v placeholder="$placeholder" -v newline="$line" '
    $0 == placeholder { next }
    /^## / {
      if (sect) { print newline; sect = 0 }
    }
    $0 == heading { sect = 1 }
    { print }
    END { if (sect) print newline }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Refresca la sección Freshness con la última consulta y la fuente más antigua.
_update_freshness() {
  local file="$1"
  local now oldest
  now="$(_now_iso)"
  oldest="$(grep -o 'fetched: [^·]*' "$file" | sed 's/^fetched: //; s/ *$//' | sort | head -1)"
  [[ -n "$oldest" ]] || oldest="-"
  sed -i "s|^- Última consulta: .*|- Última consulta: $now · fuente(s) más antiguas: $oldest|" "$file"
}

usage() {
  cat <<'EOF'
sdd-research-lane.sh — SE-370: SDD Research lane

Uso:
  sdd-research-lane.sh select <change> --grant documentation|open-web
  sdd-research-lane.sh log <change> --claim "..." [--source <ref>] [--fetched ISO] [--level N1|N2]
  sdd-research-lane.sh contradict <change> --a <ref> --b <ref>
  sdd-research-lane.sh close <change>
  sdd-research-lane.sh validate <change>    (alias: --validate <change>)

CRIT-001: niveles N3+ (N3|N4|N4b) jamás se registran en la lane.
EOF
}

# ── select ────────────────────────────────────────────────────────────────────
cmd_select() {
  local change="$1"; shift
  local grant=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --grant) grant="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
      *) _die "select: opción desconocida '$1'" ;;
    esac
  done

  # AC-0: grant registrado explícito — nunca auto, nunca inferido.
  [[ -n "$grant" ]] || _die "select: --grant requerido (documentation|open-web). El grant no se infiere ni es automático (AC-0)."
  case "$grant" in
    documentation|open-web) ;;
    *) _die "select: grant inválido '$grant' (solo documentation|open-web)" ;;
  esac

  local path; path="$(research_path "$change")"
  if artifact_exists "$change"; then
    local current
    current="$(sed -n 's/^- scope: //p' "$path" | head -1)"
    if [[ "$current" == "$grant" ]]; then
      echo "OK: lane ya abierta para $change (grant: $grant) → $path"
      return 0
    fi
    _die "select: lane abierta con grant '$current'; ampliar scope exige nuevo grant humano"
  fi

  mkdir -p "$(dirname "$path")"
  local ts; ts="$(_now_iso)"
  cat > "$path" <<EOF
# Research — $change

## Preguntas
_Sin preguntas registradas_

## Grant
- scope: $grant
- granted_at: $ts
- granted_by: human

## Claims → Sources
_Sin claims_

## Contradicciones
_Sin contradicciones_

## Incertidumbre
_Sin incertidumbre registrada_

## Freshness
- Última consulta: $ts · fuente(s) más antiguas: -
EOF
  echo "OK: lane abierta para $change (grant: $grant) → $path"
}

# ── log ───────────────────────────────────────────────────────────────────────
cmd_log() {
  local change="$1"; shift
  local claim="" source="" fetched="" level="N1"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claim) claim="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
      --source) source="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
      --fetched) fetched="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
      --level) level="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
      *) _die "log: opción desconocida '$1'" ;;
    esac
  done

  [[ -n "$claim" ]] || _die "log: --claim requerido"
  artifact_exists "$change" || _die "log: lane no abierta para $change (ejecuta select primero)"
  lane_open "$change" || _die "log: lane cerrada para $change; el gate de close ya pasó"

  # AC-6 / CRIT-001: filtro por nivel — datos N3+ jamás entran en la lane.
  local lvl; lvl="$(level_num "$level")"
  [[ "$lvl" -ge 1 ]] || _die "log: nivel inválido '$level' (N1|N2|N3|N4|N4b)"
  if [[ "$lvl" -ge 3 ]]; then
    _die "CRIT-001: la lane jamás registra datos N3+ (nivel '$level'). El artefacto vive en repo versionado; registra solo N1/N2 o deja el dato fuera."
  fi

  # AC-4: freshness en cada claim — si no viene --fetched, se estampa hoy UTC.
  [[ -n "$fetched" ]] || fetched="$(_today)"

  # AC-1: claim sin source → marcado PENDIENTE (incertidumbre de primera clase).
  local src_line="Source: PENDIENTE"
  [[ -n "$source" ]] && src_line="Source: $source"

  local path; path="$(research_path "$change")"
  local line="- Claim: \"$claim\" → $src_line · fetched: $fetched · level: $level"
  _append_to_section "$path" "## Claims → Sources" "_Sin claims_" "$line"
  _update_freshness "$path"
  echo "OK: claim registrado en $path"
}

# ── contradict ────────────────────────────────────────────────────────────────
cmd_contradict() {
  local change="$1"; shift
  local a="" b=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --a) a="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
      --b) b="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
      *) _die "contradict: opción desconocida '$1'" ;;
    esac
  done

  [[ -n "$a" && -n "$b" ]] || _die "contradict: --a y --b requeridos"
  artifact_exists "$change" || _die "contradict: lane no abierta para $change (ejecuta select primero)"
  lane_open "$change" || _die "contradict: lane cerrada para $change"

  local path; path="$(research_path "$change")"
  local line="- Fuente $a dice una cosa; fuente $b dice ¬esa → abierta (contradicción entre $a y $b)"
  _append_to_section "$path" "## Contradicciones" "_Sin contradicciones_" "$line"
  _update_freshness "$path"
  echo "OK: contradicción registrada en $path"
}

# ── close ─────────────────────────────────────────────────────────────────────
cmd_close() {
  local change="$1"
  local path; path="$(research_path "$change")"
  artifact_exists "$change" || _die "close: no hay artefacto de research para $change"
  lane_open "$change" || _die "close: lane ya cerrada para $change"

  # AC-3: falla si queda algún claim sin fuente Y sin marcar PENDIENTE.
  local unmarked=0 total=0
  local line first src
  while IFS= read -r line; do
    [[ "$line" == "- Claim:"* ]] || continue
    total=$((total + 1))
    if [[ "$line" != *"Source: "* ]]; then
      unmarked=$((unmarked + 1))
      echo "SIN FUENTE Y SIN MARCAR: $line" >&2
      continue
    fi
    src="${line#*Source: }"
    first="${src%% ·*}"
    if [[ -z "$first" ]]; then
      unmarked=$((unmarked + 1))
      echo "SIN FUENTE Y SIN MARCAR: $line" >&2
    fi
  done < "$path"

  if [[ "$unmarked" -gt 0 ]]; then
    _die "close: $unmarked claim(s) de $total sin fuente y sin marcar PENDIENTE — resuelve o marca antes de implementar (AC-3)"
  fi

  local ts; ts="$(_now_iso)"
  printf -- '- cerrado: %s · gate-ok · claims: %d\n' "$ts" "$total" >> "$path"
  echo "GATE OK: research de $change cerrada — $total claim(s), todo con fuente o PENDIENTE explícito. Implementación permitida."
}

# ── validate (--validate) ────────────────────────────────────────────────────
cmd_validate() {
  local change="$1"
  local path; path="$(research_path "$change")"
  artifact_exists "$change" || _die "validate: no hay artefacto de research para $change"

  local errors=0
  _err() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

  # Grant coherente
  grep -q -- '- scope: documentation' "$path" || grep -q -- '- scope: open-web' "$path" \
    || _err "grant scope ausente o inválido"
  grep -q -- '- granted_at: ' "$path" || _err "granted_at ausente"
  grep -q -- '- granted_by: ' "$path" || _err "granted_by ausente"
  grep -q '^## Freshness' "$path" || _err "sección Freshness ausente"

  local grant
  grant="$(sed -n 's/^- scope: //p' "$path" | head -1)"

  # AC-4 (coherencia): cada claim lleva freshness (fetched:)
  local line src ref
  while IFS= read -r line; do
    [[ "$line" == "- Claim:"* ]] || continue
    if [[ "$line" != *"fetched: "* ]]; then
      _err "claim sin freshness: $line"
    fi
    # grant documentation: refs locales (no URL, no PENDIENTE) deben existir
    if [[ "$grant" == "documentation" && "$line" == *"Source: "* ]]; then
      src="${line#*Source: }"
      ref="${src%% ·*}"
      if [[ "$ref" != "PENDIENTE" && "$ref" != http*://* && -n "$ref" ]]; then
        ref="${ref%%#*}"
        if [[ ! -e "$REPO_ROOT/$ref" && ! -e "$SPECS_DIR/$change/$ref" ]]; then
          _err "ref local inexistente: $ref"
        fi
      fi
    fi
  done < "$path"

  if [[ "$errors" -gt 0 ]]; then
    _die "validate: artefacto de $change incoherente ($errors error(es))"
  fi
  echo "OK: artefacto de $change coherente (grant, refs, freshness)"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
main() {
  [[ $# -ge 1 ]] || { usage >&2; exit 1; }
  local cmd="$1"
  case "$cmd" in
    -h|--help|help)
      usage; exit 0 ;;
    select|log|contradict|close)
      shift
      [[ $# -ge 1 ]] || _die "$cmd: falta <change>"
      "cmd_$cmd" "$@" ;;
    validate|--validate)
      shift
      [[ $# -ge 1 ]] || _die "validate: falta <change>"
      cmd_validate "$1" ;;
    *)
      usage >&2
      _die "comando desconocido '$cmd'" ;;
  esac
}

main "$@"
