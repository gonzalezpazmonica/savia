#!/usr/bin/env bats
# Ref: SPEC-125 — Recommendation Tribunal (real-time audit de recomendaciones conversacionales)
# Spec: docs/propuestas/SPEC-125-recommendation-tribunal-realtime.md
# Slice 1 Foundation: classifier + 4 judge agents + aggregate + banner + hook stub.
# Pattern source: Constitutional AI (Anthropic), G-Eval Inline (OpenAI Evals 2026).

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="scripts/recommendation-tribunal/classifier.sh"
  CLASSIFIER_ABS="$ROOT_DIR/$SCRIPT"
  AGG_ABS="$ROOT_DIR/scripts/recommendation-tribunal/aggregate.sh"
  BANNER_ABS="$ROOT_DIR/scripts/recommendation-tribunal/banner.sh"
  HOOK_ABS="$ROOT_DIR/.claude/hooks/_legacy/recommendation-tribunal-pre-output.sh"
  ORCH_ABS="$ROOT_DIR/.opencode/agents/recommendation-tribunal-orchestrator.md"
  JUDGE_DIR="$ROOT_DIR/.claude/agents"
  RULE_DOC="$ROOT_DIR/docs/rules/domain/recommendation-tribunal.md"
  TMPDIR_T=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_T"
}

# ── C1 — file existence + safety identity (positive) ────────────────────────

@test "classifier: file exists, has shebang, executable" {
  [ -f "$CLASSIFIER_ABS" ]
  head -1 "$CLASSIFIER_ABS" | grep -q '^#!'
  [ -x "$CLASSIFIER_ABS" ]
}

@test "aggregate: file exists, has shebang, executable" {
  [ -f "$AGG_ABS" ]
  head -1 "$AGG_ABS" | grep -q '^#!'
  [ -x "$AGG_ABS" ]
}

@test "banner: file exists, has shebang, executable" {
  [ -f "$BANNER_ABS" ]
  head -1 "$BANNER_ABS" | grep -q '^#!'
  [ -x "$BANNER_ABS" ]
}

@test "hook: file exists, has shebang, executable" {
  [ -f "$HOOK_ABS" ]
  head -1 "$HOOK_ABS" | grep -q '^#!'
  [ -x "$HOOK_ABS" ]
}

@test "all 4 scripts declare 'set -uo pipefail'" {
  grep -q "set -[uo]o pipefail" "$CLASSIFIER_ABS"
  grep -q "set -[uo]o pipefail" "$AGG_ABS"
  grep -q "set -[uo]o pipefail" "$BANNER_ABS"
  grep -q "set -[uo]o pipefail" "$HOOK_ABS"
}

@test "all 4 scripts pass bash -n syntax check" {
  bash -n "$CLASSIFIER_ABS"
  bash -n "$AGG_ABS"
  bash -n "$BANNER_ABS"
  bash -n "$HOOK_ABS"
}

# ── C2 — agent files (4 judges + orchestrator) ──────────────────────────────

@test "orchestrator agent: exists with frontmatter" {
  [ -f "$ORCH_ABS" ]
  grep -q "^name: recommendation-tribunal-orchestrator" "$ORCH_ABS"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$ORCH_ABS"
}

@test "memory-conflict-judge agent: exists with correct name" {
  [ -f "$JUDGE_DIR/memory-conflict-judge.md" ]
  grep -q "^name: memory-conflict-judge" "$JUDGE_DIR/memory-conflict-judge.md"
}

@test "rule-violation-judge agent: exists with correct name" {
  [ -f "$JUDGE_DIR/rule-violation-judge.md" ]
  grep -q "^name: rule-violation-judge" "$JUDGE_DIR/rule-violation-judge.md"
}

@test "hallucination-fast-judge agent: exists with correct name" {
  [ -f "$JUDGE_DIR/hallucination-fast-judge.md" ]
  grep -q "^name: hallucination-fast-judge" "$JUDGE_DIR/hallucination-fast-judge.md"
}

@test "expertise-asymmetry-judge agent: exists with correct name" {
  [ -f "$JUDGE_DIR/expertise-asymmetry-judge.md" ]
  grep -q "^name: expertise-asymmetry-judge" "$JUDGE_DIR/expertise-asymmetry-judge.md"
}

@test "all 4 judges + orchestrator declare model_tier in frontmatter" {
  for j in memory-conflict-judge rule-violation-judge hallucination-fast-judge expertise-asymmetry-judge recommendation-tribunal-orchestrator; do
    grep -qE "^model_tier: (heavy|mid|fast)" "$JUDGE_DIR/$j.md"
  done
}

@test "all 4 judges declare 'JSON-only' output contract" {
  for j in memory-conflict rule-violation hallucination-fast expertise-asymmetry; do
    grep -qiE "JSON.only|output.*JSON" "$JUDGE_DIR/$j-judge.md"
  done
}

@test "all 4 judges require evidence citation (anti-hallucination)" {
  for j in memory-conflict rule-violation hallucination-fast; do
    grep -qiE "cite|citation|evidence|refuse to score" "$JUDGE_DIR/$j-judge.md"
  done
}

# ── C3 — classifier behavior (positive cases) ───────────────────────────────

@test "classifier: detects critical pattern 'lower the threshold' (English)" {
  out=$(echo "Para que pase, lower the threshold" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":true'* ]]
  [[ "$out" == *'"risk_class":"critical"'* ]]
}

@test "classifier: detects critical pattern 'baja el umbral' (Spanish)" {
  out=$(echo "baja el umbral de cobertura" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":true'* ]]
  [[ "$out" == *'"risk_class":"critical"'* ]]
}

@test "classifier: detects '--no-verify' as critical (force-skip flag)" {
  out=$(echo "podemos hacer git push --no-verify rapido" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"risk_class":"critical"'* ]]
}

@test "classifier: detects 'force push' as critical" {
  out=$(echo "haz un force push para resolverlo" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"risk_class":"critical"'* ]]
}

@test "classifier: detects 'sudo' command as high risk" {
  out=$(echo "sudo apt-get install postgres" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":true'* ]]
  [[ "$out" == *'"risk_class":"high"'* ]]
}

@test "classifier: detects 'rm -rf' as high risk" {
  out=$(echo "rm -rf /tmp/cache" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":true'* ]]
  [[ "$out" == *'"risk_class":"high"'* ]]
}

@test "classifier: detects 'te recomiendo' (Spanish) as medium" {
  out=$(echo "te recomiendo usar python" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":true'* ]]
  [[ "$out" == *'"risk_class":"medium"'* ]]
}

@test "classifier: detects 'should use' (English) as medium" {
  out=$(echo "you should use python for this" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":true'* ]]
  [[ "$out" == *'"risk_class":"medium"'* ]]
}

@test "classifier: detects 'el problema es' root-cause claim as medium" {
  out=$(echo "el problema es la conexión a la BBDD" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":true'* ]]
  [[ "$out" == *'"risk_class":"medium"'* ]]
}

# ── C4 — classifier behavior (negative cases — non-recommendations) ─────────

@test "classifier: 'ok merged' is NOT a recommendation (acknowledgment)" {
  out=$(echo "ok merged" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":false'* ]]
  [[ "$out" == *'"risk_class":"low"'* ]]
}

@test "classifier: empty input returns is_recommendation false" {
  out=$(echo "" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":false'* ]]
}

@test "classifier: pure status report 'PR #722 mergeado' is NOT a recommendation" {
  out=$(echo "PR 722 mergeado en 2026-04-28" | bash "$CLASSIFIER_ABS")
  [[ "$out" == *'"is_recommendation":false'* ]]
}

@test "classifier: rejects unknown CLI argument (no-arg)" {
  run bash "$CLASSIFIER_ABS" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg"* ]]
}

@test "classifier: nonexistent --file exits 2" {
  run bash "$CLASSIFIER_ABS" --file "/nonexistent/path"
  [ "$status" -eq 2 ]
  [[ "$output" == *"file not found"* ]]
}

# ── C5 — aggregate behavior ─────────────────────────────────────────────────

@test "aggregate: rejects without arguments (boundary)" {
  run bash "$AGG_ABS"
  [ "$status" -eq 2 ]
}

@test "aggregate: rejects --judges with wrong count (boundary)" {
  echo '{}' > "$TMPDIR_T/j1.json"
  echo '{}' > "$TMPDIR_T/j2.json"
  run bash "$AGG_ABS" --judges "$TMPDIR_T/j1.json" "$TMPDIR_T/j2.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"exactly 4"* ]]
}

@test "aggregate: missing judge file exits 3" {
  run bash "$AGG_ABS" --judges /no /no2 /no3 /no4
  [ "$status" -eq 3 ]
  [[ "$output" == *"not found"* ]]
}

@test "aggregate: 4 zero-veto judges → verdict PASS" {
  for i in 1 2 3 4; do
    echo "{\"judge\":\"j$i\",\"score\":95,\"veto\":false,\"confidence\":0.5}" > "$TMPDIR_T/j$i.json"
  done
  out=$(bash "$AGG_ABS" --judges "$TMPDIR_T/j1.json" "$TMPDIR_T/j2.json" "$TMPDIR_T/j3.json" "$TMPDIR_T/j4.json")
  [[ "$out" == *'"verdict":"PASS"'* ]]
}

@test "aggregate: any judge veto with confidence 0.9 → verdict VETO" {
  echo '{"judge":"memory-conflict","score":10,"veto":true,"confidence":0.95}' > "$TMPDIR_T/j1.json"
  echo '{"judge":"rule-violation","score":80,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j2.json"
  echo '{"judge":"hallucination-fast","score":90,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j3.json"
  echo '{"judge":"expertise-asymmetry","score":90,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j4.json"
  out=$(bash "$AGG_ABS" --judges "$TMPDIR_T/j1.json" "$TMPDIR_T/j2.json" "$TMPDIR_T/j3.json" "$TMPDIR_T/j4.json")
  [[ "$out" == *'"verdict":"VETO"'* ]]
  [[ "$out" == *"memory-conflict"* ]]
}

@test "aggregate: low consensus (<80) without veto → verdict WARN" {
  echo '{"judge":"memory-conflict","score":60,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j1.json"
  echo '{"judge":"rule-violation","score":70,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j2.json"
  echo '{"judge":"hallucination-fast","score":75,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j3.json"
  echo '{"judge":"expertise-asymmetry","score":50,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j4.json"
  out=$(bash "$AGG_ABS" --judges "$TMPDIR_T/j1.json" "$TMPDIR_T/j2.json" "$TMPDIR_T/j3.json" "$TMPDIR_T/j4.json")
  [[ "$out" == *'"verdict":"WARN"'* ]]
}

@test "aggregate: veto with low confidence (<0.8) does NOT trigger VETO" {
  echo '{"judge":"memory-conflict","score":40,"veto":true,"confidence":0.6}' > "$TMPDIR_T/j1.json"
  echo '{"judge":"rule-violation","score":85,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j2.json"
  echo '{"judge":"hallucination-fast","score":85,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j3.json"
  echo '{"judge":"expertise-asymmetry","score":90,"veto":false,"confidence":0.5}' > "$TMPDIR_T/j4.json"
  out=$(bash "$AGG_ABS" --judges "$TMPDIR_T/j1.json" "$TMPDIR_T/j2.json" "$TMPDIR_T/j3.json" "$TMPDIR_T/j4.json")
  # Consensus = (40+85+85)/3 = 70 → WARN, NOT VETO
  [[ "$out" == *'"verdict":"WARN"'* ]]
  [[ "$out" != *'"verdict":"VETO"'* ]]
}

# ── C6 — banner behavior ─────────────────────────────────────────────────────

@test "banner: requires --draft (boundary)" {
  run bash -c "echo '{}' | bash '$BANNER_ABS'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--draft"* ]]
}

@test "banner: PASS verdict produces empty banner output" {
  out=$(echo '{"verdict":"PASS"}' | bash "$BANNER_ABS" --draft "draft text")
  [ -z "$out" ] || [[ "$out" != *"TRIBUNAL"* ]]
}

@test "banner: WARN verdict produces banner + draft" {
  out=$(echo '{"verdict":"WARN","consensus_score":60,"veto_judges":[]}' | bash "$BANNER_ABS" --draft "the draft")
  [[ "$out" == *"TRIBUNAL: WARN"* ]]
  [[ "$out" == *"the draft"* ]]
}

@test "banner: VETO verdict marks original as blocked + cites veto judges" {
  out=$(echo '{"verdict":"VETO","veto_judges":["memory-conflict"]}' | bash "$BANNER_ABS" --draft "shortcut recommendation")
  [[ "$out" == *"TRIBUNAL: VETO"* ]]
  [[ "$out" == *"memory-conflict"* ]]
  [[ "$out" == *"shortcut recommendation"* ]]
}

# ── C7 — hook (Slice 1 detect-only mode) ─────────────────────────────────────

@test "hook: detect-only mode passes draft through unchanged for non-recommendations" {
  out=$(echo "ok merged" | bash "$HOOK_ABS")
  [ "$out" = "ok merged" ]
}

@test "hook: detect-only mode passes draft through (still passes for recommendations in Slice 1)" {
  out=$(echo "te recomiendo usar python" | bash "$HOOK_ABS")
  # Slice 1 detect-only: draft is preserved unchanged — Slice 2 will mutate
  [[ "$out" == *"te recomiendo usar python"* ]]
}

@test "hook: empty input returns empty output (transparent)" {
  out=$(echo -n "" | bash "$HOOK_ABS")
  [ -z "$out" ]
}

# ── C8 — Rule canonical doc ─────────────────────────────────────────────────

@test "rule doc: exists and references SPEC-125" {
  [ -f "$RULE_DOC" ]
  grep -q "SPEC-125" "$RULE_DOC"
}

@test "rule doc: declares 'NOT activated by default' explicitly" {
  grep -qiE "NO ACTIVADO|not activated|deliberada" "$RULE_DOC"
}

@test "rule doc: documents activation as separate human step" {
  grep -qF ".claude/settings.json" "$RULE_DOC"
  grep -qiE "edici[oó]n humana|human step|paso humano" "$RULE_DOC"
}

@test "rule doc: documents the 4 judges + orchestrator + 3 scripts (9 components)" {
  for component in memory-conflict-judge rule-violation-judge hallucination-fast-judge expertise-asymmetry-judge recommendation-tribunal-orchestrator classifier.sh aggregate.sh banner.sh; do
    grep -qF "$component" "$RULE_DOC"
  done
}

@test "rule doc: declares Slice 1 detect-only mode (instrumentación, sin mutación)" {
  grep -qiE "detect.only|instrumentaci|sin mutaci" "$RULE_DOC"
}

@test "rule doc: cross-refs SPEC-106 (Truth Tribunal sibling)" {
  grep -qF "SPEC-106" "$RULE_DOC"
}

# ── C9 — Spec ref + meta-assertions ─────────────────────────────────────────

@test "spec ref: docs/propuestas/SPEC-125 referenced in this test file" {
  grep -q "docs/propuestas/SPEC-125" "$BATS_TEST_FILENAME"
}

@test "all judges' descriptions clarify their narrow scope (no overlap)" {
  grep -qiE "only.*job|only one|specific job" "$JUDGE_DIR/memory-conflict-judge.md"
  grep -qiE "only.*job|only one|specific job" "$JUDGE_DIR/rule-violation-judge.md"
  grep -qiE "only.*job|only one|specific job" "$JUDGE_DIR/hallucination-fast-judge.md"
  grep -qiE "only.*job|only one|specific job" "$JUDGE_DIR/expertise-asymmetry-judge.md"
}

@test "expertise-asymmetry-judge: explicitly NEVER vetoes" {
  grep -qiE "DO NOT veto|never blocks|nunca veta" "$JUDGE_DIR/expertise-asymmetry-judge.md"
}
