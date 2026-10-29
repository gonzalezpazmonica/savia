#!/usr/bin/env bats
# SCL-001 S1 — Captura canónica del bucle de aprendizaje
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (AC-1.1..1.5)

set -uo pipefail

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

setup() {
  SCRIPT="$REPO_ROOT/scripts/learning-proposal.sh"
  TMPD="$(mktemp -d -t scl-s1-XXXXXX)"
  PROPOSALS="$TMPD/proposals"
  GRAPH="$TMPD/graph.jsonl"
  echo "evidence-one" > "$TMPD/evidence1.txt"
  echo "evidence-two" > "$TMPD/evidence2.txt"
  mkdir -p "$PROPOSALS"
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "AC-1.1: error reconocido genera UNA propuesta con evidencia+diagnostico+cambio no vacios" {
  run bash "$SCRIPT" --origin "ledger reconoce error X" \
    --evidence "$TMPD/evidence1.txt" \
    --diagnosis "misma causa raiz en dos tareas" \
    --change "anadir regla de revision de cause-root" \
    --target criterio --output-dir "$PROPOSALS" --graph-index "$GRAPH"
  [ "$status" -eq 0 ]
  file=$(echo "$output" | grep -oP 'CREATED: \K.*' | head -1)
  [ -f "$file" ]
  grep -q "^## Evidencia" "$file"
  grep -q "^## Diagnóstico" "$file"
  grep -q "^## Cambio propuesto" "$file"
  grep -qE "^id: LP-[0-9]{8}-[0-9a-f]{8}" "$file"
  grep -q "^provenance: INFERRED" "$file"
  grep -q "^lifecycle: proposed" "$file"
  # diagnóstico y cambio no vacíos
  awk '/^## Diagnóstico/{f=1;next}/^## Cambio propuesto/{f=0} f && NF{g=1} END{exit !g}' "$file"
  awk '/^## Cambio propuesto/{f=1;next}/^## Destino/{f=0} f && NF{g=1} END{exit !g}' "$file"
}

@test "AC-1.2: decision que contradice CRIT genera propuesta de evolucion marcando origen" {
  run bash "$SCRIPT" --origin "operadora decide X contrario a CRIT-007" \
    --evidence "$TMPD/evidence2.txt" \
    --diagnosis "CRIT-007 impide el flujo observado" \
    --change "evolucionar CRIT-007 (no sobrescribir)" \
    --target criterio --trigger contradiction --output-dir "$PROPOSALS" --graph-index "$GRAPH"
  [ "$status" -eq 0 ]
  file=$(echo "$output" | grep -oP 'CREATED: \K.*' | head -1)
  grep -q "CRIT-007" "$file"
  grep -q "evolucionar" "$file"
  grep -q "^origin: operadora decide X contrario a CRIT-007" "$file"
}

@test "AC-1.3: idempotencia — mismo hash de evidencia en 24h produce como maximo 1 propuesta" {
  run bash "$SCRIPT" --origin "a" --evidence "$TMPD/evidence1.txt" \
    --diagnosis "d" --change "c" --target skill \
    --output-dir "$PROPOSALS" --graph-index "$GRAPH"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --origin "a" --evidence "$TMPD/evidence1.txt" \
    --diagnosis "d" --change "c" --target skill \
    --output-dir "$PROPOSALS" --graph-index "$GRAPH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DUPLICATE"* ]]
  count=$(ls "$PROPOSALS"/*.md | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "AC-1.4: propuesta registrada en el grafo como learning_proposal con relaciones tipadas" {
  run bash "$SCRIPT" --origin "a" --evidence "$TMPD/evidence1.txt" \
    --diagnosis "d" --change "c" --target memoria \
    --output-dir "$PROPOSALS" --graph-index "$GRAPH"
  [ "$status" -eq 0 ]
  [ -f "$GRAPH" ]
  python3 - "$GRAPH" <<'PY'
import json, sys
entry = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][0]
assert entry["type"] == "learning_proposal", entry
assert entry["provenance"] == "INFERRED"
assert "proposes_change" in entry["relations"]
assert "evidence_from" in entry["relations"]
assert entry["relations"]["evidence_from"], "evidence_from no debe estar vacio"
PY
}

@test "AC-1.5: propuesta legible con cat — id, origen y cambio sin ejecutar scripts" {
  run bash "$SCRIPT" --origin "cat-test" --evidence "$TMPD/evidence1.txt" \
    --diagnosis "d" --change "cambio visible por cat" --target spec \
    --output-dir "$PROPOSALS" --graph-index "$GRAPH"
  [ "$status" -eq 0 ]
  file=$(echo "$output" | grep -oP 'CREATED: \K.*' | head -1)
  content=$(cat "$file")
  [[ "$content" == *"id: LP-"* ]]
  [[ "$content" == *"origin: cat-test"* ]]
  [[ "$content" == *"## Cambio propuesto"* ]]
  [[ "$content" == *"cambio visible por cat"* ]]
}

# ── S03k: validación de entrada, idempotencia y formatos de salida ──

lp() { bash "$SCRIPT" --origin "${O:-o}" --evidence "${E:-$TMPD/evidence1.txt}" --diagnosis "d" --change "c" --target "${T:-skill}" --output-dir "$PROPOSALS" --graph-index "$GRAPH" "$@"; }

@test "S03k lp: faltan argumentos obligatorios → uso y exit 2" {
  run bash "$SCRIPT" --origin "x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--origin"* ]]
  [ ! -e "$GRAPH" ]
}

@test "S03k lp: --help imprime la cabecera y sale 2" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"learning-proposal.sh"* ]]
}

@test "S03k lp: target fuera de la lista se rechaza con exit 2 y no escribe nada" {
  T=otro run lp
  [ "$status" -eq 2 ]
  [[ "$output" == *"--target debe ser"* ]]
  [ -z "$(ls "$PROPOSALS")" ]
}

@test "S03k lp: los cuatro targets válidos se aceptan" {
  for t in criterio memoria skill spec; do
    echo "ev-$t" > "$TMPD/ev-$t.txt"
    E="$TMPD/ev-$t.txt" T=$t run lp
    [ "$status" -eq 0 ]
  done
  [ "$(ls "$PROPOSALS" | wc -l)" -eq 4 ]
}

@test "S03k lp: --criterion-id exige target criterio y formato CRIT-NNN" {
  T=skill run lp --criterion-id CRIT-007
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires --target criterio"* ]]
  T=criterio run lp --criterion-id CRIT-7
  [ "$status" -eq 2 ]
  [[ "$output" == *"must match CRIT-XXX"* ]]
  T=criterio run lp --criterion-id CRIT-0071
  [ "$status" -eq 2 ]
  T=criterio run lp --criterion-id CRIT-007
  [ "$status" -eq 0 ]
  grep -q '^criterion_id: CRIT-007$' "$PROPOSALS"/*.md
}

@test "S03k lp: --confidence solo alta|media|baja" {
  run lp --confidence total
  [ "$status" -eq 2 ]
  [[ "$output" == *"--confidence debe ser"* ]]
  run lp --confidence media
  [ "$status" -eq 0 ]
  grep -q '^confidence: media$' "$PROPOSALS"/*.md
}

@test "S03k lp: --when con salto de línea se rechaza (inyectaría claves en el frontmatter)" {
  run lp --when $'cuando\nlifecycle: active'
  [ "$status" -eq 2 ]
  [[ "$output" == *"saltos de línea"* ]]
  [ -z "$(ls "$PROPOSALS")" ]
}

@test "S03k lp: --when con carácter de control o de más de 200 caracteres se rechaza" {
  run lp --when $'a\tb'
  [ "$status" -eq 2 ]
  [[ "$output" == *"caracteres de control"* ]]
  run lp --when "$(printf 'x%.0s' $(seq 1 201))"
  [ "$status" -eq 2 ]
  [[ "$output" == *"200 caracteres"* ]]
  run lp --when "$(printf 'x%.0s' $(seq 1 200))"
  [ "$status" -eq 0 ]
}

@test "S03k lp: --when se entrecomilla en YAML y escapa comillas y barras" {
  run lp --when 'si dice "hola" y \ barra'
  [ "$status" -eq 0 ]
  grep -qF 'when: "si dice \"hola\" y \\ barra"' "$PROPOSALS"/*.md
}

@test "S03k lp: sin --when la sección dice que falta la condición de uso" {
  run lp
  [ "$status" -eq 0 ]
  grep -q 'sin condición de uso declarada' "$PROPOSALS"/*.md
  grep -q '^when: $' "$PROPOSALS"/*.md
}

@test "S03k lp: --confidence se muestra junto a la condición" {
  run lp --when "en revisión" --confidence alta
  [ "$status" -eq 0 ]
  grep -q 'en revisión · confianza: alta' "$PROPOSALS"/*.md
}

@test "S03k lp: evidencia inexistente sin hash → exit 3 y no crea propuesta" {
  E="$TMPD/no-existe.txt" run lp
  [ "$status" -eq 3 ]
  [[ "$output" == *"evidence path not found"* ]]
  [ -z "$(ls "$PROPOSALS")" ]
  [ ! -e "$GRAPH" ]
}

@test "S03k lp: evidencia con hash explícito no necesita que el fichero exista" {
  E="ruta/inexistente.log:abc123" run lp
  [ "$status" -eq 0 ]
  grep -q '^ruta/inexistente.log:abc123$' "$PROPOSALS"/*.md
}

@test "S03k lp: el hash de evidencia no depende del orden de las entradas" {
  run lp --evidence "$TMPD/evidence1.txt,$TMPD/evidence2.txt"
  h1=$(echo "$output" | grep -oP '^evidence_hash: \K.*')
  run bash "$SCRIPT" --origin o --evidence "$TMPD/evidence2.txt,$TMPD/evidence1.txt" --diagnosis d --change c --target skill --output-dir "$TMPD/otro" --graph-index "$TMPD/g2.jsonl"
  h2=$(echo "$output" | grep -oP '^evidence_hash: \K.*')
  [ -n "$h1" ]
  [ "$h1" = "$h2" ]
}

@test "S03k lp: otra evidencia distinta da otro hash y no cuenta como duplicado" {
  run lp
  [ "$status" -eq 0 ]
  E="$TMPD/evidence2.txt" run lp
  [ "$status" -eq 0 ]
  [ "$(ls "$PROPOSALS" | wc -l)" -eq 2 ]
}

@test "S03k lp: el duplicado imprime la ruta existente y no añade entrada al grafo" {
  run lp
  [ "$status" -eq 0 ]
  first=$(echo "$output" | grep -oP 'CREATED: \K.*')
  lines_before=$(wc -l < "$GRAPH")
  run lp
  [ "$status" -eq 1 ]
  [[ "$output" == *"$first"* ]]
  [ "$(wc -l < "$GRAPH")" -eq "$lines_before" ]
}

@test "S03k lp: una propuesta de hace más de 24 h no bloquea una nueva" {
  run lp
  [ "$status" -eq 0 ]
  f=$(echo "$output" | grep -oP 'CREATED: \K.*')
  old=$(date -u -d '30 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  sed -i "s/^created_utc: .*/created_utc: $old/" "$f"
  run lp --id LP-nueva-prueba
  [ "$status" -eq 0 ]
  [ -f "$PROPOSALS/LP-nueva-prueba.md" ]
}

@test "S03k lp: --id fuerza el identificador y el nombre de fichero" {
  run lp --id LP-forzado
  [ "$status" -eq 0 ]
  [ -f "$PROPOSALS/LP-forzado.md" ]
  grep -q '^id: LP-forzado$' "$PROPOSALS/LP-forzado.md"
}

@test "S03k lp: el id por defecto lleva la fecha UTC y 8 caracteres del hash" {
  run lp
  id=$(echo "$output" | grep -oP '^id: \K.*')
  hash=$(echo "$output" | grep -oP '^evidence_hash: \K.*')
  [ "$id" = "LP-$(date -u +%Y%m%d)-${hash:0:8}" ]
}

@test "S03k lp: --expected-p-consistent aparece en frontmatter y en la métrica" {
  run lp --expected-p-consistent 0.8
  grep -q '^expected_p_consistent: 0.8$' "$PROPOSALS"/*.md
  grep -q 'p_consistent esperado: 0.8' "$PROPOSALS"/*.md
}

@test "S03k lp: sin baseline la métrica lo declara" {
  run lp
  grep -q 'sin baseline declarado' "$PROPOSALS"/*.md
}

@test "S03k lp: el trigger por defecto es ledger y se puede cambiar" {
  run lp
  grep -q '^trigger: ledger$' "$PROPOSALS"/*.md
  E="$TMPD/evidence2.txt" run lp --trigger recurrence
  f=$(echo "$output" | grep -oP 'CREATED: \K.*')
  grep -q '^trigger: recurrence$' "$f"
}

@test "S03k lp: la entrada del grafo es JSON válido con evidence_from de cada fichero" {
  run lp --evidence "$TMPD/evidence1.txt,$TMPD/evidence2.txt"
  [ "$status" -eq 0 ]
  python3 - "$GRAPH" "$TMPD" <<'PY'
import json, sys
e = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
assert e["id"].startswith("LP-")
assert e["lifecycle"] == "proposed"
assert len(e["relations"]["evidence_from"]) == 2, e
assert e["relations"]["proposes_change"] == "skill"
PY
}

@test "S03k lp: un origen con comillas deja el índice del grafo en JSON válido" {
  O='dijo "no" aquí' run lp
  [ "$status" -eq 0 ]
  python3 -c "import json,sys; [json.loads(l) for l in open(sys.argv[1]) if l.strip()]" "$GRAPH"
}

@test "S03k lp: cada propuesta añade exactamente una línea al grafo" {
  run lp
  E="$TMPD/evidence2.txt" run lp
  [ "$(wc -l < "$GRAPH")" -eq 2 ]
}

@test "S03k lp: --persist con un persistidor que falla informa persisted: false" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TMPD/persist.sh"
  SCL_PERSIST_SCRIPT="$TMPD/persist.sh" run lp --persist
  [ "$status" -eq 0 ]
  [[ "$output" == *"persisted: false"* ]]
}

@test "S03k lp: --persist con un persistidor correcto recibe --file y informa persisted: true" {
  printf '#!/usr/bin/env bash\necho "$@" > "%s/args"\nexit 0\n' "$TMPD" > "$TMPD/persist.sh"
  SCL_PERSIST_SCRIPT="$TMPD/persist.sh" run lp --persist
  [[ "$output" == *"persisted: true"* ]]
  grep -q -- '--file .*LP-' "$TMPD/args"
}

@test "S03k lp: sin --persist no se invoca al persistidor" {
  printf '#!/usr/bin/env bash\ntouch "%s/llamado"\n' "$TMPD" > "$TMPD/persist.sh"
  SCL_PERSIST_SCRIPT="$TMPD/persist.sh" run lp
  [ ! -e "$TMPD/llamado" ]
  [[ "$output" != *"persisted:"* ]]
}

@test "S03k lp: alta, media y baja son confianzas válidas" {
  for c in alta media baja; do
    echo "ev-$c" > "$TMPD/ev-$c.txt"
    E="$TMPD/ev-$c.txt" run lp --confidence $c
    [ "$status" -eq 0 ]
  done
}

@test "S03k lp: el origen con tildes se guarda legible en el índice del grafo" {
  O='revisión del año' run lp
  [ "$status" -eq 0 ]
  grep -q '"origin":"revisión del año"' "$GRAPH"
}
