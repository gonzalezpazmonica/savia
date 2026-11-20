#!/usr/bin/env bats
# Ref: SE-347 — lecciones PMA incorporadas (goals, messaging, dispatch, session-state)

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SAVIA_GOALS_DIR="$(mktemp -d)"
  export SAVIA_MSG_DIR="$(mktemp -d)"
  export SAVIA_DISPATCH_DIR="$(mktemp -d)"
  export SAVIA_SESSION_STATE_DIR="$(mktemp -d)"
}

teardown() {
  unset SAVIA_GOALS_DIR SAVIA_MSG_DIR SAVIA_DISPATCH_DIR SAVIA_SESSION_STATE_DIR
}

# ── savia-goals.sh ────────────────────────────────────────────────────────

@test "goals: create/progress/complete con único final válido" {
  id=$(bash "$ROOT_DIR/scripts/savia-goals.sh" create --title "tarea" --budget-tokens 100 --budget-seconds 60)
  [ -n "$id" ]
  bash "$ROOT_DIR/scripts/savia-goals.sh" progress "$id" --tokens 10 --seconds 5 >/dev/null
  bash "$ROOT_DIR/scripts/savia-goals.sh" get "$id" | grep -q '"tokens": *10'
  bash "$ROOT_DIR/scripts/savia-goals.sh" complete "$id" >/dev/null
  # progress sobre completado debe fallar (complete es único final válido)
  run bash "$ROOT_DIR/scripts/savia-goals.sh" progress "$id" --tokens 1
  [ "$status" -ne 0 ]
}

@test "goals: heartbeat claimed-due sin replay + coalescing" {
  bash "$ROOT_DIR/scripts/savia-goals.sh" heartbeat add --every 10 --prompt "p" --name h1 >/dev/null
  now=$(date +%s)
  # primer claim → 1 due
  [ "$(bash "$ROOT_DIR/scripts/savia-goals.sh" heartbeat claim-due --now "$now" | wc -l)" -eq 1 ]
  # re-claim en el mismo instante → 0 (sin replay tras crash)
  [ "$(bash "$ROOT_DIR/scripts/savia-goals.sh" heartbeat claim-due --now "$now" | wc -l)" -eq 0 ]
  # saltamos 20s (varios ticks perdidos) → 1 due (coalesce, no 2)
  [ "$(bash "$ROOT_DIR/scripts/savia-goals.sh" heartbeat claim-due --now "$((now + 20))" | wc -l)" -eq 1 ]
}

# ── agent-messaging.sh ────────────────────────────────────────────────────

@test "messaging: send/list/ack con receipts" {
  mid=$(bash "$ROOT_DIR/scripts/agent-messaging.sh" send --to dev --role child --message "revisa" --from orch)
  bash "$ROOT_DIR/scripts/agent-messaging.sh" list --inbox dev --unread | grep -q "revisa"
  bash "$ROOT_DIR/scripts/agent-messaging.sh" ack --id "$mid" --as dev >/dev/null
  run bash "$ROOT_DIR/scripts/agent-messaging.sh" status --id "$mid"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "status=read"
}

@test "messaging: broadcast a todas las inbox conocidas" {
  bash "$ROOT_DIR/scripts/agent-messaging.sh" send --to a --message "x" --from o >/dev/null 2>&1
  bash "$ROOT_DIR/scripts/agent-messaging.sh" send --to b --message "y" --from o >/dev/null 2>&1
  run bash "$ROOT_DIR/scripts/agent-messaging.sh" send --to all --broadcast --message "standup" --role steer
  [ "$status" -eq 0 ]
  [ "$(grep -c 'standup' "$SAVIA_MSG_DIR/inbox/a.jsonl")" -eq 1 ]
  [ "$(grep -c 'standup' "$SAVIA_MSG_DIR/inbox/b.jsonl")" -eq 1 ]
}

# ── parallel-dispatch.sh ──────────────────────────────────────────────────

@test "dispatch: launch devuelve handle inmediato y collect agrega" {
  run bash "$ROOT_DIR/scripts/parallel-dispatch.sh" launch --id j1 --dir /tmp --cmd "sleep 1; echo RESULTADO"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "handle inmediato"
  sleep 2
  run bash "$ROOT_DIR/scripts/parallel-dispatch.sh" collect --id j1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "RESULTADO"
}

@test "dispatch: job fallido queda marcado failed" {
  bash "$ROOT_DIR/scripts/parallel-dispatch.sh" launch --id jf --dir /tmp --cmd "exit 3" >/dev/null
  sleep 1
  run bash "$ROOT_DIR/scripts/parallel-dispatch.sh" status --all --quiet
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "jf failed"
}

# ── session-state-snapshot.sh ─────────────────────────────────────────────
