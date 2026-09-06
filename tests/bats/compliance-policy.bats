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
