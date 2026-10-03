#!/usr/bin/env bash
# ── Test: cost-center (Era 38 — Cost Management & Billing) ──
set -uo pipefail

PASS=0; FAIL=0; TOTAL=0
pass() { ((PASS++)); ((TOTAL++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); ((TOTAL++)); echo "  ❌ $1"; }
check() { if eval "$1" > /dev/null 2>&1; then pass "$2"; else fail "$2"; fi; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$ROOT/.opencode/commands/cost-center.md"
RULE_BM="$ROOT/docs/rules/domain/billing-model.md"
RULE_CT="$ROOT/docs/rules/domain/cost-tracking.md"
SKILL="$ROOT/.opencode/skills/cost-management/SKILL.md"

echo "═══════════════════════════════════════════"
echo "  Test: cost-center (Era 38, v2.12.1)"
echo "═══════════════════════════════════════════"
echo ""

# ── Section 1: Command file ──────────────────────────────────
echo "📋 Command (cost-center.md)"
check "test -f '$CMD'" "Command file exists"
check "[ \$(wc -l < '$CMD') -le 150 ]" "Command ≤ 150 lines"
check "grep -q '^name: cost-center' '$CMD'" "Has name in frontmatter"
check "grep -q '^description:' '$CMD'" "Has description in frontmatter"
check "grep -q 'allowed-tools:' '$CMD'" "Has allowed-tools"
check "grep -q '^model_tier:' '$CMD'" "Has model_tier field"
check "grep -q 'log' '$CMD'" "Documents log subcommand"
check "grep -q 'report' '$CMD'" "Documents report subcommand"
check "grep -q 'budget' '$CMD'" "Documents budget subcommand"
check "grep -q 'forecast' '$CMD'" "Documents forecast subcommand"
check "grep -q 'invoice' '$CMD'" "Documents invoice subcommand"
check "grep -q 'billing-model' '$CMD'" "References billing-model rule"
check "grep -q 'cost-tracking' '$CMD'" "References cost-tracking rule"

# ── Section 2: billing-model rule ────────────────────────────
echo ""
echo "📐 Rule 1 (billing-model.md)"
check "test -f '$RULE_BM'" "Rule file exists"
check "[ \$(wc -l < '$RULE_BM') -le 150 ]" "Rule ≤ 150 lines"
check "grep -q '^name: billing-model' '$RULE_BM'" "Has name in frontmatter"
check "grep -q 'Rate Table Schema' '$RULE_BM'" "Documents rate table"
check "grep -q 'Timesheet Format' '$RULE_BM'" "Documents timesheet format"
check "grep -q 'Budget Schema' '$RULE_BM'" "Documents budget schema"
check "grep -q 'Invoice Schema' '$RULE_BM'" "Documents invoice schema"
check "grep -q 'Cost KPIs' '$RULE_BM'" "Documents KPIs"
check "grep -q 'EAC' '$RULE_BM'" "Defines EAC formula"
check "grep -q 'CPI' '$RULE_BM'" "Defines CPI formula"

# ── Section 3: cost-tracking rule ────────────────────────────
echo ""
echo "📐 Rule 2 (cost-tracking.md)"
check "test -f '$RULE_CT'" "Rule file exists"
check "[ \$(wc -l < '$RULE_CT') -le 150 ]" "Rule ≤ 150 lines"
check "grep -q '^name: cost-tracking' '$RULE_CT'" "Has name in frontmatter"
check "grep -q 'Append-Only Ledger' '$RULE_CT'" "Documents ledger"
check "grep -q 'Budget Burn Calculation' '$RULE_CT'" "Defines burn calculation"
check "grep -q 'Forecast' '$RULE_CT'" "Defines forecasting"
check "grep -q 'EAC' '$RULE_CT'" "References EAC formula"
check "grep -q 'Cost Per Deliverable' '$RULE_CT'" "Defines cost per PBI"
check "grep -q 'Profitability' '$RULE_CT'" "Defines profitability analysis"

# ── Section 4: Skill ────────────────────────────────────────
echo ""
echo "🧠 Skill (cost-management/SKILL.md)"
check "test -f '$SKILL'" "Skill file exists"
check "[ \$(wc -l < '$SKILL') -le 150 ]" "Skill ≤ 150 lines"
check "grep -q '^name: cost-management' '$SKILL'" "Has name in frontmatter"
check "grep -q '^description:' '$SKILL'" "Has description in frontmatter"
check "grep -q 'context: fork' '$SKILL'" "Uses fork context"
check "grep -q 'Flujo 1' '$SKILL'" "Has Flow 1 (log)"
check "grep -q 'Flujo 2' '$SKILL'" "Has Flow 2 (report)"
check "grep -q 'Flujo 3' '$SKILL'" "Has Flow 3 (budget)"
check "grep -q 'Flujo 4' '$SKILL'" "Has Flow 4 (forecast)"
check "grep -q 'Flujo 5' '$SKILL'" "Has Flow 5 (invoice)"
check "grep -q 'Errores' '$SKILL'" "Has error handling section"
check "grep -q 'Seguridad' '$SKILL'" "Has security section"
check "grep -q 'rates' '$SKILL'" "References rates configuration"

# ── Section 5: Cross-references ──────────────────────────────
echo ""
echo "🔗 Cross-references"
check "grep -q 'billing-model' '$CMD'" "Command → billing-model"
check "grep -q 'cost-tracking' '$CMD'" "Command → cost-tracking"
check "grep -q 'billing-model' '$SKILL'" "Skill → billing-model"
check "grep -q 'cost-tracking' '$SKILL'" "Skill → cost-tracking"

# ── Section 6: Script (test file) ────────────────────────────
echo ""
echo "🧪 Script (test-cost-center.sh)"
check "test -f '$ROOT/scripts/test-cost-center.sh'" "Test script exists"
check "[ \$(wc -l < '$ROOT/scripts/test-cost-center.sh') -le 150 ]" "Test script ≤ 150 lines"
check "grep -q 'billing-model' '$ROOT/scripts/test-cost-center.sh'" "Tests billing-model rule"
check "grep -q 'cost-tracking' '$ROOT/scripts/test-cost-center.sh'" "Tests cost-tracking rule"

echo ""
echo "═══════════════════════════════════════════"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && echo "  🎉 All tests passed!" || echo "  ⚠️  Some tests failed"
exit "$FAIL"
