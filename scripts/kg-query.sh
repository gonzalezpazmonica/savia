#!/usr/bin/env bash
set -uo pipefail
# kg-query.sh — SE-218 S3: query KG con qualified names
# Ref: docs/propuestas/SE-218-codebase-memory-patterns.md
# Usage:
#   kg-query.sh get <qualified_name>                   — buscar por QN exacto
#   kg-query.sh search <pattern>                       — buscar por nombre parcial
#   kg-query.sh list [--project <slug>]                — listar QNs
#   kg-query.sh qualify <path> [--project <slug>]      — generar QN para un path

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KG_DB="${KG_DB:-$HOME/.savia/knowledge-graph.db}"
KG_JSON="${KG_JSON:-$WORKSPACE_ROOT/output/knowledge-graph.json}"
DEFAULT_PROJECT="pm-workspace"

# ── Utilidades ────────────────────────────────────────────────────────────────

usage() {
  cat >&2 <<'EOF'
Usage:
  kg-query.sh qualify <path> [--project <slug>]   Generate qualified name for a path
  kg-query.sh get    <qualified_name>              Find node by exact qualified name
  kg-query.sh search <pattern>                     Find nodes containing pattern
  kg-query.sh list   [--project <slug>]            List all qualified names
EOF
  exit 1
}

qualify_name() {
  local path="${1:?path required}"
  local project="${2:-$DEFAULT_PROJECT}"
  # Slugify: strip leading ./, replace / with ., remove extensions, _ to -, lowercase
  local module
  module=$(echo "$path" | sed 's|^\./||; s|/|.|g; s|\.sh$||; s|\.py$||; s|\.md$||; s|\.ts$||; s|\.js$||; s|\.cs$||; s|_|-|g' | tr '[:upper:]' '[:lower:]')
  echo "${project}.${module}"
}

# Detect KG backend
kg_available() {
  [[ -f "$KG_DB" ]] && python3 -c "import sys; import sqlite3; sqlite3.connect(sys.argv[1])" "$KG_DB" 2>/dev/null && return 0
  [[ -f "$KG_JSON" ]] && return 0
  return 1
}

kg_query_python() {
  local mode="$1"
  local arg="${2:-}"
  local project_filter="${3:-}"

  python3 - "$mode" "$arg" "$project_filter" "$KG_DB" "$KG_JSON" <<'PYEOF'
import sys, json, os

mode       = sys.argv[1]
arg        = sys.argv[2]
proj_filt  = sys.argv[3]
kg_db      = sys.argv[4]
kg_json    = sys.argv[5]

def rows_from_sqlite(db_path):
    import sqlite3
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT name, type, project_id FROM entities")
    rows = [{"name": r[0], "type": r[1], "project": r[2] or ""} for r in c.fetchall()]
    conn.close()
    return rows

def rows_from_json(json_path):
    with open(json_path) as f:
        data = json.load(f)
    if isinstance(data, list):
        return [{"name": r.get("name",""), "type": r.get("type",""), "project": r.get("project_id","")} for r in data]
    entities = data.get("entities", [])
    return [{"name": r.get("name",""), "type": r.get("type",""), "project": r.get("project_id","")} for r in entities]

# Load rows
rows = []
if os.path.isfile(kg_db):
    try:
        rows = rows_from_sqlite(kg_db)
    except Exception as e:
        print(f"ERROR reading KG db: {e}", file=sys.stderr)
        sys.exit(1)
elif os.path.isfile(kg_json):
    try:
        rows = rows_from_json(kg_json)
    except Exception as e:
        print(f"ERROR reading KG json: {e}", file=sys.stderr)
        sys.exit(1)
else:
    print("KG not found — run scripts/knowledge-graph.py first", file=sys.stderr)
    sys.exit(1)

# Apply project filter
if proj_filt:
    rows = [r for r in rows if r["project"] == proj_filt]

def qualify(name, project):
    slug = name.lower()
    for ext in [".sh", ".py", ".md", ".ts", ".js", ".cs"]:
        slug = slug.replace(ext, "")
    slug = slug.replace("/", ".").replace("_", "-").lstrip("./")
    proj = project or "pm-workspace"
    return f"{proj}.{slug}"

if mode == "get":
    found = []
    for r in rows:
        qn = qualify(r["name"], r["project"])
        if qn == arg or r["name"] == arg:
            found.append({"qualified_name": qn, "name": r["name"], "type": r["type"], "project": r["project"]})
    if not found:
        print(f"No entity found for: {arg}", file=sys.stderr)
        sys.exit(1)
    for item in found:
        print(json.dumps(item))

elif mode == "search":
    pattern = arg.lower()
    for r in rows:
        if pattern in r["name"].lower():
            qn = qualify(r["name"], r["project"])
            print(json.dumps({"qualified_name": qn, "name": r["name"], "type": r["type"], "project": r["project"]}))

elif mode == "list":
    for r in rows:
        qn = qualify(r["name"], r["project"])
        print(f"{qn}  ({r['type']})")
PYEOF
}

# ── Main ──────────────────────────────────────────────────────────────────────

CMD="${1:-}"
[[ -z "$CMD" ]] && usage

case "$CMD" in

  qualify)
    TARGET_PATH="${2:-}"
    [[ -z "$TARGET_PATH" ]] && { echo "ERROR: qualify requires <path>" >&2; exit 1; }
    PROJECT="$DEFAULT_PROJECT"
    shift 2 || true
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) PROJECT="${2:?--project requires value}"; shift 2 ;;
        *) shift ;;
      esac
    done
    qualify_name "$TARGET_PATH" "$PROJECT"
    ;;

  get)
    QN="${2:-}"
    [[ -z "$QN" ]] && { echo "ERROR: get requires <qualified_name>" >&2; exit 1; }
    if ! kg_available; then
      echo "KG not found — run scripts/knowledge-graph.py first" >&2
      exit 1
    fi
    kg_query_python "get" "$QN" ""
    ;;

  search)
    PATTERN="${2:-}"
    [[ -z "$PATTERN" ]] && { echo "ERROR: search requires <pattern>" >&2; exit 1; }
    if ! kg_available; then
      echo "KG not found — run scripts/knowledge-graph.py first" >&2
      exit 1
    fi
    kg_query_python "search" "$PATTERN" ""
    ;;

  list)
    PROJECT_FILTER=""
    shift || true
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) PROJECT_FILTER="${2:?--project requires value}"; shift 2 ;;
        *) shift ;;
      esac
    done
    if ! kg_available; then
      echo "KG not found — run scripts/knowledge-graph.py first" >&2
      exit 1
    fi
    kg_query_python "list" "" "$PROJECT_FILTER"
    ;;

  *)
    echo "ERROR: unknown command '$CMD'" >&2
    usage
    ;;
esac
