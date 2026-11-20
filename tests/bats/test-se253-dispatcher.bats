#!/usr/bin/env bats
# tests/bats/test-se253-dispatcher.bats — SE-253 Slice 4
#
# Tests de aceptacion del dispatcher de hooks (AC-4.1 a AC-4.5)
# Ejecutar: bats tests/bats/test-se253-dispatcher.bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    DISPATCH_PRE="$REPO_ROOT/hooks/dispatchers/dispatch-pretooluse.sh"
    DISPATCH_POST="$REPO_ROOT/hooks/dispatchers/dispatch-posttooluse.sh"
    PRE_TSV="$REPO_ROOT/hooks/routing-pretooluse.tsv"
    POST_TSV="$REPO_ROOT/hooks/routing-posttooluse.tsv"
    BENCHMARK="$REPO_ROOT/scripts/benchmark-hook-dispatch.sh"

    # Directorio temporal para hooks mock
    MOCK_DIR="$(mktemp -d)"
    export MOCK_DIR

    # TSV temporal que apunta al hook mock
    MOCK_TSV="$(mktemp)"
    export MOCK_TSV
}

teardown() {
    rm -rf "$MOCK_DIR" "$MOCK_TSV"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-4.1: Dispatcher existe y es ejecutable
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-4.1a: dispatch-pretooluse.sh existe" {
    [ -f "$DISPATCH_PRE" ]
}

@test "AC-4.1b: dispatch-pretooluse.sh es ejecutable" {
    [ -x "$DISPATCH_PRE" ]
}

@test "AC-4.1c: dispatch-posttooluse.sh existe" {
    [ -f "$DISPATCH_POST" ]
}

@test "AC-4.1d: dispatch-posttooluse.sh es ejecutable" {
    [ -x "$DISPATCH_POST" ]
}

@test "AC-4.1e: routing-pretooluse.tsv tiene al menos 20 entradas" {
    count=$(grep -cv $'^\t*#\|^[[:space:]]*$' "$PRE_TSV" 2>/dev/null || echo 0)
    [ "$count" -ge 20 ]
}

@test "AC-4.1f: routing-posttooluse.tsv tiene al menos 15 entradas" {
    count=$(grep -cv $'^\t*#\|^[[:space:]]*$' "$POST_TSV" 2>/dev/null || echo 0)
    [ "$count" -ge 15 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-4.2: Dispatcher con tool=Edit sale con 0 cuando hooks no bloquean
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-4.2a: dispatcher-pre con routing vacio bloquea (SE-510: tabla vacía = fallo cerrado)" {
    # TSV vacío (solo comentario): una tabla sin filas es una tabla rota o truncada → exit 2
    printf '# empty routing\n# filas=0\n' > "$MOCK_TSV"

    # Creamos un dispatcher temporal que usa nuestro mock TSV
    local tmp_dispatcher
    tmp_dispatcher="$(mktemp)"
    cat "$DISPATCH_PRE" | sed "s|ROUTING=.*|ROUTING=\"$MOCK_TSV\"|" > "$tmp_dispatcher"
    chmod +x "$tmp_dispatcher"

    run bash "$tmp_dispatcher" <<< '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.sh"}}'
    exit_code=$status
    [[ "$output" == *"sin filas"* ]]
    rm -f "$tmp_dispatcher"
    [ "$exit_code" -eq 2 ]
}

@test "AC-4.2b: dispatcher-pre con hook que devuelve 0 sale con exit 0" {
    # Hook mock que siempre retorna 0
    local mock_hook="$MOCK_DIR/hook-ok.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$mock_hook"
    chmod +x "$mock_hook"

    # TSV apuntando al hook mock (matcher=Edit, bloqueante=yes)
    printf 'Edit\t%s\tspawn\tyes\tHook mock OK\n# filas=1\n' "${mock_hook#"$MOCK_DIR"/}" > "$MOCK_TSV"

    # Dispatcher temporal
    local tmp_dispatcher
    tmp_dispatcher="$(mktemp)"
    sed -e "s|ROUTING=.*|ROUTING=\"$MOCK_TSV\"|" -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$MOCK_DIR\"|" "$DISPATCH_PRE" > "$tmp_dispatcher"
    chmod +x "$tmp_dispatcher"

    printf '{"tool_name":"Edit","tool_input":{}}' | bash "$tmp_dispatcher"
    exit_code=$?
    rm -f "$tmp_dispatcher"
    [ "$exit_code" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-4.3: benchmark-hook-dispatch.sh genera output con "baseline" y "dispatcher"
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-4.3a: benchmark script existe y es ejecutable" {
    [ -x "$BENCHMARK" ]
}

@test "AC-4.3b: benchmark genera linea con 'baseline'" {
    run bash "$BENCHMARK" --fast
    [[ "$output" == *"baseline"* ]]
}

@test "AC-4.3c: benchmark genera linea con 'dispatcher'" {
    run bash "$BENCHMARK" --fast
    [[ "$output" == *"dispatcher"* ]]
}

@test "AC-4.3d: benchmark reporta spawns totales" {
    run bash "$BENCHMARK" --fast
    # Debe mostrar que el dispatcher usa 2 spawns
    [[ "$output" == *"2"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-4.4: routing TSV tiene las 5 columnas requeridas
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-4.4a: routing-pretooluse.tsv tiene 5 columnas tab-separadas" {
    # Toma primera línea de datos (no comentario)
    first_data=$(grep -v $'^\t*#\|^[[:space:]]*$' "$PRE_TSV" | head -1)
    col_count=$(printf '%s' "$first_data" | awk -F'\t' '{print NF}')
    [ "$col_count" -eq 5 ]
}

@test "AC-4.4b: routing-posttooluse.tsv tiene 5 columnas tab-separadas" {
    first_data=$(grep -v $'^\t*#\|^[[:space:]]*$' "$POST_TSV" | head -1)
    col_count=$(printf '%s' "$first_data" | awk -F'\t' '{print NF}')
    [ "$col_count" -eq 5 ]
}

@test "AC-4.4c: columna 3 (mode) contiene solo 'spawn' o 'source'" {
    invalid=$(grep -v $'^\t*#\|^[[:space:]]*$' "$PRE_TSV" \
        | awk -F'\t' '$3 != "spawn" && $3 != "source" {print NR": "$3}')
    [ -z "$invalid" ]
}

@test "AC-4.4d: columna 4 (blocking) contiene solo 'yes' o 'no'" {
    invalid=$(grep -v $'^\t*#\|^[[:space:]]*$' "$PRE_TSV" \
        | awk -F'\t' '$4 != "yes" && $4 != "no" {print NR": "$4}')
    [ -z "$invalid" ]
}

@test "AC-4.4e: columna 5 (descripcion) no esta vacia" {
    empty_desc=$(grep -v $'^\t*#\|^[[:space:]]*$' "$PRE_TSV" \
        | awk -F'\t' 'length($5) == 0 {print NR}')
    [ -z "$empty_desc" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-4.5: Dispatcher propaga exit 2 cuando hook bloqueante devuelve 2
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-4.5a: dispatcher propaga exit 2 de hook bloqueante" {
    # Hook mock que siempre devuelve 2
    local mock_hook="$MOCK_DIR/hook-block.sh"
    printf '#!/usr/bin/env bash\necho "[BLOCK] hook blocked" >&2\nexit 2\n' > "$mock_hook"
    chmod +x "$mock_hook"

    # TSV: matcher=Edit, hook=mock_block, mode=spawn, blocking=yes
    printf 'Edit\t%s\tspawn\tyes\tHook mock que bloquea\n# filas=1\n' "${mock_hook#"$MOCK_DIR"/}" > "$MOCK_TSV"

    # Dispatcher temporal con rutas absolutas
    local tmp_dispatcher
    tmp_dispatcher="$(mktemp)"
    # La tabla lleva rutas relativas a la raíz (SE-510: absolutas o con `..` bloquean).
    sed \
        -e "s|ROUTING=.*|ROUTING=\"$MOCK_TSV\"|" \
        -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$MOCK_DIR\"|" \
        "$DISPATCH_PRE" > "$tmp_dispatcher"
    chmod +x "$tmp_dispatcher"

    run bash "$tmp_dispatcher" <<< '{"tool_name":"Edit","tool_input":{}}'
    local exit_code=$status
    rm -f "$tmp_dispatcher"

    [ "$exit_code" -eq 2 ]
    [[ "$output" == *"hook blocked"* ]]   # el 2 viene del hook, no de una validación de la tabla
}

@test "AC-4.5b: dispatcher NO propaga exit 2 de hook no-bloqueante" {
    # Hook mock que devuelve 2 pero está marcado como no-bloqueante
    local mock_hook="$MOCK_DIR/hook-warn.sh"
    printf '#!/usr/bin/env bash\nexit 2\n' > "$mock_hook"
    chmod +x "$mock_hook"

    # TSV: blocking=no
    printf 'Edit\t%s\tspawn\tno\tHook mock no-bloqueante\n# filas=1\n' "${mock_hook#"$MOCK_DIR"/}" > "$MOCK_TSV"

    local tmp_dispatcher
    tmp_dispatcher="$(mktemp)"
    # La tabla lleva rutas relativas a la raíz (SE-510: absolutas o con `..` bloquean).
    sed \
        -e "s|ROUTING=.*|ROUTING=\"$MOCK_TSV\"|" \
        -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$MOCK_DIR\"|" \
        "$DISPATCH_PRE" > "$tmp_dispatcher"
    chmod +x "$tmp_dispatcher"

    run bash "$tmp_dispatcher" <<< '{"tool_name":"Edit","tool_input":{}}'
    local exit_code=$status
    rm -f "$tmp_dispatcher"

    # exit 2 no bloqueante → el dispatcher debe salir con 0
    [ "$exit_code" -eq 0 ]
}

@test "AC-4.5c: dispatcher-post NUNCA propaga exit 2 (PostToolUse no bloquea)" {
    # Hook mock que devuelve 2 marcado como bloqueante en PostToolUse
    local mock_hook="$MOCK_DIR/hook-post-block.sh"
    printf '#!/usr/bin/env bash\nexit 2\n' > "$mock_hook"
    chmod +x "$mock_hook"

    printf 'Task\t%s\tspawn\tyes\tHook post mock bloqueante\n' "$mock_hook" > "$MOCK_TSV"

    local tmp_dispatcher
    tmp_dispatcher="$(mktemp)"
    sed \
        -e "s|ROUTING=.*|ROUTING=\"$MOCK_TSV\"|" \
        -e 's|script_path="\$REPO_ROOT/\$script"|script_path="$script"|' \
        "$DISPATCH_POST" > "$tmp_dispatcher"
    chmod +x "$tmp_dispatcher"

    run bash "$tmp_dispatcher" <<< '{"tool_name":"Task","tool_input":{}}'
    local exit_code=$status
    rm -f "$tmp_dispatcher"

    # PostToolUse siempre exit 0
    [ "$exit_code" -eq 0 ]
}

@test "AC-4.5d: dispatcher ejecuta hooks en orden del TSV" {
    # Dos hooks que escriben a un fichero de orden
    ORDER_FILE="$MOCK_DIR/order.txt"
    local hook1="$MOCK_DIR/hook-first.sh"
    local hook2="$MOCK_DIR/hook-second.sh"
    printf '#!/usr/bin/env bash\necho "first" >> "%s"\n' "$ORDER_FILE" > "$hook1"
    printf '#!/usr/bin/env bash\necho "second" >> "%s"\n' "$ORDER_FILE" > "$hook2"
    chmod +x "$hook1" "$hook2"

    printf 'Edit\t%s\tspawn\tno\tPrimero\nEdit\t%s\tspawn\tno\tSegundo\n# filas=2\n' \
        "${hook1#"$MOCK_DIR"/}" "${hook2#"$MOCK_DIR"/}" > "$MOCK_TSV"

    local tmp_dispatcher
    tmp_dispatcher="$(mktemp)"
    # La tabla lleva rutas relativas a la raíz (SE-510: absolutas o con `..` bloquean).
    sed \
        -e "s|ROUTING=.*|ROUTING=\"$MOCK_TSV\"|" \
        -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$MOCK_DIR\"|" \
        "$DISPATCH_PRE" > "$tmp_dispatcher"
    chmod +x "$tmp_dispatcher"

    bash "$tmp_dispatcher" <<< '{"tool_name":"Edit"}' || true
    rm -f "$tmp_dispatcher"

    run cat "$ORDER_FILE"
    [ "${lines[0]}" = "first" ]
    [ "${lines[1]}" = "second" ]
}
