#!/usr/bin/env bats
# SE-498 F0 — época de revocación monótona (AC-8): revoke sobre la efectiva, grants por época,
# publish-epoch de uno en uno y aviso EPOCH_CHECK_NOT_REQUIRED.

load fixtures/savia-control/setup

setup() { setup_control; }

lift_global() {  # reconcile + aprobación por PR + resume de la entrada global vigente
  operator_setup
  sc reconcile
  approve global "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["epoch"]')" \
    "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stops"]["global"]["stop_seq"]')"
  sc resume --via-pr
}

@test "AC-8: con época E, dos revoke dan E+1 y E+2" {
  run sc revoke --reason a; [ "$status" -eq 0 ]
  run sc epoch; [ "${lines[0]}" = 1 ]
  run sc revoke --reason b; [ "$status" -eq 0 ]
  run sc epoch; [ "${lines[0]}" = 2 ]
}

@test "AC-8: revoke sobre la efectiva, origin/main en 5 y local en 3 → 6; grant de época 5 sale 8" {
  sc revoke --reason a; sc revoke --reason b; sc revoke --reason c
  [ "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["epoch"]')" = 3 ]
  origin_put config/control/REVOCATION_EPOCH 5
  run sc epoch; [ "${lines[0]}" = 5 ]
  sc revoke --reason d
  [ "$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["epoch"]')" = 6 ]
  run sc epoch; [ "${lines[0]}" = 6 ]
  lift_global
  run sc check --executor m --issued-epoch 5; [ "$status" -eq 8 ]; [[ "$output" == *STALE_EPOCH* ]]
  run sc check --executor m --issued-epoch 6; [ "$status" -eq 0 ]
  run sc check --executor m --issued-epoch 7; [ "$status" -eq 8 ]; [[ "$output" == *FORGED_EPOCH* ]]
}

@test "AC-8: grant sin issued_epoch (vale 0) pasa con época 0 y se deniega con época 1" {
  run sc check --executor m --issued-epoch 0; [ "$status" -eq 0 ]
  sc revoke --reason a
  lift_global
  run sc check --executor m --issued-epoch 0; [ "$status" -eq 8 ]
  run sc check --executor m --issued-epoch 1; [ "$status" -eq 0 ]
}

@test "R4: con la entrada global en REVOKED, ni un grant de la época nueva pasa (modo antes que época)" {
  sc revoke --reason a
  run sc check --executor m --issued-epoch 1; [ "$status" -eq 6 ]
  run sc check --executor m --issued-epoch 0; [ "$status" -eq 6 ]
}

@test "AC-8: pause y quarantine no cambian la época" {
  sc pause --reason a; sc quarantine q --reason b
  run sc epoch; [ "${lines[0]}" = 0 ]
}

merge_epoch() {  # simula la fusión de la PR de publish-epoch: main recibe la rama y la PR deja de estar abierta
  git -C "$R" fetch -q origin "agent/control-epoch-$1"
  [ "$(git -C "$R" show "origin/agent/control-epoch-$1:config/control/REVOCATION_EPOCH")" = "$1" ]
  origin_put config/control/REVOCATION_EPOCH "$(printf '%s\n' "$1")"
  python3 - "$GH_STUB_DIR/prs.json" "agent/control-epoch-$1" <<'EOF'
import json,sys; p=sys.argv[1]; json.dump([x for x in json.load(open(p)) if x["headRefName"]!=sys.argv[2]],open(p,"w"))
EOF
}

@test "AC-8: publish-epoch publica de uno en uno y no duplica PR abiertas" {
  sc revoke --reason a; sc revoke --reason b
  run sc publish-epoch; echo "$output"; [ "$status" -eq 0 ]
  [ "$(cat "$GH_STUB_DIR/created")" = 1 ]
  # la rama publica main + 1 (=1), no la local (=2), y solo cambia REVOCATION_EPOCH
  [ "$(git -C "$ORIGIN" show agent/control-epoch-1:config/control/REVOCATION_EPOCH)" = 1 ]
  [ "$(git -C "$ORIGIN" diff --name-only main agent/control-epoch-1)" = config/control/REVOCATION_EPOCH ]
  run sc publish-epoch; [ "$status" -eq 0 ]; [[ "$output" == *ALREADY_OPEN* ]]
  [ "$(cat "$GH_STUB_DIR/created")" = 1 ]
  merge_epoch 1
  run sc publish-epoch; [ "$status" -eq 0 ]
  [ "$(cat "$GH_STUB_DIR/created")" = 2 ]
  [ "$(git -C "$ORIGIN" show agent/control-epoch-2:config/control/REVOCATION_EPOCH)" = 2 ]
  merge_epoch 2
  run sc publish-epoch; [ "$status" -eq 0 ]; [[ "$output" == *NOTHING_TO_PUBLISH* ]]
  [ "$(cat "$GH_STUB_DIR/created")" = 2 ]
}

@test "AC-8: publish-epoch cierra una PR de época que main ya alcanzó" {
  sc revoke --reason a; sc revoke --reason b
  echo '[{"number":7,"headRefName":"agent/control-epoch-1","url":"u7"}]' > "$GH_STUB_DIR/prs.json"
  origin_put config/control/REVOCATION_EPOCH 1
  run sc publish-epoch; [ "$status" -eq 0 ]
  grep -q '^pr close 7' "$GH_STUB_DIR/calls.log"
  [ "$(git -C "$ORIGIN" show agent/control-epoch-2:config/control/REVOCATION_EPOCH)" = 2 ]
}

@test "AC-8: sin revoke pendiente publish-epoch no abre nada" {
  run sc publish-epoch; [ "$status" -eq 0 ]; [[ "$output" == *NOTHING_TO_PUBLISH* ]]
  [ ! -e "$GH_STUB_DIR/created" ]
}

@test "AC-8: EPOCH_CHECK_NOT_REQUIRED sin el check obligatorio o si gh falla; sin aviso con él" {
  run sc epoch; [[ "$output" == *EPOCH_CHECK_NOT_REQUIRED* ]]
  gh_api repos_owner_repo_rules_branches_main '[{"type":"pull_request"}]'
  run sc epoch; [[ "$output" == *EPOCH_CHECK_NOT_REQUIRED* ]]
  gh_api repos_owner_repo_rules_branches_main \
    '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"control-epoch-monotonic"}]}}]'
  run sc epoch; [ "$status" -eq 0 ]; [[ "$output" != *EPOCH_CHECK_NOT_REQUIRED* ]]
  run sc status; [[ "$output" != *EPOCH_CHECK_NOT_REQUIRED* ]]
}
