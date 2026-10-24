#!/usr/bin/env bats

# Ref: docs/specs/SE-400-model-agnostic-ablation-minimal-kernel.spec.md (F1)
setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  TMP=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP"
}

@test "SE-400 F1 contract and inventory script exist" {
  [ -x scripts/ablation_inventory.py ]
  [ -f config/ablation-contract.json ]
}

@test "SE-400 F1 unit and fixture contract tests pass" {
  run python3 -m unittest tests/test_ablation_inventory.py
  [ "$status" -eq 0 ]
}

@test "SE-400 F1 generate then check is FRESH on the repository" {
  run python3 scripts/ablation_inventory.py generate --out "$TMP"
  [ "$status" -eq 0 ]
  [ -s "$TMP/f1-inventory.json" ]
  [ -s "$TMP/f1-inventory.md" ]
  run python3 scripts/ablation_inventory.py check --out "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABLATION-F1: FRESH"* ]]
}

@test "SE-400 F1 check reports STALE when the stored revision differs" {
  python3 scripts/ablation_inventory.py generate --out "$TMP" >/dev/null
  python3 - "$TMP/f1-inventory.json" <<'EOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["report_revision"] = "0" * 64
json.dump(data, open(path, "w"))
EOF
  run python3 scripts/ablation_inventory.py check --out "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
}

@test "SE-400 F1 report never emits receipt-gated essentiality" {
  run python3 scripts/ablation_inventory.py summary
  [ "$status" -eq 0 ]
  [[ "$output" != *"CORE_ESSENTIAL"* ]]
  [[ "$output" != *"REDUNDANT_CANDIDATE"* ]]
  [[ "$output" != *"\"DEAD\""* ]]
}
