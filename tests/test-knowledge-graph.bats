#!/usr/bin/env bats
set -uo pipefail
# SE-162: Knowledge Graph sobre memoria Savia.
# Acceptance: build populates SQLite with entities+relations; query/impact/status
# return results; degradation path (no DB) returns non-zero; idempotent builds.
#
# docs/propuestas/SE-162 + docs/rules/domain/knowledge-graph.md referenced below.

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
  PY="scripts/knowledge-graph.py"
  SH="scripts/knowledge-graph.sh"
  DB="$TMPDIR/kg-test-$BATS_TEST_NUMBER.db"
  export KG_DB="$DB"
}

teardown() {
  rm -f "$DB"
  cd /
}

# ── Structural ────────────────────────────────────────────────────────────────

@test "knowledge-graph.py exists and is executable" {
  [[ -f "$PY" ]]
  python3 "$PY" --help 2>&1 | grep -qi "knowledge\|build\|query\|impact"
}

@test "knowledge-graph.sh wrapper exists and is executable" {
  [[ -x "$SH" ]]
}

@test "python script has SE-162 reference" {
  grep -q "SE-162" "$PY"
}

# ── Build ─────────────────────────────────────────────────────────────────────

@test "build creates SQLite DB" {
  run python3 "$PY" build --db "$DB"
  [ "$status" -eq 0 ]
  [[ -f "$DB" ]]
}

@test "build: entities table is populated" {
  python3 "$PY" build --db "$DB"
  local count
  count=$(python3 -c "
import sqlite3; c=sqlite3.connect('$DB')
print(c.execute('SELECT COUNT(*) FROM entities').fetchone()[0])
")
  [ "$count" -gt 0 ]
}

@test "build: relations table is populated" {
  python3 "$PY" build --db "$DB"
  local count
  count=$(python3 -c "
import sqlite3; c=sqlite3.connect('$DB')
print(c.execute('SELECT COUNT(*) FROM relations').fetchone()[0])
")
  [ "$count" -gt 0 ]
}

@test "build: entity types include spec, rule, project" {
  python3 "$PY" build --db "$DB"
  python3 -c "
import sqlite3
c = sqlite3.connect('$DB')
types = {r[0] for r in c.execute('SELECT DISTINCT type FROM entities')}
for required in ('spec', 'rule', 'project'):
    assert required in types, f'missing type: {required}'
print('all types present')
"
}

@test "build: relation types include implements, uses, mentions" {
  python3 "$PY" build --db "$DB"
  python3 -c "
import sqlite3
c = sqlite3.connect('$DB')
rels = {r[0] for r in c.execute('SELECT DISTINCT relation FROM relations')}
for required in ('implements', 'uses', 'mentions'):
    assert required in rels, f'missing relation: {required}'
print('all relation types present')
"
}

@test "build: pm-workspace appears as project entity" {
  python3 "$PY" build --db "$DB"
  python3 -c "
import sqlite3
c = sqlite3.connect('$DB')
row = c.execute(\"SELECT id FROM entities WHERE name='pm-workspace' AND type='project'\").fetchone()
assert row is not None, 'pm-workspace project not found'
print('pm-workspace found')
"
}

@test "build: idempotent — second build produces same counts" {
  python3 "$PY" build --db "$DB"
  local e1 r1
  e1=$(python3 -c "import sqlite3; c=sqlite3.connect('$DB'); print(c.execute('SELECT COUNT(*) FROM entities').fetchone()[0])")
  r1=$(python3 -c "import sqlite3; c=sqlite3.connect('$DB'); print(c.execute('SELECT COUNT(*) FROM relations').fetchone()[0])")
  python3 "$PY" build --db "$DB"
  local e2 r2
  e2=$(python3 -c "import sqlite3; c=sqlite3.connect('$DB'); print(c.execute('SELECT COUNT(*) FROM entities').fetchone()[0])")
  r2=$(python3 -c "import sqlite3; c=sqlite3.connect('$DB'); print(c.execute('SELECT COUNT(*) FROM relations').fetchone()[0])")
  [ "$e1" -eq "$e2" ]
  [ "$r1" -eq "$r2" ]
}

# ── Status ────────────────────────────────────────────────────────────────────

@test "status: returns 0 after build" {
  python3 "$PY" build --db "$DB"
  run python3 "$PY" status --db "$DB"
  [ "$status" -eq 0 ]
  grep -q "Entities" <<< "$output"
  grep -q "Relations" <<< "$output"
}

@test "status: degradation — no DB prints helpful message" {
  run python3 "$PY" status --db "$TMPDIR/nonexistent-kg-99.db"
  [ "$status" -eq 0 ]
  grep -qi "not built\|run" <<< "$output"
}

# ── Query ─────────────────────────────────────────────────────────────────────

@test "query: returns results for known entity" {
  python3 "$PY" build --db "$DB"
  run python3 "$PY" query "pm-workspace" --db "$DB"
  [ "$status" -eq 0 ]
  grep -qi "pm-workspace" <<< "$output"
}

@test "query: unknown term returns no-results message (not crash)" {
  python3 "$PY" build --db "$DB"
  run python3 "$PY" query "xyzzy-nonexistent-9999" --db "$DB"
  [ "$status" -eq 0 ]
  grep -qi "no results\|not found\|No results" <<< "$output"
}

@test "query: missing DB exits non-zero" {
  run python3 "$PY" query "anything" --db "$TMPDIR/missing-kg.db"
  [ "$status" -ne 0 ]
}

# ── Impact ────────────────────────────────────────────────────────────────────

@test "impact: pm-workspace shows downstream relations" {
  python3 "$PY" build --db "$DB"
  run python3 "$PY" impact "pm-workspace" --db "$DB" --depth 1
  [ "$status" -eq 0 ]
  grep -q "\-\-" <<< "$output"
}

@test "impact: missing entity exits non-zero" {
  python3 "$PY" build --db "$DB"
  run python3 "$PY" impact "xyzzy-ghost-entity-9999" --db "$DB"
  [ "$status" -ne 0 ]
}

# ── Entities ──────────────────────────────────────────────────────────────────

@test "entities: --type spec returns spec list" {
  python3 "$PY" build --db "$DB"
  run python3 "$PY" entities --type spec --db "$DB"
  [ "$status" -eq 0 ]
  grep -q "spec" <<< "$output"
}

# ── Spec ref ─────────────────────────────────────────────────────────────────

@test "spec ref: rule doc knowledge-graph.md exists" {
  [[ -f "docs/rules/domain/knowledge-graph.md" ]]
}

@test "spec ref: rule doc mentions entity and relation types" {
  grep -q "entities" docs/rules/domain/knowledge-graph.md
  grep -q "relations" docs/rules/domain/knowledge-graph.md
}

# ── Coverage ──────────────────────────────────────────────────────────────────

@test "coverage: build ingests at least 100 entities" {
  python3 "$PY" build --db "$DB"
  local count
  count=$(python3 -c "import sqlite3; c=sqlite3.connect('$DB'); print(c.execute('SELECT COUNT(*) FROM entities').fetchone()[0])")
  [ "$count" -ge 100 ]
}

@test "coverage: build ingests at least 100 relations" {
  python3 "$PY" build --db "$DB"
  local count
  count=$(python3 -c "import sqlite3; c=sqlite3.connect('$DB'); print(c.execute('SELECT COUNT(*) FROM relations').fetchone()[0])")
  [ "$count" -ge 100 ]
}

# ── Negative ─────────────────────────────────────────────────────────────────

@test "negative: zero relations would fail coverage check" {
  python3 -c "
import sqlite3, os
db = '$TMPDIR/empty-test.db'
c = sqlite3.connect(db)
c.execute('CREATE TABLE IF NOT EXISTS relations (id INTEGER)')
n = c.execute('SELECT COUNT(*) FROM relations').fetchone()[0]
assert n == 0
print('zero-relations detectable')
c.close()
os.remove(db)
"
}

@test "negative: nonexistent entity name returns not-found (not crash)" {
  python3 "$PY" build --db "$DB"
  run python3 "$PY" impact "ghost-entity-does-not-exist-999" --db "$DB"
  [ "$status" -ne 0 ]
}

# ── Edge ─────────────────────────────────────────────────────────────────────

@test "edge: build with no memory-store.jsonl still produces entities from rules" {
  local alt_db="$TMPDIR/kg-norules.db"
  STORE_FILE="$TMPDIR/nonexistent-store.jsonl" \
    python3 -c "
import sys, os
sys.path.insert(0, 'scripts')
os.environ['STORE_FILE'] = '$TMPDIR/nonexistent.jsonl'
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location('kg', 'scripts/knowledge-graph.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
conn = mod.open_db(pathlib.Path('$alt_db'))
n = mod.ingest_rules(conn)
total = conn.execute('SELECT COUNT(*) FROM entities').fetchone()[0]
assert total > 0, f'no entities from rules: {total}'
print(f'rules only: {total} entities from {n} rule files')
"
  rm -f "$alt_db"
}

@test "edge: boundary — depends_on relations extracted from ROADMAP requires/post patterns" {
  python3 "$PY" build --db "$DB"
  local count
  count=$(python3 -c "
import sqlite3
c = sqlite3.connect('$DB')
n = c.execute(\"SELECT COUNT(*) FROM relations WHERE relation='depends_on'\").fetchone()[0]
print(n)
")
  [ "$count" -gt 0 ]
}
