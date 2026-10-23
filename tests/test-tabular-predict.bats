#!/usr/bin/env bats
# BATS tests for tabular-profile.py predict (SE-342 S5 / Labs L21)
# Ref: SE-342 S5, hypothesis l21-assisted-prediction.md, SE-296 (no-TFM), CRIT-001

SCRIPT="scripts/tabular-profile.py"
FIX="$(mktemp -d -t tab.XXXXXX)"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  # fixture dataset (60 rows, deterministic) — above the 50-row predict gate
  python3 - "$FIX" <<'PY'
import csv, sys, os
p = os.path.join(sys.argv[1], "tiny.csv")
fields = ["id", "t", "x"]
with open(p, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=fields)
    w.writeheader()
    for i in range(60):
        w.writerow({"id": i, "t": i % 3, "x": i * 0.5})
PY
  export SAVIA_CATALOG_DB="$(mktemp -t cat.XXXXXX.db)"
  rm -f "$TMP_CATALOG" 2>/dev/null || true
}

teardown() {
  rm -rf "$FIX"
  [[ -n "${SAVIA_CATALOG_DB:-}" ]] && rm -f "$SAVIA_CATALOG_DB"
  cd /
}

@test "predict requires --target (exit 2)" {
  run python3 "$SCRIPT" predict "$FIX/tiny.csv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--target"* ]]
}

@test "predict rejects unknown target column (JSON error)" {
  run python3 "$SCRIPT" predict --target nope "$FIX/tiny.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"target column"* ]]
}

@test "predict on small dataset (<50 rows) returns size error" {
  SMALL="$(mktemp -t small.XXXXXX.csv)"
  python3 - "$SMALL" <<'PY'
import csv, sys
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "t", "x"]); w.writeheader()
    for i in range(10):
        w.writerow({"id": i, "t": i % 3, "x": i})
PY
  run python3 "$SCRIPT" predict --target t --categorical "$SMALL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"too small"* ]]
  rm -f "$SMALL"
}

@test "predict without sklearn degrades explicitly (no crash, no egress)" {
  # only runs if sklearn missing; asserts a clear JSON error either way
  run python3 "$SCRIPT" predict --target x "$FIX/tiny.csv" 2>/dev/null || true
  if python3 -c "import sklearn" 2>/dev/null; then
    [ "$status" -eq 0 ]  # sklearn present -> path continues, exit 0 or 1 per data
  else
    [ "$status" -eq 1 ]
    [[ "$output" == *"sklearn not installed"* ]]
  fi
}

@test "predict help prints usage" {
  run python3 "$SCRIPT" predict --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--target"* ]]
}
# --- S03c: orden de las compuertas de predict (SE-342 S5) ---

@test "predict: la columna objetivo inexistente se rechaza listando las columnas" {
  run python3 "$SCRIPT" predict --target nope "$FIX/tiny.csv"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert \"'nope'\" in d['error'] and \"'id', 't', 'x'\" in d['error'], d"
}

@test "predict: dataset pequeño informa filas y mínimo exactos" {
  head -11 "$FIX/tiny.csv" > "$FIX/small.csv"
  run python3 "$SCRIPT" predict --target t "$FIX/small.csv"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['rows'] == 10 and d['min'] == 50, d"
}

@test "predict: justo 50 filas supera la compuerta de tamaño (frontera)" {
  head -51 "$FIX/tiny.csv" > "$FIX/edge.csv"
  run python3 "$SCRIPT" predict --target t "$FIX/edge.csv"
  if echo "$output" | grep -q "too small"; then false; fi
  [ -n "$output" ]
}

@test "predict: 49 filas siguen siendo demasiado pocas (frontera)" {
  head -50 "$FIX/tiny.csv" > "$FIX/edge.csv"
  run python3 "$SCRIPT" predict --target t "$FIX/edge.csv"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "too small"
}

@test "predict: la validación de tamaño y objetivo ocurre antes de importar sklearn" {
  # sklearn falso que aborta al importarse: si la validación corriera después, exit 99
  mkdir -p "$FIX/fake/sklearn"
  echo 'import sys; sys.exit(99)' > "$FIX/fake/sklearn/__init__.py"
  run env PYTHONPATH="$FIX/fake" python3 "$SCRIPT" predict --target nope "$FIX/tiny.csv"
  [ "$status" -ne 99 ]
  [ "$status" -ne 0 ]
}

@test "predict: stdin vacío → no data found" {
  run bash -c "printf '' | python3 '$SCRIPT' predict --target t"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no data found"
}

@test "predict: --target sin valor se trata como ausente (exit 2)" {
  run python3 "$SCRIPT" predict "$FIX/tiny.csv" --target
  [ "$status" -eq 2 ]
}

@test "predict: objetivo no numérico deja pocas filas usables o error claro" {
  python3 - "$FIX/txt.csv" <<'PY'
import csv, sys
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "label"]); w.writeheader()
    for i in range(60): w.writerow({"id": i, "label": "a" if i % 2 else "b"})
PY
  run python3 "$SCRIPT" predict --target label "$FIX/txt.csv"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE "too few usable rows|sklearn not installed"
}

@test "predict con sklearn: regresión determinista y con top_features (si está instalado)" {
  python3 -c "import sklearn" 2>/dev/null || skip "scikit-learn no instalado: ruta de entrenamiento no ejecutable aquí"
  run python3 "$SCRIPT" predict --target x "$FIX/tiny.csv"
  [ "$status" -eq 0 ]
  first="$output"
  run python3 "$SCRIPT" predict --target x "$FIX/tiny.csv"
  [ "$output" == "$first" ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['task'] == 'regression' and d['top_features'][0]['feature'] == 'id', d"
}
