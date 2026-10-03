#!/usr/bin/env bats
# SE-376 — automation-scheduler: cálculo de next_run con cron real y CLI con códigos de salida.
# Fallos medidos el sábado 2026-10-03: '0 8 * * 1' caía en martes, '0 9 * * 1-5' en sábado,
# '*/15 * * * *' no se programaba nunca, run-due no actualizaba run_count/last_status.
# Ref: docs/propuestas/SE-376 quality debt burn-down; skill .claude/skills/automation-scheduler/SKILL.md
# Código: scripts/automations/cron.py (parser), store.py (next_run, due), savia-automations.sh (CLI).
set -uo pipefail

SCRIPT="scripts/savia-automations.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$REPO_ROOT/$SCRIPT"
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  export SAVIA_AUTOMATIONS_DIR="$WORK/automations"
  export SAVIA_AUTOMATIONS_OUTPUT="$WORK/output"
  # Hora local fija: el cron se interpreta en hora local (CEST = UTC+2 en octubre).
  export TZ="Europe/Madrid"
}

teardown() { rm -rf "$WORK"; }

# next_cron <expr> [now-utc-iso] → imprime "<utc-iso> <día local> <hora local>" o "None".
# now por defecto: sábado 2026-10-03 12:00 CEST.
next_cron() {
  python3 - "$REPO_ROOT/scripts" "$WORK" "$1" "${2:-2026-10-03T10:00:00+00:00}" <<'PY'
import sys
from datetime import datetime
sys.path.insert(0, sys.argv[1])
from automations.store import TaskStore
from automations.models import Schedule
store = TaskStore(sys.argv[2])
r = store._compute_next_run(Schedule(kind="cron", cron=sys.argv[3]),
                            now=datetime.fromisoformat(sys.argv[4]))
if r is None:
    print("None")
else:
    loc = datetime.fromisoformat(r).astimezone()
    print(r, loc.strftime("%a"), loc.strftime("%Y-%m-%d %H:%M"))
PY
}

task_field() {  # task_field <id> <campo>
  python3 -c 'import json,sys; t=[x for x in json.load(open(sys.argv[1])) if x["id"]==sys.argv[2]][0]; print(t[sys.argv[3]])' \
    "$SAVIA_AUTOMATIONS_DIR/tasks.json" "$1" "$2"
}

created_id() { sed -n 's/^created \([^:]*\):.*/\1/p' <<<"$output"; }

@test "safety: la CLI declara set -euo pipefail y propaga el exit de Python" {
  head -5 "$CLI" | grep -q "set -euo pipefail"
  run bash "$CLI" show
  [ "$status" -ne 0 ]
}

# ── Día de la semana: cron 0=domingo, 1=lunes … 7=domingo ───────────────────

@test "cron: '0 8 * * 1' desde un sábado cae el lunes 05 a las 08:00 locales (06:00 UTC)" {
  run next_cron "0 8 * * 1"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-10-05T06:00:00+00:00 Mon 2026-10-05 08:00" ]
}

@test "cron: '0 8 * * 5' cae el viernes 09, no el sábado" {
  run next_cron "0 8 * * 5"
  [ "$output" = "2026-10-09T06:00:00+00:00 Fri 2026-10-09 08:00" ]
}

@test "cron: '0 8 * * 0' y '0 8 * * 7' caen ambos el domingo 04" {
  run next_cron "0 8 * * 0"
  [[ "$output" == *" Sun 2026-10-04 08:00" ]]
  run next_cron "0 8 * * 7"
  [[ "$output" == *" Sun 2026-10-04 08:00" ]]
}

@test "cron: nombres de día 'mon-fri' equivalen a 1-5" {
  run next_cron "0 9 * * mon-fri"
  [[ "$output" == *" Mon 2026-10-05 09:00" ]]
}

# ── Rangos, listas y pasos ──────────────────────────────────────────────────

@test "cron: '0 9 * * 1-5' desde el sábado salta al lunes, no al sábado" {
  run next_cron "0 9 * * 1-5"
  [[ "$output" == *" Mon 2026-10-05 09:00" ]]
  # Desde el lunes a las 10:00 locales, el siguiente es el martes.
  run next_cron "0 9 * * 1-5" "2026-10-05T08:00:00+00:00"
  [[ "$output" == *" Tue 2026-10-06 09:00" ]]
}

@test "cron boundary: '*/15 * * * *' programa el siguiente cuarto de hora" {
  run next_cron "*/15 * * * *" "2026-10-03T10:07:00+00:00"
  [ "$output" = "2026-10-03T10:15:00+00:00 Sat 2026-10-03 12:15" ]
}

@test "cron: lista '0 8,20 * * *' a las 12:00 elige las 20:00 del mismo día" {
  run next_cron "0 8,20 * * *"
  [[ "$output" == *" Sat 2026-10-03 20:00" ]]
}

@test "cron: paso sobre rango '0 */6 * * *' y '30 9-17/4 * * *'" {
  run next_cron "0 */6 * * *"
  [[ "$output" == *" Sat 2026-10-03 18:00" ]]
  run next_cron "30 9-17/4 * * *"
  [[ "$output" == *" Sat 2026-10-03 13:30" ]]
}

# ── Día del mes y semántica OR de cron ──────────────────────────────────────

@test "cron: mensual '0 0 1 * *' (más de 8 días vista) cae el 1 de noviembre" {
  run next_cron "0 0 1 * *"
  [[ "$output" == *" Sun 2026-11-01 00:00" ]]
}

@test "cron: '0 0 13 * 5' es día 13 O viernes ⇒ viernes 09, antes que el 13" {
  run next_cron "0 0 13 * 5"
  [[ "$output" == *" Fri 2026-10-09 00:00" ]]
}

@test "cron: '0 0 13 * *' con dow '*' exige el día 13" {
  run next_cron "0 0 13 * *"
  [[ "$output" == *" Tue 2026-10-13 00:00" ]]
}

@test "cron boundary: '0 0 29 2 *' encuentra el 29 de febrero de 2028 (más de un año vista)" {
  run next_cron "0 0 29 2 *"
  [[ "$output" == *" Tue 2028-02-29 00:00" ]]
}

# ── Hora local y cambio de hora ─────────────────────────────────────────────

@test "cron boundary: tras el cambio a horario de invierno las 08:00 locales pasan a 07:00 UTC" {
  run next_cron "0 8 * * *" "2026-10-25T12:00:00+00:00"
  [ "$output" = "2026-10-26T07:00:00+00:00 Mon 2026-10-26 08:00" ]
}

# ── Crons inválidos o imposibles ────────────────────────────────────────────

@test "cron: inválidos devuelven None sin excepción" {
  for expr in "61 * * * *" "0 25 * * *" "0 0 * * 1-" "0 0 * * 5-1" "*/0 * * * *" "a b c d e" "0 0 * *"; do
    run next_cron "$expr"
    [ "$status" -eq 0 ]
    [ "$output" = "None" ] || { echo "no rechazado: $expr → $output"; return 1; }
  done
}

@test "create: cron inválido sale con 2, lo explica y no guarda la tarea" {
  run bash "$CLI" create --name roto --schedule "0 8 * * 8" --instructions x
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid schedule"*"day-of-week"* ]]
  run bash "$CLI" list
  [ "$output" = "(no tasks)" ]
}

@test "create: cron que nunca dispara ('0 0 31 2 *') se rechaza con 2" {
  run bash "$CLI" create --name nunca --schedule "0 0 31 2 *" --instructions x
  [ "$status" -eq 2 ]
  [[ "$output" == *"never fires"* ]]
}

@test "create: texto que no es cron ni fecha ISO se rechaza con 2" {
  run bash "$CLI" create --name raro --schedule "mañana" --instructions x
  [ "$status" -eq 2 ]
  [ ! -s "$SAVIA_AUTOMATIONS_DIR/tasks.json" ] || [ "$(cat "$SAVIA_AUTOMATIONS_DIR/tasks.json")" = "[]" ]
}

@test "create: forma humana de una palabra ('daily') es cron, no una fecha" {
  run bash "$CLI" create --name diario --schedule daily --instructions x
  [ "$status" -eq 0 ]
  id="$(created_id)"
  [ "$(task_field "$id" schedule | grep -o "'kind': '[a-z]*'")" = "'kind': 'cron'" ]
}

# ── CLI: códigos de salida ──────────────────────────────────────────────────

@test "cli: id nonexistent ⇒ exit 1 en show, run, disable, enable, delete e history" {
  for cmd in show run disable enable delete history; do
    run bash "$CLI" "$cmd" nope1234
    [ "$status" -eq 1 ] || { echo "$cmd devolvió $status"; return 1; }
    [[ "$output" == *"not found: nope1234"* ]]
  done
}

@test "cli: falta el argumento ⇒ exit 2 con uso; comando desconocido ⇒ exit 2" {
  run bash "$CLI" show
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: show"* ]]
  run bash "$CLI" frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: frobnicate"* ]]
  run bash "$CLI" help
  [ "$status" -eq 0 ]
}

# ── run-due: contadores y next_run ──────────────────────────────────────────

@test "run-due: tarea cron vencida se ejecuta, cuenta el run y reprograma al futuro" {
  run bash "$CLI" create --name cada-cuarto --schedule "*/15 * * * *" --instructions x
  [ "$status" -eq 0 ]
  id="$(created_id)"
  python3 - "$SAVIA_AUTOMATIONS_DIR/tasks.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d[0]["next_run"] = "2020-01-01T00:00:00+00:00"
json.dump(d, open(p, "w"))
PY
  run bash "$CLI" list
  [[ "$output" == *"cada-cuarto DUE"* ]]
  run bash "$CLI" run-due
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-due $id (cada-cuarto): recorded"* ]]
  [ "$(task_field "$id" run_count)" = "1" ]
  [ "$(task_field "$id" last_status)" = "recorded" ]
  next="$(task_field "$id" next_run)"
  python3 -c 'import sys; from datetime import datetime, timezone; assert datetime.fromisoformat(sys.argv[1]) > datetime.now(timezone.utc)' "$next"
  run bash "$CLI" run-due
  [[ "$output" == *"no due tasks"* ]]
}

@test "run-due: tarea 'once' vencida se ejecuta una sola vez" {
  run bash "$CLI" create --name una-vez --schedule "2026-01-01T09:00:00" --instructions x
  [ "$status" -eq 0 ]
  id="$(created_id)"
  run bash "$CLI" run-due
  [[ "$output" == *"1/1 tasks processed, 1 recorded without execution"* ]]
  [ "$(task_field "$id" next_run)" = "None" ]
  run bash "$CLI" run-due
  [[ "$output" == *"no due tasks"* ]]
}

@test "run: ejecución manual actualiza run_count y deja el run en history" {
  run bash "$CLI" create --name manual --schedule "0 8 * * 1" --instructions x
  id="$(created_id)"
  run bash "$CLI" run "$id"
  [ "$status" -eq 0 ]
  [ "$(task_field "$id" run_count)" = "1" ]
  run bash "$CLI" history "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recorded  manual"* ]]
}

# ── estado honesto: sin ejecución real no hay 'completed' ──────────────────
# Fallo medido el 2026-10-03: 'run' escribía las instrucciones en un .md sin invocar
# skill ni agente y registraba el run como 'completed' (history ✓, list last: completed).

@test "run: sin ejecución real el run queda 'recorded', nunca 'completed', en run, history, list y salida" {
  run bash "$CLI" create --name honesto --schedule "0 8 * * 1" --instructions "haz algo"
  id="$(created_id)"
  run bash "$CLI" run "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *": recorded"* ]]
  [[ "$output" == *"not executed"* ]]
  [[ "$output" != *"completed"* ]] || { echo "run dice completed: $output"; return 1; }
  [ "$(task_field "$id" last_status)" = "recorded" ]
  run bash "$CLI" history "$id"
  [[ "$output" == *"recorded  manual"* ]]
  [[ "$output" == *"not executed"* ]]
  [[ "$output" != *"completed"* ]] || { echo "history dice completed: $output"; return 1; }
  [[ "$output" != *$'\u2713'* ]]
  run bash "$CLI" list
  [[ "$output" == *"last: recorded (not executed)"* ]]
  out_md="$(ls "$SAVIA_AUTOMATIONS_OUTPUT/$id"/*.md)"
  run grep -c "Completed" "$out_md"
  [ "$output" = "0" ]
  grep -q "Recorded, not executed" "$out_md"
}

@test "run error: directorio de salida imposible ⇒ status 'error', exit 1 y nunca 'recorded'" {
  run bash "$CLI" create --name rota --schedule "0 8 * * 1" --instructions x
  id="$(created_id)"
  : > "$WORK/no-es-dir"
  SAVIA_AUTOMATIONS_OUTPUT="$WORK/no-es-dir" run bash "$CLI" run "$id"
  [ "$status" -eq 1 ]
  [[ "$output" == *": error"* ]]
  [ "$(task_field "$id" last_status)" = "error" ]
}

@test "run-due boundary: empty queue keeps 'no due tasks' and records nothing" {
  run bash "$CLI" create --name futura --schedule "0 8 * * 1" --instructions x
  id="$(created_id)"
  run bash "$CLI" run-due
  [ "$status" -eq 0 ]
  [[ "$output" == *"no due tasks"* ]]
  [ "$(task_field "$id" run_count)" = "0" ]
}

@test "due: compara como fecha, no como texto (offsets distintos)" {
  python3 - "$REPO_ROOT/scripts" "$WORK" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from automations.store import TaskStore
from automations.models import ScheduledTask, Schedule
s = TaskStore(sys.argv[2])
t = ScheduledTask(id="t1", name="n", description="", instructions="",
                  schedule=Schedule(kind="cron", cron="* * * * *"))
# 10:30+02:00 = 08:30Z: vencida a las 09:00Z aunque "10:30" > "09:00" como texto.
t.next_run = "2026-10-03T10:30:00+02:00"
assert s.is_due(t, "2026-10-03T09:00:00Z")
assert not s.is_due(t, "2026-10-03T08:00:00Z")
PY
}
