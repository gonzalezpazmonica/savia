#!/usr/bin/env bats
# SPEC-CONSOLIDACION 2026-08-23 — tests de los R1/R2/R3/R4 (sanitización)
# Pruebas irrefutables para: cron humano, run-due, log de instalación, instalador central.
# Ref: docs/specs/SE-376-quality-debt-burn-down.spec.md (cron del automation-scheduler)
set -uo pipefail

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
  export SAVIA_AUTOMATIONS_DIR="$FIXDIR/automations"
  export SAVIA_INSTALL_LOG="$FIXDIR/install.log"
}

teardown() {
  rm -rf "$FIXDIR"
}

# ── R1: parser de cron humano ──────────────────────────────────────────────

@test "R1a: normalize 'daily 08:30' → 5-campos y computa next_run" {
  python3 - "$FIXDIR" <<'PY'
import sys
sys.path.insert(0, "scripts")
from automations.store import TaskStore
from automations.models import Schedule
s = TaskStore(sys.argv[1])
assert s._normalize_cron("daily 08:30") == "30 8 * * *"
n = s._compute_next_run(Schedule(kind="cron", cron="daily 08:30"))
# next_run se guarda en UTC; el cron se interpreta en hora local (SE-376).
from datetime import datetime
assert n is not None and datetime.fromisoformat(n).astimezone().strftime("%H:%M") == "08:30", n
print(n)
PY
}

@test "R1b: normalize 'weekly fri 09:15' → '15 9 * * 5'" {
  python3 - "$FIXDIR" <<'PY'
import sys
sys.path.insert(0, "scripts")
from automations.store import TaskStore
s = TaskStore(sys.argv[1])
assert s._normalize_cron("weekly fri 09:15") == "15 9 * * 5"
PY
}

@test "R1c: cron inválido → next_run None sin crash" {
  python3 - "$FIXDIR" <<'PY'
import sys
sys.path.insert(0, "scripts")
from automations.store import TaskStore
from automations.models import Schedule
s = TaskStore(sys.argv[1])
assert s._compute_next_run(Schedule(kind="cron", cron="garbage no válido")) is None
PY
}

@test "R1d: CLI compute materializa next_run de una tarea diaria" {
  bash scripts/savia-automations.sh create --name test-diario \
    --schedule "daily 09:00" --instructions "test" >/dev/null 2>&1
  out=$(bash scripts/savia-automations.sh compute 2>&1)
  echo "$out" | grep -q "next_run="
  # next_run en UTC; las 09:00 son hora local (SE-376).
  next=$(echo "$out" | sed -n 's/.*test-diario: next_run=//p')
  [[ "$(python3 -c 'import sys; from datetime import datetime; print(datetime.fromisoformat(sys.argv[1]).astimezone().strftime("%H:%M"))' "$next")" == "09:00" ]]
}

@test "R1e: invalid 'daily 25:00' → create sale con 2 y no guarda" {
  run bash scripts/savia-automations.sh create --name hora-mala \
    --schedule "daily 25:00" --instructions "test"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"hour: 25 out of range"* ]]
  run bash scripts/savia-automations.sh list
  [[ "$output" == "(no tasks)" ]]
}

@test "R1f: invalid día 'weekly funday 09:00' → rechazado, no se convierte en diario" {
  python3 - "$FIXDIR" <<'PY'
import sys
sys.path.insert(0, "scripts")
from automations.store import TaskStore
s = TaskStore(sys.argv[1])
for bad in ("weekly funday 09:00", "daily 8", "daily 08:30 extra"):
    assert s._normalize_cron(bad) is None, bad
PY
  run bash scripts/savia-automations.sh create --name dia-malo \
    --schedule "weekly funday 09:00" --instructions "test"
  [[ "$status" -eq 2 ]]
}

# ── R2: run-due ejecuta tareas atrasadas ────────────────────────────────────

@test "R2a: run-due sin tareas due → no ejecuta nada" {
  bash scripts/savia-automations.sh create --name futuro \
    --schedule "daily 09:00" --instructions "test" >/dev/null 2>&1
  bash scripts/savia-automations.sh compute >/dev/null 2>&1
  run bash scripts/savia-automations.sh run-due
  echo "$output" | grep -E "no due tasks|0/1"
}

@test "R2b: run-due --max no numérico → error con exit 2" {
  run bash scripts/savia-automations.sh run-due --max muchas
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"--max needs an integer"* ]]
}

@test "R2c: boundary run-due --max 1 con dos tareas vencidas ejecuta solo una" {
  for n in a b; do
    bash scripts/savia-automations.sh create --name "vencida-$n" \
      --schedule "2026-01-01T09:00:00" --instructions "test" >/dev/null
  done
  export SAVIA_AUTOMATIONS_OUTPUT="$FIXDIR/out"
  run bash scripts/savia-automations.sh run-due --max 1
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"run-due: 1/2 tasks processed, 1 recorded without execution"* ]]
  run bash scripts/savia-automations.sh run-due
  [[ "$output" == *"run-due: 1/1 tasks processed, 1 recorded without execution"* ]]
}

# ── R3: log de instalación ─────────────────────────────────────────────────

@test "R3a: log escribe y nunca falla" {
  run bash scripts/savia-bootstrap-log.sh write paso-test 0 "ok"
  [[ "$status" -eq 0 ]]
  bash scripts/savia-bootstrap-log.sh recent 2>&1 | grep -q "paso-test"
}

@test "R3b: log con fallo (exit 1) no rompe el arranque" {
  run bash scripts/savia-bootstrap-log.sh write paso-fallo 1 "crash simulado"
  [[ "$status" -eq 0 ]]
}

# ── R4: instalador central ─────────────────────────────────────────────────

@test "R4a: savia-install existe, es ejecutable y sintácticamente válido" {
  [[ -x scripts/savia-install.sh ]]
  bash -n scripts/savia-install.sh
}

@test "R4b: savia-install --dry-run finaliza 0 y loguea start" {
  run bash scripts/savia-install.sh --dry-run --quiet
  [[ "$status" -eq 0 ]]
  bash scripts/savia-bootstrap-log.sh recent 2>&1 | grep -q "savia-install"
}

@test "R4c: idempotente — dos dry-runs no rompen" {
  bash scripts/savia-install.sh --dry-run --quiet >/dev/null 2>&1
  run bash scripts/savia-install.sh --dry-run --quiet
  [[ "$status" -eq 0 ]]
}

# ── R2/P8: orquestador diario queda con next_run materializado ─────────────

@test "P8a: tarea sagi-orquestador tiene cron computado tras compute" {
  if ! bash scripts/savia-automations.sh list 2>/dev/null | grep -q "sagi-orquestador-diario"; then
    bash scripts/savia-automations.sh create --name sagi-orquestador-diario \
      --schedule "daily 08:30" --instructions "orquestador" >/dev/null 2>&1
  fi
  bash scripts/savia-automations.sh compute >/dev/null 2>&1
  bash scripts/savia-automations.sh list 2>&1 | grep -q "next: "
}

# ── R5: calibración self-heal (P2) ─────────────────────────────────────────

@test "R5a: meta-monitor falla abierto sin curva (calibración default 0.5)" {
  run bash scripts/meta-monitor.sh --task t-consol --confidence 80 \
    --divergence 0.2 --evidence 0.9 --calibration-file "$FIXDIR/no-cal.json"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json;d=json.load(sys.stdin);assert d['calibration']==0.5"
}

@test "R5b: meta-recalibrate crea la curva al primer uso (no requiere dir previo)" {
  run bash scripts/meta-recalibrate.sh --task t-consol --predicted 80 \
    --outcome success --calibration-file "$FIXDIR/nuevo/cal.json"
  [[ "$status" -eq 0 ]]
  [[ -f "$FIXDIR/nuevo/cal.json" ]]
}