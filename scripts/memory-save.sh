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

# Escapa "\" y comillas para un literal JSON. Sin esto una ruta Windows (C:\Users)
# o una cita dejaban una línea inválida en el JSONL y rompían recall y rebuild.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"
}

# SE-352: ¿hay taint vigente (<30 min) para esta sesión? Fallo cerrado sin identificador.
_turn_is_tainted() {
    local dir="${SAVIA_MEMORY_TAINT_DIR:-/tmp/savia-memory-taint}" sid now f ts
    sid="${SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
    [[ "$sid" == "unknown" ]] && sid=""
    [[ -d "$dir" ]] || return 1
    now=$(date -u +%s 2>/dev/null || echo 0)
    if [[ -n "$sid" ]]; then
        [[ "$sid" =~ ^[A-Za-z0-9._-]+$ ]] || return 0   # id raro: no se confía
        f="$dir/$sid"; [[ -f "$f" ]] || return 1
        ts=$(head -1 "$f" 2>/dev/null); [[ "$ts" =~ ^[0-9]+$ ]] || return 0
        [[ "$now" -lt $((ts + 1800)) ]]; return
    fi
    for f in "$dir"/*; do
        [[ -f "$f" ]] || continue
        ts=$(head -1 "$f" 2>/dev/null)
        [[ "$ts" =~ ^[0-9]+$ ]] || return 0
        [[ "$now" -lt $((ts + 1800)) ]] && return 0
    done
    return 1
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
    if [[ ! "$type" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Error: --type '$type' inválido (solo letras, números, '-' y '_'); no se guarda nada." >&2
        exit 1
    fi
    command -v python3 >/dev/null 2>&1 || { echo "Error: python3 es necesario para guardar sin riesgo de corromper el almacén." >&2; exit 1; }

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
    # El hook escribe la marca con el session_id que recibe por stdin; el runtime lo
    # expone como CLAUDE_CODE_SESSION_ID (SESSION_ID se mantiene por compatibilidad).
    # Fallo cerrado: sin identificador de sesión, cualquier marca reciente degrada.
    if [[ "$origin" != "untrusted" ]] && _turn_is_tainted; then
        origin="untrusted"
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

    content=$(printf '%s' "$content" | redact_private)
    local now=$(iso8601_now)

    [[ -z "$topic_key" ]] && topic_key=$(suggest_topic_key "$type" "$title")

    # SPEC-020: TTL
    local expires_at=""
    if [[ -n "$expires_days" ]]; then
        expires_at=$(date -u -d "+${expires_days} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
    fi

    # SPEC-034: temporal validity + SPEC-037: cognitive sector
    local sector=$(map_type_to_sector "$type")

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

    # Upsert (SPEC-019), dedup 15 min, supersedes (SPEC-034), serialización JSON,
    # cerrojo y escritura atómica: todo en memory-store-write.py. Si falla, no hay
    # «Guardado» y el almacén queda como estaba.
    local _rc=0
    printf '%s' "$content" | python3 "$SCRIPT_DIR/memory-store-write.py" save \
        --store="$STORE_FILE" --type="$type" --title="$title" --topic="$topic_key" \
        --now="$now" --sector="$sector" --domain="$domain" --tier="$importance_tier" \
        --quality="$quality" --memory-type="$memory_type_kg" --origin="$origin" \
        --project="$project" --concepts="$concepts" --entities="$entities" \
        --valid-from="$valid_from" --valid-to="$valid_to" --supersedes-key="$supersedes_key" \
        --source="$source" --expires-at="$expires_at" || _rc=$?
    [[ $_rc -eq 3 ]] && return 0   # duplicado: ya informado, nada que indexar
    [[ $_rc -ne 0 ]] && return 1
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
    # SE-529 S1: --source/--origin se reenvían a cmd_save. Sin ellos, SE-072 rechazaba el guardado
    # y el resumen de pre-compact se perdía en silencio. No hay procedencia por defecto: quien llama la declara.
    local goal= discoveries= accomplished= files= project= source= origin=
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --goal) goal="$2"; shift 2 ;; --discoveries) discoveries="$2"; shift 2 ;;
            --accomplished) accomplished="$2"; shift 2 ;; --files) files="$2"; shift 2 ;;
            --project) project="$2"; shift 2 ;; --source) source="$2"; shift 2 ;;
            --origin) origin="$2"; shift 2 ;; *) shift ;;
        esac
    done
    [[ -z "$accomplished" ]] && { echo "Error: --accomplished requerido"; return 1; }
    local content="Goal: ${goal:-not specified}"
    [[ -n "$discoveries" ]] && content="$content | Discoveries: $discoveries"
    content="$content | Accomplished: $accomplished"
    [[ -n "$files" ]] && content="$content | Files: $files"
    cmd_save --type "session-summary" --title "Session $(date +%Y-%m-%d)" \
        --content "$content" --concepts "session" \
        --topic "session/$(date +%Y-%m-%d)" ${project:+--project "$project"} \
        ${source:+--source "$source"} ${origin:+--origin "$origin"}
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
# Excluir de la promoción no es borrar: las entradas excluidas (y las antiguas sin
# campo origin, que cuentan como untrusted) pasan a un fichero de cuarentena junto
# al almacén y siguen recuperables. Modo --dry-run: solo reporta, sin tocar nada.
cmd_consolidate() {
    [[ ! -f "$STORE_FILE" ]] && { echo "No hay memory store"; return; }
    local dry="" out excluded kept legacy quarantine
    while [[ $# -gt 0 ]]; do case "$1" in
        --dry-run) dry="--dry-run"; shift ;; *) shift ;; esac; done
    command -v python3 >/dev/null 2>&1 || { echo "Error: python3 es necesario para consolidar sin perder datos." >&2; return 1; }
    out=$(python3 "$SCRIPT_DIR/memory-store-write.py" consolidate --store="$STORE_FILE" $dry) || return 1
    read -r excluded kept legacy quarantine <<< "$out"
    if [[ -n "$dry" ]]; then
        echo "Consolidación (dry-run): excluidas ${excluded} entradas untrusted/system, mantenidas ${kept}."
    else
        echo "Consolidación: excluidas ${excluded} entradas untrusted/system, mantenidas ${kept}."
        [[ "$excluded" -gt 0 ]] && echo "  Las excluidas están en cuarentena (recuperables): ${quarantine}"
    fi
    [[ "$legacy" -gt 0 ]] && echo "  ${legacy} entradas sin campo origin se tratan como untrusted."
    [[ -z "$dry" ]] && _maybe_rebuild_index
    return 0
}
