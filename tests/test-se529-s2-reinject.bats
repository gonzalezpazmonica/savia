#!/usr/bin/env bats
# SE-529 S2 — reinyección acotada tras compactar (post-compaction.sh) y --max-bytes.
# Ref: SE-529 (S2, AC-8, AC-9, AC-10, AC-13, AC-14). Parámetros S0.5: 4096 B, fijada = tier A.
# Cada test debe fallar contra el post-compaction.sh / memory-store.sh previos (SE-456).

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"

setup() {
    TMP=$(mktemp -d)
    export PROJECT_ROOT="$TMP"
    export HOME="$TMP/home"
    export CLAUDE_PROJECT_DIR="$TMP/workspace"
    export SAVIA_TEST_MODE=true
    unset SAVIA_REINJECT_MAX_BYTES
    mkdir -p "$TMP/output" "$CLAUDE_PROJECT_DIR"
    SLUG=$(echo "$CLAUDE_PROJECT_DIR" | sed 's|[/:\\]|-|g; s|^-||')
    mkdir -p "$HOME/.claude/projects/$SLUG/memory"
    SESSION_HOT="$HOME/.claude/projects/$SLUG/memory/session-hot.md"
    STORE="$TMP/output/.memory-store.jsonl"
    POST="${POST_COMPACTION_SCRIPT:-$REPO_ROOT/scripts/post-compaction.sh}"
    MS="$REPO_ROOT/scripts/memory-store.sh"
    # Proyecto activo = alpha (CLAUDE.local.md en el cwd del hook).
    WORK="$TMP/work"; mkdir -p "$WORK"
    printf 'project: alpha\n' > "$WORK/CLAUDE.local.md"
}

teardown() { rm -rf "$TMP"; }

# gen_store N_ALPHA N_BETA N_GAMMA [PINNED_ALPHA]: entradas sintéticas, ts crecientes.
gen_store() {
    python3 - "$STORE" "$1" "$2" "$3" "${4:-0}" <<'PY'
import json, sys
path, na, nb, ng, pin = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
rows = []
def add(proj, i, tier, typ="discovery"):
    rows.append({"ts": "2026-10-%02dT%02d:00:00Z" % (1 + len(rows) // 24 % 28, len(rows) % 24),
                 "type": typ, "title": "%s-titular-%03d" % (proj, i), "content": "x",
                 "project": proj, "importance_tier": tier, "topic_key": "t/%s/%d" % (proj, i),
                 "origin": "agent"})
for i in range(na): add("alpha", i, "B")
for i in range(nb): add("beta", i, "B")
for i in range(ng): add("gamma", i, "B")
for i in range(pin): add("alpha", 900 + i, "A", "decision")
with open(path, "w") as f:
    for r in rows: f.write(json.dumps(r) + "\n")
PY
}

run_post() { cd "$WORK" && run bash "$POST"; }
# Bytes reales de stdout (run y $(...) recortan el salto final).
post_bytes() { (cd "$WORK" && bash "$POST" > "$TMP/stdout.bin" 2>/dev/null); wc -c < "$TMP/stdout.bin"; }

# ── AC-8: 500 entradas, 3 proyectos ──

@test "AC-8: 500 entradas de 3 proyectos: salida <= 4096 B, solo del proyecto activo" {
    gen_store 200 200 100 5
    [ "$(post_bytes)" -le 4096 ]
    run_post
    [ "$status" -eq 0 ]
    [[ "$output" == *"Memoria tras compactar (proyecto: alpha)"* ]]
    [[ "$output" != *"beta-titular"* ]]
    [[ "$output" != *"gamma-titular"* ]]
}

@test "AC-8: las fijadas van antes que las recientes" {
    gen_store 200 200 100 5
    run_post
    [ "$status" -eq 0 ]
    fij=$(printf '%s\n' "$output" | grep -n '^Fijado:' | cut -d: -f1)
    rec=$(printf '%s\n' "$output" | grep -n '^Reciente:' | cut -d: -f1)
    [ -n "$fij" ] && [ -n "$rec" ] && [ "$fij" -lt "$rec" ]
    [[ "$output" == *"alpha-titular-900"* ]]
}

@test "AC-8: lo que no cabe se resume en «y N más» con N exacto" {
    gen_store 200 200 100 5
    run_post
    [[ "$output" == *"(y "*" más; consulta con memory-store recall)"* ]]
    shown=$(printf '%s\n' "$output" | grep -oE 'alpha-titular-[0-9]+' | sort -u | wc -l)
    n=$(printf '%s\n' "$output" | grep -oE '\(y [0-9]+ más' | grep -oE '[0-9]+')
    [ $((shown + n)) -eq 205 ]
}

@test "AC-8: fijadas que no caben: tope pequeño, dice cuántas faltan y respeta el tope" {
    gen_store 100 0 0 40
    SAVIA_REINJECT_MAX_BYTES=300 run_post
    [ "$status" -eq 0 ]
    [ "$(SAVIA_REINJECT_MAX_BYTES=300 post_bytes)" -le 300 ]
    n=$(printf '%s\n' "$output" | grep -oE '\(y [0-9]+ más' | grep -oE '[0-9]+')
    shown=$(printf '%s\n' "$output" | grep -oE 'alpha-titular-[0-9]+' | sort -u | wc -l)
    [ "$n" -gt 0 ]
    [ $((shown + n)) -eq 140 ]
}

@test "AC-8 límite: tope = tamaño exacto cabe; un byte menos muestra menos" {
    gen_store 20 0 0 6
    full=$(post_bytes)   # bytes reales, salto final incluido
    [ "$(SAVIA_REINJECT_MAX_BYTES=$full post_bytes)" -eq "$full" ]
    SAVIA_REINJECT_MAX_BYTES=$full run_post
    [[ "$output" != *"(y "* ]]
    [ "$(SAVIA_REINJECT_MAX_BYTES=$((full - 1)) post_bytes)" -le $((full - 1)) ]
    SAVIA_REINJECT_MAX_BYTES=$((full - 1)) run_post
    [[ "$output" == *"(y "* ]]
}

# ── AC-9: negativos ──

@test "AC-9: almacén ausente: sale 0 sin texto de memoria" {
    run_post
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC-9: almacén vacío: sale 0 sin texto" {
    : > "$STORE"
    run_post
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC-9: almacén sin entradas del proyecto activo: no imprime nada" {
    gen_store 0 20 20
    run_post
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC-9: proyecto no determinable: ninguna entrada del almacén, avisa y reinyecta session-hot" {
    gen_store 20 20 20 3
    rm "$WORK/CLAUDE.local.md"
    git -C "$WORK" init -q
    printf '## Session Context (x)\nDecisions: usar sqlite-marca\n' > "$SESSION_HOT"
    run_post
    [ "$status" -eq 0 ]
    [[ "$output" == *"No he podido determinar el proyecto"* ]]
    [[ "$output" != *"-titular-"* ]]
    [[ "$output" == *"sqlite-marca"* ]]
}

@test "AC-9: entrada sin proyecto no fijada no entra; fijada sí; fijada de otro proyecto nunca" {
    cat > "$STORE" <<'EOF'
{"ts":"2026-10-01T00:00:00Z","type":"discovery","title":"sinproy-suelta","project":"null","importance_tier":"B"}
{"ts":"2026-10-02T00:00:00Z","type":"decision","title":"sinproy-fijada","project":"null","importance_tier":"A","origin":"agent"}
{"ts":"2026-10-03T00:00:00Z","type":"decision","title":"beta-fijada","project":"beta","importance_tier":"A","origin":"agent"}
{"ts":"2026-10-04T00:00:00Z","type":"decision","title":"alpha-fijada","project":"alpha","importance_tier":"A","origin":"agent"}
EOF
    # Relleno B: A queda en 3 de 15 (20 %), por debajo del 30 %, así que tier A basta.
    for i in $(seq 1 11); do
        printf '{"ts":"2026-09-%02dT00:00:00Z","type":"discovery","title":"alpha-relleno-%d","project":"alpha","importance_tier":"B"}\n' "$i" "$i" >> "$STORE"
    done
    run_post
    [[ "$output" == *"sinproy-fijada"* ]]
    [[ "$output" == *"alpha-fijada"* ]]
    [[ "$output" != *"sinproy-suelta"* ]]
    [[ "$output" != *"beta-fijada"* ]]
}

@test "AC-9: líneas corruptas del almacén se ignoran, sin fallar" {
    printf 'no es json\n{"title":\n' > "$STORE"
    printf '{"ts":"2026-10-04T00:00:00Z","type":"decision","title":"alpha-ok","project":"alpha","importance_tier":"A","origin":"agent"}\n' >> "$STORE"
    run_post
    [ "$status" -eq 0 ]
    [[ "$output" == "Memoria tras compactar (proyecto: alpha)"* ]]
    [[ "$output" == *"alpha-ok"* ]]
}

@test "Q1: si A pasa del 30 % del almacén, solo cuentan como fijadas feedback/correction" {
    python3 - "$STORE" <<'PY'
import json, sys
rows = []
for i in range(6):  # 6 de 8 son A (75 %): umbral estricto
    rows.append({"ts": "2026-10-0%dT00:00:00Z" % (i + 1), "type": "decision", "title": "dec-A-%d" % i, "project": "alpha", "importance_tier": "A", "origin": "agent"})
rows.append({"ts": "2026-10-07T00:00:00Z", "type": "feedback", "title": "fb-A", "project": "alpha", "importance_tier": "A", "origin": "owner"})
rows.append({"ts": "2026-10-08T00:00:00Z", "type": "discovery", "title": "disc-B", "project": "alpha", "importance_tier": "B"})
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
    run_post
    fij=$(printf '%s\n' "$output" | grep '^Fijado:')
    [[ "$fij" == *"fb-A"* ]]
    [[ "$fij" != *"dec-A-"* ]]
    [[ "$output" == *"Reciente:"*"dec-A-"* ]]
}

@test "AC-9: UTF-8 multibyte con tope pequeño: salida válida y dentro del tope" {
    python3 - "$STORE" <<'PY'
import json, sys
rows = [{"ts": "2026-10-%02dT00:00:00Z" % (i + 1), "type": "discovery", "title": "ñandú-ü-日本語-%02d" % i, "project": "alpha", "importance_tier": "B"} for i in range(25)]
open(sys.argv[1], "w").write("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows))
PY
    SAVIA_REINJECT_MAX_BYTES=200 run_post
    [ "$status" -eq 0 ]
    [ "$(SAVIA_REINJECT_MAX_BYTES=200 post_bytes)" -le 200 ]
    printf '%s' "$output" | iconv -f UTF-8 -t UTF-8 >/dev/null
    [[ "$output" == "Memoria tras compactar (proyecto: alpha)"* ]]
    [[ "$output" == *"ñandú-ü-日本語-"* ]]
}

# ── session-hot ──

@test "session-hot: se reinyecta como «Esta sesión» y se vacía tras emitir" {
    printf '## Session Context (x)\nDecisions: usar redis-marca\n' > "$SESSION_HOT"
    run_post
    [ "$status" -eq 0 ]
    [[ "$output" == *"Esta sesión: "*"redis-marca"* ]]
    [ ! -s "$SESSION_HOT" ]
}

@test "session-hot: NO se vacía si la emisión falla (stdout cerrado)" {
    gen_store 3 0 0
    printf 'Decisions: usar redis-marca\n' > "$SESSION_HOT"
    cd "$WORK"
    bash "$POST" >&- 2>/dev/null || true
    [ -s "$SESSION_HOT" ]
    grep -q redis-marca "$SESSION_HOT"
}

@test "session-hot: NO se vacía si escribir en stdout falla tras generar el bloque (/dev/full)" {
    gen_store 3 0 0
    printf 'Decisions: usar redis-marca\n' > "$SESSION_HOT"
    cd "$WORK"
    run bash -c "bash '$POST' > /dev/full 2>/dev/null; echo rc=\$?"
    [ "$output" = "rc=0" ]
    grep -q redis-marca "$SESSION_HOT"
}

@test "session-hot: si la línea de sesión no cabe, salen las fijadas y session-hot se conserva" {
    gen_store 10 0 0 3   # 3 A de 13 (23 %): fijadas por tier A
    python3 -c 'print("Decisions: " + "larga-marca " * 100)' > "$SESSION_HOT"
    SAVIA_REINJECT_MAX_BYTES=300 run_post
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fijado: "*"alpha-titular-90"* ]]
    [[ "$output" != *"Esta sesión"* ]]
    grep -q larga-marca "$SESSION_HOT"
}

@test "session-hot: sin nada que emitir (tope diminuto) no se vacía" {
    printf 'Decisions: usar redis-marca\n' > "$SESSION_HOT"
    SAVIA_REINJECT_MAX_BYTES=10 run_post
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -s "$SESSION_HOT" ]
}

# ── origen y sustitución ──

@test "SE-352: untrusted, system o sin origen nunca son «Fijado»; sin proyecto ni se reinyectan" {
    cat > "$STORE" <<'EOF'
{"ts":"2026-10-01T00:00:00Z","type":"decision","title":"inyec-nulo","project":"null","importance_tier":"A","origin":"untrusted"}
{"ts":"2026-10-02T00:00:00Z","type":"decision","title":"sistema-nulo","project":"null","importance_tier":"A","origin":"system"}
{"ts":"2026-10-03T00:00:00Z","type":"decision","title":"sinorigen-nulo","project":"null","importance_tier":"A"}
{"ts":"2026-10-04T00:00:00Z","type":"decision","title":"inyec-alpha","project":"alpha","importance_tier":"A","origin":"untrusted"}
{"ts":"2026-10-05T00:00:00Z","type":"decision","title":"buena-alpha","project":"alpha","importance_tier":"A","origin":"owner"}
EOF
    for i in $(seq 1 10); do
        printf '{"ts":"2026-09-%02dT00:00:00Z","type":"discovery","title":"alpha-relleno-%d","project":"alpha","importance_tier":"B","origin":"agent"}\n' "$i" "$i" >> "$STORE"
    done
    run_post
    fij=$(printf '%s\n' "$output" | grep '^Fijado:')
    [[ "$fij" == *"buena-alpha"* ]]
    [[ "$fij" != *"inyec-alpha"* ]]
    [[ "$output" != *"inyec-nulo"* ]]
    [[ "$output" != *"sistema-nulo"* ]]
    [[ "$output" != *"sinorigen-nulo"* ]]
}

@test "SPEC-034: una entrada sustituida (valid_to / superseded_by) no se reinyecta" {
    cat > "$STORE" <<'EOF'
{"ts":"2026-10-01T00:00:00Z","type":"decision","title":"vieja-decision","project":"alpha","importance_tier":"A","origin":"owner","topic_key":"decision/x","valid_to":"2026-10-02T00:00:00Z","superseded_by":"decision/y"}
{"ts":"2026-10-01T01:00:00Z","type":"decision","title":"otra-vieja","project":"alpha","importance_tier":"B","origin":"owner","superseded_by":"decision/z"}
{"ts":"2026-10-02T00:00:00Z","type":"decision","title":"nueva-decision","project":"alpha","importance_tier":"A","origin":"owner","topic_key":"decision/y"}
EOF
    run_post
    [[ "$output" == *"nueva-decision"* ]]
    [[ "$output" != *"vieja-decision"* ]]
    [[ "$output" != *"otra-vieja"* ]]
    [[ "$output" != *"(y "* ]]
}

# ── AC-10: --max-bytes ──

ms_store() {
    python3 - "$STORE" <<'PY'
import json, sys
rows = [{"ts": "2026-10-%02dT00:00:00Z" % (i + 1), "type": "decision", "title": "ñandú-日本-%02d" % i, "topic_key": "k%d" % i, "project": "alpha", "content": "ñandú", "rev": 1} for i in range(20)]
open(sys.argv[1], "w").write("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows))
PY
}

@test "AC-10: context --max-bytes N devuelve <= N bytes, en frontera de línea y UTF-8 válido" {
    ms_store
    run bash -c "bash '$MS' context --max-bytes 200 2>/dev/null | tee '$TMP/o.txt' | wc -c"
    [ "$output" -le 200 ]
    [ "$output" -gt 0 ]
    printf '%s' "$(tail -c1 "$TMP/o.txt" | od -An -c | tr -d ' ')" | grep -q '\\n'
    iconv -f UTF-8 -t UTF-8 "$TMP/o.txt" >/dev/null
}

@test "AC-10: N menor que la primera línea: vacío, exit 0 y aviso por stderr" {
    ms_store
    run bash -c "bash '$MS' context --max-bytes 5 2>'$TMP/err.txt' >'$TMP/out.txt'; echo rc=\$?"
    [ "$output" = "rc=0" ]
    [ ! -s "$TMP/out.txt" ]
    grep -q "max-bytes" "$TMP/err.txt"
}

@test "AC-10: sin la opción la salida es idéntica a la de siempre; con N grande también" {
    ms_store
    bash "$MS" context > "$TMP/a.txt"
    bash "$MS" context --max-bytes 1000000 > "$TMP/b.txt"
    cmp "$TMP/a.txt" "$TMP/b.txt"
    [ "$(wc -l < "$TMP/a.txt")" -eq 22 ]
}

@test "AC-10: valor no numérico de --max-bytes falla sin emitir" {
    ms_store
    run bash "$MS" context --max-bytes abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"entero"* ]]
}

@test "AC-10: --max-bytes sin valor (último argumento) falla sin emitir" {
    ms_store
    run bash -c "bash '$MS' context --max-bytes 2>'$TMP/err.txt' >'$TMP/out.txt'; echo rc=\$?"
    [ "$output" != "rc=0" ]
    [ ! -s "$TMP/out.txt" ]
    grep -q "entero" "$TMP/err.txt"
}

@test "AC-10: con entrada vacía --max-bytes no avisa de «menor que la primera línea»" {
    run bash -c "source '$MS'; printf '' | _cap_bytes 5 2>&1 >/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c "source '$MS'; printf 'linea-larga\n' | _cap_bytes 5 2>&1 >/dev/null"
    [[ "$output" == *"menor que la primera línea"* ]]
}

@test "AC-10: search --max-bytes recorta también la búsqueda" {
    ms_store
    run bash -c "bash '$MS' search 'ñandú' --mode grep 2>/dev/null | wc -c"
    [ "$output" -gt 300 ]
    bash "$MS" search 'ñandú' --mode grep --max-bytes 120 > "$TMP/s.txt" 2>/dev/null
    [ "$(wc -c < "$TMP/s.txt")" -le 120 ]
    grep -q 'ñandú' "$TMP/s.txt"
}
