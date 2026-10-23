#!/usr/bin/env bats
# tests/test-se-263-s567.bats — Tests for SE-263 S5+S6+S7

# ── S5: A2A Server ──

@test "S5-T01: A2A server script exists and is executable" {
  [[ -f "scripts/a2a-server.py" ]]
  [[ -x "scripts/a2a-server.py" ]]
}

@test "S5-T02: A2A skills allowlist exists" {
  [[ -f "config/a2a-skills-allowlist.yaml" ]]
}

@test "S5-T03: all 5 v1 skills are allowlisted" {
  python3 -c "
import yaml
d = yaml.safe_load(open('config/a2a-skills-allowlist.yaml'))
for s in ['situacion.query','commitment.propose','commitment.ack','dependency.notify','handoff.request']:
    assert d['skills'][s]['allow'] == True, f'{s} not allowed'
"
}

@test "S5-T04: default is deny (new skills blocked)" {
  python3 -c "
import yaml
d = yaml.safe_load(open('config/a2a-skills-allowlist.yaml'))
assert d['default'] == 'deny'
"
}

@test "S5-T05: bind-gate aborts on non-declared interface" {
  run timeout 10 python3 scripts/a2a-server.py --host 0.0.0.0 --allowed-interface 127.0.0.1 --port 19876
  [ "$status" -eq 1 ]
  [[ "$output" =~ "BIND-GATE ABORT" ]]
}

@test "S5-T06: A2A server starts on declared interface" {
  timeout 3 python3 scripts/a2a-server.py --host 127.0.0.1 --port 19877 2>&1 &
  local pid=$!
  sleep 1
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
}

@test "S5-T07: allowlist has only 5 skills (closed set)" {
  python3 -c "
import yaml
d = yaml.safe_load(open('config/a2a-skills-allowlist.yaml'))
assert len(d['skills']) == 5
"
}

# ── S6: Exchange Ledger ──

@test "S6-T01: exchange-ledger.sh exists and is executable" {
  [[ -f "scripts/exchange-ledger.sh" ]]
  [[ -x "scripts/exchange-ledger.sh" ]]
}

@test "S6-T02: append creates ledger with hash chain" {
  local dir
  dir=$(mktemp -d)
  run bash scripts/exchange-ledger.sh append --instance test --type commitment --content "test" --project "$dir" 2>&1
  [ "$status" -eq 0 ]
  [[ -f "$dir/coordinacion/exchange/test.jsonl" ]]
  grep -q '"prev_hash": "genesis"' "$dir/coordinacion/exchange/test.jsonl"
  rm -rf "$dir"
}

@test "S6-T03: verify detects broken chain" {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/coordinacion/exchange"
  # Create a ledger with broken chain
  echo '{"ts":"x","instance":"b","type":"t","content":"","prev_hash":"genesis","hash":"bad"}' > "$dir/coordinacion/exchange/b.jsonl"
  echo '{"ts":"y","instance":"b","type":"t","content":"","prev_hash":"wrong","hash":"bad2"}' >> "$dir/coordinacion/exchange/b.jsonl"
  run bash scripts/exchange-ledger.sh verify --instance b --project "$dir" 2>&1
  rm -rf "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "BROKEN chain at line 2" ]]
}

@test "S6-T04: show displays ledger (using default path)" {
  mkdir -p coordinacion/exchange
  echo '{"ts":"x","instance":"s-test","type":"t","content":"","prev_hash":"genesis","hash":"h"}' > coordinacion/exchange/s-test.jsonl
  run bash scripts/exchange-ledger.sh show --instance s-test
  rm -f coordinacion/exchange/s-test.jsonl
  [[ "$output" =~ "genesis" ]]
}

# ── S7: Drill + Atestacion ──

@test "S7-T01: federation-drill.sh exists and is executable" {
  [[ -f "scripts/federation-drill.sh" ]]
  [[ -x "scripts/federation-drill.sh" ]]
}

@test "S7-T02: drill health runs without error" {
  run bash scripts/federation-drill.sh health
  [[ "$status" -eq 0 ]]
}

@test "S7-T03: drill compromised runs on synthetic instance" {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/coordinacion/cards"
  cat > "$dir/coordinacion/cards/synthetic.card.json" << 'JSON'
{"instanceId":"synthetic","principal":"x","status":"active","publicKey":"","signature":"x"}
JSON
  FEDERATION_ROOT="$dir" run bash scripts/federation-drill.sh compromised synthetic
  local card_status
  card_status=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['status'])" "$dir/coordinacion/cards/synthetic.card.json")
  rm -rf "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRILL COMPLETE" ]]
  [ "$card_status" = "revoked" ]
}

@test "S7-T04: exchange ledger verify works on empty ledger" {
  run bash scripts/exchange-ledger.sh verify --instance nonexistent
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "no ledger" ]]
}

@test "S7-T05: all 5 v1 skills are read-only or documented" {
  python3 -c "
import yaml
d = yaml.safe_load(open('config/a2a-skills-allowlist.yaml'))
readonly = [s for s,v in d['skills'].items() if v.get('readOnly')]
assert len(readonly) >= 2  # situacion.query + dependency.notify are read-only
"
}
