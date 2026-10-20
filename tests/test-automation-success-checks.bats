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
