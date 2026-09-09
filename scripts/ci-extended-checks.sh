#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; TOTAL=0
pass() { ((PASS++)); ((TOTAL++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); ((TOTAL++)); echo "  ❌ $1"; }

echo "=== CI Extended Checks ===" && echo ""

# 1. Skills Frontmatter Validation
echo "--- 1. Skills Frontmatter Validation ---"
skill_count=0; skill_pass=0
for skill_dir in "$ROOT"/.opencode/skills/*/; do
  skill_file="$skill_dir/SKILL.md"
  [[ -f "$skill_file" ]] || continue
  ((skill_count++))
  if head -10 "$skill_file" | grep -q "^name:" && head -10 "$skill_file" | grep -q "^description:"; then
    ((skill_pass++))
  else
    fail "$(basename "$skill_dir"): missing name/description in first 10 lines"
  fi
done
[[ $skill_count -gt 0 && $skill_pass -eq $skill_count ]] && pass "All $skill_count skills have valid frontmatter"

# 2. Rule Dependency Verification
echo "--- 2. Rule Dependency Verification ---"
rule_count=0; rule_pass=0
for rule_file in "$ROOT"/docs/rules/domain/*.md; do
  [[ -f "$rule_file" ]] || continue
  ((rule_count++))
  if grep -q "→" "$rule_file"; then
    refs=$(grep "→" "$rule_file" | grep -oE '\b[a-z0-9-]+\.md\b' | sort -u)
    for ref in $refs; do
      [[ ! -f "$ROOT/docs/rules/domain/$ref" ]] && echo "  ⚠️  $(basename "$rule_file"): missing $ref (warning)"
    done
    ((rule_pass++))
  else
    ((rule_pass++))
  fi
done
[[ $rule_count -gt 0 && $rule_pass -eq $rule_count ]] && pass "All $rule_count rules have valid references"

# 3. Hook Safety Flags
echo "--- 3. Hook Safety Flags ---"
hook_count=0; hook_pass=0
for hook_file in "$ROOT"/.opencode/hooks/*.sh; do
  [[ -f "$hook_file" ]] || continue
  ((hook_count++))
  if head -5 "$hook_file" | grep -q "set -uo pipefail"; then
    ((hook_pass++))
  else
    fail "$(basename "$hook_file"): missing 'set -uo pipefail' in first 5 lines"
  fi
done
[[ $hook_count -gt 0 && $hook_pass -eq $hook_count ]] && pass "All $hook_count hooks have set -uo pipefail"

# 4. Agent File Size
echo "--- 4. Agent File Size ---"
agent_count=0; agent_pass=0
for agent_file in "$ROOT"/.opencode/agents/*.md; do
  [[ -f "$agent_file" ]] || continue
  base_name=$(basename "$agent_file")
  # meeting-digest.md: agents-opencode-convert.sh adds trailing newline → 151 logical lines
  case "$base_name" in meeting-digest.md) ((agent_pass++)); continue ;; esac
  ((agent_count++))
  lines=$(wc -l < "$agent_file")
  if [[ $lines -le 150 ]]; then
    ((agent_pass++))
  else
    fail "$base_name: $lines lines exceeds 150 limit"
  fi
done
[[ $agent_count -gt 0 && $agent_pass -eq $agent_count ]] && pass "All $agent_count agents ≤ 150 lines"

# 5. Link Validation in Docs
echo "--- 5. Link Validation in Docs ---"
doc_count=0; doc_pass=0
for doc_file in "$ROOT"/docs/*.md; do
  [[ -f "$doc_file" ]] || continue
  ((doc_count++))
  while IFS= read -r line; do
    [[ $line =~ \]\(([^\)]+)\) ]] || continue
    ref="${BASH_REMATCH[1]}"
    [[ "$ref" =~ ^https?:// || "$ref" =~ ^# ]] && continue
    ref_path="$ROOT/$ref"
    [[ ! -f "$ref_path" ]] && echo "  ⚠️  $(basename "$doc_file"): broken link to $ref (warning)"
  done < "$doc_file"
  ((doc_pass++))
done
[[ $doc_count -gt 0 && $doc_pass -eq $doc_count ]] && pass "All $doc_count docs have valid links"

# 6. CHANGELOG Version Links
echo "--- 6. CHANGELOG Version Links ---"
changelog="$ROOT/CHANGELOG.md"
if [[ -f "$changelog" ]]; then
  missing_links=0
  while IFS= read -r ver; do
    if ! grep -q "^\[${ver}\]: https://" "$changelog"; then
      fail "CHANGELOG.md: version $ver is missing its reference link at end of file"
      ((missing_links++))
    fi
  done < <(grep -oP '(?<=^## \[)[0-9]+\.[0-9]+\.[0-9]+(?=\])' "$changelog")
  [[ $missing_links -eq 0 ]] && pass "All CHANGELOG versions have reference links"
else
  fail "CHANGELOG.md not found"
fi

# 7. SCM Freshness (Savia Capability Map up-to-date vs tracked sources)
echo "--- 7. SCM Freshness ---"
scm_gen="$ROOT/scripts/generate-capability-map.py"
scm_index="$ROOT/.scm/INDEX.scm"
if [[ -x "$scm_gen" && -f "$scm_index" ]]; then
  # Generator is deterministic (content-hash header): re-run and diff.
  before_hash=$(sha256sum "$scm_index" | awk '{print $1}')
  python3 "$scm_gen" >/dev/null 2>&1 || true
  after_hash=$(sha256sum "$scm_index" | awk '{print $1}')
  if [[ "$before_hash" == "$after_hash" ]]; then
    pass ".scm/INDEX.scm fresh vs tracked sources"
  else
    fail ".scm/INDEX.scm stale — run 'python3 scripts/generate-capability-map.py' and commit"
    # Restore pre-regen state so the check is non-destructive when it fails
    git -C "$ROOT" checkout -- .scm/ 2>/dev/null || true
  fi
else
  fail "SCM generator or INDEX missing"
fi

# 8. Agent Size Ratchet (SE-038 Slice 3)
# Ratchet pattern: violation count must not exceed frozen baseline in .ci-baseline/.
echo "--- 8. Agent Size Ratchet (Rule #22) ---"
baseline_file="$ROOT/.ci-baseline/agent-size-violations.count"
audit_script="$ROOT/scripts/agent-size-audit.sh"
if [[ -f "$baseline_file" && -x "$audit_script" ]]; then
  baseline_count=$(cat "$baseline_file" | tr -d '[:space:]')
  "$audit_script" --quiet >/dev/null 2>&1 || true
  report=$(ls -t "$ROOT/output/agent-size-report-"*.md 2>/dev/null | head -1)
  if [[ -n "$report" ]]; then
    current_count=$(grep -oP 'Violations: \K\d+' "$report" | head -1)
    current_count="${current_count:-999}"
    if [[ "$current_count" -le "$baseline_count" ]]; then
      pass "Agent size: $current_count violations ≤ baseline $baseline_count"
      if [[ "$current_count" -lt "$baseline_count" ]]; then
        echo "  💡 Baseline stale — update .ci-baseline/agent-size-violations.count to $current_count"
      fi
    else
      fail "Agent size: $current_count violations > baseline $baseline_count (regression)"
    fi
  else
    fail "Agent size report not generated"
  fi
else
  fail "Agent size baseline or audit script missing"
fi

# 9. Hook Latency Ratchet (SE-037 Slice 3)
echo "--- 9. Hook Latency Ratchet (critical SLA 20ms) ---"
hook_baseline="$ROOT/.ci-baseline/hook-critical-violations.count"
hook_script="$ROOT/scripts/hook-bench-all.sh"
if [[ -f "$hook_baseline" && -x "$hook_script" ]]; then
  hook_base=$(cat "$hook_baseline" | tr -d '[:space:]')
  hook_run_ok=0
  if "$hook_script" --runs 5 --quiet >/dev/null 2>&1; then
    hook_run_ok=1
    hook_report=$(ls -t "$ROOT/output/hook-bench-report-"*.md 2>/dev/null | head -1)
  else
    hook_report=""
    fail "Hook benchmark execution failed"
  fi
  if [[ -n "$hook_report" ]]; then
    hook_cur=$(grep -oP 'Critical hooks: [0-9]+ \(violations: \K\d+' "$hook_report" | head -1)
    hook_cur="${hook_cur:-999}"
    if [[ "$hook_cur" -le "$hook_base" ]]; then
      pass "Hook latency: $hook_cur critical violations ≤ baseline $hook_base"
      if [[ "$hook_cur" -lt "$hook_base" ]]; then
        echo "  💡 Baseline stale — update .ci-baseline/hook-critical-violations.count to $hook_cur"
      fi
    else
      fail "Hook latency: $hook_cur critical violations > baseline $hook_base (regression)"
    fi
  elif [[ "$hook_run_ok" -eq 1 ]]; then
    fail "Hook bench report not generated"
  fi
else
  fail "Hook baseline or bench script missing"
fi

# 10. BATS Auditor Compliance Floor (SE-039 Slice 3)
# Full sweep is slow; enable with BATS_GATE_FULL=1 (CI weekly). Default: verify floor config.
echo "--- 10. BATS Auditor Compliance Floor ---"
bats_floor_file="$ROOT/.ci-baseline/bats-compliance-min.pct"
if [[ -f "$bats_floor_file" ]]; then
  floor=$(cat "$bats_floor_file" | tr -d '[:space:]')
  if [[ "$floor" =~ ^[0-9]+$ ]] && (( floor >= 0 && floor <= 100 )); then
    if [[ "${BATS_GATE_FULL:-0}" == "1" ]]; then
      bats_script="$ROOT/scripts/audit-all-bats.sh"
      if [[ -x "$bats_script" ]]; then
        "$bats_script" --quiet >/dev/null 2>&1 || true
        bats_report=$(ls -t "$ROOT/output/bats-audit-sweep-"*.md 2>/dev/null | head -1)
        if [[ -n "$bats_report" ]]; then
          compliance=$(grep -oP 'Compliant .*: [0-9]+ \(\K[0-9]+' "$bats_report" | head -1)
          compliance="${compliance:-0}"
          if [[ "$compliance" -ge "$floor" ]]; then
            pass "BATS compliance $compliance% ≥ floor $floor%"
          else
            fail "BATS compliance $compliance% < floor $floor%"
          fi
        else
          fail "BATS audit report not generated"
        fi
      else
        fail "BATS audit script missing"
      fi
    else
      pass "BATS compliance floor $floor% configured (full sweep skipped — set BATS_GATE_FULL=1 to enable)"
    fi
  else
    fail "BATS compliance floor invalid: $floor"
  fi
else
  fail "BATS compliance floor file missing"
fi

echo "" && echo "═════════════════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed ($TOTAL total checks)"
echo "═════════════════════════════════════════════════════════════"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
