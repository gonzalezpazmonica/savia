#!/usr/bin/env bats
# SE-493 S1 — Effect Ledger: concurrencia (AC-f mismo ledger), multioperador (AC-j),
# fail-closed (AC-l), ganchos inertes (AC-m), validación de entradas (AC-n) y guard de op
# en f5-state.sh.
# Ref: docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md

load se493-helpers

setup() { se493_setup; }
teardown() { se493_teardown; }

rows() {  # filas del ledger (0 si no existe)
  [[ -f "${1:-$SAVIA_EFFECT_LEDGER}" ]] || { echo 0; return; }
  python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from effects").fetchone()[0])' "${1:-$SAVIA_EFFECT_LEDGER}"
}

# ── AC-f — dos workers sobre el mismo ledger ─────────────────────────────

@test "AC-f: 20 rondas con dos workers simultáneos → uno solo pasa el CAS por ronda; contador = 20" {
  W="$BATS_TEST_TMPDIR/worker.sh"
  cat > "$W" <<EOF
#!/usr/bin/env bash
n="\$1"; res="\$2"
out=\$(python3 -I "$LEDGER_PY" prepare pr.merge --repo "$SE493_REPO" --number "\$n" --head "$SE493_HEAD_A" --method squash --holder-pid \$\$ 2>/dev/null); rc=\$?
d=-
if [[ \$rc -eq 0 ]]; then
  read -r _ eid tok <<<"\$out"
  python3 -I "$LEDGER_PY" dispatch "\$eid" --claim "\$tok" >/dev/null 2>&1; d=\$?
  if [[ \$d -eq 0 ]]; then gh pr merge "\$n" >/dev/null; python3 -I "$LEDGER_PY" complete "\$eid" --claim "\$tok" --response '{"mergeCommit":"cccccccccccccccccccccccccccccccccccccccc"}' >/dev/null 2>&1; fi
fi
echo "\$n \$rc \$d" >> "\$res"
EOF
  chmod +x "$W"
  res="$BATS_TEST_TMPDIR/res"
  for n in $(seq 101 120); do
    if (( n > 110 )); then           # partir de PREPARED huérfano
      se493_prepare "$n" "$SE493_HEAD_A" squash >/dev/null
      kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true
    fi
    "$W" "$n" "$res" & p1=$!
    "$W" "$n" "$res" & p2=$!
    wait "$p1" "$p2"
  done
  [ "$(merges)" -eq 20 ]
  for n in $(seq 101 120); do
    ok=$(awk -v n="$n" '$1==n && $2==0 && $3==0' "$res" | wc -l)
    [ "$ok" -eq 1 ]
    # el otro: 6, 3, o PROCEED con dispatch 6
    other=$(awk -v n="$n" '$1==n && !($2==0 && $3==0) {print $2":"$3}' "$res")
    [[ "$other" =~ ^(6:-|3:-|0:6)$ ]] || { echo "ronda $n: $other"; cat "$res"; false; }
    [ "$(field "$SE493_REPO#$n" state)" = SUCCEEDED ]
  done
}

# ── AC-j — multioperador ─────────────────────────────────────────────────

@test "AC-j: sin rutas absolutas personales en effect-ledger.py ni en el registro" {
  # status 1 = sin coincidencias; 2 (fichero ausente) también falla el test.
  run grep -nE '(/home/|/Users/|/root/)' "$REPO_DIR/scripts/effect-ledger.py" "$REPO_DIR/scripts/effect-ops.json"
  [ "$status" -eq 1 ]
}

@test "AC-j: dos operadores sintéticos con dos HOME → cada uno su ledger por defecto; sin perfil → 2" {
  unset SAVIA_EFFECT_TEST SAVIA_EFFECT_LEDGER
  for who in a b; do
    export HOME="$BATS_TEST_TMPDIR/home-$who"; mkdir -p "$HOME"
    printf 'active_slug: "operadora-sintetica-%s"\n' "$who" > "$BATS_TEST_TMPDIR/au-$who.md"
    export SAVIA_ACTIVE_USER_FILE="$BATS_TEST_TMPDIR/au-$who.md"
    run se493_prepare 201 "$SE493_HEAD_A" squash
    [ "$status" -eq 0 ]
    [ -f "$HOME/.savia/effects/ledger.db" ]
    [ "$(rows "$HOME/.savia/effects/ledger.db")" -eq 1 ]
  done
  export SAVIA_ACTIVE_USER_FILE="$BATS_TEST_TMPDIR/no-existe.md"
  run se493_prepare 202 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]
  [ "$(rows "$HOME/.savia/effects/ledger.db")" -eq 1 ]
}

@test "AC-j: sin /proc legible → holder_pid NULL; exclusiva mientras el lease está vigente, huérfana solo al vencer" {
  export SAVIA_EFFECT_PROC="$BATS_TEST_TMPDIR/sin-proc"
  T0=$(date +%s); export SAVIA_EFFECT_NOW=$T0
  se493_prepare 211 "$SE493_HEAD_A" squash >/dev/null
  [ "$(field "$SE493_REPO#211" holder_pid)" = "" ]
  lease=$(field "$SE493_REPO#211" lease_until)
  kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true   # aunque muera, sin /proc solo cuenta el lease
  export SAVIA_EFFECT_NOW=$(( lease - 1 ))
  run se493_prepare 211 "$SE493_HEAD_A" squash
  [ "$status" -eq 6 ]
  export SAVIA_EFFECT_NOW=$lease
  run se493_prepare 211 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]
}

# ── AC-l — fail-closed ───────────────────────────────────────────────────

@test "AC-l: ledger corrupto → 2, nunca PROCEED" {
  mkdir -p "$(dirname "$SAVIA_EFFECT_LEDGER")"; head -c 4096 /dev/urandom > "$SAVIA_EFFECT_LEDGER"
  run se493_prepare 301 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]; [[ "$output" != *PROCEED* ]]
  [[ "$output" == *"ledger ilegible"* ]]   # el motivo, no un exit 2 cualquiera
}

@test "AC-l: esquema desconocido → 2 sin tocarlo" {
  mkdir -p "$(dirname "$SAVIA_EFFECT_LEDGER")"
  python3 -I -c 'import sqlite3,sys; d=sqlite3.connect(sys.argv[1]); d.execute("create table effects(x)"); d.commit()' "$SAVIA_EFFECT_LEDGER"
  run se493_prepare 302 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]; [[ "$output" == *"esquema del ledger desconocido"* ]]
  t=$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from sqlite_master where name=\"meta\"").fetchone()[0])' "$SAVIA_EFFECT_LEDGER")
  [ "$t" -eq 0 ]
}

@test "AC-l: ledger bloqueado más allá del timeout → 2" {
  se493_prepare 303 "$SE493_HEAD_A" squash >/dev/null
  python3 -I -c 'import sqlite3,sys,time; d=sqlite3.connect(sys.argv[1], isolation_level=None); d.execute("BEGIN IMMEDIATE"); open(sys.argv[2],"w").close(); time.sleep(5)' \
    "$SAVIA_EFFECT_LEDGER" "$BATS_TEST_TMPDIR/locked" >/dev/null 2>&1 </dev/null &
  lp=$!
  for _ in $(seq 50); do [[ -f "$BATS_TEST_TMPDIR/locked" ]] && break; sleep 0.1; done
  SAVIA_EFFECT_BUSY_MS=200 run se493_prepare 304 "$SE493_HEAD_A" squash
  kill "$lp" 2>/dev/null || true
  [ "$status" -eq 2 ]; [[ "$output" != *PROCEED* ]]; [[ "$output" == *"bloquead"* ]]
}

@test "AC-l: directorio sin escritura → 2" {
  d="$BATS_TEST_TMPDIR/ro"; mkdir -p "$d"; chmod 500 "$d"
  SAVIA_EFFECT_LEDGER="$d/sub/ledger.db" run se493_prepare 305 "$SE493_HEAD_A" squash
  chmod 700 "$d"
  [ "$status" -eq 2 ]; [[ "$output" == *"sin escritura"* ]]
}

@test "AC-l: WAL + synchronous FULL; si se fuerza NORMAL → 2 sin escribir (Regla 1)" {
  se493_prepare 306 "$SE493_HEAD_A" squash >/dev/null
  jm=$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("pragma journal_mode").fetchone()[0])' "$SAVIA_EFFECT_LEDGER")
  [ "$jm" = wal ]
  SAVIA_EFFECT_FAULT=pragma_normal run se493_prepare 307 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]
  [ "$(rows)" -eq 1 ]
}

@test "AC-l: registro con op non_idempotent sin sonda previa → cualquier orden sale con 2" {
  reg="$BATS_TEST_TMPDIR/ops.json"
  python3 -I - "$REPO_DIR/scripts/effect-ops.json" "$reg" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1])); r["ops"]["pr.merge"]["pre_probe"] = False; json.dump(r, open(sys.argv[2], "w"))
EOF
  export SAVIA_EFFECT_REGISTRY="$reg"
  run se493_prepare 308 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]
  run led reconcile "$SE493_REPO#308"
  [ "$status" -eq 2 ]
  run led status --open
  [ "$status" -eq 2 ]
  [ "$(rows)" -eq 0 ]
}

@test "AC-l: sin SAVIA_EFFECT_TEST=1, SAVIA_EFFECT_LEDGER se ignora con aviso y se usa el de \$HOME" {
  unset SAVIA_EFFECT_TEST
  run se493_prepare 309 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAVIA_EFFECT_LEDGER ignorado"* ]]
  [ ! -f "$SAVIA_EFFECT_LEDGER" ]
  [ "$(rows "$HOME/.savia/effects/ledger.db")" -eq 1 ]
}

# ── AC-m — ganchos de prueba inertes ─────────────────────────────────────

full_flow() {  # prepare → dispatch → complete; imprime el estado final
  local n="$1" out e t
  out=$(se493_prepare "$n" "$SE493_HEAD_A" squash 2>/dev/null) || return 1
  read -r _ e t <<<"$out"
  led dispatch "$e" --claim "$t" >/dev/null 2>&1 || return 1
  led complete "$e" --claim "$t" --response '{"mergeCommit":"cccccccccccccccccccccccccccccccccccccccc"}' >/dev/null 2>&1 || return 1
  led status "$SE493_REPO#$n" 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["state"])'
}

@test "AC-m: sin SAVIA_EFFECT_TEST, FAULT y NOW se ignoran con aviso y el flujo termina SUCCEEDED" {
  unset SAVIA_EFFECT_TEST SAVIA_EFFECT_LEDGER
  export SAVIA_EFFECT_FAULT=after_prepare SAVIA_EFFECT_NOW=1
  run se493_prepare 401 "$SE493_HEAD_A" squash
  [ "$status" -eq 0 ]; [[ "$output" == *"ganchos de prueba ignorados"* ]]
  run full_flow 402
  [ "$status" -eq 0 ]; [ "$output" = SUCCEEDED ]
  ca=$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select min(created_at) from effects").fetchone()[0])' "$HOME/.savia/effects/ledger.db")
  [ "$ca" -gt 1000000000 ]                  # reloj real, no SAVIA_EFFECT_NOW=1
}

@test "AC-m: con SAVIA_EFFECT_TEST=1 y el ledger fuera de \${TMPDIR:-/tmp}, igual" {
  export SAVIA_EFFECT_LEDGER="$BATS_TEST_TMPDIR/fuera/ledger.db"
  export TMPDIR="$BATS_TEST_TMPDIR/otro-tmp"; mkdir -p "$TMPDIR"
  export SAVIA_EFFECT_FAULT=after_prepare SAVIA_EFFECT_NOW=1
  run full_flow 403
  [ "$status" -eq 0 ]; [ "$output" = SUCCEEDED ]
}

@test "AC-m: con SAVIA_EFFECT_TEST=1 y un enlace bajo TMPDIR que resuelve al ledger por defecto, igual" {
  mkdir -p "$HOME/.savia/effects" "$BATS_TEST_TMPDIR/ln"
  ln -s "$HOME/.savia/effects/ledger.db" "$BATS_TEST_TMPDIR/ln/ledger.db"
  export SAVIA_EFFECT_LEDGER="$BATS_TEST_TMPDIR/ln/ledger.db"
  export SAVIA_EFFECT_FAULT=after_prepare SAVIA_EFFECT_NOW=1
  run full_flow 404
  [ "$status" -eq 0 ]; [ "$output" = SUCCEEDED ]
}

@test "AC-m: control positivo — con las dos condiciones, el mismo FAULT mata el proceso" {
  export SAVIA_EFFECT_FAULT=after_prepare
  run se493_prepare 405 "$SE493_HEAD_A" squash
  [ "$status" -eq 137 ]
}

# ── AC-n — validación de entradas (Regla 8) ──────────────────────────────

@test "AC-n: entradas inválidas → 2 sin escribir ni llamar al remoto; válidas → 0" {
  bad=(
    "--number;12; DROP" "--repo;-R--foo/x" "--repo;x/-y" "--repo;../.." "--repo;./x" "--repo;x/.." "--repo;a/b/c"
    "--head;${SE493_HEAD_A:0:39}" "--head;AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "--method;fast-forward"
  )
  se493_holder
  for b in "${bad[@]}"; do
    flag="${b%%;*}"; val="${b#*;}"
    declare -A a=([--repo]="$SE493_REPO" [--number]=501 [--head]="$SE493_HEAD_A" [--method]=squash)
    a[$flag]="$val"
    run led prepare pr.merge --repo "${a[--repo]}" --number "${a[--number]}" --head "${a[--head]}" --method "${a[--method]}" --holder-pid "$HOLDER"
    [ "$status" -eq 2 ] || { echo "no rechazó $b"; false; }
  done
  [ "$(rows)" -eq 0 ]
  [ "$(views)" -eq 0 ]
  run led reconcile "../..#1"
  [ "$status" -eq 2 ]
  run led prepare pr.merge --repo "$SE493_REPO" --number 501 --head "$SE493_HEAD_A" --method squash --holder-pid "$HOLDER"
  [ "$status" -eq 0 ]
}

@test "AC-n: sin identidad remota (falla o vacía) → 2 sin reclamar" {
  echo 1 > "$STUB/user.rc"
  run se493_prepare 502 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]; [[ "$output" == *"sin identidad remota"* ]]
  echo 0 > "$STUB/user.rc"   # sale con 0 sin imprimir nada: identidad vacía
  run se493_prepare 502 "$SE493_HEAD_A" squash
  [ "$status" -eq 2 ]; [[ "$output" == *"sin identidad remota"* ]]
  [ "$(rows)" -eq 0 ]
}

# ── Guard mínimo: solo pr.merge en los contratos F5 heredados ────────────

@test "guard: f5-state.sh rechaza una op distinta de pr.merge con 2 sin crear reserva; pr.merge sigue igual" {
  export SAVIA_RESERVATIONS="$BATS_TEST_TMPDIR/resv"
  run bash "$REPO_DIR/scripts/f5-state.sh" reserve deploy.prod 7
  [ "$status" -eq 2 ]; [[ "$output" == *"no admitida"* ]]
  [ ! -e "$SAVIA_RESERVATIONS" ]
  run bash "$REPO_DIR/scripts/f5-state.sh" reserve pr.merge 7
  [ "$status" -eq 0 ]
}
