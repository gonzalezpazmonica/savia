#!/usr/bin/env bats

# Ref: docs/specs/SE-400-model-agnostic-ablation-minimal-kernel.spec.md (F1)
setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  python3 scripts/ablation_inventory.py generate --out "$BATS_FILE_TMPDIR/report" >/dev/null
}

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
  [ -s "$BATS_FILE_TMPDIR/report/f1-inventory.json" ]
  [ -s "$BATS_FILE_TMPDIR/report/f1-inventory.md" ]
  run python3 scripts/ablation_inventory.py check --out "$BATS_FILE_TMPDIR/report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABLATION-F1: FRESH"* ]]
}

@test "SE-400 F1 check reports STALE when the stored revision differs" {
  cp "$BATS_FILE_TMPDIR/report/f1-inventory.json" "$TMP/"
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
  run python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["summary"]; print(sorted(s["by_essentiality"]))' \
    "$BATS_FILE_TMPDIR/report/f1-inventory.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" != *"CORE_"* ]]
  [[ "$output" != *"MERGE_CANDIDATE"* ]]
  [[ "$output" != *"REDUNDANT_CANDIDATE"* ]]
  [[ "$output" != *"'DEAD'"* ]]
}
