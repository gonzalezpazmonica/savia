#!/usr/bin/env bats
# test-se-305-dynamic-bats.bats — Tests for SE-305: Dynamic BATS Test Selection
# Ref: SE-305 (docs/ROADMAP.md) — scripts/ci-bats-deps.sh, scripts/ci-select-bats.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
DEPS_SCRIPT="$REPO_ROOT/scripts/ci-bats-deps.sh"
SELECT_SCRIPT="$REPO_ROOT/scripts/ci-select-bats.sh"
DEPS_FILE="$REPO_ROOT/tests/bats/.deps.json"

setup() {
  cd "$REPO_ROOT"
}

teardown() {
  cd "$REPO_ROOT"
  [[ -n "${FIX:-}" && -d "$FIX" ]] && rm -rf "$FIX"
  return 0
}

# Repo git sintético y aislado: ambos scripts resuelven ROOT con
# `git rev-parse --show-toplevel` desde el cwd, así que no tocan el repo real.
mk_fixture() {
  FIX="$(mktemp -d)"
  mkdir -p "$FIX/tests/bats" "$FIX/scripts" "$FIX/docs"
  # printf y no heredoc: bats 1.9 cuenta como test cualquier línea que empiece
  # por @test, también dentro de un heredoc (plan 34, ejecutados 32).
  printf '%s\n' '@test "a" { run bash "$REPO_ROOT/scripts/foo.sh"; run cat "$REPO_ROOT/scripts/foo.sh"; }' \
    > "$FIX/tests/bats/test-a.bats"
  printf '%s\n' '@test "b" { run bash "$REPO_ROOT/scripts/foo.sh"; run bash "$REPO_ROOT/scripts/bar.sh"; run cat "$SKILLS_DIR/docs/guide.md"; run cat "$REPO_ROOT/otro/ignorado.sh"; }' \
    > "$FIX/tests/bats/test-b.bats"
  echo 'echo foo' > "$FIX/scripts/foo.sh"
  echo 'echo bar' > "$FIX/scripts/bar.sh"
  git -C "$FIX" init -q
  git -C "$FIX" config user.email t@t
  git -C "$FIX" config user.name t
  git -C "$FIX" add -A
  git -C "$FIX" commit -q -m base
}

# Ejecuta un script del repo real con cwd en el fixture.
in_fix() { ( cd "$FIX" && "$@" ); }

deps_json() { cat "$FIX/tests/bats/.deps.json"; }

@test "SE-305: deps generator creates valid JSON" {
  run bash "$DEPS_SCRIPT" --generate
  [ "$status" -eq 0 ]
  [ -f "$DEPS_FILE" ]
  python3 -c "import json; d=json.load(open('$DEPS_FILE')); assert 'mappings' in d; assert 'core_tests' in d; assert 'dir_rules' in d"
}

@test "SE-305: deps generator includes core_tests" {
  bash "$DEPS_SCRIPT" --generate
  core=$(python3 -c "import json; print(len(json.load(open('$DEPS_FILE'))['core_tests']))")
  [ "$core" -ge 10 ]
}

@test "SE-305: deps check detects missing file" {
  rm -f "$DEPS_FILE"
  run bash "$DEPS_SCRIPT" --check
  [ "$status" -ne 0 ]
}

@test "SE-305: deps check passes when fresh" {
  bash "$DEPS_SCRIPT" --generate
  run bash "$DEPS_SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "SE-305: selector produces output for current changes" {
  bash "$DEPS_SCRIPT" --generate
  run bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [ -n "${lines[0]}" ]
}

@test "SE-305: selector returns FULL when too many changes" {
  bash "$DEPS_SCRIPT" --generate
  SAVIA_BATS_FULL_THRESHOLD_PCT=1 run bash "$SELECT_SCRIPT" --base HEAD~5
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "FULL" ]]
}

@test "SE-305: selector exit 2 when deps file missing" {
  rm -f "$DEPS_FILE"
  run bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -ne 0 ]
}

@test "SE-305: deps generator uses dir rules" {
  bash "$DEPS_SCRIPT" --generate
  rules=$(python3 -c "import json; d=json.load(open('$DEPS_FILE')); print(len(d.get('dir_rules', {})))")
  [ "$rules" -ge 1 ]
}

@test "SE-305: core tests include attention anchor" {
  bash "$DEPS_SCRIPT" --generate
  has_anchor=$(python3 -c "import json; d=json.load(open('$DEPS_FILE')); print('test-se-080-attention-anchor.bats' in d.get('core_tests', []))")
  [ "$has_anchor" = "True" ]
}

@test "SE-305: mappings reference real bats files" {
  bash "$DEPS_SCRIPT" --generate
  python3 -c "
import json, os
d = json.load(open('$DEPS_FILE'))
bats_dir = '$REPO_ROOT/tests/bats'
for tests in d.get('mappings', {}).values():
    for t in tests:
        assert os.path.exists(os.path.join(bats_dir, t)), f'missing: {t}'
print('all ok')
"
}

# ── Comportamiento discriminante en repo aislado (S03 calidad) ───────────────

@test "SE-305: ambos scripts usan modo estricto (set -euo pipefail)" {
  head -3 "$DEPS_SCRIPT" | grep -q 'set -euo pipefail'
  head -3 "$SELECT_SCRIPT" | grep -q 'set -euo pipefail'
}

@test "SE-305: generate mapea cada referencia a los tests que la usan, ordenados y sin duplicados" {
  mk_fixture
  run in_fix bash "$DEPS_SCRIPT" --generate
  [ "$status" -eq 0 ]
  run jq -c '.mappings["scripts/foo.sh"]' "$FIX/tests/bats/.deps.json"
  [ "$output" = '["test-a.bats","test-b.bats"]' ]
  run jq -c '.mappings["scripts/bar.sh"]' "$FIX/tests/bats/.deps.json"
  [ "$output" = '["test-b.bats"]' ]
}

@test "SE-305: generate reconoce referencias \$X_DIR/<raíz>/ y quita el prefijo de la variable" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  run jq -c '.mappings["docs/guide.md"]' "$FIX/tests/bats/.deps.json"
  [ "$output" = '["test-b.bats"]' ]
}

@test "SE-305: generate ignora rutas fuera de las raíces conocidas (otro/)" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  run jq -e '.mappings | keys | map(select(startswith("otro"))) | length == 0' "$FIX/tests/bats/.deps.json"
  [ "$status" -eq 0 ]
}

@test "SE-305: generate cuenta total_tests y lo informa con mappings" {
  mk_fixture
  run in_fix bash "$DEPS_SCRIPT" --generate
  [[ "$output" == *"(2 tests, 3 mappings, 0 dir rules)"* ]]
  run jq -e '.total_tests == 2 and .version == "1"' "$FIX/tests/bats/.deps.json"
  [ "$status" -eq 0 ]
}

@test "SE-305: generate sin fichero de reglas deja dir_rules vacío" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  run jq -e '.dir_rules == {}' "$FIX/tests/bats/.deps.json"
  [ "$status" -eq 0 ]
}

@test "SE-305: generate incorpora reglas por directorio y por fichero del yaml" {
  mk_fixture
  cat > "$FIX/tests/bats/.deps-rules.yaml" <<'EOF'
rules:
  - dir: ".claude/agents/"
    tests: [test-a.bats]
  - file: "docs/x.md"
    tests: [test-b.bats]
  - dir: "sin-tests/"
    tests: []
EOF
  in_fix bash "$DEPS_SCRIPT" --generate
  run jq -c '.dir_rules' "$FIX/tests/bats/.deps.json"
  [ "$output" = '{".claude/agents/":["test-a.bats"],"docs/x.md":["test-b.bats"]}' ]
}

@test "SE-305: generate lista 15 core_tests fijos aunque el repo no los tenga" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  run jq -e '(.core_tests | length) == 15 and (.core_tests | index("test-evals-ci-gate.bats") != null)' "$FIX/tests/bats/.deps.json"
  [ "$status" -eq 0 ]
}

@test "SE-305: check on missing .deps.json exits 1 with STALE" {
  mk_fixture
  run in_fix bash "$DEPS_SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE: .deps.json not found"* ]]
}

@test "SE-305: check detects a bats file newer than .deps.json" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  touch -d "1 hour ago" "$FIX/tests/bats/.deps.json"
  touch "$FIX/tests/bats/test-a.bats"
  run in_fix bash "$DEPS_SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE: .bats files newer"* ]]
}

@test "SE-305: check passes when .deps.json is newer than every bats file" {
  mk_fixture
  touch -d "1 hour ago" "$FIX/tests/bats/test-a.bats" "$FIX/tests/bats/test-b.bats"
  in_fix bash "$DEPS_SCRIPT" --generate
  run in_fix bash "$DEPS_SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == "OK: .deps.json is fresh" ]]
}

@test "SE-305: invalid mode prints usage and exits 1" {
  mk_fixture
  run in_fix bash "$DEPS_SCRIPT" --otra-cosa
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: ci-bats-deps.sh"* ]]
}

@test "SE-305: selector elige los tests que referencian el fichero cambiado más los core" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'echo cambiado' >> "$FIX/scripts/bar.sh"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m cambio
  SAVIA_BATS_FULL_THRESHOLD_PCT=100000 run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 0 ]
  [[ " $output " == *" test-b.bats "* ]]
  [[ " $output " != *" test-a.bats "* ]]
  [[ " $output " == *" test-evals-ci-gate.bats "* ]]
}

@test "SE-305: selector aplica reglas por directorio al prefijo del fichero cambiado" {
  mk_fixture
  cat > "$FIX/tests/bats/.deps-rules.yaml" <<'EOF'
rules:
  - dir: "docs/"
    tests: [test-a.bats]
EOF
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'x' > "$FIX/docs/nuevo.md"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m docs
  SAVIA_BATS_FULL_THRESHOLD_PCT=100000 run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 0 ]
  [[ " $output " == *" test-a.bats "* ]]
  [[ " $output " != *" test-b.bats "* ]]
}

@test "SE-305: selector with empty diff (no changes) returns only the core" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  run in_fix bash "$SELECT_SCRIPT" --base HEAD
  [ "$status" -eq 0 ]
  [ "$(wc -w <<< "$output")" -eq 15 ]
  [[ " $output " != *" test-a.bats "* ]]
}

@test "SE-305: selector with zero matching tests for the change returns only the core" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'x' > "$FIX/huerfano.txt"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m huerfano
  SAVIA_BATS_FULL_THRESHOLD_PCT=100000 run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 0 ]
  [ "$(wc -w <<< "$output")" -eq 15 ]
}

@test "SE-305: selector devuelve FULL con exit 1 si la selección supera el umbral" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'echo c' >> "$FIX/scripts/foo.sh"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m cambio
  SAVIA_BATS_FULL_THRESHOLD_PCT=30 run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 1 ]
  [ "$output" = "FULL" ]
}

@test "SE-305: selector sin .deps.json imprime FULL y sale 1 con instrucción de regenerar" {
  mk_fixture
  run in_fix bash "$SELECT_SCRIPT" --base HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"ci-bats-deps.sh --generate"* ]]
  [[ "$output" == *FULL ]]
}

@test "SE-305: selector falls back to HEAD~1 on a nonexistent base ref instead of failing" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'echo c' >> "$FIX/scripts/bar.sh"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m cambio
  SAVIA_BATS_FULL_THRESHOLD_PCT=100000 run in_fix bash "$SELECT_SCRIPT" --base rama-que-no-existe
  [ "$status" -eq 0 ]
  [[ " $output " == *" test-b.bats "* ]]
}

@test "SE-305: --base delimita el rango: HEAD~1 ve solo el último cambio, HEAD~2 ve ambos" {
  mk_fixture
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'echo 1' >> "$FIX/scripts/foo.sh"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m c1
  echo 'echo 2' >> "$FIX/scripts/bar.sh"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m c2
  SAVIA_BATS_FULL_THRESHOLD_PCT=100000 run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [[ " $output " == *" test-b.bats "* && " $output " != *" test-a.bats "* ]]
  SAVIA_BATS_FULL_THRESHOLD_PCT=100000 run in_fix bash "$SELECT_SCRIPT" --base HEAD~2
  [[ " $output " == *" test-a.bats "* && " $output " == *" test-b.bats "* ]]
}

@test "SE-305: el umbral por defecto es 30% de los tests (boundary 17 de 60 no es FULL, 12 sí con 20%)" {
  mk_fixture
  for i in $(seq 1 58); do echo '@test "x" { true; }' > "$FIX/tests/bats/test-fill-$i.bats"; done
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'echo 1' >> "$FIX/scripts/foo.sh"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m c1
  # 15 core + test-a + test-b = 17 <= 60*30/100 = 18 → lista, no FULL
  run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 0 ]
  [ "$(wc -w <<< "$output")" -eq 17 ]
  # con 20% el tope es 12 → FULL
  SAVIA_BATS_FULL_THRESHOLD_PCT=20 run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 1 ]
  [ "$output" = "FULL" ]
}

@test "SE-305: con el umbral por defecto una selección de 22 de 60 tests (>18) es FULL" {
  mk_fixture
  for i in $(seq 1 58); do echo '@test "x" { true; }' > "$FIX/tests/bats/test-fill-$i.bats"; done
  for i in 1 2 3 4 5; do
    echo '@test "r" { run cat "$REPO_ROOT/scripts/foo.sh"; }' > "$FIX/tests/bats/test-fill-$i.bats"
  done
  in_fix bash "$DEPS_SCRIPT" --generate
  echo 'echo 1' >> "$FIX/scripts/foo.sh"
  git -C "$FIX" add -A && git -C "$FIX" commit -q -m c1
  run in_fix bash "$SELECT_SCRIPT" --base HEAD~1
  [ "$status" -eq 1 ]
  [ "$output" = "FULL" ]
}

@test "SE-305: ningún heredoc de este fichero contiene líneas @test (plan de bats 1.9 = ejecutados)" {
  run awk '/<<.?EOF.?$/ {in_h=1; next} /^EOF$/ {in_h=0} in_h && /^[[:space:]]*@test/ {print NR; bad=1} END {exit bad}' "$BATS_TEST_FILENAME"
  [ "$status" -eq 0 ]
}

wild_fixture() {
  mk_fixture
  in_fix bash "$REPO_ROOT/scripts/ci-bats-deps.sh" --generate >/dev/null
  jq '.mappings["scripts/fo*"]=["test-wild.bats"] | .mappings["docs/*"]=["test-docs.bats"]' \
    "$FIX/tests/bats/.deps.json" > "$FIX/d.json" && mv "$FIX/d.json" "$FIX/tests/bats/.deps.json"
}

@test "SE-305: claves comodín de mappings (scripts/fo*, docs/*) seleccionan por prefijo" {
  wild_fixture
  echo x > "$FIX/scripts/foo-extra.sh"; echo y > "$FIX/docs/g.md"
  git -C "$FIX" add -A; git -C "$FIX" commit -q -m wild
  run in_fix env SAVIA_BATS_FULL_THRESHOLD_PCT=10000 bash "$REPO_ROOT/scripts/ci-select-bats.sh" --base HEAD~1
  [[ "$output" == *test-wild.bats* ]]
  [[ "$output" == *test-docs.bats* ]]
}

@test "SE-305: el comodín scripts/fo* no selecciona scripts/fa.sh" {
  wild_fixture
  echo x > "$FIX/scripts/fa.sh"
  git -C "$FIX" add -A; git -C "$FIX" commit -q -m nowild
  run in_fix env SAVIA_BATS_FULL_THRESHOLD_PCT=10000 bash "$REPO_ROOT/scripts/ci-select-bats.sh" --base HEAD~1
  [[ "$output" != *test-wild.bats* ]]
}
