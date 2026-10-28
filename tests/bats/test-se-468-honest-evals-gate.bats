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

@test "AC1: con el artefacto de pbi-decomposition vacío el gate no da verde (ejecutor honesto)" {
  put_artifact ""
  SAVIA_EVAL_EXECUTOR="$(honest_executor)" run bash "$RUNNER" --dataset pbi-decomposition --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"findings"' ]
  [ "$(field "$REPORT" pbi-decomposition threshold_pass)" = "false" ]
  run python3 "$DELTA" --check-report "$REPORT"
  [ "$status" -eq 1 ]
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

@test "S3: ejecutor que falla o devuelve basura da unknown unreadable, no una nota" {
  put_artifact "# pbi-decomposition skill"
  local exe="$BATS_TEST_TMPDIR/broken.sh"
  printf '#!/usr/bin/env bash\ncat >/dev/null\necho hola\n' > "$exe"; chmod +x "$exe"
  SAVIA_EVAL_EXECUTOR="$exe" run bash "$RUNNER" --dataset pbi-decomposition --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"unknown"' ]
  [[ "$(field "$REPORT" pbi-decomposition gaps)" == *'"reason": "unreadable"'* ]]
}

@test "D1: todos los motivos del informe están en el vocabulario del contrato SE-453" {
  run bash "$RUNNER" --mock --output "$REPORT"
  [ "$status" -eq 0 ]
  source "$REPO_ROOT/.claude/hooks/lib/gate-result.sh"
  run python3 -c "
import json, sys
allowed = set(sys.argv[2].split())
bad = [g for r in json.load(open(sys.argv[1])) for g in r['gaps'] if g['reason'] not in allowed]
assert not bad, bad" "$REPORT" "$_GATE_REASONS"
  [ "$status" -eq 0 ]
}

# Dataset de prueba NAME con baseline y N filas: fixture NAME BASE_SCORE [N]
fixture() {
  local name="$1" base="$2" n="${3:-3}" i
  : > "$SANDBOX/tests/evals/datasets/skills/$name.jsonl"
  python3 - "$SANDBOX" "$name" "$base" "$n" <<'PY'
import json, sys
root, name, base, n = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4])
rows = [{"id": f"r{i}", "input": "x"} for i in range(n)]
open(f"{root}/tests/evals/datasets/skills/{name}.jsonl", "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
open(f"{root}/tests/evals/baselines/{name}-baseline.json", "w").write(
    json.dumps([{"id": r["id"], "score": base} for r in rows]))
PY
}

declare_artifact() {  # declare_artifact NAME REL_PATH
  python3 - "$SANDBOX/tests/evals/datasets/artifacts.json" "$1" "$2" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d[sys.argv[2]] = sys.argv[3]
json.dump(d, open(p, "w"))
PY
}

run_live() {  # run_live NAME [EXECUTOR]
  SAVIA_EVAL_EXECUTOR="${2:-$(honest_executor)}" run bash "$RUNNER" --dataset "$1" --output "$REPORT"
}

@test "S3: dataset con baseline y sin artefacto declarado da not_executed en el artefacto, no no_baseline" {
  fixture fx-noart 0.5
  run_live fx-noart
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" fx-noart result)" = '"unknown"' ]
  [[ "$(field "$REPORT" fx-noart gaps)" == *'"check": "fx-noart/artifact", "reason": "not_executed"'* ]]
  [[ "$(field "$REPORT" fx-noart gaps)" != *no_baseline* ]]
}

@test "S3: artefacto declarado que no existe en disco da unreadable" {
  fixture fx-missing 0.5
  declare_artifact fx-missing ".claude/skills/nope/SKILL.md"
  run_live fx-missing
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" fx-missing result)" = '"unknown"' ]
  [[ "$(field "$REPORT" fx-missing gaps)" == *'"check": "fx-missing/artifact", "reason": "unreadable"'* ]]
}

@test "seguridad: un artefacto fuera de la raíz (../ o absoluto) no se ejecuta" {
  fixture fx-esc 0.5
  echo secreto > "$BATS_TEST_TMPDIR/fuera.md"
  declare_artifact fx-esc "../fuera.md"
  run_live fx-esc
  [ "$(field "$REPORT" fx-esc result)" = '"unknown"' ]
  [[ "$(field "$REPORT" fx-esc gaps)" == *'"reason": "unreadable"'* ]]
  declare_artifact fx-esc "$BATS_TEST_TMPDIR/fuera.md"
  run_live fx-esc
  [ "$(field "$REPORT" fx-esc result)" = '"unknown"' ]
  [[ "$(field "$REPORT" fx-esc gaps)" == *'"reason": "unreadable"'* ]]
}

@test "robustez: una línea de dataset inválida da unknown solo para ese dataset y el informe se escribe" {
  put_artifact "# skill"
  fixture fx-bad 0.5
  echo 'no es json' >> "$SANDBOX/tests/evals/datasets/skills/fx-bad.jsonl"
  mkdir -p "$SANDBOX/.claude/skills/fx"; echo x > "$SANDBOX/.claude/skills/fx/SKILL.md"
  declare_artifact fx-bad ".claude/skills/fx/SKILL.md"
  SAVIA_EVAL_EXECUTOR="$(honest_executor)" run bash "$RUNNER" --output "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(field "$REPORT" fx-bad result)" = '"unknown"' ]
  [[ "$(field "$REPORT" fx-bad gaps)" == *'fx-bad/dataset'* ]]
  [ "$(field "$REPORT" pbi-decomposition result)" = '"clean"' ]
}

@test "robustez: un baseline mal formado da unknown unreadable, sin traceback" {
  fixture fx-badbase 0.5
  echo '{"x": [' > "$SANDBOX/tests/evals/baselines/fx-badbase-baseline.json"
  run bash "$RUNNER" --mock --output "$REPORT"
  [ "$status" -eq 0 ]
  [[ "$output" != *Traceback* ]]
  [[ "$(field "$REPORT" fx-badbase gaps)" == *'fx-badbase/baseline'* ]]
}

@test "robustez: ids duplicados en el dataset no se promedian: unknown" {
  fixture fx-dup 0.5
  echo '{"id": "r0", "input": "otra vez"}' >> "$SANDBOX/tests/evals/datasets/skills/fx-dup.jsonl"
  mkdir -p "$SANDBOX/.claude/skills/fx"; echo x > "$SANDBOX/.claude/skills/fx/SKILL.md"
  declare_artifact fx-dup ".claude/skills/fx/SKILL.md"
  run_live fx-dup
  [ "$(field "$REPORT" fx-dup result)" = '"unknown"' ]
  [[ "$(field "$REPORT" fx-dup gaps)" == *'fx-dup/executor'* ]]
}

@test "sabotaje: ejecutor que discrimina con baseline bajo se evalúa (real contra saboteada)" {
  fixture fx-low 0.4
  mkdir -p "$SANDBOX/.claude/skills/fx"; echo x > "$SANDBOX/.claude/skills/fx/SKILL.md"
  declare_artifact fx-low ".claude/skills/fx/SKILL.md"
  local exe="$BATS_TEST_TMPDIR/mid.sh"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nif [[ -s "$SAVIA_EVAL_ARTIFACT" ]]; then echo 0.9; else echo 0.6; fi\n' > "$exe"
  chmod +x "$exe"
  run_live fx-low "$exe"
  [ "$(field "$REPORT" fx-low result)" = '"clean"' ]
  [ "$(field "$REPORT" fx-low sabotage_detected)" = "true" ]
}

@test "pares: si el ejecutor cubre menos ids que el baseline el dataset es unknown" {
  fixture fx-part 0.5 3
  python3 - "$SANDBOX/tests/evals/baselines/fx-part-baseline.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d.append({"id": "r-extra", "score": 0.5}); json.dump(d, open(p, "w"))
PY
  mkdir -p "$SANDBOX/.claude/skills/fx"; echo x > "$SANDBOX/.claude/skills/fx/SKILL.md"
  declare_artifact fx-part ".claude/skills/fx/SKILL.md"
  run_live fx-part
  [ "$(field "$REPORT" fx-part result)" = '"unknown"' ]
  [[ "$(field "$REPORT" fx-part gaps)" == *'"reason": "no_baseline"'* ]]
}

@test "check-report: forma inválida de gaps/result sale 2, no con traceback" {
  local f="$BATS_TEST_TMPDIR/r.json"
  echo '[{"dataset":"a","result":"unknown","gaps":[{"reason":"x"}]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]]
  echo '[{"dataset":"a","result":["unknown"],"gaps":[]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]]
  # el contrato exige al menos un hueco en un unknown: gaps null o vacío no es un informe válido
  echo '[{"dataset":"a","result":"unknown","gaps":null}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 2 ]
  echo '[{"dataset":"a","result":"unknown","gaps":[]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 2 ]
  echo '[{"dataset":"a","result":"clean","gaps":[]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 0 ]
}

@test "umbral: SAVIA_EVAL_DELTA_THRESHOLD no numérico sale 2 sin traceback; numérico no falla" {
  local f="$BATS_TEST_TMPDIR/r.json"
  echo '[{"dataset":"a","result":"clean","gaps":[]}]' > "$f"
  SAVIA_EVAL_DELTA_THRESHOLD=abc run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]]
  [[ "$output" == *SAVIA_EVAL_DELTA_THRESHOLD* ]]
  SAVIA_EVAL_DELTA_THRESHOLD=0.1 run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 0 ]
}

@test "workflow: la etiqueta y el delta del comentario se escapan o se fuerzan a número" {
  run grep -c 'esc(r.label' "$REPO_ROOT/.github/workflows/evals-ci.yaml"
  [ "$output" -ge 1 ]
  run grep -c 'Number.isFinite(d)' "$REPO_ROOT/.github/workflows/evals-ci.yaml"
  [ "$output" -ge 1 ]
}

@test "check-report: datasets con el mismo nombre no se colapsan y unknown emite ::warning::" {
  local f="$BATS_TEST_TMPDIR/r.json"
  echo '[{"dataset":"a","result":"clean","gaps":[]},{"dataset":"a","result":"findings","delta":-0.3,"gaps":[]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"delta=-0.3"* ]]
  echo '[{"dataset":"a","result":"unknown","gaps":[{"check":"a","reason":"not_executed"}]}]' > "$f"
  run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
}

@test "check-report: SAVIA_GATE_UNKNOWN=block hace fallar un informe con unknown" {
  local f="$BATS_TEST_TMPDIR/r.json"
  echo '[{"dataset":"a","result":"unknown","gaps":[{"check":"a","reason":"not_executed"}]}]' > "$f"
  SAVIA_GATE_UNKNOWN=block run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 1 ]
  SAVIA_GATE_UNKNOWN=off run python3 "$DELTA" --check-report "$f"
  [ "$status" -eq 0 ]
}

@test "workflow: el comentario escapa pipes y menciones de los nombres del repo" {
  command -v node >/dev/null || skip "node no disponible"
  local y="$REPO_ROOT/.github/workflows/evals-ci.yaml"
  grep -q 'esc(r.dataset)' "$y"
  line="$(grep -m1 'const esc = ' "$y")"
  run node -e "$line; process.stdout.write(esc('a|b @quien \`x\`'))"
  [ "$status" -eq 0 ]
  [[ "$output" == 'a\|b \@quien \`x\`' ]]
}
