#!/usr/bin/env bats
# check-skill-evals.py — forma de evals.json (SE-457 AC6/AC7)
# Ref: docs/specs/SE-457-harness-architecture-skill.spec.md

setup() {
  cd "$BATS_TEST_DIRNAME/.." || exit 1
  T="$(mktemp -d)"
  EV=".claude/skills/harness-architecture/evals/evals.json"
}

teardown() { rm -rf "$T"; }

@test "evals.json real de harness-architecture cumple 20/10/3" {
  run python3 scripts/check-skill-evals.py "$EV"
  [ "$status" -eq 0 ]
}

@test "negativo AC7: 9 positivas hacen fallar el chequeo" {
  python3 - "$EV" "$T/e.json" <<'P'
import json, sys
d = json.load(open(sys.argv[1]))
for t in d["trigger_evals"]:
    if t["should_trigger"] is True:
        t["should_trigger"] = False
        break
json.dump(d, open(sys.argv[2], "w"))
P
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"positivas=9"* ]]
}

@test "negativo: eval sin assertions falla" {
  python3 - "$EV" "$T/e.json" <<'P'
import json, sys
d = json.load(open(sys.argv[1]))
d["evals"][0]["assertions"] = []
json.dump(d, open(sys.argv[2], "w"))
P
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin assertions"* ]]
}
