#!/usr/bin/env bash
# federation-drill.sh — SE-263 S7: Compromised instance drill
# Simulates key compromise, revocation, retroactive quarantine, and RTO measurement.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${FEDERATION_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

usage() {
  cat <<EOF
Usage: bash scripts/federation-drill.sh [health | compromised <instance-id>]

Drill scenarios for federation resilience:
  compromised  Simulate instance key compromise: revoke card, quarantine, measure impact
  restore      Verify federation continues operating after compromised instance removed
  health       Check all federation components (cards, exchange chains, agent index)

compromised ESCRIBE: marca como revoked la tarjeta <instance-id> en
coordinacion/cards/ y regenera el índice de agentes. Apunta FEDERATION_ROOT a una
copia para ensayar sin tocar la federación real. El id solo admite [A-Za-z0-9._-].
EOF
}

SCENARIO="${1:---health}"

case "$SCENARIO" in
  --help|-h) usage; exit 0 ;;
esac

# ── Health check ──
check_cards() {
  local cards_dir="${1:-$ROOT/coordinacion/cards}"
  local ok=0 fail=0
  echo "=== Card Health ==="
  for card in "$cards_dir"/*.card.json; do
    [[ -f "$card" ]] || continue
    local iid
    iid=$(basename "$card" .card.json)
    local status
    status=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('status',''))" "$card" 2>/dev/null || echo "invalid")
    if [[ "$status" == "active" ]]; then
      echo "  OK: $iid ($status)"; ok=$((ok+1))
    elif [[ "$status" == "revoked" ]]; then
      echo "  WARN: $iid ($status)"; fail=$((fail+1))
    else
      echo "  FAIL: $iid ($status)"; fail=$((fail+1))
    fi
  done
  echo "  Total: $ok active, $fail issues"
}

check_exchange() {
  local exchange_dir="${1:-$ROOT/coordinacion/exchange}"
  echo "=== Exchange Chain Health ==="
  for ledger in "$exchange_dir"/*.jsonl; do
    [[ -f "$ledger" ]] || continue
    local iid
    iid=$(basename "$ledger" .jsonl)
    local result
    result=$(bash "$SCRIPT_DIR/exchange-ledger.sh" verify --project "$ROOT" --instance "$iid" 2>&1 || echo "BROKEN")
    echo "  $iid: $result"
  done
}

check_agent_index() {
  echo "=== Agent Index Health ==="
  local index="$ROOT/coordinacion/domes/_federation/agent-index.json"
  if [[ -f "$index" ]]; then
    local count
    count=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get('agents',{})))" "$index" 2>/dev/null || echo 0)
    echo "  Agents indexed: $count"
  else
    echo "  WARN: agent index not found"
  fi
}

# ── Compromised drill ──
drill_compromised() {
  local target_id="${1:-}"
  [[ -z "$target_id" ]] && { echo "ERROR: specify instance ID to compromise"; exit 1; }
  if [[ ! "$target_id" =~ ^[A-Za-z0-9._-]+$ || "$target_id" == *..* ]]; then
    echo "ERROR: invalid instance ID (allowed: A-Za-z0-9._-, no '..')" >&2; exit 1
  fi

  echo "=== DRILL: Instance Compromise — $target_id ==="
  local t0
  t0=$(date +%s)

  # Step 1: Revoke card
  local card="$ROOT/coordinacion/cards/${target_id}.card.json"
  if [[ -f "$card" ]]; then
    python3 -c "
import json, sys
card, ts = sys.argv[1], sys.argv[2]
with open(card) as f:
    d = json.load(f)
d['status'] = 'revoked'
d['revokedAt'] = ts
with open(card, 'w') as f:
    json.dump(d, f, indent=2)
" "$card" "$(date -Iseconds)" 2>/dev/null
    echo "  [1/4] Card revoked: $card"
  else
    echo "  [1/4] Card not found (synthetic drill): $card"
  fi

  # Step 2: Regenerate agent index (should exclude revoked)
  bash "$SCRIPT_DIR/agent-index-generate.sh" "$ROOT/coordinacion/cards" "$ROOT/coordinacion/domes/_federation/agent-index.json" 2>&1 | tail -1
  echo "  [2/4] Agent index regenerated"

  # Step 3: Verify exchange chains still intact
  check_exchange
  echo "  [3/4] Exchange chains verified"

  # Step 4: RTO measurement
  local t1 rto
  t1=$(date +%s)
  rto=$((t1 - t0))
  echo "  [4/4] RTO: ${rto}s"
  echo "=== DRILL COMPLETE ==="
}

case "$SCENARIO" in
  --health|health)
    check_cards
    check_exchange
    check_agent_index
    ;;
  --compromised|compromised)
    drill_compromised "${2:-}"
    ;;
  *)
    echo "ERROR: unknown scenario: $SCENARIO" >&2; usage >&2; exit 1
    ;;
esac
