#!/usr/bin/env bats
# test-capacity-planning.bats — calibracion SE-376 de la skill capacity-planning
# Ref: .claude/skills/capacity-planning/SKILL.md
# Ref: .claude/skills/capacity-planning/references/capacity-formula.md
# Ref: docs/rules/domain/pm-workflow.md
# Ejecutable real de la skill: scripts/capacity-calculator.py. Datos sinteticos
# en mktemp -d; las horas esperadas se calculan a mano con la formula
# horas = (dias_habiles - dias_off) * horas_dia * factor_foco.

SCRIPT="scripts/capacity-calculator.py"

setup() {
  set -uo pipefail
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PY="$REPO_ROOT/$SCRIPT"
  TMPDIR_TEST="$(mktemp -d)"
  D="$TMPDIR_TEST/datos con espacios"
  mkdir -p "$D"
  # Sprint de 2 semanas sin festivos: 2026-09-07 (lunes) a 2026-09-18 (viernes) = 10 dias
  S1=(--sprint-start 2026-09-07 --sprint-end 2026-09-18)
}

teardown() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}

items() { printf '%s' "$1" > "$D/items.json"; }

# jget <expr python sobre r>: lee el JSON de $output
jget() {
  printf '%s' "$output" | python3 -c "import json,sys; r=json.load(sys.stdin); print($1)"
}

@test "script existe, compila y es ejecutable con python3" {
  [ -f "$PY" ]
  run python3 -m py_compile "$PY"
  [ "$status" -eq 0 ]
}

@test "formula positiva: 10 dias habiles * 8h * 0.75 = 60h y utilizacion 50%" {
  items '[{"asignado":"Ana","restante_h":30,"completado_h":0}]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "60.0" ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["utilizacion_pct"]')" = "50.0" ]
}

@test "--focus-factor y --team-hours-per-day se aplican (antes se ignoraban)" {
  items '[{"asignado":"Ana","restante_h":30}]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --focus-factor 0.5 --team-hours-per-day 6 --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "30.0" ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["utilizacion_pct"]')" = "100.0" ]
}

@test "locale es_ES: coma decimal en --focus-factor y en horas de items" {
  items '[{"asignado":"Ana","restante_h":"4,5","completado_h":"1,5"}]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --focus-factor 0,5 --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["remaining_h"]')" = "4.5" ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "40.0" ]
}

@test "limite 85% exacto es AL LIMITE (doc: 85-100%), no OK" {
  items '[{"asignado":"Ana","restante_h":51}]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [[ "$(jget 'r["carga_por_persona"]["Ana"]["estado"]')" == *"AL LÍMITE"* ]]
}

@test "limite 100% exacto es AL LIMITE y 100.1% es SOBRE-CARGADO" {
  items '[{"asignado":"Ana","restante_h":60},{"asignado":"Bo","restante_h":60.06}]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [[ "$(jget 'r["carga_por_persona"]["Ana"]["estado"]')" == *"AL LÍMITE"* ]]
  [[ "$(jget 'r["carga_por_persona"]["Bo"]["estado"]')" == *"SOBRE-CARGADO"* ]]
}

@test "sprint solo de fin de semana: zero horas da SIN DATOS, sin ZeroDivisionError" {
  items '[{"asignado":"Ana","restante_h":5}]'
  run python3 "$PY" --items "$D/items.json" --sprint-start 2026-09-12 --sprint-end 2026-09-13 --output-json
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["utilizacion_pct"]')" = "None" ]
  [[ "$(jget 'r["carga_por_persona"]["Ana"]["estado"]')" == *"SIN DATOS"* ]]
}

@test "tabla con zero horas disponibles muestra SIN DATOS, no OK" {
  items '[{"asignado":"Ana","restante_h":5}]'
  run python3 "$PY" --items "$D/items.json" --sprint-start 2026-09-12 --sprint-end 2026-09-13
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIN DATOS"* ]]
  [[ "$output" != *"🟢 OK"* ]]
}

@test "fechas invertidas se rechazan con error claro (antes 0h y OK)" {
  items '[{"asignado":"Ana","restante_h":5}]'
  run python3 "$PY" --items "$D/items.json" --sprint-start 2026-09-18 --sprint-end 2026-09-07
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "fecha invalida se rechaza sin traceback" {
  items '[{"asignado":"Ana","restante_h":5}]'
  run python3 "$PY" --items "$D/items.json" --sprint-start 2026-13-01 --sprint-end 2026-09-18
  [ "$status" -ne 0 ]
  [[ "$output" != *"Traceback"* ]]
}

@test "solo una de las dos fechas es error (reject)" {
  items '[{"asignado":"Ana","restante_h":5}]'
  run python3 "$PY" --items "$D/items.json" --sprint-start 2026-09-07
  [ "$status" -ne 0 ]
  [[ "$output" == *"--sprint-end"* ]]
}

@test "focus factor fuera de (0,1] es invalid y se rechaza" {
  items '[{"asignado":"Ana","restante_h":5}]'
  run python3 "$PY" --items "$D/items.json" --focus-factor 1.5
  [ "$status" -ne 0 ]
  run python3 "$PY" --items "$D/items.json" --focus-factor 0
  [ "$status" -ne 0 ]
}

@test "horas no numericas en un item dan error claro, sin traceback" {
  items '[{"asignado":"Ana","restante_h":"mucho"}]'
  run python3 "$PY" --items "$D/items.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "stream de objetos de azdevops-queries.sh items se acepta (antes JSON invalido)" {
  printf '{"asignado":"Ana","restante_h":3,"estado":"Active"}\n{"asignado":"Bo","restante_h":2,"estado":"New"}\n' > "$D/items.json"
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'sorted(r["carga_por_persona"])')" = "['Ana', 'Bo']" ]
}

@test "formato API con fields System.AssignedTo y System.State" {
  items '{"value":[{"fields":{"System.AssignedTo":{"displayName":"Ana"},"System.State":"Active","Microsoft.VSTS.Scheduling.RemainingWork":6,"Microsoft.VSTS.Scheduling.CompletedWork":2}}]}'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ana"* ]]
  [[ "$output" == *"Active"* ]]
  [[ "$output" != *"Desconocido"* ]]
}

@test "Sin asignar no recibe capacidad ni alerta de sobre-carga" {
  items '[{"restante_h":80},{"asignado":"Ana","restante_h":10}]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sin asignar"* ]]
  [[ "$output" != *"Sin asignar: SOBRE-CARGADO"* ]]
}

@test "capacidades de azdevops-queries.sh capacities: capacityPerDay y dias_off" {
  items '[{"asignado":"Ana","restante_h":27}]'
  printf '%s\n' '{"persona":"Ana","email":"a@x","actividades":[{"name":"Development","capacityPerDay":4},{"name":"Testing","capacityPerDay":2}],"dias_off":[{"start":"2026-09-10T00:00:00Z","end":"2026-09-11T00:00:00Z"}]}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  # (10 - 2) dias * 6 h/dia * 0.75 = 36h; 27/36 = 75%
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "36.0" ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["utilizacion_pct"]')" = "75.0" ]
}

@test "capacidades en formato API crudo (value/teamMember/activities/daysOff)" {
  items '[{"asignado":"Ana","restante_h":10}]'
  printf '%s' '{"value":[{"teamMember":{"displayName":"Ana"},"activities":[{"name":"Development","capacityPerDay":5}],"daysOff":[]}],"count":1}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "37.5" ]
}

@test "capacidad configurada a zero en AzDO es SIN DATOS (empty activities)" {
  items '[{"asignado":"Ana","restante_h":10}]'
  printf '%s' '{"value":[{"teamMember":{"displayName":"Ana"},"activities":[],"daysOff":[]}]}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [[ "$(jget 'r["carga_por_persona"]["Ana"]["estado"]')" == *"SIN DATOS"* ]]
}

@test "mapa legacy {persona: {horas_disponibles}} sigue funcionando en tabla y JSON" {
  items '[{"asignado":"Ana","restante_h":20}]'
  printf '%s' '{"Ana":{"horas_disponibles":40}}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["utilizacion_pct"]')" = "50.0" ]
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"40.0h"* ]]
}

@test "--capacities inexistente es error, no WARN silencioso" {
  items '[{"asignado":"Ana","restante_h":20}]'
  run python3 "$PY" --items "$D/items.json" --capacities "$D/no-existe.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "dias off de equipo (teamdaysoff) se restan a todos, union con los personales" {
  items '[{"asignado":"Ana","restante_h":10}]'
  printf '%s' '{"daysOff":[{"start":"2026-09-10T00:00:00Z","end":"2026-09-10T00:00:00Z"}]}' > "$D/team.json"
  printf '%s\n' '{"persona":"Ana","actividades":[{"capacityPerDay":8}],"dias_off":[{"start":"2026-09-10T00:00:00Z","end":"2026-09-11T00:00:00Z"}]}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" --team-days-off "$D/team.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  # union {10, 11} -> 8 dias * 8 * 0.75 = 48h (sin doble descuento del dia 10)
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "48.0" ]
}

@test "dias off en fin de semana no restan capacidad" {
  items '[{"asignado":"Ana","restante_h":10}]'
  printf '%s\n' '{"persona":"Ana","actividades":[{"capacityPerDay":8}],"dias_off":[{"start":"2026-09-12T00:00:00Z","end":"2026-09-13T00:00:00Z"}]}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "60.0" ]
}

@test "festivo por defecto de 2026 (12 octubre) se descuenta" {
  items '[{"asignado":"Ana","restante_h":10}]'
  run python3 "$PY" --items "$D/items.json" --sprint-start 2026-10-12 --sprint-end 2026-10-16 --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "24.0" ]
}

@test "sprint fuera de 2026 sin --team-days-off avisa de festivos no cubiertos" {
  items '[{"asignado":"Ana","restante_h":10}]'
  run python3 "$PY" --items "$D/items.json" --sprint-start 2027-01-04 --sprint-end 2027-01-08
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "items vacios (empty) producen informe sin personas y exit 0" {
  items '[]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]')" = "{}" ]
}

@test "fichero de items inexistente es error exit 1" {
  run python3 "$PY" --items "$D/nada.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no encontrado"* ]]
}

@test "large: 2000 items de 20 personas suman bien" {
  python3 -c "
import json
print(json.dumps([{'asignado':'P%02d'%(i%20),'restante_h':1.5} for i in range(2000)]))" > "$D/items.json"
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'len(r["carga_por_persona"])')" = "20" ]
  [ "$(jget 'r["carga_por_persona"]["P07"]["remaining_h"]')" = "150.0" ]
}

@test "dias_habiles_entre con festivos vacios (empty) no vuelve a los de 2026" {
  run python3 -c "
import importlib.util, sys
from datetime import date
spec = importlib.util.spec_from_file_location('cc', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.dias_habiles_entre(date(2026,10,12), date(2026,10,16), [])))
print(len(m.dias_habiles_entre(date(2026,10,12), date(2026,10,16))))" "$PY"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "5" ]
  [ "${lines[1]}" = "4" ]
}

@test "dia off de equipo fuera de los personales tambien se resta (union real)" {
  items '[{"asignado":"Ana","restante_h":10}]'
  printf '%s' '["2026-09-14"]' > "$D/team.json"
  printf '%s\n' '{"persona":"Ana","actividades":[{"capacityPerDay":8}],"dias_off":[{"start":"2026-09-10T00:00:00Z","end":"2026-09-10T00:00:00Z"}]}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" --team-days-off "$D/team.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  # personal {10} + equipo {14} -> 8 dias * 8 * 0.75 = 48h
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "48.0" ]
}

@test "--team-days-off sin --capacities resta el dia a todos" {
  items '[{"asignado":"Ana","restante_h":10},{"asignado":"Bo","restante_h":10}]'
  printf '%s' '{"daysOff":[{"start":"2026-09-10T00:00:00Z","end":"2026-09-10T00:00:00Z"}]}' > "$D/team.json"
  run python3 "$PY" --items "$D/items.json" --team-days-off "$D/team.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "54.0" ]
  [ "$(jget 'r["carga_por_persona"]["Bo"]["horas_disponibles"]')" = "54.0" ]
}

@test "utilizacion = (restante + completado) / disponibles del sprint completo" {
  items '[{"asignado":"Ana","restante_h":15,"completado_h":15}]'
  run python3 "$PY" --items "$D/items.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  # (15 + 15) / 60 = 50%; solo restante daria 25%
  [ "$(jget 'r["carga_por_persona"]["Ana"]["utilizacion_pct"]')" = "50.0" ]
}

@test "sprint planning: miembros de capacities sin items salen con carga zero" {
  items '[]'
  printf '%s\n' '{"persona":"Ana","actividades":[{"capacityPerDay":8}],"dias_off":[]}' '{"persona":"Bo","actividades":[{"capacityPerDay":4}],"dias_off":[]}' > "$D/caps.json"
  run python3 "$PY" --items "$D/items.json" --capacities "$D/caps.json" "${S1[@]}" --output-json
  [ "$status" -eq 0 ]
  [ "$(jget 'r["carga_por_persona"]["Ana"]["horas_disponibles"]')" = "60.0" ]
  [ "$(jget 'r["carga_por_persona"]["Bo"]["horas_disponibles"]')" = "30.0" ]
  [ "$(jget 'r["carga_por_persona"]["Bo"]["items"]')" = "0" ]
  [ "$(jget 'r["carga_por_persona"]["Bo"]["utilizacion_pct"]')" = "0.0" ]
}
