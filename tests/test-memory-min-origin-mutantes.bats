#!/usr/bin/env bats
# SE-352 — tests que matan a los mutantes supervivientes O04, O05 y O07 de la auditoría independiente
# del 2026-11-14 (scripts/memory-origin.py). Se ejecuta el filtro directamente, con almacén sintético.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FILTER="$REPO_ROOT/scripts/memory-origin.py"

setup() {
    STORE="$BATS_TEST_TMPDIR/store.jsonl"
    : > "$STORE"
}

# entry <topic_key> <title> <origin> [valid_to]: añade una línea al almacén sintético.
entry() {
    python3 -I -c '
import json, sys
e = {"ts": "2026-11-01T00:00:00Z", "type": "decision", "topic_key": sys.argv[1], "title": sys.argv[2],
     "content": "x", "rev": 1}
if sys.argv[3] != "-":
    e["origin"] = sys.argv[3]
if len(sys.argv) > 4:
    e["valid_to"] = sys.argv[4]
print(json.dumps(e))' "$@" >> "$STORE"
}

# filtra <min-origin> <json de un resultado>: imprime los títulos que sobreviven, separados por coma.
filtra() {
    printf '{"results":[%s]}' "$2" | python3 -I "$FILTER" filter --store "$STORE" --min-origin "$1" \
        | python3 -I -c 'import json,sys; print(",".join(r["title"] for r in json.load(sys.stdin)["results"]))'
}

# --- O04: topic y título resuelven a orígenes distintos → manda el de menor rango --------------
@test "O04 topic→owner y título→untrusted (conflicto): se descarta con umbral owner" {
    entry t/solo-topic "otro-titulo" owner
    entry t/otra-clave "titulo-conflicto" untrusted
    run filtra owner '{"title":"titulo-conflicto","topic_key":"t/solo-topic"}'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "O04 el conflicto es simétrico: topic→untrusted y título→owner también se descarta" {
    entry t/solo-topic "otro-titulo" untrusted
    entry t/otra-clave "titulo-conflicto" owner
    run filtra owner '{"title":"titulo-conflicto","topic_key":"t/solo-topic"}'
    [ "$output" = "" ]
}

@test "O04 control: topic y título coinciden en owner → pasa con umbral owner" {
    entry t/a "titulo-a" owner
    run filtra owner '{"title":"titulo-a","topic_key":"t/a"}'
    [ "$output" = "titulo-a" ]
}

@test "O04 control: solo resuelve el topic (owner) → pasa; solo el título (untrusted) → no pasa" {
    entry t/solo "otro" owner
    run filtra owner '{"title":"sin-resolver","topic_key":"t/solo"}'
    [ "$output" = "sin-resolver" ]
    entry t/otra "solo-titulo" untrusted
    run filtra owner '{"title":"solo-titulo","topic_key":"t/no-existe"}'
    [ "$output" = "" ]
}

# --- O05: una revisión sustituida (valid_to) nunca pasa, ni siquiera con origen alto -----------
@test "O05 resultado owner con valid_to y umbral owner: se descarta" {
    run filtra owner '{"title":"sustituida","origin":"owner","valid_to":"2026-11-02T00:00:00Z"}'
    [ "$output" = "" ]
}

@test "O05 control: el mismo resultado owner vigente (sin valid_to) pasa con umbral owner" {
    run filtra owner '{"title":"vigente","origin":"owner"}'
    [ "$output" = "vigente" ]
}

@test "O05 resultado sin origen propio con valid_to: se descarta aunque el almacén lo dé por owner" {
    entry t/v "vigente-en-almacen" owner
    run filtra untrusted '{"title":"vigente-en-almacen","topic_key":"t/v","valid_to":"2026-11-02T00:00:00Z"}'
    [ "$output" = "" ]
}

# --- O07: un origen desconocido del resultado cuenta como untrusted ----------------------------
@test "O07 origen desconocido con umbral owner: se descarta" {
    run filtra owner '{"title":"raro","origin":"inventado"}'
    [ "$output" = "" ]
}

@test "O07 origen desconocido con umbral agent: se descarta" {
    run filtra agent '{"title":"raro","origin":"inventado"}'
    [ "$output" = "" ]
}

@test "O07 origen desconocido con umbral untrusted: pasa, como untrusted" {
    run filtra untrusted '{"title":"raro","origin":"inventado"}'
    [ "$output" = "raro" ]
}

@test "O07 origen vacío o nulo cuenta como untrusted: no pasa con owner, sí con untrusted" {
    run filtra owner '{"title":"vacio","origin":""}'
    [ "$output" = "" ]
    run filtra owner '{"title":"nulo","origin":null}'
    [ "$output" = "" ]
    run filtra untrusted '{"title":"vacio","origin":""}'
    [ "$output" = "vacio" ]
}

@test "O07 origen conocido a ambos lados del umbral: owner pasa con owner, agent no" {
    run filtra owner '{"title":"dueno","origin":"owner"}'
    [ "$output" = "dueno" ]
    run filtra owner '{"title":"agente","origin":"agent"}'
    [ "$output" = "" ]
    run filtra agent '{"title":"agente","origin":"agent"}'
    [ "$output" = "agente" ]
}

@test "O07 origen ausente y sin entrada en el almacén: untrusted, no pasa con owner" {
    run filtra owner '{"title":"huerfano","topic_key":"t/nada"}'
    [ "$output" = "" ]
}
