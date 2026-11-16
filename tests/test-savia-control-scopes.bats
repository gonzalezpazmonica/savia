#!/usr/bin/env bats
# SE-498 F0 — ámbitos del estado (AC-9): ejecutor, principal, contrato, cuarentena y mezcla.

load fixtures/savia-control/setup

setup() { setup_control; }

@test "AC-9: pause --scope executor:a frena a a y no a b" {
  register a b
  run sc pause --scope executor:a --reason x; [ "$status" -eq 0 ]
  run sc check --executor a; [ "$status" -eq 6 ]; [[ "$output" == *"PAUSED por executor:a"* ]]
  run sc check --executor b; [ "$status" -eq 0 ]
  grep -q '^halt 0 PAUSED x$' "$T/adapter-a.log"
  [ ! -e "$T/adapter-b.log" ]
}

@test "AC-9: resume --scope executor:a con revoke global vigente sale 9 y no cambia nada" {
  sc pause --scope executor:a --reason x
  sc revoke --reason y
  before=$(state_sha)
  run sc resume --scope executor:a --via-pr
  [ "$status" -eq 9 ]; [[ "$output" == *"STILL_COVERED_BY global"* ]]
  [ "$(state_sha)" = "$before" ]
}

@test "AC-9: principal:x solo frena efectos de x; ningún halt; status 0 con EFFECT_SCOPED_STOPS" {
  register a b
  run sc pause --scope principal:x --reason x; [ "$status" -eq 0 ]
  [ ! -e "$T/adapter-a.log" ]
  [ ! -e "$T/adapter-b.log" ]
  run sc check --executor a; [ "$status" -eq 0 ]
  run sc check --executor a --principal x; [ "$status" -eq 6 ]; [[ "$output" == *PAUSED* ]]
  run sc check --executor a --principal y; [ "$status" -eq 0 ]
  run sc status; echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EFFECT_SCOPED_STOPS principal:x PAUSED"* ]]
  [[ "$output" == *"EXECUTOR a esperado=RUNNING nativo=RUNNING"* ]]
}

@test "AC-9: lo mismo con contract:" {
  register a
  sc pause --scope contract:k1 --reason x
  [ ! -e "$T/adapter-a.log" ]
  run sc check --executor a; [ "$status" -eq 0 ]
  run sc check --executor a --contract k1; [ "$status" -eq 6 ]
  run sc check --executor a --contract k2; [ "$status" -eq 0 ]
  run sc status; [ "$status" -eq 0 ]; [[ "$output" == *"EFFECT_SCOPED_STOPS contract:k1"* ]]
}

@test "AC-9 mutación: status compara el nativo con el modo de ejecutor, no con el de efecto" {
  # Con un adaptador que ya está STOPPED por su cuenta, un status que esperase el modo de
  # efecto (PAUSED por principal:x) daría 0; el de ejecutor es RUNNING y da 3 RESUME_INCOMPLETE.
  register a
  sc pause --scope principal:x --reason x
  echo STOPPED > "$T/native-a"
  run sc status; [ "$status" -eq 3 ]; [[ "$output" == *"RESUME_INCOMPLETE a"* ]]
}

@test "AC-9: quarantine con dos posicionales o sin ninguno sale 2" {
  run sc quarantine a b --reason x; [ "$status" -eq 2 ]
  run sc quarantine --reason x; [ "$status" -eq 2 ]
  [ ! -e "$SAVIA_CONTROL_DIR/state.json" ]
}

@test "AC-9: revoke --scope sale 2 y ni la época ni state.json cambian" {
  sc pause --scope executor:z --reason x
  before=$(state_sha)
  run sc revoke --scope executor:a --reason x; [ "$status" -eq 2 ]
  [ "$(state_sha)" = "$before" ]
  run sc epoch; [ "${lines[0]}" = 0 ]
}

@test "AC-9: quarantine a frena a a, no cambia la época y deja válidos los grants de b" {
  sc revoke --reason base   # época 1, para que un grant de b tenga época distinta de 0
  E=$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["epoch"]')
  # se levanta global para probar quarantine solo
  operator_setup; sc reconcile; approve global "$E" "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stops"]["global"]["stop_seq"]')"
  sc resume --via-pr
  run sc quarantine a --reason x; [ "$status" -eq 0 ]
  run sc check --executor a; [ "$status" -eq 6 ]; [[ "$output" == *QUARANTINED* ]]
  run sc epoch; [ "${lines[0]}" = "$E" ]
  run sc check --executor b --issued-epoch "$E"; [ "$status" -eq 0 ]
}

@test "AC-9: mezcla pause executor:a + quarantine b; resume de a deja b en cuarentena; revoke para a los tres" {
  register a b c
  operator_setup
  sc pause --scope executor:a --reason x
  sc quarantine b --reason y
  run sc check --executor a; [ "$status" -eq 6 ]; [[ "$output" == *"PAUSED"* ]]
  run sc check --executor b; [ "$status" -eq 6 ]; [[ "$output" == *"QUARANTINED"* ]]
  run sc check --executor c; [ "$status" -eq 0 ]
  run sc status; echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" == *"EXECUTOR a esperado=PAUSED nativo=STOPPED"* ]]
  [[ "$output" == *"EXECUTOR b esperado=QUARANTINED nativo=STOPPED"* ]]
  [[ "$output" == *"EXECUTOR c esperado=RUNNING nativo=RUNNING"* ]]
  sc reconcile --scope executor:a
  approve executor:a 0 1
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 0 ]
  grep -q '^resume 0$' "$T/adapter-a.log"
  run sc check --executor a; [ "$status" -eq 0 ]
  run sc check --executor b; [ "$status" -eq 6 ]; [[ "$output" == *QUARANTINED* ]]
  sc revoke --reason z
  for e in a b c; do
    run sc check --executor $e; [ "$status" -eq 6 ]; [[ "$output" == *REVOKED* ]]
  done
}

@test "AC-9: ids fuera de la expresión salen 2 y state.json no cambia" {
  sc pause --scope executor:z --reason x
  before=$(state_sha)
  for s in 'executor:../x' 'principal:a b' 'contract:' 'otro:x' 'executor:a:b'; do
    run sc pause --scope "$s" --reason x; [ "$status" -eq 2 ]
  done
  run sc quarantine '../x' --reason x; [ "$status" -eq 2 ]
  run sc check --executor 'a b'; [ "$status" -eq 2 ]
  [ "$(state_sha)" = "$before" ]
}

@test "R1: una parada nueva sobre un ámbito con entrada la renueva al modo más restrictivo" {
  sc quarantine a --reason x
  sc pause --scope executor:a --reason y
  [ "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stops"]["executor:a"]["mode"]')" = QUARANTINED ]
  [ "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stops"]["executor:a"]["stop_seq"]')" = 2 ]
}

@test "R4: adaptador roto → status 3 PROPAGATION_INCOMPLETE y lo nombra; el diario guarda los dos intentos" {
  register a b
  printf '#!/usr/bin/env bash\nexit 1\n' > "$T/adapters/b"
  sc pause --reason x
  run sc status; [ "$status" -eq 3 ]; [[ "$output" == *"PROPAGATION_INCOMPLETE b"* ]]
  grep '"executor":"b"' "$SAVIA_CONTROL_DIR/control.jsonl" | grep -q '"ok":false'
  [ "$(grep '"executor":"b"' "$SAVIA_CONTROL_DIR/control.jsonl" | python3 -c 'import json,sys; print(len(json.loads(sys.stdin.readline())["attempts"]))')" = 2 ]
}

@test "R4: un ejecutor marcado remoto en executors.json pero no en origin/main cuenta como local" {
  register a
  python3 - "$SAVIA_CONTROL_DIR/executors.json" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["a"]["remote"]=True; d["a"]["adapter"]="/nonexistent"; json.dump(d,open(p,"w"))
EOF
  sc pause --reason x
  run sc status; [ "$status" -eq 3 ]; [[ "$output" == *"PROPAGATION_INCOMPLETE a"* ]]
  origin_put config/control/executors-remote.json '["a"]'
  run sc status; [ "$status" -eq 0 ]; [[ "$output" == *"REMOTE_UNACKED a"* ]]
}

@test "R1: status informa REGISTRY_CHANGED si executors.json cambió desde la orden anterior" {
  register a
  sc pause --scope executor:a --reason x
  register a nuevo
  run sc status; [[ "$output" == *"REGISTRY_CHANGED +nuevo"* ]]
}
