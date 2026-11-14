#!/usr/bin/env bats
# SE-529 S2/S4 — tests que matan a los mutantes supervivientes I03, I04, I07 e I10 de la auditoría
# independiente del 2026-11-14. Cada test indica el mutante que mata. Fixtures sintéticos.
# El directorio temporal es el de bats (BATS_TEST_TMPDIR): no hay borrado recursivo en este fichero.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"

setup() {
    TMP="$BATS_TEST_TMPDIR"
    export PROJECT_ROOT="$TMP"
    export HOME="$TMP/home"
    export CLAUDE_PROJECT_DIR="$TMP/workspace"
    export SAVIA_TEST_MODE=true
    unset SAVIA_REINJECT_MAX_BYTES
    mkdir -p "$TMP/output" "$CLAUDE_PROJECT_DIR" "$HOME"
    STORE="$TMP/output/.memory-store.jsonl"
    POST="${POST_COMPACTION_SCRIPT:-$REPO_ROOT/scripts/post-compaction.sh}"
    MS="$REPO_ROOT/scripts/memory-store.sh"
    SAVER="$REPO_ROOT/scripts/compaction-summary-save.py"
    WORK="$TMP/work"; mkdir -p "$WORK"
    printf 'project: alpha\n' > "$WORK/CLAUDE.local.md"
}

# mkstore <spec>...: cada spec es tier:tipo:título[:expires_at]; todas del proyecto alpha.
mkstore() {
    python3 -I - "$STORE" "$@" <<'PY'
import json, sys
rows = []
for i, spec in enumerate(sys.argv[2:]):
    p = spec.split(":", 3)
    r = {"ts": "2026-10-%02dT00:00:00Z" % (i + 1), "type": p[1], "title": p[2], "content": "x",
         "project": "alpha", "importance_tier": p[0], "topic_key": "k/%d" % i}
    if len(p) > 3:
        r["expires_at"] = p[3]
    rows.append(r)
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
}
run_post() { cd "$WORK" && run bash "$POST"; }
line_of() { printf '%s\n' "$output" | grep "^$1"; }

# --- I03: el umbral del 30 % es estricto (a partir de >30 %) -----------------------------------
# 10 entradas: 3 de tier A y tipo decision = exactamente el 30 %: la regla estricta NO se activa.
@test "I03 exactamente 30 %: las A de tipo decisión siguen fijadas" {
    mkstore A:decision:AD1 A:decision:AD2 A:decision:AD3 B:discovery:B1 B:discovery:B2 B:discovery:B3 B:discovery:B4 B:discovery:B5 B:discovery:B6 B:discovery:B7
    run_post
    [ "$status" -eq 0 ]
    fijado=$(line_of 'Fijado:')
    [[ "$fijado" == *AD1* && "$fijado" == *AD2* && "$fijado" == *AD3* ]]
}

@test "I03 por debajo del 30 %: las A de tipo decisión están fijadas" {
    mkstore A:decision:AD1 A:decision:AD2 B:discovery:B1 B:discovery:B2 B:discovery:B3 B:discovery:B4 B:discovery:B5 B:discovery:B6 B:discovery:B7 B:discovery:B8
    run_post
    fijado=$(line_of 'Fijado:')
    [[ "$fijado" == *AD1* && "$fijado" == *AD2* ]]
}

# 4 de 13 = 30,8 %: pasa del umbral, solo quedan fijadas las A de tipo feedback/correction.
@test "I03 por encima del 30 %: solo las A de feedback quedan fijadas y las de decisión pasan a recientes" {
    mkstore A:decision:AD1 A:decision:AD2 A:decision:AD3 A:feedback:AF1 B:discovery:B1 B:discovery:B2 B:discovery:B3 B:discovery:B4 B:discovery:B5 B:discovery:B6 B:discovery:B7 B:discovery:B8 B:discovery:B9
    run_post
    fijado=$(line_of 'Fijado:')
    reciente=$(line_of 'Reciente:')
    [[ "$fijado" == *AF1* ]]
    [[ "$fijado" != *AD1* && "$fijado" != *AD2* && "$fijado" != *AD3* ]]
    [[ "$reciente" == *AD1* && "$reciente" == *AD2* && "$reciente" == *AD3* ]]
}

# --- I04: lo caducado no se reinyecta ni cuenta en el denominador ------------------------------
@test "I04 caducada, futura y sin caducidad: solo la caducada se omite" {
    mkstore B:discovery:VENCIDA:2000-01-01T00:00:00Z B:discovery:FUTURA:2999-01-01T00:00:00Z B:discovery:SINCAD
    run_post
    [ "$status" -eq 0 ]
    [[ "$output" == *FUTURA* && "$output" == *SINCAD* ]]
    [[ "$output" != *VENCIDA* ]]
}

@test "I04 las caducadas no entran en el denominador del umbral de fijadas" {
    # Vigentes: 3 A decision + 4 B = 3/7 = 43 % (estricto). Con las 3 caducadas contadas serían 3/10 = 30 %.
    mkstore A:decision:AD1 A:decision:AD2 A:decision:AD3 B:discovery:B1 B:discovery:B2 B:discovery:B3 B:discovery:B4 \
        B:discovery:V1:2000-01-01T00:00:00Z B:discovery:V2:2000-01-01T00:00:00Z B:discovery:V3:2000-01-01T00:00:00Z
    run_post
    [[ "$output" != *V1* && "$output" != *V2* && "$output" != *V3* ]]
    reciente=$(line_of 'Reciente:')
    [[ "$reciente" == *AD1* ]]
    ! printf '%s\n' "$output" | grep -q '^Fijado:'
}

# --- I07: igualdad exacta en bytes de --max-bytes ----------------------------------------------
# Para cada prefijo de k líneas con B bytes (terminador incluido), la salida con N=B-1, B y B+1 es
# exactamente el prefijo más largo de líneas completas que no pasa de N bytes (oráculo independiente).
ms_store() {
    python3 -I - "$STORE" <<'PY'
import json, sys
rows = [{"ts": "2026-10-%02dT00:00:00Z" % (i + 1), "type": "decision", "title": t, "topic_key": "k%d" % i,
         "project": "alpha", "content": t, "rev": 1}
        for i, t in enumerate(["ascii-uno", "ñandú-日本-dos", "ascii-tres"])]
open(sys.argv[1], "w").write("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows))
PY
}
prefix_le() { # prefix_le <N> <fichero>: líneas completas cuyo total acumulado <= N bytes
    python3 -I -c '
import sys
n, out, used = int(sys.argv[1]), [], 0
for ln in open(sys.argv[2], "rb").read().splitlines(keepends=True):
    if used + len(ln) > n:
        break
    out.append(ln); used += len(ln)
sys.stdout.buffer.write(b"".join(out))' "$1" "$2"
}
check_cap() { # check_cap <subcomando y args sin --max-bytes>
    bash "$MS" "$@" > "$TMP/full.txt" 2>/dev/null
    [ "$(wc -l < "$TMP/full.txt")" -ge 3 ]
    local k b d
    for k in 1 2 3; do
        b=$(head -n "$k" "$TMP/full.txt" | wc -c)
        for d in -1 0 1; do
            bash "$MS" "$@" --max-bytes $((b + d)) > "$TMP/n.txt" 2>/dev/null
            prefix_le $((b + d)) "$TMP/full.txt" > "$TMP/exp.txt"
            cmp "$TMP/n.txt" "$TMP/exp.txt"
        done
    done
}

@test "I07 context: con N-1, N y N+1 bytes la línea que cabe justa entra (ASCII y multibyte)" {
    ms_store
    check_cap context
}

@test "I07 search: con N-1, N y N+1 bytes la línea que cabe justa entra (ASCII y multibyte)" {
    ms_store
    python3 -I - "$STORE" <<'PY'
import json, sys
rows = [{"ts": "2026-10-%02dT00:00:00Z" % (i + 1), "type": "decision", "title": "hallazgo-" + t, "topic_key": "s%d" % i,
         "project": "alpha", "content": "hallazgo " + t, "rev": 1} for i, t in enumerate(["uno", "ñandú-日本", "tres"])]
open(sys.argv[1], "w").write("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows))
PY
    check_cap search hallazgo --mode grep
}

@test "I07 sin ninguna línea que quepa: no emite nada y avisa por stderr" {
    ms_store
    first=$(bash "$MS" context 2>/dev/null | head -n 1 | wc -c)
    run bash -c "bash '$MS' context --max-bytes $((first - 1)) 2>'$TMP/err.txt' >'$TMP/out.txt'; echo rc=\$?"
    [ "$output" = "rc=0" ]
    [ ! -s "$TMP/out.txt" ]
    grep -q "menor que la primera línea" "$TMP/err.txt"
}

# --- I10: el guardador acota su carga a 4 MiB por sí mismo -------------------------------------
# JSON válido con un resumen pequeño y relleno en un campo ajeno, de tamaño total exacto $1 (bytes).
sized_payload() {
    python3 -I -c '
import json, sys
size = int(sys.argv[1])
base = {"session_id": "sesion-i10", "compact_summary": "Resumen pequeño I10", "relleno": ""}
n = size - len(json.dumps(base, ensure_ascii=False).encode())
base["relleno"] = "r" * n
data = json.dumps(base, ensure_ascii=False)
assert len(data.encode()) == size, (len(data.encode()), size)
sys.stdout.write(data)' "$1" > "$TMP/payload.json"
}
save_direct() { run python3 -I "$SAVER" --project alpha < "$TMP/payload.json"; }

@test "I10 un byte por encima de 4 MiB: el guardador lo rechaza y no escribe" {
    sized_payload $((4 * 1024 * 1024 + 1))
    save_direct
    [ "$status" -eq 0 ]
    [[ "$output" == *"no disponible"*"no es JSON legible"* ]]
    [ ! -s "$STORE" ]
}

@test "I10 exactamente 4 MiB: sí se guarda" {
    sized_payload $((4 * 1024 * 1024))
    save_direct
    [ "$status" -eq 0 ]
    [ "$output" = "Resumen compactado: confirmado, guardado." ]
    grep -q 'Resumen pequeño I10' "$STORE"
}

@test "I10 a mitad del tope duplicado (6 MiB): también se rechaza" {
    sized_payload $((6 * 1024 * 1024))
    save_direct
    [[ "$output" == *"no disponible"* ]]
    [ ! -s "$STORE" ]
}
