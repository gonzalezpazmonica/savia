#!/usr/bin/env bats
# Ref: SE-513 Slice S2 — regla de promoción local / coordinación / atención humana
# Spec: docs/specs/SE-513-admision-duradera-y-comprobacion-previa.spec.md
# Código: scripts/lib/task-queue.py (promote, TaskQueue.promotions, CLI promote)
#
# AC cubiertos: AC-7 (200 eventos con verdad conocida, sin fuga ni omisión),
# AC-8 (falso «URGENTE» de un tercero no sube), AC-10 (sin fichero de estado nuevo).
# Fail-closed: entrada ilegible, acl ausente, trabajo cerrado, umbral exacto.

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TQ="$ROOT_DIR/scripts/lib/task-queue.py"
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
    base = {"A": job("ana", acl=acl)}
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

@test "fail-closed: entrada inesperada no promociona" {
  PY='
good = {"A": job("ana", deps=None, acl=["ana","operator"]), "B": job("bea", deps=["A"])}
def lvl(e, jobs=good): return promote(e, jobs, NOW)["level"]
res = []
res.append(lvl(None))                                   # evento nulo
res.append(lvl({"origin": "operator"}))                 # campos que faltan
res.append(lvl(ev(job_id="nope"), ))                    # trabajo inexistente
res.append(lvl(ev(bump=2), {"A": job("ana", acl=["ana"], status="done"), "B": job("bea", deps=["A"])}))  # cerrado
res.append(lvl(ev(bump=2), {"A": job("ana"), "B": job("bea", deps=["A"])}))                              # sin acl
res.append(lvl(ev(bump=2), {"A": job("ana", acl="bea"), "B": job("bea", deps=["A"])}))                  # acl mal formado
res.append(lvl(ev(bump=2), {"A": {"status": "running", "worker": "ana", "payload": "{no json"}}))       # payload roto
res.append(lvl(ev(bump=2), {"A": job("ana", acl=["ana","operator"], deps="B")}))                         # deps mal formado
res.append(lvl(ev(state="UNKNOWN", created_at=NOW+9999), {"A": job("ana", acl=["ana","operator"])}))                                                # reloj futuro
res.append(lvl(ev(origin="desconocido", effect_permission="PENDING")))                                   # origen no autenticado
res.append(lvl(ev(bump=2), "no es un dict"))                                                            # jobs ilegible
print(" ".join(res))
'
  run py
  [ "$status" -eq 0 ]
  [ "$output" = "LOCAL LOCAL LOCAL LOCAL LOCAL LOCAL LOCAL LOCAL LOCAL LOCAL LOCAL" ]
}

@test "CLI: promote sobre la cola real marca humano por efecto pendiente y coordina con acceso" {
  A=$(tq enqueue q informe --payload '{"text":"Informe","acl":["ana","bea","operator"]}')
  P=$(tq enqueue q publicar --payload '{"text":"Publicar","effect":"publicar"}')
  tq enqueue q dependiente --payload "{\"depends_on\":[\"$A\"],\"owner\":\"bea\"}" >/dev/null
  tq dequeue q --worker ana >/dev/null
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
