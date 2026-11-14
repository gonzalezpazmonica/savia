#!/usr/bin/env bats
# SE-529 S1 — tests que matan a los mutantes supervivientes E02..E10 de la auditoría independiente
# del 2026-11-14. Cada test indica el mutante que mata. Fixtures sintéticos, sin conversaciones reales.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/pre-compact-backup.sh"
MAX=589824

setup() {
    T="$BATS_TEST_TMPDIR"
    export HOME="$T/home"
    export CLAUDE_CONFIG_DIR="$HOME/.claude"
    export CLAUDE_PROJECT_DIR="$T/ws"
    export PROJECT_ROOT="$T/store"
    export SAVIA_MEMORY_INDEX_FILE="$T/MEMORY.md"
    mkdir -p "$CLAUDE_PROJECT_DIR" "$PROJECT_ROOT/output" "$HOME/.claude/projects/p"
    SLUG=$(echo "$CLAUDE_PROJECT_DIR" | sed 's|[/:\\]|-|g; s|^-||')
    HOT="$HOME/.claude/projects/$SLUG/memory/session-hot.md"
    STORE="$PROJECT_ROOT/output/.memory-store.jsonl"
    TR="$HOME/.claude/projects/p/s.jsonl"
}

turn() { # turn <user|assistant|system> <texto> [clave=valor_json_extra]
    python3 -I -c '
import json, sys
o = {"type": sys.argv[1], "message": {"role": sys.argv[1], "content": [{"type": "text", "text": sys.argv[2]}]}}
if len(sys.argv) > 3:
    o[sys.argv[3]] = True
print(json.dumps(o))' "$@"
}
payload() { printf '{"session_id":"x","transcript_path":"%s","cwd":"%s","hook_event_name":"PreCompact","trigger":"manual"}' "$1" "$CLAUDE_PROJECT_DIR"; }
run_hook() { run bash "$HOOK" <<< "$(payload "$1")"; }
# El texto no debe aparecer en ninguno de los dos destinos (session-hot ni almacén permanente).
not_saved() { ! { [ -f "$HOT" ] && grep -q "$1" "$HOT"; } && ! { [ -f "$STORE" ] && grep -q "$1" "$STORE"; }; }
saved_hot() { [ -f "$HOT" ] && grep -q "$1" "$HOT"; }

# --- E02: propietario del fichero --------------------------------------------------------------
# No hace falta ser otro usuario: un python3 de prueba (solo para el extractor del hook) devuelve
# getuid()+<desfase>, así que con desfase 1 el fichero, que es de quien ejecuta, parece ajeno.
# Acoplamiento deliberado: el shim reconoce el extractor por el literal «STORE_SCRIPT, MAX_BYTES» de
# su código. Si ese literal cambia, el shim deja de interceptar, no se crea $T/shim.hit y los tests
# E02 fallan en voz alta (no en silencio).
shim_uid() { # shim_uid [desfase=1]
    mkdir -p "$T/shim"
    local real; real="$(command -v python3)"
    local off="${1:-1}"
    cat > "$T/shim/python3" <<SHIM
#!/bin/bash
if [[ "\$1" == "-I" && "\$2" == "-c" && "\$3" == *"STORE_SCRIPT, MAX_BYTES"* ]]; then
    : > "$T/shim.hit"
    code="\$3"; shift 3
    exec "$real" -I -c "import os; _g = os.getuid; os.getuid = lambda: _g() + $off
\$code" "\$@"
fi
exec "$real" "\$@"
SHIM
    chmod +x "$T/shim/python3"
}

@test "E02 propietario ajeno: se rechaza, se avisa y no se escribe en ningún destino" {
    shim_uid
    turn user "Vamos con PROP_AJENO para el almacén" > "$TR"
    PATH="$T/shim:$PATH" run_hook "$TR"
    [ "$status" -eq 0 ]
    [ -f "$T/shim.hit" ]
    [[ "$output" == *"No he podido leer la conversación"*"no es de la persona que ejecuta el hook"* ]]
    [ ! -f "$HOT" ]
    [ ! -s "$STORE" ]
}

@test "E02 control positivo: por el mismo shim, con propietario propio (desfase 0), sí se extrae" {
    shim_uid 0
    turn user "Vamos con PROP_PROPIO para el almacén" > "$TR"
    PATH="$T/shim:$PATH" run_hook "$TR"
    [ "$status" -eq 0 ]
    [ -f "$T/shim.hit" ]
    [[ "$output" == *"guardados"* ]]
    saved_hot PROP_PROPIO
}

# --- E03: solo ficheros regulares --------------------------------------------------------------
@test "E03 FIFO real: se rechaza sin bloquear y no se extrae nada" {
    mkfifo "$HOME/.claude/projects/p/f.jsonl"
    SECONDS=0
    PATH="$PATH" run timeout 15 bash "$HOOK" <<< "$(payload "$HOME/.claude/projects/p/f.jsonl")"
    [ "$status" -eq 0 ]
    [ "$SECONDS" -lt 12 ]
    [[ "$output" == *"la ruta no es un fichero regular"* ]]
    [ ! -f "$HOT" ]
    [ ! -s "$STORE" ]
}

@test "E03 directorio: se rechaza como no regular" {
    mkdir "$HOME/.claude/projects/p/d.jsonl"
    run_hook "$HOME/.claude/projects/p/d.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"la ruta no es un fichero regular"* ]]
}

# --- E04: tope de lectura exacto ---------------------------------------------------------------
# Fichero con una decisión antigua al principio, un turno de relleno sin decisiones y una reciente
# al final, de tamaño total exacto $1.
big_transcript() {
    # El relleno son palabras separadas (líneas de ~1 kB): un único token gigante hace cuadrático el
    # patrón de ficheros del extractor y agota su tiempo, lo que taparía lo que mide este test.
    python3 -I -c '
import json, sys
size = int(sys.argv[1])
def t(text): return json.dumps({"type": "user", "message": {"content": [{"type": "text", "text": text}]}}) + "\n"
head, tail = t("Vamos con DECISION_ANTIGUA para empezar"), t("Vamos con DECISION_RECIENTE al final")
over = len(t(""))
fill, left = "", size - len(head) - len(tail)
while left > 0:
    n = min(1000, left - over) if left - over >= 0 else 0
    assert n > 0 or left == 0, left
    line = t(("ab " * 400)[:n]); fill += line; left -= len(line)
data = head + fill + tail
assert len(data.encode()) == size, (len(data.encode()), size)
sys.stdout.write(data)' "$1" > "$TR"
}

@test "E04 un byte por encima del tope: se trunca, se avisa y la decisión antigua queda fuera" {
    big_transcript $((MAX + 1))
    run_hook "$TR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Solo se leyeron los últimos $MAX bytes"* ]]
    saved_hot DECISION_RECIENTE
    not_saved DECISION_ANTIGUA
}

@test "E04 tamaño exacto del tope: se lee entero y no se avisa de truncamiento" {
    big_transcript "$MAX"
    run_hook "$TR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Solo se leyeron"* ]]
    saved_hot DECISION_RECIENTE
    saved_hot DECISION_ANTIGUA
}

@test "E04 conversación de unos 700 kB: solo la parte final y con aviso" {
    big_transcript 700000
    run_hook "$TR"
    [[ "$output" == *"Solo se leyeron los últimos $MAX bytes"* ]]
    saved_hot DECISION_RECIENTE
    not_saved DECISION_ANTIGUA
}

# --- E05: los turnos system no son conversación ------------------------------------------------
@test "E05 turno system: ni su texto ni sus referencias a ficheros se extraen" {
    { turn system "Vamos con SISTEMA_DECISION y revisa fantasma_sistema.py"; turn user "Vamos con PostgreSQL de verdad"; } > "$TR"
    run_hook "$TR"
    [ "$status" -eq 0 ]
    saved_hot PostgreSQL
    not_saved SISTEMA_DECISION
    not_saved fantasma_sistema
}

@test "E05 control: el mismo texto en un turno de la persona sí se extrae" {
    turn user "Vamos con PERSONA_DECISION y revisa real_persona.py" > "$TR"
    run_hook "$TR"
    saved_hot PERSONA_DECISION
    saved_hot real_persona.py
}

# --- E06: la redacción de privados va antes de extraer -----------------------------------------
@test "E06 decisión, corrección, regla y fichero dentro de privados: no llegan a ningún destino" {
    {
        turn user "<private>Vamos con ALFA_PRIV_DEC como plan</private>"
        turn user "<private>Eso no es correcto, cambia a BETA_PRIV_COR ahora</private>"
        turn user "<private>Siempre usa GAMMA_PRIV_REG en cada commit</private>"
        turn assistant "<private>Revisa delta_priv.py antes de seguir</private>"
        turn user "Vamos con PUBLICA_POSTERIOR para el resto"
    } > "$TR"
    run_hook "$TR"
    [ "$status" -eq 0 ]
    saved_hot PUBLICA_POSTERIOR
    not_saved ALFA_PRIV_DEC
    not_saved BETA_PRIV_COR
    not_saved GAMMA_PRIV_REG
    not_saved delta_priv
}

@test "E06 bloque multilínea y con mayúsculas dentro de una decisión" {
    {
        turn user $'Vamos con plan <PRIVATE>EPSILON_PRIV\nsegunda línea</Private> y seguimos con OTRA_PUBLICA'
    } > "$TR"
    run_hook "$TR"
    [ "$status" -eq 0 ]
    saved_hot OTRA_PUBLICA
    not_saved EPSILON_PRIV
    not_saved "segunda línea"
}

@test "E06 bloque sin cierre al final: lo privado no se guarda y lo público anterior sí" {
    {
        turn user "Vamos con PUBLICA_ANTERIOR primero"
        turn user "<private>Vamos con ZETA_SIN_CIERRE nunca"
    } > "$TR"
    run_hook "$TR"
    [ "$status" -eq 0 ]
    saved_hot PUBLICA_ANTERIOR
    not_saved ZETA_SIN_CIERRE
}

# --- E07: resúmenes, metadatos y conversaciones laterales no son la conversación ---------------
@test "E07 resumen compacto: no se extrae" {
    { turn user "Vamos con RESUMEN_DEC aunque sea resumen" isCompactSummary; turn user "Vamos con ORDINARIO_UNO normal"; } > "$TR"
    run_hook "$TR"
    saved_hot ORDINARIO_UNO
    not_saved RESUMEN_DEC
}

@test "E07 metadatos (isMeta): no se extraen" {
    { turn user "Vamos con META_DEC aunque sea meta" isMeta; turn user "Vamos con ORDINARIO_DOS normal"; } > "$TR"
    run_hook "$TR"
    saved_hot ORDINARIO_DOS
    not_saved META_DEC
}

@test "E07 conversación lateral (isSidechain): no se extrae" {
    { turn user "Vamos con LATERAL_DEC aunque sea lateral" isSidechain; turn user "Vamos con ORDINARIO_TRES normal"; } > "$TR"
    run_hook "$TR"
    saved_hot ORDINARIO_TRES
    not_saved LATERAL_DEC
}

# --- E08: solo la persona origina correcciones y reglas ----------------------------------------
@test "E08 corrección y regla del asistente no cuentan; las de la persona sí; su decisión sí" {
    {
        turn assistant "Eso no es correcto, cambia a ASIS_COR_UNO ahora. Siempre usa ASIS_REG_UNO en cada commit. Decidimos ASIS_DEC_UNO por ahora"
        turn user "Eso no es correcto, cambia a USER_COR_UNO ahora. Siempre usa USER_REG_UNO en cada commit"
    } > "$TR"
    run_hook "$TR"
    [ "$status" -eq 0 ]
    saved_hot USER_COR_UNO
    grep -q USER_REG_UNO "$STORE"
    saved_hot ASIS_DEC_UNO
    not_saved ASIS_COR_UNO
    not_saved ASIS_REG_UNO
}

# --- E09: se conservan las cinco decisiones más recientes --------------------------------------
decisions_line() { grep -m1 '^Decisions:' "$HOT"; }
turns_n() { # turns_n <n>: n decisiones distintas "Vamos con opcion_i elegida"
    for i in $(seq 1 "$1"); do turn user "Vamos con opcion_$i elegida"; done > "$TR"
}

@test "E09 seis decisiones: quedan las cinco más recientes, en orden" {
    turns_n 6
    run_hook "$TR"
    [ "$(decisions_line)" = "Decisions: Vamos con opcion_2 elegida;Vamos con opcion_3 elegida;Vamos con opcion_4 elegida;Vamos con opcion_5 elegida;Vamos con opcion_6 elegida" ]
}

@test "E09 cinco decisiones: se conservan las cinco" {
    turns_n 5
    run_hook "$TR"
    [ "$(decisions_line)" = "Decisions: Vamos con opcion_1 elegida;Vamos con opcion_2 elegida;Vamos con opcion_3 elegida;Vamos con opcion_4 elegida;Vamos con opcion_5 elegida" ]
}

@test "E09 una decisión: se conserva esa" {
    turns_n 1
    run_hook "$TR"
    [ "$(decisions_line)" = "Decisions: Vamos con opcion_1 elegida" ]
}

@test "E09 cero decisiones: no hay línea de decisiones" {
    turn user "hola, ¿qué tal?" > "$TR"
    run_hook "$TR"
    [ ! -f "$HOT" ]
}

@test "E09 una decisión repetida cuenta una vez: no desplaza a las anteriores" {
    { for i in 1 2 3 4 5; do turn user "Vamos con opcion_$i elegida"; done; turn user "vamos con OPCION_5 elegida"; } > "$TR"
    run_hook "$TR"
    [ "$(decisions_line)" = "Decisions: Vamos con opcion_1 elegida;Vamos con opcion_2 elegida;Vamos con opcion_3 elegida;Vamos con opcion_4 elegida;Vamos con opcion_5 elegida" ]
}

# --- E10: procedencia de lo que guarda el hook -------------------------------------------------
@test "E10 la entrada que guarda el hook lleva tipo, fuente y origen untrusted a la vez" {
    turn user "Siempre usaremos ramas agent para el trabajo autónomo ORIGEN_E10" > "$TR"
    run_hook "$TR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"memory-store"* ]]
    python3 -I - "$STORE" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if "ORIGEN_E10" in l]
assert len(rows) == 1, rows
r = rows[0]
assert r.get("type") == "session-summary", r
assert r.get("source") == "tool:pre-compact-hook", r
assert r.get("origin") == "untrusted", r
PY
}
