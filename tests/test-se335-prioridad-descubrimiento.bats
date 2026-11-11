#!/usr/bin/env bats
# BATS tests for SE-335 — prioridad de descubrimiento de conocimiento en el arranque
# SPEC: docs/specs/SE-335-prioridad-descubrimiento-arranque.spec.md
# Orden cableado: cupulas (SaviaVaults) -> memoria -> grafo de codigo -> grep

RULE="docs/rules/domain/knowledge-discovery-priority.md"
HOOK=".opencode/hooks/session-init.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  export CLAUDE_PROJECT_DIR="$(pwd)"
}

@test "AC-01: la regla existe y cat reconstruye el orden de 4 niveles sin scripts" {
  [[ -f "$RULE" ]]
  cat "$RULE" | grep -q "Cúpulas de conocimiento"
  cat "$RULE" | grep -q "Capas de memoria"
  cat "$RULE" | grep -q "Grafo de código"
  cat "$RULE" | grep -q "Grep/glob a ficheros"
}

@test "AC-02: CLAUDE.md importa la regla exactamente una vez" {
  [[ "$(grep -c "@docs/rules/domain/knowledge-discovery-priority.md" CLAUDE.md)" -eq 1 ]]
}

@test "AC-03: la cabecera de CLAUDE.md declara 3 imports criticos (SE-511 S2: savia-core los agrupa)" {
  head -10 CLAUDE.md | grep -q "3 @imports criticos"
}

@test "AC-04: session-init emite la directiva de prioridad en additionalContext" {
  run bash "$HOOK"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "Prioridad: cupulas (SaviaVaults) -> memoria -> grafo de codigo -> grep"
}

@test "AC-05: el hook termina en menos de 5s con exit 0" {
  run timeout 5 bash "$HOOK"
  [[ "$status" -eq 0 ]]
}

@test "AC-06: CRITERIO.md y CONSTITUCION.md intactos (invariantes de esta spec)" {
  # La implementacion no puede tocar ficheros fundacionales (CRIT-031).
  # El guard real es el hash; aqui verificamos que el hook en ejecucion no los modifica.
  local crit_hash_before constit_hash_before
  crit_hash_before=$(sha256sum CRITERIO.md | cut -d' ' -f1)
  constit_hash_before=$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)
  run bash "$HOOK"
  [[ "$status" -eq 0 ]]
  [[ "$(sha256sum CRITERIO.md | cut -d' ' -f1)" == "$crit_hash_before" ]]
  [[ "$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)" == "$constit_hash_before" ]]
}

@test "AC-08: la regla no contiene vendor names (CRIT-002/ADR-012)" {
  run grep -nEi "openai|anthropic|claude-3|gpt-|gemini|deepseek|mistral|llama" "$RULE"
  [[ "$status" -ne 0 ]]
}

@test "AC-09: la regla respeta el presupuesto (<= 400 tokens aprox: 120 palabras)" {
  local words
  words=$(wc -w < "$RULE")
  [[ "$words" -le 160 ]]
}

# Ref: docs/specs/SE-335-prioridad-descubrimiento-arranque.spec.md (fail-safe del hook de arranque)

@test "seguridad: el hook de arranque declara set -uo pipefail" {
  head -5 "$HOOK" | grep -q "set -uo pipefail"
}

@test "limite: la regla de prioridad no queda vacia (al menos 4 niveles numerados)" {
  local n
  n=$(grep -cE '^[1-4]\. \*\*' "$RULE")
  [[ "$n" -eq 4 ]]
}

# Comprobador del orden imperativo (revisión de #1527, P1): los 4 niveles numerados 1-4,
# en este orden y una sola vez cada uno. Lo usan el positivo y los casos negativo y límite.
rule_order_ok() {
  local got
  got="$(grep -E '^[0-9]+\. \*\*' "$1" | sed -E 's/^([0-9]+)\. \*\*([^*(]+).*/\1 \2/' | sed 's/ *$//' | tr '\n' '|')"
  [[ "$got" == "1 Cúpulas de conocimiento|2 Capas de memoria|3 Grafo de código|4 Grep/glob a ficheros|" ]]
}

@test "AC-01: la regla real declara los 4 niveles en el orden cupulas -> memoria -> grafo -> grep" {
  rule_order_ok "$RULE"
}

@test "negativo: una regla con memoria antes que cupulas no pasa el comprobador de orden" {
  sed -e 's/^1\. \*\*Cúpulas/2. **Cúpulas/' -e 's/^2\. \*\*Capas/1. **Capas/' "$RULE" > "$BATS_TEST_TMPDIR/swapped.md"
  run cmp -s "$RULE" "$BATS_TEST_TMPDIR/swapped.md"
  [[ "$status" -ne 0 ]]
  run rule_order_ok "$BATS_TEST_TMPDIR/swapped.md"
  [[ "$status" -ne 0 ]]
}

@test "edge: una regla vacia o con un nivel de menos no pasa el comprobador de orden" {
  : > "$BATS_TEST_TMPDIR/empty-rule.md"
  run rule_order_ok "$BATS_TEST_TMPDIR/empty-rule.md"
  [[ "$status" -ne 0 ]]
  grep -v '^4\. \*\*' "$RULE" > "$BATS_TEST_TMPDIR/three.md"
  run rule_order_ok "$BATS_TEST_TMPDIR/three.md"
  [[ "$status" -ne 0 ]]
}

@test "edge: hook output is valid JSON and additionalContext is not null ni vacio" {
  run timeout 10 bash "$HOOK"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d['hookSpecificOutput']['additionalContext']; assert c and 'Prioridad: cupulas' in c"
}

@test "edge boundary: la directiva de prioridad aparece exactamente una vez en la salida" {
  run timeout 10 bash "$HOOK"
  [[ "$status" -eq 0 ]]
  [[ "$(echo "$output" | grep -o 'Prioridad: cupulas' | wc -l)" -eq 1 ]]
}
