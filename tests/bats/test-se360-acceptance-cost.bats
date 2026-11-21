#!/usr/bin/env bats
# test-se360-acceptance-cost.bats — BATS tests for SE-360 acceptance-cost
# Ref: SE-360 — costo por cambio aceptado descompuesto por etapa

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AGG="$REPO_ROOT/scripts/acceptance-cost-agg.py"
  export REPO_ROOT AGG
  # ledgers de prueba aislados
  export TEST_RUNS="$(mktemp -d)"
}

teardown() {
  if [[ -d "${TEST_RUNS:-}" ]]; then
    rm -rf "$TEST_RUNS"
  fi
}

@test "agg con ledgers vacíos no falla (json válido)" {
  run python3 "$AGG" --runs /no/existe.jsonl --audit /no/existe.jsonl --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['total_prs'] == 0
assert 'bottleneck' in d
"
}

@test "agg con ledger sintético descompone por etapa" {
  local runs="$TEST_RUNS/runs.jsonl"
  # Fechas relativas: el agregador solo mira --days (30 por defecto); una fecha fija caduca.
  local d1 d2
  d1=$(date -u -d '2 days ago' +%Y-%m-%dT10:00:00Z)
  d2=$(date -u -d '2 days ago' +%Y-%m-%dT11:00:00Z)
  printf '{"run_id":"r1","started_at":"'"$d1"'","pr":{"number":101,"state":"merged","ci":"passing","review":"approved"}}\n' > "$runs"
  printf '{"run_id":"r2","started_at":"'"$d2"'","pr":{"number":102,"state":"open","ci":"pending","review":"changes_requested"}}\n' >> "$runs"
  run python3 "$AGG" --runs "$runs" --audit /no/existe.jsonl --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['total_prs'] == 2, f'total_prs={d[\"total_prs\"]}'
for s in ('cola_ci','ci','revision','remediacion','gobernanza'):
    assert s in d['stages'], f'falta {s}'
"
}

@test "agg reporta bottleneck" {
  local runs="$TEST_RUNS/runs.jsonl"
  # Fechas relativas: el agregador solo mira --days (30 por defecto); una fecha fija caduca.
  local d1 d2
  d1=$(date -u -d '2 days ago' +%Y-%m-%dT10:00:00Z)
  d2=$(date -u -d '2 days ago' +%Y-%m-%dT11:00:00Z)
  printf '{"run_id":"r1","started_at":"'"$d1"'","pr":{"number":101,"state":"open","ci":"pending","review":"changes_requested"}}\n' > "$runs"
  run python3 "$AGG" --runs "$runs" --audit /no/existe.jsonl
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Bottleneck"* ]]
}

@test "agg ignora ejecuciones fuera de la ventana de --days (caso negativo)" {
  local runs="$TEST_RUNS/old.jsonl" old
  old=$(date -u -d '90 days ago' +%Y-%m-%dT10:00:00Z)
  printf '{"run_id":"r9","started_at":"%s","pr":{"number":103,"state":"merged","ci":"passing","review":"approved"}}\n' "$old" > "$runs"
  run python3 "$AGG" --runs "$runs" --audit /no/existe.jsonl --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
assert json.load(sys.stdin)['total_prs'] == 0
"
}
