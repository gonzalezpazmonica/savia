#!/usr/bin/env bats
# SE-389 §28 — matriz core del evaluador determinista
E="python3 scripts/compliance-eval.py"
P="regulatory/registry/eu-ai-act-art50.yaml"
F="tests/fixtures/compliance/art50-executable-test.yaml"

@test "SE-389: policy no-EXECUTABLE no enforza (UNKNOWN fail-safe §18)" {
  run python3 scripts/compliance-eval.py --policy $P --context tests/fixtures/compliance/ctx-block.json
  [[ "$output" == UNKNOWN* ]]
  [[ "$output" == *"requiere validación humana"* ]]
}

@test "SE-389: EXECUTABLE + disclosure missing + human_facing => BLOCK (§19)" {
  run python3 scripts/compliance-eval.py --policy $F --context tests/fixtures/compliance/ctx-block.json
  [[ "$output" == BLOCK:* ]]
}

@test "SE-389: EXECUTABLE + disclosure performed => ALLOW_WITH_DISCLOSURE" {
  run python3 scripts/compliance-eval.py --policy $F --context tests/fixtures/compliance/ctx-allow.json
  [[ "$output" == ALLOW_WITH_DISCLOSURE:* ]]
}

@test "SE-389: NOT_APPLICABLE fuera de trigger (no human-facing)" {
  run python3 scripts/compliance-eval.py --policy $F --context tests/fixtures/compliance/ctx-napp.json
  [[ "$output" == NOT_APPLICABLE:* ]]
}

@test "SE-389: UNKNOWN fail-safe (human_facing desconocido + unknowns críticos)" {
  run python3 scripts/compliance-eval.py --policy $F --context tests/fixtures/compliance/ctx-unknown.json
  [[ "$output" == UNKNOWN:* ]]
}

@test "SE-389: receipt enlaza policy+context_hash (§7/§16)" {
  $E --policy $F --context tests/fixtures/compliance/ctx-allow.json --receipt-out /tmp/se389-receipt.json >/dev/null
  jq -e '.receipt_type=="compliance_receipt" and .policy_versions[0].id=="EU-AIA-ART50-TEST-FIXTURE" and .context_hash' /tmp/se389-receipt.json >/dev/null
}

@test "SE-389: monotonía — UNKNOWN/BLOCK jamás degradan a ALLOW (§10/§31)" {
  run python3 scripts/compliance-eval.py --policy $F --context tests/fixtures/compliance/ctx-block.json
  [[ "$output" != ALLOW* ]]
}

# ── S03u: comportamiento que los mutantes demostraron sin cubrir ─────────────

ctx() { printf '%s' "$1" > "$BATS_TEST_TMPDIR/ctx.json"; echo "$BATS_TEST_TMPDIR/ctx.json"; }

@test "SE-389: an actor role outside the trigger is NOT_APPLICABLE even if disclosure is missing" {
  run python3 scripts/compliance-eval.py --policy $F --context "$(ctx '{"actor":{"role":"importer"},"interaction":{"human_facing":true},"human_oversight":{"disclosure_performed":false}}')"
  [ "$status" -eq 0 ]
  [[ "$output" == NOT_APPLICABLE:*"actor_role=importer"* ]]
}

@test "SE-389: a context without actor is evaluated (fail-safe), not skipped" {
  run python3 scripts/compliance-eval.py --policy $F --context "$(ctx '{"interaction":{"human_facing":true},"human_oversight":{"disclosure_performed":false}}')"
  [ "$status" -eq 0 ]
  [[ "$output" == BLOCK:* ]]
}

@test "SE-389: a critical unknown wins over a performed disclosure" {
  run python3 scripts/compliance-eval.py --policy $F --context "$(ctx '{"actor":{"role":"deployer"},"interaction":{"human_facing":true},"human_oversight":{"disclosure_performed":true},"unknowns":[{"field":"x","action":"BLOCK"}]}')"
  [ "$status" -eq 0 ]
  [[ "$output" == "UNKNOWN: unknowns críticos sin resolver"* ]]
}

@test "SE-389: a non-critical unknown does not block an allowed disclosure" {
  run python3 scripts/compliance-eval.py --policy $F --context "$(ctx '{"actor":{"role":"deployer"},"interaction":{"human_facing":true},"human_oversight":{"disclosure_performed":true},"unknowns":[{"field":"x","action":"LOG"}]}')"
  [ "$status" -eq 0 ]
  [[ "$output" == ALLOW_WITH_DISCLOSURE:* ]]
}

@test "SE-389: a malformed unknowns entry fails safe to UNKNOWN without a traceback" {
  run python3 scripts/compliance-eval.py --policy $F --context "$(ctx '{"actor":{"role":"deployer"},"interaction":{"human_facing":true},"human_oversight":{"disclosure_performed":true},"unknowns":["BLOCK"]}')"
  [ "$status" -eq 0 ]
  [[ "$output" == UNKNOWN:* ]]
  [[ "$output" != *Traceback* ]]
}

@test "SE-389: without PyYAML the policy is unreadable and the result is UNKNOWN, never a crash" {
  mkdir -p "$BATS_TEST_TMPDIR/noyaml"
  printf 'raise ImportError("simulado")\n' > "$BATS_TEST_TMPDIR/noyaml/yaml.py"
  PYTHONPATH="$BATS_TEST_TMPDIR/noyaml" run python3 scripts/compliance-eval.py --policy $F --context tests/fixtures/compliance/ctx-allow.json
  [ "$status" -eq 0 ]
  [[ "$output" == "UNKNOWN: policy ilegible"* ]]
  [[ "$output" != *Traceback* ]]
}

@test "SE-389: a malformed policy YAML is UNKNOWN, never ALLOW" {
  printf 'policy_id: X\nstatus: EXECUTABLE\ntrigger: [provider\n' > "$BATS_TEST_TMPDIR/bad.yaml"
  run python3 scripts/compliance-eval.py --policy "$BATS_TEST_TMPDIR/bad.yaml" --context tests/fixtures/compliance/ctx-allow.json
  [ "$status" -eq 0 ]
  [[ "$output" == "UNKNOWN: policy ilegible"* ]]
}

@test "SE-389: a policy whose trigger is not a mapping is UNKNOWN" {
  printf 'policy_id: X\nstatus: EXECUTABLE\ntrigger: provider\n' > "$BATS_TEST_TMPDIR/flat.yaml"
  run python3 scripts/compliance-eval.py --policy "$BATS_TEST_TMPDIR/flat.yaml" --context tests/fixtures/compliance/ctx-allow.json
  [ "$status" -eq 0 ]
  [[ "$output" == "UNKNOWN: policy ilegible"* ]]
}

@test "SE-389: --context is required (exit 2)" {
  run python3 scripts/compliance-eval.py --policy $F
  [ "$status" -eq 2 ]
}

@test "SE-389: receipt is written where asked, stdout is the same JSON decision and the hash is canonical" {
  c="$(ctx '{"actor":{"role":"deployer"},"interaction":{"human_facing":true},"human_oversight":{"disclosure_performed":true},"nota":"señal"}')"
  run python3 scripts/compliance-eval.py --policy $F --context "$c" --receipt-out "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 0 ]
  run python3 - "$output" "$BATS_TEST_TMPDIR/r.json" "$c" <<'PY'
import hashlib, json, sys
out, rec, ctx = json.loads(sys.argv[1]), json.load(open(sys.argv[2])), json.load(open(sys.argv[3]))
h = hashlib.sha256(json.dumps(ctx, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
assert out["result"] == rec["decision"]["result"] == "ALLOW_WITH_DISCLOSURE", (out, rec)
assert out["context_hash"] == rec["context_hash"] == h, (out["context_hash"], h)
PY
  [ "$status" -eq 0 ]
}

@test "SE-389: without --json or --receipt-out the output is one plain verdict line" {
  run python3 scripts/compliance-eval.py --policy $F --context tests/fixtures/compliance/ctx-block.json
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "BLOCK: "*"[EU-AIA-ART50-TEST-FIXTURE v1]" ]]
}
