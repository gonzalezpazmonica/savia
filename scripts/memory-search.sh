#!/bin/bash
# memory-search.sh — Search, context, stats (sourced by memory-store.sh)
set -uo pipefail
[[ -n "${LC_ALL:-}" ]] && { export LANG="$LC_ALL"; unset LC_ALL; }; export LC_NUMERIC=C  # punto decimal fijo (es_ES usa coma); LC_ALL anularía LC_NUMERIC
# Vector search with grep fallback. SPEC-020: TTL filtering.

cmd_search() {
    [[ ! -f "$STORE_FILE" ]] && { echo "Usage: search requires a store file" >&2; return 1; }
    local query= type_filter= since_date= mode="auto" include_expired=false
    local sector_filter= include_superseded=false min_origin=
    while [[ $# -gt 0 ]]; do case "$1" in
        --type) type_filter="$2"; shift 2;; --since) since_date="$2"; shift 2;;
        --mode) mode="$2"; shift 2;; --include-expired) include_expired=true; shift;;
        --sector) sector_filter="$2"; shift 2;;
        --include-superseded) include_superseded=true; shift;;
        --min-origin) min_origin="$2"; shift 2;;   # SE-352: owner|agent|untrusted
        *) query="$1"; shift;; esac
    done
    [[ -z "$query" ]] && { echo "Usage: search \"query\" [--type tipo] [--since DATE] [--mode hybrid|vector|graph|grep|auto]" >&2; return 1; }

    # SE-352: valor inválido = error (fail-closed), no se degrada a "sin filtro" ni a untrusted.
    case "$min_origin" in ""|owner|agent|untrusted|system) ;;
        *) echo "Error: --min-origin '$min_origin' inválido. Válidos: owner|agent|untrusted|system." >&2; return 1;; esac
    local origin_args=(); [[ -n "$min_origin" ]] && origin_args=(--min-origin "$min_origin")

    # SPEC-035: Hybrid search (vector + graph + grep combined)
    if [[ "$mode" == "hybrid" || "$mode" == "auto" ]] && [[ -n "$MEMORY_PYTHON" ]]; then
        local hybrid_result
        hybrid_result=$("$MEMORY_PYTHON" "$SCRIPT_DIR/memory-hybrid.py" search "$query" --top 10 --store "$STORE_FILE" --mode hybrid "${origin_args[@]}" 2>/dev/null) || true
        if [[ -n "$hybrid_result" ]] && echo "$hybrid_result" | "$MEMORY_PYTHON" -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('results') else 1)" 2>/dev/null; then
            echo "$hybrid_result" | "$MEMORY_PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
src = d.get('sources', {})
for r in d['results']:
    ts = r.get('ts','')[:10] if r.get('ts') else '?'
    s = r.get('sources', r.get('source', '?'))
    print(f'  [{ts}] ({r.get(\"type\",\"?\")}) {r[\"title\"]} [score:{r[\"score\"]:.2f} via:{s}]')
print(f'  (hybrid: {src.get(\"vector\",0)} vec + {src.get(\"graph\",0)} graph + {src.get(\"grep\",0)} grep)', file=sys.stderr)
" 2>/dev/null
            return
        fi
    fi
    # Vector-only search (legacy path)
    if [[ "$mode" == "vector" || "$mode" == "auto" ]]; then
        local idx="${STORE_FILE%.jsonl}-index.idx"
        local idx_faiss="${STORE_FILE%.jsonl}-index.faiss"
        [[ -f "$idx_faiss" ]] && idx="$idx_faiss"
        if [[ -n "$MEMORY_PYTHON" && -f "$idx" ]]; then
            local vec_result
            vec_result=$("$MEMORY_PYTHON" "$SCRIPT_DIR/memory-vector.py" search "$query" --top 10 --store "$STORE_FILE" 2>/dev/null) || true
            # SE-352: mismo filtro que hybrid; si no puede aplicarse, el resultado se descarta (fail-closed).
            if [[ -n "$min_origin" && -n "$vec_result" ]]; then
                vec_result=$(echo "$vec_result" | "$MEMORY_PYTHON" "$SCRIPT_DIR/memory-hybrid.py" filter --store "$STORE_FILE" --min-origin "$min_origin" 2>/dev/null) || vec_result=""
            fi
            if [[ -n "$vec_result" ]] && echo "$vec_result" | "$MEMORY_PYTHON" -c "import sys,json; d=json.load(sys.stdin); exit(0 if not d.get('fallback') and d.get('results') else 1)" 2>/dev/null; then
                echo "$vec_result" | "$MEMORY_PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
for r in d['results']:
    ts = r['ts'][:10] if r.get('ts') else '?'
    print(f'  [{ts}] ({r[\"type\"]}) {r[\"title\"]} [topic:{r[\"topic_key\"]} score:{r[\"score\"]}]')
" 2>/dev/null
                echo "  (vector search)" >&2; return
            fi
        fi
        [[ "$mode" == "vector" ]] && { echo "Vector index not available. Run: bash scripts/memory-store.sh rebuild-index"; return 1; }
    fi

    # Grep fallback
    local tmp_results=$(mktemp); trap "rm -f '$tmp_results'" RETURN
    while IFS= read -r line; do
        local ts type title topic score=0
        ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f1)
        [[ -n "$since_date" && "$ts" < "$since_date" ]] && continue
        # SPEC-020: TTL filter
        if [[ "$include_expired" != "true" ]]; then
            local exp=$(echo "$line" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4 || true)
            if [[ -n "$exp" ]]; then
                local exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 9999999999)
                [[ $(date -u +%s) -gt $exp_epoch ]] && continue
            fi
        fi
        type=$(echo "$line" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
        [[ -n "$type_filter" && "$type" != "$type_filter" ]] && continue
        # SPEC-037: sector filter
        if [[ -n "$sector_filter" ]]; then
            local sector=$(echo "$line" | grep -o '"sector":"[^"]*"' | cut -d'"' -f4)
            [[ "$sector" != "$sector_filter" ]] && continue
        fi
        # SPEC-034: skip superseded entries by default
        if [[ "$include_superseded" != "true" ]]; then
            echo "$line" | grep -q '"valid_to"' && continue
        fi
        # SE-352: origin class filter (fail-safe: entry sin origin = untrusted)
        if [[ -n "$min_origin" ]]; then
            local line_origin
            line_origin=$(echo "$line" | grep -o '"origin":"[^"]*"' | cut -d'"' -f4 || echo "untrusted")
            [[ -z "$line_origin" ]] && line_origin="untrusted"
            local origin_rank line_rank
            case "$min_origin" in owner) origin_rank=4 ;; agent) origin_rank=3 ;; untrusted) origin_rank=2 ;; *) origin_rank=2 ;; esac
            case "$line_origin" in owner) line_rank=4 ;; agent) line_rank=3 ;; untrusted) line_rank=2 ;; system) line_rank=1 ;; *) line_rank=2 ;; esac
            [[ $line_rank -lt $origin_rank ]] && continue
        fi
        title=$(echo "$line" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
        topic=$(echo "$line" | grep -o '"topic_key":"[^"]*"' | cut -d'"' -f4)
        local rev=$(echo "$line" | grep -o '"rev":[0-9]*' | cut -d: -f2)
        echo "$title" | grep -qi "$query" 2>/dev/null && score=$((score+3)) || true
        echo "$line" | grep -qi "$query" 2>/dev/null && score=$((score+1)) || true
        echo "$topic" | grep -qi "$query" 2>/dev/null && score=$((score+2)) || true
        [[ $score -gt 0 ]] && printf '%03d\t%s\t%s\t%s\t%s\t%s\n' "$score" "$ts" "$type" "$title" "$topic" "$rev" >> "$tmp_results"
    done < "$STORE_FILE"
    if [[ -s "$tmp_results" ]]; then
        sort -rn "$tmp_results" | head -10 | while IFS=$'\t' read -r score ts type title topic rev; do
            echo "  [$ts] ($type) $title [topic:$topic rev:$rev score:$((10#$score))]"
        done
        echo "  (grep fallback)" >&2
    else echo "No se encontraron resultados"; fi
}

cmd_context() {
    [[ ! -f "$STORE_FILE" ]] && return
    local limit=20 project=
    while [[ $# -gt 0 ]]; do case "$1" in --limit) limit="$2"; shift 2;; --project) project="$2"; shift 2;; *) shift;; esac; done
    echo "## Memoria Persistente" && echo ""
    local src
    if [[ -n "$project" ]]; then
        src=$(grep "\"project\":\"$project\"" "$STORE_FILE" 2>/dev/null | tac | head -n "$limit")
    else src=$(tac "$STORE_FILE" | head -n "$limit"); fi
    echo "$src" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f1)
        local type=$(echo "$line" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
        local title=$(echo "$line" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
        local topic=$(echo "$line" | grep -o '"topic_key":"[^"]*"' | cut -d'"' -f4)
        echo "- [$ts] ($type) $title [$topic]"
    done
}

cmd_stats() {
    [[ ! -f "$STORE_FILE" ]] && { echo "No hay memory store"; return; }
    local total=$(wc -l < "$STORE_FILE")
    echo "Estadisticas — Total: $total entradas"
    echo "Por tipo:" && grep -o '"type":"[^"]*"' "$STORE_FILE" | cut -d'"' -f4 | \
        sort | uniq -c | sort -rn | awk '{ printf "  %s: %d\n", $2, $1 }'
    echo "Por familia topic_key:" && grep -o '"topic_key":"[^/"]*' "$STORE_FILE" | \
        cut -d'"' -f4 | sort | uniq -c | sort -rn | head -10 | \
        awk '{ printf "  %s/: %d\n", $2, $1 }'
    echo "Por concepto:" && grep -o '"concepts":\[[^]]*\]' "$STORE_FILE" | \
        sed 's/.*\[//;s/\].*//' | tr ',' '\n' | tr -d '"' | sed '/^$/d' | \
        sort | uniq -c | sort -rn | head -5 | awk '{ printf "  %s: %d\n", $2, $1 }'
    echo "Revisiones (topic_keys con rev>1):" && grep -o '"rev":[0-9]*' "$STORE_FILE" | \
        cut -d: -f2 | awk '$1>1{count++; sum+=$1} END{printf "  %d evolucionados, avg %.1f revs\n", count+0, (count>0?sum/count:0)}'
    # SPEC-020: TTL stats
    local expired=0 with_ttl=0 now_epoch
    now_epoch=$(date -u +%s)
    while IFS= read -r line; do
        local exp
        exp=$(echo "$line" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4 || true)
        [[ -z "$exp" ]] && continue
        with_ttl=$((with_ttl + 1))
        local exp_epoch
        exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 9999999999)
        [[ $now_epoch -gt $exp_epoch ]] && expired=$((expired + 1))
    done < "$STORE_FILE"
    echo "TTL: $with_ttl con expiración, $expired expiradas"
}

# SPEC-020: Prune expired entries
cmd_prune() {
    [[ ! -f "$STORE_FILE" ]] && { echo "No hay memory store"; return; }
    local now_epoch expired_count=0 kept_count=0
    now_epoch=$(date -u +%s)
    local tmp_file
    tmp_file=$(mktemp)
    trap "rm -f '$tmp_file'" RETURN
    while IFS= read -r line; do
        local exp
        exp=$(echo "$line" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4 || true)
        if [[ -n "$exp" ]]; then
            local exp_epoch
            exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 9999999999)
            if [[ $now_epoch -gt $exp_epoch ]]; then
                expired_count=$((expired_count + 1))
                continue
            fi
        fi
        echo "$line" >> "$tmp_file"
        kept_count=$((kept_count + 1))
    done < "$STORE_FILE"
    if [[ $expired_count -eq 0 ]]; then
        echo "No hay entradas expiradas."
        return
    fi
    echo "Eliminando $expired_count entradas expiradas ($kept_count mantenidas)."
    mv "$tmp_file" "$STORE_FILE"
    _maybe_rebuild_index
}
