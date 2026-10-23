#!/usr/bin/env bats
# BATS tests for tabular-profile.py monitor (SE-342 S3 / Labs L19)
# Ref: SE-342 S3, hypothesis l19-data-quality-feature-store.md, CRIT-001

SCRIPT="scripts/tabular-profile.py"
FIX="$(mktemp -d -t dq.XXXXXX)"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  python3 - "$FIX" <<'PY'
import csv, sys, os
p = os.path.join(sys.argv[1], "ok.csv")
with open(p, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "t", "x"]); w.writeheader()
    for i in range(60):
        w.writerow({"id": i, "t": i % 3, "x": round(i * 0.5, 2)})
PY
  export SAVIA_DQ_DIR="$(mktemp -d -t dqbase.XXXXXX)"
  export SAVIA_CATALOG_DB="$(mktemp -t cat.XXXXXX.db)"
  rm -f "$SAVIA_CATALOG_DB"
}

teardown() {
  rm -rf "$FIX" "$SAVIA_DQ_DIR"
  [[ -n "${SAVIA_CATALOG_DB:-}" ]] && rm -f "$SAVIA_CATALOG_DB"
  cd /
}

@test "monitor init saves baseline (exit 0)" {
  run python3 "$SCRIPT" monitor init "$FIX/ok.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"baseline_saved"* ]]
}

@test "monitor check on unchanged data verdict PASS" {
  python3 "$SCRIPT" monitor init "$FIX/ok.csv" >/dev/null
  run python3 "$SCRIPT" monitor check "$FIX/ok.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict": "PASS"'* ]]
}

@test "monitor check detects completeness drop (missing values in column)" {
  python3 "$SCRIPT" monitor init "$FIX/ok.csv" >/dev/null
  # mutate the SAME file (same logical key) with 50% missing 'x'
  python3 - "$FIX/ok.csv" <<'PY'
import csv, sys
rows = []
with open(sys.argv[1], newline="") as fh:
    for r in csv.DictReader(fh):
        if int(r["id"]) % 2 == 0:
            r["x"] = ""   # 50% missing in x
        rows.append(r)
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)
PY
  run python3 "$SCRIPT" monitor check "$FIX/ok.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"verdict": "FAIL"'* ]]
  [[ "$output" == *"completeness"* ]]
}

@test "monitor check rejects when no baseline" {
  run python3 "$SCRIPT" monitor check "$FIX/ok.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no baseline"* ]]
}

@test "monitor detects schema drift (new column)" {
  python3 "$SCRIPT" monitor init "$FIX/ok.csv" >/dev/null
  python3 - "$FIX/ok.csv" <<'PY'
import csv, sys
rows = []
with open(sys.argv[1], newline="") as fh:
    for r in csv.DictReader(fh):
        r["y"] = int(r["id"])   # add new column
        rows.append(r)
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)
PY
  run python3 "$SCRIPT" monitor check "$FIX/ok.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"new column"* ]]
}

@test "feature store: revertible feature registered in catalog (L17 integration)" {
  python3 scripts/savia-catalog.py register --type dataset --name raw --level N2 >/dev/null
  run python3 scripts/savia-catalog.py register --type feature --name f_yield --level N2 \
    --from-name raw --from-type dataset --relation feeds
  [ "$status" -eq 0 ]
  run python3 scripts/savia-catalog.py lineage --name f_yield
  [ "$status" -eq 0 ]
  [[ "$output" == *"raw"* ]]
}
# --- S03c: veredictos y umbrales del monitor (SE-342 S3) ---

mon() { python3 "$SCRIPT" monitor "$@"; }

@test "init: el baseline guardado refleja filas, columnas y completitud exacta" {
  run mon init "$FIX/ok.csv"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert (d['action'], d['file'], d['rows'], d['cols']) == ('baseline_saved', 'ok.csv', 60, 3), d
b = json.load(open(d['baseline']))
assert b['cols'] == ['id', 't', 'x'], b
assert all(s['completeness'] == 100.0 for s in b['col_stats'].values()), b"
}

@test "check PASS: filas delta 0 e issues vacío" {
  mon init "$FIX/ok.csv" >/dev/null
  run mon check "$FIX/ok.csv"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['verdict'] == 'PASS' and d['issues'] == [], d
assert d['rows'] == {'now': 60, 'baseline': 60, 'delta': 0}, d"
}

@test "check: columna eliminada → WARN (no FAIL) y exit 1" {
  mon init "$FIX/ok.csv" >/dev/null
  python3 - "$FIX/ok.csv" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], newline="")))
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "t"]); w.writeheader()
    for r in rows: w.writerow({"id": r["id"], "t": r["t"]})
PY
  run mon check "$FIX/ok.csv"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['verdict'] == 'WARN', d
assert any(i['check'] == 'schema' and \"column 'x' missing\" in i['detail'] for i in d['issues']), d"
}

@test "check: completitud justo en el umbral pasa; un punto por debajo falla" {
  mon init "$FIX/ok.csv" >/dev/null
  python3 - "$FIX/ok.csv" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], newline="")))
for r in rows[:3]: r["x"] = ""          # 57/60 = 95.0 %
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "t", "x"]); w.writeheader(); w.writerows(rows)
PY
  run mon check "$FIX/ok.csv"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"verdict": "PASS"'
  run mon check --completeness 96 "$FIX/ok.csv"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
i = [x for x in d['issues'] if x['check'] == 'completeness'][0]
assert (i['column'], i['value'], i['min'], i['status']) == ('x', 95.0, 96, 'FAIL'), i"
}

@test "check: SAVIA_DQ_COMPLETENESS desde entorno cambia el umbral" {
  mon init "$FIX/ok.csv" >/dev/null
  python3 - "$FIX/ok.csv" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], newline="")))
for r in rows[:30]: r["x"] = ""
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "t", "x"]); w.writeheader(); w.writerows(rows)
PY
  SAVIA_DQ_COMPLETENESS=40 run mon check "$FIX/ok.csv"
  [ "$status" -eq 0 ]
  SAVIA_DQ_COMPLETENESS=60 run mon check "$FIX/ok.csv"
  [ "$status" -eq 1 ]
}

@test "check: fichero más nuevo que la ventana de frescura → WARN freshness" {
  mon init "$FIX/ok.csv" >/dev/null
  touch -d "+30 days" "$FIX/ok.csv"
  run mon check "$FIX/ok.csv"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
f = [i for i in d['issues'] if i['check'] == 'freshness'][0]
assert f['days'] >= 29 and f['max'] == 7 and f['status'] == 'WARN', f
assert d['verdict'] == 'WARN', d"
  run mon check --freshness-days 90 "$FIX/ok.csv"
  [ "$status" -eq 0 ]
}

@test "check: FAIL de completitud prevalece sobre WARN de esquema" {
  mon init "$FIX/ok.csv" >/dev/null
  python3 - "$FIX/ok.csv" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], newline="")))
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "t", "x", "extra"]); w.writeheader()
    for r in rows: w.writerow({**r, "x": "", "extra": "1"})
PY
  run mon check "$FIX/ok.csv"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
kinds = {i['check'] for i in d['issues']}
assert kinds == {'schema', 'completeness'}, kinds
assert d['verdict'] == 'FAIL', d"
}

@test "check: el delta de filas se informa con signo" {
  mon init "$FIX/ok.csv" >/dev/null
  head -41 "$FIX/ok.csv" > "$FIX/trim.csv" && mv "$FIX/trim.csv" "$FIX/ok.csv"
  run mon check "$FIX/ok.csv"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['rows'] == {'now': 40, 'baseline': 60, 'delta': -20}, d"
}

@test "baselines aislados por nombre de fichero" {
  cp "$FIX/ok.csv" "$FIX/otro.csv"
  mon init "$FIX/ok.csv" >/dev/null
  run mon check "$FIX/otro.csv"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no baseline"
}

@test "fichero vacío → error 'no data found' en init y check" {
  : > "$FIX/vacio.csv"
  run mon init "$FIX/vacio.csv"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no data found"
  run mon check "$FIX/vacio.csv"
  [ "$status" -eq 1 ]
}

@test "init sobrescribe el baseline previo (re-init acepta el nuevo estado)" {
  mon init "$FIX/ok.csv" >/dev/null
  head -11 "$FIX/ok.csv" > "$FIX/t.csv" && mv "$FIX/t.csv" "$FIX/ok.csv"
  mon init "$FIX/ok.csv" >/dev/null
  run mon check "$FIX/ok.csv"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"baseline": 10'
}

@test "monitor --help imprime uso y sale 0" {
  run mon --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "monitor <init|check>"
}
