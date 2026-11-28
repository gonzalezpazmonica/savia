#!/usr/bin/env bats
# tests/test-knowledge-lint.bats
# BATS tests for knowledge-lint.sh (LLM Wiki pattern improvements)
# Inspired by: Karpathy's LLM Wiki gist (2026-04-14)
# Quality gate: SPEC-055 (audit score >=80)
# Safety: set -uo pipefail in target; tests use run/status guards + temp dirs

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/knowledge-lint.sh"
  TMPDIR_MEM=$(mktemp -d)
  mkdir -p "$TMPDIR_MEM"
}
teardown() {
  rm -rf "$TMPDIR_MEM"
}

# ── Script structure ───────────────────────────────────────────────────────

@test "knowledge-lint.sh exists and is executable" {
  [[ -x "$SCRIPT" ]]
}
@test "knowledge-lint.sh uses set -uo pipefail" {
  head -3 "$SCRIPT" | grep -q "set -uo pipefail"
}
@test "knowledge-lint command exists" {
  [[ -f "$REPO_ROOT/.opencode/commands/knowledge-lint.md" ]]
}

# ── Empty memory dir ───────────────────────────────────────────────────────

# Antes este caso esperaba salida 0 y «Nothing to lint»: daba por sano no haber
# revisado nada. La ruta por defecto apuntaba a una carpeta inexistente y el lint
# semanal llevaba semanas sin mirar la memoria (hallazgo P-3, 2026-11-15).
@test "error: nonexistent memory dir fails closed with exit 3 and says nothing was checked" {
  export MEMORY_DIR="$TMPDIR_MEM/no-existe"
  run bash "$SCRIPT"
  [[ "$status" -eq 3 ]]
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"No se ha revisado nada"* ]]
  [[ "$output" != *"HEALTHY"* ]]
}

@test "error: --summary on a nonexistent memory dir also fails closed" {
  export MEMORY_DIR="$TMPDIR_MEM/no-existe"
  run bash "$SCRIPT" --summary
  [[ "$status" -eq 3 ]]
  [[ "$output" != *"HEALTHY"* ]]
}

@test "empty: an existing but empty memory dir is checked and exits 0" {
  export MEMORY_DIR="$TMPDIR_MEM"
  run bash "$SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Items checked"* ]]
}

@test "default dir derives from the repo path, not from a fixed machine path" {
  unset MEMORY_DIR
  local fake_home="$TMPDIR_MEM/home"
  local slug; slug="$(printf '%s' "$REPO_ROOT" | sed 's#[^A-Za-z0-9]#-#g')"
  mkdir -p "$fake_home/.claude/projects/$slug/memory"
  HOME="$fake_home" run bash "$SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"/.claude/projects/$slug/memory"* ]]
}

@test "error: with no MEMORY_DIR and no project memory, the default fails closed" {
  unset MEMORY_DIR
  HOME="$TMPDIR_MEM/home-vacio" run bash "$SCRIPT"
  [[ "$status" -eq 3 ]]
}

@test "the script no longer carries a machine-specific default path" {
  run grep -c 'home-monica-claude' "$SCRIPT"
  [[ "$output" -eq 0 ]]
}

# ── Orphan index detection ─────────────────────────────────────────────────

@test "lint detects orphan index entry" {
  export MEMORY_DIR="$TMPDIR_MEM"
  cat > "$TMPDIR_MEM/MEMORY.md" <<'IDX'
- [Orphan](nonexistent-file.md) — this file does not exist
IDX
  run bash "$SCRIPT"
  [[ "$output" == *"Orphan index entry"* ]]
  [[ "$output" == *"nonexistent-file.md"* ]]
}

# ── Clean state passes ─────────────────────────────────────────────────────

@test "lint passes on clean memory with index" {
  export MEMORY_DIR="$TMPDIR_MEM"
  cat > "$TMPDIR_MEM/test-memory.md" <<'MEM'
---
name: test
description: test memory
type: feedback
evidence_type: sourced
---
Test content.
MEM
  cat > "$TMPDIR_MEM/MEMORY.md" <<'IDX'
- [Test](test-memory.md) — test memory
IDX
  run bash "$SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"HEALTHY"* ]]
}

# ── Missing evidence_type detection ────────────────────────────────────────

@test "lint warns on missing evidence_type" {
  export MEMORY_DIR="$TMPDIR_MEM"
  cat > "$TMPDIR_MEM/no-evidence.md" <<'MEM'
---
name: no evidence
description: missing evidence_type
type: project
---
Content without classification.
MEM
  cat > "$TMPDIR_MEM/MEMORY.md" <<'IDX'
- [No Evidence](no-evidence.md) — missing evidence_type
IDX
  run bash "$SCRIPT"
  [[ "$output" == *"Missing evidence_type"* ]]
}

# ── Unlisted memory detection ──────────────────────────────────────────────

@test "lint warns on unlisted memory file" {
  export MEMORY_DIR="$TMPDIR_MEM"
  cat > "$TMPDIR_MEM/unlisted.md" <<'MEM'
---
name: unlisted
type: feedback
evidence_type: sourced
---
Not in index.
MEM
  cat > "$TMPDIR_MEM/MEMORY.md" <<'IDX'
# Memory Index
IDX
  run bash "$SCRIPT"
  [[ "$output" == *"Unlisted memory file"* ]]
  [[ "$output" == *"unlisted.md"* ]]
}

# ── Oversized index detection ─────────────────────────────────────────────

@test "lint warns when MEMORY.md approaches 200 lines" {
  export MEMORY_DIR="$TMPDIR_MEM"
  # Generate 160-line MEMORY.md
  {
    for i in $(seq 1 160); do
      echo "- [mem${i}](mem${i}.md) — entry $i"
    done
  } > "$TMPDIR_MEM/MEMORY.md"
  run bash "$SCRIPT"
  [[ "$output" == *"approaching 200"* ]]
}

# ── --fix mode ─────────────────────────────────────────────────────────────

@test "lint --fix removes orphan entries from MEMORY.md" {
  export MEMORY_DIR="$TMPDIR_MEM"
  cat > "$TMPDIR_MEM/MEMORY.md" <<'IDX'
- [Real](real.md) — exists
- [Ghost](ghost.md) — does not exist
IDX
  cat > "$TMPDIR_MEM/real.md" <<'MEM'
---
name: real
type: feedback
evidence_type: sourced
---
Real content.
MEM
  run bash "$SCRIPT" --fix
  # Ghost should be removed
  ! grep -q "ghost.md" "$TMPDIR_MEM/MEMORY.md"
  # Real should remain
  grep -q "real.md" "$TMPDIR_MEM/MEMORY.md"
}

# ── Integration: context-rotation weekly calls lint ────────────────────────

@test "context-rotation.sh weekly section references knowledge-lint" {
  grep -q "knowledge-lint" "$REPO_ROOT/scripts/context-rotation.sh"
}

# ── Evidence classification documented in session-memory-protocol ──────────

@test "session-memory-protocol documents evidence_type" {
  grep -q "evidence_type" "$REPO_ROOT/docs/rules/domain/session-memory-protocol.md"
}
@test "session-memory-protocol defines 4 evidence types" {
  local rule="$REPO_ROOT/docs/rules/domain/session-memory-protocol.md"
  grep -q "sourced" "$rule"
  grep -q "analyzed" "$rule"
  grep -q "inferred" "$rule"
  grep -q '`gap`' "$rule"
}

# ── Summary banner ─────────────────────────────────────────────────────────

@test "lint shows Knowledge Lint banner" {
  export MEMORY_DIR="$TMPDIR_MEM"
  mkdir -p "$TMPDIR_MEM"
  cat > "$TMPDIR_MEM/MEMORY.md" <<'IDX'
# Index
IDX
  run bash "$SCRIPT"
  [[ "$output" == *"Knowledge Lint"* ]]
}
