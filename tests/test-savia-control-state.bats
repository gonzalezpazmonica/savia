#!/usr/bin/env bats
# SE-498 F0 — estado del plano de control: fail-closed, motivo obligatorio, estado perdido.
# AC-7, AC-12, AC-14 y AC-15. Cada test usa su repo temporal y su SAVIA_CONTROL_DIR.

load fixtures/savia-control/setup

setup() { setup_control; }

marker() { echo "$(git -C "$R" rev-parse --absolute-git-dir)/savia-control/installed"; }

# ── AC-12: motivo obligatorio ───────────────────────────────────────────────

@test "AC-12: pause, revoke y quarantine sin motivo válido salen 2 y no tocan state.json" {
  sc pause --scope executor:z --reason base
  before=$(state_sha)
  big=$(head -c 501 /dev/zero | tr '\0' x)
  for op in "pause" "revoke" "quarantine w"; do
    run sc $op --reason ""; [ "$status" -eq 2 ]
    run sc $op --reason "   "; [ "$status" -eq 2 ]
    run sc $op; [ "$status" -eq 2 ]
    run sc $op --reason "$big"; [ "$status" -eq 2 ]
    [[ "$output" == *REASON_INVALID* ]]
  done
  [ "$(state_sha)" = "$before" ]
}

@test "AC-12: límite exacto, 500 bytes pasa y 501 no (también en multibyte)" {
  r500=$(head -c 500 /dev/zero | tr '\0' x)
  run sc pause --reason "$r500"; [ "$status" -eq 0 ]
  # 250 «ñ» son 500 bytes; 251 son 502
  m500=$(python3 -c 'print("ñ"*250)'); m502=$(python3 -c 'print("ñ"*251)')
  run sc quarantine w --reason "$m500"; [ "$status" -eq 0 ]
  run sc quarantine v --reason "$m502"; [ "$status" -eq 2 ]
}

# ── AC-7: fail-closed ───────────────────────────────────────────────────────

@test "AC-7: state.json corrupto, vacío o ausente con diario → check 6; status no sale 2 e informa" {
  sc pause --scope executor:a --reason x
  cp "$SAVIA_CONTROL_DIR/state.json" "$T/ok.json"
  for variant in corrupt empty absent; do
    case $variant in
      corrupt) printf '{"version":1,' > "$SAVIA_CONTROL_DIR/state.json"; label=UNREADABLE_STATE ;;
      empty) : > "$SAVIA_CONTROL_DIR/state.json"; label=UNREADABLE_STATE ;;
      absent) rm -f "$SAVIA_CONTROL_DIR/state.json"; label=LOST_STATE ;;
    esac
    run sc check --executor b
    [ "$status" -eq 6 ]; [[ "$output" == *REVOKED* ]]
    run sc status
    [ "$status" -ne 2 ]; [[ "$output" == *"$label stop_seq=2"* ]]
    cp "$T/ok.json" "$SAVIA_CONTROL_DIR/state.json"
  done
}

@test "AC-7: un campo desconocido en state.json es estado ilegible (REVOKED)" {
  sc pause --scope executor:a --reason x
  python3 - "$SAVIA_CONTROL_DIR/state.json" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["mode"]="RUNNING"; json.dump(d,open(p,"w"))
EOF
  run sc check --executor b; [ "$status" -eq 6 ]
}

@test "AC-7: version mayor → check 6, status 0/3 (nunca 6 ni 2), pause y reconcile 2 sin tocar el fichero" {
  sc pause --scope executor:a --reason x
  printf '{"version":2,"epoch":0,"stop_seq":1,"stops":{},"nuevo":true}' > "$SAVIA_CONTROL_DIR/state.json"
  before=$(state_sha)
  run sc check --executor b
  [ "$status" -eq 6 ]; [[ "$output" == *UNSUPPORTED_STATE_VERSION* ]]
  run sc status
  [[ "$output" == *UNSUPPORTED_STATE_VERSION* ]]
  [ "$status" -eq 0 ] || [ "$status" -eq 3 ]
  run sc pause --reason y; [ "$status" -eq 2 ]
  run sc reconcile; [ "$status" -eq 2 ]
  [ "$(state_sha)" = "$before" ]
}

@test "AC-7: REVOCATION_EPOCH no entero o de diez cifras en origin/main → epoch y check salen 2" {
  for bad in '3; rm' '1e3' '  ' '1234567890' '-1'; do
    origin_put config/control/REVOCATION_EPOCH "$bad"
    run sc epoch; [ "$status" -eq 2 ]
    run sc check --executor a; [ "$status" -eq 2 ]
  done
}

@test "AC-7: caso límite, nueve cifras pasa" {
  origin_put config/control/REVOCATION_EPOCH "$(printf '999999999\n')"
  run sc epoch; [ "$status" -eq 0 ]; [ "${lines[0]}" = 999999999 ]
}

@test "AC-7: instalación nueva → check 0 con la época de origin/main (5)" {
  origin_put config/control/REVOCATION_EPOCH 5
  run sc check --executor a; [ "$status" -eq 0 ]
  run sc epoch; [ "$status" -eq 0 ]; [ "${lines[0]}" = 5 ]
  [ ! -e "$(marker)" ]   # las órdenes de solo lectura no crean la marca
}

@test "AC-7: ausencias de origin/main en tres pasos" {
  # 1) sin remoto origin: época local, exit 0 y aviso
  sc revoke --reason x
  git -C "$R" remote remove origin
  run sc epoch; [ "$status" -eq 0 ]; [ "${lines[0]}" = 1 ]; [[ "$output" == *ORIGIN_MAIN_MISSING* ]]
  # 2) origin/main sin el fichero: vale 0 y sin aviso
  git -C "$R" remote add origin "$ORIGIN"; git -C "$R" fetch -q origin
  run sc epoch; [ "$status" -eq 0 ]; [[ "$output" != *ORIGIN_MAIN_MISSING* ]]
  # 3) presente y no entero: 2
  origin_put config/control/REVOCATION_EPOCH 'x'
  run sc epoch; [ "$status" -eq 2 ]
}

@test "AC-7: REVOCATION_EPOCH que no es un fichero regular en origin/main → 2" {
  mkdir -p "$R/config/control"; ln -s /etc/hostname "$R/config/control/REVOCATION_EPOCH"
  git -C "$R" add -A && git -C "$R" commit -qm link && git -C "$R" push -q origin main && git -C "$R" fetch -q origin
  run sc epoch; [ "$status" -eq 2 ]
}

@test "AC-7: copia del script fuera de un checkout de git → check, pause y status salen 2 sin escribir" {
  mkdir -p "$T/suelto"; cp "$R/scripts/savia-control.py" "$T/suelto/"
  export SAVIA_CONTROL_DIR="$T/suelto-ctl"
  for cmd in "check --executor a" "pause --reason x" "status"; do
    run python3 -I "$T/suelto/savia-control.py" $cmd
    [ "$status" -eq 2 ]; [[ "$output" == *MARK_UNRESOLVABLE* ]]
  done
  [ ! -e "$T/suelto-ctl" ]
}

# ── AC-14: estado perdido no deshace la revocación ──────────────────────────

@test "AC-14: revoke y borrado de state.json + diario → check 6, epoch 1, grant de época 0 denegado" {
  sc revoke --reason x
  rm -f "$SAVIA_CONTROL_DIR/state.json" "$SAVIA_CONTROL_DIR/control.jsonl"
  run sc check --executor a; [ "$status" -eq 6 ]; [[ "$output" == *REVOKED* ]]
  run sc epoch; [ "${lines[0]}" = 1 ]
  # la parada global da 6 antes de mirar la época: se levanta por la vía aprobada para probar la época sola
  operator_setup; sc reconcile; approve global 1 2
  run sc resume --via-pr; [ "$status" -eq 0 ]
  run sc check --executor a --issued-epoch 0; [ "$status" -eq 8 ]; [[ "$output" == *STALE_EPOCH* ]]
  run sc check --executor a --issued-epoch 1; [ "$status" -eq 0 ]
}

@test "AC-14: borrar todo SAVIA_CONTROL_DIR tampoco la deshace" {
  sc revoke --reason x
  rm -rf "$SAVIA_CONTROL_DIR"
  run sc check --executor a; [ "$status" -eq 6 ]
  run sc epoch; [ "${lines[0]}" = 1 ]
}

@test "AC-14: con marca, SAVIA_CONTROL_DIR distinto → check, pause y revoke salen 2 y no crean nada" {
  sc revoke --reason x
  mkdir -p "$T/otro"
  export SAVIA_CONTROL_DIR="$T/otro"
  run sc check --executor a; [ "$status" -eq 2 ]; [[ "$output" == *CONTROL_DIR_MISMATCH* ]]
  run sc pause --reason y; [ "$status" -eq 2 ]
  run sc revoke --reason y; [ "$status" -eq 2 ]
  [ -z "$(ls -A "$T/otro")" ]
}

@test "AC-14: la marca se resuelve desde el script, no desde el cwd (repo ajeno recién creado)" {
  sc revoke --reason x
  rm -f "$SAVIA_CONTROL_DIR/state.json" "$SAVIA_CONTROL_DIR/control.jsonl"
  mkdir -p "$T/ajeno"; git init -q "$T/ajeno"
  cd "$T/ajeno"
  run sc check --executor a; [ "$status" -eq 6 ]
  run sc epoch; [ "${lines[0]}" = 1 ]
  mkdir -p "$T/otro2"
  SAVIA_CONTROL_DIR="$T/otro2" run sc pause --reason y; [ "$status" -eq 2 ]
  [ -z "$(ls -A "$T/otro2")" ]
}

@test "AC-14 negativo: el mismo borrado sin marca previa es instalación nueva (check 0)" {
  sc revoke --reason x
  rm -rf "$SAVIA_CONTROL_DIR" "$(dirname "$(marker)")"
  run sc check --executor a; [ "$status" -eq 0 ]
}

# ── AC-15: salida del estado perdido ────────────────────────────────────────

lose_after_revoke() {  # deja S y E en variables y borra estado y diario (marca presente)
  sc pause --scope executor:a --reason uno
  sc revoke --reason dos
  S=$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stop_seq"]'); E=$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["epoch"]')
  rm -f "$SAVIA_CONTROL_DIR/state.json" "$SAVIA_CONTROL_DIR/control.jsonl"
}

@test "AC-15: LOST_STATE con S+1, reconcile lo materializa y resume por PR procede" {
  operator_setup
  lose_after_revoke
  run sc status; [[ "$output" == *"LOST_STATE stop_seq=$((S + 1))"* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
  approve global "$E" $((S + 1))
  run sc resume --via-pr; [ "$status" -eq 5 ]; [[ "$output" == *RECONCILE_REQUIRED* ]]
  run grep -q "$APPROVAL_BLOB" "$(marker)"; [ "$status" -ne 0 ]
  run sc reconcile; [ "$status" -eq 0 ]
  [ "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stops"]["global"]["stop_seq"]')" = $((S + 1)) ]
  [ "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stops"]["global"]["mode"]')" = REVOKED ]
  grep -q '"op":"LOST_STATE"' "$SAVIA_CONTROL_DIR/control.jsonl"
  run sc status; [[ "$output" == *"STOP global REVOKED stop_seq=$((S + 1))"* ]]
  run sc resume --via-pr; echo "$output"; [ "$status" -eq 0 ]
  run sc check --executor b; [ "$status" -eq 0 ]
  run sc epoch; [ "${lines[0]}" = "$E" ]
  grep -q "$APPROVAL_BLOB" "$(marker)"
  # executor:a seguía parado antes del revoke, pero esa entrada se perdió con el estado: solo queda global
  run sc check --executor a; [ "$status" -eq 0 ]
}

@test "AC-15 negativos: aprobación con S, con época E-1 o ausente → 4" {
  operator_setup
  lose_after_revoke
  sc reconcile
  approve global "$E" "$S"
  run sc resume --via-pr; [ "$status" -eq 4 ]
  approve global $((E - 1)) $((S + 1))
  run sc resume --via-pr; [ "$status" -eq 4 ]
  run sc resume < /dev/null; [ "$status" -eq 4 ]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "AC-15: con state.json corrupto, la secuencia procede y el corrupto queda apartado" {
  operator_setup
  sc revoke --reason x
  S=$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stop_seq"]'); E=$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["epoch"]')
  printf 'basura' > "$SAVIA_CONTROL_DIR/state.json"
  run sc status; [[ "$output" == *"UNREADABLE_STATE stop_seq=$((S + 1))"* ]]
  run sc reconcile; [ "$status" -eq 0 ]
  ls "$SAVIA_CONTROL_DIR"/state.json.unreadable-* >/dev/null
  [ "$(cat "$SAVIA_CONTROL_DIR"/state.json.unreadable-*)" = basura ]
  approve global "$E" $((S + 1))
  run sc resume --via-pr; [ "$status" -eq 0 ]
  run sc check --executor a; [ "$status" -eq 0 ]
}

@test "R1: estado válido sin diario → JOURNAL_MISSING y la siguiente orden crea un diario que cita el estado" {
  sc pause --scope executor:a --reason x
  rm -f "$SAVIA_CONTROL_DIR/control.jsonl"
  run sc check --executor a; [ "$status" -eq 6 ]
  run sc status; [[ "$output" == *JOURNAL_MISSING* ]]
  sha=$(state_sha)
  sc pause --scope executor:b --reason y
  head -1 "$SAVIA_CONTROL_DIR/control.jsonl" | grep -q "\"state_sha256\":\"$sha\""
}

@test "R1: un diario con la cadena rota es fuente ilegible (check 2)" {
  sc pause --scope executor:a --reason x
  sc pause --scope executor:b --reason y
  sed -i '1s/"reason":"x"/"reason":"z"/' "$SAVIA_CONTROL_DIR/control.jsonl"
  run sc check --executor c; [ "$status" -eq 2 ]; [[ "$output" == *JOURNAL_UNREADABLE* ]]
}

@test "R1: bajar la época en state.json no baja la efectiva (diario y marca mandan)" {
  sc revoke --reason x; sc revoke --reason y
  python3 - "$SAVIA_CONTROL_DIR/state.json" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["epoch"]=0; d["stops"]={}; json.dump(d,open(p,"w"))
EOF
  # sin paradas en el estado, check llega a comparar la época: la efectiva sigue en 2
  run sc epoch; [ "${lines[0]}" = 2 ]
  run sc check --executor a --issued-epoch 0; [ "$status" -eq 8 ]; [[ "$output" == *STALE_EPOCH* ]]
  run sc check --executor a --issued-epoch 2; [ "$status" -eq 0 ]
}

# ── revisión #1593: tipos y diario truncado ─────────────────────────────────

@test "R1 tipos: state.json con tipos incorrectos es UNREADABLE_STATE (check 6, status sin traceback)" {
  sc pause --scope executor:a --reason x
  cp "$SAVIA_CONTROL_DIR/state.json" "$T/ok.json"
  for mut in 'd["version"]=True' 'd["epoch"]=False' 'd["stops"]["executor:a"]["actor"]="yo"' \
             'd["stops"]["executor:a"]["stop_seq"]=True' 'd["stops"]["executor:a"]["since"]=1' \
             'd["stops"]["executor:a"]["reason"]=None' 'd["stops"]["executor:a"]["mode"]=["PAUSED"]'; do
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); exec(sys.argv[2]); json.dump(d,open(sys.argv[3],"w"))' \
      "$T/ok.json" "$mut" "$SAVIA_CONTROL_DIR/state.json"
    run sc check --executor b; echo "$mut → $output"; [ "$status" -eq 6 ]; [[ "$output" == *UNREADABLE_STATE* ]]
    run sc status; [ "$status" -eq 0 ]; [[ "$output" == *UNREADABLE_STATE* ]]; [[ "$output" != *Traceback* ]]
  done
  cp "$T/ok.json" "$SAVIA_CONTROL_DIR/state.json"
  run sc check --executor b; [ "$status" -eq 0 ]
}

@test "R1 tipos: un registro del diario con epoch o stop_seq no enteros y cadena válida → check 2 JOURNAL_UNREADABLE" {
  sc pause --scope executor:a --reason x
  sc pause --scope executor:b --reason y
  J="$SAVIA_CONTROL_DIR/control.jsonl"; cp "$J" "$T/ok.jsonl"
  # solo se toca la última línea: ninguna posterior cita su hash, así que la cadena sigue válida
  for mut in 'r["epoch"]="1"' 'r["stop_seq"]=True' 'r["epoch"]=-1'; do
    python3 -c 'import json,sys; L=open(sys.argv[1]).read().splitlines(); r=json.loads(L[-1]); exec(sys.argv[2]); L[-1]=json.dumps(r,sort_keys=True,separators=(",",":")); open(sys.argv[3],"w").write("\n".join(L)+"\n")' \
      "$T/ok.jsonl" "$mut" "$J"
    run sc check --executor c; echo "$mut → $output"; [ "$status" -eq 2 ]; [[ "$output" == *JOURNAL_UNREADABLE* ]]
  done
  # control: reescribir la última línea sin cambiar tipos mantiene el diario legible
  python3 -c 'import json,sys; L=open(sys.argv[1]).read().splitlines(); r=json.loads(L[-1]); L[-1]=json.dumps(r,sort_keys=True,separators=(",",":")); open(sys.argv[2],"w").write("\n".join(L)+"\n")' "$T/ok.jsonl" "$J"
  run sc check --executor c; [ "$status" -eq 0 ]
}

@test "R1 diario: una última línea sin \\n (append interrumpido) no deja sin freno; se aparta al escribir" {
  sc pause --scope executor:a --reason x
  J="$SAVIA_CONTROL_DIR/control.jsonl"
  printf '{"op":"pause","sco' >> "$J"
  run sc check --executor a; [ "$status" -eq 6 ]
  run sc check --executor b; [ "$status" -eq 0 ]
  run sc status; [[ "$output" == *JOURNAL_TRUNCATED_TAIL* ]]
  run sc pause --scope executor:b --reason y; [ "$status" -eq 0 ]
  [ "$(cat "$SAVIA_CONTROL_DIR"/control.jsonl.truncated-*)" = '{"op":"pause","sco' ]
  run sc status; [[ "$output" != *JOURNAL_TRUNCATED_TAIL* ]]
  run sc check --executor b; [ "$status" -eq 6 ]
  [ "$(wc -l < "$J")" -eq 2 ]
}

@test "R1 diario negativo: la misma línea rota CON \\n final, o en mitad del diario, sigue siendo exit 2" {
  sc pause --scope executor:a --reason x
  J="$SAVIA_CONTROL_DIR/control.jsonl"; cp "$J" "$T/ok.jsonl"
  printf '{"op":"pause","sco\n' >> "$J"
  run sc check --executor b; [ "$status" -eq 2 ]; [[ "$output" == *JOURNAL_UNREADABLE* ]]
  run sc pause --scope executor:b --reason y; [ "$status" -eq 2 ]
  { printf '{"op":"pause","sco\n'; cat "$T/ok.jsonl"; } > "$J"
  run sc check --executor b; [ "$status" -eq 2 ]
}

@test "R4: SAVIA_CONTROL_ACK_TIMEOUT_S no numérico no rompe la parada: avisa, usa 10 s y propaga" {
  register a
  SAVIA_CONTROL_ACK_TIMEOUT_S=abc run sc pause --reason x
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *ACK_TIMEOUT_INVALID* ]]; [[ "$output" != *Traceback* ]]
  grep -q '^halt' "$T/adapter-a.log"
  SAVIA_CONTROL_ACK_TIMEOUT_S=-1 run sc status; [[ "$output" == *ACK_TIMEOUT_INVALID* ]]; [[ "$output" != *Traceback* ]]
  SAVIA_CONTROL_ACK_TIMEOUT_S=5 run sc status; [[ "$output" != *ACK_TIMEOUT_INVALID* ]]
}
