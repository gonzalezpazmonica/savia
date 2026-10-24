#!/usr/bin/env bats

# Ref: docs/specs/SE-400-model-agnostic-ablation-minimal-kernel.spec.md (F2/F3)
setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  python3 scripts/ablation_graphs.py generate --out "$BATS_FILE_TMPDIR/report" >/dev/null
  python3 scripts/ablation_kernel.py run --out "$BATS_FILE_TMPDIR/report" >/dev/null || true
}

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  TMP=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP"
}

@test "SE-400 F2/F3 scripts and configs exist" {
  [ -x scripts/ablation_graphs.py ]
  [ -x scripts/ablation_kernel.py ]
  [ -f config/kernel-candidate.json ]
  [ -f config/kernel-corpus.json ]
}

@test "SE-400 F2/F3 unit and fixture tests pass" {
  run python3 -m unittest tests/test_ablation_kernel.py
  [ "$status" -eq 0 ]
}

@test "SE-400 F2 generate then check is FRESH on the repository" {
  run python3 scripts/ablation_graphs.py check --out "$BATS_FILE_TMPDIR/report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABLATION-F2: FRESH"* ]]
}

@test "SE-400 F2 check reports STALE when the stored revision differs" {
  cp "$BATS_FILE_TMPDIR/report/f2-graphs.json" "$TMP/"
  python3 - "$TMP/f2-graphs.json" <<'EOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["report_revision"] = "0" * 64
json.dump(data, open(path, "w"))
EOF
  run python3 scripts/ablation_graphs.py check --out "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
}

@test "SE-400 F2 hook matrix covers every settings registration" {
  run python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); s=json.load(open(".claude/settings.json"))
n=sum(len(g["hooks"]) for gs in s["hooks"].values() for g in gs)
print(len(r["hook_matrix"]), n); assert len(r["hook_matrix"]) == n' "$BATS_FILE_TMPDIR/report/f2-graphs.json"
  [ "$status" -eq 0 ]
}

@test "SE-400 F3 plan reports the accidental pack dependency" {
  run python3 scripts/ablation_kernel.py plan
  [ "$status" -eq 0 ]
  [[ "$output" == *'"pack_dependencies"'* ]]
  [[ "$output" == *"pm-sdd-legacy"* ]]
}

@test "SE-400 F3 receipt on the repository has zero false allows and a bound hash" {
  run python3 -c 'import json,re,sys; r=json.load(open(sys.argv[1]))
assert r["invariants"]["false_allows"] == 0, r["verdicts"]
assert re.fullmatch("[0-9a-f]{64}", r["receipt_sha256"])
assert r["model_invocations"] == 0
assert r["vector"]["kernel"]["files"] < r["vector"]["full"]["files"]
print(r["decision"])' "$BATS_FILE_TMPDIR/report/f3-kernel-receipt.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ABORT"* ]]
}

@test "SE-400 F3 refuses to materialize inside the repository" {
  run python3 -c 'import sys; sys.path.insert(0, "scripts")
import ablation_kernel as k
from pathlib import Path
k.ensure_isolated(Path("."), Path("output/kernel-probe"))'
  [ "$status" -ne 0 ]
  [[ "$output" == *"DEST_NOT_ISOLATED"* ]]
}
