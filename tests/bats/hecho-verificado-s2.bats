#!/usr/bin/env bats
# SE-530 S2 — la regla en el recibo del trabajador, con fallo cerrado (AC-2.1 a AC-2.9).
# Cada caso positivo tiene su par negativo. SE530_ROOT permite correr los mismos tests
# contra otra copia del código (así se comprueba que fallan contra el código anterior, AC-2.9).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ROOT="${SE530_ROOT:-$REPO_ROOT}"
HV="$ROOT/scripts/hecho-verificado.py"
RUNS="$ROOT/scripts/savia-runs.sh"
S1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
S2=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

setup() { T="$(mktemp -d)"; R="$T/recibo.json"; }
teardown() { rm -rf "$T"; }

# rec <sha-vigente> <verificaciones-json-array>  (ejecutor fijo: worker-1)
rec() { printf '{"version":1,"job":"j1","ejecutor":"worker-1","sha":"%s","verificaciones":%s}\n' "$1" "$2" > "$R"; }
# v <clase> <verificador> <sha> <resultado> [extra-json-sin-llaves]  (propuesta_por = verificador por defecto)
v() { printf '{"clase":"%s","ref":"ref-1","sha":"%s","verificador":"%s","propuesta_por":"%s","resultado":"%s"%s}' "$1" "$3" "$2" "$2" "$4" "${5:+,$5}"; }
rcpt() { python3 "$HV" receipt "$R" "$@"; }

@test "AC-2.1 mismo id de ejecutor y de verificador: declarado" {
  rec $S1 "[$(v revision worker-1 $S1 superada)]"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.2 verificador distinto, superada y sobre el SHA vigente: verificado" {
  rec $S1 "[$(v revision reviewer-a $S1 superada)]"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == verificado:* ]]
  [[ "${lines[0]}" == *aaaaaaaa* ]]
}

@test "AC-2.2 par negativo: la orquestadora como verificadora de una revision no cuenta" {
  rec $S1 "[$(v revision savia-orchestrator $S1 superada)]"
  run rcpt
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.3 sin el campo verificaciones: declarado" {
  printf '{"version":1,"job":"j1","ejecutor":"worker-1","sha":"%s"}\n' $S1 > "$R"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.3 recibo que no valida contra el esquema (falta ejecutor): declarado, salida 2" {
  printf '{"version":1,"job":"j1","sha":"%s","verificaciones":[%s]}\n' $S1 "$(v revision reviewer-a $S1 superada)" > "$R"
  run rcpt
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.3 sha mal formado y resultado fuera del enum: declarado, salida 2" {
  rec "abc123" "[$(v revision reviewer-a $S1 superada)]"
  run rcpt
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == declarado:* ]]
  rec $S1 "[$(v revision reviewer-a $S1 quizas)]"
  run rcpt
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.3 JSON ilegible o fichero vacío: declarado, salida 2" {
  printf 'no es json{' > "$R"
  run rcpt
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == declarado:* ]]
  : > "$R"
  run rcpt
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.3 recibo inexistente: declarado, salida 2" {
  run python3 "$HV" receipt "$T/no-existe.json"
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.4 propuesta por el ejecutor sin aprobada_por: no cuenta" {
  rec $S1 "[$(v ci_base reviewer-a $S1 superada '"propuesta_por":"worker-1"' | sed 's/"propuesta_por":"reviewer-a",//')]"
  run rcpt
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.4 aprobada_por igual al ejecutor o a la orquestadora: no cuenta" {
  for ap in worker-1 savia-orchestrator; do
    rec $S1 "[$(v revision reviewer-a $S1 superada "\"aprobada_por\":\"$ap\",\"contenido_hash\":\"h1\",\"aprobada_hash\":\"h1\"" | sed 's/"propuesta_por":"reviewer-a"/"propuesta_por":"worker-1"/')]"
    run rcpt
    [[ "${lines[0]}" == declarado:* ]]
  done
}

@test "AC-2.4 par positivo: propuesta del ejecutor aprobada por la persona sobre el mismo hash cuenta" {
  rec $S1 "[$(v revision reviewer-a $S1 superada '"aprobada_por":"persona-1","contenido_hash":"h1","aprobada_hash":"h1"' | sed 's/"propuesta_por":"reviewer-a"/"propuesta_por":"worker-1"/')]"
  run rcpt
  [[ "${lines[0]}" == verificado:* ]]
}

@test "AC-2.4 limite: aprobación sobre un hash distinto (el ejecutor cambió la prueba) no cuenta" {
  rec $S1 "[$(v revision reviewer-a $S1 superada '"aprobada_por":"persona-1","contenido_hash":"h2","aprobada_hash":"h1"' | sed 's/"propuesta_por":"reviewer-a"/"propuesta_por":"worker-1"/')]"
  run rcpt
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-2.5 verificación de un SHA anterior al vigente: no cuenta, el motivo lo dice" {
  rec $S2 "[$(v revision reviewer-a $S1 superada)]"
  run rcpt
  [[ "${lines[0]}" == declarado:* ]]
  [[ "${lines[0]}" == *"SHA anterior"* ]]
}

@test "AC-2.6 una superada y una fallida independientes: refutado, salida 1" {
  rec $S1 "[$(v revision reviewer-a $S1 superada),$(v ci_base ci-base $S1 fallida)]"
  run rcpt
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == refutado:* ]]
}

@test "AC-2.6 par negativo: la fallida es del propio ejecutor, no refuta ni se calla" {
  rec $S1 "[$(v ci_propio worker-1 $S1 fallida)]"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
  [[ "${lines[0]}" == *"propia del ejecutor falla"* ]]
}

@test "AC-2.7 campo de estado escrito por el ejecutor: se ignora y se anota como anomalía" {
  rec $S1 "[]"
  python3 - "$R" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["estado"] = "verificado"; d["verificado"] = True
json.dump(d, open(sys.argv[1], "w"))
PY
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
  [[ "$output" == *"anomalia=campo 'estado' escrito por el ejecutor, ignorado"* ]]
  [[ "$output" == *"anomalia=campo 'verificado' escrito por el ejecutor, ignorado"* ]]
}

@test "AC-2.7 ignorar no es rechazar: con evidencia real, un estado escrito por el ejecutor no cambia el resultado" {
  rec $S1 "[$(v revision reviewer-a $S1 superada)]"
  python3 - "$R" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["estado"] = "refutado"
json.dump(d, open(sys.argv[1], "w"))
PY
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == verificado:* ]]
  [[ "$output" == *"anomalia="* ]]
}

@test "AC-2.7 el campo de estado dentro de una verificación se ignora (no se rechaza): verificador independiente, sale verificado" {
  rec $S1 "[$(v revision reviewer-a $S1 superada '"verificado":false,"estado":"refutado"')]"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == verificado:* ]]
  [[ "$output" == *"anomalia=campo 'verificado' escrito por el ejecutor, ignorado"* ]]
  [[ "$output" == *"anomalia=campo 'estado' escrito por el ejecutor, ignorado"* ]]
}

@test "AC-2.7 par negativo: el campo de estado dentro de una verificación no sube a verificado si el verificador es el ejecutor" {
  rec $S1 "[$(v revision worker-1 $S1 superada '"verificado":true')]"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
  [[ "$output" == *"anomalia=campo 'verificado'"* ]]
}

@test "recibo sin version pero con campos S2: declarado, salida 0 y anomalía anotada" {
  printf '{"job":"j1","ejecutor":"w","sha":"%s","verificaciones":[{"basura":1}]}\n' $S1 > "$R"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
  [[ "$output" == *"anomalia=campo 'verificaciones' sin 'version'"* ]]
}

@test "AC-2.8 recibo anterior a S2 (sin version ni campos nuevos): se lee, declarado, salida 0" {
  printf '{"job":"j1","estado_fin":"OK"}\n' > "$R"
  run rcpt
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "esquema versionado: version distinta de 1 no valida" {
  printf '{"version":2,"job":"j1","ejecutor":"w","sha":"%s"}\n' $S1 > "$R"
  run rcpt
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == declarado:*esquema* ]]
}

@test "schemas/recibo-trabajo.schema.json es JSON válido con version const 1" {
  run python3 -c "import json;s=json.load(open('$ROOT/schemas/recibo-trabajo.schema.json'));assert s['properties']['version']['const']==1"
  [ "$status" -eq 0 ]
}

# ── savia-runs.sh derive: junto al estado de la PR, sin guardar ──────────
mkrun() {
  export SAVIA_RUNS_LEDGER="$T/ledger.jsonl" SAVIA_RUNS_LOCK_WAIT=5
  RID="$(bash "$RUNS" start agent-task worker-1 "tarea" 2>/dev/null | tail -1)"
  bash "$RUNS" pr "$RID" 7 --state open --ci passing --review approved --mergeable true >/dev/null 2>&1
}

@test "derive: expone estado de la PR y hecho verificado, y no modifica el ledger" {
  mkrun
  rec $S1 "[$(v revision reviewer-a $S1 superada)]"
  before="$(sha256sum "$SAVIA_RUNS_LEDGER")"
  run bash "$RUNS" derive "$RID" --receipt "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"derived_status   : approved"* ]]
  [[ "$output" == *"hecho_verificado : verificado"* ]]
  [ "$before" = "$(sha256sum "$SAVIA_RUNS_LEDGER")" ]
}

@test "derive: PR aprobada pero sin recibo => declarado (la PR aprobada no verifica)" {
  mkrun
  run bash "$RUNS" derive "$RID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"derived_status   : approved"* ]]
  [[ "$output" == *"hecho_verificado : declarado"* ]]
}

@test "derive: recibo que no valida => declarado, nunca verificado" {
  mkrun
  printf '{"version":1,"job":"j1"}\n' > "$R"
  run bash "$RUNS" derive "$RID" --receipt "$R"
  [[ "$output" == *"hecho_verificado : declarado"* ]]
  [[ "$output" != *"hecho_verificado : verificado"* ]]
}

@test "derive: recibo refutado se muestra como refutado; run inexistente falla" {
  mkrun
  rec $S1 "[$(v revision reviewer-a $S1 superada),$(v ci_base ci-base $S1 fallida)]"
  run bash "$RUNS" derive "$RID" --receipt "$R"
  [[ "$output" == *"hecho_verificado : refutado"* ]]
  run bash "$RUNS" derive no-existe --receipt "$R"
  [ "$status" -ne 0 ]
}

@test "derive: --receipt sin valor falla con error y no se cuelga" {
  mkrun
  run timeout 10 bash "$RUNS" derive "$RID" --receipt
  [ "$status" -eq 1 ]
  [[ "$output" == *"--receipt requires"* ]]
}

@test "derive: hv_motivo es de una línea; clase y anomalía van en hv_detalle" {
  mkrun
  rec $S1 "[$(v revision reviewer-a $S1 superada '"verificado":true')]"
  run bash "$RUNS" derive "$RID" --receipt "$R"
  [[ "$output" == *"hecho_verificado : verificado"* ]]
  [[ "$output" == *"recibo_valido    : si"* ]]
  [[ "$output" == *"hv_detalle       : clase=revision"* ]]
  [[ "$output" == *"hv_detalle       : anomalia=campo 'verificado'"* ]]
  mot="$(printf '%s\n' "$output" | grep -A1 '^hv_motivo' | tail -1)"
  [[ "$mot" != clase=* && "$mot" != anomalia=* ]]
}

@test "derive: recibo que no valida expone recibo_valido=no y la salida 2 del derivador" {
  mkrun
  printf '{"version":1,"job":"j1"}\n' > "$R"
  run bash "$RUNS" derive "$RID" --receipt "$R"
  [[ "$output" == *"recibo_valido    : no"* ]]
  [[ "$output" == *"hv_exit          : 2"* ]]
}

@test "derive: el entorno no puede vaciar la lista de orquestadoras" {
  mkrun
  rec $S1 "[$(v revision savia-orquestadora $S1 superada)]"
  HECHO_VERIFICADO_ORCH="otra-id" run bash "$RUNS" derive "$RID" --receipt "$R"
  [[ "$output" == *"hecho_verificado : declarado"* ]]
}

@test "límite de confianza: un recibo escrito por el ejecutor puede aparentar verificado (documentado, no autenticado)" {
  rec $S1 "[$(v revision forjado-x $S1 superada)]"
  run rcpt
  [[ "${lines[0]}" == verificado:* ]]
  grep -q "no está autenticado" "$ROOT/docs/rules/domain/hecho-verificado.md"
}
