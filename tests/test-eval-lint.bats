#!/usr/bin/env bats
# tests/test-eval-lint.bats — SE-316: linter de golden sets de tribunales.
# Ref: docs/propuestas/SE-316-eval-lint-golden-sets.md (AC-S1, AC-S2)

SCRIPT="scripts/eval-lint.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export EVAL_TMP="${BATS_TEST_TMPDIR}/evals"
  mkdir -p "$EVAL_TMP/code-review-court"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# Genera un golden set válido con N casos bien formados.
make_golden() {
  local file="$1" n="$2"
  : > "$file"
  local i=1
  while [[ $i -le $n ]]; do
    cat >> "$file" <<EOF
{"id":"case-$i","input":"input $i","expected":"finding","should_trigger":["security-judge","correctness-judge","spec-judge","architecture-judge","cognitive-judge"],"should_not_trigger":[{"case":"a-$i","route_to":"agent:correctness-judge"},{"case":"b-$i","route_to":"agent:spec-judge"},{"case":"c-$i","route_to":"none"},{"case":"d-$i","route_to":"external:vendor"}],"capabilities":[{"name":"cap-$i","must_include":"$i"}]}
EOF
    i=$((i+1))
  done
}

# ── Estructura ────────────────────────────────────────────────────────────────

@test "script existe y es ejecutable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

@test "usa set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "pasa bash -n" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "sin args devuelve usage (exit 2)" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

# ── AC-S1: Linter operativo ──────────────────────────────────────────────────

@test "AC-S1.1: golden set real de code-review-court pasa" {
  run bash "$SCRIPT" --check tests/evals/code-review-court
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "AC-S1.1: los 3 golden sets reales pasan (check global)" {
  run bash "$SCRIPT" --check tests/evals
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "AC-S1.2: route_to a skill inexistente produce FAIL" {
  make_golden "$EVAL_TMP/code-review-court/cases.jsonl" 5
  sed -i 's/"route_to":"agent:correctness-judge"/"route_to":"skill:inexistente-xyz"/' "$EVAL_TMP/code-review-court/cases.jsonl"
  run bash "$SCRIPT" --check "$EVAL_TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"route_to"*"inexistente-xyz"* ]]
}

@test "AC-S1.3: caso sin should_not_trigger produce FAIL" {
  : > "$EVAL_TMP/code-review-court/cases.jsonl"
  cat > "$EVAL_TMP/code-review-court/cases.jsonl" <<'EOF'
{"id":"no-neg","input":"x","expected":"clean","should_trigger":["security-judge","correctness-judge","spec-judge","architecture-judge","cognitive-judge"]}
EOF
  run bash "$SCRIPT" --check "$EVAL_TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"should_not_trigger vacío"* ]]
}

@test "golden set bien formado pasa" {
  make_golden "$EVAL_TMP/code-review-court/cases.jsonl" 5
  run bash "$SCRIPT" --check "$EVAL_TMP"
  [ "$status" -eq 0 ]
}

@test "JSONL mal formado produce FAIL" {
  echo '{"id":"broken","input":' > "$EVAL_TMP/code-review-court/cases.jsonl"
  run bash "$SCRIPT" --check "$EVAL_TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"JSONL inválido"* ]]
}

@test "route_to valida agentes reales del catálogo" {
  make_golden "$EVAL_TMP/code-review-court/cases.jsonl" 5
  sed -i 's/"route_to":"none"/"route_to":"agent:code-reviewer"/' "$EVAL_TMP/code-review-court/cases.jsonl"
  run bash "$SCRIPT" --check "$EVAL_TMP"
  [ "$status" -eq 0 ]
}

@test "route_to valida skills reales de RESOLVER.md" {
  make_golden "$EVAL_TMP/code-review-court/cases.jsonl" 5
  sed -i 's/"route_to":"none"/"route_to":"skill:sprint-management"/' "$EVAL_TMP/code-review-court/cases.jsonl"
  run bash "$SCRIPT" --check "$EVAL_TMP"
  [ "$status" -eq 0 ]
}

@test "evals dir inexistente devuelve exit 2" {
  run bash "$SCRIPT" --check /nonexistent/evals
  [ "$status" -eq 2 ]
}

@test "directorio sin golden sets produce FAIL" {
  mkdir -p "$EVAL_TMP/empty"
  run bash "$SCRIPT" --check "$EVAL_TMP/empty"
  [ "$status" -eq 1 ]
}

# ── AC-S2: Schema ────────────────────────────────────────────────────────────

@test "AC-S2.1: config/eval-case.schema.json existe y es JSON válido" {
  run jq -e . config/eval-case.schema.json
  [ "$status" -eq 0 ]
}

@test "AC-S2.2: linter reporta caso y campo de cada violación" {
  make_golden "$EVAL_TMP/code-review-court/cases.jsonl" 5
  sed -i 's/"route_to":"agent:spec-judge"/"route_to":"agent:ghost-judge"/' "$EVAL_TMP/code-review-court/cases.jsonl"
  run bash "$SCRIPT" --check "$EVAL_TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"case-1"* ]]
  [[ "$output" == *"route_to"* ]]
}

@test "--json emite objeto JSON con verdict FAIL en violación" {
  make_golden "$EVAL_TMP/code-review-court/cases.jsonl" 5
  sed -i 's/"route_to":"agent:spec-judge"/"route_to":"agent:ghost-judge"/' "$EVAL_TMP/code-review-court/cases.jsonl"
  run bash "$SCRIPT" --check "$EVAL_TMP" --json
  [ "$status" -eq 1 ]
  run jq -e '.verdict == "FAIL" and (.violations | length > 0)' <<< "$output"
  [ "$status" -eq 0 ]
}

# ── Cobertura ────────────────────────────────────────────────────────────────

@test "cobertura: eval-lint referencia SE-316" {
  run grep -c 'SE-316' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "cobertura: eval-lint referencia SE-274" {
  run grep -c 'SE-274' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "aislamiento: linter no modifica golden sets" {
  make_golden "$EVAL_TMP/code-review-court/cases.jsonl" 5
  local before after
  before=$(md5sum "$EVAL_TMP/code-review-court/cases.jsonl" | awk '{print $1}')
  bash "$SCRIPT" --check "$EVAL_TMP" >/dev/null 2>&1
  after=$(md5sum "$EVAL_TMP/code-review-court/cases.jsonl" | awk '{print $1}')
  [[ "$before" == "$after" ]]
}

# ── Comportamiento: cada regla del linter, con su caso válido y su caso roto ─────────

CASES() { echo "$EVAL_TMP/code-review-court/cases.jsonl"; }
# lint [args]: ejecuta el linter sobre el directorio temporal
lint() { bash "$SCRIPT" --check "$EVAL_TMP" "$@"; }

@test "PASS imprime el resumen con numero de sets, casos y cero violaciones" {
  make_golden "$(CASES)" 6
  run lint
  [ "$status" -eq 0 ]
  [ "$output" = "PASS: 1 golden set(s), 6 casos, 0 violaciones" ]
}

@test "--json de un set valido: verdict PASS, files, cases y violations vacio" {
  make_golden "$(CASES)" 5
  run lint --json
  [ "$status" -eq 0 ]
  run jq -e '.verdict=="PASS" and .files==1 and .cases==5 and (.violations|length)==0' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "--json FAIL cuenta ficheros y casos y lista cada violacion como cadena" {
  make_golden "$(CASES)" 5
  sed -i '2s/"route_to":"none"/"route_to":"skill:no-existe-abc"/' "$(CASES)"
  run lint --json
  [ "$status" -eq 1 ]
  run jq -e '.verdict=="FAIL" and .files==1 and .cases==5 and (.violations|length)==1 and (.violations[0]|test("case-2.*no-existe-abc"))' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "FAIL cuenta las violaciones y las lista con guion" {
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"skill:uno-no"/; 3s/"route_to":"none"/"route_to":"skill:dos-no"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL: 2 violaciones en 5 casos"* ]]
  [[ "$output" == *"  - tests"* || "$output" == *"  - "* ]]
  [[ "$output" == *"uno-no"* && "$output" == *"dos-no"* ]]
}

@test "una violacion se localiza como fichero:linea[id]" {
  make_golden "$(CASES)" 5
  sed -i '4s/"route_to":"none"/"route_to":"skill:zzz-no"/' "$(CASES)"
  run lint
  [[ "$output" == *"code-review-court/cases.jsonl:4[case-4]: route_to 'skill:zzz-no' no resuelve"* ]]
}

@test "caso sin id se reporta como falta campo id" {
  make_golden "$(CASES)" 5
  sed -i '2s/"id":"case-2",//' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"cases.jsonl:2: falta campo 'id'"* ]]
}

@test "caso sin input se reporta" {
  make_golden "$(CASES)" 5
  sed -i '3s/"input":"input 3",//' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"[case-3]: falta 'input'"* ]]
}

@test "caso sin expected se reporta" {
  make_golden "$(CASES)" 5
  sed -i '3s/"expected":"finding",//' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"[case-3]: falta 'expected'"* ]]
}

@test "should_trigger vacio o ausente se reporta" {
  make_golden "$(CASES)" 5
  sed -i '1s/"should_trigger":\[[^]]*\]/"should_trigger":[]/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"[case-1]: should_trigger vacío"* ]]
}

@test "should_not_trigger vacio se reporta" {
  make_golden "$(CASES)" 5
  sed -i '5s/"should_not_trigger":\[.*\],"capabilities"/"should_not_trigger":[],"capabilities"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"[case-5]: should_not_trigger vacío"* ]]
}

@test "una entrada de should_not_trigger sin route_to se reporta con su indice" {
  make_golden "$(CASES)" 5
  sed -i '1s/{"case":"c-1","route_to":"none"}/{"case":"c-1"}/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"[case-1]: should_not_trigger[2] sin route_to"* ]]
}

@test "none, external: y agent: del catalogo son destinos validos" {
  make_golden "$(CASES)" 5
  run lint
  [ "$status" -eq 0 ]
}

@test "un destino sin prefijo conocido no resuelve" {
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"correctness-judge"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"route_to 'correctness-judge' no resuelve"* ]]
}

@test "un agente inexistente no resuelve aunque exista una skill con ese nombre" {
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"agent:sprint-management"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent:sprint-management"* ]]
}

@test "una skill del RESOLVER pasa pero un agente con prefijo skill no" {
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"skill:code-reviewer"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
}

@test "cobertura: 4 casos son insuficientes (should_trigger < 5)" {
  make_golden "$(CASES)" 4
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"cobertura should_trigger=4 < 5"* ]]
  [[ "$output" != *"route_to=4 < 4"* ]]
}

@test "cobertura: 5 casos cumplen los minimos exactos" {
  make_golden "$(CASES)" 5
  run lint
  [ "$status" -eq 0 ]
}

@test "cobertura: sin capabilities se reporta" {
  make_golden "$(CASES)" 5
  sed -i 's/,"capabilities":\[[^]]*\]//' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"cobertura capabilities=0 < 1"* ]]
}

@test "cobertura: pocas lineas con route_to se reporta" {
  make_golden "$(CASES)" 5
  sed -i 's/"route_to"/"ruta"/g' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"cobertura route_to=0 < 4"* ]]
}

@test "las lineas en blanco no cuentan como casos" {
  make_golden "$(CASES)" 5
  printf '\n\n' >> "$(CASES)"
  run lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 casos"* ]]
}

@test "una ultima linea sin salto de linea tambien se valida" {
  make_golden "$(CASES)" 5
  printf '%s' '{"id":"sin-nl","input":"x"' >> "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"JSONL inválido"* ]]
}

@test "descubre cases.jsonl y *.golden.jsonl en cualquier subcarpeta y suma los casos" {
  make_golden "$(CASES)" 5
  mkdir -p "$EVAL_TMP/otro/profundo"
  make_golden "$EVAL_TMP/otro/profundo/extra.golden.jsonl" 5
  make_golden "$EVAL_TMP/otro/ignorado.jsonl" 1
  run lint
  [ "$status" -eq 0 ]
  [ "$output" = "PASS: 2 golden set(s), 10 casos, 0 violaciones" ]
}

@test "un directorio sin golden sets falla con mensaje y, en --json, con el recuento a cero" {
  mkdir -p "$EVAL_TMP/vacio"
  run bash "$SCRIPT" --check "$EVAL_TMP/vacio"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: no golden sets encontrados"* ]]
  run bash "$SCRIPT" --check "$EVAL_TMP/vacio" --json
  [ "$status" -eq 1 ]
  run jq -e '.verdict=="FAIL" and .files==0 and .cases==0' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "ruta relativa se resuelve contra la raiz del repo y la absoluta se usa tal cual" {
  run bash "$SCRIPT" --check tests/evals/code-review-court
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --check "$PWD/tests/evals/code-review-court"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --check tests/evals/no-existe-este
  [ "$status" -eq 2 ]
  [[ "$output" == *"evals dir no existe"* ]]
}

@test "--check sin directorio usa tests/evals y acepta --json justo despues" {
  run bash "$SCRIPT" --check --json
  [ "$status" -eq 0 ]
  run jq -e '.verdict=="PASS" and .files>=1' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "--json sin --check es un error de uso" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 2 ]
}

@test "argumento desconocido: exit 2 con el nombre en stderr" {
  run bash "$SCRIPT" --check "$EVAL_TMP" --frob
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg '--frob'"* ]]
}

@test "-h imprime el uso y sale con 0" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "un fallo en un set no oculta las violaciones de otro" {
  make_golden "$(CASES)" 5
  mkdir -p "$EVAL_TMP/b"
  make_golden "$EVAL_TMP/b/cases.jsonl" 5
  sed -i '1s/"route_to":"none"/"route_to":"skill:malo-b"/' "$EVAL_TMP/b/cases.jsonl"
  sed -i '2s/"route_to":"none"/"route_to":"skill:malo-a"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"malo-a"* && "$output" == *"malo-b"* ]]
}

@test "un identificador parcial no resuelve: el nombre debe coincidir entero" {
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"agent:correctness"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"route_to 'agent:correctness' no resuelve"* ]]
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"skill:adversarial"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"route_to 'skill:adversarial' no resuelve"* ]]
}

@test "una skill del RESOLVER no es un agente y un agente no es una skill" {
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"agent:adversarial-security"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"skill:architect"/' "$(CASES)"
  run lint
  [ "$status" -eq 1 ]
  make_golden "$(CASES)" 5
  sed -i '1s/"route_to":"none"/"route_to":"skill:adversarial-security"/; 2s/"route_to":"none"/"route_to":"agent:architect"/' "$(CASES)"
  run lint
  [ "$status" -eq 0 ]
}

@test "cobertura: tres lineas con route_to son insuficientes, cuatro bastan" {
  make_golden "$(CASES)" 5
  sed -i '4,5s/"route_to"/"ruta"/g' "$(CASES)"
  run lint
  [[ "$output" == *"cobertura route_to=3 < 4"* ]]
  make_golden "$(CASES)" 5
  sed -i '5s/"route_to"/"ruta"/g' "$(CASES)"
  run lint
  [[ "$output" != *"cobertura route_to"* ]]
}
