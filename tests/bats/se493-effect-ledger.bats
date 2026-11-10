#!/usr/bin/env bats
# SE-493 S1 — Effect Ledger: reclamación, CAS, gracia, complete/fail/reject, reconcile (3d),
# reintento tras resync (2d.3), resolve --by-probe y recibo verificable.
# Ref: docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md
# Remoto simulado (stub gh) que cuenta las peticiones de efecto; ledger y HOME temporales.

load se493-helpers

setup() { se493_setup; }
teardown() { se493_teardown; }

G=300  # dispatch_grace_s de pr.merge

# ── AC-a — caída antes de iniciar ────────────────────────────────────────

@test "AC-a: llamador muerto tras prepare → PREPARED huérfano, PROCEED con token nuevo y un solo efecto" {
  out=$(se493_prepare 11 "$SE493_HEAD_A" squash); read -r v eid1 tok1 <<<"$out"
  [ "$v" = PROCEED ]
  kill "$(tail -1 "$BATS_TEST_TMPDIR/holders")"   # el llamador muere (su PID iba en --holder-pid)
  sleep 0.2
  run se493_prepare 11 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]
  read -r v eid tok <<<"$output"
  [ "$eid" = "$eid1" ]; [ "$tok" != "$tok1" ]
  run led dispatch "$eid" --claim "$tok1"
  [ "$status" -eq 6 ]                       # token antiguo: no envíes
  led dispatch "$eid" --claim "$tok" >/dev/null
  gh pr merge 11 >/dev/null                  # el llamador envía
  led complete "$eid" --claim "$tok" --response '{"mergeCommit":{"oid":"cccccccccccccccccccccccccccccccccccccccc"},"headRefOid":"'"$SE493_HEAD_A"'"}' >/dev/null
  [ "$(field "$SE493_REPO#11" state)" = SUCCEEDED ]
  [ "$(merges)" -eq 1 ]
  run se493_prepare 11 "$SE493_HEAD_A" squash
  [ "$status" -eq 3 ]
  [[ "$output" == ALREADY_EXECUTED* ]]
  [ "$(merges)" -eq 1 ]
}

@test "AC-a: llamador vivo con lease vigente y con lease vencido → IN_FLIGHT (6)" {
  se493_prepare 12 "$SE493_HEAD_A" squash >/dev/null
  run se493_prepare 12 "$SE493_HEAD_A" squash
  [ "$status" -eq 6 ]; [[ "$output" == IN_FLIGHT* ]]
  export SAVIA_EFFECT_NOW=$(( $(date +%s) + 100000 ))
  run se493_prepare 12 "$SE493_HEAD_A" squash
  [ "$status" -eq 6 ]
}

@test "AC-a: prepare sin --holder-pid sale con 2 y no escribe en el ledger" {
  run led prepare pr.merge --repo "$SE493_REPO" --number 13 --head "$SE493_HEAD_A" --method squash
  [ "$status" -eq 2 ]
  [ "$(led status "$SE493_REPO#13")" = none ]
}

@test "AC-a: PID reutilizado (holder_pid vivo con otro holder_start) → huérfano" {
  out=$(se493_prepare 14 "$SE493_HEAD_A" squash); read -r _ eid _ <<<"$out"
  python3 -I - "$SAVIA_EFFECT_LEDGER" "$eid" <<'EOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1]); db.execute("UPDATE effects SET holder_start='1' WHERE effect_id=?", (sys.argv[2],)); db.commit()
EOF
  run se493_prepare 14 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]; [[ "$output" == "PROCEED $eid "* ]]
}

@test "AC-a: fallo inyectado after_prepare mata el proceso tras persistir PREPARED" {
  export SAVIA_EFFECT_FAULT=after_prepare
  run se493_prepare 15 "$SE493_HEAD_A" squash
  [ "$status" -eq 137 ]
  [ "$(field "$SE493_REPO#15" state)" = PREPARED ]
}

# ── AC-d — misma clave, otros argumentos (2d) ────────────────────────────

@test "AC-d: SUCCEEDED + otro head → CONFLICT (5) sin llamada remota; mismo args → 3 con el recibo byte a byte" {
  se493_to_dispatched 21
  led complete "$EID" --claim "$TOK" --response '{"mergeCommit":"dddddddddddddddddddddddddddddddddddddddd"}' >/dev/null
  rec=$(field "$SE493_REPO#21" receipt)
  v0=$(views)
  run se493_prepare 21 "$SE493_HEAD_B" squash
  [ "$status" -eq 5 ]; [[ "$output" == CONFLICT* ]]
  [ "$(views)" -eq "$v0" ]
  [ "$(field "$SE493_REPO#21" receipt)" = "$rec" ]
  run se493_prepare 21 "$SE493_HEAD_A" squash
  [ "$status" -eq 3 ]
  [ "${lines[1]}" = "$rec" ]
  [ "$(merges)" -eq 0 ]
}

@test "AC-d: otro método → 5 desde FAILED y desde DISPATCHED" {
  se493_to_dispatched 22
  run se493_prepare 22 "$SE493_HEAD_A" merge
  [ "$status" -eq 5 ]
  out=$(se493_prepare 23 "$SE493_HEAD_A" squash); read -r _ e t <<<"$out"
  led fail "$e" --claim "$t" --reason "grant caducado" >/dev/null
  run se493_prepare 23 "$SE493_HEAD_A" rebase
  [ "$status" -eq 5 ]
}

@test "AC-d: NEEDS_REVIEW + otro head → 4; FAILED + solo head distinto → 0 con args nuevos" {
  se493_to_dispatched 24
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G ))
  se493_view_raw 'no json'
  led reconcile "$SE493_REPO#24" >/dev/null || true
  [ "$(field "$SE493_REPO#24" state)" = NEEDS_REVIEW ]
  run se493_prepare 24 "$SE493_HEAD_B" squash
  [ "$status" -eq 4 ]
  unset SAVIA_EFFECT_NOW
  out=$(se493_prepare 25 "$SE493_HEAD_A" squash); read -r _ e t <<<"$out"
  led fail "$e" --claim "$t" --reason "validación local" >/dev/null
  run se493_prepare 25 "$SE493_HEAD_B" squash
  [ "$status" -eq 0 ]
  [ "$(field "$SE493_REPO#25" attempt)" = 2 ]
  [[ "$(field "$SE493_REPO#25" args)" == *"$SE493_HEAD_B"* ]]
}

@test "AC-d: op de prueba sin head_pinned → cambio de head sobre FAILED da 5" {
  reg="$BATS_TEST_TMPDIR/ops.json"
  python3 -I - "$REPO_DIR/scripts/effect-ops.json" "$reg" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1])); op = dict(r["ops"]["pr.merge"]); op["head_pinned"] = False
r["ops"]["test.unpinned"] = op; json.dump(r, open(sys.argv[2], "w"))
EOF
  export SAVIA_EFFECT_REGISTRY="$reg"
  se493_holder
  out=$(led prepare test.unpinned --repo "$SE493_REPO" --number 26 --head "$SE493_HEAD_A" --method squash --holder-pid "$HOLDER")
  read -r _ e t <<<"$out"
  led fail "$e" --claim "$t" --reason x >/dev/null
  run led prepare test.unpinned --repo "$SE493_REPO" --number 26 --head "$SE493_HEAD_B" --method squash --holder-pid "$HOLDER"
  [ "$status" -eq 5 ]
}

# ── Transiciones admitidas: complete / reject / fail ────────────────────

@test "complete sin evidencia (mergeCommit) deja DISPATCHED y sale con 6; con token ajeno sale con 2" {
  se493_to_dispatched 31
  run led complete "$EID" --claim "$TOK" --response '{"ok":true}'
  [ "$status" -eq 6 ]
  [ "$(field "$SE493_REPO#31" state)" = DISPATCHED ]
  run led complete "$EID" --claim deadbeef --response '{"mergeCommit":"x"}'
  [ "$status" -eq 2 ]
  [ "$(field "$SE493_REPO#31" state)" = DISPATCHED ]
}

@test "fail solo desde PREPARED: desde DISPATCHED sale con 2 y no cambia nada" {
  se493_to_dispatched 32
  run led fail "$EID" --claim "$TOK" --reason x
  [ "$status" -eq 2 ]
  [ "$(field "$SE493_REPO#32" state)" = DISPATCHED ]
}

# ── AC-p — reconcile por estado (3d) y reject (3e) ───────────────────────

@test "AC-p: clave ausente → NOT_SENT (0); PREPARED vivo → 6; PREPARED huérfano → 0" {
  run led reconcile "$SE493_REPO#41"
  [ "$status" -eq 0 ]; [ "$output" = "NOT_SENT - - -" ]
  se493_prepare 41 "$SE493_HEAD_A" squash >/dev/null
  run led reconcile "$SE493_REPO#41"
  [ "$status" -eq 6 ]; [[ "$output" == IN_FLIGHT* ]]
  kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true
  run led reconcile "$SE493_REPO#41"
  [ "$status" -eq 0 ]; [[ "$output" == NOT_SENT*" -" ]]
  [ "$(field "$SE493_REPO#41" state)" = PREPARED ]
}

@test "AC-p: DISPATCHED con PRESENT coincidente → RECONCILED (3) y luego ALREADY_SUCCEEDED (7), un recibo, head del recibo" {
  se493_to_dispatched 42
  se493_view_merged "$SE493_HEAD_A" "Cuenta-Sintetica-A"     # login en otra caja: coincide
  run led reconcile "$SE493_REPO#42"
  [ "$status" -eq 3 ]; [[ "$output" == "RECONCILED $EID - $SE493_HEAD_A" ]]
  run led reconcile "$SE493_REPO#42"
  [ "$status" -eq 7 ]; [[ "$output" == "ALREADY_SUCCEEDED $EID - $SE493_HEAD_A" ]]
  n=$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from receipts").fetchone()[0])' "$SAVIA_EFFECT_LEDGER")
  [ "$n" -eq 1 ]
  [[ "$(field "$SE493_REPO#42" receipt)" == *'"attribution":"probe"'* ]]
  [ "$(merges)" -eq 0 ]
}

@test "AC-p: DISPATCHED con PRESENT discrepante (otro mergedBy, otro head) → 4 sin esperar a la gracia" {
  se493_to_dispatched 43
  se493_view_merged "$SE493_HEAD_A" "otra-cuenta"
  run led reconcile "$SE493_REPO#43"
  [ "$status" -eq 4 ]; [[ "$output" == *"review_origin=dispatched" ]]
  se493_to_dispatched 44
  se493_view_merged "$SE493_HEAD_B" "cuenta-sintetica-a"
  run led reconcile "$SE493_REPO#44"
  [ "$status" -eq 4 ]
}

@test "AC-p: DISPATCHED dentro de la gracia (ABSENT o UNKNOWN) → 6; borde grace-1 → 6, grace exacto → 4/0" {
  se493_to_dispatched 45
  run led reconcile "$SE493_REPO#45"
  [ "$status" -eq 6 ]; [[ "$output" == "IN_FLIGHT $EID - -" ]]
  se493_view_raw '{"state":"OPEN"' 1
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G - 1 ))
  run led reconcile "$SE493_REPO#45"
  [ "$status" -eq 6 ]
  [ "$(field "$SE493_REPO#45" state)" = DISPATCHED ]
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G ))
  run led reconcile "$SE493_REPO#45"
  [ "$status" -eq 4 ]
  [ "$(field "$SE493_REPO#45" review_origin)" = dispatched ]
  # ABSENT definitivo en el borde exacto → FAILED sin intento nuevo
  unset SAVIA_EFFECT_NOW
  se493_to_dispatched 46
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G ))
  run led reconcile "$SE493_REPO#46"
  [ "$status" -eq 0 ]; [[ "$output" == NOT_SENT* ]]
  [ "$(field "$SE493_REPO#46" state)" = FAILED ]
  [ "$(field "$SE493_REPO#46" attempt)" = 1 ]
  [ "$(merges)" -eq 0 ]
}

@test "AC-p: SUCCEEDED, NEEDS_REVIEW y FAILED se informan sin sondear ni cambiar" {
  out=$(se493_prepare 47 "$SE493_HEAD_A" squash); read -r _ e t <<<"$out"
  led fail "$e" --claim "$t" --reason x >/dev/null
  v0=$(views)
  run led reconcile "$SE493_REPO#47"
  [ "$status" -eq 0 ]; [[ "$output" == "NOT_SENT $e - -" ]]
  [ "$(views)" -eq "$v0" ]
}

@test "AC-p (3e): rechazo anotado + PRESENT coincidente → 4 rejected; resolve --by-probe sale con 2 sin sondear" {
  se493_to_dispatched 48
  run led reject "$EID" --claim "$TOK" --response "not mergeable"
  [ "$status" -eq 6 ]
  [ "$(field "$SE493_REPO#48" state)" = DISPATCHED ]
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a"
  run led reconcile "$SE493_REPO#48"
  [ "$status" -eq 4 ]; [[ "$output" == *"review_origin=rejected" ]]
  v0=$(views)
  run led resolve "$EID" --by-probe
  [ "$status" -eq 2 ]
  [ "$(views)" -eq "$v0" ]
  [ "$(field "$SE493_REPO#48" state)" = NEEDS_REVIEW ]
}

@test "AC-p (3e): reject sobre PREPARED o con token ajeno → 2; rechazo + ABSENT pasada la gracia → FAILED" {
  out=$(se493_prepare 49 "$SE493_HEAD_A" squash); read -r _ e t <<<"$out"
  run led reject "$e" --claim "$t" --response x
  [ "$status" -eq 2 ]
  se493_to_dispatched 50
  run led reject "$EID" --claim otro --response x
  [ "$status" -eq 2 ]
  led reject "$EID" --claim "$TOK" --response x >/dev/null || true
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G ))
  run led reconcile "$SE493_REPO#50"
  [ "$status" -eq 0 ]
  [ "$(field "$SE493_REPO#50" state)" = FAILED ]
}

# ── Regla 3 desde prepare: ABSENT pasada la gracia → FAILED + attempt+1 ──

@test "prepare sobre DISPATCHED: ABSENT al momento → 6; en grace-1 → 6; en grace exacto → 0 con attempt+1" {
  se493_to_dispatched 51
  run se493_prepare 51 "$SE493_HEAD_A" squash
  [ "$status" -eq 6 ]
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G - 1 ))
  run se493_prepare 51 "$SE493_HEAD_A" squash
  [ "$status" -eq 6 ]
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G ))
  run se493_prepare 51 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]; [[ "$output" == PROCEED* ]]
  [ "$(field "$SE493_REPO#51" attempt)" = 2 ]
  [ "$(field "$SE493_REPO#51" state)" = PREPARED ]
  [ "$(merges)" -eq 0 ]
}

@test "prepare sobre DISPATCHED: sin identidad remota tras ABSENT definitivo → FAILED anterior, sin reclamar (2)" {
  se493_to_dispatched 52
  echo 1 > "$STUB/user.rc"
  export SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G ))
  run se493_prepare 52 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]
  [ "$(field "$SE493_REPO#52" state)" = FAILED ]
  [ "$(field "$SE493_REPO#52" attempt)" = 1 ]
}

@test "2d: PREPARED huérfano con head A + prepare con head B → 0; el intento A queda FAILED sin envío" {
  se493_prepare 53 "$SE493_HEAD_A" squash >/dev/null
  kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true
  run se493_prepare 53 "$SE493_HEAD_B" squash
  [ "$status" -eq 0 ]
  [ "$(field "$SE493_REPO#53" attempt)" = 2 ]
  f=$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select state||\":\"||failure from effects where attempt=1 and idempotency_key=?",(sys.argv[2],)).fetchone()[0])' "$SAVIA_EFFECT_LEDGER" "$SE493_REPO#53")
  [ "$f" = "FAILED:abandoned_unsent" ]
  # con el llamador vivo, el mismo cambio de head da 6
  se493_prepare 54 "$SE493_HEAD_A" squash >/dev/null
  run se493_prepare 54 "$SE493_HEAD_B" squash
  [ "$status" -eq 6 ]
}

# ── AC-q — reintento tras rechazo y resync (2d.3) ────────────────────────

@test "AC-q: DISPATCHED A con rechazo, sonda OPEN con head B → prepare B da 0, A superseded" {
  se493_to_dispatched 61 "$SE493_HEAD_A"
  led reject "$EID" --claim "$TOK" --response "BEHIND" >/dev/null || true
  se493_view_open "$SE493_HEAD_B"
  run se493_prepare 61 "$SE493_HEAD_B" squash
  [ "$status" -eq 0 ]
  st=$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select state||\":\"||failure from effects where effect_id=?",(sys.argv[2],)).fetchone()[0])' "$SAVIA_EFFECT_LEDGER" "$EID")
  [ "$st" = "FAILED:superseded" ]
  [[ "$(field "$SE493_REPO#61" args)" == *"$SE493_HEAD_B"* ]]
  [ "$(merges)" -eq 0 ]
}

@test "AC-q: lo mismo sin rechazo anotado" {
  se493_to_dispatched 62 "$SE493_HEAD_A"
  se493_view_open "$SE493_HEAD_B"
  run se493_prepare 62 "$SE493_HEAD_B" squash
  [ "$status" -eq 0 ]
}

@test "AC-q negativos: head A → 6; UNKNOWN → 6; MERGED de A con rechazo → 4 rejected; otro método → 5; auto-merge → 6" {
  se493_to_dispatched 63 "$SE493_HEAD_A"
  run se493_prepare 63 "$SE493_HEAD_B" squash
  [ "$status" -eq 6 ]
  se493_view_raw 'boom' 1
  run se493_prepare 63 "$SE493_HEAD_B" squash
  [ "$status" -eq 6 ]
  se493_view_open "$SE493_HEAD_B" '{"enabledAt":"2026-11-10T10:00:00Z"}'
  run se493_prepare 63 "$SE493_HEAD_B" squash
  [ "$status" -eq 6 ]
  run se493_prepare 63 "$SE493_HEAD_B" merge
  [ "$status" -eq 5 ]
  led reject "$EID" --claim "$TOK" --response x >/dev/null || true
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a"
  run se493_prepare 63 "$SE493_HEAD_B" squash
  [ "$status" -eq 4 ]; [[ "$output" == *"review_origin=rejected" ]]
  [ "$(merges)" -eq 0 ]
}

# ── AC-i — resolución por sonda (S1) ─────────────────────────────────────

to_review() {  # PR -> NEEDS_REVIEW (dispatched) con UNKNOWN pasada la gracia
  se493_to_dispatched "$1"
  se493_view_raw ''
  SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G )) led reconcile "$SE493_REPO#$1" >/dev/null || true
  [ "$(field "$SE493_REPO#$1" state)" = NEEDS_REVIEW ]
}

@test "AC-i: --by-probe con SAVIA_AUTONOMOUS_RUN=1: PRESENT → SUCCEEDED (0); ABSENT tras gracia → FAILED; UNKNOWN → 4" {
  export SAVIA_AUTONOMOUS_RUN=1
  to_review 71
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a"
  run led resolve "$EID" --by-probe
  [ "$status" -eq 0 ]
  [ "$(field "$SE493_REPO#71" state)" = SUCCEEDED ]
  [[ "$(field "$SE493_REPO#71" resolution)" == *'"route":"by-probe"'* ]]
  to_review 72
  se493_view_open "$SE493_HEAD_A"
  SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G )) run led resolve "$EID" --by-probe --outcome failed
  [ "$status" -eq 0 ]
  [ "$(field "$SE493_REPO#72" state)" = FAILED ]
  to_review 73
  run led resolve "$EID" --by-probe
  [ "$status" -eq 4 ]
  [ "$(field "$SE493_REPO#73" state)" = NEEDS_REVIEW ]
}

@test "AC-i: --outcome contrario a la sonda o --evidence → 2 sin escribir ni attempt+1" {
  to_review 74
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a"
  run led resolve "$EID" --by-probe --outcome failed
  [ "$status" -eq 2 ]
  [ "$(field "$SE493_REPO#74" state)" = NEEDS_REVIEW ]
  [ "$(field "$SE493_REPO#74" attempt)" = 1 ]
  se493_view_open "$SE493_HEAD_A"
  SAVIA_EFFECT_NOW=$(( DISPATCHED_AT + G )) run led resolve "$EID" --by-probe --outcome succeeded
  [ "$status" -eq 2 ]
  run led resolve "$EID" --by-probe --evidence nota
  [ "$status" -eq 2 ]
  [ "$(field "$SE493_REPO#74" state)" = NEEDS_REVIEW ]
  [ "$(merges)" -eq 0 ]
}

@test "AC-i: resolve sin ruta, con las dos, o --manual en S1 → 2" {
  to_review 75
  run led resolve "$EID"
  [ "$status" -eq 2 ]
  run led resolve "$EID" --by-probe --manual
  [ "$status" -eq 2 ]
  run led resolve "$EID" --manual --outcome succeeded --evidence x
  [ "$status" -eq 2 ]
  [ "$(field "$SE493_REPO#75" state)" = NEEDS_REVIEW ]
}

@test "3c: sonda previa PRESENT → NEEDS_REVIEW pre_probe (4) sin enviar; UNKNOWN → 2 y sigue PREPARED" {
  out=$(se493_prepare 76 "$SE493_HEAD_A" squash); read -r _ e t <<<"$out"
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a"
  run led dispatch "$e" --claim "$t"
  [ "$status" -eq 4 ]; [[ "$output" == *"review_origin=pre_probe" ]]
  [ "$(field "$SE493_REPO#76" state)" = NEEDS_REVIEW ]
  [ "$(field "$SE493_REPO#76" review_origin)" = pre_probe ]
  [ "$(field "$SE493_REPO#76" dispatched_at)" = "" ]
  run led resolve "$e" --by-probe
  [ "$status" -eq 2 ]
  se493_view_open "$SE493_HEAD_A"
  out=$(se493_prepare 77 "$SE493_HEAD_A" squash); read -r _ e t <<<"$out"
  se493_view_raw 'x' 1
  run led dispatch "$e" --claim "$t"
  [ "$status" -eq 2 ]
  [ "$(field "$SE493_REPO#77" state)" = PREPARED ]
  [ "$(merges)" -eq 0 ]
}

# ── AC-h — recibo verificable ────────────────────────────────────────────

close_ok() {  # PR -> SUCCEEDED por sonda; deja EID
  se493_to_dispatched "$1"
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a" "$2"
  led reconcile "$SE493_REPO#$1" >/dev/null || true
}

@test "AC-h: VERIFIED (0) con cadena íntegra y remoto coincidente; la salida declara method no verificado" {
  close_ok 81 1111111111111111111111111111111111111111
  run led verify-receipt "$EID"
  [ "$status" -eq 0 ]; [[ "$output" == VERIFIED*"unverified: method"* ]]
}

@test "AC-h: recibo de complete sin headRefOid ni mergedBy → VERIFIED sin afirmar esos campos; otro commit → FAIL" {
  se493_to_dispatched 85
  led complete "$EID" --claim "$TOK" --response '{"mergeCommit":{"oid":"4444444444444444444444444444444444444444"}}' >/dev/null
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a" 4444444444444444444444444444444444444444
  run led verify-receipt "$EID"
  [ "$status" -eq 0 ]; [[ "$output" == *"unverified: method,headRefOid,mergedBy"* ]]
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a" 5555555555555555555555555555555555555555
  run led verify-receipt "$EID"
  [ "$status" -eq 1 ]
}

@test "AC-h: FAIL (1) si cambia el merge_commit remoto; UNVERIFIED (4) con sonda UNKNOWN o sin gh" {
  close_ok 82 1111111111111111111111111111111111111111
  se493_view_merged "$SE493_HEAD_A" "cuenta-sintetica-a" 2222222222222222222222222222222222222222
  run led verify-receipt "$EID"
  [ "$status" -eq 1 ]
  se493_view_raw 'oops' 1
  run led verify-receipt "$EID"
  [ "$status" -eq 4 ]
  PATH="/usr/bin:/bin" run python3 -I "$LEDGER_PY" verify-receipt "$EID"
  [ "$status" -eq 4 ]
}

@test "AC-h: un byte alterado en un recibo anterior → FAIL (1), también sin sonda" {
  close_ok 83 1111111111111111111111111111111111111111
  first="$EID"
  close_ok 84 3333333333333333333333333333333333333333
  python3 -I - "$SAVIA_EFFECT_LEDGER" "$first" <<'EOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
b = db.execute("select body from receipts where effect_id=?", (sys.argv[2],)).fetchone()[0]
db.execute("update receipts set body=? where effect_id=?", (b.replace("succeeded", "succeedex"), sys.argv[2])); db.commit()
EOF
  run led verify-receipt "$EID"
  [ "$status" -eq 1 ]
  se493_view_raw '' 1
  run led verify-receipt "$EID"
  [ "$status" -eq 1 ]
  run led verify-receipt 00000000-0000-0000-0000-000000000000
  [ "$status" -eq 2 ]
}
