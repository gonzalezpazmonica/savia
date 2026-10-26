#!/usr/bin/env bats
# SE-366 — Decision Ledger bitemporal (AC-0..AC-7)
# Ref: docs/specs/SE-366-decision-ledger-bitemporal.spec.md
# CRIT-001: ledgers temporales en /tmp; sin red.

LB="python3 scripts/ledger-bitemporal.py"
VALID_REF="AGENTS.md"

setup() {
    TMPD="$(mktemp -d)"
    export SAVIA_AUDIT_DIR="$TMPD/audit"
    LEDGER="$TMPD/ledger.jsonl"
}

teardown() {
    rm -rf "$TMPD"
}

add_v1() {
    $LB add --ledger "$LEDGER" --predicate "decision:dependencia_modelos" \
        --subject "savia:autonomia" --object "ollama-local" \
        --valid-from 2026-09-01 --origin "test" --source agent \
        --asserted-at 2026-09-01T10:00:00Z \
        --evidence-json "[{\"ref\":\"$VALID_REF\",\"quote\":\"local\",\"chunk_id\":\"as-014\"}]"
}

@test "SE-366 AC-0: add valida schema y genera fact_id secuencial" {
    run add_v1
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"added": "fact-20260901-1"'
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-01 --asserted-at 2026-09-01T11:00:00Z
    echo "$output" | grep -q '"added": "fact-20260901-2"'
}

@test "SE-366 AC-0: add rechaza valid_from invalido (exit 2)" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from ayer
    [ "$status" -eq 2 ]
}

@test "SE-366 AC-0: add rechaza source invalido (exit 2)" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-01 --source robot
    [ "$status" -eq 2 ]
}

@test "SE-366 AC-1: correct cierra fila vieja y crea nueva enlazada (no overwrite)" {
    add_v1 > /dev/null
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --object "glm-local" \
        --asserted-at 2026-09-02T10:00:00Z
    [ "$status" -eq 0 ]
    N=$(wc -l < "$LEDGER")
    [ "$N" -eq 2 ]
    OLD=$(sed -n 1p "$LEDGER")
    NEW=$(sed -n 2p "$LEDGER")
    echo "$OLD" | grep -q '"superseded_at": "2026-09-02T10:00:00Z"'
    echo "$OLD" | grep -q '"object": "ollama-local"'
    echo "$NEW" | grep -q '"supersedes": "fact-20260901-1"'
    echo "$NEW" | grep -q '"object": "glm-local"'
    echo "$NEW" | grep -q '"superseded_at": null'
}

@test "SE-366 AC-1: correct sobre hecho ya cerrado falla (exit 2)" {
    add_v1 > /dev/null
    $LB correct fact-20260901-1 --ledger "$LEDGER" --object x --asserted-at 2026-09-02T10:00:00Z >/dev/null
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --object y --asserted-at 2026-09-03T10:00:00Z
    [ "$status" -eq 2 ]
}

@test "SE-366 AC-2: as-of reconstruye el estado en 3 fechas (3 versiones)" {
    add_v1 > /dev/null
    ID2=$($LB correct fact-20260901-1 --ledger "$LEDGER" --object "v2" --asserted-at 2026-09-02T10:00:00Z | python3 -c "import json,sys; print(json.load(sys.stdin)['new'])")
    ID3=$($LB correct "$ID2" --ledger "$LEDGER" --object "v3" --asserted-at 2026-09-03T10:00:00Z | python3 -c "import json,sys; print(json.load(sys.stdin)['new'])")
    V1=$($LB as-of 2026-09-01 --ledger "$LEDGER" | python3 -c "import json,sys; print(json.load(sys.stdin)['facts'][0]['object'])")
    V2=$($LB as-of 2026-09-02 --ledger "$LEDGER" | python3 -c "import json,sys; print(json.load(sys.stdin)['facts'][0]['object'])")
    V3=$($LB as-of 2026-09-03 --ledger "$LEDGER" | python3 -c "import json,sys; print(json.load(sys.stdin)['facts'][0]['object'])")
    [ "$V1" == "ollama-local" ]
    [ "$V2" == "v2" ]
    [ "$V3" == "v3" ]
}

@test "SE-366 AC-2b: as-of respeta eje mundo (valid_to excluye el hecho)" {
    $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-01 --valid-to 2026-09-05 --asserted-at 2026-09-01T10:00:00Z >/dev/null
    DENTRO=$($LB as-of 2026-09-03 --ledger "$LEDGER" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['facts']))")
    FUERA=$($LB as-of 2026-09-07 --ledger "$LEDGER" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['facts']))")
    [ "$DENTRO" -eq 1 ]
    [ "$FUERA" -eq 0 ]
}

@test "SE-366 AC-3: history expande la cadena completa de versiones" {
    add_v1 > /dev/null
    ID2=$($LB correct fact-20260901-1 --ledger "$LEDGER" --object v2 --asserted-at 2026-09-02T10:00:00Z | python3 -c "import json,sys; print(json.load(sys.stdin)['new'])")
    run $LB history "$ID2" --ledger "$LEDGER"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'fact-20260901-1'
    echo "$output" | grep -q "$ID2"
    NV=$(echo "$output" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['versions']))")
    [ "$NV" -eq 2 ]
}

@test "SE-366 AC-4: evidence lista las filas de evidencia de la version" {
    add_v1 > /dev/null
    run $LB evidence fact-20260901-1 --ledger "$LEDGER"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"chunk_id": "as-014"'
    echo "$output" | grep -q "\"ref\": \"$VALID_REF\""
}

@test "SE-366 AC-5: add con ref local inexistente se rechaza (grounding)" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-01 \
        --evidence-json '[{"ref":"docs/no/existe.md","chunk_id":"x"}]'
    [ "$status" -eq 2 ]
    echo "$output" | grep -q 'ref inexistente'
}

@test "SE-366 AC-5b: --validate detecta ref rota en ledger existente (exit 1)" {
    $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-01 --asserted-at 2026-09-01T10:00:00Z \
        --evidence-json "[{\"ref\":\"$VALID_REF\"}]" >/dev/null
    python3 - "$LEDGER" <<'PY'
import json, sys
path = sys.argv[1]
rows = [json.loads(l) for l in open(path) if l.strip()]
rows[0]["evidence"] = [{"ref": "docs/roto-ya-borrado.md"}]
open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
    run $LB --validate --ledger "$LEDGER"
    [ "$status" -eq 1 ]
}

@test "SE-366: --validate pasa en ledger coherente y detecta fechas incoherentes" {
    $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-01 --asserted-at 2026-09-01T10:00:00Z \
        --evidence-json "[{\"ref\":\"$VALID_REF\"}]" >/dev/null
    run $LB --validate --ledger "$LEDGER"
    [ "$status" -eq 0 ]
    python3 - "$LEDGER" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rows[0]["valid_from"] = "2026-09-09"
rows[0]["valid_to"] = "2026-09-01"
open(sys.argv[1], "w").write(json.dumps(rows[0]) + "\n")
PY
    run $LB --validate --ledger "$LEDGER"
    [ "$status" -eq 1 ]
}

@test "SE-366 AC-6: escritura emite receipt SE-355 (metadata-only)" {
    add_v1 > /dev/null
    $LB correct fact-20260901-1 --ledger "$LEDGER" --object v2 --asserted-at 2026-09-02T10:00:00Z >/dev/null
    R="$SAVIA_AUDIT_DIR/actions.jsonl"
    [ -f "$R" ]
    grep -q '"action":"ledger_bitemporal_add"' "$R"
    grep -q '"action":"ledger_bitemporal_correct"' "$R"
}

@test "SE-366 AC-7: suites SE-355 y SE-364 sin regression" {
    run bats tests/bats/test-se355-audit-receipts.bats
    [ "$status" -eq 0 ]
    run bats tests/bats/test-se364-evidence-loop.bats
    [ "$status" -eq 0 ]
}

# ── Comportamiento: ejes temporales, validación y errores (SE-456) ────────────

@test "SE-366 add: la fila guardada lleva todos los campos con sus valores" {
    run add_v1
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$LEDGER")" -eq 1 ]
    row="$(cat "$LEDGER")"
    [ "$(jq -r .predicate <<<"$row")" = "decision:dependencia_modelos" ]
    [ "$(jq -r .subject <<<"$row")" = "savia:autonomia" ]
    [ "$(jq -r .valid_from <<<"$row")" = "2026-09-01" ]
    [ "$(jq -r .valid_to <<<"$row")" = "null" ]
    [ "$(jq -r .asserted_at <<<"$row")" = "2026-09-01T10:00:00Z" ]
    [ "$(jq -r .superseded_at <<<"$row")" = "null" ]
    [ "$(jq -r .supersedes <<<"$row")" = "null" ]
    [ "$(jq -r .origin <<<"$row")" = "test" ]
    [ "$(jq -r .source <<<"$row")" = "agent" ]
}

@test "SE-366 add: origen por defecto cli, source human aceptado, valid-to 'null' = abierto" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-01 \
        --valid-to null --source human --asserted-at 2026-09-01T10:00:00Z
    [ "$status" -eq 0 ]
    [ "$(jq -r .origin "$LEDGER")" = "cli" ]
    [ "$(jq -r .source "$LEDGER")" = "human" ]
    [ "$(jq -r .valid_to "$LEDGER")" = "null" ]
}

@test "SE-366 add: el contador de fact_id es por día, no global" {
    add_v1 >/dev/null
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-01 \
        --asserted-at 2026-09-03T10:00:00Z
    [ "$(jq -r .added <<<"$output")" = "fact-20260903-1" ]
}

@test "SE-366 add: sin --valid-from, sin predicate/subject/object o con fechas mal formadas → exit 2 y no escribe" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o
    [ "$status" -eq 2 ]
    [[ "$output" == *"add exige --valid-from"* ]]
    run $LB add --ledger "$LEDGER" --predicate p --valid-from 2026-09-01
    [ "$status" -eq 2 ]
    [[ "$output" == *"add exige --predicate --subject --object"* ]]
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-01 --valid-to mañana
    [ "$status" -eq 2 ]
    [[ "$output" == *"--valid-to debe ser YYYY-MM-DD o null"* ]]
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-01 --asserted-at 2026-09-01
    [ "$status" -eq 2 ]
    [[ "$output" == *"--asserted-at debe ser ISO UTC"* ]]
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-13-45
    [ "$status" -eq 2 ]
    [ ! -e "$LEDGER" ]
}

@test "SE-366 add: evidencia que no es array se rechaza; URL se acepta sin comprobar" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-01 --evidence-json '{"ref":"x"}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"debe ser un array"* ]]
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-01 \
        --evidence-json '[{"ref":"https://example.org/x"},{"ref":"http://example.org/y"}]'
    [ "$status" -eq 0 ]
    [ "$(jq '.evidence|length' "$LEDGER")" -eq 2 ]
}

@test "SE-366 correct: valid-from y valid-to cambian; la evidencia previa se hereda; el objeto se conserva" {
    add_v1 >/dev/null
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --valid-from 2026-09-02 --valid-to 2026-12-31 \
        --asserted-at 2026-09-05T10:00:00Z
    [ "$status" -eq 0 ]
    [ "$(jq -r .corrected <<<"$output")" = "fact-20260901-1" ]
    [ "$(jq -r .new <<<"$output")" = "fact-20260905-1" ]
    new="$(sed -n 2p "$LEDGER")"
    [ "$(jq -r .object <<<"$new")" = "ollama-local" ]
    [ "$(jq -r .valid_from <<<"$new")" = "2026-09-02" ]
    [ "$(jq -r .valid_to <<<"$new")" = "2026-12-31" ]
    [ "$(jq -r '.evidence[0].chunk_id' <<<"$new")" = "as-014" ]
    # la fila vieja conserva su valid_from original
    [ "$(jq -r .valid_from <<<"$(sed -n 1p "$LEDGER")")" = "2026-09-01" ]
}

@test "SE-366 correct: --valid-to null reabre un hecho con fin" {
    $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-01 \
        --valid-to 2026-09-30 --asserted-at 2026-09-01T10:00:00Z >/dev/null
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --valid-to null --asserted-at 2026-09-02T10:00:00Z
    [ "$status" -eq 0 ]
    [ "$(jq -r .valid_to <<<"$(sed -n 2p "$LEDGER")")" = "null" ]
    [ "$(jq -r .valid_to <<<"$(sed -n 1p "$LEDGER")")" = "2026-09-30" ]
}

@test "SE-366 correct: nueva evidencia con ref inexistente se rechaza y el ledger queda intacto" {
    add_v1 >/dev/null
    before="$(cat "$LEDGER")"
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --object x --evidence-json '[{"ref":"no/existe.md"}]'
    [ "$status" -eq 2 ]
    [[ "$output" == *"ref inexistente"* ]]
    [ "$(cat "$LEDGER")" = "$before" ]
}

@test "SE-366 correct: fact_id inexistente y sin cambios pedidos → exit 2 con mensaje" {
    add_v1 >/dev/null
    run $LB correct fact-20260901-99 --ledger "$LEDGER" --object x
    [ "$status" -eq 2 ]
    [[ "$output" == *"fact_id no encontrado: fact-20260901-99"* ]]
    run $LB correct fact-20260901-1 --ledger "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"correct exige --object"* ]]
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --object x --asserted-at 2026-09-02T10:00:00Z
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --object y
    [[ "$output" == *"ya esta cerrado"* ]]
}

@test "SE-366 as-of: antes de que Savia lo registrara no existe aunque fuera cierto en el mundo" {
    $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-01-01 \
        --asserted-at 2026-09-10T10:00:00Z >/dev/null
    [ "$($LB as-of 2026-09-09 --ledger "$LEDGER" | jq '.facts|length')" -eq 0 ]
    [ "$($LB as-of 2026-09-10 --ledger "$LEDGER" | jq '.facts|length')" -eq 1 ]
}

@test "SE-366 as-of: aún no válido en el mundo se excluye; los límites valid_from y valid_to son inclusivos" {
    $LB add --ledger "$LEDGER" --predicate p --subject s --object o --valid-from 2026-09-10 \
        --valid-to 2026-09-20 --asserted-at 2026-09-01T10:00:00Z >/dev/null
    [ "$($LB as-of 2026-09-09 --ledger "$LEDGER" | jq '.facts|length')" -eq 0 ]
    [ "$($LB as-of 2026-09-10 --ledger "$LEDGER" | jq '.facts|length')" -eq 1 ]
    [ "$($LB as-of 2026-09-20 --ledger "$LEDGER" | jq '.facts|length')" -eq 1 ]
    [ "$($LB as-of 2026-09-21 --ledger "$LEDGER" | jq '.facts|length')" -eq 0 ]
}

@test "SE-366 as-of: dos hechos independientes aparecen una sola vez cada uno (solo la versión vigente)" {
    add_v1 >/dev/null
    $LB add --ledger "$LEDGER" --predicate q --subject s2 --object o2 --valid-from 2026-09-01 \
        --asserted-at 2026-09-01T11:00:00Z >/dev/null
    $LB correct fact-20260901-1 --ledger "$LEDGER" --object v2 --asserted-at 2026-09-02T10:00:00Z >/dev/null
    run $LB as-of 2026-09-05 --ledger "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$(jq -r .as_of <<<"$output")" = "2026-09-05" ]
    [ "$(jq '.facts|length' <<<"$output")" -eq 2 ]
    [ "$(jq -r '[.facts[].object]|sort|join(",")' <<<"$output")" = "o2,v2" ]
}

@test "SE-366 as-of: fecha mal formada → exit 2" {
    run $LB as-of ayer --ledger "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"as-of exige YYYY-MM-DD"* ]]
}

@test "SE-366 history: la primera versión es la más reciente y encadena supersedes; id desconocido → 2" {
    add_v1 >/dev/null
    ID2="$($LB correct fact-20260901-1 --ledger "$LEDGER" --object v2 --asserted-at 2026-09-02T10:00:00Z | jq -r .new)"
    ID3="$($LB correct "$ID2" --ledger "$LEDGER" --object v3 --asserted-at 2026-09-03T10:00:00Z | jq -r .new)"
    run $LB history "$ID3" --ledger "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$(jq '.versions|length' <<<"$output")" -eq 3 ]
    [ "$(jq -r '.versions[0].object' <<<"$output")" = "v3" ]
    [ "$(jq -r '.versions[2].object' <<<"$output")" = "ollama-local" ]
    run $LB history nada --ledger "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"fact_id no encontrado: nada"* ]]
}

@test "SE-366 evidence: --version elige la versión (1 = la más reciente) y valida el rango" {
    add_v1 >/dev/null
    ID2="$($LB correct fact-20260901-1 --ledger "$LEDGER" --object v2 --asserted-at 2026-09-02T10:00:00Z \
        --evidence-json '[{"ref":"AGENTS.md","chunk_id":"nueva"}]' | jq -r .new)"
    [ "$($LB evidence "$ID2" --ledger "$LEDGER" | jq -r '.evidence[0].chunk_id')" = "nueva" ]
    [ "$($LB evidence "$ID2" --ledger "$LEDGER" --version 1 | jq -r '.evidence[0].chunk_id')" = "nueva" ]
    run $LB evidence "$ID2" --ledger "$LEDGER" --version 2
    [ "$(jq -r .fact_id <<<"$output")" = "fact-20260901-1" ]
    [ "$(jq -r '.evidence[0].chunk_id' <<<"$output")" = "as-014" ]
    run $LB evidence "$ID2" --ledger "$LEDGER" --version 3
    [ "$status" -eq 2 ]
    [[ "$output" == *"fuera de rango 1..2"* ]]
    run $LB evidence "$ID2" --ledger "$LEDGER" --version 0
    [ "$status" -eq 2 ]
}

@test "SE-366 validate: ledger vacío o inexistente es válido con 0 hechos" {
    run $LB --validate --ledger "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$(jq -r .validate <<<"$output")" = "OK" ]
    [ "$(jq -r .facts <<<"$output")" -eq 0 ]
}

@test "SE-366 validate: cada incoherencia produce su mensaje concreto" {
    cat > "$LEDGER" <<'EOF'
{"fact_id":"f1","predicate":"p","subject":"s","object":"o","valid_from":"2026-09-09","valid_to":"2026-09-01","asserted_at":"2026-09-10T10:00:00Z","superseded_at":"2026-09-01T00:00:00Z","supersedes":"fantasma","evidence":[],"origin":"x","source":"agent"}
{"fact_id":"f2","predicate":"p","subject":"s","object":"o","valid_from":"ayer","valid_to":"mañana","asserted_at":"mal","superseded_at":"mal","supersedes":null,"evidence":[],"origin":"x","source":"agent"}
{"fact_id":"f3","predicate":"p"}
EOF
    run $LB --validate --ledger "$LEDGER"
    [ "$status" -eq 1 ]
    [ "$(jq -r .validate <<<"$output")" = "FAIL" ]
    msgs="$(jq -r '.errors[]' <<<"$output")"
    [[ "$msgs" == *"f1: valid_to < valid_from"* ]]
    [[ "$msgs" == *"f1: superseded_at < asserted_at"* ]]
    [[ "$msgs" == *"f1: supersedes a id inexistente fantasma"* ]]
    [[ "$msgs" == *"f2: valid_from invalido"* ]]
    [[ "$msgs" == *"f2: valid_to invalido"* ]]
    [[ "$msgs" == *"f2: asserted_at invalido"* ]]
    [[ "$msgs" == *"f2: superseded_at invalido"* ]]
    [[ "$msgs" == *"f3: falta campo object"* ]]
    # los campos correctos no generan error
    [[ "$msgs" != *"f1: falta campo"* ]]
    [[ "$msgs" != *"f1: valid_from invalido"* ]]
}

@test "SE-366 validate: un supersedes que apunta a una fila posterior del fichero es válido" {
    cat > "$LEDGER" <<'EOF'
{"fact_id":"b","predicate":"p","subject":"s","object":"o","valid_from":"2026-09-01","valid_to":null,"asserted_at":"2026-09-02T10:00:00Z","superseded_at":null,"supersedes":"a","evidence":[],"origin":"x","source":"agent"}
{"fact_id":"a","predicate":"p","subject":"s","object":"o","valid_from":"2026-09-01","valid_to":null,"asserted_at":"2026-09-01T10:00:00Z","superseded_at":"2026-09-02T10:00:00Z","supersedes":null,"evidence":[],"origin":"x","source":"agent"}
EOF
    run $LB --validate --ledger "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$(jq -r .facts <<<"$output")" -eq 2 ]
}

@test "SE-366 ledger con línea JSON corrupta → exit 2 con fichero y número de línea" {
    printf '{"fact_id":"a"}\nesto no es json\n' > "$LEDGER"
    run $LB as-of 2026-09-01 --ledger "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ledger.jsonl:2: JSON invalido"* ]]
}

@test "SE-366 sin subcomando → exit 2 con ayuda" {
    run $LB --ledger "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage"* ]]
}

@test "SE-366 add: intervalo invertido (valid_to < valid_from) se rechaza y no se escribe" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-10 --valid-to 2026-09-01 --asserted-at 2026-09-01T10:00:00Z
    [ "$status" -eq 2 ]
    [[ "$output" == *"valid_to (2026-09-01) anterior a valid_from (2026-09-10)"* ]]
    [ ! -e "$LEDGER" ]
}

@test "SE-366 add: valid_to igual a valid_from es válido (día único)" {
    run $LB add --ledger "$LEDGER" --predicate p --subject s --object o \
        --valid-from 2026-09-10 --valid-to 2026-09-10 --asserted-at 2026-09-01T10:00:00Z
    [ "$status" -eq 0 ]
}

@test "SE-366 correct: no puede dejar un intervalo invertido ni fechas mal formadas; el ledger no cambia" {
    add_v1 >/dev/null
    before="$(cat "$LEDGER")"
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --valid-to 2026-01-01 --asserted-at 2026-09-02T10:00:00Z
    [ "$status" -eq 2 ]
    [[ "$output" == *"anterior a valid_from"* ]]
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --valid-from 2026-12-01 --valid-to 2026-10-01 --asserted-at 2026-09-02T10:00:00Z
    [ "$status" -eq 2 ]
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --valid-from ayer --asserted-at 2026-09-02T10:00:00Z
    [ "$status" -eq 2 ]
    [[ "$output" == *"--valid-from debe ser YYYY-MM-DD"* ]]
    run $LB correct fact-20260901-1 --ledger "$LEDGER" --valid-to mañana --asserted-at 2026-09-02T10:00:00Z
    [ "$status" -eq 2 ]
    [[ "$output" == *"--valid-to debe ser YYYY-MM-DD o null"* ]]
    [ "$(cat "$LEDGER")" = "$before" ]
}
