#!/usr/bin/env bash
# agents-catalog-sync.sh — SE-047 Slice 1 agents catalog auto-sync.
#
# Genera tabla canónica desde `.opencode/agents/*.md` frontmatter y la
# compara con / sincroniza en `docs/rules/domain/agents-catalog.md`.
#
# Elimina el drift: "catalog dice 56 agents, reales 65+" (audit D5).
#
# Usage:
#   agents-catalog-sync.sh --check              # exit 1 si drift detectado
#   agents-catalog-sync.sh --generate           # print tabla a stdout
#   agents-catalog-sync.sh --apply              # reescribe catalog
#   agents-catalog-sync.sh --json
#
# Exit codes:
#   0 — en sync (o --generate / --apply exitoso)
#   1 — drift detectado (--check)
#   2 — usage error
#
# Ref: SE-047, audit-arquitectura-20260420.md D5
# Safety: solo --apply escribe, resto es read-only. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE=""
JSON=0
CATALOG_PATH="$PROJECT_ROOT/docs/rules/domain/agents-catalog.md"
# SE-073: source of truth = .opencode/agents/ (consistent with
# scripts/agents-md-generate.sh). Override via AGENTS_DIR for tests.
AGENTS_DIR="${AGENTS_DIR:-$PROJECT_ROOT/.opencode/agents}"

usage() {
  cat <<EOF
Usage:
  $0 --check | --generate | --apply [--json]

Modes:
  --check        Exit 1 if agents-catalog.md out of sync with .opencode/agents/
  --generate     Print generated table to stdout (no write)
  --apply        Rewrite docs/rules/domain/agents-catalog.md (atomic)

Optional:
  --json         JSON output

Ref: SE-047. Source of truth = .opencode/agents/*.md frontmatter.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --generate) MODE="generate"; shift ;;
    --apply) MODE="apply"; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ -z "$MODE" ]] && { echo "ERROR: --check / --generate / --apply required" >&2; exit 2; }
[[ ! -d "$AGENTS_DIR" ]] && { echo "ERROR: agents dir not found: $AGENTS_DIR" >&2; exit 2; }

# Extract frontmatter field
extract_field() {
  local file="$1" field="$2"
  awk -v f="$field:" '
    NR==1 && $0=="---" {inside=1; next}
    inside && $0=="---" {exit}
    inside && $1==f {sub(/^[^:]+:/, ""); sub(/^[ \t]+/, ""); gsub(/^"|"$/, ""); print; exit}
  ' "$file" 2>/dev/null
}

# Build table
TABLE_HEADER="| Agent | Tier | Description |"
TABLE_SEP="|---|---|---|"

generate_table() {
  echo "$TABLE_HEADER"
  echo "$TABLE_SEP"
  for f in "$AGENTS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    local name model desc
    name=$(extract_field "$f" "name")
    model=$(extract_field "$f" "model_tier")
    desc=$(extract_field "$f" "description")
    # Fallback: filename
    name="${name:-$(basename "$f" .md)}"
    # Truncate long desc
    desc=$(echo "$desc" | head -c 120 | tr '\n' ' ' | sed 's/|/\\|/g')
    model="${model:-(default)}"
    echo "| $name | $model | $desc |"
  done | sort
}

TOTAL=$(ls "$AGENTS_DIR"/*.md 2>/dev/null | wc -l)
TABLE=$(generate_table)

case "$MODE" in
  generate)
    echo "$TABLE"
    exit 0
    ;;
  check)
    [[ ! -f "$CATALOG_PATH" ]] && {
      if [[ "$JSON" -eq 1 ]]; then
        echo "{\"verdict\":\"FAIL\",\"total_agents\":$TOTAL,\"catalog_missing\":true}"
      else
        echo "FAIL: catalog not found at $CATALOG_PATH"
      fi
      exit 1
    }
    # Count table rows in catalog
    catalog_rows=$(awk '/^\|[^-]/ && NR>2' "$CATALOG_PATH" 2>/dev/null | grep -cE '^\|[^|]+\|' || true)
    # Subtract header row if present
    [[ "$catalog_rows" -gt 0 ]] && catalog_rows=$((catalog_rows - 1))
    drift=0
    [[ "$catalog_rows" -ne "$TOTAL" ]] && drift=1

    if [[ "$JSON" -eq 1 ]]; then
      echo "{\"verdict\":$([ "$drift" -eq 0 ] && echo '"PASS"' || echo '"FAIL"'),\"total_agents\":$TOTAL,\"catalog_rows\":$catalog_rows,\"drift\":$drift}"
    else
      echo "=== SE-047 Agents Catalog Sync Check ==="
      echo ""
      echo "Agents on disk: $TOTAL"
      echo "Catalog rows:   $catalog_rows"
      if [[ "$drift" -eq 0 ]]; then
        echo "VERDICT: PASS"
      else
        echo "VERDICT: FAIL (drift detected)"
        echo ""
        echo "Fix: bash $0 --apply"
      fi
    fi
    exit "$drift"
    ;;
  apply)
    # SE-220: preserve existing YAML frontmatter (context_tier, token_budget)
    # if present. SPEC-181 enforces these fields in docs/rules/domain/*.md.
    tmp=$(mktemp)
    if [[ -f "$CATALOG_PATH" ]] && head -1 "$CATALOG_PATH" 2>/dev/null | grep -q '^---$'; then
      python3 - "$CATALOG_PATH" "$tmp" <<'PY_FM' 2>/dev/null
import sys
src_fm, dst_fm = sys.argv[1], sys.argv[2]
with open(src_fm, 'r', encoding='utf-8') as f:
    lines = f.readlines()
out = []
if lines and lines[0].rstrip() == '---':
    out.append(lines[0])
    for ln in lines[1:]:
        out.append(ln)
        if ln.rstrip() == '---':
            break
    out.append('\n')
with open(dst_fm, 'w', encoding='utf-8') as f:
    f.writelines(out)
PY_FM
    fi
    cat >> "$tmp" <<HEADER
# Agents Catalog (auto-generated by scripts/agents-catalog-sync.sh)

> Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) · Total: $TOTAL agents
> Source of truth: \`.opencode/agents/*.md\` frontmatter
> Ref: SE-047, docs/rules/domain/autonomous-safety.md

HEADER
    echo "$TABLE" >> "$tmp"
    mkdir -p "$(dirname "$CATALOG_PATH")"
    mv "$tmp" "$CATALOG_PATH"
    if [[ "$JSON" -eq 1 ]]; then
      echo "{\"action\":\"applied\",\"path\":\"$CATALOG_PATH\",\"total_agents\":$TOTAL}"
    else
      echo "Applied: $CATALOG_PATH ($TOTAL agents)"
    fi
    exit 0
    ;;
esac
