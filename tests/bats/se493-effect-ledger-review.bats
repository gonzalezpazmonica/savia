#!/usr/bin/env bats
# SE-493 S1 — correcciones tras la revisión independiente de la PR #1517.
# Token fuera de `status`, holder zombi, error interno ≠ veredicto, complete que no contradice
# la entrada ni un rechazo anotado, permisos del ledger, lock por realpath y ganchos inertes
# con TMPDIR=/ o con un enlace duro al ledger por defecto.
# Ref: docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md

load se493-helpers

setup() { se493_setup; }
teardown() { se493_teardown; }

# ── P1-1: el token de reclamación no sale por `status` ───────────────────

@test "status y status --open no exponen claim_token; otro proceso no puede usar la reclamación" {
  out=$(se493_prepare 501 "$SE493_HEAD_A" squash); read -r v eid tok <<<"$out"
  [ "$v" = PROCEED ]; [ -n "$tok" ]
  run led status "$SE493_REPO#501"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$tok"* ]]
  [[ "$output" != *claim_token* ]]
  [[ "$output" == *'"claim_held":true'* ]]
  run led status --open
  [ "$status" -eq 0 ]
  [[ "$output" == *"$eid"* ]]
  [[ "$output" != *"$tok"* ]]
  # el titular sigue pudiendo despachar con su token
  run led dispatch "$eid" --claim "$tok"
  [ "$status" -eq 0 ]
}

@test "status tras cerrar: claim_held false y sin token" {
  se493_to_dispatched 502
  led complete "$EID" --claim "$TOK" --response '{"mergeCommit":"cccccccccccccccccccccccccccccccccccccccc"}' >/dev/null
  run led status "$SE493_REPO#502"
  [[ "$output" == *'"claim_held":false'* ]]
  [[ "$output" != *"$TOK"* ]]
}

# ── P2-1: holder zombi = muerto ──────────────────────────────────────────

fake_proc() {  # pid estado → copia /proc/<pid>/stat bajo $P con el estado indicado
  mkdir -p "$P/$1"
  python3 -I - "/proc/$1/stat" "$P/$1/stat" "$2" <<'EOF'
import sys
s = open(sys.argv[1]).read(); i = s.rindex(")") + 2
open(sys.argv[2], "w").write(s[:i] + sys.argv[3] + s[i + 1:])
EOF
}

@test "holder zombi (estado Z, mismo starttime) → huérfano: PROCEED con token nuevo; vivo (S) → 6" {
  export P="$BATS_TEST_TMPDIR/proc"; export SAVIA_EFFECT_PROC="$P"
  se493_holder; fake_proc "$HOLDER" S
  out=$(led prepare pr.merge --repo "$SE493_REPO" --number 503 --head "$SE493_HEAD_A" --method squash --holder-pid "$HOLDER")
  read -r v eid tok <<<"$out"; [ "$v" = PROCEED ]
  [ -n "$(field "$SE493_REPO#503" holder_start)" ]
  run se493_prepare 503 "$SE493_HEAD_A" squash
  [ "$status" -eq 6 ]                        # control: mismo starttime y vivo → en curso
  fake_proc "$HOLDER" Z
  run se493_prepare 503 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]; [[ "$output" == "PROCEED $eid "* ]]
  [[ "$output" != *" $tok" ]]
}

# ── P2-2: fallo interno → 2, nunca el 1 de verify-receipt ────────────────

@test "fila corrupta (args no JSON) → reconcile y verify-receipt salen con 2 y ERROR interno, no 1" {
  se493_to_dispatched 504
  python3 -I - "$SAVIA_EFFECT_LEDGER" "$EID" <<'EOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1]); db.execute("UPDATE effects SET args='{' WHERE effect_id=?", (sys.argv[2],)); db.commit()
EOF
  run led reconcile "$SE493_REPO#504"
  [ "$status" -eq 2 ]; [[ "$output" == *"ERROR interno"* ]]
  [[ "$output" != *Traceback* ]]
  [ "$(field "$SE493_REPO#504" state)" = DISPATCHED ]
}

# ── P2-3: complete no contradice la entrada ni un rechazo anotado ────────

@test "complete tras reject anotado → 6 sin recibo; la cierra la sonda" {
  se493_to_dispatched 505
  led reject "$EID" --claim "$TOK" --response "not mergeable" >/dev/null || true
  run led complete "$EID" --claim "$TOK" --response '{"mergeCommit":"cccccccccccccccccccccccccccccccccccccccc"}'
  [ "$status" -eq 6 ]; [[ "$output" == *"rechazo anotado"* ]]
  [ "$(field "$SE493_REPO#505" state)" = DISPATCHED ]
  [ "$(field "$SE493_REPO#505" receipt)" = "" ]
}

@test "complete con headRefOid o mergedBy que contradicen la entrada → 6 sin recibo; coincidentes → 0" {
  se493_to_dispatched 506
  run led complete "$EID" --claim "$TOK" --response '{"mergeCommit":"cccccccccccccccccccccccccccccccccccccccc","headRefOid":"'"$SE493_HEAD_B"'"}'
  [ "$status" -eq 6 ]; [[ "$output" == *contradice* ]]
  run led complete "$EID" --claim "$TOK" --response '{"mergeCommit":"cccccccccccccccccccccccccccccccccccccccc","mergedBy":{"login":"otra-cuenta"}}'
  [ "$status" -eq 6 ]
  [ "$(field "$SE493_REPO#506" state)" = DISPATCHED ]
  [ "$(field "$SE493_REPO#506" receipt)" = "" ]
  run led complete "$EID" --claim "$TOK" --response '{"mergeCommit":"cccccccccccccccccccccccccccccccccccccccc","headRefOid":"'"$SE493_HEAD_A"'","mergedBy":{"login":"Cuenta-Sintetica-A"}}'
  [ "$status" -eq 0 ]
  [ "$(field "$SE493_REPO#506" state)" = SUCCEEDED ]
}

# ── P2 seguridad: permisos y lock ────────────────────────────────────────

@test "ledger, WAL y lock con permisos 600; directorio 700" {
  se493_prepare 507 "$SE493_HEAD_A" squash >/dev/null
  d="$(dirname "$SAVIA_EFFECT_LEDGER")"
  [ "$(stat -c %a "$d")" = 700 ]
  for f in "$SAVIA_EFFECT_LEDGER" "$SAVIA_EFFECT_LEDGER.lock"; do
    [ "$(stat -c %a "$f")" = 600 ]
  done
  for f in "$SAVIA_EFFECT_LEDGER"-wal "$SAVIA_EFFECT_LEDGER"-shm; do
    [[ ! -e "$f" ]] || [ "$(stat -c %a "$f")" = 600 ]
  done
}

@test "un enlace simbólico al ledger usa el mismo lock (realpath), no uno propio" {
  se493_prepare 508 "$SE493_HEAD_A" squash >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/sl"
  ln -s "$SAVIA_EFFECT_LEDGER" "$BATS_TEST_TMPDIR/sl/ledger.db"
  SAVIA_EFFECT_LEDGER="$BATS_TEST_TMPDIR/sl/ledger.db" run led status "$SE493_REPO#508"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/sl/ledger.db.lock" ]
  [ -e "$SAVIA_EFFECT_LEDGER.lock" ]
}

# ── P2 seguridad: ganchos inertes con TMPDIR=/ o enlace duro ─────────────

@test "con TMPDIR=/ los ganchos se ignoran con aviso" {
  export TMPDIR=/ SAVIA_EFFECT_FAULT=after_prepare
  run se493_prepare 509 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]; [[ "$output" == *"ganchos de prueba ignorados"* ]]
}

@test "con un enlace duro bajo TMPDIR al ledger por defecto, los ganchos se ignoran" {
  ( unset SAVIA_EFFECT_LEDGER; led status --open >/dev/null )
  def="$HOME/.savia/effects/ledger.db"; [ -f "$def" ]
  mkdir -p "$BATS_TEST_TMPDIR/hl"
  ln "$def" "$BATS_TEST_TMPDIR/hl/ledger.db"
  export SAVIA_EFFECT_LEDGER="$BATS_TEST_TMPDIR/hl/ledger.db" SAVIA_EFFECT_FAULT=after_prepare
  run se493_prepare 510 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]; [[ "$output" == *"ganchos de prueba ignorados"* ]]
}

# ── Segunda revisión (cabeza 735d69371) ──────────────────────────────────

@test "3e: rechazo anotado + UNKNOWN pasada la gracia → revisión dispatched; un merge posterior coincidente no se resuelve por sonda (2, sin recibo)" {
  se493_to_dispatched 520
  led reject "$EID" --claim "$TOK" --response "not mergeable" >/dev/null || true
  se493_view_raw ''
  SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + 300 )) run led reconcile "$SE493_REPO#520"
  [ "$status" -eq 4 ]; [[ "$output" == *"review_origin=dispatched" ]]
  [ "$(field "$SE493_REPO#520" dispatch_rejected)" = 1 ]
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a"
  run led resolve "$EID" --by-probe
  [ "$status" -eq 2 ]; [[ "$output" == *"rechazo anotado"* ]]
  [ "$(field "$SE493_REPO#520" state)" = NEEDS_REVIEW ]
  [ "$(field "$SE493_REPO#520" receipt)" = "" ]
  run led verify-receipt "$EID"
  [ "$status" -ne 0 ]
}

@test "3e control: sin rechazo anotado, la misma secuencia sí se resuelve por sonda (0, SUCCEEDED)" {
  se493_to_dispatched 521
  se493_view_raw ''
  SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + 300 )) led reconcile "$SE493_REPO#521" >/dev/null || true
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a"
  run led resolve "$EID" --by-probe
  [ "$status" -eq 0 ]
  [ "$(field "$SE493_REPO#521" state)" = SUCCEEDED ]
}

@test "complete con mergeCommit que no es sha de 40 hex → 6 sin recibo" {
  se493_to_dispatched 522
  for bad in x 'cccccccccccccccccccccccccccccccccccccccC' 'ccccccccccccccccccccccccccccccccccccccc' '{"oid":"main"}'; do
    if [[ "$bad" == \{* ]]; then resp='{"mergeCommit":'"$bad"'}'; else resp='{"mergeCommit":"'"$bad"'"}'; fi
    run led complete "$EID" --claim "$TOK" --response "$resp"
    [ "$status" -eq 6 ]; [[ "$output" == *"sha de 40 hex"* ]]
  done
  [ "$(field "$SE493_REPO#522" state)" = DISPATCHED ]
  [ "$(field "$SE493_REPO#522" receipt)" = "" ]
}

@test "ledger y directorio ya existentes con permisos abiertos se cierran a 600/700 al abrir" {
  se493_prepare 523 "$SE493_HEAD_A" squash >/dev/null
  d="$(dirname "$SAVIA_EFFECT_LEDGER")"
  chmod 755 "$d"; chmod 644 "$SAVIA_EFFECT_LEDGER" "$SAVIA_EFFECT_LEDGER.lock"
  run led status "$SE493_REPO#523"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$d")" = 700 ]
  [ "$(stat -c %a "$SAVIA_EFFECT_LEDGER")" = 600 ]
  [ "$(stat -c %a "$SAVIA_EFFECT_LEDGER.lock")" = 600 ]
}

@test "f5-state.sh y effect-reservation.sh rechazan claves con recorrido de rutas (2) sin crear nada fuera" {
  R="$BATS_TEST_TMPDIR/res"; mkdir -p "$R/sub"
  for k in '../fuera' 'a/b' '' '.oculta'; do
    SAVIA_RESERVATIONS="$R/sub" run bash "$REPO_DIR/scripts/effect-reservation.sh" reserve pr.merge "$k"
    [ "$status" -eq 2 ]; [[ "$output" == *"no válida"* ]]
  done
  for k in '../7' 'abc' '' '07'; do
    SAVIA_RESERVATIONS="$R/sub" run bash "$REPO_DIR/scripts/f5-state.sh" reserve pr.merge "$k"
    [ "$status" -eq 2 ]; [[ "$output" == *"no es un número de PR"* ]]
  done
  [ -z "$(ls -A "$R/sub")" ]
  [ ! -e "$R/pr.merge__fuera.json" ]
  # Controles: claves válidas siguen funcionando.
  SAVIA_RESERVATIONS="$R/sub" run bash "$REPO_DIR/scripts/effect-reservation.sh" reserve pr.merge bats-key.1
  [ "$status" -eq 0 ]
  SAVIA_RESERVATIONS="$R/sub" run bash "$REPO_DIR/scripts/f5-state.sh" reserve pr.merge 42
  [ "$status" -eq 0 ]
}
