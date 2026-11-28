#!/usr/bin/env bats
# tests/test-python-c-path-argv-family.bats — barrido Python (pendientes, 2026-11-27)
# Familia de la fila 21 del informe: rutas interpoladas como literal Python
# dentro de python3 -c "... open('$X') ...". Con una comilla en la ruta (un
# checkout en un directorio con «'», un $HOME raro) el código se rompe o se
# ejecuta. Las rutas van por argv.
# Ref: docs/evidence/barridos/20261127-barrido-python.md

FAMILY=(
  scripts/ci-select-bats.sh scripts/context-erosion-detect.sh scripts/kg-export.sh
  scripts/kg-query.sh scripts/memory-check.sh scripts/lib/enterprise-helpers.sh
  scripts/opencode-config-validate.sh scripts/permissions-wildcard-audit.sh
  scripts/pr-plan-gates.sh scripts/rule-manifest-generate.sh scripts/federation-discover.sh
  scripts/corporate-adopt.sh scripts/corporate-monotonicity-gate.sh
  projects/savia-vaults/scripts/vaults
)

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  T="$(mktemp -d)"
}

teardown() {
  [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"
}

@test "ningún script de la familia interpola una ruta dentro de open()/connect() de python3 -c" {
  run grep -nE "(open|connect)\('\\$" "${FAMILY[@]}"
  [ "$status" -eq 1 ]
}

@test "todos los scripts de la familia pasan bash -n" {
  for f in "${FAMILY[@]}"; do
    run bash -n "$f"
    [ "$status" -eq 0 ]
  done
}

@test "enterprise-helpers: manifiesto en ruta con comilla se lee y el módulo no se interpola" {
  local d="$T/it's"
  mkdir -p "$d/.claude/enterprise"
  echo '{"version":"9.9","modules":{"a":{"enabled":true}}}' > "$d/.claude/enterprise/manifest.json"
  run bash -c 'CLAUDE_PROJECT_DIR="$1"; source scripts/lib/enterprise-helpers.sh; enterprise_version; enterprise_mode; enterprise_enabled a && echo A-ON' _ "$d"
  [[ "$output" == *"9.9"* ]]
  [[ "$output" == *"enterprise"* ]]
  [[ "$output" == *"A-ON"* ]]
  run bash -c 'CLAUDE_PROJECT_DIR="$1"; source scripts/lib/enterprise-helpers.sh; enterprise_enabled "$2"' _ "$d" "x',{}).get('a',{}) or __import__('pathlib').Path('$T/pwn-ent').touch() or {}).get('"
  [ ! -e "$T/pwn-ent" ]
}
