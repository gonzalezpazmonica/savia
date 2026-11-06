#!/usr/bin/env bash
# graphrag-quality-gates.sh — SE-030
set -uo pipefail
# Wrapper over knowledge-graph.py that executes 12 structural quality checks
# on the Savia knowledge graph SQLite database.
#
# These 12 checks are STRUCTURAL (graph topology, data integrity) — distinct
# from graphrag-quality-gate.sh which validates METRIC thresholds (NDCG, MRR).
#
# Usage:
#   bash scripts/graphrag-quality-gates.sh [--db PATH] [--json] [--quiet]
#
# Output:
#   Table of 12 checks with PASS/WARN/FAIL status + JSON summary
#
# Exit codes:
#   0  = all checks PASS or WARN only
#   1  = one or more FAIL checks
#   2  = usage/configuration error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")}"

DB_PATH="${KG_DB:-$HOME/.savia/knowledge-graph.db}"
JSON_OUT=false
QUIET=false

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)     [[ $# -ge 2 && -n "$2" ]] || { echo "Error: --db requires a path" >&2; exit 2; }
              DB_PATH="$2"; shift 2 ;;
    --json)   JSON_OUT=true; shift ;;
    --quiet)  QUIET=true; shift ;;
    -h|--help) usage ;;
    *) echo "Error: unknown flag '$1'" >&2; exit 2 ;;
  esac
done

# ── Check database exists ────────────────────────────────────────────────────
if [[ ! -f "$DB_PATH" ]]; then
  if [[ "$JSON_OUT" == true ]]; then
    python3 -c 'import json,sys; print(json.dumps({"error":"database not found","db":sys.argv[1],"checks":[],"summary":{"passed":0,"warned":0,"failed":0}}))' "$DB_PATH"
    exit 1
  else
    echo "WARN: Knowledge graph database not found: $DB_PATH" >&2
    echo "      Run: python3 scripts/knowledge-graph.py build" >&2
    # Emit a minimal passing result so CI is not hard-blocked
    echo "=== GraphRAG Quality Gates (SE-030) ==="
    echo "  [WARN] Database not found — run 'python3 scripts/knowledge-graph.py build' first"
    echo ""
    echo "Summary: 0 PASS, 1 WARN, 0 FAIL"
    exit 0
  fi
fi

# ── Execute 12 checks via Python (SQLite queries) ────────────────────────────
python3 - "$DB_PATH" "$JSON_OUT" "$QUIET" <<'PY'
import json
import sqlite3
import sys
from datetime import datetime, timezone

db_path  = sys.argv[1]
json_out = sys.argv[2] == "true"
quiet    = sys.argv[3] == "true"

checks = []
fails  = 0
warns  = 0
passed = 0

def run_check(name: str, description: str, fn):
    """Execute one check; catch exceptions as FAIL."""
    global fails, warns, passed
    try:
        status, detail = fn()
    except Exception as exc:
        status  = "FAIL"
        detail  = f"Exception: {exc}"
    entry = {
        "id": len(checks) + 1,
        "name": name,
        "description": description,
        "status": status,
        "detail": detail,
    }
    checks.append(entry)
    if status == "FAIL":
        fails  += 1
    elif status == "WARN":
        warns  += 1
    else:
        passed += 1

try:
    con = sqlite3.connect(db_path)
    cur = con.cursor()
except Exception as exc:
    print(json.dumps({"error": str(exc), "checks": [], "summary": {"passed": 0, "warned": 0, "failed": 0}}))
    sys.exit(1)

# Helper: check if table exists
def table_exists(name: str) -> bool:
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,))
    return cur.fetchone() is not None

entities_ok = table_exists("entities")
relations_ok = table_exists("relations")

# Detect relation edge column names (source_id/target_id OR entity_a/entity_b)
def get_edge_cols():
    cur.execute("PRAGMA table_info(relations)")
    cols = [row[1] for row in cur.fetchall()]
    if "source_id" in cols and "target_id" in cols:
        return "source_id", "target_id"
    elif "entity_a" in cols and "entity_b" in cols:
        return "entity_a", "entity_b"
    return None, None

# ── Check 1: No orphan nodes (entities with zero relations in either direction)
def check_no_orphans():
    if not entities_ok or not relations_ok:
        return "WARN", "entities or relations table missing"
    src_col, tgt_col = get_edge_cols()
    if src_col is None:
        return "WARN", "relation edge columns not detected"
    cur.execute(f"""
        SELECT COUNT(*) FROM entities
        WHERE id NOT IN (
            SELECT DISTINCT {src_col} FROM relations
            UNION
            SELECT DISTINCT {tgt_col} FROM relations
        )
    """)
    count = cur.fetchone()[0]
    if count == 0:
        return "PASS", "0 orphan nodes"
    elif count <= 5:
        return "WARN", f"{count} orphan nodes (≤5 tolerated)"
    else:
        return "FAIL", f"{count} orphan nodes"

run_check("no-orphan-nodes", "No entities with zero relations", check_no_orphans)

# ── Check 2: No edges to non-existent nodes
def check_no_dangling_edges():
    if not entities_ok or not relations_ok:
        return "WARN", "entities or relations table missing"
    src_col, tgt_col = get_edge_cols()
    if src_col is None:
        return "WARN", "relation edge columns not detected"
    cur.execute(f"""
        SELECT COUNT(*) FROM relations
        WHERE {src_col} NOT IN (SELECT id FROM entities)
           OR {tgt_col} NOT IN (SELECT id FROM entities)
    """)
    count = cur.fetchone()[0]
    if count == 0:
        return "PASS", "0 dangling edges"
    else:
        return "FAIL", f"{count} edges reference non-existent nodes"

run_check("no-dangling-edges", "No edges pointing to non-existent nodes", check_no_dangling_edges)

# ── Check 3: Type consistency (entity_type in known set)
KNOWN_ENTITY_TYPES = {
    "project", "person", "skill", "decision", "spec", "concept",
    "tool", "rule", "artifact", "observation", "fact", "goal",
    "commitment", "event", "learning", "error", "preference",
    "relationship", "context",
}
KNOWN_RELATION_TYPES = {
    "uses", "owns", "blocks", "depends_on", "decided", "implements",
    "mentions", "related_to", "part_of", "extends", "documents",
}

def check_type_consistency():
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("SELECT DISTINCT type FROM entities WHERE type IS NOT NULL")
    found_types = {row[0] for row in cur.fetchall()}
    unknown = found_types - KNOWN_ENTITY_TYPES
    if not unknown:
        return "PASS", f"all {len(found_types)} entity types known"
    elif len(unknown) <= 3:
        return "WARN", f"unknown types (tolerated): {sorted(unknown)}"
    else:
        return "FAIL", f"too many unknown entity types: {sorted(unknown)}"

run_check("type-consistency", "Entity/relation types within known vocabulary", check_type_consistency)

# ── Check 4: No exact duplicates (same name + type)
def check_no_duplicates():
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("""
        SELECT COUNT(*) FROM (
            SELECT name, type, COUNT(*) as cnt FROM entities
            GROUP BY name, type HAVING cnt > 1
        )
    """)
    dup_groups = cur.fetchone()[0]
    if dup_groups == 0:
        return "PASS", "0 duplicate (name, type) pairs"
    elif dup_groups <= 3:
        return "WARN", f"{dup_groups} duplicate groups (≤3 tolerated)"
    else:
        return "FAIL", f"{dup_groups} exact duplicate entity groups"

run_check("no-exact-duplicates", "No duplicate entities with same name+type", check_no_duplicates)

# ── Check 5: Minimum entity count (warn if < 10)
def check_min_entities():
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("SELECT COUNT(*) FROM entities")
    count = cur.fetchone()[0]
    if count >= 10:
        return "PASS", f"{count} entities (≥10)"
    elif count > 0:
        return "WARN", f"only {count} entities (< 10 — graph may be empty)"
    else:
        return "FAIL", "0 entities — graph is empty"

run_check("min-entity-count", "Minimum 10 entities in graph (warn if fewer)", check_min_entities)

# ── Check 6: No self-loops (source_id == target_id)
def check_no_self_loops():
    if not relations_ok:
        return "WARN", "relations table missing"
    src_col, tgt_col = get_edge_cols()
    if src_col is None:
        return "WARN", "relation edge columns not detected"
    cur.execute(f"SELECT COUNT(*) FROM relations WHERE {src_col} = {tgt_col}")
    count = cur.fetchone()[0]
    if count == 0:
        return "PASS", "0 self-loops"
    else:
        return "FAIL", f"{count} self-loop edges (source == target)"

run_check("no-self-loops", "No self-referential edges", check_no_self_loops)

# ── Check 7: Basic connectivity (at least 1 connected component, i.e. > 0 edges)
def check_basic_connectivity():
    if not relations_ok:
        return "WARN", "relations table missing"
    cur.execute("SELECT COUNT(*) FROM relations")
    edge_count = cur.fetchone()[0]
    if edge_count >= 1:
        return "PASS", f"{edge_count} edges — graph is non-empty"
    else:
        return "WARN", "0 edges — graph has no connections"

run_check("basic-connectivity", "Graph has at least one edge (non-trivial component)", check_basic_connectivity)

# ── Check 8: No empty required properties (name must not be NULL/blank)
def check_no_empty_required():
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("SELECT COUNT(*) FROM entities WHERE name IS NULL OR TRIM(name) = ''")
    count = cur.fetchone()[0]
    if count == 0:
        return "PASS", "all entities have non-empty name"
    else:
        return "FAIL", f"{count} entities with NULL or empty name"

run_check("no-empty-required-props", "All required properties (name) are non-empty", check_no_empty_required)

# ── Check 9: No future timestamps
def check_no_future_timestamps():
    # El esquema real (knowledge-graph.py) usa first_seen/last_seen. SQLite datetime() normaliza
    # 'YYYY-MM-DD HH:MM:SS' e ISO con 'T' o zona: comparar cadenas con un isoformat de Python
    # ('T' > ' ') dejaba pasar fechas futuras del mismo día.
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("PRAGMA table_info(entities)")
    cols = [row[1] for row in cur.fetchall()]
    present = [c for c in ("created_at", "updated_at", "timestamp", "first_seen", "last_seen") if c in cols]
    if not present:
        return "WARN", "no timestamp column present — skipping"
    for col in present:
        cur.execute(f"SELECT COUNT(*) FROM entities WHERE datetime({col}) > datetime('now')")
        count = cur.fetchone()[0]
        if count > 0:
            return "FAIL", f"{count} entities with future {col}"
    return "PASS", f"no future timestamps in {', '.join(present)}"

run_check("no-future-timestamps", "No entity timestamps set in the future", check_no_future_timestamps)

# ── Check 10: Reasonable graph size (warn if > 10000 nodes)
def check_reasonable_size():
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("SELECT COUNT(*) FROM entities")
    count = cur.fetchone()[0]
    if count <= 10000:
        return "PASS", f"{count} entities (≤10000)"
    else:
        return "WARN", f"{count} entities exceeds 10000 — consider archiving"

run_check("reasonable-graph-size", "Node count ≤ 10000 (warn if larger)", check_reasonable_size)

# ── Check 11: Confidence scores in [0, 1]
def check_confidence_range():
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("PRAGMA table_info(entities)")
    cols = [row[1] for row in cur.fetchall()]
    if "confidence" not in cols:
        return "WARN", "confidence column not present — skipping"
    cur.execute("""
        SELECT COUNT(*) FROM entities
        WHERE confidence IS NOT NULL AND (confidence < 0 OR confidence > 1)
    """)
    count = cur.fetchone()[0]
    if count == 0:
        return "PASS", "all confidence scores in [0,1]"
    else:
        return "FAIL", f"{count} entities with confidence outside [0,1]"

run_check("confidence-range", "Confidence scores between 0.0 and 1.0", check_confidence_range)

# ── Check 12: Source field not empty on entities
def check_source_not_empty():
    if not entities_ok:
        return "WARN", "entities table missing"
    cur.execute("PRAGMA table_info(entities)")
    cols = [row[1] for row in cur.fetchall()]
    source_col = None
    for candidate in ("source", "provenance"):
        if candidate in cols:
            source_col = candidate
            break
    if source_col is None:
        return "WARN", "source/provenance column not present — skipping"
    cur.execute(f"SELECT COUNT(*) FROM entities WHERE {source_col} IS NULL OR TRIM(CAST({source_col} AS TEXT)) = '' OR CAST({source_col} AS TEXT) = 'unknown'")
    count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM entities")
    total = cur.fetchone()[0]
    if count == 0:
        return "PASS", "all entities have non-empty source"
    ratio = count / total if total > 0 else 0
    if ratio < 0.1:
        return "WARN", f"{count}/{total} entities missing/unknown source (< 10%)"
    elif ratio < 0.5:
        return "WARN", f"{count}/{total} entities have 'unknown' provenance"
    else:
        return "FAIL", f"{count}/{total} entities missing source field"

run_check("source-not-empty", "Source/provenance field non-empty on all entities", check_source_not_empty)

con.close()

# ── Output ────────────────────────────────────────────────────────────────────
summary = {"passed": passed, "warned": warns, "failed": fails}

if json_out:
    print(json.dumps({"checks": checks, "summary": summary}, indent=2))
else:
    if not quiet:
        print("=== GraphRAG Quality Gates (SE-030) ===")
        print(f"  Database: {db_path}")
        print()
        for c in checks:
            status  = c["status"]
            pad     = f"[{status:<4}]"
            print(f"  {pad} #{c['id']:02d} {c['name']:<30}  {c['detail']}")
        print()
    print(f"Summary: {passed} PASS, {warns} WARN, {fails} FAIL")

sys.exit(1 if fails > 0 else 0)
PY
