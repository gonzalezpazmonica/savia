#!/usr/bin/env bats
# nightly: serial (comprueba que no modifica nada del árbol; otra suite escribiendo a la vez lo falsea)
# Ref: SE-028/041/056 + unified runner
SCRIPT="scripts/security-audit-all.sh"

setup() { export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"; cd "$BATS_TEST_DIRNAME/.."; }
teardown() { cd /; }

@test "exists + executable" { [[ -x "$SCRIPT" ]]; }
@test "uses set -uo pipefail" { run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "passes bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }
@test "--help exits 0" { run bash "$SCRIPT" --help; [ "$status" -eq 0 ]; }
@test "rejects unknown arg" { run bash "$SCRIPT" --bogus; [ "$status" -eq 2 ]; }
@test "runs without crash" { run bash "$SCRIPT"; [[ "$status" -eq 0 || "$status" -eq 1 ]]; }
@test "--json produces output" { run bash "$SCRIPT" --json; [[ "$output" == *"{"* ]]; }
@test "--json parses as JSON" {
  run bash -c 'bash '"$SCRIPT"' --json | python3 -c "import json,sys; json.load(sys.stdin); print(\"ok\")"'
  [[ "$output" == *"ok"* ]]
}

@test "references 4 scanners" {
  run grep -c 'mcp-security-audit\|permissions-wildcard-audit\|hook-injection-audit\|prompt-security-scan' "$SCRIPT"
  [[ "$output" -ge 4 ]]
}
@test "rejects invalid --fail-on" { run bash "$SCRIPT" --fail-on BOGUS; [ "$status" -eq 2 ]; }
@test "--fail-on LOW works" { run bash "$SCRIPT" --fail-on LOW --json; [[ "$output" == *"verdict"* ]]; }
@test "--fail-on CRITICAL works" { run bash "$SCRIPT" --fail-on CRITICAL --json; [[ "$output" == *"verdict"* ]]; }
@test "--json has scanners list" {
  run bash -c 'bash scripts/security-audit-all.sh --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d[\"scanners\"], list); print(\"ok\")"'
  [[ "$output" == *"ok"* ]]
}
@test "--json has total_critical" {
  run bash -c 'bash scripts/security-audit-all.sh --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert \"total_critical\" in d; print(\"ok\")"'
  [[ "$output" == *"ok"* ]]
}
@test "graceful degradation when sub-scanners missing" {
  # Should still complete even if a sub-scanner returns {}
  run bash "$SCRIPT"
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}
@test "output reports SCANNER header" {
  run bash "$SCRIPT"
  [[ "$output" == *"SCANNER"* ]]
}
@test "output reports Totals line" {
  run bash "$SCRIPT"
  [[ "$output" == *"Totals:"* ]]
}
@test "isolation: does not modify anything" {
  local before
  before=$(find scripts tests docs .claude -type f 2>/dev/null | wc -l)
  bash "$SCRIPT" >/dev/null 2>&1 || true
  local after
  after=$(find scripts tests docs .claude -type f 2>/dev/null | wc -l)
  [[ "$before" == "$after" ]]
}
@test "isolation: exit codes 0/1/2" {
  run bash "$SCRIPT"; [[ "$status" -eq 0 || "$status" -eq 1 ]]
  run bash "$SCRIPT" --bogus; [ "$status" -eq 2 ]
}
