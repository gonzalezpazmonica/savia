#!/usr/bin/env bats
# SE-376 S03 — azure-devops-queries: el script real de consultas respeta las reglas de Savia con
# `az` y `curl` sustituidos por dobles (sin red): el WIQL lleva siempre el filtro de iteración
# (Rule 2), el PAT sale del fichero y nunca va en argumentos ni en la salida (Rule 1), y los
# cálculos (velocity, burndown, board) devuelven lo que dicen.
# Ref: docs/rules/domain/mcp-migration.md · .claude/skills/azure-devops-queries/SKILL.md · scripts/azdevops-queries.sh
set -uo pipefail

SCRIPT="scripts/azdevops-queries.sh"
PAT="pat-de-prueba-9f3a"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  Q="$ROOT/$SCRIPT"
  W="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
  BIN="$W/bin"; AZBIN="$W/azbin"; LOG="$W/log"; mkdir -p "$BIN" "$AZBIN" "$LOG"
  for t in bash jq date cat base64 tr dirname python3 sed grep sort find head cut mkdir; do
    p="$(command -v "$t")" && ln -sf "$p" "$BIN/$t"
  done
  # az doble: registra argv y entorno; las respuestas salen de ficheros que fija cada test.
  cat > "$AZBIN/az" <<'A'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG_DIR/az.args"
printf '%s\n' "${AZURE_DEVOPS_EXT_PAT:-}" >> "$LOG_DIR/az.env-pat"
case "$1 $2 $3" in
  "boards iteration team") cat "$LOG_DIR/iterations.json" ;;
  "boards work-item update") echo '{"id": 1234}' ;;
esac
exit 0
A
  # curl doble: registra URL, cabeceras y cuerpo; responde según la URL.
  cat > "$BIN/curl" <<'C'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG_DIR/curl.args"
url=""; body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) body="$2"; shift 2 ;;
    -H|-X) shift 2 ;;
    -s) shift ;;
    *) url="$1"; shift ;;
  esac
done
[[ -n "$body" ]] && printf '%s\n' "$body" > "$LOG_DIR/wiql.body"
case "$url" in
  *"/wit/wiql"*) cat "$LOG_DIR/wiql.json" ;;
  *"/wit/workitems"*) cat "$LOG_DIR/items.json" ;;
  *"/_odata/"*) cat "$LOG_DIR/odata.json" ;;
  *"/capacities"*) cat "$LOG_DIR/capacities.json" ;;
esac
C
  chmod +x "$AZBIN/az" "$BIN/curl"
  : > "$LOG/curl.args"; : > "$LOG/az.args"; : > "$LOG/az.env-pat"
  printf '%s' "$PAT" > "$W/pat"
  export LOG_DIR="$LOG" BASH_BIN="$(command -v bash)"
  export AZURE_DEVOPS_ORG_URL="https://dev.azure.example/org" AZURE_DEVOPS_PAT_FILE="$W/pat"
  export AZURE_DEVOPS_DEFAULT_PROJECT="Demo" AZURE_DEVOPS_DEFAULT_TEAM="Demo Team"
  echo '{"workItems":[{"id":11},{"id":12}]}' > "$LOG/wiql.json"
  echo '{"value":[
    {"id":11,"fields":{"System.WorkItemType":"Task","System.Title":"A","System.State":"Active","System.AssignedTo":{"displayName":"Ana"},"System.ChangedDate":"2026-11-02T10:00:00Z","Microsoft.VSTS.Scheduling.RemainingWork":3}},
    {"id":12,"fields":{"System.WorkItemType":"Task","System.Title":"B","System.State":"Active","System.AssignedTo":{"displayName":"Luis"},"System.ChangedDate":"2026-11-03T10:00:00Z","Microsoft.VSTS.Scheduling.RemainingWork":5}},
    {"id":13,"fields":{"System.WorkItemType":"Bug","System.Title":"C","System.State":"New","System.AssignedTo":{"displayName":"Ana"},"System.ChangedDate":"2026-11-04T10:00:00Z"}}]}' > "$LOG/items.json"
  echo '{"value":[{"id":"it-9","name":"Sprint 9","path":"Demo\\Sprint 9","attributes":{"startDate":"2026-11-02T00:00:00Z","finishDate":"2026-11-13T00:00:00Z","timeFrame":"current"}}]}' > "$LOG/iterations.json"
}

teardown() { cd /; }

# PATH acotado solo para el script bajo prueba (bats necesita el suyo).
run_q() { run env PATH="${TPATH:-$BIN:$AZBIN}" "$BASH_BIN" "$Q" "$@"; }

@test "items: el WIQL enviado filtra por iteración (Rule 2) con proyecto y equipo sustituidos" {
  run_q items Demo "Demo Team"
  [ "$status" -eq 0 ]
  body="$(cat "$LOG/wiql.body")"
  [[ "$body" == *"System.IterationPath"* ]]
  [[ "$body" == *"@CurrentIteration('[Demo\\\\Demo Team]')"* ]]
  [[ "$body" != *"{{"* ]]
}

@test "board: el WIQL también filtra por iteración y excluye estados terminales y Epic/Feature" {
  run_q board Demo "Demo Team"
  [ "$status" -eq 0 ]
  body="$(cat "$LOG/wiql.body")"
  [[ "$body" == *"System.IterationPath"* ]]
  [[ "$body" == *"NOT IN ('Done', 'Closed', 'Removed')"* ]]
  [[ "$body" == *"NOT IN ('Epic', 'Feature')"* ]]
}

@test "Rule 1: el PAT va como Basic base64(':PAT') en la cabecera y nunca en argv de az ni en la salida" {
  run_q items Demo "Demo Team"
  [ "$status" -eq 0 ]
  esperado="Authorization: Basic $(printf ':%s' "$PAT" | base64)"
  grep -qF "$esperado" "$LOG/curl.args"
  run grep -F "$PAT" "$LOG/az.args"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$PAT"* ]]
  # az recibe el PAT por entorno, no por argumentos
  grep -qF "$PAT" "$LOG/az.env-pat"
}

@test "items: pide el detalle de los IDs que devolvió el WIQL y proyecta los campos" {
  run_q items Demo "Demo Team"
  [ "$status" -eq 0 ]
  grep -qF 'ids=11,12' "$LOG/curl.args"
  [[ "$output" == *'"titulo": "A"'* ]]
  [[ "$output" == *'"asignado": "Luis"'* ]]
  [[ "$output" == *'"restante_h": 5'* ]]
}

@test "items: sprint sin work items (empty) devuelve [] y no pide detalle" {
  echo '{"workItems":[]}' > "$LOG/wiql.json"
  run_q items Demo "Demo Team"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[]"* ]]
  run grep -F '/wit/workitems?' "$LOG/curl.args"
  [ "$status" -ne 0 ]
}

@test "board: sin items activos avisa y no pide detalle" {
  echo '{"workItems":[]}' > "$LOG/wiql.json"
  run_q board Demo "Demo Team"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No hay items activos"* ]]
  run grep -F '/wit/workitems?' "$LOG/curl.args"
  [ "$status" -ne 0 ]
}

@test "board: agrupa por estado con su cuenta" {
  run_q board Demo "Demo Team"
  [ "$status" -eq 0 ]
  json="$(printf '%s\n' "$output" | sed -n '/^\[$/,$p')"
  [ "$(printf '%s' "$json" | jq -r '.[] | select(.estado=="Active") | .count')" = "2" ]
  [ "$(printf '%s' "$json" | jq -r '.[] | select(.estado=="New") | .count')" = "1" ]
}

@test "velocity: solo sprints pasados, orden cronológico y respeta el límite N" {
  echo '{"value":[
    {"id":"s1","name":"S1","attributes":{"startDate":"2026-08-03T00:00:00Z","finishDate":"2026-08-14T00:00:00Z","timeFrame":"past"}},
    {"id":"s3","name":"S3","attributes":{"startDate":"2026-10-05T00:00:00Z","finishDate":"2026-10-16T00:00:00Z","timeFrame":"past"}},
    {"id":"s2","name":"S2","attributes":{"startDate":"2026-09-07T00:00:00Z","finishDate":"2026-09-18T00:00:00Z","timeFrame":"past"}},
    {"id":"s4","name":"S4 actual","attributes":{"startDate":"2026-11-02T00:00:00Z","finishDate":"2026-11-13T00:00:00Z","timeFrame":"current"}}]}' > "$LOG/iterations.json"
  run_q velocity Demo "Demo Team" 2
  [ "$status" -eq 0 ]
  nombres="$(printf '%s\n' "$output" | grep -o '"nombre": "[^"]*"' | sed 's/.*: //' | tr '\n' ' ')"
  [ "$nombres" = '"S2" "S3" ' ]
  [[ "$output" != *"S4 actual"* ]]
}

@test "burndown: filtra por la iteración del sprint actual y suma el restante por día" {
  echo '{"value":[
    {"WorkItemId":1,"RemainingWork":3,"DateValue":"2026-11-02T00:00:00Z"},
    {"WorkItemId":2,"RemainingWork":5,"DateValue":"2026-11-02T00:00:00Z"},
    {"WorkItemId":1,"RemainingWork":1,"DateValue":"2026-11-03T00:00:00Z"}]}' > "$LOG/odata.json"
  run_q burndown Demo "Demo Team"
  [ "$status" -eq 0 ]
  grep -qF "IterationPath eq 'Demo\\Sprint 9'" "$LOG/curl.args"
  json="$(printf '%s\n' "$output" | sed -n '/^\[$/,$p')"
  [ "$(printf '%s' "$json" | jq -r '.[] | select(.fecha=="2026-11-02") | .remaining_total')" = "8" ]
  [ "$(printf '%s' "$json" | jq -r '.[] | select(.fecha=="2026-11-03") | .remaining_total')" = "1" ]
}

@test "capacities: usa el id de la iteración actual y proyecta persona y días libres" {
  echo '{"value":[{"teamMember":{"displayName":"Ana","uniqueName":"ana@example.org"},"activities":[{"name":"Dev","capacityPerDay":6}],"daysOff":[]}]}' > "$LOG/capacities.json"
  run_q capacities Demo "Demo Team"
  [ "$status" -eq 0 ]
  grep -qF '/iterations/it-9/capacities?api-version' "$LOG/curl.args"
  [[ "$output" == *'"persona": "Ana"'* ]]
}

@test "update: pasa el id y CAMPO=valor a az boards work-item update" {
  run_q update Demo 1234 "Microsoft.VSTS.Scheduling.RemainingWork" 4
  [ "$status" -eq 0 ]
  grep -qF -- '--id 1234' "$LOG/az.args"
  grep -qF -- '--fields Microsoft.VSTS.Scheduling.RemainingWork=4' "$LOG/az.args"
}

@test "error: update sin campo ni valor (missing args) falla y no llama a az work-item update" {
  run_q update Demo 1234
  [ "$status" -ne 0 ]
  run grep -F 'work-item update' "$LOG/az.args"
  [ "$status" -ne 0 ]
}

@test "error: sin fichero de PAT (missing) aborta antes de llamar a az o curl (fail-closed)" {
  AZURE_DEVOPS_PAT_FILE="$W/no-existe-pat" run_q items Demo "Demo Team"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PAT no encontrado"* ]]
  [ ! -s "$LOG/curl.args" ]
  [ ! -s "$LOG/az.args" ]
}

@test "error: sin az instalado aborta con mensaje y sin tocar la red" {
  TPATH="$BIN" run_q items Demo "Demo Team"
  [ "$status" -ne 0 ]
  [[ "$output" == *"az cli no encontrado"* ]]
  [ ! -s "$LOG/curl.args" ]
}

@test "comando desconocido muestra la ayuda sin hacer llamadas" {
  run_q frobnicate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Comandos disponibles"* ]]
  [ ! -s "$LOG/curl.args" ]
}

@test "stdout es JSON puro: los mensajes de progreso van a stderr (los consumidores redirigen a fichero)" {
  echo '{"value":[{"teamMember":{"displayName":"Ana","uniqueName":"ana@example.org"},"activities":[],"daysOff":[]}]}' > "$LOG/capacities.json"
  env PATH="$BIN:$AZBIN" "$BASH_BIN" "$Q" capacities Demo "Demo Team" > "$W/out.json" 2> "$W/err.txt"
  jq -e . "$W/out.json" > /dev/null
  grep -q 'Obteniendo capacidades' "$W/err.txt"
}
