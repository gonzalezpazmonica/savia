#!/usr/bin/env bats
# tests/bats/test-se-468-honest-evals-gate.bats — SE-468: el gate de evals debe poder fallar.
#
# Reproduce el hallazgo de la spec: un sandbox con solo el runner, el script de delta, los datasets
# y los baselines (sin ninguna skill, agente ni hook) daba PASS. Con el gate honesto ese sandbox da
# `unknown`, nunca un verde.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  SANDBOX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$SANDBOX/scripts" "$SANDBOX/tests/evals"
  cp "$REPO_ROOT/scripts/evals-runner.sh" "$REPO_ROOT/scripts/evals-paired-delta.py" "$SANDBOX/scripts/"
  cp -r "$REPO_ROOT/tests/evals/datasets" "$REPO_ROOT/tests/evals/baselines" "$SANDBOX/tests/evals/"
  RUNNER="$SANDBOX/scripts/evals-runner.sh"
  DELTA="$SANDBOX/scripts/evals-paired-delta.py"
  REPORT="$BATS_TEST_TMPDIR/report.json"
  unset SAVIA_EVAL_EXECUTOR
}

# Lee un campo del dataset NAME en el informe: field REPORT NAME KEY
field() {
  python3 -c "
import json, sys
rows = {r['dataset']: r for r in json.load(open(sys.argv[1]))}
v = rows[sys.argv[2]].get(sys.argv[3])
print(json.dumps(v))" "$1" "$2" "$3"
}

# Deja el artefacto de pbi-decomposition en el sandbox con el contenido dado.
put_artifact() {
  mkdir -p "$SANDBOX/.claude/skills/pbi-decomposition"
  printf '%s' "$1" > "$SANDBOX/.claude/skills/pbi-decomposition/SKILL.md"
}

# Ejecutor de prueba honesto: puntúa 0 si el artefacto está vacío y 0.9 si tiene contenido.
honest_executor() {
  local exe="$BATS_TEST_TMPDIR/honest.sh"
  cat > "$exe" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
if [[ -s "$SAVIA_EVAL_ARTIFACT" ]]; then echo 0.90; else echo 0.00; fi
SH
  chmod +x "$exe"; echo "$exe"
}

# Ejecutor vacuo: ignora el artefacto y devuelve siempre la misma nota.
vacuous_executor() {
  local exe="$BATS_TEST_TMPDIR/vacuous.sh"
  printf '#!/usr/bin/env bash\ncat >/dev/null\necho 0.90\n' > "$exe"
  chmod +x "$exe"; echo "$exe"
}

@test "AC1: sin skills/agentes/hooks el gate en mock no da PASS (hallazgo reproducido)" {
  [ ! -d "$SANDBOX/.claude" ]
  run bash "$RUNNER" --mock --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition threshold_pass)" != "true" ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"unknown"' ]
  run python3 "$DELTA" --check-report "$REPORT"
  [[ "$output" != *"within threshold"* ]]
  [[ "$output" == *"UNKNOWN"* ]]
}

@test "AC1: con el artefacto de pbi-decomposition vacío el gate no da PASS" {
  put_artifact ""
  run bash "$RUNNER" --mock --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"unknown"' ]
  [ "$(field "$REPORT" pbi-decomposition threshold_pass)" = "null" ]
}

@test "S1: mock no ejecuta el artefacto: gap not_executed y sin nota inventada" {
  run bash "$RUNNER" --mock --output "$REPORT"
  [ "$status" -eq 0 ]
  [[ "$(field "$REPORT" pbi-decomposition gaps)" == *'"reason": "not_executed"'* ]]
  [ "$(field "$REPORT" pbi-decomposition current_score)" = "null" ]
}

@test "AC2: modo vivo sin ejecutor sale con código distinto de 0 y nombra la variable" {
  run bash "$RUNNER" --output "$REPORT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SAVIA_EVAL_EXECUTOR"* ]]
  [ ! -s "$REPORT" ]
}

@test "AC3: un dataset sin baseline da unknown con no_baseline, nunca threshold_pass true" {
  run bash "$RUNNER" --mock --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" privacy-shield result)" = '"unknown"' ]
  [[ "$(field "$REPORT" privacy-shield gaps)" == *'"reason": "no_baseline"'* ]]
  [ "$(field "$REPORT" privacy-shield threshold_pass)" != "true" ]
}

@test "AC4: el JSON del comentario lleva resultado y etiqueta «no evaluado» por dataset" {
  run bash "$RUNNER" --mock --output "$REPORT"
  [ "$status" -eq 0 ]
  run python3 -c "
import json, sys
rows = json.load(open(sys.argv[1]))
assert rows, 'informe vacío'
for r in rows:
    assert r['result'] in ('clean', 'findings', 'unknown'), r
    if r['result'] == 'unknown':
        assert r['label'] == 'no evaluado', r
        assert r['gaps'], r
" "$REPORT"
  [ "$status" -eq 0 ]
  grep -q "r.label" "$REPO_ROOT/.github/workflows/evals-ci.yaml"
}

@test "check-report: findings sale 1, unknown sale 0 sin decir PASS, clean dice PASS" {
  local f="$BATS_TEST_TMPDIR/r.json"
  echo '[{"dataset":"a","result":"findings","delta":-0.2,"gaps":[]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DEGRADATION"* ]]
  echo '[{"dataset":"a","result":"unknown","gaps":[{"check":"a","reason":"not_executed"}]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" != *"PASS"* ]]
  echo '[{"dataset":"a","result":"clean","gaps":[]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "check-report: informe ilegible o con resultado desconocido no pasa" {
  local f="$BATS_TEST_TMPDIR/r.json"
  echo 'no json' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 2 ]
  echo '[{"dataset":"a","threshold_pass":true}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 2 ]
}

@test "S3: ejecutor honesto con artefacto real detecta el sabotaje y evalúa (clean)" {
  put_artifact "# pbi-decomposition skill"
  SAVIA_EVAL_EXECUTOR="$(honest_executor)" run bash "$RUNNER" --dataset pbi-decomposition --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"clean"' ]
  [ "$(field "$REPORT" pbi-decomposition sabotage_detected)" = "true" ]
}

@test "S3: ejecutor honesto con artefacto vacío da findings" {
  put_artifact ""
  SAVIA_EVAL_EXECUTOR="$(honest_executor)" run bash "$RUNNER" --dataset pbi-decomposition --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"findings"' ]
  [ "$(field "$REPORT" pbi-decomposition threshold_pass)" = "false" ]
}

@test "S3: ejecutor vacuo que ignora el artefacto no puede declarar el dataset evaluado" {
  put_artifact "# pbi-decomposition skill"
  SAVIA_EVAL_EXECUTOR="$(vacuous_executor)" run bash "$RUNNER" --dataset pbi-decomposition --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"unknown"' ]
  [[ "$(field "$REPORT" pbi-decomposition gaps)" == *'pbi-decomposition/sabotage'* ]]
  [ "$(field "$REPORT" pbi-decomposition threshold_pass)" != "true" ]
}

@test "S3: sin artefacto declarado el modo vivo no evalúa el dataset" {
  SAVIA_EVAL_EXECUTOR="$(honest_executor)" run bash "$RUNNER" --dataset privacy-shield --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" privacy-shield result)" = '"unknown"' ]
}

@test "S3: ejecutor que falla o devuelve basura da unknown unreadable, no una nota" {
  put_artifact "# pbi-decomposition skill"
  local exe="$BATS_TEST_TMPDIR/broken.sh"
  printf '#!/usr/bin/env bash\ncat >/dev/null\necho hola\n' > "$exe"; chmod +x "$exe"
  SAVIA_EVAL_EXECUTOR="$exe" run bash "$RUNNER" --dataset pbi-decomposition --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"unknown"' ]
  [[ "$(field "$REPORT" pbi-decomposition gaps)" == *'"reason": "unreadable"'* ]]
}
