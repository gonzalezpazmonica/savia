#!/usr/bin/env bash
set -uo pipefail
# exit-purge-verify.sh — SE-272 S5: Verify purge after engagement forget
#
# After scenario-forget (engagement deletion), verifies zero living
# references outside tombstones and audit log.
#
# Performs exhaustive grep across the workspace looking for:
#   - Engagement name references in code, docs, configs
#   - Project directory remnants
#   - Agent memory references
#   - Session log references
#   - Knowledge graph nodes
#
# Allowed references:
#   - Tombstone files: .savia-tombstones/{engagement}.json
#   - Audit log entries: output/audit-trail.jsonl
#   - Exit packages: output/exit-packages/{engagement}/
#   - Drill logs: output/exit-drills/
#   - This script itself
#
# Usage:
#   bash scripts/exit-purge-verify.sh verify --engagement NAME
#   bash scripts/exit-purge-verify.sh verify --engagement NAME --exclude-dir DIR
#   bash scripts/exit-purge-verify.sh tombstone --engagement NAME
#   bash scripts/exit-purge-verify.sh --help

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 2; }
warn() { echo "WARN:  $*" >&2; }
ok() { echo "OK:    $*" >&2; }
info() { echo "INFO:  $*" >&2; }

usage() {
  sed -n '/^# /{s/^# //;p;}' "$0" | head -22
}

# ── Engagement name (also used as file name and grep literal) ──────────────────
# Solo letras, dígitos, punto, guion y guion bajo: nada de rutas ni comillas.
valid_engagement() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ && "$1" != *..* ]]; }

# ── Allowed paths (references that are expected to survive purge) ──────────────
# Rutas relativas a ROOT. Se comparan exactas o como prefijo de directorio; nunca
# por subcadena (un docs/exit-notes.md o un docs/audit-trail-x.md NO son seguros).

is_allowed_path() {
  local rel="$1" engagement="$2"
  case "$rel" in
    .savia-tombstones/*|output/audit-trail.jsonl) return 0 ;;
    "output/exit-packages/$engagement"/*|output/exit-drills/*) return 0 ;;
    scripts/exit-purge-verify.sh|scripts/exit-package-generate.sh) return 0 ;;
    scripts/exit-dependencies-declare.sh|scripts/exit-drill-execute.sh) return 0 ;;
    scripts/exit-independence-verify.sh) return 0 ;;
  esac
  return 1
}

is_excluded_path() {
  local rel="$1" d
  shift
  for d in "$@"; do
    d="${d#./}"; d="${d%/}"
    [[ -n "$d" && "$rel" == "$d"/* ]] && return 0
  done
  return 1
}

# ── Verify purge ───────────────────────────────────────────────────────────────

cmd_verify() {
  local engagement="" extra_excludes=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --engagement) engagement="${2:-}"; shift 2 || shift ;;
      --exclude-dir) extra_excludes+=("${2:-}"); shift 2 || shift ;;
      *) shift ;;
    esac
  done

  [[ -z "$engagement" ]] && die "--engagement required"
  valid_engagement "$engagement" || die "invalid engagement name: only [A-Za-z0-9._-]"

  echo "=== PURGE VERIFICATION ==="
  echo "Engagement: $engagement"
  echo "Workspace: $ROOT"
  echo ""

  local allowed_count=0
  local violation_count=0

  # Search patterns (literales, no regex): nombre, nombre con espacios y ruta.
  local patterns=("$engagement")
  if [[ "$engagement" == *-* ]]; then
    patterns+=("${engagement//-/ }")
  fi
  patterns+=("projects/$engagement")

  echo "Search patterns: ${patterns[*]}"
  echo ""

  local results grep_rc=0 rc pat
  local pat_args=()
  for pat in "${patterns[@]}"; do pat_args+=(-e "$pat"); done

  # Una sola pasada: cada línea aparece una vez aunque case con varios patrones.
  # Rutas relativas a ROOT para clasificar sin depender de dónde vive el workspace.
  info "Searching for: ${patterns[*]}"
  results=$(cd "$ROOT" && grep -rnIF "${pat_args[@]}" --exclude-dir=".git" . 2>/dev/null)
  rc=$?
  # grep: 0 hay coincidencias, 1 ninguna, >1 error (p. ej. directorio ilegible).
  [[ "$rc" -gt 1 ]] && grep_rc="$rc"

  local total=0
  echo "=== Match Details ==="
  local match file rest line_num content
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    file="${match%%:*}"; file="${file#./}"
    rest="${match#*:}"
    line_num="${rest%%:*}"
    content="${rest#*:}"
    is_excluded_path "$file" "${extra_excludes[@]}" && continue
    total=$((total + 1))
    if is_allowed_path "$file" "$engagement"; then
      allowed_count=$((allowed_count + 1))
      echo "  [ALLOWED] $file:$line_num — $content"
    else
      violation_count=$((violation_count + 1))
      echo "  [VIOLATION] $file:$line_num — $content"
    fi
  done <<< "$results"

  echo ""
  echo "=== VERIFICATION RESULT ==="
  echo "Total matches:    $total"
  echo "Allowed references: $allowed_count"
  echo "Violations:       $violation_count"

  if [[ "$violation_count" -gt 0 ]]; then
    echo ""
    echo "RESULT: DIRTY — $violation_count living reference(s) found"
    echo ""
    echo "These references should either be:"
    echo "  1. Moved to .savia-tombstones/$engagement.json"
    echo "  2. Replaced with generic/obfuscated content"
    echo "  3. Marked as excluded via --exclude-dir if legitimate"
    return 1
  fi
  if [[ "$grep_rc" -ne 0 ]]; then
    # Fail-closed: si parte del workspace no se pudo leer, no hay «limpio».
    echo ""
    echo "RESULT: UNKNOWN — search failed (grep exit $grep_rc); part of the workspace was not read"
    return 2
  fi
  echo ""
  echo "RESULT: CLEAN — zero living references outside tombstones and audit log"
  return 0
}

# ── Create tombstone ───────────────────────────────────────────────────────────

cmd_tombstone() {
  local engagement=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --engagement) engagement="${2:-}"; shift 2 || shift ;;
      *) shift ;;
    esac
  done

  [[ -z "$engagement" ]] && die "--engagement required"
  valid_engagement "$engagement" || die "invalid engagement name: only [A-Za-z0-9._-]"

  local tombstone_dir="$ROOT/.savia-tombstones"
  mkdir -p "$tombstone_dir"

  local tombstone="$tombstone_dir/${engagement}.json"

  if [[ -f "$tombstone" ]]; then
    warn "Tombstone already exists: $tombstone"
    info "Existing content:"
    python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), indent=2, ensure_ascii=False))' "$tombstone" 2>/dev/null || cat "$tombstone"
    return 0
  fi

  info "Creating tombstone for engagement: $engagement"

  # Valores por argv, nunca interpolados en el código Python.
  if ! python3 - "$tombstone" "$engagement" "$(date -Iseconds)" <<'PYEOF' 2>/dev/null
import json, sys
path, eng, ts = sys.argv[1:4]
tombstone = {
    'engagement': eng,
    'action': 'scenario-forget',
    'timestamp': ts,
    'reason': 'Engagement completed — data purged per exit guarantee',
    'retained': {
        'exit_package': f'output/exit-packages/{eng}/',
        'audit_log': 'output/audit-trail.jsonl',
        'drill_reports': 'output/exit-drills/',
        'tombstone': f'.savia-tombstones/{eng}.json',
    },
    'purged': {
        'project_directory': f'projects/{eng}',
        'agent_memory': f'memory entries for {eng}',
        'agent_notes': f'agent notes referencing {eng}',
        'session_logs': f'session entries for {eng}',
    },
    'verified_at': ts,
    'verification_status': 'pending',
    'notes': 'This tombstone records the purge. All references outside this file and audit-trail.jsonl should have been removed.',
}
with open(path, 'w') as f:
    json.dump(tombstone, f, indent=2, ensure_ascii=False)
PYEOF
  then
    die "could not write tombstone: $tombstone"
  fi

  ok "Tombstone created: $tombstone"

  # Verify immediately: el estado refleja el resultado real, no «verified» siempre.
  info "Running purge verification..."
  local vrc=0 status="verified"
  cmd_verify --engagement "$engagement" || vrc=$?
  case "$vrc" in
    0) status="verified" ;;
    1) status="dirty"; warn "Verification found references — purge is incomplete" ;;
    *) status="unknown"; warn "Verification could not complete — purge not verified" ;;
  esac

  python3 - "$tombstone" "$(date -Iseconds)" "$status" <<'PYEOF' 2>/dev/null || die "could not update tombstone: $tombstone"
import json, sys
path, ts, status = sys.argv[1:4]
with open(path) as f:
    d = json.load(f)
d['verified_at'] = ts
d['verification_status'] = status
with open(path, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF

  ok "Tombstone updated: verification_status=$status"
  return "$vrc"
}

# ── Main ──────────────────────────────────────────────────────────────────────

cmd="${1:-}"; shift || true
case "$cmd" in
  verify)    cmd_verify "$@" ;;
  tombstone) cmd_tombstone "$@" ;;
  --help|-h) usage; exit 0 ;;
  *) echo "Usage: exit-purge-verify.sh {verify|tombstone} [options]" >&2; usage >&2; exit 1 ;;
esac
