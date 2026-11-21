#!/usr/bin/env bats
# Ref: SE-220 Slice 0 / SE-376 S03 — scripts/speculative/feasibility-probe.sh
#
# Comportamiento del probe con una base de sesiones sintética (FEASIBILITY_DB): la decisión
# GO/DEFERRED/ABORT sale de la tasa de acierto real del predictor, el informe refleja los datos
# y un fallo (sin base, pocos datos, argumentos malos) nunca se presenta como GO.

SCRIPT="scripts/speculative/feasibility-probe.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMPDIR="$(mktemp -d)"
  export FEASIBILITY_DB="$TMPDIR/sessions.db"
  OUT="$TMPDIR/out"
}

teardown() { rm -rf "$TMPDIR"; }

# mkdb <tool> [<tool>...] — una sesión con esa secuencia de herramientas
mkdb() {
  python3 - "$FEASIBILITY_DB" "$@" <<'PY'
import sqlite3, sys, json
db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE IF NOT EXISTS part (session_id TEXT, time_created INTEGER, data TEXT)")
for i, tool in enumerate(sys.argv[2:]):
    db.execute("INSERT INTO part VALUES (?,?,?)",
               ("sess-aaaaaaaaaaaaaaaa", i, json.dumps({"type": "tool", "tool": tool, "state": {"input": {}}}, separators=(",", ":"))))
# una fila que no es de herramienta: no debe contar
db.execute("INSERT INTO part VALUES (?,?,?)", ("sess-aaaaaaaaaaaaaaaa", 9999, json.dumps({"type": "text", "text": "hola"}, separators=(",", ":"))))
db.commit()
PY
}

run_probe() { run bash "$REPO_ROOT/$SCRIPT" --command /sprint-status --output "$OUT" "$@"; }

report() { cat "$OUT"/se220-feasibility-*.md; }

cycle() { # n veces el ciclo read grep edit bash
  local n="$1" i; for ((i = 0; i < n; i++)); do printf 'read grep edit bash '; done
}

@test "FP-01: secuencia perfectamente predecible da GO con tasa 1.0" {
  mkdb $(cycle 10)
  run_probe --runs 20
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"decision": "GO"'
  echo "$output" | grep -q '"acceptance_rate": 1.0'
  report | grep -q '## Decision: GO'
}

@test "FP-02: secuencia impredecible da ABORT, no GO" {
  # ninguna transición se repite: sin ver el par antes, el predictor no puede acertar (0 %)
  mkdb a b c d e f g h i j k l m n o p q r s t u v w x y z
  run_probe --runs 20
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"decision": "ABORT"'
  [[ "$output" != *'"decision": "GO"'* ]]
}

@test "FP-03: tasa intermedia da DEFERRED" {
  # tras 'x' alternan y/z: acierta la mitad (10 de 20)
  mkdb x y x y x z x y x z x z x y x z x y x z x y x z
  run_probe --runs 20
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"acceptance_rate": 0.5'
  echo "$output" | grep -q '"decision": "DEFERRED"'
}

@test "FP-04: --runs limita las muestras evaluadas pero no el tamaño del dataset" {
  mkdb $(cycle 10)
  run_probe --runs 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"total_evaluated": 5'
  echo "$output" | grep -q '"total_dataset": 37'
}

@test "FP-05: --runs mayor que el dataset evalúa solo el dataset" {
  mkdb $(cycle 4)
  run_probe --runs 500
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"total_evaluated": 13'
  # cada muestra se evalúa con la tabla completa menos ella misma: una secuencia periódica acierta todo
  echo "$output" | grep -q '"correct": 13'
  echo "$output" | grep -q '"decision": "GO"'
}

@test "FP-06: empty or insufficient history gives DEFERRED with a reason, no rate and never GO" {
  mkdb read grep edit bash read grep
  run_probe --runs 20
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"decision": "DEFERRED"'
  echo "$output" | grep -q '"acceptance_rate": null'
  echo "$output" | grep -q 'Insufficient data: 3 samples'
  report | grep -q 'Insufficient historical data (3 samples'
}

@test "FP-07: missing database fails with ABORT and exit 1, no report" {
  rm -f "$FEASIBILITY_DB"
  run_probe --runs 20
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '"decision": "ABORT"'
  echo "$output" | grep -q 'DB not found'
  [ -z "$(ls "$OUT"/se220-feasibility-*.md 2>/dev/null)" ]
}

@test "FP-08: la ruta de la base usada es la configurada, no un literal sin expandir" {
  mkdb $(cycle 10)
  run_probe --runs 20
  [ "$status" -eq 0 ]
  [[ "$output" != *"DB not found"* ]]
  [[ "$output" != *'${'* ]]
}

@test "FP-09: el informe lleva el comando objetivo y los umbrales" {
  mkdb $(cycle 10)
  run_probe --runs 20
  report | grep -q '^## Target command: /sprint-status$'
  report | grep -q 'ABORT — pattern does not apply'
}

@test "FP-10: un comando con comillas y expansiones no se interpreta como código" {
  mkdb $(cycle 10)
  run bash "$REPO_ROOT/$SCRIPT" --command '/x"; import os; os.system("touch '"$TMPDIR"'/pwned"); "' --runs 20 --output "$OUT"
  [ ! -e "$TMPDIR/pwned" ]
  [ "$status" -eq 0 ]
  grep -q 'os.system' "$OUT"/se220-feasibility-*.md
}

@test "FP-11: invalid --runs (non numeric or zero) is rejected with exit 2 and no report" {
  mkdb $(cycle 10)
  run_probe --runs abc
  [ "$status" -eq 2 ]
  run_probe --runs 0
  [ "$status" -eq 2 ]
  [ -z "$(ls "$OUT"/se220-feasibility-*.md 2>/dev/null)" ]
}

@test "FP-12: no arg shows usage and fails with exit 2" {
  run bash "$REPO_ROOT/$SCRIPT" --output "$OUT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'feasibility-probe'
}

@test "FP-13: unknown arg fails with exit 2" {
  run bash "$REPO_ROOT/$SCRIPT" --command /x --bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'unknown arg'
}

@test "FP-14: null-ish rows (not a tool, or broken JSON) are skipped and do not count" {
  mkdb $(cycle 10)
  python3 - "$FEASIBILITY_DB" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("INSERT INTO part VALUES ('sess-aaaaaaaaaaaaaaaa', 5000, '{\"type\":\"tool\" roto')")
db.commit()
PY
  run_probe --runs 20
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"total_dataset": 37'
}

@test "FP-15: boundary 0.60 exact (3 of 5) is already GO" {
  mkdb a c c a b c b c c a c a b b
  run_probe --runs 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"correct": 3'
  echo "$output" | grep -q '"acceptance_rate": 0.6'
  echo "$output" | grep -q '"decision": "GO"'
}

@test "FP-16: boundary 0.40 exact (2 of 5) is DEFERRED, not ABORT" {
  mkdb c a a c b c c b b c a a c a
  run_probe --runs 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"correct": 2'
  echo "$output" | grep -q '"acceptance_rate": 0.4'
  echo "$output" | grep -q '"decision": "DEFERRED"'
}

@test "FP-17: zero hits when no pair was seen before (no evaluation leak)" {
  # 23 transiciones, todas distintas: con la tabla completa daría 100 % y GO
  mkdb a b c d e f g h i j k l m n o p q r s t u v w x y z
  run_probe --runs 20
  echo "$output" | grep -q '"correct": 0'
  echo "$output" | grep -q '"acceptance_rate": 0.0'
}

@test "FP-18: dos ejecuciones el mismo día sobrescriben el informe, no lo acumulan" {
  mkdb $(cycle 10)
  local d1 d2; d1="$(date +%Y%m%d)"
  run_probe --runs 20
  run_probe --runs 20
  d2="$(date +%Y%m%d)"
  [ "$d1" = "$d2" ] || skip "la ejecución cruzó la medianoche: el nombre del informe cambia"
  [ "$(ls "$OUT"/se220-feasibility-*.md | wc -l)" -eq 1 ]
  [ "$(report | grep -c '^## Decision')" -eq 1 ]
}

@test "FP-19: the script keeps strict mode so a failure is never swallowed" {
  grep -q '^set -uo pipefail' "$REPO_ROOT/$SCRIPT"
}

@test "FP-20: una fila de otro tipo que contiene un objeto tool anidado no es una llamada" {
  mkdb $(cycle 10)
  python3 - "$FEASIBILITY_DB" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("INSERT INTO part VALUES ('sess-aaaaaaaaaaaaaaaa', 5001, '{\"type\":\"step\",\"meta\":{\"type\":\"tool\",\"tool\":\"ghost\"}}')")
db.commit()
PY
  run_probe --runs 20
  echo "$output" | grep -q '"total_dataset": 37'
}

@test "FP-21: ruta relativa de la base (FEASIBILITY_DB) se resuelve contra el cwd" {
  mkdb $(cycle 10)
  cd "$TMPDIR"
  FEASIBILITY_DB="sessions.db" run_probe --runs 20
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"decision": "GO"'
}

@test "FP-22: ruta con ? # y % no altera la URI de SQLite" {
  local odd="$TMPDIR/we?ird#na%me.db"
  mkdb $(cycle 10)
  mv "$FEASIBILITY_DB" "$odd"
  FEASIBILITY_DB="$odd" run_probe --runs 20
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"decision": "GO"'
}

@test "FP-23: base corrupta da ABORT en JSON con exit 1, sin traceback ni informe" {
  head -c 4096 /dev/urandom > "$FEASIBILITY_DB"
  run_probe --runs 20
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '"decision": "ABORT"'
  [[ "$output" != *Traceback* ]]
  [ -z "$(ls "$OUT"/se220-feasibility-*.md 2>/dev/null)" ]
}

@test "FP-24: base SQLite vacía (sin tabla part) da ABORT en JSON con exit 1, no traceback" {
  python3 -c "import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute('CREATE TABLE otra (x)').connection.commit()" "$FEASIBILITY_DB"
  run_probe --runs 20
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '"decision": "ABORT"'
  [[ "$output" != *Traceback* ]]
}

@test "FP-25: el desempate del predictor es el orden de primera aparición, no el de reinserción" {
  # con empates, borrar y reinsertar la clave en el leave-one-out cambiaba el resultado (2 aciertos)
  mkdb a b c c b c c b a c b a a a
  run_probe --runs 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"correct": 0'
}
