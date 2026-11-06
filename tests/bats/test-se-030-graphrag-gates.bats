#!/usr/bin/env bats
# tests/bats/test-se-030-graphrag-gates.bats — SE-030 GraphRAG Quality Gates
# Tests for scripts/graphrag-quality-gates.sh
#
# Ref: docs/propuestas/SE-030-graphrag-quality-gates.md

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/graphrag-quality-gates.sh"

setup() {
  # Fixtures en un directorio temporal propio: nada se escribe en el repo.
  FIXTURE_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/graphrag.XXXXXX")"
}

teardown() {
  rm -f "$FIXTURE_DIR"/*.db 2>/dev/null || true
}

# ── Helper: create a minimal valid SQLite KG ─────────────────────────────────
create_minimal_db() {
  local db="$1"
  python3 - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.executescript("""
CREATE TABLE entities (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    first_seen TEXT DEFAULT (datetime('now')),
    last_seen  TEXT DEFAULT (datetime('now')),
    confidence REAL DEFAULT 0.8,
    provenance TEXT DEFAULT 'test'
);
CREATE TABLE relations (
    id INTEGER PRIMARY KEY,
    entity_a INTEGER NOT NULL,
    relation TEXT NOT NULL,
    entity_b INTEGER NOT NULL,
    confidence REAL DEFAULT 1.0
);
INSERT INTO entities VALUES (1,'Alpha','concept',datetime('now'),datetime('now'),0.9,'test.md');
INSERT INTO entities VALUES (2,'Beta','tool',datetime('now'),datetime('now'),0.8,'test.md');
INSERT INTO entities VALUES (3,'Gamma','decision',datetime('now'),datetime('now'),0.7,'test.md');
INSERT INTO entities VALUES (4,'Delta','skill',datetime('now'),datetime('now'),0.95,'test.md');
INSERT INTO entities VALUES (5,'Epsilon','project',datetime('now'),datetime('now'),0.85,'test.md');
INSERT INTO entities VALUES (6,'Zeta','person',datetime('now'),datetime('now'),0.75,'test.md');
INSERT INTO entities VALUES (7,'Eta','spec',datetime('now'),datetime('now'),0.8,'test.md');
INSERT INTO entities VALUES (8,'Theta','rule',datetime('now'),datetime('now'),0.9,'test.md');
INSERT INTO entities VALUES (9,'Iota','concept',datetime('now'),datetime('now'),0.85,'test.md');
INSERT INTO entities VALUES (10,'Kappa','tool',datetime('now'),datetime('now'),0.9,'test.md');
INSERT INTO relations VALUES (1,1,'uses',2,1.0);
INSERT INTO relations VALUES (2,2,'depends_on',3,1.0);
INSERT INTO relations VALUES (3,3,'implements',4,1.0);
INSERT INTO relations VALUES (4,5,'owns',6,1.0);
INSERT INTO relations VALUES (5,7,'mentions',8,1.0);
INSERT INTO relations VALUES (6,9,'uses',10,1.0);
INSERT INTO relations VALUES (7,1,'related_to',3,1.0);
INSERT INTO relations VALUES (8,4,'blocks',5,1.0);
INSERT INTO relations VALUES (9,6,'related_to',7,1.0);
INSERT INTO relations VALUES (10,8,'depends_on',9,1.0);
""")
con.close()
PY
}

# ── Test 1: Script exists and is executable ───────────────────────────────────
@test "SE-030-01: script exists and is bash-parseable" {
  [ -f "$SCRIPT" ]
  bash -n "$SCRIPT"
}

# ── Test 2: Script produces output (table format) ────────────────────────────
@test "SE-030-02: script produces output for valid DB" {
  create_minimal_db "$FIXTURE_DIR/minimal.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/minimal.db"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [[ "$output" == *"GraphRAG Quality Gates"* ]] || [[ "$output" == *"Summary"* ]]
}

# ── Test 3: JSON output is valid JSON with required keys ─────────────────────
@test "SE-030-03: --json output is valid JSON with checks and summary" {
  create_minimal_db "$FIXTURE_DIR/json_test.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/json_test.db" --json
  # Must be valid JSON parseable by python
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'checks' in d; assert 'summary' in d"
  [ $? -eq 0 ]
}

# ── Test 4: JSON output has exactly 12 checks ────────────────────────────────
@test "SE-030-04: JSON output contains exactly 12 checks" {
  create_minimal_db "$FIXTURE_DIR/count_test.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/count_test.db" --json
  count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['checks']))")
  [ "$count" -eq 12 ]
}

# ── Test 5: Missing DB emits WARN not hard error ──────────────────────────────
@test "SE-030-05: missing database does not crash (exits 0 with WARN)" {
  run bash "$SCRIPT" --db "/tmp/nonexistent-$(date +%s).db"
  # Should exit 0 (WARN) not 2 (crash)
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [[ "$output" != *"Traceback"* ]]
}

# ── Test 6: Summary line appears in text output ───────────────────────────────
@test "SE-030-06: text output contains Summary line" {
  create_minimal_db "$FIXTURE_DIR/summary_test.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/summary_test.db"
  [[ "$output" == *"Summary:"* ]]
}

# ── Test 7: Minimal valid DB passes min-entity-count check ───────────────────
@test "SE-030-07: valid DB with 10 entities passes min-entity-count" {
  create_minimal_db "$FIXTURE_DIR/entity_count.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/entity_count.db" --json
  status_val=$(echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
check = next(c for c in d['checks'] if c['name'] == 'min-entity-count')
print(check['status'])
")
  [ "$status_val" = "PASS" ]
}

# ── Test 8: Self-loops are detected as FAIL ───────────────────────────────────
@test "SE-030-08: self-loops in relations are detected as FAIL" {
  create_minimal_db "$FIXTURE_DIR/self_loop.db"
  python3 -c "
import sqlite3
con=sqlite3.connect('$FIXTURE_DIR/self_loop.db')
con.execute(\"INSERT INTO relations VALUES(99,1,'self',1,1.0)\")
con.commit(); con.close()
"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/self_loop.db" --json
  status_val=$(echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
check = next(c for c in d['checks'] if c['name'] == 'no-self-loops')
print(check['status'])
")
  [ "$status_val" = "FAIL" ]
}

# ── Test 9: confidence out of range detected ──────────────────────────────────
@test "SE-030-09: confidence scores outside [0,1] are detected as FAIL" {
  create_minimal_db "$FIXTURE_DIR/conf_fail.db"
  python3 -c "
import sqlite3
con=sqlite3.connect('$FIXTURE_DIR/conf_fail.db')
con.execute(\"UPDATE entities SET confidence=1.5 WHERE id=1\")
con.commit(); con.close()
"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/conf_fail.db" --json
  status_val=$(echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
check = next(c for c in d['checks'] if c['name'] == 'confidence-range')
print(check['status'])
")
  [ "$status_val" = "FAIL" ]
}

# ── Test 10: --help does not crash ────────────────────────────────────────────
@test "SE-030-10: --help flag exits cleanly" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
}

# ── S03o: comportamiento discriminante por check, umbrales y errores ─────────

sql() { python3 -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.executescript(sys.argv[2]); c.close()' "$1" "$2"; }

# check_of <db> <nombre>: estado de un check en la salida JSON.
check_of() {
  bash "$SCRIPT" --db "$1" --json | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(next(c["status"] for c in d["checks"] if c["name"]==sys.argv[1]))' "$2"
}

@test "SE-030-11: grafo sano da 12 PASS y exit 0" {
  create_minimal_db "$FIXTURE_DIR/ok.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/ok.db"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary: 12 PASS, 0 WARN, 0 FAIL"* ]]
}

@test "SE-030-12: last_seen en el futuro es FAIL (esquema real de knowledge-graph.py)" {
  create_minimal_db "$FIXTURE_DIR/future.db"
  sql "$FIXTURE_DIR/future.db" "UPDATE entities SET last_seen=datetime('now','+2 hours') WHERE id=3"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/future.db"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 entities with future last_seen"* ]]
}

@test "SE-030-13: created_at ISO con T en el futuro del mismo día es FAIL" {
  create_minimal_db "$FIXTURE_DIR/iso.db"
  sql "$FIXTURE_DIR/iso.db" "ALTER TABLE entities ADD COLUMN created_at TEXT; UPDATE entities SET created_at=strftime('%Y-%m-%d %H:%M:%S','now','-1 day'); UPDATE entities SET created_at=strftime('%Y-%m-%dT%H:%M:%S+00:00','now','+30 minutes') WHERE id=1"
  [ "$(check_of "$FIXTURE_DIR/iso.db" no-future-timestamps)" = "FAIL" ]
}

@test "SE-030-14: fechas pasadas en first_seen/last_seen dan PASS y se nombran las columnas" {
  create_minimal_db "$FIXTURE_DIR/past.db"
  sql "$FIXTURE_DIR/past.db" "UPDATE entities SET first_seen=datetime('now','-3 days'), last_seen=datetime('now','-1 minute')"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/past.db" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
c=next(c for c in json.load(sys.stdin)["checks"] if c["name"]=="no-future-timestamps")
assert c["status"]=="PASS" and "first_seen, last_seen" in c["detail"], c'
}

@test "SE-030-15: huérfanos: 5 es WARN y 6 es FAIL (límite)" {
  create_minimal_db "$FIXTURE_DIR/orph.db"
  sql "$FIXTURE_DIR/orph.db" "INSERT INTO entities(id,name,type,provenance) VALUES (11,'o1','concept','t'),(12,'o2','concept','t'),(13,'o3','concept','t'),(14,'o4','concept','t'),(15,'o5','concept','t')"
  [ "$(check_of "$FIXTURE_DIR/orph.db" no-orphan-nodes)" = "WARN" ]
  sql "$FIXTURE_DIR/orph.db" "INSERT INTO entities(id,name,type,provenance) VALUES (16,'o6','concept','t')"
  [ "$(check_of "$FIXTURE_DIR/orph.db" no-orphan-nodes)" = "FAIL" ]
}

@test "SE-030-16: arista a nodo inexistente es FAIL y el gate sale 1" {
  create_minimal_db "$FIXTURE_DIR/dangling.db"
  sql "$FIXTURE_DIR/dangling.db" "INSERT INTO relations VALUES (50,1,'uses',999,1.0)"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/dangling.db"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 edges reference non-existent nodes"* ]]
}

@test "SE-030-17: tipos desconocidos: 3 es WARN y 4 es FAIL (límite)" {
  create_minimal_db "$FIXTURE_DIR/types.db"
  sql "$FIXTURE_DIR/types.db" "UPDATE entities SET type='x1' WHERE id=1; UPDATE entities SET type='x2' WHERE id=2; UPDATE entities SET type='x3' WHERE id=3"
  [ "$(check_of "$FIXTURE_DIR/types.db" type-consistency)" = "WARN" ]
  sql "$FIXTURE_DIR/types.db" "UPDATE entities SET type='x4' WHERE id=4"
  [ "$(check_of "$FIXTURE_DIR/types.db" type-consistency)" = "FAIL" ]
}

@test "SE-030-18: duplicados nombre+tipo: 3 grupos es WARN y 4 es FAIL (límite)" {
  create_minimal_db "$FIXTURE_DIR/dup.db"
  sql "$FIXTURE_DIR/dup.db" "INSERT INTO entities(id,name,type,provenance) VALUES (21,'Alpha','concept','t'),(22,'Beta','tool','t'),(23,'Gamma','decision','t')"
  [ "$(check_of "$FIXTURE_DIR/dup.db" no-exact-duplicates)" = "WARN" ]
  sql "$FIXTURE_DIR/dup.db" "INSERT INTO entities(id,name,type,provenance) VALUES (24,'Delta','skill','t')"
  [ "$(check_of "$FIXTURE_DIR/dup.db" no-exact-duplicates)" = "FAIL" ]
}

@test "SE-030-19: grafo vacío (zero entidades) es FAIL; 9 entidades es WARN" {
  create_minimal_db "$FIXTURE_DIR/few.db"
  sql "$FIXTURE_DIR/few.db" "DELETE FROM relations WHERE entity_a=10 OR entity_b=10; DELETE FROM entities WHERE id=10"
  [ "$(check_of "$FIXTURE_DIR/few.db" min-entity-count)" = "WARN" ]
  sql "$FIXTURE_DIR/few.db" "DELETE FROM relations; DELETE FROM entities"
  [ "$(check_of "$FIXTURE_DIR/few.db" min-entity-count)" = "FAIL" ]
  [ "$(check_of "$FIXTURE_DIR/few.db" basic-connectivity)" = "WARN" ]
}

@test "SE-030-20: nombre vacío o en blanco es FAIL" {
  create_minimal_db "$FIXTURE_DIR/blank.db"
  sql "$FIXTURE_DIR/blank.db" "UPDATE entities SET name='   ' WHERE id=2"
  [ "$(check_of "$FIXTURE_DIR/blank.db" no-empty-required-props)" = "FAIL" ]
}

@test "SE-030-21: tamaño: 10000 entidades es PASS y 10001 es WARN (límite large)" {
  create_minimal_db "$FIXTURE_DIR/large.db"
  sql "$FIXTURE_DIR/large.db" "WITH RECURSIVE n(i) AS (SELECT 11 UNION ALL SELECT i+1 FROM n WHERE i<10000) INSERT INTO entities(id,name,type,provenance) SELECT i,'n'||i,'concept','t' FROM n"
  [ "$(check_of "$FIXTURE_DIR/large.db" reasonable-graph-size)" = "PASS" ]
  sql "$FIXTURE_DIR/large.db" "INSERT INTO entities(id,name,type,provenance) VALUES (10001,'big','concept','t')"
  [ "$(check_of "$FIXTURE_DIR/large.db" reasonable-graph-size)" = "WARN" ]
}

@test "SE-030-22: confianza 0 y 1 son válidas (límite); negativa es FAIL" {
  create_minimal_db "$FIXTURE_DIR/conf.db"
  sql "$FIXTURE_DIR/conf.db" "UPDATE entities SET confidence=0 WHERE id=1; UPDATE entities SET confidence=1 WHERE id=2"
  [ "$(check_of "$FIXTURE_DIR/conf.db" confidence-range)" = "PASS" ]
  sql "$FIXTURE_DIR/conf.db" "UPDATE entities SET confidence=-0.01 WHERE id=3"
  [ "$(check_of "$FIXTURE_DIR/conf.db" confidence-range)" = "FAIL" ]
}

@test "SE-030-23: procedencia: 1 de 10 unknown es WARN y 5 de 10 vacías es FAIL" {
  create_minimal_db "$FIXTURE_DIR/src.db"
  sql "$FIXTURE_DIR/src.db" "UPDATE entities SET provenance='unknown' WHERE id=1"
  [ "$(check_of "$FIXTURE_DIR/src.db" source-not-empty)" = "WARN" ]
  sql "$FIXTURE_DIR/src.db" "UPDATE entities SET provenance='' WHERE id IN (2,3,4,5)"
  [ "$(check_of "$FIXTURE_DIR/src.db" source-not-empty)" = "FAIL" ]
}

@test "SE-030-24: esquema real sin confidence ni provenance: esos checks son WARN, no PASS" {
  local db="$FIXTURE_DIR/real.db"
  sql "$db" "CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, first_seen TEXT DEFAULT (datetime('now')), last_seen TEXT DEFAULT (datetime('now')));
CREATE TABLE relations (id INTEGER PRIMARY KEY, entity_a INTEGER, relation TEXT, entity_b INTEGER);
INSERT INTO entities(id,name,type) VALUES (1,'a','concept'),(2,'b','tool');
INSERT INTO relations VALUES (1,1,'uses',2);"
  [ "$(check_of "$db" confidence-range)" = "WARN" ]
  [ "$(check_of "$db" source-not-empty)" = "WARN" ]
  [ "$(check_of "$db" no-future-timestamps)" = "PASS" ]
}

@test "SE-030-25: columnas source_id/target_id también se detectan (self-loop FAIL)" {
  local db="$FIXTURE_DIR/alt.db"
  sql "$db" "CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, type TEXT);
CREATE TABLE relations (id INTEGER PRIMARY KEY, source_id INTEGER, target_id INTEGER);
INSERT INTO entities VALUES (1,'a','concept'),(2,'b','tool');
INSERT INTO relations VALUES (1,1,2),(2,2,2);"
  [ "$(check_of "$db" no-self-loops)" = "FAIL" ]
  [ "$(check_of "$db" no-dangling-edges)" = "PASS" ]
}

@test "SE-030-26: relaciones sin columnas de arista reconocibles: WARN, no PASS" {
  local db="$FIXTURE_DIR/nocols.db"
  sql "$db" "CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, type TEXT);
CREATE TABLE relations (id INTEGER PRIMARY KEY, a INTEGER, b INTEGER);
INSERT INTO entities VALUES (1,'a','concept');"
  [ "$(check_of "$db" no-orphan-nodes)" = "WARN" ]
  [ "$(check_of "$db" no-self-loops)" = "WARN" ]
}

@test "SE-030-27: sin tablas: los checks estructurales son WARN" {
  local db="$FIXTURE_DIR/empty.db"
  sql "$db" "CREATE TABLE otra (x INTEGER);"
  run bash "$SCRIPT" --db "$db" --json
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
st={c["name"]:c["status"] for c in d["checks"]}
assert st["no-orphan-nodes"]=="WARN" and st["min-entity-count"]=="WARN" and st["no-future-timestamps"]=="WARN", st'
}

@test "SE-030-28: base inexistente con --json: exit 1 y JSON válido aunque la ruta tenga comillas" {
  run bash "$SCRIPT" --db "$FIXTURE_DIR/no \"existe\".db" --json
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["error"]=="database not found" and d["db"].endswith("no \"existe\".db"), d'
}

@test "SE-030-29: base inexistente en texto: exit 0 con WARN y orden de reconstrucción" {
  run bash "$SCRIPT" --db "$FIXTURE_DIR/missing.db"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary: 0 PASS, 1 WARN, 0 FAIL"* ]]
  [[ "$output" == *"knowledge-graph.py build"* ]]
}

@test "SE-030-30: flag desconocida o --db sin valor: exit 2 (no arg)" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown flag '--bogus'"* ]]
  run bash "$SCRIPT" --db
  [ "$status" -eq 2 ]
  [[ "$output" == *"--db requires a path"* ]]
}

@test "SE-030-31: --quiet solo imprime el resumen" {
  create_minimal_db "$FIXTURE_DIR/q.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/q.db" --quiet
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "Summary: 12 PASS, 0 WARN, 0 FAIL" ]]
}

@test "SE-030-32: fichero que no es SQLite: falla con exit distinto de 0 (fail-closed)" {
  printf 'no soy una base de datos\n' > "$FIXTURE_DIR/garbage.db"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/garbage.db"
  [ "$status" -ne 0 ]
  [[ "$output" != *"0 FAIL"* ]]
}

@test "SE-030-33: el script declara set -uo pipefail" {
  head -5 "$SCRIPT" | grep -q "set -uo pipefail"
}

@test "SE-030-34: created_at con espacio unos segundos en el futuro es FAIL; ISO con T en el pasado es PASS" {
  create_minimal_db "$FIXTURE_DIR/fmt.db"
  sql "$FIXTURE_DIR/fmt.db" "ALTER TABLE entities ADD COLUMN created_at TEXT; UPDATE entities SET created_at=strftime('%Y-%m-%dT%H:%M:%S+00:00','now','-30 minutes')"
  [ "$(check_of "$FIXTURE_DIR/fmt.db" no-future-timestamps)" = "PASS" ]
  sql "$FIXTURE_DIR/fmt.db" "UPDATE entities SET created_at=datetime('now','+30 seconds') WHERE id=4"
  [ "$(check_of "$FIXTURE_DIR/fmt.db" no-future-timestamps)" = "FAIL" ]
}

@test "SE-030-35: entidades sin ninguna columna de fecha: WARN, no PASS" {
  local db="$FIXTURE_DIR/nodates.db"
  sql "$db" "CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, type TEXT); INSERT INTO entities VALUES (1,'a','concept');"
  run bash "$SCRIPT" --db "$db" --json
  echo "$output" | python3 -c '
import json,sys
c=next(c for c in json.load(sys.stdin)["checks"] if c["name"]=="no-future-timestamps")
assert c["status"]=="WARN" and "no timestamp column" in c["detail"], c'
}

@test "SE-030-36: procedencia exactamente al 10% (límite) cae en el tramo de unknown" {
  create_minimal_db "$FIXTURE_DIR/ten.db"
  sql "$FIXTURE_DIR/ten.db" "UPDATE entities SET provenance='unknown' WHERE id=7"
  run bash "$SCRIPT" --db "$FIXTURE_DIR/ten.db"
  [[ "$output" == *"1/10 entities have 'unknown' provenance"* ]]
}

@test "SE-030-37: un check que lanza excepción cuenta como FAIL (sin columna name)" {
  local db="$FIXTURE_DIR/noname.db"
  sql "$db" "CREATE TABLE entities (id INTEGER PRIMARY KEY, type TEXT); CREATE TABLE relations (id INTEGER PRIMARY KEY, entity_a INTEGER, entity_b INTEGER); INSERT INTO entities VALUES (1,'concept'),(2,'tool'); INSERT INTO relations VALUES (1,1,2);"
  run bash "$SCRIPT" --db "$db"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FAIL] #04 no-exact-duplicates"*"Exception"* ]]
}
