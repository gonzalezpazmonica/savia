#!/usr/bin/env bats
# Learning proposals: cuándo aplica y confianza (idea de harness2: una lección
# sin condición de uso ni evidencia no se puede verificar después).
# Ref: docs/rules/domain/remedy-ladder.md

set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LP="$REPO_ROOT/scripts/learning-proposal.sh"
  TMPD="$(mktemp -d -t lp-cue-XXXXXX)"
  printf 'evidencia de prueba\n' > "$TMPD/ev.md"
  export SCL_GRAPH_INDEX="$TMPD/graph.jsonl"
}

teardown() {
  [[ -n "${TMPD:-}" && -d "$TMPD" ]] && find "$TMPD" -mindepth 1 -delete && rmdir "$TMPD"
}

crear() {
  bash "$LP" --origin "origen" --evidence "$TMPD/ev.md" --diagnosis "diag" \
    --change "cambio" --target criterio --output-dir "$TMPD/out" "$@"
}

@test "cue y confianza quedan en frontmatter y cuerpo" {
  run crear --when "tareas de cúpula en headless" --confidence media
  [ "$status" -eq 0 ]
  f=$(ls "$TMPD"/out/LP-*.md)
  grep -q '^when: "tareas de cúpula en headless"$' "$f"
  grep -q '^confidence: media$' "$f"
  grep -q '^## Cuándo aplica$' "$f"
}

@test "confianza fuera de alta/media/baja es error de uso" {
  run crear --when "x" --confidence total
  [ "$status" -eq 2 ]
  [[ "$output" == *"--confidence"* ]]
  [ ! -d "$TMPD/out" ] || [ -z "$(ls "$TMPD/out")" ]
}

@test "sin cue sigue funcionando y lo marca como pendiente" {
  run crear
  [ "$status" -eq 0 ]
  f=$(ls "$TMPD"/out/LP-*.md)
  grep -q '^when: *$' "$f"
  grep -q 'sin condición de uso declarada' "$f"
}

@test "evidencia inexistente sigue rechazándose" {
  run bash "$LP" --origin o --evidence "$TMPD/no-existe.md" --diagnosis d \
    --change c --target criterio --output-dir "$TMPD/out" --when x --confidence alta
  [ "$status" -eq 3 ]
}

@test "--when con salto de línea se rechaza (no inyecta claves en el frontmatter)" {
  run crear --when $'x\ntarget: skill' --confidence alta
  [ "$status" -eq 2 ]
  [[ "$output" == *"--when"* ]]
  [ ! -d "$TMPD/out" ] || [ -z "$(ls "$TMPD/out")" ]
}

@test "--when con dos puntos y comillas queda como un escalar entrecomillado" {
  run crear --when 'cuando falla X: "reintentar"' --confidence baja
  [ "$status" -eq 0 ]
  f=$(ls "$TMPD"/out/LP-*.md)
  grep -qF 'when: "cuando falla X: \"reintentar\""' "$f"
  grep -q '^target: criterio$' "$f"
}

@test "--help muestra la cabecera entera" {
  run bash "$LP" --help
  [[ "$output" == *"Exit codes"* ]]
  [[ "$output" == *"--when"* ]]
}

@test "--when con caracteres de control o demasiado largo se rechaza" {
  run crear --when $'x\ty' --confidence alta
  [ "$status" -eq 2 ]
  run crear --when "$(printf 'a%.0s' $(seq 1 201))" --confidence alta
  [ "$status" -eq 2 ]
  [[ "$output" == *"200"* ]]
}

# ── Comportamiento: identidad, evidencia e idempotencia ───────────────────────

_fm() { grep -m1 "^$2: " "$1" | sed "s/^$2: //"; }

@test "salida estándar: CREATED, id y evidence_hash coinciden con el fichero escrito" {
  run crear
  [ "$status" -eq 0 ]
  f=$(ls "$TMPD"/out/LP-*.md)
  [ "$(echo "$output" | sed -n 1p)" = "CREATED: $f" ]
  [ "$(echo "$output" | sed -n 2p)" = "id: $(_fm "$f" id)" ]
  [ "$(echo "$output" | sed -n 3p)" = "evidence_hash: $(_fm "$f" evidence_hash)" ]
}

@test "el id por defecto es LP-<fecha UTC>-<8 primeros del hash de evidencia>" {
  crear >/dev/null
  f=$(ls "$TMPD"/out/LP-*.md)
  h="$(_fm "$f" evidence_hash)"
  [ "$(_fm "$f" id)" = "LP-$(date -u +%Y%m%d)-${h:0:8}" ]
  [[ "$h" =~ ^[0-9a-f]{64}$ ]]
}

@test "--id fuerza el identificador y el nombre del fichero" {
  run crear --id LP-MIO-1
  [ "$status" -eq 0 ]
  [ -f "$TMPD/out/LP-MIO-1.md" ]
  [ "$(_fm "$TMPD/out/LP-MIO-1.md" id)" = "LP-MIO-1" ]
}

@test "frontmatter fijo: INFERRED, proposed, learning_proposal y trigger ledger por defecto" {
  crear >/dev/null
  f=$(ls "$TMPD"/out/LP-*.md)
  [ "$(_fm "$f" provenance)" = "INFERRED" ]
  [ "$(_fm "$f" lifecycle)" = "proposed" ]
  [ "$(_fm "$f" type)" = "learning_proposal" ]
  [ "$(_fm "$f" trigger)" = "ledger" ]
  [ "$(_fm "$f" target)" = "criterio" ]
  [ "$(_fm "$f" origin)" = "origen" ]
}

@test "--trigger se refleja en el frontmatter" {
  crear --trigger recurrence >/dev/null
  [ "$(_fm "$(ls "$TMPD"/out/LP-*.md)" trigger)" = "recurrence" ]
}

@test "el hash de evidencia depende del contenido del fichero" {
  crear >/dev/null
  h1="$(_fm "$(ls "$TMPD"/out/LP-*.md)" evidence_hash)"
  printf 'otro contenido\n' > "$TMPD/ev.md"
  bash "$LP" --origin o --evidence "$TMPD/ev.md" --diagnosis d --change c --target criterio \
    --output-dir "$TMPD/out2" >/dev/null
  h2="$(_fm "$(ls "$TMPD"/out2/LP-*.md)" evidence_hash)"
  [ "$h1" != "$h2" ]
}

@test "el hash de evidencia no depende del orden de las entradas" {
  printf 'dos\n' > "$TMPD/ev2.md"
  bash "$LP" --origin o --evidence "$TMPD/ev.md,$TMPD/ev2.md" --diagnosis d --change c --target spec \
    --output-dir "$TMPD/a" >/dev/null
  bash "$LP" --origin o --evidence "$TMPD/ev2.md,$TMPD/ev.md" --diagnosis d --change c --target spec \
    --output-dir "$TMPD/b" >/dev/null
  [ "$(_fm "$(ls "$TMPD"/a/LP-*.md)" evidence_hash)" = "$(_fm "$(ls "$TMPD"/b/LP-*.md)" evidence_hash)" ]
}

@test "evidencia con hash explícito no necesita que el fichero exista y lo usa tal cual" {
  run bash "$LP" --origin o --evidence "ruta/que/no/existe.md:abc123" --diagnosis d --change c \
    --target memoria --output-dir "$TMPD/out"
  [ "$status" -eq 0 ]
  grep -q '^ruta/que/no/existe.md:abc123$' "$(ls "$TMPD"/out/LP-*.md)"
}

@test "evidencia: espacios alrededor se ignoran y una lista sin entradas válidas es exit 3" {
  run bash "$LP" --origin o --evidence " , ," --diagnosis d --change c --target skill --output-dir "$TMPD/out"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no valid evidence"* ]]
  run bash "$LP" --origin o --evidence " $TMPD/ev.md , x:h1 " --diagnosis d --change c --target skill --output-dir "$TMPD/out"
  [ "$status" -eq 0 ]
  [ "$(grep -c "^x:h1$" "$(ls "$TMPD"/out/LP-*.md)")" -eq 1 ]
}

@test "evidencia inexistente: exit 3 con la ruta en el error y nada escrito" {
  run bash "$LP" --origin o --evidence "$TMPD/falta.md" --diagnosis d --change c --target skill --output-dir "$TMPD/out"
  [ "$status" -eq 3 ]
  [[ "$output" == *"evidence path not found and no hash given: $TMPD/falta.md"* ]]
  [ ! -e "$TMPD/out" ]
}

@test "la misma evidencia en 24 h es duplicado: exit 1, avisa y muestra el fichero existente" {
  crear >/dev/null
  f=$(ls "$TMPD"/out/LP-*.md)
  run crear --id LP-OTRO
  [ "$status" -eq 1 ]
  [[ "$output" == *"DUPLICATE: proposal for evidence"* ]]
  [[ "$output" == *"$f"* ]]
  [ ! -e "$TMPD/out/LP-OTRO.md" ]
}

@test "una propuesta con la misma evidencia de hace más de 24 h no cuenta como duplicado" {
  crear >/dev/null
  f=$(ls "$TMPD"/out/LP-*.md)
  sed -i 's/^created_utc: .*/created_utc: 2020-01-01T00:00:00Z/' "$f"
  run crear --id LP-NUEVO
  [ "$status" -eq 0 ]
  [ -f "$TMPD/out/LP-NUEVO.md" ]
}

@test "evidencia distinta no es duplicado aunque el resto de campos coincida" {
  crear >/dev/null
  printf 'distinta\n' > "$TMPD/ev3.md"
  run bash "$LP" --origin origen --evidence "$TMPD/ev3.md" --diagnosis diag --change cambio \
    --target criterio --output-dir "$TMPD/out"
  [ "$status" -eq 0 ]
  [ "$(ls "$TMPD"/out | wc -l)" -eq 2 ]
}

# ── Comportamiento: validación de argumentos ──────────────────────────────────

@test "falta cualquiera de los cinco campos obligatorios: exit 2 con la cabecera de uso" {
  for omit in origin evidence diagnosis change target; do
    args=(--origin o --evidence "$TMPD/ev.md" --diagnosis d --change c --target spec)
    for i in "${!args[@]}"; do
      if [[ "${args[$i]}" == "--$omit" ]]; then unset 'args[i]' 'args[i+1]'; break; fi
    done
    run bash "$LP" "${args[@]}" --output-dir "$TMPD/out"
    [ "$status" -eq 2 ]
    [[ "$output" == *"learning-proposal.sh"* ]]
  done
  [ ! -e "$TMPD/out" ]
}

@test "--target fuera de criterio|memoria|skill|spec es exit 2 y nombra los válidos" {
  run crear --target otra
  [ "$status" -eq 2 ]
  [[ "$output" == *"criterio|memoria|skill|spec"* ]]
}

@test "los cuatro destinos válidos se aceptan" {
  for t in criterio memoria skill spec; do
    run bash "$LP" --origin o --evidence "x:h-$t" --diagnosis d --change c --target "$t" --output-dir "$TMPD/out"
    [ "$status" -eq 0 ]
  done
  [ "$(ls "$TMPD"/out | wc -l)" -eq 4 ]
}

@test "--criterion-id exige destino criterio y formato CRIT-NNN" {
  run crear --criterion-id CRIT-042
  [ "$status" -eq 0 ]
  [ "$(_fm "$(ls "$TMPD"/out/LP-*.md)" criterion_id)" = "CRIT-042" ]
  run bash "$LP" --origin o --evidence "x:h1" --diagnosis d --change c --target skill \
    --criterion-id CRIT-042 --output-dir "$TMPD/o2"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires --target criterio"* ]]
  run crear --criterion-id CRIT-42 --id LP-X
  [ "$status" -eq 2 ]
  [[ "$output" == *"must match CRIT-XXX"* ]]
  run crear --criterion-id crit-042 --id LP-Y
  [ "$status" -eq 2 ]
}

@test "--expected-p-consistent aparece en frontmatter y en la métrica esperada; sin él, sin baseline" {
  crear --expected-p-consistent 0.8 >/dev/null
  f=$(ls "$TMPD"/out/LP-*.md)
  [ "$(_fm "$f" expected_p_consistent)" = "0.8" ]
  grep -q '^p_consistent esperado: 0.8$' "$f"
  bash "$LP" --origin o --evidence "x:h9" --diagnosis d --change c --target spec --output-dir "$TMPD/o2" >/dev/null
  g=$(ls "$TMPD"/o2/LP-*.md)
  grep -q '^sin baseline declarado$' "$g"
  [ "$(grep -c '^p_consistent esperado' "$g")" -eq 0 ]
}

@test "la confianza se muestra junto al cue en el cuerpo" {
  crear --when "cuando X" --confidence alta >/dev/null
  grep -q '^cuando X · confianza: alta$' "$(ls "$TMPD"/out/LP-*.md)"
}

@test "--when con barra invertida se escapa en el frontmatter" {
  crear --when 'ruta C:\tmp' >/dev/null
  grep -qF 'when: "ruta C:\\tmp"' "$(ls "$TMPD"/out/LP-*.md)"
}

@test "--when de exactamente 200 caracteres se acepta" {
  run crear --when "$(printf 'a%.0s' $(seq 1 200))"
  [ "$status" -eq 0 ]
}

@test "el cuerpo contiene las secciones Origen, Evidencia, Diagnóstico, Cambio propuesto y Destino con su texto" {
  crear >/dev/null
  f=$(ls "$TMPD"/out/LP-*.md)
  [ "$(awk '/^## Origen$/{getline; getline; print}' "$f")" = "origen" ]
  [ "$(awk '/^## Diagnóstico$/{getline; getline; print}' "$f")" = "diag" ]
  [ "$(awk '/^## Cambio propuesto$/{getline; getline; print}' "$f")" = "cambio" ]
  [ "$(awk '/^## Destino$/{getline; getline; print}' "$f")" = "criterio" ]
  grep -q "^$TMPD/ev.md:[0-9a-f]\{64\}$" "$f"
}

# ── Comportamiento: índice del grafo y persistencia ───────────────────────────

@test "el índice del grafo recibe una línea JSON válida por propuesta y las anteriores se conservan" {
  crear >/dev/null
  bash "$LP" --origin o --evidence "x:h2" --diagnosis d --change c --target skill --output-dir "$TMPD/out" >/dev/null
  [ "$(wc -l < "$TMPD/graph.jsonl")" -eq 2 ]
  line="$(sed -n 1p "$TMPD/graph.jsonl")"
  [ "$(echo "$line" | jq -r .type)" = "learning_proposal" ]
  [ "$(echo "$line" | jq -r .provenance)" = "INFERRED" ]
  [ "$(echo "$line" | jq -r .target)" = "criterio" ]
  [ "$(echo "$line" | jq -r '.relations.proposes_change')" = "criterio" ]
  [ "$(echo "$line" | jq -r '.relations.evidence_from[0]')" = "$TMPD/ev.md:$(sha256sum "$TMPD/ev.md" | cut -d' ' -f1)" ]
  [ "$(sed -n 2p "$TMPD/graph.jsonl" | jq -r .target)" = "skill" ]
}

@test "--persist: el script de persistencia que sale 0 da persisted: true y recibe --file" {
  printf '#!/usr/bin/env bash\necho "$@" > "%s/persist-args.txt"\n' "$TMPD" > "$TMPD/persist.sh"
  SCL_PERSIST_SCRIPT="$TMPD/persist.sh" run crear --persist
  [ "$status" -eq 0 ]
  [[ "$output" == *"persisted: true"* ]]
  grep -q -- "--file $(ls "$TMPD"/out/LP-*.md)" "$TMPD/persist-args.txt"
  ! grep -q -- "--commit" "$TMPD/persist-args.txt"
}

@test "--persist: si el script falla da persisted: false pero la propuesta se crea (exit 0)" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TMPD/persist.sh"
  SCL_PERSIST_SCRIPT="$TMPD/persist.sh" run crear --persist
  [ "$status" -eq 0 ]
  [[ "$output" == *"persisted: false"* ]]
  [ -n "$(ls "$TMPD"/out/LP-*.md)" ]
}

@test "--persist con SCL_PERSIST_COMMIT pasa --commit; sin script no imprime persisted" {
  printf '#!/usr/bin/env bash\necho "$@" > "%s/persist-args.txt"\n' "$TMPD" > "$TMPD/persist.sh"
  SCL_PERSIST_SCRIPT="$TMPD/persist.sh" SCL_PERSIST_COMMIT=1 crear --persist >/dev/null
  grep -q -- "--commit" "$TMPD/persist-args.txt"
  SCL_PERSIST_SCRIPT="$TMPD/no-existe.sh" run crear --persist --id LP-SIN
  [[ "$output" != *"persisted"* ]]
}

@test "sin --persist no se invoca el script de persistencia" {
  printf '#!/usr/bin/env bash\ntouch "%s/llamado"\n' "$TMPD" > "$TMPD/persist.sh"
  SCL_PERSIST_SCRIPT="$TMPD/persist.sh" run crear
  [ ! -e "$TMPD/llamado" ]
}

@test "la ventana de idempotencia es de 24 h: 23 h cuenta como duplicado, 25 h no" {
  crear >/dev/null
  f=$(ls "$TMPD"/out/LP-*.md)
  sed -i "s/^created_utc: .*/created_utc: $(date -u -d '23 hours ago' +%Y-%m-%dT%H:%M:%SZ)/" "$f"
  run crear --id LP-A
  [ "$status" -eq 1 ]
  sed -i "s/^created_utc: .*/created_utc: $(date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ)/" "$f"
  run crear --id LP-B
  [ "$status" -eq 0 ]
}
