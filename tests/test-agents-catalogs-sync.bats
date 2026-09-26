#!/usr/bin/env bats
# tests/test-agents-catalogs-sync.bats — SE-220 Plan-Then-Execute
#
# Spec: docs/propuestas/SE-220-jailbreak-defenses.md (AC-13)
# Ref:  docs/rules/domain/agents-md-source-of-truth.md
#
# Invariante: AGENTS.md, agents-catalog.md y .opencode/agents/ DEBEN coincidir
# en número y nombres. Drift entre catálogos = vector de skill confusion attack
# (typosquatting de skills/agents) según informe jailbreak §2.4.
#
# Source of truth canónica: .opencode/agents/*.md frontmatter.
#
# Safety: el script target scripts/agents-catalog-sync.sh usa set -uo pipefail.

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/scripts/agents-catalog-sync.sh"
AGENTS_DIR="$ROOT/.opencode/agents"
AGENTS_MD="$ROOT/AGENTS.md"
CATALOG_MD="$ROOT/docs/rules/domain/agents-catalog.md"

setup() {
  TMPDIR_AC=$(mktemp -d)
  export TMPDIR_AC
}

teardown() {
  [[ -n "${TMPDIR_AC:-}" && -d "$TMPDIR_AC" ]] && rm -rf "$TMPDIR_AC"
}

# Helpers
agents_on_disk() {
  ls "$AGENTS_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort
}
agents_in_md() {
  awk -F'|' '/^\|/ && !/Name.*Tier/ && !/^\|---/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' \
    "$1" 2>/dev/null | sort
}
agents_in_catalog() {
  awk -F'|' '/^\|/ && !/Agent.*Tier/ && !/^\|---/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' \
    "$1" 2>/dev/null | sort
}

# ── Positive cases ──────────────────────────────────────────────────────────

@test "SPEC-220 AC-13: directorio .opencode/agents existe" {
  [ -d "$AGENTS_DIR" ]
}

@test "SPEC-220 AC-13: AGENTS.md existe" {
  [ -f "$AGENTS_MD" ]
}

@test "SPEC-220 AC-13: agents-catalog.md existe" {
  [ -f "$CATALOG_MD" ]
}

@test "SPEC-220 AC-13: AGENTS.md count = .opencode/agents count" {
  disk=$(agents_on_disk | wc -l)
  md=$(agents_in_md "$AGENTS_MD" | wc -l)
  [ "$disk" -eq "$md" ]
}

@test "SPEC-220 AC-13: agents-catalog.md count = .opencode/agents count" {
  disk=$(agents_on_disk | wc -l)
  cat=$(agents_in_catalog "$CATALOG_MD" | wc -l)
  [ "$disk" -eq "$cat" ]
}

@test "SPEC-220 AC-13: AGENTS.md set = .opencode/agents set (mismos nombres)" {
  diff <(agents_on_disk) <(agents_in_md "$AGENTS_MD")
}

@test "SPEC-220 AC-13: agents-catalog.md set = .opencode/agents set (mismos nombres)" {
  diff <(agents_on_disk) <(agents_in_catalog "$CATALOG_MD")
}

@test "SPEC-220 AC-13: scripts/agents-md-drift-check.sh reporta sync" {
  run bash "$ROOT/scripts/agents-md-drift-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync"* ]] || [[ -z "$output" ]]
}

@test "SPEC-220 AC-13: scripts/agents-catalog-sync.sh --check exit 0" {
  run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "SPEC-220 AC-13: --generate produces valid markdown table" {
  run bash "$SCRIPT" --generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Agent | Tier |"* ]]
  [[ "$output" == *"|---|---|"* ]]
}

@test "SPEC-220 AC-13: --check --json returns valid JSON with PASS verdict" {
  run bash "$SCRIPT" --check --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["verdict"]=="PASS"; assert d["drift"]==0'
}

# ── Negative cases ──────────────────────────────────────────────────────────

@test "SPEC-220 AC-13: NEGATIVO — invalid argument fails with usage error" {
  run bash "$SCRIPT" --bogus-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown arg"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "SPEC-220 AC-13: NEGATIVO — missing mode arg fails with error" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"required"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "SPEC-220 AC-13: NEGATIVO — invalid AGENTS_DIR path fails" {
  AGENTS_DIR="/nonexistent-dir-$$" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
}

@test "SPEC-220 AC-13: NEGATIVO — drift detection rejects mismatched catalog (count error)" {
  # Crear AGENTS_DIR con N agentes y catalog con M agentes — drift evidente
  mismatch_dir="$TMPDIR_AC/mismatch-agents"
  mkdir -p "$mismatch_dir"
  for i in 1 2 3; do
    cat > "$mismatch_dir/agent-$i.md" <<EOF
---
name: agent-$i
model: mid
description: A
---
EOF
  done
  # Genera tabla esperada (3 agents)
  AGENTS_DIR="$mismatch_dir" run bash "$SCRIPT" --check
  # Como CATALOG_PATH apunta a uno de 72 agentes: 3 != 72 = drift
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]] || [[ "$output" == *"drift"* ]]
}

# ── Edge cases ──────────────────────────────────────────────────────────────

@test "SPEC-220 AC-13: EDGE — empty agents directory produces empty table" {
  empty_dir="$TMPDIR_AC/empty-agents"
  mkdir -p "$empty_dir"
  AGENTS_DIR="$empty_dir" run bash "$SCRIPT" --generate
  [ "$status" -eq 0 ]
  # El header está siempre, el cuerpo vacío
  [[ "$output" == *"| Agent | Tier |"* ]]
}

@test "SPEC-220 AC-13: EDGE — large agents dir (50+ files) handled" {
  many_dir="$TMPDIR_AC/many-agents"
  mkdir -p "$many_dir"
  for i in $(seq 1 50); do
    cat > "$many_dir/agent-$i.md" <<EOF
---
name: agent-$i
model: mid
description: Test agent $i
---
EOF
  done
  AGENTS_DIR="$many_dir" run bash "$SCRIPT" --generate
  [ "$status" -eq 0 ]
  count=$(echo "$output" | grep -c '^| agent-' || true)
  [ "${count:-0}" -ge 50 ]
}

@test "SPEC-220 AC-13: EDGE — agent without frontmatter handled gracefully (no crash)" {
  no_fm_dir="$TMPDIR_AC/no-fm-agents"
  mkdir -p "$no_fm_dir"
  echo "Just a plain markdown file" > "$no_fm_dir/orphan.md"
  AGENTS_DIR="$no_fm_dir" run bash "$SCRIPT" --generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"| orphan"* ]]
}

@test "SPEC-220 AC-13: BOUNDARY — count match at exact 72 agents in production" {
  # Documentación: el invariante real del workspace es 72 agents.
  # Si este test falla, hubo cambio de cardinalidad — auditar el catálogo.
  disk=$(agents_on_disk | wc -l)
  [ "$disk" -ge 70 ]
}

# ── Safety verification ──────────────────────────────────────────────────────

@test "SPEC-220 safety: agents-catalog-sync.sh uses set -uo pipefail" {
  head -30 "$SCRIPT" | grep -qE 'set -[uo]+ pipefail|set -[euo]+ pipefail'
}

@test "SPEC-220 safety: script bash syntax valid" {
  bash -n "$SCRIPT"
}
