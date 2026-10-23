#!/usr/bin/env bats
# Coherencia de los bloques completion de planning-state (revisión independiente de la conciliación 2026-10-23).

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  . "$ROOT/scripts/lib/planning-completion.sh"
  STATE="${PLANNING_STATE_FILE:-$ROOT/docs/propuestas/planning-state.json}"
}

item() { jq -c --arg id "$1" '[.. | objects | select(.id? == $id and has("completion"))][0]' "$STATE"; }

@test "SE-442 AC5 no se declara cumplido con autoridad inferior a la requerida" {
  c=$(item SE-442 | jq -c .completion)
  run planning_unverified_authority_list "$c"
  [[ "$output" == *"AC5"*"insuficiente"*"simulada"*"real"* ]]
}

@test "ninguna nota deja frases pegadas sin punto ni el aviso obsoleto del re-firmado" {
  for id in SE-404 SE-426 SE-442 SE-444 SE-445 SE-451; do
    n=$(item "$id" | jq -r .note)
    [[ ! "$n" =~ [^.]\ 2026-10-23\ conciliación ]] || { echo "$id: falta separador"; return 1; }
    [[ "$n" != *"Falta observar el re-firmado"* ]] || { echo "$id: aviso obsoleto"; return 1; }
  done
}

@test "SE-404 registra el PR que contiene el código de G13 v2" {
  [ "$(item SE-404 | jq .completion.merge_pr)" = "1336" ]
}

@test "negativo: el detector de separador sí salta con una nota pegada" {
  n="Falta observar 2026-10-23 conciliación: x"
  [[ "$n" =~ [^.]\ 2026-10-23\ conciliación ]]
}

@test "todo completion nuevo sigue cumpliendo forma y ficheros de evidencia" {
  for id in SE-404 SE-426 SE-442 SE-444 SE-445 SE-451; do
    c=$(item "$id" | jq -c .completion)
    planning_acceptance_evidence_valid "$ROOT" "$c"
  done
}
