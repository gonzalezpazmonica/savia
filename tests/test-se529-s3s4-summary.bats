#!/usr/bin/env bats
# SE-529 S3+S4 — resumen compactado guardado una sola vez, idempotente, «no confirmado» si falla;
# fixtures sintéticos con la forma de S0.1; paridad Claude Code / OpenCode; hooks que no bloquean.
# Ref: SE-529 AC-11, AC-12, AC-13, AC-14. Cada test debe fallar contra post-compaction.sh previo (SE-456).
# El directorio temporal es el de bats (BATS_TEST_TMPDIR): no hay borrado recursivo en este fichero.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"
S1_ID="00000000-0000-4000-8000-000000000001"
S2_ID="00000000-0000-4000-8000-000000000002"

setup() {
    TMP="$BATS_TEST_TMPDIR"
    export PROJECT_ROOT="$TMP"
    export HOME="$TMP/home"
    export CLAUDE_PROJECT_DIR="$TMP/workspace"
    export SAVIA_TEST_MODE=true
    mkdir -p "$TMP/output" "$CLAUDE_PROJECT_DIR" "$HOME"
    STORE="$TMP/output/.memory-store.jsonl"
    SAVER="$REPO_ROOT/scripts/compaction-summary-save.py"
    POST="${POST_COMPACTION_SCRIPT:-$REPO_ROOT/scripts/post-compaction.sh}"
    FIX="$REPO_ROOT/scripts/compaction-fixtures.py"
    WORK="$TMP/work"; mkdir -p "$WORK"
    printf 'project: alpha\n' > "$WORK/CLAUDE.local.md"
}

payload() { python3 "$FIX" payload "$@"; }                    # evento frontend [opciones]
save() { printf '%s' "$1" | python3 -I "$SAVER" --project alpha; }
entries() { [ -f "$STORE" ] && { grep -c '"topic_key":"compact-summary/' "$STORE" || true; } || echo 0; }
# Raíz de almacén rota: «output» es un fichero, así que no se puede crear el almacén.
break_store() { mkdir -p "$TMP/bad"; : > "$TMP/bad/output"; export PROJECT_ROOT="$TMP/bad"; }

# ── fixtures: forma medida en S0.1 ──

@test "fixtures: PostCompact de Claude Code tiene los campos de S0.1 y compact_summary" {
    run payload PostCompact claude-code
    [ "$status" -eq 0 ]
    keys=$(printf '%s' "$output" | python3 -c 'import json,sys;print(",".join(sorted(json.load(sys.stdin))))')
    [ "$keys" = "compact_summary,cwd,hook_event_name,prompt_id,session_id,transcript_path,trigger" ]
}

@test "fixtures: PreCompact y SessionStart de Claude Code no traen el resumen" {
    run payload PreCompact claude-code
    [[ "$output" != *compact_summary* ]]
    run payload SessionStart claude-code
    [[ "$output" != *compact_summary* ]]
    [[ "$output" == *'"source": "compact"'* ]]
}

@test "fixtures: OpenCode no entrega transcript_path ni resumen (S0.1)" {
    run payload PostCompact opencode
    [ "$status" -eq 0 ]
    [[ "$output" != *transcript_path* && "$output" != *compact_summary* ]]
    [[ "$output" == *session.compacted* ]]
}

@test "fixtures: celda no entregada (SessionStart de OpenCode) falla en vez de inventar" {
    run payload SessionStart opencode
    [ "$status" -ne 0 ]
}

@test "fixtures: --summary-bytes fija el tamaño y la semilla es determinista" {
    a=$(payload PostCompact claude-code --summary-bytes 20000 --seed 7)
    b=$(payload PostCompact claude-code --summary-bytes 20000 --seed 7)
    [ "$a" = "$b" ]
    n=$(printf '%s' "$a" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["compact_summary"]))')
    [ "$n" -eq 20000 ]
}

@test "fixtures: el transcript sintético tiene N vueltas y K decisiones, una línea JSON cada una" {
    run python3 "$FIX" transcript --turns 30 --decisions 2
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | python3 -c 'import json,sys;print(sum(1 for l in sys.stdin if json.loads(l)["type"] in ("user","assistant")))')" -eq 30 ]
    [ "$(printf '%s\n' "$output" | grep -c 'Decisión:')" -eq 2 ]
}

# ── AC-11: idempotencia ──

@test "AC-11: mismo resumen y misma sesión dos veces: una entrada, la segunda no escribe" {
    p=$(payload PostCompact claude-code)
    run save "$p"
    [ "$status" -eq 0 ]
    [[ "$output" == *"confirmado, guardado"* ]]
    before=$(sha256sum "$STORE")
    run save "$p"
    [[ "$output" == *"ya estaba guardado"* ]]
    [ "$(entries)" -eq 1 ]
    [ "$before" = "$(sha256sum "$STORE")" ]
}

@test "AC-11: resumen distinto en la misma sesión: dos entradas" {
    save "$(payload PostCompact claude-code --seed 1)" >/dev/null
    save "$(payload PostCompact claude-code --seed 2)" >/dev/null
    [ "$(entries)" -eq 2 ]
}

@test "AC-11: la huella normaliza espacios: el mismo resumen con otro espaciado no duplica" {
    p=$(payload PostCompact claude-code)
    save "$p" >/dev/null
    q=$(printf '%s' "$p" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["compact_summary"]="  "+d["compact_summary"].replace(" ","   ")+"\n";print(json.dumps(d))')
    run save "$q"
    [[ "$output" == *"ya estaba guardado"* ]]
    [ "$(entries)" -eq 1 ]
}

@test "AC-11: dos sesiones con resúmenes distintos: dos entradas (la clave incluye la sesión)" {
    save "$(payload PostCompact claude-code --session $S1_ID --seed 1)" >/dev/null
    save "$(payload PostCompact claude-code --session $S2_ID --seed 2)" >/dev/null
    [ "$(entries)" -eq 2 ]
    grep -q "compact-summary/$S1_ID/" "$STORE"
    grep -q "compact-summary/$S2_ID/" "$STORE"
}

@test "AC-11: guardado fallido (almacén no creable): dice no confirmado, no guardado" {
    break_store
    run save "$(payload PostCompact claude-code)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no confirmado"* ]]
    [[ "$output" == *"memory-store recall"* ]]
    [[ "$output" != *"confirmado, guardado"* && "$output" != *"ya estaba"* ]]
}

@test "AC-11: guardado sin error pero sin entrada (contenido duplicado de otra sesión): no confirmado" {
    save "$(payload PostCompact claude-code --session $S1_ID --seed 1)" >/dev/null
    # Mismo texto, otra sesión: save lo omite como duplicado (15 min) y no escribe la clave nueva.
    run save "$(payload PostCompact claude-code --session $S2_ID --seed 1)"
    [[ "$output" == *"no confirmado"* && "$output" == *"no aparece"* ]]
    [[ "$output" != *"confirmado, guardado"* ]]
    [ "$(entries)" -eq 1 ]
}

# ── S0.1: celda sin resumen → no disponible (AC-12 paridad) ──

@test "AC-12: OpenCode (sin resumen) da aviso explícito «no disponible» y no escribe" {
    run save "$(payload PostCompact opencode)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no disponible"* ]]
    [ "$(entries)" -eq 0 ]
}

@test "AC-12: paridad normalizada: Claude Code confirma, OpenCode declara no disponible; ninguno calla" {
    a=$(save "$(payload PostCompact claude-code)")
    b=$(save "$(payload PostCompact opencode)")
    [ -n "$a" ] && [ -n "$b" ]
    [ "$(printf '%s' "$a" | sed -E 's/^Resumen compactado: ([a-z]+).*/\1/')" = "confirmado" ]
    [ "$(printf '%s' "$b" | sed -E 's/^Resumen compactado: ([a-z]+ [a-z]+).*/\1/')" = "no disponible" ]
}

@test "S4: carga con resumen pero sin identificador de sesión: no disponible, sin escribir" {
    p=$(payload PostCompact claude-code | python3 -c 'import json,sys;d=json.load(sys.stdin);del d["session_id"];print(json.dumps(d))')
    run save "$p"
    [[ "$output" == *"no disponible"* && "$output" == *"sesión"* ]]
    [ "$(entries)" -eq 0 ]
}

@test "S4: identificador de sesión con caracteres de ruta o shell se rechaza" {
    p=$(payload PostCompact claude-code --session 'x/../$(id)')
    run save "$p"
    [[ "$output" == *"no disponible"* ]]
    [ "$(entries)" -eq 0 ]
}

@test "S4: resumen vacío o solo espacios: no disponible, sin escribir" {
    run save '{"session_id":"abc","compact_summary":"   \n "}'
    [[ "$output" == *"no disponible"* ]]
    [ "$(entries)" -eq 0 ]
}

@test "S4/S5: el contenido privado del resumen no llega al almacén" {
    p=$(payload PostCompact claude-code | python3 -c 'import json,sys;d=json.load(sys.stdin);d["compact_summary"]="pub uno <private>CLAVE-SECRETA-XYZ\nlinea dos</private> pub dos";print(json.dumps(d))')
    run save "$p"
    [[ "$output" == *"confirmado, guardado"* ]]
    run grep -c 'CLAVE-SECRETA-XYZ' "$STORE"
    [ "$output" = "0" ]
    grep -q 'pub uno' "$STORE"
}

# ── AC-13 / AC-14: post-compaction.sh integrado ──

run_post() { cd "$WORK" && run bash -c 'printf "%s" "$1" | bash "$2"' _ "$1" "$POST"; }

@test "integración: PostCompact de Claude Code guarda el resumen y avisa tras el bloque" {
    printf '{"ts":"2026-10-01T00:00:00Z","type":"decision","title":"alpha-titular","content":"x","project":"alpha","importance_tier":"B","topic_key":"t/a/1"}\n' > "$STORE"
    run_post "$(payload PostCompact claude-code)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Memoria tras compactar (proyecto: alpha)"* ]]
    [[ "$output" == *"Resumen compactado: confirmado, guardado"* ]]
    [ "$(entries)" -eq 1 ]
}

@test "integración: compactar dos veces con el mismo resumen deja una entrada" {
    p=$(payload PostCompact claude-code)
    run_post "$p"; run_post "$p"
    [[ "$output" == *"ya estaba guardado"* ]]
    [ "$(entries)" -eq 1 ]
}

@test "integración: OpenCode sin almacén ni sesión caliente: solo el aviso de no disponible" {
    run_post "$(payload PostCompact opencode)"
    [ "$status" -eq 0 ]
    [ "$output" = "Resumen compactado: no disponible (el frontend no entrega el resumen en este evento)." ]
}

@test "integración: sin carga (stdin vacío) el comportamiento de S2 no cambia: sin texto" {
    run_post ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$STORE" ]
}

@test "AC-13: basura, JSON roto, binario y carga enorme: exit 0 y sin escribir en el almacén" {
    run_post 'esto no es json {{{'
    [ "$status" -eq 0 ]
    [[ "$output" == *"no disponible"* ]]
    run bash -c 'cd "$1" && head -c 3000 /dev/urandom | bash "$2"' _ "$WORK" "$POST"
    [ "$status" -eq 0 ]
    python3 -c 'import json;print(json.dumps({"session_id":"s","compact_summary":"a "*3000000}))' > "$TMP/big.json"
    run bash -c 'cd "$1" && bash "$2" < "$3"' _ "$WORK" "$POST" "$TMP/big.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no disponible"* ]]
    [ "$(entries)" -eq 0 ]
}

@test "AC-13: solo escribe en el almacén: ningún otro fichero nuevo bajo la raíz de pruebas" {
    before=$(find "$TMP" -type f -not -path "$TMP/output/*" | sort | sha256sum)
    run_post "$(payload PostCompact claude-code)"
    after=$(find "$TMP" -type f -not -path "$TMP/output/*" | sort | sha256sum)
    [ "$before" = "$after" ]
}

@test "AC-14: «confirmado, guardado» solo aparece cuando la entrada existe en el almacén" {
    run_post "$(payload PostCompact claude-code)"
    [[ "$output" == *"confirmado, guardado"* ]]
    [ "$(entries)" -eq 1 ]
    break_store
    run_post "$(payload PostCompact claude-code --seed 9)"
    [[ "$output" != *"confirmado, guardado"* ]]
    [[ "$output" == *"no confirmado"* ]]
}
