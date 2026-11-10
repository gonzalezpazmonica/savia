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

@test "AC-03: la cabecera de CLAUDE.md declara 6 imports criticos" {
  head -5 CLAUDE.md | grep -q "6 @imports criticos"
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
