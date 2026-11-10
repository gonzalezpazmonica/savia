#!/usr/bin/env bats

# Ref: docs/specs/SE-510-guardas-sin-bloqueos-falsos-despachador.spec.md (S1: D1, AC-1, AC-3)
# El corpus corre con el despachador simulado de SE-400 F3 (scripts/ablation_kernel.py), sin runner nuevo.
setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  export HEAD_OUT="$BATS_FILE_TMPDIR/head" OLD_OUT="$BATS_FILE_TMPDIR/old"
  local rc=0
  python3 scripts/ablation_kernel.py guard-corpus --out "$HEAD_OUT" >"$BATS_FILE_TMPDIR/head.log" 2>&1 || rc=$?
  echo "$rc" >"$BATS_FILE_TMPDIR/head.rc"
  # main de la spec (2026-11-04), antes de #1483: F1b y F2 tienen que dar BLOCK.
  rc=0
  python3 scripts/ablation_kernel.py guard-corpus --hooks-rev be2fca5aa --out "$OLD_OUT" \
    >"$BATS_FILE_TMPDIR/old.log" 2>&1 || rc=$?
  echo "$rc" >"$BATS_FILE_TMPDIR/old.rc"
}

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  TMP=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP"
}

# verdict <receipt> <id> → veredicto del caso
verdict() {
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))
print(next(c["verdict"] for c in r["cases"] if c["id"] == sys.argv[2]))' "$1/se510-guard-corpus-receipt.json" "$2"
}

# validate_mutated <python que muta la variable c> → código de InventoryError o OK
validate_mutated() {
  python3 - "$1" <<'EOF'
import json, sys
sys.path.insert(0, "scripts")
import ablation_kernel as k
c = json.load(open(k.GUARD_CORPUS_PATH, encoding="utf-8"))
by = {x["id"]: x for x in c["cases"]}
exec(sys.argv[1])
try:
    k.validate_guard_corpus(c)
    print("OK")
except k.InventoryError as e:
    print(e.code)
EOF
}

@test "SE-510 S1: el corpus existe y es válido con su semilla" {
  [ -f config/guard-allow-corpus.json ]
  run validate_mutated "pass"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "SE-510 AC-1: F1a, F1b, F2 y F3 son reales del 2026-11-04 y no hay entrada F4" {
  run python3 -c 'import json; c={x["id"]:x for x in json.load(open("config/guard-allow-corpus.json"))["cases"]}
assert all(c[i]["origin"]=="real:2026-11-04" and c[i]["expect"]=="ALLOW" for i in ("F1a","F1b","F2","F3"))
assert "F4" not in c and c["B4"]["expect"]=="BLOCK"; print("ok")'
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "SE-510 AC-1: con los hooks de main be2fca5aa, F1b y F2 dan BLOCK (el corpus está en rojo)" {
  [ "$(cat "$BATS_FILE_TMPDIR/old.rc")" -eq 1 ]
  [ "$(verdict "$OLD_OUT" F1b)" = "FALSE_BLOCK" ]
  [ "$(verdict "$OLD_OUT" F2)" = "FALSE_BLOCK" ]
  grep -q "FALSE_BLOCK" "$BATS_FILE_TMPDIR/old.log"
}

@test "SE-510 AC-3: los pares peligrosos B1, B1b, B2, B3, B4 y el push forzado a main siguen en BLOCK" {
  for id in B1 B1b B2 B3 B4 B5; do
    [ "$(verdict "$HEAD_OUT" "$id")" = "MATCH" ]
  done
  run python3 -c 'import json; r=json.load(open("'"$HEAD_OUT"'/se510-guard-corpus-receipt.json"))
assert r["false_allows"] == [], r["false_allows"]
assert all(c["observed"]=="BLOCK" for c in r["cases"] if c["id"].startswith("B")); print("ok")'
  [ "$status" -eq 0 ]
}

@test "SE-510 S1 en main actual: F1a, F1b y F2 pasan; F3 es el único bloqueo falso (S2 lo arregla)" {
  # Rojo conocido y con causa: pr-summary-gate.sh lee el resumen de CLAUDE_PROJECT_DIR, no el del
  # árbol donde corre gh. Cuando S2 lo arregle, este test falla y hay que pasarlo a «0 falsos».
  [ "$(cat "$BATS_FILE_TMPDIR/head.rc")" -eq 1 ]
  for id in F1a F1b F2; do
    [ "$(verdict "$HEAD_OUT" "$id")" = "MATCH" ]
  done
  run python3 -c 'import json; r=json.load(open("'"$HEAD_OUT"'/se510-guard-corpus-receipt.json"))
print(r["decision"], r["false_block_rate"], ",".join(r["false_blocks"]), r["threshold_false_blocks"])'
  [ "$output" = "FALSE_BLOCK 1/4 F3 0" ]
  grep -q "97h" "$HEAD_OUT/se510-guard-corpus-receipt.json"
}

@test "SE-510 AC-3: un par que deja de bloquear es FALSE_ALLOW y sale con 3" {
  python3 -c 'import json; c=json.load(open("config/guard-allow-corpus.json"))
b2=next(x for x in c["cases"] if x["id"]=="B2"); b2["fixture"]="repo-clean"
json.dump(c, open("'"$TMP"'/c.json","w"))'
  run python3 scripts/ablation_kernel.py guard-corpus --corpus "$TMP/c.json" --out "$TMP/out"
  [ "$status" -eq 3 ]
  [[ "$output" == *"FALSE_ALLOW"* ]]
  [ "$(verdict "$TMP/out" B2)" = "FALSE_ALLOW" ]
}

@test "SE-510 AC-3: un caso ALLOW sin par no valida" {
  run validate_mutated 'del by["F2"]["pair"]'
  [ "$output" = "GUARD_CORPUS_PAIR_MISSING" ]
  run validate_mutated 'by["F2"]["pair"] = "F1a"'
  [ "$output" = "GUARD_CORPUS_PAIR_MISSING" ]
}

@test "SE-510 AC-3: un par con otro evento, herramienta u orden base no valida" {
  run validate_mutated 'by["B2"]["tool"] = "Write"'
  [ "$output" = "GUARD_CORPUS_PAIR_SHAPE" ]
  run validate_mutated 'by["B2"]["event"] = "PostToolUse"'
  [ "$output" = "GUARD_CORPUS_PAIR_SHAPE" ]
  run validate_mutated 'by["B2"]["input"] = {"command": "ls main"}'
  [ "$output" = "GUARD_CORPUS_PAIR_SHAPE" ]
}

@test "SE-510 AC-3: la misma entrada con dos veredictos no valida" {
  run validate_mutated 'by["B3"]["fixture"] = "worktree-summary-fresh"'
  [ "$output" = "GUARD_CORPUS_TWO_VERDICTS" ]
  run validate_mutated 'c["cases"].append(dict(by["B5"], id="B5bis"))'
  [ "$output" = "GUARD_CORPUS_DUPLICATE" ]
}

@test "SE-510 D1: semilla, F4, origen y fixture se comprueban" {
  run validate_mutated 'c["cases"] = [x for x in c["cases"] if x["id"] != "B4"]'
  [ "$output" = "GUARD_CORPUS_SEED" ]
  run validate_mutated 'c["cases"].append(dict(by["B4"], id="F4", fixture="repo-clean"))'
  [ "$output" = "GUARD_CORPUS_F4" ]
  run validate_mutated 'by["F3"]["origin"] = "sintético"'
  [ "$output" = "GUARD_CORPUS_SEED_ORIGIN" ]
  run validate_mutated 'del by["F1a"]["guard"]'
  [ "$output" = "GUARD_CORPUS_ORIGIN" ]
  run validate_mutated 'by["B5"]["fixture"] = "otro"'
  [ "$output" = "GUARD_CORPUS_FIXTURE" ]
}

@test "SE-510 S1: una revisión de hooks inexistente es INVALID (exit 2), nunca PASS" {
  run python3 scripts/ablation_kernel.py guard-corpus --hooks-rev 0000000000000000000000000000000000000000 --out "$TMP/x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"INVALID HOOKS_REV"* ]]
  [ ! -f "$TMP/x/se510-guard-corpus-receipt.json" ]
}

@test "SE-510 S1: el veredicto por caso no confunde permiso y bloqueo" {
  run python3 -c 'import sys; sys.path.insert(0,"scripts"); import ablation_kernel as k
print(k.guard_verdict("ALLOW","ALLOW"), k.guard_verdict("ALLOW","BLOCK"), k.guard_verdict("BLOCK","ALLOW"), k.guard_verdict("BLOCK","BLOCK"))'
  [ "$output" = "MATCH FALSE_BLOCK FALSE_ALLOW MATCH" ]
}
