#!/usr/bin/env bats
# tests/bats/test-se253-language-boundaries.bats — SE-253 Slice 7
#
# Tests de aceptacion de language boundaries y migracion test-workspace (AC-7.1 a AC-7.5)
# Ejecutar: bats tests/bats/test-se253-language-boundaries.bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    LANG_BOUNDS_DOC="$REPO_ROOT/docs/rules/domain/language-boundaries.md"
    TEST_WORKSPACE_PY="$REPO_ROOT/scripts/test_workspace.py"
    TEST_WORKSPACE_SH="$REPO_ROOT/scripts/test-workspace.sh"
    LB_CHECK="$REPO_ROOT/scripts/language-boundary-check.sh"
    PYTEST_SUITE="$REPO_ROOT/tests/test_workspace_migration.py"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-7.1: language-boundaries.md existe en docs/rules/domain/
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-7.1a: language-boundaries.md existe" {
    [ -f "$LANG_BOUNDS_DOC" ]
}

@test "AC-7.1b: language-boundaries.md tiene context_tier L2" {
    grep -q "context_tier: L2" "$LANG_BOUNDS_DOC"
}

@test "AC-7.1c: language-boundaries.md referencia SE-253" {
    grep -q "SE-253" "$LANG_BOUNDS_DOC"
}

@test "AC-7.1d: language-boundaries.md define heuristica >=5 usos jq" {
    grep -q ">=5" "$LANG_BOUNDS_DOC"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-7.2: test_workspace.py existe y produce exit 0 en workspace actual
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-7.2a: test_workspace.py existe" {
    [ -f "$TEST_WORKSPACE_PY" ]
}

@test "AC-7.2b: test_workspace.py tiene shebang python3" {
    head -1 "$TEST_WORKSPACE_PY" | grep -q "python3"
}

@test "AC-7.2c: test_workspace.py produce exit 0 en mock mode" {
    # CI: skip if full workspace check requires tools not installed in BATS runner
    # (Claude CLI, Node.js not always available in the BATS test container)
    skip_reason=""
    command -v node >/dev/null 2>&1 || skip_reason="node not installed"
    [[ -n "$skip_reason" ]] && skip "$skip_reason"
    run python3 "$TEST_WORKSPACE_PY" --mock --only capacity
    [ "$status" -eq 0 ]
}

@test "AC-7.2c-smoke: test_workspace.py arranca sin crash" {
    # Minimal smoke: script imports and shows usage without crashing
    run python3 "$TEST_WORKSPACE_PY" --help
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "AC-7.2d: test_workspace.py acepta --only capacity" {
    python3 "$TEST_WORKSPACE_PY" --mock --only capacity > /dev/null 2>&1
}

@test "AC-7.2e: test_workspace.py acepta --only structure" {
    python3 "$TEST_WORKSPACE_PY" --mock --only structure > /dev/null 2>&1
}

@test "AC-7.2f: test_workspace.py produce exit 2 con argumento desconocido" {
    run python3 "$TEST_WORKSPACE_PY" --opcion-invalida-xyz
    [ "$status" -eq 2 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-7.3: El job CI invoca test-workspace.sh (wrapper preserva interfaz)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-7.3a: test-workspace.sh existe" {
    [ -f "$TEST_WORKSPACE_SH" ]
}

@test "AC-7.3b: test-workspace.sh es ejecutable" {
    [ -x "$TEST_WORKSPACE_SH" ]
}

@test "AC-7.3c: ci.yml referencia test-workspace.sh" {
    grep -q "test-workspace.sh" "$REPO_ROOT/.github/workflows/ci.yml"
}

@test "AC-7.3d: test-workspace.sh wrapper delega a test_workspace.py" {
    grep -q "test_workspace.py" "$TEST_WORKSPACE_SH"
}

@test "AC-7.3e: wrapper tiene <=15 lineas" {
    LINE_COUNT=$(wc -l < "$TEST_WORKSPACE_SH")
    [ "$LINE_COUNT" -le 15 ]
}

@test "AC-7.3f: wrapper invocado con --mock produce exit 0" {
    bash "$TEST_WORKSPACE_SH" --mock > /dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-7.4: pytest tests/test_workspace_migration.py pasa (>=10 tests)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-7.4a: tests/test_workspace_migration.py existe" {
    [ -f "$PYTEST_SUITE" ]
}

@test "AC-7.4b: pytest test_workspace_migration.py pasa" {
    run python3 -m pytest "$PYTEST_SUITE" --no-header -q 2>&1
    [ "$status" -eq 0 ]
}

@test "AC-7.4c: pytest ejecuta al menos 10 tests" {
    OUTPUT=$(python3 -m pytest "$PYTEST_SUITE" --no-header -q 2>&1)
    # Extrae el numero de tests pasados: "22 passed" o "10 passed"
    COUNT=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | grep -oE '^[0-9]+' || echo "0")
    [ "$COUNT" -ge 10 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-7.5: language-boundary-check.sh existe y es ejecutable
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-7.5a: language-boundary-check.sh existe" {
    [ -f "$LB_CHECK" ]
}

@test "AC-7.5b: language-boundary-check.sh es ejecutable" {
    [ -x "$LB_CHECK" ]
}

@test "AC-7.5c: language-boundary-check.sh --warn con fichero de 5 jqs emite WARN" {
    # Crear fichero temporal con 5 usos de jq
    TMPFILE=$(mktemp /tmp/test_jq_script_XXXXXX.sh)
    printf '#!/usr/bin/env bash\njq . a.json\njq . b.json\njq . c.json\njq . d.json\njq . e.json\n' > "$TMPFILE"
    run bash "$LB_CHECK" --warn "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "AC-7.5d: language-boundary-check.sh --check con fichero de 5 jqs retorna exit 1" {
    TMPFILE=$(mktemp /tmp/test_jq_script_XXXXXX.sh)
    printf '#!/usr/bin/env bash\njq . a.json\njq . b.json\njq . c.json\njq . d.json\njq . e.json\n' > "$TMPFILE"
    run bash "$LB_CHECK" --check "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 1 ]
}

@test "AC-7.5e: language-boundary-check.sh --warn con fichero de 4 jqs no emite WARN" {
    TMPFILE=$(mktemp /tmp/test_jq_script_XXXXXX.sh)
    printf '#!/usr/bin/env bash\njq . a.json\njq . b.json\njq . c.json\njq . d.json\n' > "$TMPFILE"
    run bash "$LB_CHECK" --warn "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "AC-7.5f: language-boundary-check.sh respeta excepcion setup.sh" {
    TMPFILE=$(mktemp -t setup.sh.XXXXXX)
    # Renombrar para que sea "setup.sh"
    SETUP_FILE="$(dirname "$TMPFILE")/setup.sh"
    printf '#!/usr/bin/env bash\njq . a.json\njq . b.json\njq . c.json\njq . d.json\njq . e.json\n' > "$SETUP_FILE"
    run bash "$LB_CHECK" --check "$SETUP_FILE"
    rm -f "$SETUP_FILE" "$TMPFILE"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# S03q (SE-376): comportamiento del checker (usos, no líneas; solo scripts nuevos)
# ─────────────────────────────────────────────────────────────────────────────

lb_file() {  # lb_file <nombre> <contenido> → ruta
    local f="$BATS_TEST_TMPDIR/$1"
    printf '%s\n' "$2" > "$f"
    echo "$f"
}

@test "S03q: cuenta usos de jq en pipes, no líneas (6 usos en 2 líneas → WARN)" {
    f="$(lb_file pipes.sh 'jq . a | jq .x | jq .y
jq . b | jq .z | jq .w')"
    run bash "$LB_CHECK" --check "$f"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tiene 6 usos de jq"* ]]
}

@test "S03q: boundary — 5 usos en una línea avisa, 4 no" {
    f="$(lb_file cinco.sh 'jq a | jq b | jq c | jq d | jq e')"
    run bash "$LB_CHECK" --check "$f"
    [ "$status" -eq 1 ]
    f="$(lb_file cuatro.sh 'jq a | jq b | jq c | jq d')"
    run bash "$LB_CHECK" --check "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}

@test "S03q: palabras que contienen jq no cuentan (negativo)" {
    f="$(lb_file palabras.sh 'myjq jqx jq_tool xjqx ajq')"
    run bash "$LB_CHECK" --check "$f"
    [ "$status" -eq 0 ]
}

@test "S03q: fichero sin jq no rompe con set -e/pipefail (empty)" {
    f="$(lb_file vacio.sh 'echo hola')"
    run bash "$LB_CHECK" --check "$f" "$(lb_file otro.sh 'jq a | jq b | jq c | jq d | jq e')"
    [ "$status" -eq 1 ]
    [[ "$output" == *"otro.sh tiene 5 usos"* ]]
}

@test "S03q: excepción install-*.sh (no avisa aunque tenga 5 usos)" {
    f="$(lb_file install-x.sh 'jq a | jq b | jq c | jq d | jq e')"
    run bash "$LB_CHECK" --check "$f"
    [ "$status" -eq 0 ]
}

@test "S03q: opción desconocida → exit 2 (invalid)" {
    run bash "$LB_CHECK" --nope
    [ "$status" -eq 2 ]
}

lb_repo() {
    R="$BATS_TEST_TMPDIR/repo"; mkdir -p "$R/sub"
    git -C "$R" init -q
    git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

@test "S03q: staged — script nuevo con 5 usos avisa, también desde un subdirectorio" {
    lb_repo
    printf 'jq a | jq b | jq c | jq d | jq e\n' > "$R/sub/nuevo.sh"
    git -C "$R" add sub/nuevo.sh
    run bash -c 'cd "$1/sub" && bash "$2" --check' _ "$R" "$LB_CHECK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sub/nuevo.sh tiene 5 usos"* ]]
}

lb_viejo_sin_jq() {  # script versionado sin jq: al renombrarlo con poco cambio git ve R<100
    lb_repo
    printf 'echo uno\necho dos\necho tres\necho cuatro\necho cinco\necho seis\n' > "$R/viejo.sh"
    git -C "$R" add viejo.sh
    git -C "$R" -c user.email=t@t -c user.name=t commit -q -m viejo
}

@test "S03q: staged — renombrado con código nuevo de jq avisa (R<100)" {
    lb_viejo_sin_jq
    git -C "$R" mv viejo.sh renombrado.sh
    printf 'jq a | jq b | jq c | jq d | jq e\n' >> "$R/renombrado.sh"
    git -C "$R" add renombrado.sh
    run bash -c 'cd "$1" && bash "$2" --check' _ "$R" "$LB_CHECK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"renombrado.sh tiene 5 usos"* ]]
}

@test "S03q: staged — renombrado puro (R100) no avisa (negativo)" {
    lb_repo
    printf 'jq a | jq b | jq c | jq d | jq e\n' > "$R/viejo.sh"
    git -C "$R" add viejo.sh
    git -C "$R" -c user.email=t@t -c user.name=t commit -q -m viejo
    git -C "$R" mv viejo.sh movido.sh
    run bash -c 'cd "$1" && bash "$2" --check' _ "$R" "$LB_CHECK"
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}

@test "S03q: staged — script existente modificado no avisa (la regla es para código nuevo)" {
    lb_repo
    printf 'echo viejo\n' > "$R/viejo.sh"
    git -C "$R" add viejo.sh
    git -C "$R" -c user.email=t@t -c user.name=t commit -q -m viejo
    printf 'jq a\njq b\njq c\njq d\njq e\n' >> "$R/viejo.sh"
    git -C "$R" add viejo.sh
    run bash -c 'cd "$1" && bash "$2" --check' _ "$R" "$LB_CHECK"
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}
