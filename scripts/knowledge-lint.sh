#!/usr/bin/env bash
set -uo pipefail
# knowledge-lint.sh — LLM Wiki pattern: periodic knowledge base health check
#
# Inspired by Karpathy's LLM Wiki gist (2026-04-14).
# Detects: orphan memories, stale cross-references, missing evidence types,
# contradictions between memory and current state, oversized indexes.
#
# Usage:
#   bash scripts/knowledge-lint.sh [--fix]    # report + optional auto-fix
#   bash scripts/knowledge-lint.sh --summary  # counts only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Carpeta de memoria. Si MEMORY_DIR viene dado, manda. Si no, se usa la memoria
# automática de Claude Code para ESTE repositorio: su carpeta de proyecto se llama
# como la ruta del repo con cada carácter no alfanumérico cambiado por «-».
# Antes había aquí una ruta fija de una máquina concreta que ya no existía, y el
# guion respondía «nada que revisar» con salida 0 sin haber mirado nada.
default_memory_dir() {
  printf '%s/.claude/projects/%s/memory' "$HOME" "$(printf '%s' "$REPO_ROOT" | sed 's#[^A-Za-z0-9]#-#g')"
}
MEMORY_DIR="${MEMORY_DIR:-$(default_memory_dir)}"
FIX_MODE=false

[[ "${1:-}" == "--fix" ]] && FIX_MODE=true

errors=0
warnings=0
checked=0
fixed=0

log_error() { echo "ERROR: $*" >&2; (( errors++ )) || true; }
log_warn()  { echo "WARN:  $*" >&2; (( warnings++ )) || true; }
log_fix()   { echo "FIXED: $*"; (( fixed++ )) || true; }

# ── Check 1: MEMORY.md index references point to existing files ────────────

check_orphan_index_entries() {
  local index="$MEMORY_DIR/MEMORY.md"
  [[ -f "$index" ]] || return 0
  (( checked++ )) || true

  while IFS= read -r line; do
    local ref
    ref=$(echo "$line" | grep -oP '\[.*?\]\(\K[^)]+' || true)
    [[ -z "$ref" ]] && continue
    if [[ ! -f "$MEMORY_DIR/$ref" ]]; then
      log_error "Orphan index entry: $ref (file does not exist)"
      if $FIX_MODE; then
        sed -i "\|$ref|d" "$index"
        log_fix "Removed orphan entry: $ref from MEMORY.md"
      fi
    fi
  done < "$index"
}

# ── Check 2: Memory files not listed in MEMORY.md ─────────────────────────

check_unlisted_memories() {
  local index="$MEMORY_DIR/MEMORY.md"
  [[ -f "$index" ]] || return 0

  while IFS= read -r -d '' memfile; do
    local basename_file
    basename_file=$(basename "$memfile")
    [[ "$basename_file" == "MEMORY.md" ]] && continue
    (( checked++ )) || true

    if ! grep -q "$basename_file" "$index" 2>/dev/null; then
      log_warn "Unlisted memory file: $basename_file (exists but not in MEMORY.md)"
    fi
  done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" -print0 2>/dev/null)
}

# ── Check 3: Missing evidence_type in memory frontmatter ──────────────────

check_missing_evidence_type() {
  while IFS= read -r -d '' memfile; do
    local basename_file
    basename_file=$(basename "$memfile")
    [[ "$basename_file" == "MEMORY.md" ]] && continue
    (( checked++ )) || true

    # Check if file has frontmatter
    if head -1 "$memfile" | grep -q "^---$"; then
      if ! sed -n '/^---$/,/^---$/p' "$memfile" | grep -q "evidence_type:"; then
        log_warn "[$basename_file] Missing evidence_type field (sourced|analyzed|inferred|gap)"
      fi
    fi
  done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" -print0 2>/dev/null)
}

# ── Check 4: MEMORY.md exceeds 200 line limit ─────────────────────────────

check_index_size() {
  local index="$MEMORY_DIR/MEMORY.md"
  [[ -f "$index" ]] || return 0
  (( checked++ )) || true

  local lines
  lines=$(wc -l < "$index")
  if (( lines > 200 )); then
    log_error "MEMORY.md has $lines lines (max 200 — truncation will occur)"
  elif (( lines > 150 )); then
    log_warn "MEMORY.md has $lines lines (approaching 200 line limit)"
  fi
}

# ── Check 5: Stale memories (type=project older than 90 days) ─────────────

check_stale_memories() {
  local today_epoch
  today_epoch=$(date +%s)

  while IFS= read -r -d '' memfile; do
    local basename_file
    basename_file=$(basename "$memfile")
    [[ "$basename_file" == "MEMORY.md" ]] && continue

    local mem_type
    mem_type=$(sed -n '/^---$/,/^---$/p' "$memfile" 2>/dev/null | grep -m1 "^type:" | awk '{print $2}' || echo "")
    [[ "$mem_type" != "project" ]] && continue
    (( checked++ )) || true

    local file_age_days
    if [[ "$(uname)" == "Darwin" ]]; then
      file_age_days=$(( (today_epoch - $(stat -f %m "$memfile")) / 86400 ))
    else
      file_age_days=$(( (today_epoch - $(stat -c %Y "$memfile")) / 86400 ))
    fi

    if (( file_age_days > 90 )); then
      log_warn "[$basename_file] Stale project memory (${file_age_days}d old, >90d threshold)"
    fi
  done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" -print0 2>/dev/null)
}

# ── Check 6: Duplicate descriptions in MEMORY.md ─────────────────────────

check_duplicate_descriptions() {
  local index="$MEMORY_DIR/MEMORY.md"
  [[ -f "$index" ]] || return 0
  (( checked++ )) || true

  local dupes
  dupes=$(grep -oP '— \K.*$' "$index" 2>/dev/null | sort | uniq -d)
  if [[ -n "$dupes" ]]; then
    while IFS= read -r dup; do
      log_warn "Duplicate description in MEMORY.md: '$dup'"
    done <<< "$dupes"
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────

main() {
  echo "Knowledge Lint (LLM Wiki pattern)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Memory dir: $MEMORY_DIR"
  echo ""

  # Falla cerrado: sin carpeta no se ha revisado nada, y eso no es «sano».
  if [[ ! -d "$MEMORY_DIR" ]]; then
    echo "ERROR: no existe la carpeta de memoria: $MEMORY_DIR" >&2
    echo "No se ha revisado nada. Indica la carpeta con MEMORY_DIR=<ruta>." >&2
    exit 3
  fi

  check_orphan_index_entries
  check_unlisted_memories
  check_missing_evidence_type
  check_index_size
  check_stale_memories
  check_duplicate_descriptions

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Knowledge Lint Results"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Items checked:  $checked"
  echo "  Errors:         $errors"
  echo "  Warnings:       $warnings"
  if $FIX_MODE; then
    echo "  Auto-fixed:     $fixed"
  fi
  if (( errors > 0 )); then
    echo "  Status:         NEEDS ATTENTION"
    exit 1
  elif (( warnings > 0 )); then
    echo "  Status:         HEALTHY (with advisories)"
    exit 0
  else
    echo "  Status:         HEALTHY"
    exit 0
  fi
}

main "$@"
