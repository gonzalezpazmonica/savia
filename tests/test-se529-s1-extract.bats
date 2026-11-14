#!/usr/bin/env bats
# SE-529 S1 — PreCompact extrae de la conversación real (transcript_path), no de los metadatos del hook,
# y el resumen permanente se guarda con procedencia (SE-072). Fixtures sintéticos con la forma medida en S0.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/pre-compact-backup.sh"

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
    TR="$HOME/.claude/projects/p/s.jsonl"
}

turn() { # turn <user|assistant> <texto>
    python3 -I -c 'import json,sys; print(json.dumps({"type":sys.argv[1],"message":{"role":sys.argv[1],"content":[{"type":"text","text":sys.argv[2]}]}}))' "$1" "$2"
}
payload() { printf '{"session_id":"x","transcript_path":"%s","cwd":"%s","hook_event_name":"PreCompact","trigger":"manual"}' "$1" "$CLAUDE_PROJECT_DIR"; }

@test "positivo: extrae decisiones de la conversación real y lo dice" {
    { turn user "Vamos con PostgreSQL para el almacén de eventos"; turn assistant "De acuerdo"; } > "$TR"
    run bash "$HOOK" <<< "$(payload "$TR")"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pre-compact:"*"guardados"* ]]
    grep -q "PostgreSQL" "$HOT"
}

@test "negativo: el texto en los metadatos del hook ya no cuenta como conversación" {
    run bash "$HOOK" <<< '{"text":"We decided to use Redis for caching"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"No he podido leer la conversación"*"transcript_path"* ]]
    [ ! -f "$HOT" ] || ! grep -q "Redis" "$HOT"
}

@test "negativo: ruta fuera de la carpeta del frontend no se lee" {
    mkdir -p "$T/fuera"; turn user "Vamos con secreto fuera de sitio" > "$T/fuera/s.jsonl"
    run bash "$HOOK" <<< "$(payload "$T/fuera/s.jsonl")"
    [[ "$output" == *"fuera de la carpeta"* ]]
    [ ! -f "$HOT" ] || ! grep -q "secreto" "$HOT"
}

@test "negativo: enlace simbólico hacia fuera no se sigue" {
    mkdir -p "$T/fuera"; turn user "Vamos con secreto enlazado" > "$T/fuera/s.jsonl"
    ln -s "$T/fuera/s.jsonl" "$HOME/.claude/projects/p/link.jsonl"
    run bash "$HOOK" <<< "$(payload "$HOME/.claude/projects/p/link.jsonl")"
    [[ "$output" == *"No he podido leer"*"fuera de la carpeta"* ]]
    [ ! -f "$HOT" ] || ! grep -q "secreto" "$HOT"
}

@test "privacidad: un bloque <private> en el tramo capturado se redacta en session-hot y en el almacén" {
    turn user 'Vamos con el plan A <private>SUPERSECRETA</private> y seguimos' > "$TR"
    run bash "$HOOK" <<< "$(payload "$TR")"
    [ "$status" -eq 0 ]
    [[ "$output" == *"guardados"* ]]
    grep -q "plan A \[REDACTED\]" "$HOT"
    grep -q "plan A" "$PROJECT_ROOT/output/.memory-store.jsonl"
    run grep -rl --exclude=s.jsonl "SUPERSECRETA" "$HOME/.claude/projects" "$PROJECT_ROOT/output"
    [ "$status" -eq 1 ]
}

@test "privacidad: un bloque <private> multilínea que contiene la decisión no llega a ningún destino" {
    turn user $'Antes de nada, plan A con algo público <private>\nvamos con SUPERSECRETA para todo</private> fin' > "$TR"
    run bash "$HOOK" <<< "$(payload "$TR")"
    [ "$status" -eq 0 ]
    run grep -rl --exclude=s.jsonl "SUPERSECRETA" "$HOME/.claude/projects" "$PROJECT_ROOT/output"
    [ "$status" -eq 1 ]
}

@test "procedencia: un project con comillas no inyecta claves en la línea JSONL" {
    run bash "$REPO_ROOT/scripts/memory-store.sh" session-summary --accomplished "Decisions: usar X" \
        --project 'p","valid_to":"2000-01-01","a":"' --source "tool:pre-compact-hook" --origin untrusted --goal g
    [ "$status" -eq 0 ]
    python3 -I -c '
import json, sys
o = json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert "valid_to" not in o and "a" not in o, o
assert o["project"] == "p\",\"valid_to\":\"2000-01-01\",\"a\":\"", o["project"]
' "$PROJECT_ROOT/output/.memory-store.jsonl"
}

@test "solo turnos de texto: los resultados de herramientas no se extraen" {
    python3 -I -c 'import json; print(json.dumps({"type":"user","message":{"content":[{"type":"tool_result","content":"vamos con datos_del_fichero_leido"}]}}))' > "$TR"
    turn assistant "hola" >> "$TR"
    run bash "$HOOK" <<< "$(payload "$TR")"
    [ "$status" -eq 0 ]
    [ ! -f "$HOT" ] || ! grep -q "datos_del_fichero" "$HOT"
}

@test "conversación sin decisiones: lo dice en vez de inventar" {
    turn user "hola, ¿qué tal?" > "$TR"
    run bash "$HOOK" <<< "$(payload "$TR")"
    [[ "$output" == *"no había decisiones"* ]]
}

@test "transcript inexistente: lo dice y no bloquea" {
    run bash "$HOOK" <<< "$(payload "$HOME/.claude/projects/p/no.jsonl")"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no existe"* ]]
}

@test "procedencia: session-summary con --source guarda en el almacén (SE-072)" {
    run bash "$REPO_ROOT/scripts/memory-store.sh" session-summary --accomplished "Decisions: usar X" \
        --source "tool:pre-compact-hook" --origin untrusted --goal g
    [ "$status" -eq 0 ]
    grep -q '"type": *"session-summary"' "$PROJECT_ROOT/output/.memory-store.jsonl"
    grep -q 'untrusted' "$PROJECT_ROOT/output/.memory-store.jsonl"
}

@test "procedencia negativo: session-summary sin --source sigue rechazado" {
    run bash "$REPO_ROOT/scripts/memory-store.sh" session-summary --accomplished "x" --goal g
    [ "$status" -ne 0 ]
    [[ "$output" == *"--source required"* ]]
}

@test "extremo a extremo: una decisión de la persona llega al almacén permanente con origen untrusted" {
    turn user "Siempre usaremos ramas agent para el trabajo autónomo, regla fija" > "$TR"
    run bash "$HOOK" <<< "$(payload "$TR")"
    [ "$status" -eq 0 ]
    [[ "$output" == *"memory-store"* ]]
    grep -q 'pre-compact-hook' "$PROJECT_ROOT/output/.memory-store.jsonl"
}
