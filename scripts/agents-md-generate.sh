#!/usr/bin/env bash
# agents-md-generate.sh — SE-078
#
# Generates AGENTS.md from .opencode/agents/*.md. AGENTS.md is the cross-frontend
# index that OpenCode v1.14, Codex, Cursor and other modern frontends read as
# context (see https://agents.md/). The source of truth remains
# .opencode/agents/*.md — AGENTS.md is DERIVED, never hand-edited.
#
# Idempotent: same input → same output (no timestamps in body). pr-plan G14
# (`agents-md-drift-check.sh`) calls this with --check to fail PRs where an
# agent edit was not propagated.
#
# Usage:
#   bash scripts/agents-md-generate.sh                # print to stdout
#   bash scripts/agents-md-generate.sh --apply        # atomic write to AGENTS.md
#   bash scripts/agents-md-generate.sh --check        # exit 1 if drift vs current AGENTS.md
#
# Exit codes: 0 ok | 1 drift (--check only) | 2 usage | 3 agents dir missing
#
# Reference: SE-078 (docs/propuestas/SE-078-agents-md-cross-frontend.md)
# Reference: docs/rules/domain/agents-md-source-of-truth.md
# Reference: docs/rules/domain/autonomous-safety.md

set -uo pipefail

ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AGENTS_DIR="${AGENTS_DIR:-${ROOT}/.opencode/agents}"
TARGET="${AGENTS_MD:-${ROOT}/AGENTS.md}"
MODE="generate"

usage() {
  cat <<USG
Usage: agents-md-generate.sh [--apply | --check]

Modes:
  (default)  Print AGENTS.md content to stdout (dry run)
  --apply    Write AGENTS.md atomically (rewrites the file)
  --check    Exit 1 if generated content differs from on-disk AGENTS.md

Env:
  AGENTS_DIR  default \${ROOT}/.opencode/agents
  AGENTS_MD   default \${ROOT}/AGENTS.md
USG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)  MODE="apply"; shift ;;
    --check)  MODE="check"; shift ;;
    --generate) MODE="generate"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "${AGENTS_DIR}" ]] || { echo "ERROR: agents dir not found: ${AGENTS_DIR}" >&2; exit 3; }

# SE-371: congelación en sesión activa — regenerar AGENTS.md a mitad de una
# conversación invalida el prefijo de instrucciones (prompt cache) en el
# siguiente turno. Los runs autónomos/cron sin sesión viva regeneran normal.
# Sesión activa = env SAVIA_SESSION_ACTIVE=1 o marker del hook cache-hygiene.
if [[ "${MODE:-print}" == "apply" ]]; then
  _cache_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ "${SAVIA_SESSION_ACTIVE:-0}" == "1" || -f "$_cache_root/data/.cache-session-active" ]]; then
    echo "SKIP: sesión activa (SE-371) — regeneración de AGENTS.md congelada." >&2
    exit 3
  fi
fi

# Extract a single field from frontmatter. Handles both `key: value` and the
# multiline `key: >` block form (used heavily for `description`).
extract_field() {
  local file="$1" field="$2"
  awk -v field="^${field}:" '
    /^---$/ { c++; if (c>=2) exit; next }
    c==1 {
      if ($0 ~ field) {
        sub(field, "")
        # Strip leading whitespace
        sub(/^[[:space:]]+/, "")
        if ($0 ~ /^>/) {
          # Multiline block — gather until next top-level key or block end
          collecting = 1
          buf = ""
          next
        }
        # Strip surrounding quotes
        gsub(/^"|"$/, "")
        print
        exit
      }
      if (collecting) {
        if ($0 ~ /^[[:alpha:]_][^[:space:]]*:/) {
          collecting = 0
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", buf)
          print buf
          exit
        }
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 != "") buf = buf " " $0
      }
    }
    END {
      if (collecting) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", buf)
        print buf
      }
    }
  ' "$file"
}

# Extract the `tools:` list — entries are dash-prefixed in YAML
extract_tools() {
  local file="$1"
  awk '
    /^---$/ { c++; if (c>=2) exit; next }
    c==1 && /^tools:/ { collecting = 1; next }
    c==1 && collecting {
      if ($0 ~ /^[[:alpha:]_][^[:space:]]*:/) { exit }
      if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        sub(/^[[:space:]]*-[[:space:]]+/, "")
        sub(/[[:space:]]+$/, "")
        if (out == "") { out = $0 } else { out = out "," $0 }
      }
    }
    END { print out }
  ' "$file"
}

# Truncate to 120 chars and escape pipes (so it survives a markdown table cell)
sanitise_description() {
  local s="$1"
  # Collapse whitespace
  s=$(echo "$s" | tr -s '[:space:]' ' ' | sed -E 's/^ +| +$//g')
  # Escape pipes
  s="${s//|/\\|}"
  if [[ ${#s} -gt 120 ]]; then
    s="${s:0:117}..."
  fi
  echo "$s"
}

# Build the body
build() {
  cat <<'HEADER'
---
lang: es
---
# AGENTS.md

> Auto-generated from `.opencode/agents/*.md`. **Do not edit by hand.**
> Source of truth: `docs/rules/domain/agents-md-source-of-truth.md` (SE-078).

## Savia startup — all frontends

Before working, read `CLAUDE.md` and its critical context files explicitly:
`docs/critical-facts.md`, `.claude/profiles/savia.md`,
`docs/rules/domain/radical-honesty.md`, `docs/rules/domain/autonomous-safety.md`,
`docs/rules/domain/caveman-default.md`, and
`docs/rules/domain/knowledge-discovery-priority.md`.
Read `.claude/profiles/active-user.md` and the active profile's preferences
when present; keep private profile and memory data out of tracked output.
Do not assume that another frontend expands Claude-style `@imports`.
Before working in a project, read its `projects/<name>/CLAUDE.md`.

Skills share one source: `.claude/skills/`. OpenCode exposes it through
`.opencode/skills`; Codex through `.agents/skills`. Use `SKILLS.md` and
`docs/RESOLVER.md` to find the relevant instructions, then read the skill.
This registry describes roles; its model identifiers and permissions are
OpenCode metadata, not automatically configured Codex subagents.

For concurrent sessions in the same directory, read
`docs/rules/domain/parallel-session-protocol.md`. The working tree, branch
and Git index are shared: coordinate file ownership, serialize Git mutations,
and never switch branches, stage another session's edits or discard changes.
Use separate worktrees when tasks need independent branches.
Hooks and MCP configuration are frontend-specific: do not assume Codex runs
`.claude/settings.json` hooks or `.opencode/plugins`. Run the applicable
validation scripts explicitly and report any unverified gate.
HEADER
  python3 "${ROOT}/scripts/dual-cli/autonomy.py" contract
  cat <<'HEADER'

## How to use

This file is the cross-frontend mirror of Savia's agent registry. Claude Code
reads `.opencode/agents/*.md` directly; OpenCode v1.14, Codex, Cursor and other
modern frontends pick up this `AGENTS.md` as freeform context. The source of
truth is `.opencode/agents/*.md`; this index is regenerated automatically by
the Stop hook `agents-md-auto-regenerate.sh` whenever an agent file changes.

## Agents

| Name | Model | Permission | Tools | Description |
|---|---|---|---|---|
HEADER
  # Iterate agents alphabetically — sort -V for stable output
  local rows=""
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    local name perm desc tools model
    name=$(extract_field "$f" "name")
    [[ -z "$name" ]] && { echo "WARN: skipping ${f}: no name field" >&2; continue; }
    perm=$(extract_field "$f" "permission_level")
    [[ -z "$perm" ]] && perm="—"
    model=$(extract_field "$f" "model")
    [[ -z "$model" ]] && model="—"
    desc=$(extract_field "$f" "description")
    desc=$(sanitise_description "$desc")
    tools=$(extract_tools "$f")
    [[ -z "$tools" ]] && tools="—"
    rows+="| ${name} | ${model} | ${perm} | ${tools} | ${desc} |"$'\n'
  done < <(find "${AGENTS_DIR}" -maxdepth 1 -type f -name '*.md' | sort)
  printf '%s' "$rows"
}

GENERATED=$(build)

case "$MODE" in
  generate) printf '%s' "$GENERATED" ;;
  apply)
    if [[ "${SENTINEL_MODE:-0}" == "1" ]]; then
      # SPEC-180 piloto: write only the agents-table block via sentinel
      # primitive, preserving any @user blocks present in the file.
      table_content=$(printf '%s' "$GENERATED" | awk '/^\| Name \| Model \|/{flag=1} flag')
      [[ -f "$TARGET" ]] || {
        # First-time bootstrap: write header-only file (without table)
        printf '%s' "$GENERATED" | awk '/^\| Name \| Model \|/{exit} {print}' > "$TARGET"
      }
      printf '%s' "$table_content" | bash "$(dirname "$0")/sentinel-regen.sh" inject "$TARGET" agents-table
      echo "wrote (sentinel) ${TARGET} ($(wc -l < "$TARGET") lines)"
    else
      tmp=$(mktemp)
      printf '%s' "$GENERATED" > "$tmp"
      mv "$tmp" "$TARGET"
      echo "wrote ${TARGET} ($(wc -l < "$TARGET") lines)"
    fi
    ;;
  check)
    if [[ ! -f "$TARGET" ]]; then
      echo "drift: ${TARGET} missing — run --apply" >&2
      exit 1
    fi
    if diff -u "$TARGET" <(printf '%s' "$GENERATED") >/dev/null; then
      echo "in sync"
    else
      echo "drift detected — diff vs --apply output:" >&2
      diff -u "$TARGET" <(printf '%s' "$GENERATED") | head -40 >&2 || true
      exit 1
    fi
    ;;
esac
