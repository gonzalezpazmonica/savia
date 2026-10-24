#!/usr/bin/env bats
# BATS tests for slm-registry.sh run (SE-342 S2 / Labs L18)
# Ref: SE-342 S2, hypothesis l18-experiment-tracking.md, CRIT-001

SCRIPT="scripts/slm-registry.sh"
CATALOG="scripts/savia-catalog.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP_PROJ="$(mktemp -d -t reg.XXXXXX)"
  export SAVIA_CATALOG_DB="$(mktemp -t cat.XXXXXX.db)"
  rm -f "$SAVIA_CATALOG_DB"
  python3 "$CATALOG" register --type dataset --name agent_data --level N2 >/dev/null
}

teardown() {
  rm -rf "$TMP_PROJ"
  [[ -n "${SAVIA_CATALOG_DB:-}" ]] && rm -f "$SAVIA_CATALOG_DB"
  cd /
}

@test "script exists and executable" {
  [[ -x "$SCRIPT" ]]
}

@test "passes bash -n" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "run logs metrics+params to manifest" {
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id exp-001 \
    --base-model llama3.2-1b \
    --metrics '{"final_loss": 0.82}' --params '{"epochs": 3}'
  [ "$status" -eq 0 ]
  json="$(cat "$TMP_PROJ/registry/manifest.json")"
  [[ "$json" == *"\"id\": \"exp-001\""* ]]
  [[ "$json" == *"\"final_loss\": 0.82"* ]]
  [[ "$json" == *"\"epochs\": 3"* ]]
}

@test "run without run-id rejected (exit 2)" {
  run bash "$SCRIPT" run --project "$TMP_PROJ"
  [ "$status" -eq 2 ]
}

@test "duplicate run rejected (exit 1)" {
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id exp-001 >/dev/null
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id exp-001
  [ "$status" -eq 1 ]
}

@test "run with dataset writes lineage to L17 catalog" {
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id exp-002 \
    --artifact adapters/sft-v1 --dataset agent_data --catalog-db "$SAVIA_CATALOG_DB"
  [ "$status" -eq 0 ]
  run python3 "$CATALOG" --db "$SAVIA_CATALOG_DB" lineage --name "run:exp-002"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent_data"* ]]
}
# --- Comportamiento de run: contenido exacto del manifest y casos limite ---

m() { jq -r "$1" "$TMP_PROJ/registry/manifest.json"; }

@test "run guarda todos los campos y el mensaje resume metrics + params" {
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 --base-model llama \
    --metrics '{"loss":0.5}' --params '{"lr":0.001}' --artifact out/a --dataset ds1
  [ "$status" -eq 0 ]
  [[ "$output" == "slm-registry run: r1 logged (metrics + params)" ]]
  [ "$(m '.runs[0] | [.kind,.id,.base_model,.artifact,.dataset] | join(",")')" = "run,r1,llama,out/a,ds1" ]
  [ "$(m '.runs[0].metrics.loss')" = "0.5" ]
  [ "$(m '.runs[0].params.lr')" = "0.001" ]
  [[ "$(m '.runs[0].created_at')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
}

@test "run solo con metrics: el mensaje no menciona params; sin ninguno, parentesis vacios" {
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 --metrics '{"a":1}'
  [ "$output" = "slm-registry run: r1 logged (metrics + )" ]
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r2
  [ "$output" = "slm-registry run: r2 logged ()" ]
}

@test "run sin --run-id explica que falta (no confunde con slug invalido)" {
  run bash "$SCRIPT" run --project "$TMP_PROJ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--run-id required for run"* ]]
}

@test "run sin opcionales no escribe claves vacias" {
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 >/dev/null
  [ "$(m '.runs[0] | keys | join(",")')" = "created_at,id,kind" ]
}

@test "metrics que no son JSON se guardan como {values: texto}" {
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 --metrics 'loss=0.5 acc=0.9' >/dev/null
  [ "$(m '.runs[0].metrics.values')" = "loss=0.5 acc=0.9" ]
}

@test "run-id invalido (mayuscula, espacio, empieza por guion) sale 2 y no crea registry" {
  for bad in "Exp1" "a b" "-x" "a/b"; do
    run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id "$bad"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--run-id must be slug"* ]]
  done
  [ ! -e "$TMP_PROJ/registry" ]
}

@test "run-id valido con punto, guion y guion bajo se acepta" {
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id a1.b-c_d
  [ "$status" -eq 0 ]
}

@test "varios runs se acumulan en orden y conviven con versiones registradas" {
  bash "$SCRIPT" register --project "$TMP_PROJ" --id v1 --base-model m --method sft >/dev/null
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 >/dev/null
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r2 >/dev/null
  [ "$(m '[.runs[].id] | join(",")')" = "r1,r2" ]
  [ "$(m '.versions | length')" = "1" ]
}

@test "un run con el mismo id que una version registrada no es duplicado" {
  bash "$SCRIPT" register --project "$TMP_PROJ" --id same --base-model m --method sft >/dev/null
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id same
  [ "$status" -eq 0 ]
}

@test "duplicado no modifica el manifest" {
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 --metrics '{"a":1}' >/dev/null
  before=$(cat "$TMP_PROJ/registry/manifest.json")
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 --metrics '{"a":2}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"already logged"* ]]
  [ "$(cat "$TMP_PROJ/registry/manifest.json")" = "$before" ]
}

@test "dataset sin --catalog-db no toca el catalogo; con db pero sin dataset tampoco" {
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 --dataset agent_data >/dev/null
  run python3 "$CATALOG" --db "$SAVIA_CATALOG_DB" lineage --name "run:r1"
  [[ "$output" != *"agent_data"* ]]
  bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r2 --catalog-db "$SAVIA_CATALOG_DB" >/dev/null
  run python3 "$CATALOG" --db "$SAVIA_CATALOG_DB" lineage --name "run:r2"
  [[ "$output" != *"agent_data"* ]]
}

@test "dataset desconocido en el catalogo no hace fallar el run (lineage es best-effort)" {
  run bash "$SCRIPT" run --project "$TMP_PROJ" --run-id r1 --dataset no_existe --catalog-db "$SAVIA_CATALOG_DB"
  [ "$status" -eq 0 ]
  [ "$(m '.runs[0].dataset')" = "no_existe" ]
}

@test "run con proyecto inexistente sale 2 sin crear nada" {
  run bash "$SCRIPT" run --project "$TMP_PROJ/nada" --run-id r1
  [ "$status" -eq 2 ]
  [ ! -e "$TMP_PROJ/nada" ]
}
