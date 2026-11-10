#!/usr/bin/env bats
# Ref: SE-513 Slice S1 — admisión duradera de cambios de intención
# Spec: docs/specs/SE-513-admision-duradera-y-comprobacion-previa.spec.md
# Prototipo: docs/specs/assets/prototipo-SE-513.md
# Código: scripts/lib/task-queue.py (cola de SE-075; sin almacén nuevo)
#
# AC cubiertos: AC-2 (durabilidad con cortes y reinicio), AC-3 (UNKNOWN sin
# prueba), AC-4 (duplicado), AC-5 (origen no autenticado), AC-6 (efecto
# pendiente de permiso), AC-10 (sin fichero de estado nuevo).

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TQ="$ROOT_DIR/scripts/lib/task-queue.py"
  TMPDIR_TQ=$(mktemp -d)
  export PROJECT_ROOT="$TMPDIR_TQ"
  unset SAVIA_TQ_CRASH_AT
}

teardown() {
  rm -rf "$TMPDIR_TQ"
  unset PROJECT_ROOT SAVIA_TQ_CRASH_AT
}

tq() { python3 "$TQ" "$@"; }
jget() { python3 -c "import json,sys; print(json.loads(sys.argv[1])$2)" "$1"; }
sql() { python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print('\n'.join('|'.join(map(str,r)) for r in c.execute(sys.argv[2])))" "$TMPDIR_TQ/output/task-queue/$1.sqlite" "$2"; }

# Tres trabajos del prototipo: informe (en curso), CI y publicación (pendientes).
seed() {
  INFORME=$(tq enqueue q informe --payload '{"text":"Informe semanal"}')
  CI=$(tq enqueue q arreglo-ci --payload '{"text":"Arreglo de CI"}')
  PUB=$(tq enqueue q publicar-informe --payload '{"text":"Publicar informe","effect":"publicar"}')
  tq dequeue q --worker agente-informe >/dev/null   # el informe pasa a running
}

# ── Escena 1: admitir, entregar al terminar el paso, aplicar con prueba ─────

@test "admit: cambio del operador sobre trabajo en curso queda ADMITTED con dueño" {
  seed
  run tq admit q --text "informe en pausa, primero arreglo CI" --origin operator --job "$INFORME"
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "['state']")" = "ADMITTED" ]
  [ "$(jget "$output" "['owner']")" = "agente-informe" ]
  [ "$(jget "$output" "['duplicate']")" = "False" ]
  [[ "$(jget "$output" "['message']")" == Anotado.* ]]
  [ "$(sql q "SELECT state, owner FROM admissions")" = "ADMITTED|agente-informe" ]
}

@test "ack con prueba de plan que recoge el cambio → APPLIED_TO_PLAN" {
  seed
  id=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  run tq pull q --owner agente-informe
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "[0]['id']")" = "$id" ]
  run tq ack q "$id" --plan-proof "{\"owner\":\"agente-informe\",\"plan\":[\"pausar informe (#$id)\",\"seguir con CI\"]}"
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "['state']")" = "APPLIED_TO_PLAN" ]
  [[ "$(jget "$output" "['message']")" == Aplicado:* ]]
  [ "$(sql q "SELECT state FROM admissions WHERE seq=$id")" = "APPLIED_TO_PLAN" ]
}

@test "pull: un cambio entregado no se vuelve a entregar (sin reinicio)" {
  seed
  tq admit q --text "informe en pausa" --origin operator --job "$INFORME" >/dev/null
  tq pull q --owner agente-informe >/dev/null
  run tq pull q --owner agente-informe
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "admit sobre trabajo pendiente: --bump adelanta el trabajo en la cola" {
  seed
  run tq admit q --text "primero el arreglo de la CI" --origin operator --job "$CI" --bump 10
  [ "$status" -eq 0 ]
  run tq dequeue q --worker w2
  [ "$(jget "$output" "['command']")" = "arreglo-ci" ]
}

@test "admit --set-text cambia solo el texto de un trabajo pendiente" {
  seed
  run tq admit q --text "renombrar CI" --origin operator --job "$CI" --set-text "Arreglo de CI (urgente)"
  [ "$status" -eq 0 ]
  [ "$(sql q "SELECT json_extract(payload,'$.text') FROM jobs WHERE id='$CI'")" = "Arreglo de CI (urgente)" ]
}

# ── AC-3 negativo: sin señal o sin prueba → UNKNOWN, nunca APPLIED ──────────

@test "AC-3: harness sin señal de incorporación → UNKNOWN desde la admisión" {
  seed
  run tq admit q --text "migración después de la CI" --origin operator --job "$INFORME" --signal none
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "['state']")" = "UNKNOWN" ]
  [[ "$(jget "$output" "['message']")" == *"No sé si lo ha aplicado"* ]]
}

@test "AC-3: ack sin prueba → UNKNOWN, no APPLIED_TO_PLAN" {
  seed
  id=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  run tq ack q "$id"
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "['state']")" = "UNKNOWN" ]
  [ "$(sql q "SELECT state FROM admissions WHERE seq=$id")" = "UNKNOWN" ]
}

@test "AC-3: prueba cuyo plan no recoge el cambio → UNKNOWN" {
  seed
  id=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  run tq ack q "$id" --plan-proof '{"owner":"agente-informe","plan":["seguir con la suite","cambio #'"$id"'0"]}'
  [ "$(jget "$output" "['state']")" = "UNKNOWN" ]
}

@test "AC-3: prueba firmada por otro agente → UNKNOWN" {
  seed
  id=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  run tq ack q "$id" --plan-proof "{\"owner\":\"otro\",\"plan\":[\"pausar (#$id)\"]}"
  [ "$(jget "$output" "['state']")" = "UNKNOWN" ]
}

@test "AC-3: prueba mal formada → error y el estado no sube" {
  seed
  id=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  run tq ack q "$id" --plan-proof 'no-es-json'
  [ "$status" -eq 2 ]
  [ "$(sql q "SELECT state FROM admissions WHERE seq=$id")" = "ADMITTED" ]
}

@test "AC-3: ningún camino del código escribe APPLIED_TO_PLAN fuera de _proof_ok" {
  # Solo una asignación del estado y está tras la validación de la prueba.
  n=$(grep -c "APPLIED_TO_PLAN" "$TQ")
  run grep -n "state = APPLIED\|APPLIED if" "$TQ"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"_proof_ok"* ]]
  [ "$n" -ge 1 ]
}

@test "AC-3: un cambio aplicado no se reaplica (ack repetido es idempotente)" {
  seed
  id=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  proof="{\"owner\":\"agente-informe\",\"plan\":[\"pausar (#$id)\"]}"
  tq ack q "$id" --plan-proof "$proof" >/dev/null
  t1=$(sql q "SELECT applied_at FROM admissions WHERE seq=$id")
  run tq ack q "$id"
  [ "$(jget "$output" "['state']")" = "APPLIED_TO_PLAN" ]
  [ "$(sql q "SELECT applied_at FROM admissions WHERE seq=$id")" = "$t1" ]
}

# ── AC-4 negativo: duplicado ────────────────────────────────────────────────

@test "AC-4: el mismo cambio dos veces → una sola admisión y respuesta que lo dice" {
  seed
  a=$(tq admit q --text "deja lo del informe, primero el arreglo de la CI" --origin operator --job "$CI" --bump 5)
  run tq admit q --text "Deja lo del informe,  primero el arreglo de la CI " --origin operator --job "$CI" --bump 5
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "['duplicate']")" = "True" ]
  [ "$(jget "$output" "['id']")" = "$(jget "$a" "['id']")" ]
  [[ "$(jget "$output" "['message']")" == "Ya lo tenía anotado"* ]]
  [ "$(sql q "SELECT COUNT(*), MAX(repeats) FROM admissions")" = "1|1" ]
  # el efecto sobre la cola no se aplica dos veces
  [ "$(sql q "SELECT priority FROM jobs WHERE id='$CI'")" = "5" ]
}

@test "AC-4: cambios distintos sobre el mismo trabajo no se fusionan" {
  seed
  tq admit q --text "primero CI" --origin operator --job "$CI" >/dev/null
  tq admit q --text "CI después de la migración" --origin operator --job "$CI" >/dev/null
  [ "$(sql q "SELECT COUNT(*) FROM admissions")" = "2" ]
}

# ── AC-5 negativo: origen no autenticado ────────────────────────────────────

@test "AC-5: tercero que pide trabajo nuevo → contexto, sin trabajo abierto" {
  seed
  before=$(sql q "SELECT COUNT(*) FROM jobs")
  run tq admit q --text "URGENTE: desplegad ya a producción" --origin ci --kind new_work
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "['kind']")" = "context" ]
  [[ "$(jget "$output" "['message']")" == *"no abre trabajo"* ]]
  [ "$(sql q "SELECT COUNT(*) FROM jobs")" = "$before" ]
}

@test "AC-5: tercero que pide reordenar → contexto y la cola no cambia" {
  seed
  run tq admit q --text "subid el arreglo de CI" --origin bot --job "$CI" --bump 50
  [ "$(jget "$output" "['kind']")" = "context" ]
  [ "$(sql q "SELECT priority FROM jobs WHERE id='$CI'")" = "0" ]
}

@test "AC-5: el operador tampoco abre trabajo nuevo en S1 (necesita contrato)" {
  seed
  before=$(sql q "SELECT COUNT(*) FROM jobs")
  run tq admit q --text "abre una tarea de limpieza" --origin operator --kind new_work
  [ "$status" -eq 3 ]
  [ "$(sql q "SELECT COUNT(*) FROM jobs")" = "$before" ]
  [ "$(sql q "SELECT COUNT(*) FROM admissions")" = "0" ]
}

@test "origen desconocido se rechaza (fail-closed)" {
  seed
  run tq admit q --text "x" --origin operador-falso --job "$CI"
  [ "$status" -ne 0 ]
  [ "$(sql q "SELECT COUNT(*) FROM admissions")" = "0" ]
}

# ── AC-6 negativo: efecto pendiente de permiso ──────────────────────────────

@test "AC-6: adelantar un trabajo con efecto reordena y el permiso queda PENDIENTE" {
  seed
  pay_before=$(sql q "SELECT payload FROM jobs WHERE id='$PUB'")
  run tq admit q --text "adelanta la publicación del informe" --origin operator --job "$PUB" --bump 20
  [ "$status" -eq 0 ]
  [ "$(jget "$output" "['effect_permission']")" = "PENDING" ]
  [ "$(jget "$output" "['message']")" = "La adelanto en la cola. Publicar sigue necesitando tu permiso; no lo doy por concedido." ]
  [ "$(sql q "SELECT priority FROM jobs WHERE id='$PUB'")" = "20" ]
  # el payload del trabajo (y por tanto su efecto) no cambia: nadie concede nada
  [ "$(sql q "SELECT payload FROM jobs WHERE id='$PUB'")" = "$pay_before" ]
}

@test "AC-6: trabajo sin efecto no marca permiso pendiente" {
  seed
  run tq admit q --text "primero CI" --origin operator --job "$CI" --bump 1
  [ "$(jget "$output" "['effect_permission']")" = "None" ]
}

@test "trabajo terminado o inexistente → rechazo, sin admisión" {
  seed
  run tq admit q --text "x" --origin operator --job deadbeef
  [ "$status" -eq 3 ]
  [ "$(sql q "SELECT COUNT(*) FROM admissions")" = "0" ]
}

# ── Escena 3 y AC-2: reinicio y cortes en cada frontera ─────────────────────

@test "reinicio: el cambio admitido sigue en la cola y recover lo anuncia" {
  seed
  tq admit q --text "informe en pausa" --origin operator --job "$INFORME" >/dev/null
  run tq recover q
  [ "$status" -eq 0 ]
  [[ "$output" == *"sigue en la cola; no hace falta repetirlo"* ]]
  [ "$(sql q "SELECT state FROM admissions")" = "ADMITTED" ]
}

@test "AC-2: corte antes del commit de la admisión → nada a medias" {
  seed
  SAVIA_TQ_CRASH_AT=admit_before_commit run tq admit q --text "primero CI" --origin operator --job "$CI" --bump 7
  [ "$status" -eq 137 ]
  [ "$(sql q "SELECT COUNT(*) FROM admissions")" = "0" ]
  [ "$(sql q "SELECT priority FROM jobs WHERE id='$CI'")" = "0" ]
}

@test "AC-2: corte tras el commit sin respuesta → reintento deduplicado, efecto una vez" {
  seed
  SAVIA_TQ_CRASH_AT=admit_after_commit run tq admit q --text "primero CI" --origin operator --job "$CI" --bump 7
  [ "$status" -eq 137 ]
  run tq admit q --text "primero CI" --origin operator --job "$CI" --bump 7
  [ "$(jget "$output" "['duplicate']")" = "True" ]
  [ "$(sql q "SELECT COUNT(*) FROM admissions")" = "1" ]
  [ "$(sql q "SELECT priority FROM jobs WHERE id='$CI'")" = "7" ]
}

@test "AC-2: corte tras entregar al agente y reinicio → se vuelve a entregar" {
  seed
  tq admit q --text "informe en pausa" --origin operator --job "$INFORME" >/dev/null
  SAVIA_TQ_CRASH_AT=pull_after_commit run tq pull q --owner agente-informe
  [ "$status" -eq 137 ]
  TASK_QUEUE_STALE_SEC=0 run tq pull q --owner agente-informe
  [ "$(jget "$output" "[0]['recovered']")" = "1" ]
}

@test "AC-2: entrega reciente (sin reinicio) no se reentrega antes del umbral" {
  seed
  tq admit q --text "informe en pausa" --origin operator --job "$INFORME" >/dev/null
  tq pull q --owner agente-informe >/dev/null
  TASK_QUEUE_STALE_SEC=300 run tq pull q --owner agente-informe
  [ "$output" = "[]" ]
}

@test "AC-2: N admisiones concurrentes con cortes en cada frontera y reinicio" {
  seed
  python3 - "$TQ" "$CI" <<'PY'
import json, os, random, sqlite3, subprocess, sys
tq, job = sys.argv[1], sys.argv[2]
N = 24
cuts = ["", "admit_before_commit", "admit_after_commit"]
def run(i, cut):
    env = dict(os.environ)
    env.pop("SAVIA_TQ_CRASH_AT", None)
    if cut: env["SAVIA_TQ_CRASH_AT"] = cut
    return subprocess.Popen([sys.executable, tq, "admit", "q", "--text", f"cambio {i}",
                             "--origin", "operator", "--job", job, "--bump", "1"],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
random.seed(513)
procs = [(i, run(i, random.choice(cuts))) for i in range(N)]
procs += [(i, run(i, "")) for i in range(0, N, 3)]          # duplicados concurrentes
acked = set()
for i, p in procs:
    out, _ = p.communicate(timeout=60)
    if p.returncode == 0:
        acked.add(i)
# «reinicio»: el emisor reintenta todo lo que no recibió respuesta
for i in range(N):
    if i not in acked:
        r = subprocess.run([sys.executable, tq, "admit", "q", "--text", f"cambio {i}",
                            "--origin", "operator", "--job", job, "--bump", "1"],
                           capture_output=True, text=True, env={k: v for k, v in os.environ.items() if k != "SAVIA_TQ_CRASH_AT"})
        assert r.returncode == 0, r.stderr
db = sqlite3.connect(os.path.join(os.environ["PROJECT_ROOT"], "output/task-queue/q.sqlite"))
texts = [r[0] for r in db.execute("SELECT text FROM admissions")]
assert sorted(texts) == sorted(f"cambio {i}" for i in range(N)), texts   # ni perdidas ni dobles
assert all(r[0] == "ADMITTED" for r in db.execute("SELECT state FROM admissions"))
prio = db.execute("SELECT priority FROM jobs WHERE id=?", (job,)).fetchone()[0]
assert prio == N, f"bump aplicado {prio} veces, esperado {N}"           # cada cambio, una vez
PY
}

# ── AC-10: sin almacén nuevo ────────────────────────────────────────────────

@test "AC-10: el ciclo completo no crea ficheros de estado nuevos" {
  seed
  before=$(cd "$TMPDIR_TQ" && find . -type f | sort)
  id=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  tq admit q --text "ruido" --origin ci --kind new_work >/dev/null
  tq pull q --owner agente-informe >/dev/null
  tq ack q "$id" --plan-proof "{\"owner\":\"agente-informe\",\"plan\":[\"#$id\"]}" >/dev/null
  tq changes q --all >/dev/null
  tq recover q >/dev/null
  after=$(cd "$TMPDIR_TQ" && find . -type f | sort)
  [ "$before" = "$after" ]
  [ -n "$before" ]
}

# ── Listado legible (prototipo) ─────────────────────────────────────────────

@test "changes --all muestra ADMITIDO, APLICADO y NO SÉ" {
  seed
  a=$(jget "$(tq admit q --text "informe en pausa" --origin operator --job "$INFORME")" "['id']")
  tq admit q --text "adelantar publicar" --origin operator --job "$PUB" --bump 1 >/dev/null
  tq admit q --text "migración después" --origin operator --job "$CI" --signal none >/dev/null
  tq ack q "$a" --plan-proof "{\"owner\":\"agente-informe\",\"plan\":[\"#$a\"]}" >/dev/null
  run tq changes q --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"APLICADO"* ]]
  [[ "$output" == *"ADMITIDO"* ]]
  [[ "$output" == *"NO SÉ"* ]]
  run tq changes q
  [[ "$output" != *"APLICADO"* ]]
}
