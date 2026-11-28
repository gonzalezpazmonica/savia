#!/usr/bin/env bash
set -uo pipefail
# kg-export.sh — SE-218 S2: KG snapshot versionado (codebase-memory-mcp pattern)
# Ref: docs/propuestas/SE-218-codebase-memory-patterns.md
# Usage:
#   kg-export.sh export [--mode best|fast]   — exportar snapshot
#   kg-export.sh import                      — importar snapshot existente
#   kg-export.sh status                      — ver estado del snapshot

# ── Paths ─────────────────────────────────────────────────────────────────────

WORKSPACE_ROOT="${SAVIA_WORKSPACE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
KG_DB="${SAVIA_KG_DB:-$WORKSPACE_ROOT/output/knowledge-graph.db}"
SNAPSHOT_DIR="$WORKSPACE_ROOT/.savia-kg"
SNAPSHOT_FILE="$SNAPSHOT_DIR/graph.db.zst"
SNAPSHOT_META="$SNAPSHOT_DIR/meta.json"

# ── Helpers ───────────────────────────────────────────────────────────────────

_write_meta() {
  local mode="$1" file="$2"
  local sha; sha=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "now")
  printf '{"mode":"%s","file":"%s","sha256":"%s","exported_at":"%s"}\n' \
    "$mode" "$file" "$sha" "$ts" > "$SNAPSHOT_META"
}

_ensure_gitattributes() {
  local file="$1"
  local rel; rel="${file#$WORKSPACE_ROOT/}"
  local ga="$WORKSPACE_ROOT/.gitattributes"
  local line="$rel merge=ours"
  if [[ -f "$ga" ]]; then
    grep -qF "$rel" "$ga" || echo "$line" >> "$ga"
  else
    echo "$line" > "$ga"
  fi
}

# ── Subcommand: export ────────────────────────────────────────────────────────

export_snapshot() {
  local mode="${1:-best}"
  [[ "$mode" != "best" && "$mode" != "fast" ]] && echo "ERROR: mode must be best or fast" >&2 && exit 2

  mkdir -p "$SNAPSHOT_DIR"

  # Verificar que hay KG
  [[ ! -f "$KG_DB" ]] && echo "ERROR: KG not found at $KG_DB — run knowledge-graph.py first" >&2 && exit 1

  local level=9
  [[ "$mode" == "fast" ]] && level=3

  # Verificar zstd disponible
  if ! command -v zstd >/dev/null 2>&1; then
    echo "WARN: zstd not available — using gzip fallback" >&2
    gzip -"$level" -c "$KG_DB" > "${SNAPSHOT_FILE%.zst}.gz" 2>/dev/null || {
      echo "ERROR: neither zstd nor gzip available" >&2; exit 1
    }
    local gz_file="${SNAPSHOT_FILE%.zst}.gz"
    echo "EXPORTED mode=$mode file=$gz_file" >&2
    _write_meta "$mode" "$gz_file"
    _ensure_gitattributes "$gz_file"
    return 0
  fi

  zstd -"$level" -f -q "$KG_DB" -o "$SNAPSHOT_FILE" 2>/dev/null || {
    echo "ERROR: compression failed" >&2; exit 1
  }

  _write_meta "$mode" "$SNAPSHOT_FILE"
  _ensure_gitattributes "$SNAPSHOT_FILE"

  local size; size=$(wc -c < "$SNAPSHOT_FILE" 2>/dev/null || echo "?")
  local orig; orig=$(wc -c < "$KG_DB" 2>/dev/null || echo "?")
  echo "EXPORTED mode=$mode file=$SNAPSHOT_FILE size=${size}B orig=${orig}B" >&2
}

# ── Subcommand: import ────────────────────────────────────────────────────────

import_snapshot() {
  local snap="$SNAPSHOT_FILE"
  # Fallback gzip
  [[ ! -f "$snap" && -f "${snap%.zst}.gz" ]] && snap="${snap%.zst}.gz"

  if [[ ! -f "$snap" ]]; then
    echo "WARN: no snapshot found at $SNAPSHOT_FILE — skipping import" >&2
    exit 0
  fi

  # Verificar SHA si hay meta
  if [[ -f "$SNAPSHOT_META" ]]; then
    local saved_sha; saved_sha=$(python3 -c "import sys; import json; d=json.load(open(sys.argv[1])); print(d.get('sha256',''))" "$SNAPSHOT_META" 2>/dev/null || echo "")
    if [[ -n "$saved_sha" ]]; then
      local actual_sha; actual_sha=$(sha256sum "$snap" 2>/dev/null | cut -d' ' -f1 || echo "")
      if [[ -n "$actual_sha" && "$saved_sha" != "$actual_sha" ]]; then
        echo "WARN: SHA mismatch on snapshot (saved=$saved_sha actual=$actual_sha) — skipping import" >&2
        exit 0
      fi
    fi
  fi

  mkdir -p "$(dirname "$KG_DB")"

  if [[ "$snap" == *.zst ]]; then
    command -v zstd >/dev/null 2>&1 || { echo "WARN: zstd not available — cannot import .zst" >&2; exit 0; }
    zstd -d -f -q "$snap" -o "$KG_DB" 2>/dev/null || {
      echo "WARN: decompression failed — snapshot may be corrupt" >&2; exit 0
    }
  else
    gzip -d -c "$snap" > "$KG_DB" 2>/dev/null || {
      echo "WARN: gzip decompression failed" >&2; exit 0
    }
  fi

  echo "IMPORTED $snap -> $KG_DB" >&2
}

# ── Subcommand: status ────────────────────────────────────────────────────────

status_snapshot() {
  echo "Snapshot: $SNAPSHOT_FILE"
  if [[ -f "$SNAPSHOT_FILE" ]]; then
    echo "  exists: yes"
    echo "  size:   $(wc -c < "$SNAPSHOT_FILE" 2>/dev/null || echo '?') bytes"
    if [[ -f "$SNAPSHOT_META" ]]; then
      echo "  meta:   $(cat "$SNAPSHOT_META")"
    fi
  else
    echo "  exists: no"
  fi
  echo "KG DB: $KG_DB"
  if [[ -f "$KG_DB" ]]; then
    echo "  exists: yes"
    echo "  size:   $(wc -c < "$KG_DB" 2>/dev/null || echo '?') bytes"
  else
    echo "  exists: no"
  fi
}

# ── Main dispatch ─────────────────────────────────────────────────────────────

cmd="${1:-help}"; shift || true
case "$cmd" in
  export)
    # Parse --mode flag or positional
    local_mode="best"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --mode) local_mode="${2:-best}"; shift 2 ;;
        best|fast) local_mode="$1"; shift ;;
        *) echo "ERROR: unknown option '$1'" >&2; exit 2 ;;
      esac
    done
    export_snapshot "$local_mode"
    ;;
  import)  import_snapshot ;;
  status)  status_snapshot ;;
  help|--help|-h)
    echo "Usage: kg-export.sh export [--mode best|fast] | import | status" >&2
    exit 0 ;;
  *) echo "ERROR: unknown command '$cmd'" >&2; exit 2 ;;
esac
