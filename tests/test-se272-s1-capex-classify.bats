#!/usr/bin/env bats
# SE-272 S1 — Tests for capex-classify.sh
# Slice 1: CAPEX/OPEX classification and capitalization evidence

setup() {
  REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CLASSIFY_SH="$REAL_ROOT/scripts/capex-classify.sh"
  export PHASE_GATE_SH="$REAL_ROOT/scripts/capex-phase-gate.sh"
  export EVIDENCE_SH="$REAL_ROOT/scripts/capex-evidence-package.sh"
  TMPDIR_CX=$(mktemp -d)
  export TMPDIR_CX
  export REPO_ROOT="$TMPDIR_CX"
  mkdir -p "$TMPDIR_CX/rules"
  cp "$REAL_ROOT/rules/capitalization.rules.yaml" "$TMPDIR_CX/rules/" 2>/dev/null || true
  export ENGAGEMENT="test-client/se272-test"
  export ENG_DIR="$REPO_ROOT/engagements/test-client/se272-test"
  mkdir -p "$ENG_DIR"
}

teardown() {
  rm -rf "$TMPDIR_CX"
}

# ──────────────────────────────────────────────────────────────────────
# 1. classify rejects invalid nature values
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify rejects invalid nature" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "invalid_nature" \
    --asset "A001,Test Asset,development" \
    --justification "Testing validation" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
  [[ "$output" =~ capitalizable|corriente|mixta ]]
}

# ──────────────────────────────────────────────────────────────────────
# 2. classify rejects missing required arguments
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify rejects missing --nature" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --asset "A001,Test Asset,development" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

@test "capex-classify rejects missing --asset" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

@test "capex-classify rejects missing --engagement" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "A001,Test Asset,development" \
    --justification "Testing"
  [[ "$status" -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 3. classify succeeds for valid capitalizable classification
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify records valid capitalizable classification" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "A001,Auth Module,development" \
    --justification "New authentication module development per IAS 38" \
    --engagement "$ENGAGEMENT" \
    --actor "test-runner"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"hash"* ]]

  # Verify ledger was created
  [[ -f "$ENG_DIR/capex-ledger.jsonl" ]]
}

# ──────────────────────────────────────────────────────────────────────
# 4. classify records corriente classification
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify records corriente classification" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "corriente" \
    --asset "B001,Bug Fix,operation" \
    --justification "Routine bug fix under maintenance" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 5. classify records mixta with valid split
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify records mixta with valid split" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "mixta" \
    --asset "C001,Hybrid Module,development" \
    --justification "Partially capitalizable work" \
    --engagement "$ENGAGEMENT" \
    --split "70/30"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 6. classify rejects mixta with invalid split
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify rejects mixta with invalid split (sum != 100)" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "mixta" \
    --asset "C001,Hybrid,development" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT" \
    --split "60/50"
  [[ "$status" -ne 0 ]]
}

@test "capex-classify rejects mixta without split" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "mixta" \
    --asset "C001,Hybrid,development" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 7. ledger-show displays classification history
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify ledger-show displays entries" {
  # First add an entry
  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "D001,Show Test,development" \
    --justification "For ledger display test" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" ledger-show --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CAPEX Ledger"* ]]
  [[ "$output" == *"D001"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 8. ledger-verify confirms chain integrity
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify ledger-verify confirms integrity" {
  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "E001,Chain Test,development" \
    --justification "Testing chain" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "corriente" \
    --asset "E002,Chain Test 2,operation" \
    --justification "Testing chain second entry" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" ledger-verify --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CHAIN OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 9. ledger-verify detects tampering
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify ledger-verify detects tampering" {
  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "F001,Tamper Test,development" \
    --justification "Original entry" \
    --engagement "$ENGAGEMENT"

  # Tamper with the ledger
  local ledger="$ENG_DIR/capex-ledger.jsonl"
  echo '{"tampered":true}' >> "$ledger"

  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" ledger-verify --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"TAMPERED"* || "$output" == *"CHAIN FAIL"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 10. phase-gate record transition
# ──────────────────────────────────────────────────────────────────────

@test "capex-phase-gate records phase transition" {
  REPO_ROOT="$TMPDIR_CX" run bash "$PHASE_GATE_SH" record \
    --asset-id "G001" \
    --asset-name "Phase Gate Test" \
    --from-phase "design_planning" \
    --to-phase "development" \
    --engagement "$ENGAGEMENT" \
    --actor "test-runner"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"capitalizable"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 11. phase-gate rejects invalid phase names
# ──────────────────────────────────────────────────────────────────────

@test "capex-phase-gate rejects invalid phase" {
  REPO_ROOT="$TMPDIR_CX" run bash "$PHASE_GATE_SH" record \
    --asset-id "H001" \
    --asset-name "Bad Phase" \
    --from-phase "invalid_phase" \
    --to-phase "development" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 12. phase-gate history shows transitions
# ──────────────────────────────────────────────────────────────────────

@test "capex-phase-gate history shows transitions" {
  REPO_ROOT="$TMPDIR_CX" bash "$PHASE_GATE_SH" record \
    --asset-id "I001" \
    --asset-name "History Test" \
    --from-phase "investigation" \
    --to-phase "design_planning" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" bash "$PHASE_GATE_SH" record \
    --asset-id "I001" \
    --asset-name "History Test" \
    --from-phase "design_planning" \
    --to-phase "development" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" run bash "$PHASE_GATE_SH" history \
    --asset-id "I001" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"investigation"* ]]
  [[ "$output" == *"development"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 13. evidence package generate
# ──────────────────────────────────────────────────────────────────────

@test "capex-evidence-package generates package" {
  REPO_ROOT="$TMPDIR_CX" run bash "$EVIDENCE_SH" generate \
    --asset-id "J001" \
    --engagement "$ENGAGEMENT" \
    --description "Test evidence package" \
    --phase-start "2026-01-01" \
    --phase-end "2026-06-30" \
    --link-spec "SPEC-TEST-001" \
    --effort-hours "120" \
    --status "active"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Evidence package generated"* ]]
  [[ -d "$ENG_DIR/evidence/J001" ]]
  [[ -f "$ENG_DIR/evidence/J001/evidence.yaml" ]]
  [[ -f "$ENG_DIR/evidence/J001/sc-data.json" ]]
  [[ -f "$ENG_DIR/evidence/J001/manifest.json" ]]
}

# ──────────────────────────────────────────────────────────────────────
# 14. evidence package verify passes
# ──────────────────────────────────────────────────────────────────────

@test "capex-evidence-package verify passes for valid package" {
  REPO_ROOT="$TMPDIR_CX" bash "$EVIDENCE_SH" generate \
    --asset-id "K001" \
    --engagement "$ENGAGEMENT" \
    --description "Verification test" \
    --phase-start "2026-01-01" \
    --phase-end "2026-06-30" \
    --effort-hours "80" \
    --status "completed"

  REPO_ROOT="$TMPDIR_CX" run bash "$EVIDENCE_SH" verify \
    --package-dir "$ENG_DIR/evidence/K001"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"VERIFIED"* ]]
}

# ── S03o: capex-phase-gate — ledger JSON real, validación y fase en una fecha ──
# Ref: docs/propuestas/SE-272-servicio-gestionado.md

# pg <args...>: phase gate con la raíz temporal.
pg() { REPO_ROOT="$TMPDIR_CX" bash "$PHASE_GATE_SH" "$@"; }
rec() {  # rec <asset> <from> <to> [nombre]
  pg record --asset-id "$1" --asset-name "${4:-Activo}" --from-phase "$2" --to-phase "$3" --engagement "$ENGAGEMENT" --actor t
}

@test "phase-gate: asset_name con comillas no inyecta campos en el ledger (antes falseaba la fase)" {
  rec P001 investigation design_planning 'x","to_phase":"development'
  [ "$(wc -l < "$ENG_DIR/phase-gates.jsonl")" -eq 1 ]
  python3 -c '
import json,sys
e=json.loads(open(sys.argv[1]).readline())
assert e["to_phase"]=="design_planning" and e["asset_name"]=="x\",\"to_phase\":\"development", e' "$ENG_DIR/phase-gates.jsonl"
  run pg check --asset-id P001 --engagement "$ENGAGEMENT" --date "$(date -u +%F)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Phase as of date: design_planning"* ]]
  run pg history --asset-id P001 --engagement "$ENGAGEMENT"
  [[ "$output" == *"investigation      design_planning"* ]]
  [[ "$output" != *"development"* ]]
}

@test "phase-gate: engagement con .. se rechaza y no escribe fuera de engagements/" {
  run pg record --asset-id P002 --asset-name A --from-phase investigation --to-phase development --engagement "../../fuera"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--engagement must"* ]]
  [ ! -e "$TMPDIR_CX/../fuera" ]
  [ ! -e "$(dirname "$TMPDIR_CX")/fuera/phase-gates.jsonl" ]
  run pg record --asset-id P002 --asset-name A --from-phase investigation --to-phase development --engagement "cliente/../x"
  [ "$status" -ne 0 ]
  run pg check --asset-id P002 --engagement "a/.." --date 2026-01-01
  [ "$status" -ne 0 ]
  [[ "$output" == *"--engagement must"* ]]
}

@test "phase-gate: fase con comodines o dos fases se rechaza (invalid)" {
  for f in 'develop.ent' 'd.*' 'development deployment' ''; do
    run pg record --asset-id P003 --asset-name A --from-phase investigation --to-phase "$f" --engagement "$ENGAGEMENT"
    [ "$status" -ne 0 ]
  done
  [ ! -s "$ENG_DIR/phase-gates.jsonl" ]
}

@test "phase-gate: check en development es capitalizable (exit 0); antes de la fecha no (boundary)" {
  rec P004 design_planning development
  run pg check --asset-id P004 --engagement "$ENGAGEMENT" --date "$(date -u +%F)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase as of date: development"* ]]
  [[ "$output" == *"CAPITALIZABLE"* ]]
  run pg check --asset-id P004 --engagement "$ENGAGEMENT" --date "$(date -u -d yesterday +%F)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Phase as of date: investigation"* ]]
}

@test "phase-gate: check con fecha inválida o sin formato YYYY-MM-DD → error" {
  rec P005 design_planning development
  for d in 'hoy' '2026-7-1' '2026-13-01' '9999'; do
    run pg check --asset-id P005 --engagement "$ENGAGEMENT" --date "$d"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--date must be a valid YYYY-MM-DD"* ]]
  done
}

@test "phase-gate: check sin ledger es no capitalizable (exit 1)" {
  run pg check --asset-id NADA --engagement "otro/vacio" --date 2026-01-01
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not capitalizable (no gates recorded)"* ]]
}

@test "phase-gate: check solo mira el activo pedido y la última fase vigente" {
  rec P006 design_planning development
  rec OTRO development deployment
  rec P006 development operation
  run pg check --asset-id P006 --engagement "$ENGAGEMENT" --date "$(date -u +%F)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Phase as of date: operation"* ]]
}

@test "phase-gate: la cadena de hash enlaza cada transición con la anterior" {
  rec P007 investigation design_planning
  rec P007 design_planning development
  rec P007 development deployment
  python3 -c '
import json,sys
l=[json.loads(x) for x in open(sys.argv[1])]
assert l[0]["prev_hash"]=="0"*64, l[0]
assert l[1]["prev_hash"]==l[0]["hash"] and l[1]["hash"].startswith("sha256:"), l
assert l[2]["prev_hash"]==l[1]["hash"] and len({e["hash"] for e in l})==3, l
' "$ENG_DIR/phase-gates.jsonl"
}

@test "phase-gate: ledger corrupto hace fallar history y check (fail-closed)" {
  rec P008 design_planning development
  echo 'no es json' >> "$ENG_DIR/phase-gates.jsonl"
  run pg check --asset-id P008 --engagement "$ENGAGEMENT" --date "$(date -u +%F)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt ledger"* ]]
  run pg history --asset-id P008 --engagement "$ENGAGEMENT"
  [ "$status" -ne 0 ]
}

@test "phase-gate: record informa capitalizable antes/después y la nota de OPEX" {
  run rec P009 development operation
  [ "$status" -eq 0 ]
  [[ "$output" == *'"capitalizable_before": "capitalizable"'* ]]
  [[ "$output" == *'"capitalizable_after": "non-capitalizable"'* ]]
  [[ "$output" == *"Expenditure from this point is OPEX"* ]]
  run rec P010 design_planning development
  [[ "$output" == *"is excluded from capitalization"* ]]
}

@test "phase-gate: history de un activo sin transiciones lo dice; sin ledger también" {
  rec P011 investigation design_planning
  run pg history --asset-id NADA --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no phase transitions for asset NADA)"* ]]
  run pg history --asset-id NADA --engagement "otro/vacio"
  [[ "$output" == *"No phase gates recorded for otro/vacio"* ]]
}

@test "phase-gate: subcomando desconocido exit 2; argumento desconocido o faltante exit 1 (missing)" {
  run pg bogus
  [ "$status" -eq 2 ]
  run pg record --bogus x
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
  run pg record --asset-id X --from-phase investigation --to-phase development --engagement "$ENGAGEMENT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--asset-name is required"* ]]
}

@test "phase-gate: sin fichero de reglas usa la tabla por defecto (deployment capitalizable, operation no)" {
  mv "$TMPDIR_CX/rules/capitalization.rules.yaml" "$TMPDIR_CX/rules.bak"
  run rec P012 development deployment
  [[ "$output" == *'"capitalizable_after": "capitalizable"'* ]]
  run rec P013 deployment operation
  [[ "$output" == *'"capitalizable_after": "non-capitalizable"'* ]]
}

@test "phase-gate: el script declara set -uo pipefail" {
  grep -q "^set -uo pipefail" "$PHASE_GATE_SH"
}

@test "phase-gate: engagement sin barra, con dos barras o con espacios se rechaza (invalid)" {
  for e in 'solo-cliente' 'a/b/c' 'a b/c' '/abs'; do
    run pg record --asset-id P014 --asset-name A --from-phase investigation --to-phase development --engagement "$e"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--engagement must be CLIENT/ENGAGEMENT"* ]]
  done
  [ ! -e "$TMPDIR_CX/engagements/solo-cliente" ]
  [ ! -e "$TMPDIR_CX/engagements/a" ]
}
