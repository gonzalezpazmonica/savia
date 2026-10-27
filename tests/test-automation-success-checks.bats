#!/usr/bin/env bats
# SE-445 S4 (AC7) — success_checks y max_retries en las automatizaciones.
# Un run que "termino" sin cumplir su criterio de exito cuenta como fallido; el reintento recibe
# el fallo del check como entrada nueva y un reintento con entrada identica se rechaza
# (patron prohibido n3 de feedback_root_cause_always).
# Ref: docs/specs/SE-445-autonomous-execution-safeguards.spec.md
# Codigo: scripts/automations/runner.py (run_with_checks), savia-automations.sh (--success-check).
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$REPO_ROOT/scripts/savia-automations.sh"
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  export SAVIA_AUTOMATIONS_DIR="$WORK/automations"
  export SAVIA_AUTOMATIONS_OUTPUT="$WORK/output"
  export TZ="Europe/Madrid"
}

teardown() { rm -rf "$WORK"; }

create_task() { # extra args...
  run bash "$CLI" create --name "fx" --schedule "0 9 * * 1-5" --instructions "genera out.md" "$@"
  [ "$status" -eq 0 ]
  TASK_ID=$(printf '%s\n' "$output" | sed -n 's/^created \([^:]*\):.*/\1/p')
  [ -n "$TASK_ID" ]
}

# py <code> : ejecuta python con scripts/ en el path; el codigo recibe WORK como argv[1].
py() { python3 - "$WORK" <<PY
import sys, asyncio
sys.path.insert(0, "$REPO_ROOT/scripts")
$1
PY
}

@test "AC7: success_check que no se cumple marca el run como failed (CLI)" {
  create_task --success-check "test -f $WORK/out.md"
  run bash "$CLI" run "$TASK_ID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed"* ]]
  [[ "$output" == *"test -f $WORK/out.md"* ]]
}

@test "AC7: success_check cumplido mantiene el estado del runner (recorded, no failed)" {
  touch "$WORK/out.md"
  create_task --success-check "test -f $WORK/out.md"
  run bash "$CLI" run "$TASK_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recorded"* ]]
}

@test "AC7: sin success_checks el comportamiento no cambia" {
  create_task
  run bash "$CLI" run "$TASK_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recorded"* ]]
}

@test "AC7: max_retries se limita a 3 y se rechaza un valor invalido" {
  run bash "$CLI" create --name fx --schedule "0 9 * * 1-5" --instructions x --max-retries 9
  [ "$status" -eq 2 ]
  run bash "$CLI" create --name fx --schedule "0 9 * * 1-5" --instructions x --max-retries abc
  [ "$status" -eq 2 ]
}

@test "AC7: show expone success_checks y max_retries" {
  create_task --success-check "test -f a" --success-check "test -f b" --max-retries 2
  run bash "$CLI" show "$TASK_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"max_retries": 2'* ]]
  [[ "$output" == *'"test -f b"'* ]]
}

@test "AC7: con max_retries=2 se reintenta como mucho 2 veces y cada reintento recibe el check fallido" {
  run py '
from automations.models import ScheduledTask, Schedule
from automations.runner import run_with_checks
import os
work = sys.argv[1]
counter = os.path.join(work, "n")
# La salida del check cambia en cada intento: la entrada del reintento es nueva cada vez.
check = f"n=$(cat {counter} 2>/dev/null || echo 0); echo $((n+1)) > {counter}; echo intento-$n; test -f {work}/out.md"
t = ScheduledTask(id="t1", name="fx", description="", instructions="genera out.md",
                  schedule=Schedule(kind="once"), success_checks=[check], max_retries=2)
seen = []
async def executor(task, trigger, *, output_dir, instructions):
    seen.append(instructions)
    from automations.runner import run_scheduled_task
    return await run_scheduled_task(task, trigger, output_dir=output_dir, instructions=instructions)
res = asyncio.run(run_with_checks(t, "manual", output_dir=work + "/o", check_cwd=work, executor=executor))
print("status=" + res.status, "attempts=" + str(res.attempts), "calls=" + str(len(seen)))
print("first_has_feedback=" + str("Fallo del criterio" in seen[0]))
print("retry1_has_feedback=" + str("Fallo del criterio" in seen[1] and "intento-0" in seen[1]))
print("retry2_has_feedback=" + str("Fallo del criterio" in seen[2] and "intento-1" in seen[2]))
'
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=failed attempts=3 calls=3"* ]]
  [[ "$output" == *"first_has_feedback=False"* ]]
  [[ "$output" == *"retry1_has_feedback=True"* ]]
  [[ "$output" == *"retry2_has_feedback=True"* ]]
}

@test "AC7: un reintento que se ejecutaria con entrada identica se rechaza" {
  run py '
from automations.models import ScheduledTask, Schedule
from automations.runner import run_with_checks
work = sys.argv[1]
t = ScheduledTask(id="t2", name="fx", description="", instructions="genera out.md",
                  schedule=Schedule(kind="once"), success_checks=["echo mismo-fallo; false"], max_retries=3)
res = asyncio.run(run_with_checks(t, "manual", output_dir=work + "/o", check_cwd=work))
print("status=" + res.status, "attempts=" + str(res.attempts))
print("rejected=" + str("entrada identica" in (res.error or "")))
'
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=failed attempts=2"* ]]
  [[ "$output" == *"rejected=True"* ]]
}

@test "AC7: el reintento que cumple el check termina bien" {
  run py '
from automations.models import ScheduledTask, Schedule
from automations.runner import run_with_checks, run_scheduled_task
import os
work = sys.argv[1]
async def executor(task, trigger, *, output_dir, instructions):
    r = await run_scheduled_task(task, trigger, output_dir=output_dir, instructions=instructions)
    if "Fallo del criterio" in instructions:
        open(os.path.join(work, "out.md"), "w").write("ok")
    return r
t = ScheduledTask(id="t3", name="fx", description="", instructions="genera out.md",
                  schedule=Schedule(kind="once"), success_checks=[f"test -f {work}/out.md"], max_retries=2)
res = asyncio.run(run_with_checks(t, "manual", output_dir=work + "/o", check_cwd=work, executor=executor))
print("status=" + res.status, "attempts=" + str(res.attempts))
'
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=recorded attempts=2"* ]]
}

@test "AC7: un check colgado agota su timeout y cuenta como fallo" {
  run py '
from automations.models import ScheduledTask, Schedule
from automations.runner import run_with_checks
work = sys.argv[1]
t = ScheduledTask(id="t4", name="fx", description="", instructions="x",
                  schedule=Schedule(kind="once"), success_checks=["sleep 30"], max_retries=0)
res = asyncio.run(run_with_checks(t, "manual", output_dir=work + "/o", check_cwd=work, check_timeout=1))
print("status=" + res.status, "timeout=" + str("timeout" in (res.error or "")))
'
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=failed timeout=True"* ]]
}

@test "AC7: una tarea guardada sin los campos nuevos se carga con valores por defecto" {
  run py '
from automations.models import ScheduledTask
t = ScheduledTask.from_dict({"id": "x", "name": "n"})
print(t.success_checks, t.max_retries)
'
  [ "$status" -eq 0 ]
  [[ "$output" == "[] 0" ]]
}

# ── S03k: ciclo de vida de la CLI (list, enable/disable, delete, history, output, compute, init-defaults, run-due) ──

@test "S03k auto: list sin tareas imprime '(no tasks)'" {
  run bash "$CLI" list
  [ "$status" -eq 0 ]
  [ "$output" = "(no tasks)" ]
}

@test "S03k auto: list muestra id, nombre, cron, estado habilitada y 'never'" {
  create_task
  run bash "$CLI" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[✓] $TASK_ID  fx"* ]]
  [[ "$output" == *"schedule: cron=0 9 * * 1-5"* ]]
  [[ "$output" == *"last: never"* ]]
  [[ "$output" == *"runs: 0"* ]]
}

@test "S03k auto: disable marca la tarea, la saca de --enabled y enable la devuelve" {
  create_task
  run bash "$CLI" disable "$TASK_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == "disabled $TASK_ID: fx" ]]
  run bash "$CLI" list
  [[ "$output" == *"[✗] $TASK_ID"* ]]
  run bash "$CLI" list --enabled
  [ "$output" = "(no tasks)" ]
  run bash "$CLI" enable "$TASK_ID"
  [[ "$output" == "enabled $TASK_ID: fx" ]]
  run bash "$CLI" list --enabled
  [[ "$output" == *"[✓] $TASK_ID"* ]]
}

@test "S03k auto: una tarea deshabilitada no se ejecuta en run-due" {
  create_task
  py 'import json,pathlib
p=pathlib.Path(sys.argv[1])/"automations"/"tasks.json"
d=json.loads(p.read_text())
ts=d["tasks"] if isinstance(d,dict) and "tasks" in d else d
for t in (ts.values() if isinstance(ts,dict) else ts): t["next_run"]="2020-01-01T00:00:00+00:00"
p.write_text(json.dumps(d))'
  bash "$CLI" disable "$TASK_ID"
  run bash "$CLI" run-due
  [ "$status" -eq 0 ]
  [[ "$output" == *"no due tasks"* ]]
}

@test "S03k auto: delete borra la tarea y un segundo delete falla con exit 1" {
  create_task
  run bash "$CLI" delete "$TASK_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "deleted $TASK_ID" ]
  run bash "$CLI" list
  [ "$output" = "(no tasks)" ]
  run bash "$CLI" delete "$TASK_ID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found: $TASK_ID"* ]]
}

@test "S03k auto: show devuelve JSON con las instrucciones y los success_checks guardados" {
  create_task --success-check "test -f a" --success-check "test -f b" --max-retries 2
  run bash "$CLI" show "$TASK_ID"
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["instructions"] == "genera out.md", d
assert d["success_checks"] == ["test -f a", "test -f b"], d
assert d["max_retries"] == 2, d
PY
}

@test "S03k auto: --max-retries no entero sale con 2 y no guarda" {
  run bash "$CLI" create --name fx --schedule "0 9 * * 1-5" --instructions x --max-retries dos
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs an integer"* ]]
  run bash "$CLI" list
  [ "$output" = "(no tasks)" ]
}

@test "S03k auto: --max-retries negativo se rechaza y 3 (el tope) se acepta" {
  run bash "$CLI" create --name fx --schedule "0 9 * * 1-5" --instructions x --max-retries -1
  [ "$status" -eq 2 ]
  run bash "$CLI" create --name fx --schedule "0 9 * * 1-5" --instructions x --max-retries 3
  [ "$status" -eq 0 ]
}

@test "S03k auto: history sin ejecuciones dice '(no runs)'; con ejecuciones respeta --last" {
  create_task
  run bash "$CLI" history "$TASK_ID"
  [ "$output" = "(no runs)" ]
  for i in 1 2 3; do bash "$CLI" run "$TASK_ID" >/dev/null; done
  run bash "$CLI" history "$TASK_ID"
  [ "$(grep -c 'recorded  manual' <<< "$output")" -eq 3 ]
  run bash "$CLI" history "$TASK_ID" --last 2
  [ "$(grep -c 'recorded  manual' <<< "$output")" -eq 2 ]
}

@test "S03k auto: history marca las ejecuciones fallidas y muestra su error" {
  create_task --success-check "false"
  run bash "$CLI" run "$TASK_ID"
  [ "$status" -eq 1 ]
  run bash "$CLI" history "$TASK_ID"
  [[ "$output" == *"[✗]"*"failed  manual"* ]]
  [[ "$output" == *"error:"* ]]
}

@test "S03k auto: output de un run inexistente falla con exit 1; sin argumentos con 2" {
  create_task
  run bash "$CLI" output "$TASK_ID" nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found: $TASK_ID/nope"* ]]
  run bash "$CLI" output "$TASK_ID"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: output"* ]]
}

@test "S03k auto: run cuenta en run_count y list lo refleja con '(not executed)'" {
  create_task
  bash "$CLI" run "$TASK_ID" >/dev/null
  run bash "$CLI" list
  [[ "$output" == *"last: recorded (not executed)"* ]]
  [[ "$output" == *"runs: 1"* ]]
}

@test "S03k auto: init-defaults crea 6 tareas y una segunda llamada no duplica" {
  run bash "$CLI" init-defaults
  [ "$status" -eq 0 ]
  [[ "$output" == *"6 default tasks created"* ]]
  run bash "$CLI" init-defaults
  [[ "$output" == *"skip morning-brief (already exists)"* ]]
  [[ "$output" == *"0 default tasks created"* ]]
  [ "$(bash "$CLI" list | grep -c '^\[')" -eq 6 ]
}

@test "S03k auto: drift-daily solo recibe herramienta de lectura; el resto lectura y escritura" {
  bash "$CLI" init-defaults >/dev/null
  id=$(bash "$CLI" list | awk '/drift-daily/{print $2}')
  run bash "$CLI" show "$id"
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["always_allowed_tools"] == ["read"], d
PY
  id=$(bash "$CLI" list | awk '/weekly-report/{print $2}')
  run bash "$CLI" show "$id"
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["always_allowed_tools"] == ["read", "write"], d
PY
}

@test "S03k auto: run-due --max no entero sale con 2" {
  run bash "$CLI" run-due --max muchas
  [ "$status" -eq 2 ]
  [[ "$output" == *"--max needs an integer"* ]]
}

@test "S03k auto: run-due --max 1 procesa solo una de dos vencidas" {
  create_task
  first="$TASK_ID"
  create_task
  py 'import json,pathlib
p=pathlib.Path(sys.argv[1])/"automations"/"tasks.json"
d=json.loads(p.read_text())
ts=d["tasks"] if isinstance(d,dict) and "tasks" in d else d
for t in (ts.values() if isinstance(ts,dict) else ts): t["next_run"]="2020-01-01T00:00:00+00:00"
p.write_text(json.dumps(d))'
  run bash "$CLI" run-due --max 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-due: 1/2 tasks processed, 1 recorded without execution"* ]]
}

@test "S03k auto: compute materializa next_run y cuenta solo las tareas que cambian" {
  create_task
  run bash "$CLI" compute
  [ "$status" -eq 0 ]
  [[ "$output" == *"compute: 0 tasks updated"* ]]
  py 'import json,pathlib
p=pathlib.Path(sys.argv[1])/"automations"/"tasks.json"
d=json.loads(p.read_text())
ts=d["tasks"] if isinstance(d,dict) and "tasks" in d else d
for t in (ts.values() if isinstance(ts,dict) else ts): t["next_run"]=None
p.write_text(json.dumps(d))'
  run bash "$CLI" compute
  [[ "$output" == *"compute: 1 tasks updated"* ]]
}

@test "S03k auto: list --due solo muestra las vencidas y las marca DUE" {
  create_task
  run bash "$CLI" list --due
  [ "$output" = "(no tasks)" ]
  py 'import json,pathlib
p=pathlib.Path(sys.argv[1])/"automations"/"tasks.json"
d=json.loads(p.read_text())
ts=d["tasks"] if isinstance(d,dict) and "tasks" in d else d
for t in (ts.values() if isinstance(ts,dict) else ts): t["next_run"]="2020-01-01T00:00:00+00:00"
p.write_text(json.dumps(d))'
  run bash "$CLI" list --due
  [[ "$output" == *"$TASK_ID  fx DUE"* ]]
}

@test "S03k auto: tarea 'once' con fecha ISO se guarda como once, con su fecha" {
  run bash "$CLI" create --name unica --schedule "2099-01-01T10:00:00" --instructions x --timezone UTC
  [ "$status" -eq 0 ]
  run bash "$CLI" list
  [[ "$output" == *"schedule: once=2099-01-01T10:00:00"* ]]
}

@test "S03k auto: create sin --instructions es un error de uso" {
  run bash "$CLI" create --name fx --schedule "0 9 * * 1-5"
  [ "$status" -ne 0 ]
  run bash "$CLI" list
  [ "$output" = "(no tasks)" ]
}

@test "S03k auto: cada comando con id exige el argumento y nombra su uso" {
  for c in show disable enable run; do
    run bash "$CLI" $c
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: $c <task-id>"* ]]
  done
  run bash "$CLI" delete
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: delete <task-id>"* ]]
}
