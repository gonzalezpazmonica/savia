#!/usr/bin/env bash
# spec-lifecycle.sh — SE-222 S1: spec status transitions + append-only log (LOG.d/ fragments, SE-500 S1)
set -uo pipefail
#
# Helper to change the `status:` field of a spec and record the lifecycle
# transition as a fragment docs/propuestas/LOG.d/SE-NNN-STATUS.md (SE-500 S1);
#
# LOG.md (consolidated base + LOG.d/ fragments) captures the conceptual history:
# - When a spec was proposed
# - When it was implemented (or discarded)
# - Why (one-line rationale)
#
# This complements:
# - CHANGELOG.md (repo-wide, code changes)
# - git log (commits, but no conceptual narrative)
# - spec-status-normalize.sh (bulk normalization)
#
# Usage:
#   bash scripts/spec-lifecycle.sh --spec docs/propuestas/SE-XXX.md \
#                                  --status IMPLEMENTED \
#                                  --note "Implementado en PR #850"
#
#   bash scripts/spec-lifecycle.sh --bootstrap   # Generate LOG.md from
#                                                 # last 10 specs as seed.
#
# Exit codes:
#   0 — success
#   1 — invalid arguments / spec not found / invalid status
#   2 — usage error
#
# Ref: SE-222 S1 OKF Adoptable Patterns (log.md convention)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROPUESTAS_DIR="${PROPUESTAS_DIR_OVERRIDE:-$PROJECT_ROOT/docs/propuestas}"
LOG_FILE="${LOG_FILE_OVERRIDE:-$PROPUESTAS_DIR/LOG.md}"   # base consolidada (solo --bootstrap)
LOG_DIR="${LOG_DIR_OVERRIDE:-$PROPUESTAS_DIR/LOG.d}"       # fragmentos (SE-500 S1)

# Canonical statuses (uppercase): los mismos que acepta roadmap.sh validate (comprobación 2)
# y el nombre de los fragmentos de LOG.d (SE-500 S1).
CANONICAL_STATUSES="IDEA PROPOSED APPROVED IMPLEMENTING IMPLEMENTED REJECTED SUPERSEDED DEFERRED RETIRED"

SPEC=""
NEW_STATUS=""
NOTE=""
BOOTSTRAP=0
DRY_RUN=0
NO_TIMELINE=0

usage() {
  cat <<EOF
Usage:
  $0 --spec <path> --status <STATUS> [--note "rationale"] [--dry-run] [--no-timeline]
  $0 --bootstrap [--dry-run]

Changes the status: field of a spec and records the lifecycle transition as a
fragment docs/propuestas/LOG.d/SE-NNN-STATUS.md (SE-500 S1; LOG.md is the
consolidated base and is only rewritten by roadmap.sh consolidate).

Options:
  --spec PATH       Path to spec file (e.g. docs/propuestas/SE-222.md)
  --status STATUS   New status (one of: $CANONICAL_STATUSES)
  --note TEXT       One-line rationale for the LOG.d entry (optional)
  --bootstrap       Generate LOG.md from last 10 specs + git history (seed)
  --dry-run         Show what would happen, don't modify files
  --no-timeline     Skip automatic timeline entry (spec-timeline-append.py)
  -h, --help        This help

Exit codes:
  0  Success
  1  Spec not found, invalid status, or write error
  2  Usage error (missing required args)

Ref: SE-222 S1 OKF Adoptable Patterns
Ref: SPEC-182 Bitemporal timeline frontmatter
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec)         SPEC="$2"; shift 2 ;;
    --status)       NEW_STATUS="$2"; shift 2 ;;
    --note)         NOTE="$2"; shift 2 ;;
    --bootstrap)    BOOTSTRAP=1; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --no-timeline)  NO_TIMELINE=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

is_canonical_status() {
  local s="$1"
  for canonical in $CANONICAL_STATUSES; do
    [[ "$s" == "$canonical" ]] && return 0
  done
  return 1
}

# Extract YAML frontmatter field value from a spec file
get_field() {
  local file="$1" field="$2"
  awk -v fld="$field" '
    NR==1 && $0 != "---" { exit }
    NR==1 { in_fm=1; next }
    in_fm && /^---$/ { exit }
    in_fm && $0 ~ "^"fld"[[:space:]]*:" {
      sub("^"fld"[[:space:]]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

# SE-500 S1: la transición se escribe como fragmento docs/propuestas/LOG.d/SE-NNN-ESTADO.md
# (una entrada, sin editar LOG.md). La vista consolidada la calcula scripts/planning-view.py.
append_log_entry() {
  local date_str="$1" spec_id="$2" new_status="$3" title="$4" note="$5"
  local text="$title"
  [[ -n "$note" ]] && text="${text:+$text
}$note"
  python3 "$SCRIPT_DIR/planning-view.py" --root "$PROJECT_ROOT" log-entry "$spec_id" "$new_status" \
    --date "$date_str" --text "$text" --log-dir "$LOG_DIR"
}

# Update status: field in spec frontmatter
update_status() {
  local file="$1" new_status="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] Would update status: $new_status in $file"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  local in_frontmatter=0 done=0
  while IFS= read -r line; do
    if [[ "$in_frontmatter" -eq 0 ]]; then
      if [[ "$line" == "---" ]]; then
        in_frontmatter=1
      fi
      printf '%s\n' "$line"
      continue
    fi
    if [[ "$in_frontmatter" -eq 1 && "$line" == "---" ]]; then
      in_frontmatter=2
      printf '%s\n' "$line"
      continue
    fi
    if [[ "$in_frontmatter" -eq 1 && "$done" -eq 0 && "$line" =~ ^status[[:space:]]*: ]]; then
      printf 'status: %s\n' "$new_status"
      done=1
    else
      printf '%s\n' "$line"
    fi
  done < "$file" > "$tmp"

  if [[ "$done" -eq 0 ]]; then
    echo "WARN: status: field not found in $file (no update made)" >&2
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$file"
}

# Bootstrap: generate LOG.md with seed entries from last 10 spec commits
bootstrap_log() {
  local date_str
  date_str="$(date +%Y-%m-%d)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] Would create $LOG_FILE with seed from last 10 specs"
    return 0
  fi

  cat > "$LOG_FILE" <<HEADER
<!-- @generated/managed by scripts/spec-lifecycle.sh — append-only -->
<!-- Most recent entries at the top. Format: ## YYYY-MM-DD SPEC-ID STATUS -->
# Specs Lifecycle Log

> Conceptual history of specs in docs/propuestas/. Append-only.
> Each entry: date, spec ID, status transition, optional rationale.
> Ref: SE-222 S1 OKF Adoptable Patterns (log.md convention).

## ${date_str} LOG.md created (SE-222 S1)
Bootstrap entry — file created from this point forward.
New transitions appended at the top.

HEADER
  echo "Created $LOG_FILE"
  return 0
}

# ── Main ─────────────────────────────────────────────────────────────────

if [[ "$BOOTSTRAP" -eq 1 ]]; then
  bootstrap_log
  exit $?
fi

if [[ -z "$SPEC" || -z "$NEW_STATUS" ]]; then
  echo "ERROR: --spec and --status are required (or use --bootstrap)" >&2
  usage >&2
  exit 2
fi

if ! is_canonical_status "$NEW_STATUS"; then
  echo "ERROR: '$NEW_STATUS' is not a canonical status." >&2
  echo "Valid: $CANONICAL_STATUSES" >&2
  exit 1
fi

if [[ ! -f "$SPEC" ]]; then
  echo "ERROR: spec file not found: $SPEC" >&2
  exit 1
fi

# Extract spec_id and title from frontmatter
SPEC_ID="$(get_field "$SPEC" "spec_id")"
[[ -z "$SPEC_ID" ]] && SPEC_ID="$(basename "$SPEC" .md | sed -E 's/^(SE-[0-9]+|SPEC-[A-Z0-9]+-?[0-9]*).*/\1/')"
TITLE="$(get_field "$SPEC" "title")"
TITLE="${TITLE#\"}"; TITLE="${TITLE%\"}"  # strip surrounding quotes

OLD_STATUS="$(get_field "$SPEC" "status")"
DATE_STR="$(date +%Y-%m-%d)"

if [[ ! "$SPEC_ID" =~ ^SE-[0-9]+$ ]]; then
  echo "ERROR: spec id '$SPEC_ID' no es SE-NNN: los fragmentos de LOG.d solo admiten SE-NNN" >&2
  exit 1
fi

if [[ -z "$OLD_STATUS" ]]; then
  echo "WARN: spec $SPEC has no current status: field" >&2
fi

# Apply changes
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[DRY-RUN] Would change status: $OLD_STATUS → $NEW_STATUS in $SPEC"
  echo "[DRY-RUN] Would write $LOG_DIR/$SPEC_ID-$NEW_STATUS.md:"
  echo "  ## $DATE_STR $SPEC_ID $NEW_STATUS"
  [[ -n "$TITLE" ]] && echo "  $TITLE"
  [[ -n "$NOTE" ]] && echo "  $NOTE"
  exit 0
fi

LOGGED=$(append_log_entry "$DATE_STR" "$SPEC_ID" "$NEW_STATUS" "$TITLE" "$NOTE") || {
  echo "ERROR: no se pudo escribir la entrada en $LOG_DIR; spec sin cambios" >&2
  exit 1
}
update_status "$SPEC" "$NEW_STATUS"

echo "Updated: $SPEC ($OLD_STATUS → $NEW_STATUS)"
echo "Logged:  $LOGGED"

# ── SPEC-182: auto-append bitemporal timeline entry ──────────────────────────
if [[ "$NO_TIMELINE" -eq 0 ]]; then
  TIMELINE_SCRIPT="$SCRIPT_DIR/spec-timeline-append.py"
  if [[ -f "$TIMELINE_SCRIPT" ]]; then
    python3 "$TIMELINE_SCRIPT" \
      --file "$SPEC" \
      --from "$DATE_STR" \
      --learned "$DATE_STR" \
      --value "$NEW_STATUS" \
      --source "spec-lifecycle:auto" \
      && echo "Timeline: entry appended ($NEW_STATUS)" \
      || echo "WARN: timeline append failed (non-fatal)" >&2
  else
    echo "WARN: spec-timeline-append.py not found — skipping timeline (use --no-timeline to suppress)" >&2
  fi
fi
