#!/usr/bin/env bats
# test-sonora-tests.bats — SE-537: los tests de Sonora corren en el CI raíz
# Ref: scripts/sonora-tests.sh, scripts/lib/sonora_weights_skip.py,
#      scripts/sonora-tests-weights.txt, .github/workflows/sonora-tests.yml

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/sonora-tests.sh"
PLUGIN_DIR="$REPO_ROOT/scripts/lib"
WEIGHTS="$REPO_ROOT/scripts/sonora-tests-weights.txt"
WORKFLOW="$REPO_ROOT/.github/workflows/sonora-tests.yml"
APP="$REPO_ROOT/projects/savia-sonora/app"

setup() {
  TMP="$(mktemp -d)"
  # Python con pytest: el del entorno de Sonora si existe; si no, se saltan
  # solo los casos que ejecutan el plugin (los estáticos corren siempre).
  PY="${SONORA_PYTHON:-${SONORA_VENV:-$HOME/.cache/savia-sonora-tests/venv312}/bin/python}"
}

teardown() {
  rm -rf "$TMP"
}

need_pytest() {
  [ -x "$PY" ] && "$PY" -c 'import pytest' 2>/dev/null || skip "sin pytest en $PY (ejecuta scripts/sonora-tests.sh backend una vez)"
}

mk_suite() {
  mkdir -p "$TMP/suite"
  cat > "$TMP/suite/test_demo.py" <<'EOF'
def test_needs_weights():
    raise AssertionError("no debería ejecutarse")

def test_plain():
    assert True
EOF
}

@test "SE-537 script: existe, es bash estricto y acepta backend|frontend|all" {
  [ -f "$SCRIPT" ]
  head -1 "$SCRIPT" | grep -q 'bash'
  grep -q 'set -euo pipefail' "$SCRIPT"
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"backend"* && "$output" == *"frontend"* ]]
}

@test "SE-537 script: modo desconocido falla con código 2" {
  run bash "$SCRIPT" lo-que-sea
  [ "$status" -eq 2 ]
}

@test "SE-537 script: instala solo desde lockfiles (uv --frozen, pnpm --frozen-lockfile) y sin descargas de modelos" {
  grep -q 'uv sync --frozen' "$SCRIPT"
  grep -q -- '--frozen-lockfile' "$SCRIPT"
  grep -q 'HF_HUB_OFFLINE=1' "$SCRIPT"
  # toda invocación de uv sync lleva --frozen
  ! grep -E 'uv sync' "$SCRIPT" | grep -vq -- '--frozen'
  # ya no se ignora el fichero entero: se salta test a test con motivo
  ! grep -q -- '--ignore=src-pyloid/tests/test_transcription.py' "$SCRIPT"
}

@test "SE-537 script: python 3.12 y pnpm fijados a versión exacta" {
  grep -Eq 'SONORA_PYTHON_VERSION:-3\.12' "$SCRIPT"
  grep -Eq 'pnpm@[0-9]+\.[0-9]+\.[0-9]+' "$SCRIPT"
}

@test "SE-537 lista de pesos: cada entrada tiene nodeid y motivo, y existe en la suite" {
  [ -f "$WEIGHTS" ]
  n=0
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    nodeid="${line%% | *}"
    reason="${line#* | }"
    [ "$nodeid" != "$line" ]
    [ -n "$reason" ]
    file="${nodeid%%::*}"
    func="${nodeid##*::}"
    [ -f "$APP/$file" ]
    grep -q "def $func(" "$APP/$file"
    n=$((n + 1))
  done < "$WEIGHTS"
  [ "$n" -ge 1 ]
}

@test "SE-537 plugin: salta lo listado con su motivo y ejecuta el resto" {
  need_pytest
  mk_suite
  printf '# comentario\ntest_demo.py::test_needs_weights | carga whisper tiny\n' > "$TMP/w.txt"
  cd "$TMP/suite"
  run env PYTHONPATH="$PLUGIN_DIR" SONORA_WEIGHTS_SKIP_FILE="$TMP/w.txt" \
    "$PY" -m pytest -q -rs -p sonora_weights_skip -p no:cacheprovider .
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 passed, 1 skipped"* ]]
  [[ "$output" == *"necesita pesos de modelo: carga whisper tiny"* ]]
}

@test "SE-537 plugin: falla cerrado si la lista nombra un test que no existe" {
  need_pytest
  mk_suite
  printf 'test_demo.py::test_fantasma | lo que sea\n' > "$TMP/w.txt"
  cd "$TMP/suite"
  run env PYTHONPATH="$PLUGIN_DIR" SONORA_WEIGHTS_SKIP_FILE="$TMP/w.txt" \
    "$PY" -m pytest -q -p sonora_weights_skip -p no:cacheprovider .
  [ "$status" -ne 0 ]
  [[ "$output" == *"test_fantasma"* ]]
}

@test "SE-537 plugin: falla cerrado si falta el fichero de la lista" {
  need_pytest
  mk_suite
  cd "$TMP/suite"
  run env PYTHONPATH="$PLUGIN_DIR" SONORA_WEIGHTS_SKIP_FILE="$TMP/no-existe.txt" \
    "$PY" -m pytest -q -p sonora_weights_skip -p no:cacheprovider .
  [ "$status" -ne 0 ]
}

@test "SE-537 plugin: SONORA_WITH_WEIGHTS=1 no salta nada" {
  need_pytest
  mk_suite
  printf 'test_demo.py::test_needs_weights | carga whisper tiny\n' > "$TMP/w.txt"
  cd "$TMP/suite"
  run env PYTHONPATH="$PLUGIN_DIR" SONORA_WEIGHTS_SKIP_FILE="$TMP/w.txt" SONORA_WITH_WEIGHTS=1 \
    "$PY" -m pytest -q -p sonora_weights_skip -p no:cacheprovider .
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 failed, 1 passed"* ]]
}

@test "SE-537 workflow: dos jobs, acciones fijadas por SHA y llama al script" {
  [ -f "$WORKFLOW" ]
  grep -q 'sonora-tests.sh backend' "$WORKFLOW"
  grep -q 'sonora-tests.sh frontend' "$WORKFLOW"
  run grep -E '^\s*-?\s*uses:' "$WORKFLOW"
  [ "$status" -eq 0 ]
  while IFS= read -r l; do
    [[ "$l" =~ @[0-9a-f]{40} ]] || { echo "sin SHA: $l"; return 1; }
  done <<< "$output"
  grep -q 'permissions:' "$WORKFLOW"
}

@test "SE-537 uv.lock: la raíz del lock coincide con el nombre de pyproject" {
  name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$APP/pyproject.toml" | head -1)"
  [ -n "$name" ]
  grep -A2 "^name = \"$name\"" "$APP/uv.lock" | grep -q 'source = { virtual = "." }'
}
