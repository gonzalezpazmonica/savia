#!/usr/bin/env bats
# SE-376 S03 — parallel-dispatch: comportamiento real del despacho con handle de admisión
# (launch devuelve al instante; status/collect/clean reflejan el estado verdadero del hijo).
# Ref: SE-347 · .claude/skills/parallel-dispatch/SKILL.md · scripts/parallel-dispatch.sh
set -uo pipefail

SCRIPT="scripts/parallel-dispatch.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SAVIA_DISPATCH_DIR="$BATS_TEST_TMPDIR/dispatch"
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  PD="$ROOT/$SCRIPT"
}

# Los hijos largos (sleep 5) escriben en el temporal de este test; bats lo borra y no afecta a otros.
teardown() { unset SAVIA_DISPATCH_DIR; }

# Espera (máx. 10 s) a que el job salga de «running».
wait_done() {
  local i
  for i in $(seq 1 100); do
    bash "$PD" status --id "$1" --quiet | grep -qv " running " && return 0
    sleep 0.1
  done
  return 1
}

@test "positivo: launch devuelve el handle sin esperar al hijo (hijo de 5 s, vuelve en menos de 3)" {
  local t0=$SECONDS
  run bash "$PD" launch --id lento --dir "$WORK" --cmd "sleep 5; echo fin"
  [ "$status" -eq 0 ]
  [ $((SECONDS - t0)) -lt 3 ]
  [[ "$output" == *"launched lento"* ]]
  run bash "$PD" status --id lento --quiet
  [ "$output" = "lento running n/a" ]
}

@test "positivo: un hijo correcto acaba en done con exit 0 y collect devuelve su salida" {
  bash "$PD" launch --id ok --dir "$WORK" --cmd "echo resultado-$$"
  wait_done ok
  run bash "$PD" status --id ok --quiet
  [ "$output" = "ok done 0" ]
  run bash "$PD" collect --id ok
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] done exit=0"* ]]
  [[ "$output" == *"resultado-$$"* ]]
}

@test "positivo: el hijo corre en --dir (cwd real, no el del padre)" {
  bash "$PD" launch --id cwd --dir "$WORK" --cmd "pwd"
  wait_done cwd
  run bash "$PD" collect --id cwd
  [[ "$output" == *"$WORK"* ]]
}

@test "negativo: un hijo que falla acaba en failed con su código y collect --fail-fast sale distinto de 0" {
  bash "$PD" launch --id mal --dir "$WORK" --cmd "echo roto; exit 7"
  wait_done mal
  run bash "$PD" status --id mal --quiet
  [ "$output" = "mal failed 7" ]
  run bash "$PD" collect --id mal --fail-fast
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed exit=7"* ]]
  run bash "$PD" collect --id mal
  [ "$status" -eq 0 ]
}

@test "negativo: collect de un job aún en marcha lo declara RUNNING y falla, no inventa resultado" {
  bash "$PD" launch --id vivo --dir "$WORK" --cmd "sleep 5"
  run bash "$PD" collect --id vivo
  [ "$status" -eq 1 ]
  [[ "$output" == *"RUNNING"* ]]
  [[ "$output" != *"done exit"* ]]
}

@test "error: launch sin --id o sin --cmd → exit 2 y no crea ningún job" {
  run bash "$PD" launch --cmd "true"
  [ "$status" -eq 2 ]
  run bash "$PD" launch --id sin-cmd
  [ "$status" -eq 2 ]
  [ -z "$(ls "$SAVIA_DISPATCH_DIR"/*.job.json 2>/dev/null)" ]
}

@test "error: un id repetido se rechaza y no pisa el job original" {
  bash "$PD" launch --id dup --dir "$WORK" --cmd "echo primero"
  wait_done dup
  run bash "$PD" launch --id dup --dir "$WORK" --cmd "echo segundo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ya existe"* ]]
  run bash "$PD" collect --id dup
  [[ "$output" == *"primero"* ]]
  [[ "$output" != *"segundo"* ]]
}

@test "limite timeout: el hijo que excede --timeout se corta y queda failed con exit 124" {
  bash "$PD" launch --id tarda --dir "$WORK" --cmd "sleep 30" --timeout 1
  wait_done tarda
  run bash "$PD" status --id tarda --quiet
  [ "$output" = "tarda failed 124" ]
}

@test "limite empty: sin jobs, status y collect lo dicen y salen con 0" {
  run bash "$PD" status
  [ "$status" -eq 0 ]
  [ "$output" = "(sin jobs)" ]
  run bash "$PD" collect --all
  [ "$status" -eq 0 ]
  [ "$output" = "(sin jobs)" ]
}

@test "clean: rechaza limpiar un job en marcha; con uno terminado borra job y salida; --all --done conserva los vivos" {
  bash "$PD" launch --id vivo --dir "$WORK" --cmd "sleep 5"
  bash "$PD" launch --id fin --dir "$WORK" --cmd "echo x"
  wait_done fin
  run bash "$PD" clean --id vivo
  [ "$status" -eq 1 ]
  [ -f "$SAVIA_DISPATCH_DIR/vivo.job.json" ]
  run bash "$PD" clean --all --done
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean fin"* ]]
  [ ! -f "$SAVIA_DISPATCH_DIR/fin.job.json" ]
  [ ! -f "$SAVIA_DISPATCH_DIR/fin.out" ]
  [ -f "$SAVIA_DISPATCH_DIR/vivo.job.json" ]
}

@test "seguro: un cmd con comillas y barras se registra como JSON válido" {
  bash "$PD" launch --id q --dir "$WORK" --cmd 'echo "a\"b" && true'
  wait_done q
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['id']=='q' and d['status']=='done', d" "$SAVIA_DISPATCH_DIR/q.job.json"
}

@test "uso: subcomando desconocido → exit 2" {
  run bash "$PD" nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"Uso:"* ]]
}
