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

# ── Comportamiento con fixtures sintéticas (S03s) ──
# evals_json <fichero> <total> <positivas> <evals>: genera un evals.json con esa forma.
evals_json() {
  python3 - "$@" <<'P'
import json, sys
out, total, pos, n = sys.argv[1], *map(int, sys.argv[2:5])
trig = [{"query": f"q{i}", "should_trigger": i < pos} for i in range(total)]
ev = [{"prompt": f"p{i}", "expected_output": "x", "assertions": ["a"]} for i in range(n)]
json.dump({"trigger_evals": trig, "evals": ev}, open(out, "w"))
P
}

@test "exact shape passes and custom --total/--positives/--evals are honoured" {
  evals_json "$T/e.json" 6 2 1
  run python3 scripts/check-skill-evals.py "$T/e.json" --total 6 --positives 2 --evals 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "one trigger too many or too few fails (boundary on --total)" {
  evals_json "$T/e.json" 21 10 3
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: trigger_evals=21 (esperado 20)"* ]]
  evals_json "$T/e.json" 19 10 3
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trigger_evals=19 (esperado 20)"* ]]
}

@test "11 positives fail too: the count is exact, not a minimum" {
  evals_json "$T/e.json" 20 11 3
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"positivas=11 (esperado 10)"* ]]
}

@test "should_trigger as the string \"true\" does not count as positive" {
  evals_json "$T/e.json" 20 10 3
  python3 - "$T/e.json" <<'P'
import json, sys
d = json.load(open(sys.argv[1])); d["trigger_evals"][0]["should_trigger"] = "true"
json.dump(d, open(sys.argv[1], "w"))
P
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"positivas=9"* ]]
}

@test "wrong number of evals and every missing field are reported together" {
  evals_json "$T/e.json" 20 10 2
  python3 - "$T/e.json" <<'P'
import json, sys
d = json.load(open(sys.argv[1])); d["evals"][1] = {"prompt": "", "expected_output": None}
json.dump(d, open(sys.argv[1], "w"))
P
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evals=2 (esperado 3)"* ]]
  [[ "$output" == *"evals[1] sin prompt"* ]]
  [[ "$output" == *"evals[1] sin expected_output"* ]]
  [[ "$output" == *"evals[1] sin assertions"* ]]
  [[ "$output" != *"evals[0]"* ]]
}

@test "empty object fails on every count instead of passing" {
  printf '{}' > "$T/e.json"
  run python3 scripts/check-skill-evals.py "$T/e.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trigger_evals=0"* ]]
  [[ "$output" == *"evals=0"* ]]
}

@test "missing or invalid JSON file gives exit 2 without a traceback" {
  printf '{no json' > "$T/bad.json"
  for f in "$T/bad.json" "$T/no-existe.json"; do
    run python3 scripts/check-skill-evals.py "$f"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ilegible"* ]]
    [[ "$output" != *Traceback* ]]
  done
}

@test "wrong shape (list, string list, non-object items) gives exit 2 without a traceback" {
  for bad in '[]' '{"trigger_evals":"x","evals":[]}' '{"trigger_evals":[],"evals":"x"}' '{"trigger_evals":[1],"evals":[]}' '{"trigger_evals":[],"evals":["p"]}'; do
    printf '%s' "$bad" > "$T/e.json"
    run python3 scripts/check-skill-evals.py "$T/e.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"forma inválida"* ]]
    [[ "$output" != *Traceback* ]]
  done
}
