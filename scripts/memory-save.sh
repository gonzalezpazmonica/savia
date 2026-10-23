#!/bin/bash
# memory-save.sh — Save, upsert, entity, session-summary (sourced by memory-store.sh)
set -uo pipefail
# SPEC-019: contradiction tracking (supersedes). SPEC-020: TTL (expires_at).
# SPEC-041: importance_tier (A/B/C), quality gate, questions[] for P3/P5.

# SPEC-037: Map type → cognitive sector (episodic/semantic/procedural/referential/reflective)
# SE-076 Slice 1: 'episode' is now first-class (was implicit via feedback/session)
map_type_to_sector() {
    case "${1:-}" in feedback|correction|episode) echo "episodic";; decision|project|bug) echo "semantic";;
        pattern|convention) echo "procedural";; reference) echo "referential";;
        discovery) echo "reflective";; *) echo "semantic";; esac
}

# SPEC-041 P5: Map type → importance tier (A=critical, B=useful, C=ephemeral)
map_type_to_importance_tier() {
    case "${1:-}" in
        feedback|correction|decision|project) echo "A" ;;
        pattern|convention|discovery|reference|architecture|bug|episode) echo "B" ;;
        session-summary|entity|config|session) echo "C" ;;
        *) echo "B" ;;
    esac
}

cmd_save() {
    local type= title= content= concepts= topic_key= project= rev=1 expires_days=
    local what= why= where= learned= supersedes_key= valid_from= quality="unverified"
    local source= entities= valid_to= pin=false origin=
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) type="$2"; shift 2 ;; --title) title="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;; --concepts) concepts="$2"; shift 2 ;;
            --topic) topic_key="$2"; shift 2 ;; --project) project="$2"; shift 2 ;;
            --what) what="$2"; shift 2 ;; --why) why="$2"; shift 2 ;;
            --where) where="$2"; shift 2 ;; --learned) learned="$2"; shift 2 ;;
            --expires) expires_days="$2"; shift 2 ;;
            --supersedes) supersedes_key="$2"; shift 2 ;;
            --valid-from) valid_from="$2"; shift 2 ;;
            --valid-to) valid_to="$2"; shift 2 ;;
            --entities) entities="$2"; shift 2 ;;     # SE-076 Slice 1: comma-separated refs
            --pin) pin=true; shift ;;                  # SE-076 Slice 1: skip auto-TTL for episodes
            --quality) quality="$2"; shift 2 ;;
            --source) source="$2"; shift 2 ;;
            --origin) origin="$2"; shift 2 ;;          # SE-352: owner|agent|untrusted|system
            *) shift ;;
        esac
    done

    # SE-076 Slice 1: episodes auto-default to 90-day TTL unless --pin
    if [[ "$type" == "episode" && -z "$expires_days" && "$pin" != "true" ]]; then
        expires_days=90
    fi
    [[ -z "$type" || -z "$title" ]] && { echo "Error: --type, --title requeridos"; exit 1; }

    # SE-072: Verified Memory axiom — "No Execution, No Memory"
    # Reject saves without provenance. Escape hatch: SAVIA_VERIFIED_MEMORY_DISABLED=true
    if [[ "${SAVIA_VERIFIED_MEMORY_DISABLED:-false}" != "true" ]]; then
        if [[ -z "$source" ]]; then
            cat >&2 <<'EOF'
Error: --source required (SE-072 Verified Memory axiom).

Valid sources:
  --source tool:<tool_name>     e.g. tool:Bash, tool:Read, tool:Edit
  --source file:<path>:<line>   e.g. file:scripts/foo.sh:42
  --source verified:<sha>       e.g. verified:abc123 (commit hash proving persistence)
  --source user:explicit        when user told agent to remember X

Rejected: speculation, plan, intent (memory must reflect verified facts, not draft thinking).
EOF
            exit 1
        fi
        # Reject blacklisted sources (drafts/speculation)
        case "$source" in
            speculation|plan|intent|draft|hypothesis)
                echo "Error: --source '$source' is blacklisted by SE-072 Verified Memory axiom. Use one of: tool:*, file:*:*, verified:*, user:explicit." >&2
                exit 1 ;;
        esac
        # Validate source format
        case "$source" in
            tool:*|file:*:*|verified:*|user:explicit) ;;
            *)
                echo "Error: --source '$source' does not match required format. Expected: tool:<name>, file:<path>:<line>, verified:<sha>, or user:explicit." >&2
                exit 1 ;;
        esac
    fi

    # SE-352: origin class — fail-safe: sin --origin explícito, se clasifica
    # según el source. Sin source confiable → untrusted (nunca owner por defecto).
    if [[ -z "$origin" ]]; then
        case "$source" in
            user:explicit) origin="owner" ;;
            tool:*|file:*:*|verified:*) origin="agent" ;;
            *) origin="untrusted" ;;
        esac
    else
        case "$origin" in
            owner|agent|untrusted|system) ;;
            *)
                echo "Error: --origin '$origin' inválido. Válidos: owner|agent|untrusted|system." >&2
                exit 1 ;;
        esac
    fi

    # SE-352: turn taint — si el turno está marcado por memoria de origen de red,
    # la entrada se degrada a untrusted aunque se pidió origin superior.
    local _taint_file="/tmp/savia-memory-taint/${SESSION_ID:-}"
    if [[ -f "$_taint_file" && "$origin" != "untrusted" ]]; then
        local _taint_epoch _now_epoch
        _taint_epoch=$(cat "$_taint_file" 2>/dev/null | head -1 || echo 0)
        _now_epoch=$(date -u +%s 2>/dev/null || echo 0)
        if [[ "$_now_epoch" -lt $((_taint_epoch + 1800)) ]]; then
            origin="untrusted"
        fi
    fi

    # Build structured content from W/W/W/L fields
    if [[ -n "$what" || -n "$why" || -n "$where" || -n "$learned" ]]; then
        local structured=""
        [[ -n "$what" ]] && structured="What: $what"
        [[ -n "$why" ]] && structured="$structured | Why: $why"
        [[ -n "$where" ]] && structured="$structured | Where: $where"
        [[ -n "$learned" ]] && structured="$structured | Learned: $learned"
        [[ -n "$content" ]] && content="$content | $structured" || content="$structured"
    fi
    [[ -z "$content" ]] && { echo "Error: --content or --what required"; exit 1; }

    content=$(echo "$content" | redact_private | head -c 2000)
    content="${content//$'\n'/\\n}"; content="${content//$'\r'/\\r}"; content="${content//$'\t'/\\t}"
    local tokens_est=$((${#content} / 4))
    local hash=$(hash_content "$content") now=$(iso8601_now)

    [[ -z "$topic_key" ]] && topic_key=$(suggest_topic_key "$type" "$title")

    # Parse concepts
    local concepts_json="[]"
    if [[ -n "$concepts" ]]; then
        concepts_json="["; IFS=',' read -ra CPTS <<< "$concepts"
        for i in "${!CPTS[@]}"; do
            concepts_json="$concepts_json\"${CPTS[$i]// /}\""
            [[ $i -lt $((${#CPTS[@]} - 1)) ]] && concepts_json="$concepts_json,"
        done; concepts_json="$concepts_json]"
    fi

    # SPEC-020: TTL
    local expires_at="null"
    if [[ -n "$expires_days" ]]; then
        expires_at=$(date -u -d "+${expires_days} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "null")
    fi

    # UPSERT + SPEC-019 contradiction
    local supersedes="null"
    if [[ -n "$topic_key" && "$topic_key" != "null" && -f "$STORE_FILE" ]]; then
        local old_line=$(grep -F "\"topic_key\":\"$topic_key\"" "$STORE_FILE" 2>/dev/null | tail -1 || true)
        if [[ -n "$old_line" ]]; then
            rev=$(($(echo "$old_line" | grep -o '"rev":[0-9]*' | cut -d: -f2) + 1))
            local old_content=$(echo "$old_line" | grep -o '"content":"[^"]*"' | sed 's/"content":"//;s/"$//' | head -c 200)
            [[ -n "$old_content" && "$old_content" != "$content" ]] && supersedes="$old_content"
            local temp_file=$(mktemp)
            grep -vF "\"topic_key\":\"$topic_key\"" "$STORE_FILE" > "$temp_file" || true
            mv "$temp_file" "$STORE_FILE"
        fi
    fi

    # Dedup (15 min)
    if [[ -f "$STORE_FILE" ]] && grep -qF "\"hash\":\"$hash\"" "$STORE_FILE" 2>/dev/null; then
        local recent_ts=$(grep -F "\"hash\":\"$hash\"" "$STORE_FILE" | tail -1 | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)
        local recent_epoch=$(date -d "$recent_ts" +%s 2>/dev/null || echo 0)
        local cutoff=$(date -u -d '15 minutes ago' +%s 2>/dev/null || echo 0)
        if [[ $recent_epoch -gt $cutoff ]]; then echo "⊘ Duplicado omitido"; return 0; fi
    fi

    # SPEC-034: temporal validity + SPEC-037: cognitive sector
    local vf="${valid_from:-$now}"
    local sector=$(map_type_to_sector "$type")

    # SPEC-034: mark superseded entry with valid_to
    if [[ -n "$supersedes_key" && -f "$STORE_FILE" ]]; then
        # Las claves de topic llevan "/" (tipo/slug): se escapan para sed.
        local _k_re _k_rep _t_rep
        _k_re=$(printf '%s' "$supersedes_key" | sed -e 's/[]\/$*.^|[&]/\\&/g')
        _t_rep=$(printf '%s' "$topic_key" | sed -e 's/[\/&]/\\&/g')
        _k_rep=$(printf '%s' "$supersedes_key" | sed -e 's/[\/&]/\\&/g')
        sed -i "s/\"topic_key\":\"$_k_re\"\(.*\)}/\"topic_key\":\"$_k_rep\"\1,\"valid_to\":\"$now\",\"superseded_by\":\"$_t_rep\"}/" "$STORE_FILE"
    fi

    # SPEC-038: auto-classify knowledge domain (skip in test mode for speed)
    local domain="general"
    if [[ "${SAVIA_TEST_MODE:-false}" != "true" ]] && command -v python3 &>/dev/null && [[ -f "$SCRIPT_DIR/memory-domains.py" ]]; then
        domain=$(python3 "$SCRIPT_DIR/memory-domains.py" classify "$title $topic_key" 2>/dev/null | head -1 | sed "s/Domains: \['\([^']*\)'.*/\1/" || echo "general")
        [[ "$domain" == "Domains:"* || -z "$domain" ]] && domain="general"
    fi

    # SPEC-041 P5: importance tier + P3: quality gate fields
    local importance_tier
    importance_tier=$(map_type_to_importance_tier "$type")

    # SE-211: map store type to semantic memory_type for KG
    local memory_type_kg="unknown"
    case "$type" in
        decision)        memory_type_kg="decision" ;;
        discovery)       memory_type_kg="observation" ;;
        bug)             memory_type_kg="error" ;;
        architecture)    memory_type_kg="artifact" ;;
        pattern)         memory_type_kg="learning" ;;
        session-summary) memory_type_kg="context" ;;
        episode)         memory_type_kg="event" ;;
        feedback)        memory_type_kg="observation" ;;
        *)               memory_type_kg="unknown" ;;
    esac

    # SE-076 Slice 1: build entities array for episodes (and any type that supplies refs)
    local entities_json="[]"
    if [[ -n "$entities" ]]; then
        IFS=',' read -ra ENTS <<< "$entities"
        entities_json="["
        for i in "${!ENTS[@]}"; do
            local e="${ENTS[$i]// /}"
            [[ -z "$e" ]] && continue
            entities_json="$entities_json\"${e//\"/\\\"}\""
            [[ $i -lt $((${#ENTS[@]} - 1)) ]] && entities_json="$entities_json,"
        done
        entities_json="$entities_json]"
    fi

    local json="{\"ts\":\"$now\",\"type\":\"$type\",\"sector\":\"$sector\",\"domain\":\"$domain\",\"title\":\"$title\",\"content\":\"$content\",\"concepts\":$concepts_json,\"tokens_est\":$tokens_est,\"topic_key\":\"${topic_key}\",\"project\":\"${project:-null}\",\"hash\":\"$hash\",\"rev\":$rev,\"valid_from\":\"$vf\",\"importance_tier\":\"$importance_tier\",\"quality\":\"$quality\",\"memory_type\":\"$memory_type_kg\",\"origin\":\"$origin\",\"questions\":[]"
    [[ "$supersedes" != "null" ]] && json="$json,\"supersedes\":\"$supersedes\""
    [[ "$expires_at" != "null" ]] && json="$json,\"expires_at\":\"$expires_at\""
    [[ -n "$supersedes_key" ]] && json="$json,\"supersedes_key\":\"$supersedes_key\""
    [[ -n "$source" ]] && json="$json,\"source\":\"${source//\"/\\\"}\""
    [[ "$entities_json" != "[]" ]] && json="$json,\"entities\":$entities_json"
    [[ -n "$valid_to" ]] && json="$json,\"valid_to\":\"$valid_to\""
    echo "$json}" >> "$STORE_FILE"
    echo "✓ Guardado: $title (topic: $topic_key, rev: $rev)"
    _update_memory_index "$topic_key" "$title" "$type" "$origin" 2>/dev/null || true
    _maybe_rebuild_index

    # SE-214: optional conflict check (activated by SAVIA_CONFLICT_CHECK=true)
    if [[ "${SAVIA_CONFLICT_CHECK:-false}" == "true" ]]; then
        bash "$(dirname "$0")/memory-conflict-check.sh" "$content" "$type" 2>&1 || true
    fi
}

cmd_entity() { local action="${1:-list}" query= etype= proj=; shift 2>/dev/null || true
    while [[ $# -gt 0 ]]; do case "$1" in --type) etype="$2"; shift 2;; --project) proj="$2"; shift 2;; *) query="$1"; shift;; esac; done
    [[ ! -f "$STORE_FILE" ]] && { echo "No hay entidades registradas"; return; }
    if [[ "$action" == "list" ]]; then
        echo "## Entidades Registradas"
        grep '"type":"entity"' "$STORE_FILE" 2>/dev/null | while IFS= read -r line; do
            local t=$(echo "$line" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
            local c=$(echo "$line" | grep -o '"concepts":\[[^]]*\]' | sed 's/.*\[//;s/\].*//' | tr -d '"')
            local p=$(echo "$line" | grep -o '"project":"[^"]*"' | cut -d'"' -f4)
            [[ -n "$etype" && "$c" != *"$etype"* ]] && continue; [[ -n "$proj" && "$p" != "$proj" ]] && continue
            echo "  - $t ($c) — proyecto: $p"
        done
    elif [[ "$action" == "find" ]]; then
        [[ -z "$query" ]] && { echo "Uso: entity find {nombre}"; return; }
        grep '"type":"entity"' "$STORE_FILE" 2>/dev/null | grep -i "$query" | while IFS= read -r line; do
            local t=$(echo "$line" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
            local c=$(echo "$line" | grep -o '"content":"[^"]*"' | sed 's/"content":"//' | sed 's/"$//')
            echo "$t — $(echo "$line" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f1): $c"
        done
    else echo "Uso: entity {list|find} [nombre] [--type tipo] [--project proj]"; fi
}

cmd_session_summary() {
    local goal= discoveries= accomplished= files= project=
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --goal) goal="$2"; shift 2 ;; --discoveries) discoveries="$2"; shift 2 ;;
            --accomplished) accomplished="$2"; shift 2 ;; --files) files="$2"; shift 2 ;;
            --project) project="$2"; shift 2 ;; *) shift ;;
        esac
    done
    [[ -z "$accomplished" ]] && { echo "Error: --accomplished requerido"; return 1; }
    local content="Goal: ${goal:-not specified}"
    [[ -n "$discoveries" ]] && content="$content | Discoveries: $discoveries"
    content="$content | Accomplished: $accomplished"
    [[ -n "$files" ]] && content="$content | Files: $files"
    cmd_save --type "session-summary" --title "Session $(date +%Y-%m-%d)" \
        --content "$content" --concepts "session" \
        --topic "session/$(date +%Y-%m-%d)" ${project:+--project "$project"}
}

# SE-352: distribución de orígenes de las entradas de memoria
cmd_audit_origins() {
    [[ ! -f "$STORE_FILE" ]] && { echo "No hay memory store"; return; }
    local total=0 owner=0 agent=0 untrusted=0 system=0 missing=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        total=$((total + 1))
        local o
        o=$(echo "$line" | grep -o '"origin":"[^"]*"' | cut -d'"' -f4 || true)
        [[ -z "$o" ]] && { missing=$((missing + 1)); o="untrusted"; }
        case "$o" in
            owner) owner=$((owner + 1)) ;; agent) agent=$((agent + 1)) ;;
            untrusted) untrusted=$((untrusted + 1)) ;; system) system=$((system + 1)) ;;
        esac
    done < "$STORE_FILE"
    local pct_owner pct_agent pct_untrusted pct_system
    pct_owner=$(LC_ALL=C awk -v a="$owner" -v t="$total" 'BEGIN{printf "%.1f", (t>0?100*a/t:0)}')
    pct_agent=$(LC_ALL=C awk -v a="$agent" -v t="$total" 'BEGIN{printf "%.1f", (t>0?100*a/t:0)}')
    pct_untrusted=$(LC_ALL=C awk -v a="$untrusted" -v t="$total" 'BEGIN{printf "%.1f", (t>0?100*a/t:0)}')
    pct_system=$(LC_ALL=C awk -v a="$system" -v t="$total" 'BEGIN{printf "%.1f", (t>0?100*a/t:0)}')
    echo "Distribución de orígenes — Total: $total entradas"
    echo "  owner:      $owner ($pct_owner%)"
    echo "  agent:      $agent ($pct_agent%)"
    echo "  untrusted:  $untrusted ($pct_untrusted%)"
    echo "  system:     $system ($pct_system%)"
    echo "  sin src:    $missing (tratadas como untrusted)"
}

# SE-352: consolidación con exclusión de orígenes no confiables
# Regla (OpenClaw dreaming): untrusted/system NUNCA entran en la promoción.
# Modo --dry-run: solo reporta qué se excluiría, sin tocar el store.
cmd_consolidate() {
    [[ ! -f "$STORE_FILE" ]] && { echo "No hay memory store"; return; }
    local dry=false
    while [[ $# -gt 0 ]]; do case "$1" in
        --dry-run) dry=true; shift ;; *) shift ;; esac; done
    local excluded=0 kept=0 tmp_file
    tmp_file=$(mktemp); trap "rm -f '$tmp_file'" RETURN
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local o
        o=$(echo "$line" | grep -o '"origin":"[^"]*"' | cut -d'"' -f4 || echo "untrusted")
        [[ -z "$o" ]] && o="untrusted"
        if [[ "$o" == "untrusted" || "$o" == "system" ]]; then
            excluded=$((excluded + 1))
            continue
        fi
        echo "$line" >> "$tmp_file"; kept=$((kept + 1))
    done < "$STORE_FILE"
    if $dry; then
        echo "Consolidación (dry-run): excluidas ${excluded} entradas untrusted/system, mantenidas ${kept}."
        return
    fi
    mv "$tmp_file" "$STORE_FILE"
    echo "Consolidación: excluidas ${excluded} entradas untrusted/system, mantenidas ${kept}."
    _maybe_rebuild_index
}
