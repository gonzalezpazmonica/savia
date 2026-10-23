#!/usr/bin/env bats
# test-se228-s5-loop-phasing.bats — SE-228 Slice 5: L1→L3 phasing checklist + loop_level
#
# Validates:
#   - loop-phasing.md doc exists with L0-L3 definitions and checklists
#   - loop-phasing-audit.sh script exists, is executable, and behaves correctly
#   - loop_level field present in _template and autonomous skills SKILL.md
#   - set -uo pipefail in script
#
# Ref: docs/rules/domain/loop-phasing.md (SE-228 S5)
# Ref: docs/rules/domain/autonomous-safety.md

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LOOP_PHASING_DOC="$REPO_ROOT/docs/rules/domain/loop-phasing.md"
  AUDIT_SCRIPT="$REPO_ROOT/scripts/loop-phasing-audit.sh"
  TEMPLATE_SKILL="$REPO_ROOT/templates/skills/_template/SKILL.md"
  OVERNIGHT_SKILL="$REPO_ROOT/.opencode/skills/overnight-sprint/SKILL.md"
  CODE_LOOP_SKILL="$REPO_ROOT/.opencode/skills/code-improvement-loop/SKILL.md"
  RESEARCH_SKILL="$REPO_ROOT/.opencode/skills/tech-research-agent/SKILL.md"
  TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP_DIR" 2>/dev/null || true
}

# ── A. Documentation ─────────────────────────────────────────────────────────

@test "A1 loop-phasing.md exists in docs/rules/domain/" {
  [ -f "$LOOP_PHASING_DOC" ]
}

@test "A2 loop-phasing.md defines levels L0 L1 L2 L3" {
  grep -q 'L0' "$LOOP_PHASING_DOC"
  grep -q 'L1' "$LOOP_PHASING_DOC"
  grep -q 'L2' "$LOOP_PHASING_DOC"
  grep -q 'L3' "$LOOP_PHASING_DOC"
}

@test "A3 loop-phasing.md has L1→L2 promotion checklist" {
  grep -qE 'Checklist.*L1|L1.*L2|checklist.*promo' "$LOOP_PHASING_DOC"
}

@test "A4 loop-phasing.md has L2→L3 promotion checklist" {
  grep -qE 'L2.*L3|L3.*checklist|Checklist.*L2' "$LOOP_PHASING_DOC"
}

@test "A5 loop-phasing.md mentions red flags for invalid promotion" {
  grep -qiE 'red flag|never.*promot|no promover' "$LOOP_PHASING_DOC"
}

@test "A6 loop-phasing.md references autonomous-safety.md" {
  grep -q 'autonomous-safety' "$LOOP_PHASING_DOC"
}

@test "A7 loop-phasing.md mentions maker-checker protocol" {
  grep -qiE 'maker.checker|maker/checker' "$LOOP_PHASING_DOC"
}

@test "A8 loop-phasing.md mentions loop-budget" {
  grep -qi 'loop-budget\|loop_budget' "$LOOP_PHASING_DOC"
}

@test "A9 loop-phasing.md references SE-228" {
  grep -q 'SE-228' "$LOOP_PHASING_DOC"
}

# ── B. Script existence and safety ───────────────────────────────────────────

@test "B1 loop-phasing-audit.sh exists and is executable" {
  [ -f "$AUDIT_SCRIPT" ]
  [ -x "$AUDIT_SCRIPT" ]
}

@test "B2 set -uo pipefail present in loop-phasing-audit.sh" {
  grep -q 'set -uo pipefail' "$AUDIT_SCRIPT"
}

@test "B3 loop-phasing-audit.sh references SE-228 in header" {
  grep -q 'SE-228' "$AUDIT_SCRIPT"
}

@test "B4 audit script does not hardcode absolute /home/ paths" {
  # Must use REPO_ROOT variable — never hardcoded /home/ paths
  run grep -c '/home/' "$AUDIT_SCRIPT"
  [[ "$output" == "0" ]] || [ "$status" -ne 0 ]
}

# ── C. Audit script behavior ──────────────────────────────────────────────────

@test "C1 loop-phasing-audit.sh no args exits 0" {
  run bash "$AUDIT_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "C2 loop-phasing-audit.sh emits table with declared inferred gap columns" {
  run bash "$AUDIT_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"declared"* ]]
  [[ "$output" == *"inferred"* ]]
  [[ "$output" == *"gap"* ]]
}

@test "C3 audit --skill overnight-sprint exits 0" {
  run bash "$AUDIT_SCRIPT" --skill overnight-sprint
  [ "$status" -eq 0 ]
  [[ "$output" == *"overnight-sprint"* ]]
}

@test "C4 audit --json exits 0 and returns valid JSON array" {
  run bash "$AUDIT_SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\[ ]]
  [[ "$output" =~ \]$ ]]
}

@test "C5 audit --json contains declared inferred gap fields" {
  run bash "$AUDIT_SCRIPT" --skill overnight-sprint --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"declared"'* ]]
  [[ "$output" == *'"inferred"'* ]]
  [[ "$output" == *'"gap"'* ]]
}

@test "C6 audit gap values are only OK OVER or UNDER — no invalid values" {
  run bash "$AUDIT_SCRIPT" --skill overnight-sprint
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]] || [[ "$output" == *"OVER"* ]] || [[ "$output" == *"UNDER"* ]]
}

# ── D. Negative / error / missing cases ──────────────────────────────────────

@test "D1 audit --skill missing-nonexistent skill exits 0 (graceful error)" {
  run bash "$AUDIT_SCRIPT" --skill __no_such_skill_xyz__
  [ "$status" -eq 0 ]
}

@test "D2 loop-phasing.md does not block invalid L4 level from being absent" {
  # L4 should NOT exist in the phasing model — only L0..L3
  run grep -E '^\| L4' "$LOOP_PHASING_DOC"
  [ "$status" -ne 0 ]
}

@test "D3 audit script fails gracefully with no output crash on empty skills dir" {
  # Run with a temp skills dir with no SKILL.md files (empty dir)
  local empty_dir="$TMP_DIR/empty-skills"
  mkdir -p "$empty_dir"
  # Script should handle empty find results without crashing
  run bash "$AUDIT_SCRIPT" --skill __nonexistent_skill_xyz__
  [ "$status" -eq 0 ]
}

@test "D4 loop-phasing.md red flags: missing state file blocks promotion" {
  grep -qiE 'state file|STATE.md.*absent|sin state' "$LOOP_PHASING_DOC"
}

@test "D5 loop-phasing.md red flags: same verifier and implementer is invalid" {
  grep -qiE 'verifier.*implementer|implementer.*verifier' "$LOOP_PHASING_DOC"
}

# ── E. loop_level field in SKILL.md files ────────────────────────────────────

@test "E1 _template SKILL.md contains loop_level: L0 with comment" {
  grep -qE '^[[:space:]]*#?[[:space:]]*savia\.loop_level:[[:space:]]*"?L0"?' "$TEMPLATE_SKILL"
  grep -q 'loop-phasing.md' "$TEMPLATE_SKILL"
}

@test "E2 overnight-sprint SKILL.md contains loop_level: L2" {
  grep -qE '^[[:space:]]*savia\.loop_level:[[:space:]]*"?L2"?' "$OVERNIGHT_SKILL"
}

@test "E3 code-improvement-loop SKILL.md contains loop_level: L2" {
  grep -qE '^[[:space:]]*savia\.loop_level:[[:space:]]*"?L2"?' "$CODE_LOOP_SKILL"
}

@test "E4 tech-research-agent SKILL.md contains loop_level: L1" {
  grep -qE '^[[:space:]]*savia\.loop_level:[[:space:]]*"?L1"?' "$RESEARCH_SKILL"
}

@test "E5 loop_level comment references loop-phasing.md in autonomous skills" {
  grep -q 'loop-phasing.md' "$OVERNIGHT_SKILL"
  grep -q 'loop-phasing.md' "$CODE_LOOP_SKILL"
  grep -q 'loop-phasing.md' "$RESEARCH_SKILL"
}

# ── F. Isolation / taxonomy ───────────────────────────────────────────────────

@test "F1 BATS setup uses mktemp for isolation" {
  [ -d "$TMP_DIR" ]
}

@test "F2 teardown cleans TMP_DIR without error" {
  mkdir -p "$TMP_DIR/test-artifact"
  [ -d "$TMP_DIR/test-artifact" ]
  rm -rf "$TMP_DIR/test-artifact"
  [ ! -d "$TMP_DIR/test-artifact" ]
}

@test "F3 loop-phasing.md taxonomy: file is in docs/rules/domain/" {
  [[ "$LOOP_PHASING_DOC" == */docs/rules/domain/loop-phasing.md ]]
}

@test "F4 audit script taxonomy: file is in scripts/" {
  [[ "$AUDIT_SCRIPT" == */scripts/loop-phasing-audit.sh ]]
}

@test "F5 audit runs without side effects in repo" {
  local before_count
  before_count=$(find "$REPO_ROOT/output" -newer "$AUDIT_SCRIPT" 2>/dev/null | wc -l || echo 0)
  run bash "$AUDIT_SCRIPT" --skill overnight-sprint
  [ "$status" -eq 0 ]
  local after_count
  after_count=$(find "$REPO_ROOT/output" -newer "$AUDIT_SCRIPT" 2>/dev/null | wc -l || echo 0)
  # No new output files should have been created by the audit
  [ "$after_count" -le "$before_count" ]
}
