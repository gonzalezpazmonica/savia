#!/usr/bin/env bats
# tests/test-se-350-coherence-court.bats — SE-350: Coherence Court
# Ref: docs/specs/SE-350-coherence-court.spec.md
# Safety: set -uo pipefail applied per-test in setup().
#
# Coverage notes:
#   Exercises the public command surface of scripts/coherence-court.sh:
#     check, premises (init/add/list/show/clear), skeleton, score, gate, hash
#   Verifies the transversal contract: coherence is RELATIVE (needs premises),
#   gate exit codes mirror court-score-aggregator (0/2/1), and CRIT-001 (no net).

CC="${BATS_TEST_DIRNAME}/../scripts/coherence-court.sh"
SCHEMA="${BATS_TEST_DIRNAME}/../.claude/schemas/coherence-crc.schema.json"
RULES="${BATS_TEST_DIRNAME}/../rules/coherence.rules.yaml"
AGENTS_DIR="${BATS_TEST_DIRNAME}/../.opencode/agents"
RULES_DOC="${BATS_TEST_DIRNAME}/../docs/rules/domain/coherence-court.md"

setup() {
  set -uo pipefail
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
  export COHERENCE_PREMISES_DIR="$TMP_DIR/data"
  mkdir -p "$TMP_DIR/data"
  echo "stage output dummy" > "$TMP_DIR/stage.txt"
  FLOW="test-flow"
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

# helper: register 3 premises (one of each kind)
seed_premises() {
  bash "$CC" premises "$FLOW" init
  bash "$CC" premises "$FLOW" add constraint "Max 400 LOC" --stage stage-1 >/dev/null
  bash "$CC" premises "$FLOW" add fact "El modulo X existe" --stage stage-1 >/dev/null
  bash "$CC" premises "$FLOW" add objective "No romper API" --stage stage-1 >/dev/null
}

# ── Structural ────────────────────────────────────────────────────────────

@test "coherence-court.sh exists and has no syntax errors" {
  [[ -f "$CC" ]]
  bash -n "$CC"
}

@test "coherence-court.sh is executable" {
  [[ -x "$CC" ]]
}

@test "coherence-court.sh uses set -uo pipefail" {
  head -3 "$CC" | grep -q "set -uo pipefail"
}

@test "coherence-crc schema exists and is valid JSON" {
  [[ -f "$SCHEMA" ]]
  python3 -c "import json; json.load(open('$SCHEMA'))"
}

@test "schema defines all 4 coherence judges" {
  for judge in coherence-factual coherence-scope coherence-objectives coherence-premise-drift; do
    grep -q "\"$judge\"" "$SCHEMA"
  done
}

@test "schema defines finding severity enum" {
  grep -q '"critical"' "$SCHEMA"
  grep -q '"high"' "$SCHEMA"
  grep -q '"medium"' "$SCHEMA"
  grep -q '"low"' "$SCHEMA"
}

@test "schema requires SHA-256 pattern for file hashes" {
  grep -q 'a-f0-9.*64' "$SCHEMA"
}

@test "rules/coherence.rules.yaml exists with thresholds" {
  [[ -f "$RULES" ]]
  grep -q "pass_threshold: 90" "$RULES"
  grep -q "conditional_threshold: 70" "$RULES"
}

@test "all 5 coherence agents exist and are <=150 lines" {
  for agent in coherence-court-orchestrator coherence-factual-judge coherence-scope-judge coherence-objectives-judge coherence-premise-drift-judge; do
    [[ -f "$AGENTS_DIR/$agent.md" ]]
    local lines
    lines=$(wc -l < "$AGENTS_DIR/$agent.md")
    [[ "$lines" -le 150 ]]
  done
}

@test "coherence-court rule doc exists" {
  [[ -f "$RULES_DOC" ]]
  grep -q "SE-350" "$RULES_DOC"
}

# ── check (flujo multi-etapa gate) ────────────────────────────────────────

@test "check without premises fails (single-stage flow)" {
  bash "$CC" premises "$FLOW" init
  run bash "$CC" check --flow "$FLOW" --stage-output "$TMP_DIR/stage.txt"
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "single-stage\|no prior stage"
}

@test "check requires --flow" {
  run bash "$CC" check
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "requires --flow"
}

@test "check requires --stage-output" {
  bash "$CC" premises "$FLOW" init
  run bash "$CC" check --flow "$FLOW"
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "requires --stage-output"
}

@test "check fails on missing stage output file" {
  bash "$CC" premises "$FLOW" init
  bash "$CC" premises "$FLOW" add fact "X" >/dev/null
  run bash "$CC" check --flow "$FLOW" --stage-output "$TMP_DIR/nope.txt"
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "stage_output not found"
}

@test "check passes with premises + stage output" {
  seed_premises
  run bash "$CC" check --flow "$FLOW" --stage-output "$TMP_DIR/stage.txt"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "PASS"
}

# ── premises ──────────────────────────────────────────────────────────────

@test "premises init creates registry file" {
  bash "$CC" premises "$FLOW" init
  [[ -f "$TMP_DIR/data/coherence-premises-$FLOW.jsonl" ]]
}

@test "premises add writes a v1 record with timestamp" {
  bash "$CC" premises "$FLOW" init
  local pid
  pid=$(bash "$CC" premises "$FLOW" add constraint "Max 400 LOC" --stage stage-1)
  [[ -n "$pid" ]]
  grep -q '"schema_version": "1"' "$TMP_DIR/data/coherence-premises-$FLOW.jsonl"
  grep -q '"premise_id": "'"$pid"'"' "$TMP_DIR/data/coherence-premises-$FLOW.jsonl"
  grep -q '"kind": "constraint"' "$TMP_DIR/data/coherence-premises-$FLOW.jsonl"
  grep -q '"added_at"' "$TMP_DIR/data/coherence-premises-$FLOW.jsonl"
}

@test "premises add rejects invalid kind" {
  bash "$CC" premises "$FLOW" init
  run bash "$CC" premises "$FLOW" add bogus-kind "something"
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "invalid kind"
}

@test "premises add requires content" {
  bash "$CC" premises "$FLOW" init
  run bash "$CC" premises "$FLOW" add fact
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "requires <content>"
}

@test "premises list shows all premises" {
  seed_premises
  local out
  out=$(bash "$CC" premises "$FLOW" list)
  echo "$out" | grep -q "constraint"
  echo "$out" | grep -q "fact"
  echo "$out" | grep -q "objective"
}

@test "premises list --json is parseable" {
  seed_premises
  bash "$CC" premises "$FLOW" list --json | python3 -c "import sys,json; rows=json.load(sys.stdin); assert len(rows)==3, rows"
}

@test "premises show returns a single premise" {
  seed_premises
  local pid
  pid=$(grep -oP '"premise_id": "\K[^"]+' "$TMP_DIR/data/coherence-premises-$FLOW.jsonl" | head -1)
  bash "$CC" premises "$FLOW" show "$pid" | grep -q "\"premise_id\": \"$pid\""
}

@test "premises show on unknown id fails" {
  seed_premises
  run bash "$CC" premises "$FLOW" show does-not-exist
  [[ "$status" -ne 0 ]]
}

@test "premises clear empties the registry" {
  seed_premises
  bash "$CC" premises "$FLOW" clear
  run bash "$CC" premises "$FLOW" list --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json; assert json.load(sys.stdin)==[], sys.stdin.read()"
}

# ── skeleton ──────────────────────────────────────────────────────────────

@test "skeleton generates .coherence.crc with 4 judges" {
  seed_premises
  bash "$CC" skeleton "$FLOW" "$TMP_DIR/stage.txt" > "$TMP_DIR/out.crc"
  grep -q "coherence-factual" "$TMP_DIR/out.crc"
  grep -q "coherence-scope" "$TMP_DIR/out.crc"
  grep -q "coherence-objectives" "$TMP_DIR/out.crc"
  grep -q "coherence-premise-drift" "$TMP_DIR/out.crc"
  grep -q "score: 0" "$TMP_DIR/out.crc"
  grep -q "premises_count: 3" "$TMP_DIR/out.crc"
}

@test "skeleton includes sha256 of stage output" {
  seed_premises
  local expected
  expected=$(bash "$CC" hash "$TMP_DIR/stage.txt")
  bash "$CC" skeleton "$FLOW" "$TMP_DIR/stage.txt" | grep -q "$expected"
}

@test "skeleton requires flow and stage_output" {
  run bash "$CC" skeleton
  [[ "$status" -ne 0 ]]
  run bash "$CC" skeleton "$FLOW"
  [[ "$status" -ne 0 ]]
}

# ── score ─────────────────────────────────────────────────────────────────

@test "score computes 100 - (C*25 + H*10 + M*3 + L*1)" {
  run bash "$CC" score 1 2 3 4
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "score=42"
}

@test "score floors at 0" {
  run bash "$CC" score 5 5 5 5
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "score=0"
}

@test "score 0 0 0 0 = 100 pass" {
  run bash "$CC" score 0 0 0 0
  echo "$output" | grep -q "score=100"
  echo "$output" | grep -q "verdict=pass"
}

# ── gate ──────────────────────────────────────────────────────────────────

@test "gate 95 passes (exit 0)" {
  run bash "$CC" gate 95
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "PASS"
}

@test "gate 80 is conditional (exit 2)" {
  run bash "$CC" gate 80
  [[ "$status" -eq 2 ]]
  echo "$output" | grep -q "CONDITIONAL"
}

@test "gate 50 fails (exit 1) — human gate" {
  run bash "$CC" gate 50
  [[ "$status" -eq 1 ]]
  echo "$output" | grep -qi "puerta humana"
}

@test "gate respects --threshold override" {
  run bash "$CC" gate 85 --threshold 90
  [[ "$status" -eq 2 ]]
  run bash "$CC" gate 85 --threshold 80
  [[ "$status" -eq 0 ]]
}

@test "gate rejects non-numeric score" {
  run bash "$CC" gate abc
  [[ "$status" -ne 0 ]]
}

@test "gate respects COHERENCE_SCORE_PASS env" {
  run env COHERENCE_SCORE_PASS=80 bash "$CC" gate 85
  [[ "$status" -eq 0 ]]
  run env COHERENCE_SCORE_PASS=95 bash "$CC" gate 85
  [[ "$status" -eq 2 ]]
  echo "$output" | grep -q "CONDITIONAL"
}

# ── hash ──────────────────────────────────────────────────────────────────

@test "hash emits 64 hex chars" {
  run bash "$CC" hash "$TMP_DIR/stage.txt"
  [[ "$status" -eq 0 ]]
  [[ "${#output}" -eq 64 ]]
  echo "$output" | grep -qE '^[a-f0-9]{64}$'
}

@test "hash fails on missing file" {
  run bash "$CC" hash "$TMP_DIR/missing.txt"
  [[ "$status" -ne 0 ]]
}

# ── CRIT-001 (no red) ─────────────────────────────────────────────────────

@test "no network calls in script" {
  grep -vE '^\s*#' "$CC" | grep -qE 'curl|wget|http://|https://' && return 1
  return 0
}

# ── Comportamiento: fórmula, fronteras, validación de enteros, premisas y esqueleto ──

cc() { run bash "$CC" "$@"; }

@test "score: pesos exactos C=25 H=10 M=3 L=1 sobre 100" {
  cc score 1 0 0 0; [ "$output" = "score=75 verdict=conditional (C=1 H=0 M=0 L=0)" ]
  cc score 0 1 0 0; [ "$output" = "score=90 verdict=pass (C=0 H=1 M=0 L=0)" ]
  cc score 0 0 1 0; [ "$output" = "score=97 verdict=pass (C=0 H=0 M=1 L=0)" ]
  cc score 0 0 0 1; [ "$output" = "score=99 verdict=pass (C=0 H=0 M=0 L=1)" ]
  cc score 2 1 3 4; [ "$output" = "score=27 verdict=fail (C=2 H=1 M=3 L=4)" ]
}

@test "score: sin argumentos es 100 y nunca baja de 0" {
  cc score; [ "$output" = "score=100 verdict=pass (C=0 H=0 M=0 L=0)" ]
  cc score 5 5 5 5; [ "$output" = "score=0 verdict=fail (C=5 H=5 M=5 L=5)" ]
}

@test "score: fronteras de veredicto 90 y 70 (>=)" {
  cc score 0 1 0 0; [[ "$output" == "score=90 verdict=pass"* ]]
  cc score 0 1 0 1; [[ "$output" == "score=89 verdict=conditional"* ]]
  cc score 1 0 1 2; [[ "$output" == "score=70 verdict=conditional"* ]]
  cc score 1 0 2 0; [[ "$output" == "score=69 verdict=fail"* ]]
}

@test "score: los umbrales por entorno cambian el veredicto y se validan" {
  COHERENCE_SCORE_PASS=99 run bash "$CC" score 0 0 0 1
  [[ "$output" == "score=99 verdict=pass"* ]]
  COHERENCE_SCORE_PASS=100 run bash "$CC" score 0 0 0 1
  [[ "$output" == "score=99 verdict=conditional"* ]]
  COHERENCE_SCORE_CONDITIONAL=99 COHERENCE_SCORE_PASS=100 run bash "$CC" score 0 0 1 0
  [[ "$output" == "score=97 verdict=fail"* ]]
  COHERENCE_SCORE_PASS=101 run bash "$CC" score
  [ "$status" -eq 1 ]
  [[ "$output" == *"COHERENCE_SCORE_PASS out of range 0-100"* ]]
  COHERENCE_SCORE_CONDITIONAL=abc run bash "$CC" score
  [ "$status" -eq 1 ]
}

@test "score: enteros inválidos se rechazan antes de evaluar (negativos, ceros a la izquierda, texto, enormes)" {
  local bad
  for bad in -1 08 007 1.5 abc " 1" 1000000 99999999999999999999; do
    cc score "$bad" 0 0 0
    [ "$status" -eq 1 ] || { echo "aceptó C='$bad'"; return 1; }
  done
  cc score 0 0 0 08
  [ "$status" -eq 1 ]
  [[ "$output" == *"L must be an integer 0-999999 without leading zeros: '08'"* ]]
  cc score 999999 0 0 0
  [ "$status" -eq 0 ]
  [[ "$output" == "score=0 verdict=fail (C=999999"* ]]
}

@test "score: una sustitución de comandos en un contador no se ejecuta" {
  local marca="$TMP_DIR/pwned"
  cc score "a[\$(touch $marca)]" 0 0 0
  [ "$status" -eq 1 ]
  [ ! -e "$marca" ]
}

@test "gate: PASS/CONDITIONAL/FAIL con exit 0/2/1 y mensajes en las fronteras" {
  cc gate 90; [ "$status" -eq 0 ]; [[ "$output" == "PASS: score=90 >= 90"* ]]
  cc gate 89; [ "$status" -eq 2 ]; [[ "$output" == "CONDITIONAL: score=89 >= 70 < 90"* ]]
  cc gate 70; [ "$status" -eq 2 ]
  cc gate 69; [ "$status" -eq 1 ]; [[ "$output" == "FAIL: score=69 < 70"* ]]
  cc gate 100; [ "$status" -eq 0 ]
  cc gate 0; [ "$status" -eq 1 ]
}

@test "gate: --threshold y --conditional mueven las fronteras; el score puede ir antes o después" {
  cc gate 80 --threshold 80; [ "$status" -eq 0 ]
  cc gate --threshold 80 79; [ "$status" -eq 2 ]
  cc gate 50 --conditional 50; [ "$status" -eq 2 ]
  cc gate 49 --conditional 50; [ "$status" -eq 1 ]
  cc gate 60 --threshold 60 --conditional 60; [ "$status" -eq 0 ]
}

@test "gate: errores de validación" {
  cc gate;                       [ "$status" -eq 1 ]; [[ "$output" == *"gate requires <score>"* ]]
  cc gate 101;                   [ "$status" -eq 1 ]; [[ "$output" == *"score out of range 0-100"* ]]
  cc gate 80 --threshold 101;    [ "$status" -eq 1 ]
  cc gate 80 --conditional 95;   [ "$status" -eq 1 ]; [[ "$output" == *"conditional threshold (95) must be <= pass threshold (90)"* ]]
  cc gate 80 --threshold;        [ "$status" -eq 1 ]; [[ "$output" == *"--threshold requires a value"* ]]
  cc gate 80 --threshold "";     [ "$status" -eq 1 ]; [[ "$output" == *"--threshold requires a value"* ]]
  cc gate 80 --conditional;      [ "$status" -eq 1 ]
  cc gate abc;                   [ "$status" -eq 1 ]
}

@test "gate --help imprime el uso con exit 0" {
  cc gate --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Usage: coherence-court.sh gate <score> [--threshold N] [--conditional N]" ]]
}

@test "subcomando desconocido o ausente -> exit 2 con uso por stderr; --help y -h exit 0" {
  cc bogus; [ "$status" -eq 2 ]; [[ "$output" == "Usage: coherence-court.sh {check|premises|skeleton|score|gate|hash}" ]]
  cc; [ "$status" -eq 2 ]
  cc --help; [ "$status" -eq 0 ]; [[ "$output" == *"coherence-court.sh — SE-350 Coherence Court"* ]]
  cc -h; [ "$status" -eq 0 ]
}

@test "check: --help exit 0; opciones sin valor o vacías mueren con mensaje" {
  cc check --help; [ "$status" -eq 0 ]; [[ "$output" == *"Usage:"* ]]
  cc check --flow;               [ "$status" -eq 1 ]; [[ "$output" == *"--flow requires a value"* ]]
  cc check --flow "";            [ "$status" -eq 1 ]; [[ "$output" == *"--flow requires a value"* ]]
  cc check --flow f --stage-output ""; [ "$status" -eq 1 ]; [[ "$output" == *"--stage-output requires a value"* ]]
  cc check --nope;               [ "$status" -eq 1 ]; [[ "$output" == *"Unknown arg: --nope"* ]]
  cc check --stage-output "$TMP_DIR/stage.txt"; [ "$status" -eq 1 ]; [[ "$output" == *"check requires --flow"* ]]
  cc check --flow f;             [ "$status" -eq 1 ]; [[ "$output" == *"check requires --stage-output"* ]]
  cc check --flow f --stage-output "$TMP_DIR/no.txt"; [[ "$output" == *"stage_output not found"* ]]
}

@test "check: flujo con una sola etapa falla con exit 1 y cuenta 0; con premisas pasa y las cuenta" {
  cc check --flow solo --stage-output "$TMP_DIR/stage.txt"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "FAIL: flow 'solo' has 0 premises"* ]]
  [[ "${lines[1]}" == "Register premises with: coherence-court.sh premises solo add <kind> <content>" ]]
  bash "$CC" premises solo add fact "uno" >/dev/null
  bash "$CC" premises solo add decision "dos" >/dev/null
  cc check --flow solo --stage-output "$TMP_DIR/stage.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "PASS: flow 'solo' has 2 premise(s); stage output present ($TMP_DIR/stage.txt)" ]
}

@test "flujo: nombres con barra o salto de línea se rechazan en check, premises y skeleton" {
  cc premises "a/b" init; [ "$status" -eq 1 ]; [[ "$output" == *"invalid flow name 'a/b'"* ]]
  cc premises $'a\nb' init; [ "$status" -eq 1 ]
  cc skeleton "../x" "$TMP_DIR/stage.txt"; [ "$status" -eq 1 ]
  cc check --flow "x/y" --stage-output "$TMP_DIR/stage.txt"; [ "$status" -eq 1 ]
  [ -z "$(ls -A "$TMP_DIR/data")" ]
}

@test "premises: sin flujo -> uso; subcomando desconocido -> exit 2" {
  cc premises; [ "$status" -eq 1 ]; [[ "$output" == *"Usage: coherence-court.sh premises <flow>"* ]]
  cc premises f nada; [ "$status" -eq 2 ]; [[ "$output" == *"{init|add|list|show|clear}"* ]]
  cc premises f; [ "$status" -eq 2 ]
}

@test "premises add: valida tipo y contenido, acepta los cuatro tipos y devuelve el id" {
  cc premises f add;               [ "$status" -eq 1 ]; [[ "$output" == *"requires <kind>"* ]]
  cc premises f add rumor "x";     [ "$status" -eq 1 ]; [[ "$output" == *"Invalid kind 'rumor'"* ]]
  cc premises f add fact;          [ "$status" -eq 1 ]; [[ "$output" == *"requires <content>"* ]]
  cc premises f add fact "x" --nope; [ "$status" -eq 1 ]; [[ "$output" == *"Unknown arg: --nope"* ]]
  cc premises f add fact "x" --id; [ "$status" -eq 1 ]; [[ "$output" == *"--id requires a value"* ]]
  local k
  for k in fact constraint objective decision; do
    cc premises f add "$k" "contenido $k" --id "id-$k"
    [ "$status" -eq 0 ]
    [ "$output" = "id-$k" ]
  done
  cc premises f add fact "sin id"
  [[ "$output" =~ ^[0-9a-f]{12}$ ]]
}

@test "premises add/show: guarda etapa, fuente, flujo y fecha; show devuelve ese registro" {
  bash "$CC" premises f add objective "reducir coste" --id p1 --stage stage-3 --source "acta 5" >/dev/null
  cc premises f show p1
  [ "$status" -eq 0 ]
  python3 - "$output" <<'EOP'
import json, re, sys
d = json.loads(sys.argv[1])
assert (d["premise_id"], d["flow"], d["stage"], d["kind"]) == ("p1", "f", "stage-3", "objective"), d
assert d["content"] == "reducir coste" and d["source"] == "acta 5" and d["schema_version"] == "1", d
assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", d["added_at"]), d
EOP
  bash "$CC" premises f add fact "otra" --id p2 >/dev/null
  cc premises f show p2
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["stage"]=="stage-1" and d["source"] is None, d' "$output"
}

@test "premises show: id inexistente, sin id o sin registro -> exit 1 con mensaje" {
  bash "$CC" premises f add fact "x" --id p1 >/dev/null
  cc premises f show zzz; [ "$status" -eq 1 ]; [[ "$output" == *"premise zzz not found"* ]]
  cc premises f show;     [ "$status" -eq 1 ]; [[ "$output" == *"requires <premise_id>"* ]]
  cc premises otro show p1; [ "$status" -eq 1 ]; [[ "$output" == *"No premises registry for flow 'otro'"* ]]
}

@test "premises list: formato de texto y --json; sin registro falla" {
  bash "$CC" premises f add fact "uno" --id a1 --stage s1 >/dev/null
  bash "$CC" premises f add constraint "dos" --id a2 >/dev/null
  cc premises f list
  [ "${lines[0]}" = "a1  [fact] stage=s1  uno" ]
  [ "${lines[1]}" = "a2  [constraint] stage=stage-1  dos" ]
  cc premises f list --json
  [ "$(echo "$output" | python3 -c 'import json,sys; print([r["premise_id"] for r in json.load(sys.stdin)])')" = "['a1', 'a2']" ]
  cc premises nuevo list
  [ "$status" -eq 1 ]
  [[ "$output" == *"No premises registry for flow 'nuevo' (run init)"* ]]
}

@test "premises init/clear: crean el registro, vacían y informan de la ruta" {
  cc premises f init
  [ "$output" = "initialized: $TMP_DIR/data/coherence-premises-f.jsonl" ]
  [ -f "$TMP_DIR/data/coherence-premises-f.jsonl" ]
  bash "$CC" premises f add fact "x" >/dev/null
  [ -s "$TMP_DIR/data/coherence-premises-f.jsonl" ]
  cc premises f clear
  [ "$output" = "cleared: $TMP_DIR/data/coherence-premises-f.jsonl" ]
  [ ! -s "$TMP_DIR/data/coherence-premises-f.jsonl" ]
}

@test "premises: las líneas corruptas del registro no cuentan" {
  printf '{"premise_id":"ok1","kind":"fact","content":"x"}\nesto no es json\n\n{"premise_id":"ok2","kind":"fact","content":"y"}\n' > "$TMP_DIR/data/coherence-premises-c.jsonl"
  cc check --flow c --stage-output "$TMP_DIR/stage.txt"
  [[ "$output" == "PASS: flow 'c' has 2 premise(s)"* ]]
}

@test "skeleton: campos estructurales, sha256 real, premisas listadas y flujo escapado" {
  bash "$CC" premises sk add decision 'usar "Postgres"' --id d1 >/dev/null
  cc skeleton sk "$TMP_DIR/stage.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "---" ]
  [ "${lines[-1]}" = "---" ]
  [[ "$output" == *'flow_ref: "sk"'* ]]
  [[ "$output" == *"premises_count: 1"* ]]
  [[ "$output" == *"sha256: \"$(sha256sum "$TMP_DIR/stage.txt" | awk '{print $1}')\""* ]]
  [[ "$output" == *'path: "'"$TMP_DIR"'/stage.txt"'* ]]
  [[ "$output" == *'- id: "d1"'* && "$output" == *'kind: "decision"'* && "$output" == *'content: "usar \"Postgres\""'* ]]
  [[ "$output" =~ court_id:\ \"COH-[0-9]{4}-[0-9]{4}-001\" ]]
  [[ "$output" == *'judges:'* && "$output" == *'coherence-premise-drift'* && "$output" == *'reviewed_by: "coherence-court-v1"'* ]]
}

@test "skeleton: sin premisas -> premises_count 0 y lista vacía; errores de uso" {
  cc skeleton vacio "$TMP_DIR/stage.txt"
  [[ "$output" == *"premises_count: 0"* ]]
  [[ "$output" == *"premises:"$'\n'"  []"* ]]
  cc skeleton;                        [ "$status" -eq 1 ]; [[ "$output" == *"skeleton requires <flow>"* ]]
  cc skeleton f;                      [ "$status" -eq 1 ]; [[ "$output" == *"requires <stage_output>"* ]]
  cc skeleton f "$TMP_DIR/no.txt";    [ "$status" -eq 1 ]; [[ "$output" == *"stage_output not found"* ]]
}

@test "hash: coincide con sha256sum; errores si falta o no existe" {
  cc hash "$TMP_DIR/stage.txt"
  [ "$output" = "$(sha256sum "$TMP_DIR/stage.txt" | awk '{print $1}')" ]
  cc hash;                    [ "$status" -eq 1 ]; [[ "$output" == *"Usage: coherence-court.sh hash FILE"* ]]
  cc hash "$TMP_DIR/no.txt";  [ "$status" -eq 1 ]; [[ "$output" == *"File not found"* ]]
}
