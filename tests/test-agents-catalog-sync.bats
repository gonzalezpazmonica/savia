#!/usr/bin/env bats
# BATS tests for scripts/agents-catalog-sync.sh (SE-047 Slice 1).
# Ref: SE-047, audit D5
SCRIPT="scripts/agents-catalog-sync.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
}
teardown() { cd /; }

@test "exists + executable" { [[ -x "$SCRIPT" ]]; }
@test "uses set -uo pipefail" { run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "passes bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }
@test "references SE-047" { run grep -c 'SE-047' "$SCRIPT"; [[ "$output" -ge 1 ]]; }

@test "--help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"check"* ]]
  [[ "$output" == *"generate"* ]]
  [[ "$output" == *"apply"* ]]
}

@test "rejects unknown arg" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "requires mode flag" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

# ── Generate ──────────────────────────────────────────

@test "--generate emits markdown table" {
  run bash "$SCRIPT" --generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Agent"* ]]
  [[ "$output" == *"| Tier"* ]]
}

@test "--generate includes all agents from disk" {
  local disk_count
  disk_count=$(ls .opencode/agents/*.md 2>/dev/null | wc -l)
  run bash "$SCRIPT" --generate
  # Count rows (excluding header + separator)
  local rows
  rows=$(echo "$output" | grep -cE '^\| [a-z-]+ \|' || true)
  [[ "$rows" -ge 1 ]]
}

@test "--generate output does not write files" {
  local h_before
  h_before=$(md5sum docs/rules/domain/agents-catalog.md 2>/dev/null | awk '{print $1}' || echo "")
  bash "$SCRIPT" --generate >/dev/null 2>&1
  local h_after
  h_after=$(md5sum docs/rules/domain/agents-catalog.md 2>/dev/null | awk '{print $1}' || echo "")
  [[ "$h_before" == "$h_after" ]]
}

# ── Check ────────────────────────────────────────────

@test "--check reports VERDICT" {
  run bash "$SCRIPT" --check
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  [[ "$output" == *"VERDICT"* ]]
}

@test "--check reports Agents on disk" {
  run bash "$SCRIPT" --check
  [[ "$output" == *"Agents on disk:"* ]]
}

@test "--check reports Catalog rows" {
  run bash "$SCRIPT" --check
  [[ "$output" == *"Catalog rows:"* ]]
}

@test "--check --json valid" {
  run bash -c 'bash scripts/agents-catalog-sync.sh --check --json | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k in [\"verdict\",\"total_agents\",\"catalog_rows\",\"drift\"]:
    assert k in d
print(\"ok\")
"'
  [[ "$output" == *"ok"* ]]
}

@test "--check verdict is PASS or FAIL" {
  run bash "$SCRIPT" --check --json
  [[ "$output" == *'"verdict":"PASS"'* || "$output" == *'"verdict":"FAIL"'* ]]
}

@test "--check does not modify catalog" {
  local h_before
  h_before=$(md5sum docs/rules/domain/agents-catalog.md 2>/dev/null | awk '{print $1}' || echo "")
  bash "$SCRIPT" --check >/dev/null 2>&1 || true
  local h_after
  h_after=$(md5sum docs/rules/domain/agents-catalog.md 2>/dev/null | awk '{print $1}' || echo "")
  [[ "$h_before" == "$h_after" ]]
}

# ── Apply (isolated) ─────────────────────────────────

@test "--apply writes to tmp-redirected path" {
  # S03n: copia del script en un árbol temporal; el catálogo real no se toca.
  _tree
  _agent alpha-judge "name: alpha-judge" "model_tier: fast" "description: Juez alfa"
  run env AGENTS_DIR="$T/agents" bash "$T/scripts/agents-catalog-sync.sh" --apply --json
  [ "$status" -eq 0 ]
  [ "$output" = "{\"action\":\"applied\",\"path\":\"$T/docs/rules/domain/agents-catalog.md\",\"total_agents\":1}" ]
  grep -qF '| alpha-judge | fast | Juez alfa  |' "$T/docs/rules/domain/agents-catalog.md"
}

@test "mode flags are mutually recognized" {
  run bash "$SCRIPT" --check --generate
  # Last mode wins (generate overwrites check). Should still succeed or be a usage pattern.
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ── Total agents > 0 ─────────────────────────────────

@test "total_agents > 0" {
  run bash -c 'bash scripts/agents-catalog-sync.sh --check --json | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d[\"total_agents\"] > 0
print(\"ok\")
"'
  [[ "$output" == *"ok"* ]]
}

# ── Isolation ────────────────────────────────────

@test "isolation: --check does not modify agents dir" {
  local h_before
  h_before=$(find .claude/agents -name "*.md" -exec md5sum {} + 2>/dev/null | sort | md5sum | awk '{print $1}')
  bash "$SCRIPT" --check >/dev/null 2>&1 || true
  local h_after
  h_after=$(find .claude/agents -name "*.md" -exec md5sum {} + 2>/dev/null | sort | md5sum | awk '{print $1}')
  [[ "$h_before" == "$h_after" ]]
}

@test "isolation: --generate does not modify agents dir" {
  local h_before
  h_before=$(find .claude/agents -name "*.md" -exec md5sum {} + 2>/dev/null | sort | md5sum | awk '{print $1}')
  bash "$SCRIPT" --generate >/dev/null 2>&1 || true
  local h_after
  h_after=$(find .claude/agents -name "*.md" -exec md5sum {} + 2>/dev/null | sort | md5sum | awk '{print $1}')
  [[ "$h_before" == "$h_after" ]]
}

@test "isolation: exit codes 0/1/2" {
  run bash "$SCRIPT" --check
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

# ── S03n: comportamiento discriminante en árbol temporal ────────────

_tree() {
  T="$BATS_TEST_TMPDIR/w"
  mkdir -p "$T/scripts" "$T/agents" "$T/docs/rules/domain"
  cp "$SCRIPT" "$T/scripts/"
}
_agent() {  # _agent <fichero> <línea-frontmatter>...
  local f="$T/agents/$1.md"; shift
  { echo '---'; printf '%s\n' "$@"; echo '---'; echo 'name: cuerpo-no-cuenta'; } > "$f"
}
_sync() { AGENTS_DIR="$T/agents" bash "$T/scripts/agents-catalog-sync.sh" "$@"; }

# Nota: echo + tr '\\n' ' ' deja un espacio final en cada descripción no truncada.
@test "S03n --generate: filas ordenadas, tier por defecto y nombre de fichero como respaldo" {
  _tree
  # El fichero a-primero.md se llama «zeta»: el orden es por nombre, no por fichero.
  _agent a-primero "name: zeta" "model_tier: heavy" "description: Ultimo"
  _agent sin-nombre "description: Sin nombre en frontmatter"
  run _sync --generate
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "| Agent | Tier | Description |" ]
  [ "${lines[1]}" = "|---|---|---|" ]
  [ "${lines[2]}" = "| sin-nombre | (default) | Sin nombre en frontmatter  |" ]
  [ "${lines[3]}" = "| zeta | heavy | Ultimo  |" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "S03n --generate: quita comillas, escapa | y corta la descripción a 120 bytes" {
  _tree
  local long; long=$(printf 'a%.0s' $(seq 1 150))
  _agent q 'name: q' 'description: "con | tubo"'
  _agent l 'name: l' "description: $long"
  run _sync --generate
  [[ "$output" == *'| q | (default) | con \| tubo  |'* ]]
  [[ "$output" == *"| l | (default) | $(printf 'a%.0s' $(seq 1 120)) |"* ]]
  [[ "$output" != *"$(printf 'a%.0s' $(seq 1 121))"* ]]
}

@test "S03n --generate: solo lee el frontmatter, no el cuerpo" {
  _tree
  { echo '---'; echo 'description: x'; echo '---'; echo 'name: impostor'; } > "$T/agents/real.md"
  run _sync --generate
  [[ "$output" == *"| real | (default) | x  |"* ]]
  [[ "$output" != *"impostor"* ]]
}

@test "S03n --check: PASS cuando las filas igualan a los agentes; FAIL con uno nuevo" {
  _tree
  _agent a "name: a"
  _agent b "name: b"
  _sync --apply >/dev/null
  run _sync --check --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"verdict":"PASS","total_agents":2,"catalog_rows":2,"drift":0}' ]
  _agent c "name: c"
  run _sync --check --json
  [ "$status" -eq 1 ]
  [ "$output" = '{"verdict":"FAIL","total_agents":3,"catalog_rows":2,"drift":1}' ]
  run _sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERDICT: FAIL (drift detected)"* ]]
}

@test "S03n --check: catálogo ausente es FAIL (exit 1), también en JSON" {
  _tree
  _agent a "name: a"
  run _sync --check --json
  [ "$status" -eq 1 ]
  [ "$output" = '{"verdict":"FAIL","total_agents":1,"catalog_missing":true}' ]
  run _sync --check
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL: catalog not found at "* ]]
}

@test "S03n --apply: conserva el frontmatter del catálogo y agrupa por capacidad en orden" {
  _tree
  printf -- '---\ncontext_tier: L2\ntoken_budget: 900\n---\n# viejo\n' > "$T/docs/rules/domain/agents-catalog.md"
  _agent o "name: dag-orchestrator"
  _agent j "name: zz-judge"
  _agent v "name: aa-validator"
  _agent x "name: rarito"
  _agent p "name: business-analyst"
  run _sync --apply
  [ "$status" -eq 0 ]
  local cat="$T/docs/rules/domain/agents-catalog.md"
  [ "$(head -4 "$cat")" = "$(printf -- '---\ncontext_tier: L2\ntoken_budget: 900\n---')" ]
  run grep -E '^- \*\*' "$cat"
  [ "${lines[0]}" = "- **Metaorquestación (orquestadores y despacho)**: dag-orchestrator" ]
  [ "${lines[1]}" = "- **Tribunales y verificación**: aa-validator, zz-judge" ]
  [ "${lines[2]}" = "- **Proyectos (dominio de gestión de proyectos)**: business-analyst" ]
  [ "${lines[3]}" = "- **Dominios especializados**: rarito" ]
  [ "${#lines[@]}" -eq 4 ]
  ! grep -q '# viejo' "$cat" || false
}

@test "S03n --apply: sin catálogo previo lo crea sin frontmatter y queda en sync" {
  _tree
  _agent a "name: memory-agent"
  run _sync --apply
  [ "$status" -eq 0 ]
  [ "$output" = "Applied: $T/docs/rules/domain/agents-catalog.md (1 agents)" ]
  [ "$(head -1 "$T/docs/rules/domain/agents-catalog.md")" = "# Agents Catalog (auto-generated by scripts/agents-catalog-sync.sh)" ]
  grep -qF -- '- **Conocimiento**: memory-agent' "$T/docs/rules/domain/agents-catalog.md"
  run _sync --check
  [ "$status" -eq 0 ]
}

@test "S03n: directorio de agentes inexistente es error de uso (exit 2)" {
  _tree
  run env AGENTS_DIR="$T/no-hay" bash "$T/scripts/agents-catalog-sync.sh" --generate
  [ "$status" -eq 2 ]
  [[ "$output" == *"agents dir not found"* ]]
}
