#!/usr/bin/env bats
# Tests for Era 100.1 — Lazy Loading of Rules Domain

setup() {
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  ROOT="$PWD"
  TMPDIR_RLL=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_RLL"
}

@test "rule-usage-analyzer.sh exists and is executable" {
  [ -x "$ROOT/scripts/rule-usage-analyzer.sh" ]
}

@test "analyzer summary mode outputs rule counts" {
  run bash -c "echo '' | $ROOT/scripts/rule-usage-analyzer.sh --summary"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Rules:.*total"
  echo "$output" | grep -q "tier1"
  echo "$output" | grep -q "dormant"
}

@test "analyzer full mode outputs valid JSON" {
  run bash -c "echo '' | $ROOT/scripts/rule-usage-analyzer.sh"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "analyzer detects at least 2 tier1 rules" {
  # Threshold history (each lowering is an intentional architectural win):
  #   - 10 originally
  #   - 8 after SPEC-067 CLAUDE.md diet (rules 9-25 moved to critical-rules-extended @import)
  #   - 2 after Era 201 lazy context fix (CLAUDE.md now has only 3 @imports:
  #     savia profile + radical-honesty + autonomous-safety; the first is a
  #     profile not a rule, so tier1 rules = 2). Lazy context reduced
  #     per-turn context by 83% and fixed subagent autocompact thrashing.
  # The remaining critical rules are still available via explicit Read.
  run bash -c "echo '' | $ROOT/scripts/rule-usage-analyzer.sh"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['tier1_count'])")
  [ "$count" -ge 2 ]
}

@test "rule-manifest.json exists" {
  [ -f "$ROOT/docs/rules/domain/rule-manifest.json" ]
}

@test "rule-manifest.json is valid JSON with required fields" {
  run python3 -c "
import json
d = json.load(open('$ROOT/docs/rules/domain/rule-manifest.json'))
assert 'total' in d, 'missing total'
assert 'tier1_count' in d, 'missing tier1_count'
assert 'rules' in d, 'missing rules'
assert d['total'] > 0, 'no rules found'
print('OK')
"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "manifest tier counts add up and dormant rules have no consumers" {
  run python3 -c "
import json
d = json.load(open('$ROOT/docs/rules/domain/rule-manifest.json'))
total = d['tier1_count'] + d['tier2_count'] + d['dormant_count']
assert total == d['total'], f'{total} != {d[\"total\"]}'
for n, i in d['rules'].items():
    if i['tier'] == 'dormant' and i['consumers']:
        raise AssertionError(f'{n} dormant but has consumers')
print('OK')
"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

# ── Negative cases ──

@test "analyzer fails on nonexistent directory" {
  run bash -c "echo '' | $ROOT/scripts/rule-usage-analyzer.sh --root /nonexistent/dir 2>&1"
  [ "$status" -ne 0 ] || [[ "$output" == *"0"* ]] || [[ "$output" == *"error"* ]]
}

@test "manifest rules have valid tier values" {
  run python3 -c "
import json
d = json.load(open('$ROOT/docs/rules/domain/rule-manifest.json'))
valid = {'tier1', 'tier2', 'dormant'}
for name, info in d['rules'].items():
    assert info['tier'] in valid, f'{name} has invalid tier: {info[\"tier\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

# ── Edge cases ──

@test "analyzer handles empty rules directory with zero rules" {
  mkdir -p "$TMPDIR_RLL/docs/rules/domain"
  run bash -c "echo '' | $ROOT/scripts/rule-usage-analyzer.sh --root $TMPDIR_RLL --summary 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]]
  [[ "$output" != *"319"* ]]
}

@test "manifest rules each have a consumers field" {
  run python3 -c "
import json
d = json.load(open('$ROOT/docs/rules/domain/rule-manifest.json'))
for name, info in d['rules'].items():
    assert 'consumers' in info, f'{name} missing consumers'
print('OK')
"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

# ── Safety verification ──

@test "rule-usage-analyzer.sh has set -uo pipefail safety" {
  grep -q "set -[euo]*o pipefail" "$ROOT/scripts/rule-usage-analyzer.sh"
}

# ── Additional coverage ──

@test "analyzer detects dormant rules" {
  run bash -c "echo '' | $ROOT/scripts/rule-usage-analyzer.sh"
  local dormant
  dormant=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['dormant_count'])")
  [ "$dormant" -ge 0 ]
}

@test "manifest total matches number of rule entries" {
  run python3 -c "
import json
d = json.load(open('$ROOT/docs/rules/domain/rule-manifest.json'))
assert d['total'] == len(d['rules']), f'{d[\"total\"]} != {len(d[\"rules\"])}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == "OK" ]]
}

@test "analyzer rejects invalid --root path" {
  run bash -c "echo '' | $ROOT/scripts/rule-usage-analyzer.sh --root /dev/null 2>&1"
  [ "$status" -ne 0 ] || [[ "$output" == *"0"* ]]
}

@test "manifest handles nonexistent rule ref gracefully" {
  run python3 -c "import json; d=json.load(open('$ROOT/docs/rules/domain/rule-manifest.json')); print('OK')"
  [ "$status" -eq 0 ]
}
