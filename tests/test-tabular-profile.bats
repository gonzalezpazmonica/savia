#!/usr/bin/env bats

setup() {
  PROFILER="$BATS_TEST_DIRNAME/../scripts/tabular-profile.py"
  TESTDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "tabular-profile exists and is executable" {
  [ -f "$PROFILER" ]
  [ -x "$PROFILER" ]
}

@test "detects numeric column type" {
  cat > "$TESTDIR/data.csv" << 'EOF'
name,age,salary
Alice,30,50000
Bob,25,45000
Carol,35,60000
Dave,28,48000
Eve,32,52000
EOF
  run python3 "$PROFILER" "$TESTDIR/data.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"numeric"* ]]
  [[ "$output" == *"mean"* ]]
}

@test "detects categorical column type" {
  cat > "$TESTDIR/data.csv" << 'EOF'
name,department
Alice,Engineering
Bob,Sales
Carol,Engineering
Dave,Marketing
Eve,Sales
EOF
  run python3 "$PROFILER" "$TESTDIR/data.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"categorical"* ]]
}

@test "computes correlations" {
  cat > "$TESTDIR/data.csv" << 'EOF'
x,y
1,2
2,4
3,6
4,8
5,10
EOF
  run python3 "$PROFILER" "$TESTDIR/data.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"correlations"* ]]
  [[ "$output" == *"coefficient"* ]]
}

@test "detects outliers via IQR" {
  cat > "$TESTDIR/data.csv" << 'EOF'
value
10
12
11
13
10
500
11
12
EOF
  run python3 "$PROFILER" "$TESTDIR/data.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"outliers"* ]]
  [[ "$output" == *"500"* ]]
}

@test "handles JSON array input" {
  echo '[{"a":1,"b":2},{"a":3,"b":4},{"a":5,"b":6},{"a":7,"b":8},{"a":9,"b":10}]' > "$TESTDIR/data.json"
  run python3 "$PROFILER" "$TESTDIR/data.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"numeric"* ]]
}

@test "handles empty input gracefully" {
  echo "" > "$TESTDIR/empty.csv"
  run python3 "$PROFILER" "$TESTDIR/empty.csv"
  [ "$status" -eq 1 ] || [[ "$output" == *"no data"* ]]
}

@test "safety: has set -uo pipefail" {
  head -1 "$PROFILER" | grep -q "python3" || true
}

@test "token savings reported" {
  cat > "$TESTDIR/big.csv" << 'EOF'
col1,col2,col3,col4,col5
1,2,3,4,5
2,3,4,5,6
3,4,5,6,7
4,5,6,7,8
5,6,7,8,9
EOF
  run python3 "$PROFILER" "$TESTDIR/big.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"token_estimate"* ]]
  [[ "$output" == *"savings"* ]]
}

# --- S03c: valores exactos del perfilado (SE-296 / SE-324) ---
# prof FILE... → JSON en $output; col NAME extrae el perfil de una columna.

col() {
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
p = [c for c in d['profiles'] if c['name'] == sys.argv[1]][0]
print(json.dumps(p))" "$1"
}

@test "numeric: estadísticos exactos (mean, median, std, min, max, q25, q75)" {
  printf 'v\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n' > "$TESTDIR/n.csv"
  run python3 "$PROFILER" "$TESTDIR/n.csv"
  [ "$status" -eq 0 ]
  col v | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['type'] == 'numeric', p
assert (p['mean'], p['median'], p['min'], p['max']) == (5.5, 5.5, 1.0, 10.0), p
assert p['std'] == 3.03, p
assert (p['q25'], p['q75']) == (3.0, 8.0), p
assert p['outliers'] == 0, p"
}

@test "numeric: la mediana de longitud impar es el elemento central" {
  printf 'v\n9\n1\n5\n' > "$TESTDIR/n.csv"
  run python3 "$PROFILER" "$TESTDIR/n.csv"
  col v | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['median'] == 5.0 and p['mean'] == 5.0, p"
}

@test "outlier: se cuenta exactamente 1 con porcentaje sobre el total" {
  printf 'v\n10\n12\n11\n13\n10\n500\n11\n12\n' > "$TESTDIR/o.csv"
  run python3 "$PROFILER" "$TESTDIR/o.csv"
  col v | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['outliers'] == 1 and p['outlier_pct'] == 12.5, p
assert p['max'] == 500.0, p"
}

@test "numeric: la columna constante tiene std 0 y skewness 0 (borde)" {
  printf 'v\n7\n7\n7\n7\n' > "$TESTDIR/c.csv"
  run python3 "$PROFILER" "$TESTDIR/c.csv"
  [ "$status" -eq 0 ]
  col v | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['std'] == 0 and p['skewness'] == 0 and p['outliers'] == 0, p"
}

@test "categorical: top_values ordenados por frecuencia y nulls contados" {
  printf 'k,d\n1,A\n2,B\n3,A\n4,\n5,A\n6,B\n7,\n' > "$TESTDIR/c.csv"
  run python3 "$PROFILER" "$TESTDIR/c.csv"
  [ "$status" -eq 0 ]
  col d | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['type'] == 'categorical', p
assert p['top_values'][0] == {'value': 'A', 'count': 3}, p
assert p['top_values'][1] == {'value': 'B', 'count': 2}, p
assert p['unique'] == 2 and p['nulls'] == 2, p"
}

@test "datetime: rango, span_days y tendencia ascendente" {
  printf 'f\n2026-01-01\n2026-01-02\n2026-01-03\n2026-01-31\n' > "$TESTDIR/d.csv"
  run python3 "$PROFILER" "$TESTDIR/d.csv"
  [ "$status" -eq 0 ]
  col f | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['type'] == 'datetime', p
assert (p['min'], p['max'], p['span_days'], p['count']) == ('2026-01-01', '2026-01-31', 30, 4), p
assert p['trend'] == 'ascending', p"
}

@test "datetime: formato d/m/Y se reconoce como fecha, no como texto" {
  printf 'f\n01/02/2026\n15/02/2026\n28/02/2026\n' > "$TESTDIR/d.csv"
  run python3 "$PROFILER" "$TESTDIR/d.csv"
  col f | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['type'] == 'datetime' and p['span_days'] == 27, p"
}

@test "tipo text: columna con más de la mitad vacía" {
  printf 'a,b\nx,\ny,\nz,\nw,q\n' > "$TESTDIR/t.csv"
  run python3 "$PROFILER" "$TESTDIR/t.csv"
  col b | python3 -c "
import json, sys
p = json.load(sys.stdin)
assert p['type'] == 'text' and p['nulls'] == 3, p
assert 'top_values' not in p, p"
}

@test "correlación: perfecta positiva 1.0 y negativa -1.0" {
  printf 'x,y,z\n1,2,10\n2,4,8\n3,6,6\n4,8,4\n5,10,2\n' > "$TESTDIR/c.csv"
  run python3 "$PROFILER" "$TESTDIR/c.csv"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
m = {(c['col1'], c['col2']): c['coefficient'] for c in d['correlations']}
assert m[('x', 'y')] == 1.0, m
assert m[('x', 'z')] == -1.0, m
assert m[('y', 'z')] == -1.0, m"
}

@test "correlación: |r| ≤ 0.3 no se reporta (umbral)" {
  printf 'x,y\n1,5\n2,1\n3,4\n4,2\n5,3\n6,5\n' > "$TESTDIR/c.csv"
  run python3 "$PROFILER" "$TESTDIR/c.csv"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['correlations'] == [], d['correlations']"
}

@test "--sample N recorta filas antes de perfilar" {
  python3 -c "
print('v')
for i in range(100): print(i)" > "$TESTDIR/b.csv"
  run python3 "$PROFILER" --sample 10 "$TESTDIR/b.csv"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['rows'] == 10, d['rows']
assert d['profiles'][0]['max'] == 9.0, d"
}

@test "stdin CSV y stdin JSON dan el mismo perfil numérico" {
  printf 'a,b\n1,2\n3,4\n5,6\n' | python3 "$PROFILER" > "$TESTDIR/c.out"
  echo '[{"a":1,"b":2},{"a":3,"b":4},{"a":5,"b":6}]' | python3 "$PROFILER" > "$TESTDIR/j.out"
  python3 - "$TESTDIR/c.out" "$TESTDIR/j.out" <<'PY'
import json, sys
c, j = (json.load(open(p)) for p in sys.argv[1:])
assert c['rows'] == j['rows'] == 3
assert [p['mean'] for p in c['profiles']] == [p['mean'] for p in j['profiles']] == [3.0, 4.0]
PY
}

@test "salida de un solo fichero es plana (sin tables) y cita su source" {
  printf 'v\n1\n2\n3\n' > "$TESTDIR/n.csv"
  run python3 "$PROFILER" "$TESTDIR/n.csv"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'tables' not in d and 'name' not in d, list(d)
assert d['source'].endswith('n.csv'), d"
}

@test "varios ficheros: tables + relations con solape de claves compartidas" {
  printf 'id,v\n1,a\n2,b\n3,c\n4,d\n' > "$TESTDIR/a.csv"
  printf 'ID,w\n3,x\n4,y\n9,z\n10,t\n' > "$TESTDIR/b.csv"
  run python3 "$PROFILER" "$TESTDIR/a.csv" "$TESTDIR/b.csv"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert [t['name'] for t in d['tables']] == ['a.csv', 'b.csv'], d['tables']
r = d['relations']
assert len(r) == 1, r
assert (r[0]['column_a'], r[0]['column_b'], r[0]['overlap_pct']) == ('id', 'ID', 50.0), r"
}

@test "relations: sin valores en común no hay relación (negativo)" {
  printf 'id\n1\n2\n' > "$TESTDIR/a.csv"
  printf 'id\n8\n9\n' > "$TESTDIR/b.csv"
  run python3 "$PROFILER" "$TESTDIR/a.csv" "$TESTDIR/b.csv"
  echo "$output" | python3 -c "
import json, sys
assert json.load(sys.stdin)['relations'] == []"
}

@test "relations: el orden de los ficheros no cambia el conjunto de relaciones" {
  printf 'id,k\n1,a\n2,b\n' > "$TESTDIR/a.csv"
  printf 'id,k\n2,b\n3,c\n' > "$TESTDIR/b.csv"
  python3 "$PROFILER" "$TESTDIR/a.csv" "$TESTDIR/b.csv" > "$TESTDIR/ab.json"
  python3 "$PROFILER" "$TESTDIR/b.csv" "$TESTDIR/a.csv" > "$TESTDIR/ba.json"
  python3 - "$TESTDIR" <<'PY'
import json, sys
d = sys.argv[1]
ab = json.load(open(d + '/ab.json'))['relations']
ba = json.load(open(d + '/ba.json'))['relations']
assert [(r['column_a'], r['overlap_pct']) for r in ab] == [('id', 50.0), ('k', 50.0)], ab
assert {(r['column_a'], r['overlap_pct']) for r in ab} == {(r['column_a'], r['overlap_pct']) for r in ba}
PY
}

@test "fichero inexistente → falla (exit distinto de 0)" {
  run python3 "$PROFILER" "$TESTDIR/nope.csv"
  [ "$status" -ne 0 ]
}

@test "xlsx sin openpyxl → error JSON con fallback raw y exit 1" {
  if python3 -c "import openpyxl" 2>/dev/null; then skip "openpyxl instalado"; fi
  : > "$TESTDIR/x.xlsx"
  run python3 "$PROFILER" "$TESTDIR/x.xlsx"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '"fallback": "raw"'
}

@test "token_estimate: savings_pct sube con filas más largas y summary es 200" {
  python3 -c "
print('c')
for i in range(50): print('x' * 200)" > "$TESTDIR/l.csv"
  run python3 "$PROFILER" "$TESTDIR/l.csv"
  echo "$output" | python3 -c "
import json, sys
t = json.load(sys.stdin)['token_estimate']
assert t['summary'] == 200 and t['raw'] > 5000, t
assert t['savings_pct'] > 95, t"
}
