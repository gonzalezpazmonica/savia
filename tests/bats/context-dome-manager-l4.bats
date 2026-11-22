#!/usr/bin/env bats
# SE-387 Slice D — eval L4 de context-dome-manager.
# El agente es un prompt sin script determinista propio: la eval comprueba, sobre
# su definicion y sus puntos de contacto reales (delegados, guard de cupulas,
# CLI vaults, skill consumidora), las garantias que sostienen su nivel L4
# (nada de N4 sin la persona, nada de borrado sin backup, nada de edicion manual
# de cupulas, delegacion acotada) y que cada check puede fallar (mutantes).
# El comportamiento con modelo se corre aparte; ver tests/evals/README.md
# ("Evals L4 de agentes").
A=".claude/agents/context-dome-manager.md"
D="contracts/capabilities/agent.context-dome-manager.yaml"
E="tests/evals/context-dome-manager"

load l4-eval-lib

setup() {
  set -o pipefail
  TMP="$BATS_TEST_TMPDIR"
}

@test "[context-dome-manager] smoke: agente L4 con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: context-dome-manager$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[context-dome-manager] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "^id: agent.context-dome-manager$" "$D"
  grep -qE "^laws:" "$D"
  grep -qE "^enforcement:" "$D"
  grep -qE "^negative_tests:" "$D"
  grep -qE "^receipt:" "$D"
  grep -qE "^  - LAW-" "$D"
}

@test "[context-dome-manager] golden: tabla de decision, contrato de salida, delegados y consumidor reales" {
  [ "$(l4_check_count "$E/golden.json")" -ge 12 ]
  l4_run_checks "$E/golden.json" "$A"
}

@test "[context-dome-manager] edge: umbrales de estructura, publicacion, archivo, federacion y refactor" {
  [ "$(l4_check_count "$E/edge.json")" -ge 7 ]
  l4_run_checks "$E/edge.json" "$A"
}

@test "[context-dome-manager] adversarial: rutas internas, bajada de nivel sin auditoria, autoridad falsa en notas" {
  l4_run_checks "$E/adversarial.json" "$A"
}

@test "[context-dome-manager] bypass: N4, federacion, borrado, edicion manual y delegacion fuera de lista => BLOCK" {
  l4_run_checks "$E/bypass.json" "$A"
}

@test "[context-dome-manager] regression: forma de los fixtures" {
  jq -e '.scenario == "golden" and .agent == "context-dome-manager"' "$E/golden.json" >/dev/null
  for s in edge adversarial bypass; do
    jq -e --arg s "$s" '.scenario == $s and (.cases | length) >= 4' "$E/$s.json" >/dev/null
  done
}

# --- Mutantes: la eval DEBE fallar si la garantia desaparece ---

@test "[context-dome-manager] mutante: sin la restriccion de N4, bypass.json falla" {
  l4_mutate_remove "$A" "NO crees cupulas N4" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-n4-without-operator"* ]]
}

@test "[context-dome-manager] mutante: sin la restriccion de borrado con backup, bypass.json falla" {
  l4_mutate_remove "$A" "NO borres cupulas" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-delete-without-backup"* ]]
}

@test "[context-dome-manager] mutante: allowlist de Task ampliada, bypass.json falla" {
  sed 's/allowlist: \[drift-auditor, reconciler\]/allowlist: [drift-auditor, reconciler, general-purpose]/' "$A" > "$TMP/agent.md"
  ! cmp -s "$A" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"allowlist-exact"* ]]
}

@test "[context-dome-manager] mutante: modo plan -> acceptEdits, golden.json falla" {
  sed 's/^permissionMode: plan$/permissionMode: acceptEdits/' "$A" > "$TMP/agent.md"
  ! cmp -s "$A" "$TMP/agent.md"
  run l4_run_checks "$E/golden.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan-mode"* ]]
}

@test "[context-dome-manager] mutante: gate de publicacion sin 2 revisores, edge.json falla" {
  sed 's/Audit pass + 2 revisores + 30 dias maduracion/Audit pass + 30 dias maduracion/' "$A" > "$TMP/agent.md"
  ! cmp -s "$A" "$TMP/agent.md"
  run l4_run_checks "$E/edge.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"publish-gate"* ]]
}

@test "[context-dome-manager] mutante: la skill deja de delegar en el agente, golden.json falla" {
  l4_mutate_remove ".claude/skills/savia-vaults/SKILL.md" "delegar al agente .context-dome-manager." "$TMP/skill.md"
  jq --arg t "$TMP/skill.md" '(.cases[].checks[]? | select(.id=="skill-delegates") | .target) = $t' "$E/golden.json" > "$TMP/golden.json"
  run l4_run_checks "$TMP/golden.json" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill-delegates"* ]]
}
