#!/bin/bash
# savia-compat.sh — Portable helpers for cross-platform compatibility
# Sourced by Company Savia scripts. Replaces GNU-only patterns.
#
# Functions:
#   portable_base64_encode  — base64 without -w0 (works on macOS+Linux)
#   portable_base64_decode  — base64 -d with -D fallback
#   portable_sed_i          — sed -i '' (macOS) vs sed -i (Linux)
#   portable_read_config    — grep+cut replacement for grep -oP
#   portable_yaml_field     — extract YAML frontmatter value
#   portable_valid_date     — YYYY-MM-DD real (GNU o BSD date)
#   portable_wc_l           — wc -l without leading spaces

# ── Base64 encode (no line wrapping) ─────────────────────────────
portable_base64_encode() {
  local file="${1:-}"
  if [ -n "$file" ] && [ -f "$file" ]; then
    base64 "$file" | tr -d '\n'
  else
    base64 | tr -d '\n'
  fi
}

# ── Base64 decode ────────────────────────────────────────────────
portable_base64_decode() {
  base64 -d 2>/dev/null || base64 -D 2>/dev/null
}

# ── Sed in-place (macOS needs '' arg, Linux does not) ────────────
portable_sed_i() {
  local expression="$1"
  local file="$2"
  case "$OSTYPE" in
    darwin*) sed -i '' "$expression" "$file" ;;
    *)       sed -i "$expression" "$file" ;;
  esac
}

# ── Read key=value config (replaces grep -oP) ────────────────────
portable_read_config() {
  local key="$1"
  local file="$2"
  grep "^${key}=" "$file" 2>/dev/null | cut -d= -f2- || echo ""
}

# ── Extract YAML frontmatter field (replaces grep -oP) ───────────
portable_yaml_field() {
  local field="$1"
  local file="$2"
  grep "${field}:" "$file" 2>/dev/null \
    | head -1 \
    | sed 's/.*'"${field}"':[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/' \
    || echo ""
}

# ── Fecha YYYY-MM-DD real (rechaza 2026-02-30); GNU date o BSD date
portable_valid_date() {
  [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  [ "$(date -d "$1" +%Y-%m-%d 2>/dev/null)" = "$1" ] \
    || [ "$(date -j -f %Y-%m-%d "$1" +%Y-%m-%d 2>/dev/null)" = "$1" ]
}

# ── wc -l without leading spaces ────────────────────────────────
portable_wc_l() {
  wc -l < "$1" | tr -d ' '
}
