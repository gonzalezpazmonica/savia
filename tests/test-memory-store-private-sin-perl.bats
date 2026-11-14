#!/usr/bin/env bats
# SE-529 S5 — ruta de redactar privados cuando NO hay perl (mutante R06 de la auditoría independiente
# del 2026-11-14). Sin perl no se puede garantizar la redacción: una marca <private> descarta toda la
# entrada; sin marca, el texto se conserva byte a byte. La ausencia de perl se simula sombreando
# `command -v perl` con una función; el resto del script es el real.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/memory-store.sh"

# sin_perl <fichero de entrada>: ejecuta redact_private con perl «ausente» y vuelca la salida.
sin_perl() {
    bash -c '
        source "$1"
        command() { if [[ "${1:-}" == "-v" && "${2:-}" == "perl" ]]; then return 1; fi; builtin command "$@"; }
        ! command -v perl >/dev/null || { echo "la simulación de perl ausente no funciona" >&2; exit 9; }
        redact_private < "$2"' _ "$SCRIPT" "$1"
}

@test "R06 contraste: con perl disponible se usa la ruta de perl y se conserva el texto público" {
    command -v perl >/dev/null || skip "sin perl en este runner: el contraste solo aplica con perl"
    printf 'a <private>S1</private> b' > "$BATS_TEST_TMPDIR/in"
    run bash -c 'source "$1"; redact_private < "$2"' _ "$SCRIPT" "$BATS_TEST_TMPDIR/in"
    # La ruta de perl conserva el texto público alrededor del bloque; la de sin perl descarta todo.
    [ "$output" = "a [REDACTED] b" ]
}

@test "R06 sin perl: bloque privado cerrado no se devuelve en claro" {
    printf 'antes <private>SECRETO-CERRADO</private> despues' > "$BATS_TEST_TMPDIR/in"
    run sin_perl "$BATS_TEST_TMPDIR/in"
    [ "$status" -eq 0 ]
    [[ "$output" != *SECRETO-CERRADO* ]]
    [[ "$output" != *"<private>"* ]]
    [ "$output" = "[REDACTED]" ]
}

@test "R06 sin perl: bloque sin cierre no se devuelve en claro" {
    printf 'antes <private>SECRETO-ABIERTO\nsegunda linea' > "$BATS_TEST_TMPDIR/in"
    run sin_perl "$BATS_TEST_TMPDIR/in"
    [[ "$output" != *SECRETO-ABIERTO* ]]
    [[ "$output" != *"segunda linea"* ]]
    [ "$output" = "[REDACTED]" ]
}

@test "R06 sin perl: etiquetas en mayúsculas o mixtas tampoco" {
    printf 'x <PRIVATE>SECRETO-MAYUS</PRIVATE> y' > "$BATS_TEST_TMPDIR/in"
    run sin_perl "$BATS_TEST_TMPDIR/in"
    [[ "$output" != *SECRETO-MAYUS* ]]
    printf 'x <PrIvAtE>SECRETO-MIXTO</pRiVaTe> y' > "$BATS_TEST_TMPDIR/in"
    run sin_perl "$BATS_TEST_TMPDIR/in"
    [[ "$output" != *SECRETO-MIXTO* ]]
}

@test "R06 sin perl: bloque multilínea en medio de texto público" {
    printf 'publico\n<private>SECRETO-ML1\nSECRETO-ML2</private>\nmas publico\n' > "$BATS_TEST_TMPDIR/in"
    run sin_perl "$BATS_TEST_TMPDIR/in"
    [[ "$output" != *SECRETO-ML* ]]
}

@test "R06 sin perl, control positivo: texto público con saltos finales se conserva exactamente" {
    printf 'hola publico\n\n\n' > "$BATS_TEST_TMPDIR/in"
    sin_perl "$BATS_TEST_TMPDIR/in" > "$BATS_TEST_TMPDIR/out"
    cmp "$BATS_TEST_TMPDIR/in" "$BATS_TEST_TMPDIR/out"
}

@test "R06 sin perl, control positivo: un </private> suelto sin apertura no descarta el texto" {
    printf 'texto </private> mas texto' > "$BATS_TEST_TMPDIR/in"
    sin_perl "$BATS_TEST_TMPDIR/in" > "$BATS_TEST_TMPDIR/out"
    cmp "$BATS_TEST_TMPDIR/in" "$BATS_TEST_TMPDIR/out"
}
