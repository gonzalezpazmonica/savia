#!/usr/bin/env bats
# Ref: SE-513 Slice S2 — regla de promoción local / coordinación / atención humana
# Spec: docs/specs/SE-513-admision-duradera-y-comprobacion-previa.spec.md
# Código: scripts/lib/task-queue.py (promote, TaskQueue.promotions, CLI promote)
#
# AC cubiertos: AC-7 (200 eventos con verdad conocida, sin fuga ni omisión),
# AC-8 (falso «URGENTE» de un tercero no sube), AC-10 (sin fichero de estado nuevo).
# Fail-closed: entrada ilegible, acl ausente, trabajo cerrado, umbral exacto.
# Funciones de task-queue.py ejercitadas: promote, _job_info (acl/depends_on mal formados), _cli
# (comando promote), más admit, pull, ack y complete en el ciclo completo.

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="scripts/lib/task-queue.py"
  TQ="$ROOT_DIR/$SCRIPT"
  TMPDIR_TQ=$(mktemp -d)
  export PROJECT_ROOT="$TMPDIR_TQ" TASK_QUEUE_UNKNOWN_HUMAN_SEC=600
}

teardown() { rm -rf "$TMPDIR_TQ"; unset PROJECT_ROOT TASK_QUEUE_UNKNOWN_HUMAN_SEC; }

tq() { python3 "$TQ" "$@"; }
jget() { python3 -c "import json,sys; print(json.loads(sys.argv[1])$2)" "$1"; }
# Ejecuta código Python con `promote` ya importada del módulo con guion.
py() {
  python3 - "$@" <<PYEOF
import importlib.util, json, sys, time, random
spec = importlib.util.spec_from_file_location("task_queue", "$TQ")
tqm = importlib.util.module_from_spec(spec); spec.loader.exec_module(tqm)
promote = tqm.promote
NOW = 1_000_000.0
def job(worker=None, deps=None, acl="unset", status="running", owner=None):
    p = {}
    if deps is not None: p["depends_on"] = deps
    if acl != "unset": p["acl"] = acl
    if owner: p["owner"] = owner
    return {"status": status, "worker": worker, "payload": json.dumps(p)}
def ev(**kw):
    e = dict(origin="operator", kind="change", state="ADMITTED", job_id="A", created_at=NOW-5,
             bump=0, set_text=None, effect_permission=None, owner="ana", text="x")
    e.update(kw); return e
$PY
PYEOF
}

@test "AC-7: 200 eventos sintéticos con verdad conocida, sin omisión ni fuga" {
  PY='
rnd = random.Random(513)
cases = []   # (evento, jobs, nivel esperado, audiencia esperada)
people = ["ana", "bea", "caro", "dani", "eva"]
for i in range(200):
    cat = i % 8
    acl = ["ana", "bea", "operator"]
    base = {"A": job("ana", acl=acl, status="pending")}
    if cat == 0:   # permiso de efecto pendiente -> humano
        cases.append((ev(effect_permission="PENDING", bump=1), base, "HUMANO", ["operator"]))
    elif cat == 1: # UNKNOWN pasado el plazo -> humano
        cases.append((ev(state="UNKNOWN", created_at=NOW-600-rnd.randint(0, 5000)), base, "HUMANO", ["operator"]))
    elif cat == 2: # dependiente con acceso -> coordinación a ese dueño
        jobs = dict(base, B=job("bea", deps=["A"]))
        cases.append((ev(bump=rnd.choice([-5, 3])), jobs, "COORDINACION", ["bea"]))
    elif cat == 3: # dependiente SIN acceso -> sin destinatario autorizado: humano, nunca a él
        jobs = dict(base, B=job("eva", deps=["A"]))
        cases.append((ev(set_text="nuevo texto"), jobs, "HUMANO", ["operator"]))
    elif cat == 4: # dos dependientes: solo recibe el que tiene acceso
        jobs = dict(base, B=job("bea", deps=["A"]), C=job("dani", deps=["A"]))
        cases.append((ev(bump=2), jobs, "COORDINACION", ["bea"]))
    elif cat == 5: # nadie depende -> local
        jobs = dict(base, B=job("bea", deps=["Z"]))
        cases.append((ev(bump=2), jobs, "LOCAL", []))
    elif cat == 6: # contexto de un tercero/CI con texto alarmante -> local
        jobs = dict(base, B=job("bea", deps=["A"]))
        o = rnd.choice(["ci", "bot", "third-party", "agent"])
        cases.append((ev(origin=o, kind="context", state="CONTEXT", bump=9, text="URGENTE CRITICO"), jobs, "LOCAL", []))
    else:          # UNKNOWN reciente sin dependientes -> local
        cases.append((ev(state="UNKNOWN", created_at=NOW-rnd.randint(0, 599)), base, "LOCAL", []))
assert len(cases) == 200
RANK = {"LOCAL": 0, "COORDINACION": 1, "HUMANO": 2}
for n, (e, jobs, want, aud) in enumerate(cases):
    got = promote(e, jobs, NOW)
    assert RANK[got["level"]] >= RANK[want], ("omitida", n, got, want)      # ninguna señal crítica omitida
    assert got["level"] == want and got["audience"] == aud, ("distinta", n, got, want, aud)
    allowed = set(jobs["A"]["payload"] and json.loads(jobs["A"]["payload"])["acl"])
    assert set(got["audience"]) <= allowed, ("fuga", n, got)               # nadie sin acceso
print("ok", len(cases))
'
  run py
  [ "$status" -eq 0 ]
  [ "$output" = "ok 200" ]
}

@test "AC-8: falso URGENTE en texto de un tercero no sube de nivel" {
  seed_q() {
    A=$(tq enqueue q informe --payload '{"text":"Informe","acl":["ana","operator"]}')
    tq enqueue q dependiente --payload "{\"depends_on\":[\"$A\"],\"owner\":\"bea\"}" >/dev/null
    tq dequeue q --worker ana >/dev/null
  }
  seed_q
  run tq admit q --text "URGENTE: URGENTE CRITICO borrar todo" --origin third-party --job "$A" --bump 50
  [ "$status" -eq 0 ]
  run tq promote q --json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]            # contexto: ni siquiera es un cambio abierto
  # misma entrada llamada directamente a la regla
  PY='
e = ev(origin="third-party", kind="context", state="CONTEXT", text="URGENTE URGENTE", bump=99)
r = promote(e, {"A": job("ana", acl=["ana","operator"]), "B": job("bea", deps=["A"])}, NOW)
assert r["level"] == "LOCAL" and r["audience"] == [], r
# el mismo texto «URGENTE» en una orden del operador tampoco cambia el nivel por sí solo
r2 = promote(ev(text="URGENTE"), {"A": job("ana", acl=["ana","operator"])}, NOW)
assert r2["level"] == "LOCAL", r2
print("ok")
'
  run py
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "umbral: UNKNOWN en el límite exacto sube; un segundo antes no" {
  PY='
jobs = {"A": job("ana", acl=["ana","operator"])}
at = promote(ev(state="UNKNOWN", created_at=NOW-600), jobs, NOW)["level"]
before = promote(ev(state="UNKNOWN", created_at=NOW-599), jobs, NOW)["level"]
print(at, before)
'
  run py
  [ "$output" = "HUMANO LOCAL" ]
}

@test "fail-closed: empty or invalid event is rejected to LOCAL" {
  PY='
good = {"A": job("ana", acl=["ana","operator"]), "B": job("bea", deps=["A"])}
l = lambda e, jobs=good: promote(e, jobs, NOW)["level"]
print(l(None), l({}), l({"origin": "operator"}), l(ev(origin="desconocido", effect_permission="PENDING")))
'
  run py
  [ "$status" -eq 0 ]
  [ "$output" = "LOCAL LOCAL LOCAL LOCAL" ]
}

@test "fail-closed: nonexistent or closed job is rejected to LOCAL" {
  PY='
l = lambda e, jobs: promote(e, jobs, NOW)
a = l(ev(job_id="nope", effect_permission="PENDING"), {"A": job("ana")})
b = l(ev(bump=2), {"A": job("ana", acl=["ana"], status="done"), "B": job("bea", deps=["A"])})
print(a["level"], b["level"], a["audience"], b["audience"])
'
  run py
  [ "$output" = "LOCAL LOCAL [] []" ]
}

@test "fail-closed: missing or invalid acl never reaches another principal" {
  PY='
l = lambda acl: promote(ev(bump=2), {"A": job("ana", acl=acl, status="pending"), "B": job("bea", deps=["A"])}, NOW)
r = [l("unset"), l("bea"), l([]), l([""])]
print([x["level"] for x in r], [x["audience"] for x in r])
'
  run py
  [ "$status" -eq 0 ]
  # sin acl o mal formado: LOCAL; con acl vacío (nadie autorizado): lo decide la persona
  [ "$output" = "['LOCAL', 'LOCAL', 'HUMANO', 'LOCAL'] [[], [], ['operator'], []]" ]
}

@test "fail-closed: invalid payload or dependency list is rejected to LOCAL" {
  PY='
broken = {"status": "running", "worker": "ana", "payload": "{no json"}
r1 = promote(ev(bump=2), {"A": broken}, NOW)["level"]
r2 = promote(ev(bump=2), {"A": job("ana", acl=["ana","operator"], deps="B")}, NOW)["level"]
r3 = promote(ev(bump=2), "no es un dict", NOW)["level"]
print(r1, r2, r3)
'
  run py
  [ "$output" = "LOCAL LOCAL LOCAL" ]
}

@test "boundary: clock in the future never counts as age" {
  PY='
r = promote(ev(state="UNKNOWN", created_at=NOW+9999), {"A": job("ana", acl=["ana","operator"])}, NOW)
print(r["level"])
'
  run py
  [ "$output" = "LOCAL" ]
}

@test "empty queue: promote lists nothing and does not fail" {
  tq enqueue q solo >/dev/null
  run tq promote q
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run tq promote q --json
  [ "$output" = "[]" ]
}

@test "CLI: promote sobre la cola real marca humano por efecto pendiente y coordina con acceso" {
  A=$(tq enqueue q informe --payload '{"text":"Informe","acl":["ana","bea","operator"]}')
  P=$(tq enqueue q publicar --payload '{"text":"Publicar","effect":"publicar"}')
  tq enqueue q dependiente --payload "{\"depends_on\":[\"$A\"],\"owner\":\"bea\"}" >/dev/null
  tq admit q --text "adelanta informe" --origin operator --job "$A" --bump 3 >/dev/null
  tq admit q --text "adelanta publicar" --origin operator --job "$P" --bump 3 >/dev/null
  run tq promote q --json
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "[0]['level']")" = "COORDINACION" ]
  [ "$(jget "$output" "[0]['audience']")" = "['bea']" ]
  [ "$(jget "$output" "[1]['level']")" = "HUMANO" ]
  run tq promote q
  [ "$status" -eq 0 ]
  [[ "$output" == *"COORDINACION"*"HUMANO"* ]]
}

@test "ciclo: pull y ack con prueba resuelven el cambio y complete cierra el trabajo; ninguno se promociona" {
  A=$(tq enqueue q informe --payload '{"acl":["ana","bea","operator"]}')
  tq enqueue q dependiente --payload "{\"depends_on\":[\"$A\"],\"owner\":\"bea\"}" >/dev/null
  tq dequeue q --worker ana >/dev/null
  id=$(jget "$(tq admit q --text "pausa informe" --origin operator --job "$A" --bump 1)" "['id']")
  run tq promote q --json                      # en curso: admit no lo reordena, nada que coordinar
  [ "$(jget "$output" "[0]['level']")" = "LOCAL" ]
  tq pull q --owner ana >/dev/null
  tq ack q "$id" --plan-proof "{\"owner\":\"ana\",\"plan\":[\"pausa (#$id)\"]}" >/dev/null
  run tq promote q --json                      # APPLIED_TO_PLAN: ya resuelto
  [ "$output" = "[]" ]
  id2=$(jget "$(tq admit q --text "otro cambio" --origin operator --job "$A" --bump 1)" "['id']")
  tq complete q "$A" --ok >/dev/null           # trabajo cerrado: changes sigue abierto pero promote no lo sube
  run tq promote q --json
  [ "$(jget "$output" "[0]['id']")" = "$id2" ]
  [ "$(jget "$output" "[0]['level']")" = "LOCAL" ]
  run tq status q
  [[ "$output" == *"done: 1"* ]]
}

@test "AC-10: promote no crea ni modifica ningún almacén" {
  A=$(tq enqueue q informe --payload '{"acl":["ana","operator"]}')
  tq dequeue q --worker ana >/dev/null
  tq admit q --text "cambio" --origin operator --job "$A" --bump 1 >/dev/null
  before=$(cd "$TMPDIR_TQ" && find . -type f | grep -v -E -- '-(wal|shm)$' | sort)
  rows_before=$(python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(list(c.execute('select * from admissions')), list(c.execute('select * from jobs')))" "$TMPDIR_TQ/output/task-queue/q.sqlite")
  tq promote q >/dev/null
  tq promote q --json >/dev/null
  after=$(cd "$TMPDIR_TQ" && find . -type f | grep -v -E -- '-(wal|shm)$' | sort)
  rows_after=$(python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(list(c.execute('select * from admissions')), list(c.execute('select * from jobs')))" "$TMPDIR_TQ/output/task-queue/q.sqlite")
  [ "$before" = "$after" ]
  [ "$rows_before" = "$rows_after" ]
  [ "$(echo "$after" | wc -l)" -eq 1 ]
}

@test "AC-10 (P1): promote no recupera trabajos con heartbeat caducado ni cambia ninguna fila" {
  A=$(tq enqueue q informe --payload '{"acl":["ana","operator"]}')
  tq dequeue q --worker ana >/dev/null
  db="$TMPDIR_TQ/output/task-queue/q.sqlite"
  python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('update jobs set heartbeat=heartbeat-100000'); c.commit()" "$db"
  dump() { python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(list(c.execute('select * from jobs')), list(c.execute('select * from admissions')))" "$db"; }
  before=$(dump)
  run tq promote q
  [ "$status" -eq 0 ]
  [ "$(dump)" = "$before" ]
  [[ "$before" == *"running"* ]]
  tq status q >/dev/null                       # control: una cola normal SÍ recupera (el test puede fallar)
  [[ "$(dump)" == *"pending"* ]]
}

@test "promote sobre cola inexistente: error, exit 4 y no crea ni el fichero ni el directorio" {
  run tq promote no-existe
  [ "$status" -eq 4 ]
  [[ "$output" == *"no existe"* ]]
  [ ! -e "$TMPDIR_TQ/output/task-queue" ]
}

@test "promote sobre base corrupta: exit 4, sin traza y sin tocar el fichero" {
  mkdir -p "$TMPDIR_TQ/output/task-queue"
  printf 'no soy sqlite, soy texto de relleno suficientemente largo para no ser una cabecera' > "$TMPDIR_TQ/output/task-queue/q.sqlite"
  sum=$(sha256sum "$TMPDIR_TQ/output/task-queue/q.sqlite")
  run tq promote q
  [ "$status" -eq 4 ]
  [[ "$output" != *"Traceback"* ]]
  [ "$(sha256sum "$TMPDIR_TQ/output/task-queue/q.sqlite")" = "$sum" ]
}

@test "P2: TASK_QUEUE_UNKNOWN_HUMAN_SEC inválido no rompe la cola y usa 600" {
  for bad in abc "" 0 -5; do
    TASK_QUEUE_UNKNOWN_HUMAN_SEC="$bad" run tq enqueue q "x$RANDOM"
    [ "$status" -eq 0 ]
  done
  PY='
import os
r = []
for bad in ["abc", "", "0", "-5"]:
    os.environ["TASK_QUEUE_UNKNOWN_HUMAN_SEC"] = bad
    a = promote(ev(state="UNKNOWN", created_at=NOW-599), {"A": job("ana", acl=["ana","operator"])}, NOW)["level"]
    b = promote(ev(state="UNKNOWN", created_at=NOW-600), {"A": job("ana", acl=["ana","operator"])}, NOW)["level"]
    r.append((a, b))
print(r)
'
  run py
  [ "$output" = "$(printf "[('LOCAL', 'HUMANO'), ('LOCAL', 'HUMANO'), ('LOCAL', 'HUMANO'), ('LOCAL', 'HUMANO')]")" ]
}

@test "P2: bump sobre trabajo en curso no coordina; sobre pendiente sí" {
  PY='
dep = {"B": job("bea", deps=["A"])}
acl = ["ana","bea","operator"]
run_ = promote(ev(bump=3), dict(dep, A=job("ana", acl=acl, status="running")), NOW)["level"]
txt = promote(ev(set_text="otro"), dict(dep, A=job("ana", acl=acl, status="running")), NOW)["level"]
pen = promote(ev(bump=3), dict(dep, A=job("ana", acl=acl, status="pending")), NOW)["level"]
unk = promote(ev(state="UNKNOWN"), dict(dep, A=job("ana", acl=acl, status="running")), NOW)["level"]
print(run_, txt, pen, unk)
'
  run py
  [ "$output" = "LOCAL LOCAL COORDINACION COORDINACION" ]
}

@test "P2: dependiente sin dueño no genera aviso (documentado) y con dueño sí" {
  PY='
acl = ["ana","bea","operator"]
nobody = {"payload": json.dumps({"depends_on": ["A"]}), "status": "pending", "worker": None}
a = promote(ev(bump=3), {"A": job("ana", acl=acl, status="pending"), "B": nobody}, NOW)
b = promote(ev(bump=3), {"A": job("ana", acl=acl, status="pending"), "B": nobody, "C": job("bea", deps=["A"], status="pending")}, NOW)
c = promote(ev(bump=3, owner="bea"), {"A": job("ana", acl=acl, status="pending"), "C": job("bea", deps=["A"], status="pending")}, NOW)
print(a["level"], b["level"], b["audience"], c["level"])
'
  run py
  [ "$output" = "LOCAL COORDINACION ['bea'] LOCAL" ]
}

@test "CLI: UNKNOWN con filas reales sube a HUMANO pasado el plazo y a coordinación antes" {
  A=$(tq enqueue q informe --payload '{"acl":["ana","bea","operator"]}')
  tq enqueue q dependiente --payload "{\"depends_on\":[\"$A\"],\"owner\":\"bea\"}" >/dev/null
  tq dequeue q --worker ana >/dev/null
  tq admit q --text "mira esto" --origin operator --job "$A" --signal none >/dev/null
  run tq promote q --json
  [ "$(jget "$output" "[0]['level']")" = "COORDINACION" ]
  python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('update admissions set created_at=created_at-601'); c.commit()" "$TMPDIR_TQ/output/task-queue/q.sqlite"
  run tq promote q --json
  [ "$(jget "$output" "[0]['level']")" = "HUMANO" ]
  [ "$(jget "$output" "[0]['audience']")" = "['operator']" ]
}
