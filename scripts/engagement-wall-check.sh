#!/usr/bin/env bash
# engagement-wall-check.sh — SE-271 S3: Cross-client isolation verification
# Verifies 7-layer ethical walls between client engagements.
# Tags artifacts, blocks cross-client contamination, reports violations.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGAGEMENTS_DIR="$ROOT/engagements"

usage() {
  cat <<EOF
Usage: bash scripts/engagement-wall-check.sh [options]

Verifies cross-client isolation across 7 layers.

Options:
  --client CLIENT        Check walls for a specific client (default: all)
  --engagement NAME      Check specific engagement (requires --client)
  --layer N              Check specific layer (1-7, default: all)
  --check-only           Dry run — check but do not tag or block
  --tag-artifacts        Tag untagged artifacts with current client
  --json                 Output JSON violations report
  --strict               Exit non-zero on any violation (default: warn only)
  --help, -h             This help

Layers:
  1: episodic_memory     .claude/external-memory/auto/
  2: semantic_memory     output/, .claude/enterprise/
  3: active_context      .claude/profiles/
  4: knowledge_graph     .savia/knowledge-graph* patterns
  5: domes               output/domes/, .claude/enterprise/domes/
  6: federation_exchange coordinacion/exchange/
  7: briefs_drafts_engrams output/reports/, output/drafts/, output/briefs/
EOF
}

CLIENT=""; ENGAGEMENT=""; LAYER=""; CHECK_ONLY=false; TAG_ARTIFACTS=false
JSON_OUT=false; STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client)        CLIENT="$2";         shift 2 ;;
    --engagement)    ENGAGEMENT="$2";     shift 2 ;;
    --layer)         LAYER="$2";          shift 2 ;;
    --check-only)    CHECK_ONLY=true;     shift ;;
    --tag-artifacts) TAG_ARTIFACTS=true;  shift ;;
    --json)          JSON_OUT=true;       shift ;;
    --strict)        STRICT=true;         shift ;;
    --help|-h)       usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

VIOLATIONS=()
VIOLATIONS_JSON="["

# ── Discover engagements ────────────────────────────────────────────────────────
discover_engagements() {
  if [[ -n "$CLIENT" ]] && [[ -n "$ENGAGEMENT" ]]; then
    local yf="$ENGAGEMENTS_DIR/$CLIENT/${ENGAGEMENT}.yaml"
    if [[ -f "$yf" ]]; then
      echo "$CLIENT|$ENGAGEMENT|$yf"
    fi
    return
  fi
  if [[ -n "$CLIENT" ]]; then
    local dir="$ENGAGEMENTS_DIR/$CLIENT"
    if [[ -d "$dir" ]]; then
      for yf in "$dir"/*.yaml; do
        [[ -f "$yf" ]] || continue
        local ename
        ename=$(basename "$yf" .yaml)
        echo "$CLIENT|$ename|$yf"
      done
    fi
    return
  fi
  if [[ -d "$ENGAGEMENTS_DIR" ]]; then
    for client_dir in "$ENGAGEMENTS_DIR"/*/; do
      [[ -d "$client_dir" ]] || continue
      local cslug
      cslug=$(basename "$client_dir")
      for yf in "$client_dir"/*.yaml; do
        [[ -f "$yf" ]] || continue
        local ename
        ename=$(basename "$yf" .yaml)
        echo "$cslug|$ename|$yf"
      done
    done
  fi
}

# ── Read wall mode from engagement YAML ─────────────────────────────────────────
get_wall_mode() {
  local yf="$1"
  grep -E "^\s+mode:" "$yf" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "strict"
}

get_client_from_yaml() {
  local yf="$1"
  grep -E "^\s+client:" "$yf" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo ""
}

# ── Tag check: does file have client tag? ───────────────────────────────────────
has_client_tag() {
  local file="$1"
  local client="$2"
  [[ ! -f "$file" ]] && return 1
  grep -q "client:${client}" "$file" 2>/dev/null
}

has_any_client_tag() {
  local file="$1"
  [[ ! -f "$file" ]] && return 1
  grep -qE 'client:[a-z0-9][a-z0-9-]*' "$file" 2>/dev/null
}

# Primera etiqueta de cliente del fichero distinta de $2 (vacío si no hay).
# Mirar solo la primera etiqueta dejaba pasar «client:propio … client:ajeno».
get_foreign_tag() {
  local file="$1" own="$2"
  [[ ! -f "$file" ]] && { echo ""; return; }
  grep -oE 'client:[a-z0-9][a-z0-9-]*' "$file" 2>/dev/null | cut -d: -f2 | grep -vxF -- "$own" | head -1 || true
}

# Etiqueta a evaluar en las capas que comparan con los engagements activos:
# la primera que NO pertenece a ninguno; si todas pertenecen, la primera.
# Mirar solo la primera dejaba pasar «client:conocido … client:desconocido».
get_check_tag() {
  local file="$1"
  [[ ! -f "$file" ]] && { echo ""; return; }
  local known tags t
  known=$(discover_engagements | cut -d'|' -f1)
  tags=$(grep -oE 'client:[a-z0-9][a-z0-9-]*' "$file" 2>/dev/null | cut -d: -f2 || true)
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    grep -qxF -- "$t" <<< "$known" || { echo "$t"; return; }
  done <<< "$tags"
  head -1 <<< "$tags"
}

tag_artifact() {
  local file="$1"
  local client="$2"
  local engagement="$3"
  local tag="<!-- SE-271-WALL client:${client} engagement:${engagement} confidentiality:auto -->"
  # Only tag text files
  if [[ -f "$file" ]] && file "$file" 2>/dev/null | grep -qE 'text|JSON|YAML|empty' 2>/dev/null; then
    if ! grep -q "client:${client}" "$file" 2>/dev/null; then
      echo "" >> "$file"
      echo "$tag" >> "$file"
    fi
  fi
}

# ── Record violation ────────────────────────────────────────────────────────────
record_violation() {
  local layer="$1"
  local artifact="$2"
  local message="$3"
  local client_a="$4"
  local client_b="$5"
  VIOLATIONS+=("$layer|$artifact|$message|$client_a|$client_b")

  local escaped_msg
  escaped_msg=$(echo "$message" | tr '"' "'" | head -c 200)
  local escaped_artifact
  escaped_artifact=$(echo "$artifact" | tr '"' "'" | head -c 200)

  if [[ "$VIOLATIONS_JSON" != "[" ]]; then
    VIOLATIONS_JSON+=","
  fi
  VIOLATIONS_JSON+="{\"layer\":\"$layer\",\"artifact\":\"$escaped_artifact\",\"violation\":\"$escaped_msg\",\"client_a\":\"$client_a\",\"client_b\":\"$client_b\"}"
}

# ── Check layer 1: Episodic memory ──────────────────────────────────────────────
check_layer_episodic() {
  local l="episodic_memory"
  local mem_dir="$ROOT/.claude/external-memory/auto"
  [[ ! -d "$mem_dir" ]] && return

  for eng in $(discover_engagements); do
    IFS='|' read -r cslug ename yf <<< "$eng"
    local wmode
    wmode=$(get_wall_mode "$yf")

    # Check memory entries for cross-tagging
    if [[ -f "$mem_dir/MEMORY.md" ]]; then
      if has_any_client_tag "$mem_dir/MEMORY.md"; then
        local file_clients
        file_clients=$(grep -oE 'client:[a-z0-9][a-z0-9-]*' "$mem_dir/MEMORY.md" 2>/dev/null | sort -u || true)
        local client_count
        client_count=$(echo "$file_clients" | grep -c . 2>/dev/null || [ $? -eq 1 ] || echo 0)
        if [[ "$client_count" -gt 1 ]]; then
          record_violation "$l" "$mem_dir/MEMORY.md" \
            "Episodic memory file contains $client_count client tags — should be confined per client" \
            "" ""
        fi
      fi
    fi

    # Check per-engagement memory files
    local eng_mem="$ENGAGEMENTS_DIR/$cslug/memory"
    if [[ -d "$eng_mem" ]]; then
      shopt -s nullglob 2>/dev/null || true
      local mem_files=("$eng_mem"/*.md "$eng_mem"/*.jsonl)
      shopt -u nullglob 2>/dev/null || true
      for memf in "${mem_files[@]}"; do
        [[ -f "$memf" ]] || continue
        if has_any_client_tag "$memf"; then
          local tagged
          tagged=$(get_foreign_tag "$memf" "$cslug")
          if [[ -n "$tagged" ]] && [[ "$tagged" != "$cslug" ]]; then
            record_violation "$l" "$memf" \
              "Memory file tagged client:$tagged but belongs to client:$cslug" \
              "$cslug" "$tagged"
          fi
        fi
      done
    fi
  done
}

# ── Check layer 2: Semantic memory ──────────────────────────────────────────────
check_layer_semantic() {
  local l="semantic_memory"
  local sem_dirs=(
    "$ROOT/output"
    "$ROOT/.claude/enterprise"
  )

  for dir in "${sem_dirs[@]}"; do
    [[ ! -d "$dir" ]] && continue
    # Scan recent files (last 100)
    while IFS= read -r -d '' f; do
      [[ -f "$f" ]] || continue
      if has_any_client_tag "$f"; then
        local tagged
        tagged=$(get_check_tag "$f")
        # Check against all other engagement clients
        for eng in $(discover_engagements); do
          IFS='|' read -r cslug ename yf <<< "$eng"
          if [[ "$tagged" == "$cslug" ]]; then
            # Tag matches this client — fine if we're in their context
            continue 2  # continue outer while to next file
          fi
        done
        # Tagged with unknown client
        if [[ -n "$tagged" ]]; then
          record_violation "$l" "$f" \
            "Semantic artifact tagged client:$tagged — client not in active engagements" \
            "" "$tagged"
        fi
      fi
    done < <(find "$dir" -maxdepth 3 -type f \( -name "*.md" -o -name "*.json" -o -name "*.jsonl" -o -name "*.yaml" \) -print0 2>/dev/null | head -z -n 100)
  done
}

# ── Check layer 3: Active context ───────────────────────────────────────────────
check_layer_active_context() {
  local l="active_context"
  local dir="$ROOT/.claude/profiles"
  [[ ! -d "$dir" ]] && return

  for eng in $(discover_engagements); do
    IFS='|' read -r cslug ename yf <<< "$eng"
    local wmode
    wmode=$(get_wall_mode "$yf")
    local profile_dir="$dir/$cslug"
    if [[ -d "$profile_dir" ]]; then
      shopt -s nullglob 2>/dev/null || true
      local pf_files=("$profile_dir"/*.md "$profile_dir"/*.yaml)
      shopt -u nullglob 2>/dev/null || true
      for pf in "${pf_files[@]}"; do
        [[ -f "$pf" ]] || continue
        if has_any_client_tag "$pf"; then
          local tagged
          tagged=$(get_foreign_tag "$pf" "$cslug")
          if [[ -n "$tagged" ]] && [[ "$tagged" != "$cslug" ]]; then
            record_violation "$l" "$pf" \
              "Profile artifact tagged client:$tagged but profile belongs to client:$cslug" \
              "$cslug" "$tagged"
          fi
        fi
      done
    fi
  done
}

# ── Check layer 4: Knowledge graph ──────────────────────────────────────────────
check_layer_knowledge_graph() {
  local l="knowledge_graph"
  local kg_db="${HOME}/.savia/knowledge-graph.db"

  if [[ -f "$kg_db" ]]; then
    if command -v sqlite3 >/dev/null 2>&1; then
      # Check if entities table has client tags
      local has_col
      has_col=$(sqlite3 "$kg_db" "SELECT COUNT(*) FROM pragma_table_info('entities') WHERE name='client_tag'" 2>/dev/null || echo 0)
      if [[ "$has_col" -eq 0 ]]; then
        record_violation "$l" "$kg_db" \
          "Knowledge graph entities table missing client_tag column — cannot enforce wall" \
          "" ""
      else
        # Check for entities without client tags
        local untagged
        untagged=$(sqlite3 "$kg_db" "SELECT COUNT(*) FROM entities WHERE client_tag IS NULL OR client_tag = ''" 2>/dev/null || echo 0)
        if [[ "$untagged" -gt 0 ]]; then
          record_violation "$l" "$kg_db" \
            "Knowledge graph has $untagged entities without client_tag" \
            "" ""
        fi
        # Check for cross-client entity references
        local cross_refs
        cross_refs=$(sqlite3 "$kg_db" "
          SELECT COUNT(*) FROM relations r
          JOIN entities e1 ON r.source_id = e1.id
          JOIN entities e2 ON r.target_id = e2.id
          WHERE e1.client_tag != e2.client_tag AND e1.client_tag != '' AND e2.client_tag != ''
        " 2>/dev/null || echo 0)
        if [[ "$cross_refs" -gt 0 ]]; then
          record_violation "$l" "$kg_db" \
            "Knowledge graph has $cross_refs cross-client relations" \
            "" ""
        fi
      fi
    fi
  fi

  # Check flat-file KG markers
  local kg_files
  kg_files=$(find "$ROOT" -maxdepth 3 -name "*.kg.json" -o -name "*.kg.yaml" 2>/dev/null | head -20)
  if [[ -n "$kg_files" ]]; then
    for kgf in $kg_files; do
      [[ -f "$kgf" ]] || continue
      if has_any_client_tag "$kgf"; then
        local tagged
        for eng in $(discover_engagements); do
          IFS='|' read -r cslug ename yf <<< "$eng"
          tagged=$(get_foreign_tag "$kgf" "$cslug")
          if [[ -n "$tagged" ]]; then
            record_violation "$l" "$kgf" \
              "KG artifact tagged client:$tagged — potential cross-contamination" \
              "" "$tagged"
          fi
        done
      fi
    done
  fi
}

# ── Check layer 5: Domes ────────────────────────────────────────────────────────
check_layer_domes() {
  local l="domes"
  local dome_dirs=(
    "$ROOT/output/domes"
    "$ROOT/.claude/enterprise/domes"
  )

  for dir in "${dome_dirs[@]}"; do
    [[ ! -d "$dir" ]] && continue
    while IFS= read -r -d '' df; do
      [[ -f "$df" ]] || continue
      if has_any_client_tag "$df"; then
        local tagged
        tagged=$(get_check_tag "$df")

        # Check against all engagements
        local found_match=false
        for eng in $(discover_engagements); do
          IFS='|' read -r cslug ename yf <<< "$eng"
          if [[ "$tagged" == "$cslug" ]]; then
            found_match=true
            break
          fi
        done
        if ! $found_match && [[ -n "$tagged" ]]; then
          record_violation "$l" "$df" \
            "Dome artifact tagged client:$tagged but client not in engagements" \
            "" "$tagged"
        fi
      elif [[ -n "$CLIENT" ]]; then
        record_violation "$l" "$df" \
          "Dome artifact lacks client tag — cannot verify isolation" \
          "$CLIENT" ""
      fi
    done < <(find "$dir" -type f \( -name "*.md" -o -name "CONTEXT_DOME.md" \) -print0 2>/dev/null | head -z -n 50)
  done
}

# ── Check layer 6: Federation exchange ──────────────────────────────────────────
check_layer_federation() {
  local l="federation_exchange"
  local fed_dir="$ROOT/coordinacion/exchange"
  [[ ! -d "$fed_dir" ]] && return

  for eng in $(discover_engagements); do
    IFS='|' read -r cslug ename yf <<< "$eng"
    local wmode
    wmode=$(get_wall_mode "$yf")

    while IFS= read -r -d '' ef; do
      [[ -f "$ef" ]] || continue
      if has_any_client_tag "$ef"; then
        local tagged
        tagged=$(get_foreign_tag "$ef" "$cslug")
        if [[ -n "$tagged" ]] && [[ "$tagged" != "$cslug" ]]; then
          # In strict mode, this is a violation
          # In permeable-declared, check for operator declaration
          if [[ "$wmode" == "strict" ]]; then
            record_violation "$l" "$ef" \
              "Federation exchange file tagged client:$tagged entering client:$cslug context — wall:$wmode blocks" \
              "$cslug" "$tagged"
          else
            # Permeable: check if declaration exists
            local decl_file="$ENGAGEMENTS_DIR/$cslug/wall/permeability-declarations.yaml"
            if [[ -f "$decl_file" ]]; then
              local has_decl
              has_decl=$(grep -c "client:${tagged}" "$decl_file" 2>/dev/null || [ $? -eq 1 ] || echo 0)
              if [[ "$has_decl" -eq 0 ]]; then
                record_violation "$l" "$ef" \
                  "Federation exchange file tagged client:$tagged entering client:$cslug context — no operator declaration" \
                  "$cslug" "$tagged"
              fi
            else
              record_violation "$l" "$ef" \
                "Federation exchange file tagged client:$tagged entering client:$cslug context — no permeability declaration" \
                "$cslug" "$tagged"
            fi
          fi
        fi
      fi
    done < <(find "$fed_dir" -type f -name "*.jsonl" -print0 2>/dev/null | head -z -n 50)
  done
}

# ── Check layer 7: Briefs, drafts, engrams ──────────────────────────────────────
check_layer_briefs_drafts() {
  local l="briefs_drafts_engrams"
  local bde_dirs=(
    "$ROOT/output/reports"
    "$ROOT/output/drafts"
    "$ROOT/output/briefs"
  )

  for dir in "${bde_dirs[@]}"; do
    [[ ! -d "$dir" ]] && continue
    while IFS= read -r -d '' bf; do
      [[ -f "$bf" ]] || continue

      # Check if file has ANY client tag
      if ! has_any_client_tag "$bf"; then
        if $TAG_ARTIFACTS && [[ -n "$CLIENT" ]]; then
          tag_artifact "$bf" "$CLIENT" "${ENGAGEMENT:-unknown}"
        else
          if [[ -n "$CLIENT" ]]; then
            record_violation "$l" "$bf" \
              "Brief/draft/engram lacks client tag" \
              "$CLIENT" ""
          fi
        fi
        continue
      fi

      local tagged
      tagged=$(get_check_tag "$bf")

      # In strict mode, check against all current engagements
      if [[ -n "$tagged" ]]; then
        local found_match=false
        for eng in $(discover_engagements); do
          IFS='|' read -r cslug ename yf <<< "$eng"
          if [[ "$tagged" == "$cslug" ]]; then
            found_match=true
            # In specific client mode, check all OTHER clients too
            if [[ -n "$CLIENT" ]] && [[ "$CLIENT" != "$cslug" ]]; then
              for eng2 in $(discover_engagements); do
                IFS='|' read -r c2 e2 y2 <<< "$eng2"
                if [[ -f "$y2" ]]; then
                  local wmode2
                  wmode2=$(get_wall_mode "$y2")
                  if [[ "$wmode2" == "strict" ]] && echo "$bf" | grep -q "$ENGAGEMENTS_DIR/$c2" 2>/dev/null; then
                    : # file physically in c2's dir but tagged cslug — that's a cross
                  fi
                fi
              done
            fi
            break
          fi
        done
        if ! $found_match; then
          record_violation "$l" "$bf" \
            "Brief/draft/engram tagged with unknown client:$tagged" \
            "" "$tagged"
        fi
      fi
    done < <(find "$dir" -maxdepth 2 -type f \( -name "*.md" -o -name "*.pdf" -o -name "*.json" \) -print0 2>/dev/null | head -z -n 100)
  done

  # Also check per-engagement output dirs
  for eng in $(discover_engagements); do
    IFS='|' read -r cslug ename yf <<< "$eng"
    local eng_dir="$ENGAGEMENTS_DIR/$cslug"
    while IFS= read -r -d '' bf; do
      [[ -f "$bf" ]] || continue
      if has_any_client_tag "$bf"; then
        local tagged
        tagged=$(get_foreign_tag "$bf" "$cslug")
        if [[ -n "$tagged" ]] && [[ "$tagged" != "$cslug" ]]; then
          record_violation "$l" "$bf" \
            "Engagement artifact tagged client:$tagged found in client:$cslug directory" \
            "$cslug" "$tagged"
        fi
      fi
    done < <(find "$eng_dir" -type f \( -name "*.md" -o -name "*.json" -o -name "*.yaml" \) -print0 2>/dev/null | head -z -n 50)
  done
}

# ── Execute checks ──────────────────────────────────────────────────────────────
ENGAGEMENT_COUNT=0
for eng in $(discover_engagements); do
  ENGAGEMENT_COUNT=$((ENGAGEMENT_COUNT + 1))
done

check_all_layers() {
  local target_layer="$1"

  if [[ -z "$target_layer" ]]; then
    check_layer_episodic
    check_layer_semantic
    check_layer_active_context
    check_layer_knowledge_graph
    check_layer_domes
    check_layer_federation
    check_layer_briefs_drafts
    return
  fi

  case "$target_layer" in
    1) check_layer_episodic ;;
    2) check_layer_semantic ;;
    3) check_layer_active_context ;;
    4) check_layer_knowledge_graph ;;
    5) check_layer_domes ;;
    6) check_layer_federation ;;
    7) check_layer_briefs_drafts ;;
  esac
}

check_all_layers "$LAYER"

# ── Output ──────────────────────────────────────────────────────────────────────
VIOLATIONS_JSON+="]"

if $JSON_OUT; then
  python3 << PYEOF
import json, sys
raw = '''$VIOLATIONS_JSON'''
try:
    violations = json.loads(raw)
except:
    violations = []
report = {
    "engagements": $ENGAGEMENT_COUNT,
    "checked_layers": $( [[ -n "$LAYER" ]] && echo "[$LAYER]" || echo '[1,2,3,4,5,6,7]' ),
    "violation_count": ${#VIOLATIONS[@]},
    "violations": violations,
    "wall_intact": $([[ ${#VIOLATIONS[@]} -eq 0 ]] && echo 'True' || echo 'False')
}
print(json.dumps(report, indent=2))
PYEOF
else
  echo "=== Engagement Wall Check: ${#VIOLATIONS[@]} violations ==="
  echo "  Engagements: $ENGAGEMENT_COUNT"
  echo "  Layers checked: ${LAYER:-all 7}"
  echo ""

  if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    echo "  WALL INTACT — no cross-client violations detected"
  else
    for v in "${VIOLATIONS[@]}"; do
      IFS='|' read -r vlayer vartif vmsg vca vcb <<< "$v"
      echo "  [VIOLATION] $vlayer: $vmsg"
      echo "      Artifact: $vartif"
      [[ -n "$vca" ]] && echo "      Client A: $vca"
      [[ -n "$vcb" ]] && echo "      Client B: $vcb"
      echo ""
    done
  fi
fi

# ── Exit code ───────────────────────────────────────────────────────────────────
if $STRICT && [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  exit 1
fi
exit 0
