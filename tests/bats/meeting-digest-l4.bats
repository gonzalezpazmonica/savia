#!/usr/bin/env bats
# SE-387 Slice D — eval L4 de meeting-digest.
# El agente es un prompt sin script determinista: la eval comprueba, sobre su
# definicion y la de sus dos delegados, las garantias que sostienen su nivel L4
# (Task solo a dos jueces, sin Bash, lo confidencial nunca a ficheros, el
# analista de riesgos nunca ve lo confidencial) y que cada check puede fallar
# (mutantes). El comportamiento con modelo se corre aparte; ver
# tests/evals/README.md ("Evals L4 de agentes").
A=".claude/agents/meeting-digest.md"
D="contracts/capabilities/agent.meeting-digest.yaml"
E="tests/evals/meeting-digest"

load l4-eval-lib

setup() {
  set -o pipefail
  TMP="$BATS_TEST_TMPDIR"
}

@test "[meeting-digest] smoke: agente L4 con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: meeting-digest$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[meeting-digest] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "^id: agent.meeting-digest$" "$D"
  grep -qE "^laws:" "$D"
  grep -qE "^enforcement:" "$D"
  grep -qE "^negative_tests:" "$D"
  grep -qE "^receipt:" "$D"
  grep -qE "^  - LAW-" "$D"
}

@test "[meeting-digest] golden: cadena de fases, delegados existentes y formato de salida" {
  [ "$(l4_check_count "$E/golden.json")" -ge 14 ]
  l4_run_checks "$E/golden.json" "$A"
}

@test "[meeting-digest] edge: limites de seccion confidencial, umbrales ASR y marcadores" {
  [ "$(l4_check_count "$E/edge.json")" -ge 10 ]
  l4_run_checks "$E/edge.json" "$A"
}

@test "[meeting-digest] adversarial: sujeto del perfil, aislamiento del analista, delegados de solo lectura" {
  l4_run_checks "$E/adversarial.json" "$A"
}

@test "[meeting-digest] bypass: confidencial nunca a ficheros, Task acotada, sin Bash, memoria por proyecto" {
  l4_run_checks "$E/bypass.json" "$A"
}

@test "[meeting-digest] regression: forma de los fixtures" {
  jq -e '.scenario == "golden" and .agent == "meeting-digest"' "$E/golden.json" >/dev/null
  for s in edge adversarial bypass; do
    jq -e --arg s "$s" '.scenario == $s and (.cases | length) >= 4' "$E/$s.json" >/dev/null
  done
}

# --- Mutantes: la eval DEBE fallar si la garantia desaparece ---

@test "[meeting-digest] mutante: se anade Bash a las herramientas, bypass.json falla" {
  awk '{print} /^  - Edit$/ && !d {print "  - Bash"; d=1}' "$A" > "$TMP/agent.md"
  ! cmp -s "$A" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-bash-tool"* ]]
}

@test "[meeting-digest] mutante: allowlist de Task ampliada a otro agente, bypass.json falla" {
  sed 's/allowlist: \[meeting-confidentiality-judge, meeting-risk-analyst\]/allowlist: [meeting-confidentiality-judge, meeting-risk-analyst, general-purpose]/' "$A" > "$TMP/agent.md"
  ! cmp -s "$A" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task-allowlist-values"* ]]
}

@test "[meeting-digest] mutante: sin la prohibicion de confidencial en .md, bypass.json falla" {
  l4_mutate_remove "$A" "NUNCA en ficheros \\.md" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"never-in-md"* ]]
}

@test "[meeting-digest] mutante: el analista de riesgos pasa a ver datos confidenciales, adversarial.json falla" {
  l4_mutate_remove "$A" "El risk-analyst NUNCA ve datos confidenciales" "$TMP/agent.md"
  run l4_run_checks "$E/adversarial.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"risk-never-sees-confidential"* ]]
}

@test "[meeting-digest] mutante: el analista de riesgos gana Bash, adversarial.json falla" {
  awk '{print} /^  - Grep$/ && !d {print "  - Bash"; d=1}' .claude/agents/meeting-risk-analyst.md > "$TMP/risk.md"
  ! cmp -s .claude/agents/meeting-risk-analyst.md "$TMP/risk.md"
  jq --arg t "$TMP/risk.md" '(.cases[].checks[]? | select(.id=="risk-analyst-read-only-no-bash") | .target) = $t' "$E/adversarial.json" > "$TMP/adv.json"
  run l4_run_checks "$TMP/adv.json" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"risk-analyst-read-only-no-bash"* ]]
}

@test "[meeting-digest] mutante: sin el umbral de resolucion ASR, edge.json falla" {
  l4_mutate_remove "$A" "50-79% marcado" "$TMP/agent.md"
  run l4_run_checks "$E/edge.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"asr-thresholds"* ]]
}
