#!/usr/bin/env bats
# SE-529 S0 — tests que matan a los mutantes supervivientes B02, B04, B05, B06 y B07 de la auditoría
# independiente del 2026-11-14 (compaction-baseline-counts.py y compaction-shape-collector.py).
# Fixtures sintéticos; el directorio temporal es el de bats (sin borrado de ficheros en este test).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
BASE="$REPO_ROOT/scripts/compaction-baseline-counts.py"
COL="$REPO_ROOT/scripts/compaction-shape-collector.py"

setup() {
    T="$BATS_TEST_TMPDIR"
    export HOME="$T/home"
    export SAVIA_COMPACT_SHAPE_LOG="$T/state/shape.jsonl"
    mkdir -p "$HOME/.claude/projects/p1" "$T/ws/output" "$T/state"
    STORE="$T/ws/output/.memory-store.jsonl"
}
reset_log() { : > "$SAVIA_COMPACT_SHAPE_LOG"; }

# ── B02: ventana de las últimas 20 entradas del almacén ────────────────────────────────────────
# mkstore <n> <posiciones activas contadas desde el final, 1 = última>: n entradas, las indicadas
# del proyecto "pa" y el resto de "pb".
mkstore() {
    python3 -I - "$STORE" "$1" "${2:-}" <<'PY'
import json, sys
path, n, act = sys.argv[1], int(sys.argv[2]), {int(x) for x in sys.argv[3].split(",") if x}
with open(path, "w") as f:
    for i in range(n):
        from_end = n - i
        f.write(json.dumps({"ts": "2026-01-01T00:00:00Z", "type": "decision", "title": "t%d" % i, "content": "c",
                            "project": "pa" if from_end in act else "pb", "importance_tier": "B"}) + "\n")
PY
}
window() { # window <n> <posiciones>: imprime "<count> <of>"
    mkstore "$1" "${2:-}"
    python3 -I "$BASE" --transcripts-dir "$T/nope" --store "$STORE" --active-project pa | python3 -I -c '
import json, sys
w = json.load(sys.stdin)["s04"]["active_project_in_last20"]
print(w["count"], w["of"])'
}

@test "B02 proyecto activo solo en las posiciones 11-15 desde el final: la ventana de 20 las cuenta" {
    run window 30 11,12,13,14,15
    [ "$output" = "5 20" ]
}

@test "B02 tamaños 0, 19, 20 y 21: la ventana crece hasta 20 y no más" {
    run window 0
    [ "$output" = "0 0" ]
    run window 19 19
    [ "$output" = "1 19" ]
    run window 20 20
    [ "$output" = "1 20" ]
    run window 21 21
    [ "$output" = "0 20" ]
}

@test "B02 la entrada 20 desde el final entra y la 21 no" {
    run window 40 20
    [ "$output" = "1 20" ]
    run window 40 21
    [ "$output" = "0 20" ]
}

# ── B04: bytes exactos que imprime post-compaction.sh ──────────────────────────────────────────
post_bytes() { # post_bytes <script de prueba>: imprime "<bytes> <líneas> <exit>"
    mkstore 1 1
    python3 -I "$BASE" --transcripts-dir "$T/nope" --store "$STORE" --post-script "$1" | python3 -I -c '
import json, sys
s = json.load(sys.stdin)["s04"]
print(s["post_compaction_stdout_bytes"], s.get("post_compaction_stdout_lines"), s["post_compaction_exit"])'
}

@test "B04 un hook que emite tres bytes se mide como 3" {
    printf "printf 'abc'\n" > "$T/post3.sh"
    run post_bytes "$T/post3.sh"
    [ "$output" = "3 0 0" ]
}

@test "B04 salida vacía se mide como 0" {
    printf ":\n" > "$T/post0.sh"
    run post_bytes "$T/post0.sh"
    [ "$output" = "0 0 0" ]
}

@test "B04 UTF-8 multibyte: se miden bytes, no caracteres, y se cuentan las líneas" {
    printf "printf 'ñ日\\\\n'\n" > "$T/postu.sh"
    run post_bytes "$T/postu.sh"
    [ "$output" = "6 1 0" ]
}

# ── B05: bytes de los últimos 30 turnos ────────────────────────────────────────────────────────
# mkturns <n>: n turnos de tamaños desiguales con líneas system (grandes) intercaladas; deja en
# $T/expected la suma de longitudes de las últimas 30 líneas de turno (calculada aparte).
mkturns() {
    python3 -I - "$HOME/.claude/projects/p1/s.jsonl" "$1" "$T/expected" <<'PY'
import json, sys
path, n, exp = sys.argv[1], int(sys.argv[2]), sys.argv[3]
turn_lens = []
with open(path, "w") as f:
    for i in range(n):
        ln = json.dumps({"type": "user" if i % 2 == 0 else "assistant", "message": {"role": "x", "content": "t" * (10 + 7 * i)}})
        f.write(ln + "\n"); turn_lens.append(len(ln))
        f.write(json.dumps({"type": "system", "subtype": "informational", "content": "s" * 500}) + "\n")
open(exp, "w").write(str(sum(turn_lens[-30:])))
PY
}
last30() { # imprime "<medido> <esperado>"
    mkturns "$1"
    reset_log
    printf '{"transcript_path":"%s"}' "$HOME/.claude/projects/p1/s.jsonl" | SAVIA_COMPACT_SHAPE=1 python3 -I "$COL" --event PreCompact --frontend claude-code
    python3 -I -c '
import json, sys
t = json.loads(open(sys.argv[1]).readline())["transcript"]
print(t["last30_turn_bytes"], open(sys.argv[2]).read())' "$SAVIA_COMPACT_SHAPE_LOG" "$T/expected"
}

@test "B05 con 1, 29, 30, 31 y 45 turnos la suma es exactamente la de los últimos 30" {
    local n got exp
    for n in 1 29 30 31 45; do
        read -r got exp <<< "$(last30 $n)"
        [ -n "$got" ] && [ "$got" = "$exp" ] || { echo "n=$n got=$got exp=$exp"; return 1; }
    done
}

@test "B05 treinta turnos pesan más que el último solo" {
    read -r got exp <<< "$(last30 31)"
    last_only=$(python3 -I -c 'import json; print(len(json.dumps({"type":"assistant","message":{"role":"x","content":"t"*(10+7*30)}})))')
    [ "$got" -gt $((last_only * 10)) ]
}

# ── B06 / B07: límites de profundidad y de claves de la forma registrada ───────────────────────
record() { # stdin = carga JSON
    reset_log
    SAVIA_COMPACT_SHAPE=1 python3 -I "$COL" --event PreCompact --frontend claude-code
}
payload_depth() { # payload_depth <profundidad de la hoja> <hoja json>: cadena de objetos k0..k{D-1}
    python3 -I -c '
import json, sys
d, leaf = int(sys.argv[1]), json.loads(sys.argv[2])
v = leaf
for i in reversed(range(d)):
    v = {"k%d" % i: v}
print(json.dumps(v))' "$1" "$2"
}
leaf_shape() { # camino de claves hasta el primer no-objeto y forma de ese nodo
    python3 -I -c '
import json, sys
v = json.loads(open(sys.argv[1]).readline())["payload"]
path = []
while v.get("t") == "object":
    (k, v), = v["keys"].items()
    path.append(k)
print(",".join(path), json.dumps(v, sort_keys=True))' "$SAVIA_COMPACT_SHAPE_LOG"
}

@test "B06 una lista en profundidad 5 se registra como lista; en profundidad 6, como corte" {
    payload_depth 5 '[1,2]' | record
    run leaf_shape
    [ "$output" = 'k0,k1,k2,k3,k4 {"item_types": ["number"], "n": 2, "t": "list"}' ]
    payload_depth 6 '[1,2]' | record
    run leaf_shape
    [ "$output" = 'k0,k1,k2,k3,k4,k5 {"t": "deep"}' ]
}

@test "B06 ocho niveles de objetos: la forma se corta en el marcador y no aparecen claves más profundas" {
    payload_depth 8 '{"k6": {"k7": 1}}' | record
    run leaf_shape
    [ "$output" = 'k0,k1,k2,k3,k4,k5 {"t": "deep"}' ]
    ! grep -q '"k6"\|"k7"' "$SAVIA_COMPACT_SHAPE_LOG"
}

@test "B06 un escalar en profundidad 6 sigue registrándose (el corte es solo para contenedores)" {
    payload_depth 6 '"hoja"' | record
    run leaf_shape
    [ "$output" = 'k0,k1,k2,k3,k4,k5 {"bytes": 4, "t": "str"}' ]
}

nkeys() { # nkeys <n>: objeto plano con n claves f000..; imprime "<n declarado> <claves registradas> <última>"
    python3 -I -c '
import json, sys
print(json.dumps({"f%03d" % i: i for i in range(int(sys.argv[1]))}))' "$1" | record
    python3 -I -c '
import json, sys
p = json.loads(open(sys.argv[1]).readline())["payload"]
print(p["n"], len(p["keys"]), sorted(p["keys"])[-1])' "$SAVIA_COMPACT_SHAPE_LOG"
}

@test "B07 63, 64 y 65 claves: se registran hasta 64 y el total declarado es el real" {
    run nkeys 63
    [ "$output" = "63 63 f062" ]
    run nkeys 64
    [ "$output" = "64 64 f063" ]
    run nkeys 65
    [ "$output" = "65 64 f063" ]
}

@test "B07 con 640 claves el tope sigue siendo 64 y el total declarado, 640" {
    run nkeys 640
    [ "$output" = "640 64 f063" ]
}

@test "B07 un nombre de campo con texto libre se sustituye por <key> y no llega al registro" {
    python3 -I -c '
import json
d = {"f%03d" % i: i for i in range(10)}
d["texto libre SECRETO-B07"] = 1
print(json.dumps(d))' | record
    ! grep -q "SECRETO-B07" "$SAVIA_COMPACT_SHAPE_LOG"
    grep -q '<key>' "$SAVIA_COMPACT_SHAPE_LOG"
}
